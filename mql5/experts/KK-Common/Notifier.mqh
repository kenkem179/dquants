//+------------------------------------------------------------------+
//|  KK-Common/Notifier.mqh                                           |
//|  D3 - Minimal shared notifications for KK-MasterVP (+ Monster).   |
//|                                                                    |
//|  KK-KenKem already has the full suite (ported from KenKemExpert) - |
//|  do NOT touch it. This is a small standalone helper that reuses    |
//|  the proven WebRequest call shapes WITHOUT copy-pasting KenKem's   |
//|  5 Trade-struct-coupled files. Discord webhook + Telegram          |
//|  token/chatId + Email via SendMail.                                |
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
   KKN_MODE_FULL       = 1,   // full detail (entry/SL/TP/net)
   KKN_MODE_SIMPLIFIED = 2    // prop-safe: symbol + action + result only
};

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
   string m_discord,m_tgToken,m_tgChat,m_eaTag;

   bool DiscOn(){ return m_channel==KKN_DISCORD||m_channel==KKN_EMAIL_DISC||m_channel==KKN_DISC_TG||m_channel==KKN_ALL_THREE; }
   bool TgOn()  { return m_channel==KKN_TELEGRAM||m_channel==KKN_EMAIL_TG||m_channel==KKN_DISC_TG||m_channel==KKN_ALL_THREE; }
   bool MailOn(){ return m_channel==KKN_EMAIL||m_channel==KKN_EMAIL_DISC||m_channel==KKN_EMAIL_TG||m_channel==KKN_ALL_THREE; }

public:
   KKNotifier(){ m_channel=KKN_NONE; m_mode=KKN_MODE_FULL; }

   void Init(int channel,int mode,string discord,string tgToken,string tgChat,string eaTag)
   {
      m_channel=channel; m_mode=mode;
      m_discord=discord; m_tgToken=tgToken; m_tgChat=tgChat; m_eaTag=eaTag;
   }

   bool Enabled(){ return m_channel!=KKN_NONE; }

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

   void TradeOpen(bool isLong,double lot,double entry,double sl,double tp,string reason)
   {
      if(m_channel==KKN_NONE) return;
      string act=isLong?"BUY":"SELL";
      string line;
      if(m_mode==KKN_MODE_SIMPLIFIED)
         line=StringFormat("[%s] %s %s",m_eaTag,_Symbol,act);
      else
         line=StringFormat("[%s] %s %s %.2f lots @ %s SL %s TP %s (%s)",
                           m_eaTag,_Symbol,act,lot,
                           DoubleToString(entry,_Digits),DoubleToString(sl,_Digits),
                           DoubleToString(tp,_Digits),reason);
      Send(m_eaTag+" "+act+" "+_Symbol,line);
   }

   void TradeClose(double profit,double net,string how)
   {
      if(m_channel==KKN_NONE) return;
      string res=(net>=0.0)?"WIN":"LOSS";
      string line;
      if(m_mode==KKN_MODE_SIMPLIFIED)
         line=StringFormat("[%s] %s closed %s",m_eaTag,_Symbol,res);
      else
         line=StringFormat("[%s] %s closed %s net %.2f (%s)",m_eaTag,_Symbol,res,net,how);
      Send(m_eaTag+" closed "+_Symbol,line);
   }

   // Account-guardian / safety alert (always sent in full - prop-critical).
   void AlertMsg(string msg)
   {
      if(m_channel==KKN_NONE) return;
      Send(m_eaTag+" ALERT","["+m_eaTag+"] "+msg);
   }
};

#endif // KK_NOTIFIER_MQH
