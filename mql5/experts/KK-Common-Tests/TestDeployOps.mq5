//+------------------------------------------------------------------+
//|  TestDeployOps.mq5 - drag-and-drop validator for D1/D2/D3.        |
//|                                                                    |
//|  Like the KenKemExpert Discord test EA: attach to ANY chart, set   |
//|  your webhook/token, and it (1) runs the Account Guardian pure-    |
//|  math unit tests headlessly (PASS/FAIL in the Experts log), (2)    |
//|  sends a REAL test message to each configured channel so you can   |
//|  confirm Discord/Telegram/Email are reachable, and (3) creates the |
//|  live trade CSV + writes a sample row. Then it removes itself.     |
//|                                                                    |
//|  Run this on a DEMO chart BEFORE deploying KK-MasterVP. WebRequest |
//|  must be allowed (Tools > Options > Expert Advisors) and Email SMTP|
//|  set (Tools > Options > Email) for those channels to pass.         |
//+------------------------------------------------------------------+
#property copyright "KenKem / dquants"
#property version   "1.00"
#property strict
#property description "Validates D1 Account Guardian math + D2 trade CSV + D3 Discord/Telegram/Email before deployment"

#include "../KK-Common/AccountGuardian.mqh"
#include "../KK-Common/TradeLogger.mqh"
#include "../KK-Common/Notifier.mqh"

input group "===== What to run ====="
input bool   RUN_GUARDIAN_MATH = true;   // D1: run Account Guardian pure-math unit tests
input bool   RUN_NOTIFY_TEST   = true;   // D3: send a REAL test message to the channels below
input bool   RUN_CSV_TEST      = true;   // D2: create the live trade CSV + write a sample row

input group "===== Notification channels (D3; same as the EA) ====="
input int    InpNotifyChannel     = 2;   // 0 None 1 Email 2 Discord 3 Telegram 4 E+D 5 E+T 6 D+T 7 All
input int    InpNotifyMode        = 1;   // 1 Full, 2 Simplified
input string InpDiscordWebhookUrl = "";  // Discord webhook URL
input string InpTelegramBotToken  = "";  // Telegram bot token
input string InpTelegramChatId    = "";  // Telegram chat ID (group IDs are negative)

int g_pass=0, g_fail=0;

void Check(bool cond,string name)
{
   if(cond){ g_pass++; Print("PASS: ",name); }
   else    { g_fail++; Print("FAIL: ",name); }
}

//+------------------------------------------------------------------+
//| D1 - Account Guardian pure-math unit tests (no MT5 state needed)  |
//+------------------------------------------------------------------+
void TestGuardianMath()
{
   Print("--- D1 Account Guardian math ---");
   // Trigger loss = (limit - buffer)% of the anchor.
   Check(MathAbs(KKG_TriggerLoss(100000,4.0,0.5)-3500.0)<1e-6, "TriggerLoss 4.0/0.5 of 100k = 3500");
   Check(MathAbs(KKG_TriggerLoss(100000,8.0,0.5)-7500.0)<1e-6, "TriggerLoss 8.0/0.5 of 100k = 7500");
   // Buffer >= limit clamps to act immediately (trigger 0).
   Check(MathAbs(KKG_TriggerLoss(100000,4.0,5.0)-0.0)<1e-6,    "TriggerLoss buffer>=limit clamps to 0");

   // Daily breach: act when equity <= anchor - trigger (96500 for 4.0/0.5 of 100k).
   Check( KKG_DailyBreached(96499.0,100000,4.0,0.5), "Daily breach at eq 96499 (<=96500) = true");
   Check(!KKG_DailyBreached(96600.0,100000,4.0,0.5), "Daily safe   at eq 96600 (>96500)  = false");
   Check(!KKG_DailyBreached(99999.0,100000,0.0,0.5), "Daily disabled (limit 0) = false");

   // Overall/max-DD breach: trigger 7500 for 8.0/0.5 of 100k -> act at eq<=92500.
   Check( KKG_OverallBreached(92499.0,100000,8.0,0.5), "Overall breach at eq 92499 = true");
   Check(!KKG_OverallBreached(92600.0,100000,8.0,0.5), "Overall safe   at eq 92600 = false");

   // Buffer-immediate: trigger 0 -> any loss breaches.
   Check( KKG_DailyBreached(99999.0,100000,4.0,5.0), "Daily breach immediate when buffer>=limit");

   // Day key (yyyymmdd) from a server datetime.
   Check(KKG_DayKey(StringToTime("2026.06.25 14:30:00"))==20260625, "DayKey 2026.06.25 = 20260625");
}

//+------------------------------------------------------------------+
//| D3 - send a real test message to each configured channel          |
//+------------------------------------------------------------------+
void TestNotifications()
{
   Print("--- D3 Notifications (sending REAL messages) ---");
   long login=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   string stamp=TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS);
   string line="[KK-TEST] D1-D3 validator on "+_Symbol+" acct "+IntegerToString(login)+" @ "+stamp;

   // Direct low-level sends (so each channel reports independently).
   if(InpDiscordWebhookUrl!="")
      Check(KKN_SendDiscord(InpDiscordWebhookUrl,line),   "Discord send (check your channel)");
   else Print("SKIP: Discord (no webhook set)");

   if(InpTelegramBotToken!="" && InpTelegramChatId!="")
      Check(KKN_SendTelegram(InpTelegramBotToken,InpTelegramChatId,line), "Telegram send (check your chat)");
   else Print("SKIP: Telegram (no token/chatId set)");

   // Router test (uses the channel/mode exactly as the EA would).
   KKNotifier nf;
   nf.Init(InpNotifyChannel,InpNotifyMode,InpDiscordWebhookUrl,InpTelegramBotToken,InpTelegramChatId,"KK-TEST");
   nf.TradeOpen(true,0.10,1234.56,1230.00,1250.00,"BRK-TEST");
   nf.TradeClose(42.0,42.0,"tp");
   nf.AlertMsg("guardian HALT self-test");
   Print("Router fired TradeOpen/TradeClose/Alert on channel ",InpNotifyChannel," (check the destination).");
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

   if(RUN_GUARDIAN_MATH) TestGuardianMath(); else Print("[SKIP] D1 guardian math");
   if(RUN_CSV_TEST)      TestTradeCsv();     else Print("[SKIP] D2 CSV");
   if(RUN_NOTIFY_TEST)   TestNotifications();else Print("[SKIP] D3 notifications");

   Print("========================================");
   PrintFormat("RESULT: %d passed, %d failed", g_pass, g_fail);
   Print(g_fail==0 ? "ALL CHECKS PASSED" : "SOME CHECKS FAILED - see log above");
   Print("Note: notification 'send' PASS means HTTP/SMTP accepted it; still");
   Print("confirm the message actually arrived in your Discord/Telegram/inbox.");
   Print("========================================");

   ExpertRemove();   // one-shot: remove after the run
   return INIT_SUCCEEDED;
}

void OnTick(){}
//+------------------------------------------------------------------+
