//+------------------------------------------------------------------+
//|  TestDeployOps.mq5 - drag-and-drop validator for D1/D2/D3.        |
//|                                                                    |
//|  Attach to ANY chart, set your webhook/token in the Inputs tab,    |
//|  and it (1) runs the Account Guardian pure-math unit tests, (2)    |
//|  writes the live trade CSV + a sample row, and (3) sends REAL test |
//|  messages for EVERY strategy family x EVERY lifecycle event, in    |
//|  BOTH signal modes, so you can eyeball exactly how each alert      |
//|  looks in Discord/Telegram before deploying. Then it removes       |
//|  itself.                                                           |
//|                                                                    |
//|  Strategy families covered (KK-Common Notifier): MasterVP          |
//|  BreakOut / MeanReversion / Impulse / XReversion, plus a KenKem    |
//|  mapping (KenKem keeps its own embed-based alert suite live; this  |
//|  shows how it renders through the unified format).                 |
//|                                                                    |
//|  Events covered: ENTRY, TP1 hit, SL -> BE, SL trailed, SL (loss),  |
//|  SL+ (break-even+), TP2 (full TP).                                 |
//|                                                                    |
//|  Run on a DEMO chart BEFORE deploying. WebRequest must be allowed  |
//|  (Tools > Options > Expert Advisors) and Email SMTP set for those  |
//|  channels to pass. If no inputs dialog appears on drag, DOUBLE-    |
//|  CLICK the EA in the Navigator instead.                            |
//+------------------------------------------------------------------+
#property copyright "KenKem / dquants"
#property version   "1.10"
#property strict
#property description "Validates D1 Account Guardian math + D2 trade CSV + D3 alerts + D4 signal-compliance (not financial advice)"

#include "../KK-Common/AccountGuardian.mqh"
#include "../KK-Common/TradeLogger.mqh"
#include "../KK-Common/Notifier.mqh"

input group "===== What to run ====="
input bool   RUN_GUARDIAN_MATH = true;   // D1: run Account Guardian pure-math unit tests
input bool   RUN_NOTIFY_TEST   = true;   // D3: send REAL test messages to the channels below
input bool   RUN_CSV_TEST      = true;   // D2: create the live trade CSV + write a sample row
input bool   RUN_COMPLIANCE_TEST = true; // D4: assert signal text reads as a bot log, NOT financial advice (offline)

input group "===== Notification channels (D3; same as the EA) ====="
input bool   InpAutoChannelFromCreds = true; // auto-route showcase to whichever creds you filled (Telegram and/or Discord), overriding InpNotifyChannel
input int    InpNotifyChannel     = 2;   // 0 None 1 Email 2 Discord 3 Telegram 4 E+D 5 E+T 6 D+T 7 All (used when auto is OFF / no creds)
input int    InpNotifyMode        = 2;   // 1 Full (developers), 2 Simplified (default for users)
input bool   InpSendBothModes     = true;// also send the event showcase in the OTHER mode (see both styles)
input int    InpSendGapMs         = 700; // pause between messages (ms) - avoids Discord/Telegram rate limits
input string InpDiscordWebhookUrl = "";  // Discord webhook URL
input string InpTelegramBotToken  = "";  // Telegram bot token
input string InpTelegramChatId    = "";  // Telegram chat ID (group IDs are negative)

int g_pass=0, g_fail=0, g_sent=0;

void Check(bool cond,string name)
{
   if(cond){ g_pass++; Print("PASS: ",name); }
   else    { g_fail++; Print("FAIL: ",name); }
}

// Map (email, discord, telegram) presence flags -> the KKN_Channel enum value.
int ChannelFromFlags(bool e,bool d,bool t)
{
   if(e&&d&&t) return KKN_ALL_THREE;
   if(d&&t)    return KKN_DISC_TG;
   if(e&&t)    return KKN_EMAIL_TG;
   if(e&&d)    return KKN_EMAIL_DISC;
   if(t)       return KKN_TELEGRAM;
   if(d)       return KKN_DISCORD;
   if(e)       return KKN_EMAIL;
   return KKN_NONE;
}

// Resolve which channel the showcase should actually use. When auto is on and any
// webhook/token creds are filled, route to exactly those channels (so "I only set
// Telegram" sends the whole showcase to Telegram), preserving an Email selection
// from InpNotifyChannel if one was made. Otherwise fall back to InpNotifyChannel.
int ResolveShowcaseChannel()
{
   bool hasD=(InpDiscordWebhookUrl!="");
   bool hasT=(InpTelegramBotToken!="" && InpTelegramChatId!="");
   if(!InpAutoChannelFromCreds || (!hasD && !hasT)) return InpNotifyChannel;

   bool wantEmail=(InpNotifyChannel==KKN_EMAIL||InpNotifyChannel==KKN_EMAIL_DISC||
                   InpNotifyChannel==KKN_EMAIL_TG||InpNotifyChannel==KKN_ALL_THREE);
   return ChannelFromFlags(wantEmail,hasD,hasT);
}

// Case-insensitive substring search (for content compliance scans).
bool ContainsCI(string haystack,string needle)
{
   string h=haystack, n=needle;
   StringToLower(h); StringToLower(n);
   return (StringFind(h,n)>=0);
}

//+------------------------------------------------------------------+
//| D1 - Account Guardian pure-math unit tests (no MT5 state needed)  |
//+------------------------------------------------------------------+
void TestGuardianMath()
{
   Print("--- D1 Account Guardian math ---");
   Check(MathAbs(KKG_TriggerLoss(100000,4.0,0.5)-3500.0)<1e-6, "TriggerLoss 4.0/0.5 of 100k = 3500");
   Check(MathAbs(KKG_TriggerLoss(100000,8.0,0.5)-7500.0)<1e-6, "TriggerLoss 8.0/0.5 of 100k = 7500");
   Check(MathAbs(KKG_TriggerLoss(100000,4.0,5.0)-0.0)<1e-6,    "TriggerLoss buffer>=limit clamps to 0");
   Check( KKG_DailyBreached(96499.0,100000,4.0,0.5), "Daily breach at eq 96499 (<=96500) = true");
   Check(!KKG_DailyBreached(96600.0,100000,4.0,0.5), "Daily safe   at eq 96600 (>96500)  = false");
   Check(!KKG_DailyBreached(99999.0,100000,0.0,0.5), "Daily disabled (limit 0) = false");
   Check( KKG_OverallBreached(92499.0,100000,8.0,0.5), "Overall breach at eq 92499 = true");
   Check(!KKG_OverallBreached(92600.0,100000,8.0,0.5), "Overall safe   at eq 92600 = false");
   Check( KKG_DailyBreached(99999.0,100000,4.0,5.0), "Daily breach immediate when buffer>=limit");
   Check(KKG_DayKey(StringToTime("2026.06.25 14:30:00"))==20260625, "DayKey 2026.06.25 = 20260625");
}

//+------------------------------------------------------------------+
//| D3 helpers - drive the unified Notifier through every event shape |
//+------------------------------------------------------------------+
// One full position lifecycle for a given strategy/side, closing via closeEv
// (KKN_EV_SL | KKN_EV_SLPLUS | KKN_EV_TP2). Representative XAU-style levels.
void Lifecycle(KKNotifier &nf,string reason,bool isLong,int closeEv)
{
   double entry=1234.56, sl=1230.00, tp1=1250.00, tp2=1270.00, lot=0.10;
   double be   =isLong? 1234.66 : 1234.46;
   double trail=isLong? 1255.00 : 1214.00;
   double net  =(closeEv==KKN_EV_TP2)?120.00:((closeEv==KKN_EV_SLPLUS)?2.00:-45.00);

   nf.Emit(KKN_EV_OPEN ,isLong,lot,entry,sl,tp1,tp2,0,0,reason); Sleep(InpSendGapMs);
   nf.Emit(KKN_EV_TP1  ,isLong,0,0,0,0,0,tp1,0,reason);          Sleep(InpSendGapMs);
   nf.Emit(KKN_EV_BE   ,isLong,0,0,0,0,0,be,0,reason);           Sleep(InpSendGapMs);
   nf.Emit(KKN_EV_TRAIL,isLong,0,0,0,0,0,trail,0,reason);        Sleep(InpSendGapMs);
   nf.Emit(closeEv     ,isLong,0,0,0,0,0,0,net,reason);          Sleep(InpSendGapMs);
   g_sent+=5;
}

// Just the entry + close (for strategy-NAME coverage without re-sending every shape).
void OpenClose(KKNotifier &nf,string reason,bool isLong,int closeEv)
{
   double net=(closeEv==KKN_EV_TP2)?120.00:((closeEv==KKN_EV_SLPLUS)?2.00:-45.00);
   nf.Emit(KKN_EV_OPEN,isLong,0.10,1234.56,1230.00,1250.00,1270.00,0,0,reason); Sleep(InpSendGapMs);
   nf.Emit(closeEv    ,isLong,0,0,0,0,0,0,net,reason);                          Sleep(InpSendGapMs);
   g_sent+=2;
}

//+------------------------------------------------------------------+
//| D3 - send real test messages: all strategies x all events x modes |
//+------------------------------------------------------------------+
void TestNotifications()
{
   Print("--- D3 Notifications (sending REAL messages) ---");

   // (a) Reachability probes - one direct send per channel, PASS/FAIL counted.
   long login=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   string stamp=TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS);
   string probe="[KK-TEST] D1-D3 validator on "+_Symbol+" acct "+IntegerToString(login)+" @ "+stamp;
   if(InpDiscordWebhookUrl!="")
      Check(KKN_SendDiscord(InpDiscordWebhookUrl,probe), "Discord reachable (check your channel)");
   else Print("SKIP: Discord (no webhook set)");
   if(InpTelegramBotToken!="" && InpTelegramChatId!="")
      Check(KKN_SendTelegram(InpTelegramBotToken,InpTelegramChatId,probe), "Telegram reachable (check your chat)");
   else Print("SKIP: Telegram (no token/chatId set)");

   int showChannel=ResolveShowcaseChannel();
   if(showChannel==KKN_NONE){ Print("Channel=None -> showcase skipped (fill Telegram and/or Discord creds)."); return; }
   if(showChannel!=InpNotifyChannel)
      Print("  > Auto-routing showcase to channel ",showChannel," (derived from the creds you filled).");

   // (b) Event-SHAPE showcase: MasterVP BreakOut full lifecycle, in BOTH modes
   //     so you can compare Full vs Simplified for every event.
   int modes[2]; int nModes=1; modes[0]=InpNotifyMode;
   if(InpSendBothModes){ modes[1]=(InpNotifyMode==KKN_MODE_FULL?KKN_MODE_SIMPLIFIED:KKN_MODE_FULL); nModes=2; }

   for(int m=0;m<nModes;m++)
   {
      string tag=(modes[m]==KKN_MODE_FULL)?"FULL (developers)":"SIMPLIFIED (users)";
      Print("  > Event showcase in ",tag," mode ...");
      KKNotifier nf;
      nf.Init(showChannel,modes[m],InpDiscordWebhookUrl,InpTelegramBotToken,InpTelegramChatId,
              "MasterVP",14111850);
      Lifecycle(nf,"L-BRK",true,KKN_EV_TP2);   // long breakout, full take-profit
   }

   // (c) Strategy-NAME coverage: remaining MasterVP families + a KenKem mapping,
   //     in the default/primary mode. Close types vary so SL / SL+ / TP2 all show.
   Print("  > Strategy-name coverage in primary mode (",
         (InpNotifyMode==KKN_MODE_FULL?"Full":"Simplified"),") ...");
   KKNotifier mvp;
   mvp.Init(showChannel,InpNotifyMode,InpDiscordWebhookUrl,InpTelegramBotToken,InpTelegramChatId,
            "MasterVP",14111850);
   OpenClose(mvp,"S-REV", false,KKN_EV_SL);     // MeanReversion (short, stopped out)
   OpenClose(mvp,"L-IMP", true ,KKN_EV_SLPLUS); // Impulse (long, break-even+)
   OpenClose(mvp,"S-XREV",false,KKN_EV_TP2);    // XReversion (short, full TP)

   KKNotifier kk;
   kk.Init(showChannel,InpNotifyMode,InpDiscordWebhookUrl,InpTelegramBotToken,InpTelegramChatId,
           "KenKem",770001);
   OpenClose(kk,"L-E1",true,KKN_EV_SL);         // KenKem E1 mapping (long, stopped out)

   Print("Sent ",g_sent," showcase messages on channel ",showChannel," - confirm they arrived.");
}

//+------------------------------------------------------------------+
//| D4 - signal CONTENT compliance: every broadcast message must read |
//| as an automated record of what the EA did, NOT financial advice.  |
//| Pure/offline (uses KKNotifier::Preview, no WebRequest) so it runs  |
//| anywhere, including Tester. Asserts, for every lifecycle event:    |
//|   - the "not financial advice" disclaimer is present (both modes)  |
//|   - no advice/recommendation phrasing leaks in (both modes)        |
//|   - SIMPLIFIED (the user-facing mode) exposes NO exact entry/SL/TP |
//|     levels or P&L, so it can't look like a signal-service tip.     |
//+------------------------------------------------------------------+
void TestSignalCompliance()
{
   Print("--- D4 Signal compliance (not financial advice) ---");

   // Advice/recommendation red-flags (case-insensitive). Deliberately does NOT
   // include "advice"/"financial advice" - our disclaimer legitimately says
   // "not financial advice" and must not trip its own check.
   string banned[]={"recommend","guarantee","you should","you must","buy now",
                    "sell now","act now","risk-free","risk free","sure profit",
                    "can't lose","cannot lose","signal to buy","signal to sell",
                    "should buy","should sell","must buy","must sell"};

   // All seven lifecycle events, exercised long-side with representative levels.
   int evs[7]={KKN_EV_OPEN,KKN_EV_TP1,KKN_EV_BE,KKN_EV_TRAIL,KKN_EV_SL,KKN_EV_SLPLUS,KKN_EV_TP2};

   KKNotifier nf;
   nf.Init(KKN_TELEGRAM,KKN_MODE_SIMPLIFIED,"","","","MasterVP",14111850);

   // ---- SIMPLIFIED: the default, user-facing / marketplace-safe mode ----
   for(int i=0;i<7;i++)
   {
      string msg=nf.Preview(evs[i],true,0.10,1234.56,1230.00,1250.00,1270.00,1250.00,120.00,"L-BRK");
      string tag="SIMPLIFIED ev"+IntegerToString(evs[i]);

      Check(ContainsCI(msg,"not financial advice"), tag+": carries disclaimer");

      bool clean=true;
      for(int b=0;b<ArraySize(banned);b++)
         if(ContainsCI(msg,banned[b])){ clean=false; Print("   advice phrase '",banned[b],"' in: ",msg); }
      Check(clean, tag+": no advice phrasing");

      // No actionable levels for users: no Entry/SL/TP labels, no " @ price", no " net pnl".
      bool noLevels=(StringFind(msg,"Entry:")<0 && StringFind(msg,"SL:")<0 &&
                     StringFind(msg,"TP1:")<0  && StringFind(msg,"TP2:")<0 &&
                     StringFind(msg," @ ")<0   && StringFind(msg," net ")<0);
      Check(noLevels, tag+": no exact entry/SL/TP/PnL levels exposed");
   }

   // ---- FULL: developer mode shows levels, but still must not read as advice ----
   nf.SetMode(KKN_MODE_FULL);
   for(int i=0;i<7;i++)
   {
      string msg=nf.Preview(evs[i],true,0.10,1234.56,1230.00,1250.00,1270.00,1250.00,120.00,"L-BRK");
      string tag="FULL ev"+IntegerToString(evs[i]);

      Check(ContainsCI(msg,"not financial advice"), tag+": carries disclaimer");

      bool clean=true;
      for(int b=0;b<ArraySize(banned);b++)
         if(ContainsCI(msg,banned[b])) clean=false;
      Check(clean, tag+": no advice phrasing");
   }

   // Eyeball samples (entry shape in both modes).
   nf.SetMode(KKN_MODE_SIMPLIFIED);
   Print("  sample SIMPLIFIED entry: ",
         nf.Preview(KKN_EV_OPEN,true,0.10,1234.56,1230.00,1250.00,1270.00,0,0,"L-BRK"));
   nf.SetMode(KKN_MODE_FULL);
   Print("  sample FULL entry:       ",
         nf.Preview(KKN_EV_OPEN,true,0.10,1234.56,1230.00,1250.00,1270.00,0,0,"L-BRK"));
}

//+------------------------------------------------------------------+
//| D2 - create the live trade CSV + write a sample row               |
//+------------------------------------------------------------------+
void TestTradeCsv()
{
   Print("--- D2 Live trade CSV ---");
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
   { Print("SKIP: CSV is live-only (running in Tester)"); return; }

   long login=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   string fn="KKTrades_TEST_"+_Symbol+"_"+IntegerToString(login)+".csv";
   int h=FileOpen(fn,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(h==INVALID_HANDLE){ Check(false,"open live CSV "+fn); return; }
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),"KK-TEST",_Symbol,
             "0","buy","0.10","0.00000","0.00","0.00","0.00","0.00","sample-row",
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));
   FileFlush(h); FileClose(h);
   Check(FileIsExist(fn),"live CSV written: "+fn+" (MQL5/Files)");
}

//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("KK Deploy-Ops validator (D1/D2/D3)");
   Print("========================================");

   if(RUN_GUARDIAN_MATH)   TestGuardianMath();     else Print("[SKIP] D1 guardian math");
   if(RUN_COMPLIANCE_TEST) TestSignalCompliance(); else Print("[SKIP] D4 signal compliance");
   if(RUN_CSV_TEST)        TestTradeCsv();         else Print("[SKIP] D2 CSV");
   if(RUN_NOTIFY_TEST)     TestNotifications();    else Print("[SKIP] D3 notifications");

   Print("========================================");
   PrintFormat("RESULT: %d passed, %d failed, %d showcase messages sent", g_pass, g_fail, g_sent);
   Print(g_fail==0 ? "ALL CHECKS PASSED" : "SOME CHECKS FAILED - see log above");
   Print("Note: a reachable PASS means HTTP/SMTP accepted the probe; still");
   Print("confirm the showcase messages actually arrived in Discord/Telegram/inbox,");
   Print("and that each strategy name + event label reads correctly.");
   Print("========================================");

   ExpertRemove();   // one-shot: remove after the run
   return INIT_SUCCEEDED;
}

void OnTick(){}
//+------------------------------------------------------------------+
