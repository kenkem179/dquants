//+------------------------------------------------------------------+
//|  KK-Common/Notifier.mqh                                           |
//|  D3 - Shared notifications for KK-MasterVP.                        |
//|                                                                    |
//|  KK-KenKem keeps its own (richer, embed-based) alert suite - this  |
//|  is the small standalone helper that reuses the proven WebRequest  |
//|  call shapes WITHOUT copy-pasting KenKem's Trade-struct-coupled    |
//|  files. Discord webhook + Telegram token/chatId + Email/SendMail.  |
//|                                                                    |
//|  Signal style (2026-06 redesign):                                  |
//|   FULL (developers only) - shows exact levels:                     |
//|     XAUUSD BUY 0.10 lots #12345 | Entry: 1234.56 | SL: 1230.00 |   |
//|       TP1: 1250.00 | TP2: 1270.00 | Strategy: MasterVP-BreakOut    |
//|   SIMPLIFIED (default - prop/marketplace safe, no signal-service   |
//|   look, NO exact prices):                                          |
//|     XAUUSD BUY 0.10 lots #12345 | Strategy: MasterVP-BreakOut      |
//|                                                                    |
//|  Lifecycle events (same style, both modes):                        |
//|     ENTRY, TP1 hit, SL -> BE, SL trailed, SL hit (loss),           |
//|     SL+ (break-even+), TP2 (full TP).                              |
//|                                                                    |
//|  Operational notes (see the EA user guide):                        |
//|   - WebRequest needs api.telegram.org + discord.com whitelisted    |
//|     in Tools > Options > Expert Advisors > Allow WebRequest.       |
//|   - Email needs SMTP set in Tools > Options > Email.               |
//|   - WebRequest / SendMail are BLOCKED in Tester/Optimization - the |
//|     senders self-guard so backtests never spam or stall.           |
//|                                                                    |
//|  All source text is ASCII (MQL5 Market NON_LATIN rule).            |
//+------------------------------------------------------------------+
#ifndef KK_NOTIFIER_MQH
#define KK_NOTIFIER_MQH

// ---- channel enum (matches the InpNotifyChannel input) ----
enum KKN_Channel
{
   KKN_NONE       = 0,
   KKN_EMAIL      = 1,
   KKN_DISCORD    = 2,
   KKN_TELEGRAM   = 3,
   KKN_EMAIL_DISC = 4,   // Email + Discord
   KKN_EMAIL_TG   = 5,   // Email + Telegram
   KKN_DISC_TG    = 6,   // Discord + Telegram
   KKN_ALL_THREE  = 7    // Email + Discord + Telegram
};

enum KKN_Mode
{
   KKN_MODE_FULL       = 1,   // full detail (entry/SL/TP1/TP2/net) - developers
   KKN_MODE_SIMPLIFIED = 2    // prop-safe: symbol + side + lots + magic + strategy
};

// ---- trade lifecycle events (drive one shared formatter) ----
enum KKN_Event
{
   KKN_EV_OPEN  = 0,   // ENTRY
   KKN_EV_TP1   = 1,   // TP1 hit (first partial)
   KKN_EV_BE    = 2,   // SL -> BE (stop moved to break-even)
   KKN_EV_TRAIL = 3,   // SL trailed (throttled by caller)
   KKN_EV_SL    = 4,   // SL hit (loss)
   KKN_EV_SLPLUS= 5,   // SL+ (closed at break-even+, small win)
   KKN_EV_TP2   = 6    // TP2 (full TP)
};

// Compliance disclaimer appended to every broadcast trade message. These are a
// record of what the EA DID on the account, never a recommendation - make that
// explicit so a signal can never read as financial advice. ASCII only (MQL5
// Market NON_LATIN rule).
const string KKN_DISCLAIMER=" | Automated bot logs, not financial advice.";

// ===================================================================
//  Strategy display name: EA tag + family parsed from the reason tag.
//  reason tags: L-/S- prefix + family. ORDER MATTERS ("XREV" contains
//  "REV", so test XREV before REV). KenKem entries are E1..E5.
// ===================================================================
string KKN_FamilyName(string reason)
{
   if(StringFind(reason,"XREV")>=0) return "XReversion";
   if(StringFind(reason,"IMP")>=0)  return "Impulse";
   if(StringFind(reason,"REV")>=0)  return "MeanReversion";
   if(StringFind(reason,"BRK")>=0)  return "BreakOut";
   if(StringFind(reason,"E1")>=0)   return "E1";
   if(StringFind(reason,"E2")>=0)   return "E2";
   if(StringFind(reason,"E3")>=0)   return "E3";
   if(StringFind(reason,"E4")>=0)   return "E4";
   if(StringFind(reason,"E5")>=0)   return "E5";
   return (reason=="" ? "Signal" : reason);
}

// ===================================================================
//  Low-level senders - tester-guarded, return true on success.
// ===================================================================
bool KKN_TesterSkip(){ return MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION); }

// JSON string-escape (Discord content): backslash, quote, control chars.
string KKN_JsonEscape(string s)
{
   string out=""; int n=StringLen(s);
   for(int i=0;i<n;i++)
   {
      ushort c=StringGetCharacter(s,i);
      if(c=='\\')      out+="\\\\";
      else if(c=='"')  out+="\\\"";
      else if(c=='\n') out+="\\n";
      else if(c=='\r') out+="";
      else if(c=='\t') out+="\\t";
      else             out+=ShortToString(c);
   }
   return out;
}

// URL-encode for Telegram (UTF-8 byte level; safe for any text).
string KKN_UrlEncode(string text)
{
   uchar utf8[]; int bytes=StringToCharArray(text,utf8,0,WHOLE_ARRAY,CP_UTF8);
   if(bytes<=0) return "";
   string r="";
   for(int i=0;i<bytes-1;i++)   // -1 skips the null terminator
   {
      uchar b=utf8[i];
      if((b>='A'&&b<='Z')||(b>='a'&&b<='z')||(b>='0'&&b<='9')||b=='-'||b=='_'||b=='.'||b=='~')
         r+=CharToString(b);
      else
         r+=StringFormat("%%%02X",b);
   }
   return r;
}

bool KKN_SendDiscord(string webhookUrl,string content)
{
   if(KKN_TesterSkip() || webhookUrl=="") return false;
   string json="{\"content\":\""+KKN_JsonEscape(content)+"\"}";
   string headers="Content-Type: application/json\r\n";
   string resHeaders="";
   char post[],result[];
   StringToCharArray(json,post,0,StringLen(json),CP_UTF8);
   int res=WebRequest("POST",webhookUrl,headers,5000,post,result,resHeaders);
   if(res==-1)
   {
      Print("[KKNotifier] Discord WebRequest err=",GetLastError(),
            " - whitelist https://discord.com in Tools>Options>Expert Advisors>Allow WebRequest");
      return false;
   }
   if(res==200 || res==204) return true;
   Print("[KKNotifier] Discord HTTP=",res," body=",CharArrayToString(result,0,-1,CP_UTF8));
   return false;
}

bool KKN_SendTelegram(string botToken,string chatId,string text)
{
   if(KKN_TesterSkip() || botToken=="" || chatId=="") return false;
   string url="https://api.telegram.org/bot"+botToken+"/sendMessage";
   string headers="Content-Type: application/x-www-form-urlencoded\r\n";
   string resHeaders="";
   string postData="chat_id="+chatId+"&text="+KKN_UrlEncode(text);
   char post[],result[];
   StringToCharArray(postData,post,0,StringLen(postData),CP_UTF8);
   int res=WebRequest("POST",url,headers,5000,post,result,resHeaders);
   if(res==-1)
   {
      Print("[KKNotifier] Telegram WebRequest err=",GetLastError(),
            " - whitelist https://api.telegram.org in Tools>Options>Expert Advisors>Allow WebRequest");
      return false;
   }
   string resp=CharArrayToString(result,0,-1,CP_UTF8);
   if(res==200 && StringFind(resp,"\"ok\":true")>=0) return true;
   Print("[KKNotifier] Telegram HTTP=",res," body=",resp);
   return false;
}

bool KKN_SendEmail(string subject,string body)
{
   if(KKN_TesterSkip()) return false;
   if(!TerminalInfoInteger(TERMINAL_EMAIL_ENABLED))
   {
      Print("[KKNotifier] Email disabled - set SMTP in Tools>Options>Email");
      return false;
   }
   return SendMail(subject,body);
}

// ===================================================================
//  Router - drives all configured channels from one Send().
// ===================================================================
class KKNotifier
{
private:
   int    m_channel;
   int    m_mode;
   long   m_magic;
   string m_discord,m_tgToken,m_tgChat,m_eaTag;

   bool DiscOn(){ return m_channel==KKN_DISCORD||m_channel==KKN_EMAIL_DISC||m_channel==KKN_DISC_TG||m_channel==KKN_ALL_THREE; }
   bool TgOn()  { return m_channel==KKN_TELEGRAM||m_channel==KKN_EMAIL_TG||m_channel==KKN_DISC_TG||m_channel==KKN_ALL_THREE; }
   bool MailOn(){ return m_channel==KKN_EMAIL||m_channel==KKN_EMAIL_DISC||m_channel==KKN_EMAIL_TG||m_channel==KKN_ALL_THREE; }

   string P(double v){ return DoubleToString(v,_Digits); }       // price
   string M(double v){ return (v>=0?"+":"")+DoubleToString(v,2); } // signed money

   string Strategy(string reason){ return m_eaTag+"-"+KKN_FamilyName(reason); }

   // Short label for each lifecycle event.
   string EventLabel(int ev)
   {
      switch(ev)
      {
         case KKN_EV_TP1:    return "TP1 hit";
         case KKN_EV_BE:     return "SL to BE";
         case KKN_EV_TRAIL:  return "SL trailed";   // side-neutral (up for longs, down for shorts)
         case KKN_EV_SL:     return "SL hit (loss)";
         case KKN_EV_SLPLUS: return "SL+ (BE hit)";
         case KKN_EV_TP2:    return "TP2 (full TP)";
         default:            return "ENTRY";
      }
   }

   // ONE formatter for every event in both modes. `price` is the event-
   // relevant level (TP1/BE/trail), `net` the realized money (closes).
   string Build(int ev,bool isLong,double lot,double entry,double sl,
                double tp1,double tp2,double price,double net,string reason)
   {
      string side  =isLong?"BUY":"SELL";
      string strat =Strategy(reason);
      string mg    ="#"+IntegerToString(m_magic);
      string line;

      if(ev==KKN_EV_OPEN)
      {
         string head=StringFormat("%s %s %.2f lots %s",_Symbol,side,lot,mg);
         if(m_mode==KKN_MODE_SIMPLIFIED)
            line=head+" | Strategy: "+strat;
         else
            line=head+" | Entry: "+P(entry)+" | SL: "+P(sl)+
                 " | TP1: "+P(tp1)+" | TP2: "+P(tp2)+" | Strategy: "+strat;
      }
      else
      {
         // follow-up events
         string head=StringFormat("%s %s %s",_Symbol,side,mg);
         string label=EventLabel(ev);
         if(m_mode==KKN_MODE_SIMPLIFIED)
            line=head+" | "+label+" | Strategy: "+strat;
         else
         {
            // full mode: attach the relevant level / net
            string detail="";
            if(ev==KKN_EV_TP1 || ev==KKN_EV_BE || ev==KKN_EV_TRAIL) detail=" @ "+P(price);
            else                                                    detail=" net "+M(net);   // SL / SL+ / TP2
            line=head+" | "+label+detail+" | Strategy: "+strat;
         }
      }

      return line+KKN_DISCLAIMER;   // compliance: tag every signal as a bot log
   }

public:
   KKNotifier(){ m_channel=KKN_NONE; m_mode=KKN_MODE_FULL; m_magic=0; }

   void Init(int channel,int mode,string discord,string tgToken,string tgChat,string eaTag,long magic=0)
   {
      m_channel=channel; m_mode=mode; m_magic=magic;
      m_discord=discord; m_tgToken=tgToken; m_tgChat=tgChat; m_eaTag=eaTag;
   }
   void SetMagic(long magic){ m_magic=magic; }
   void SetMode(int mode){ m_mode=mode; }

   bool Enabled(){ return m_channel!=KKN_NONE; }

   // Offline formatter accessor: returns the EXACT line that would be broadcast
   // for this event/mode WITHOUT sending. Used by the deploy-ops compliance test
   // to assert message content (no advice phrasing / no leaked levels for users).
   string Preview(int ev,bool isLong,double lot,double entry,double sl,
                  double tp1,double tp2,double price,double net,string reason)
   { return Build(ev,isLong,lot,entry,sl,tp1,tp2,price,net,reason); }

   // Route one line to every configured channel. subject is for Email only.
   void Send(string subject,string line)
   {
      if(m_channel==KKN_NONE) return;
      if(DiscOn()) KKN_SendDiscord(m_discord,line);
      if(TgOn())   KKN_SendTelegram(m_tgToken,m_tgChat,line);
      if(MailOn()) KKN_SendEmail(subject,line);
   }

   void Startup()
   {
      if(m_channel==KKN_NONE) return;
      long login=(long)AccountInfoInteger(ACCOUNT_LOGIN);
      Send(m_eaTag+" started",
           "["+m_eaTag+"] started on "+_Symbol+" acct "+IntegerToString(login));
   }

   // ---- lifecycle emitters (one per event, all route through Build) ----
   void TradeOpen(bool isLong,double lot,double entry,double sl,double tp1,double tp2,string reason)
   {
      if(m_channel==KKN_NONE) return;
      string line=Build(KKN_EV_OPEN,isLong,lot,entry,sl,tp1,tp2,0,0,reason);
      Send(m_eaTag+" "+(isLong?"BUY":"SELL")+" "+_Symbol,line);
   }
   void Tp1Hit(bool isLong,double price,string reason)
   {
      if(m_channel==KKN_NONE) return;
      Send(m_eaTag+" TP1 "+_Symbol,Build(KKN_EV_TP1,isLong,0,0,0,0,0,price,0,reason));
   }
   void SlToBe(bool isLong,double bePrice,string reason)
   {
      if(m_channel==KKN_NONE) return;
      Send(m_eaTag+" SL->BE "+_Symbol,Build(KKN_EV_BE,isLong,0,0,0,0,0,bePrice,0,reason));
   }
   void SlTrailed(bool isLong,double newSl,string reason)
   {
      if(m_channel==KKN_NONE) return;
      Send(m_eaTag+" trail "+_Symbol,Build(KKN_EV_TRAIL,isLong,0,0,0,0,0,newSl,0,reason));
   }
   // Final close. ev must be KKN_EV_SL / KKN_EV_SLPLUS / KKN_EV_TP2.
   void TradeClose(bool isLong,int ev,double net,string reason)
   {
      if(m_channel==KKN_NONE) return;
      Send(m_eaTag+" closed "+_Symbol,Build(ev,isLong,0,0,0,0,0,0,net,reason));
   }
   // Generic event entry point (used by the validator EA to exercise all shapes).
   void Emit(int ev,bool isLong,double lot,double entry,double sl,
             double tp1,double tp2,double price,double net,string reason)
   {
      if(m_channel==KKN_NONE) return;
      Send(m_eaTag+" "+EventLabel(ev)+" "+_Symbol,
           Build(ev,isLong,lot,entry,sl,tp1,tp2,price,net,reason));
   }

   // Account-guardian / safety alert (always sent in full - prop-critical).
   void AlertMsg(string msg)
   {
      if(m_channel==KKN_NONE) return;
      Send(m_eaTag+" ALERT","["+m_eaTag+"] "+msg);
   }
};

#endif // KK_NOTIFIER_MQH
