//+------------------------------------------------------------------+
//|  KK-MasterVP/SessionNews.mqh — self-contained sessions + news.    |
//|  Ports cpp_core kk::Sessions (filters.hpp) 1:1 and the KenKem      |
//|  NewsFilter (CSV calendar + embedded fallback). No external        |
//|  framework deps — include AFTER Inputs.mqh.                        |
//|                                                                    |
//|  TIME MODEL (load-bearing): the C++ engine evaluates sessions on   |
//|  UTC tick time + InpBrokerGMTOffset (=10, the TV chart tz). MT5     |
//|  gives BROKER-SERVER time, so we auto-detect the broker's UTC      |
//|  offset (TimeTradeServer - TimeGMT) to first recover UTC, then add |
//|  InpBrokerGMTOffset to reach the session reference tz. This makes  |
//|  the EA trade the SAME wall-clock UTC hours as the backtest on any |
//|  broker, regardless of its server timezone.                        |
//+------------------------------------------------------------------+
#ifndef KKMVP_SESSIONNEWS_MQH
#define KKMVP_SESSIONNEWS_MQH

#include "Inputs.mqh"
#include "NewsCalendarEmbedded.mqh"

// ---- session-window parse state (minutes-of-day) ----
int  g_asiaLo=-1,g_asiaHi=-1, g_ldnLo=-1,g_ldnHi=-1, g_nyLo=-1,g_nyHi=-1;
bool g_blockedHour[24];
int  g_brokerToUtcHrs = 0;       // auto-detected broker server offset from UTC (hours)
int  g_curSessionId   = -1;
int  g_tradesThisSession = 0;

// "HH:MM" -> minute-of-day, or -1 if malformed.
int SN_ParseHM(string t){
   int c=StringFind(t,":"); if(c<0) return -1;
   int h=(int)StringToInteger(StringSubstr(t,0,c));
   int m=(int)StringToInteger(StringSubstr(t,c+1));
   if(h<0||h>23||m<0||m>59) return -1;
   return h*60+m;
}
// "HH:MM-HH:MM" -> (lo,hi); lo=hi=-1 if malformed.
void SN_ParseWindow(string s,int &lo,int &hi){
   lo=-1; hi=-1; int d=StringFind(s,"-"); if(d<0) return;
   int a=SN_ParseHM(StringSubstr(s,0,d)), b=SN_ParseHM(StringSubstr(s,d+1));
   if(a<0||b<0) return; lo=a; hi=b;
}
void SN_ParseBlocked(string raw){
   for(int i=0;i<24;i++) g_blockedHour[i]=false;
   string s=""; for(int i=0;i<StringLen(raw);i++){ ushort ch=StringGetCharacter(raw,i); if(ch!=' ') s+=ShortToString(ch); }
   string toks[]; int n=StringSplit(s,',',toks);
   for(int i=0;i<n;i++){
      string tok=toks[i]; if(StringLen(tok)==0) continue;
      int d=StringFind(tok,"-");
      if(d<0){ int h=(int)StringToInteger(tok); if(h>=0&&h<24) g_blockedHour[h]=true; }
      else{
         int lo=(int)StringToInteger(StringSubstr(tok,0,d)), hi=(int)StringToInteger(StringSubstr(tok,d+1));
         if(lo>hi){ int t=lo; lo=hi; hi=t; }
         for(int h=lo;h<=hi&&h<24;h++) if(h>=0) g_blockedHour[h]=true;
      }
   }
}

// Detect the broker server's offset from UTC (hours), rounded. Live: exact.
// Tester: TimeGMT() tracks TimeTradeServer with the broker's known offset, so
// this still recovers it; if TimeGMT is unavailable it degrades to 0 (server==UTC).
void SN_DetectBrokerOffset(){
   datetime srv=TimeTradeServer(), utc=TimeGMT();
   if(srv>0 && utc>0) g_brokerToUtcHrs=(int)MathRound((double)((long)srv-(long)utc)/3600.0);
   else g_brokerToUtcHrs=0;
}

void SN_Init(){
   SN_ParseWindow(InpAsiaSess,g_asiaLo,g_asiaHi);
   SN_ParseWindow(InpLdnSess, g_ldnLo, g_ldnHi);
   SN_ParseWindow(InpNySess,  g_nyLo,  g_nyHi);
   SN_ParseBlocked(InpBlockedHoursStr);
   SN_DetectBrokerOffset();
   g_curSessionId=-1; g_tradesThisSession=0;
   PrintFormat("[KK-MasterVP] sessions: brokerUTC=%+d refOffset=%+d Asia[%d-%d] Ldn[%d-%d] NY[%d-%d]",
      g_brokerToUtcHrs,InpBrokerGMTOffset,g_asiaLo,g_asiaHi,g_ldnLo,g_ldnHi,g_nyLo,g_nyHi);
}

// Server bar time -> session REFERENCE time (UTC + InpBrokerGMTOffset).
datetime SN_RefTime(datetime serverBarTime){
   return serverBarTime - (datetime)(g_brokerToUtcHrs*3600) + (datetime)(InpBrokerGMTOffset*3600);
}
// Server bar time -> pure UTC (for the news calendar, which is in UTC).
datetime SN_UtcTime(datetime serverBarTime){
   return serverBarTime - (datetime)(g_brokerToUtcHrs*3600);
}

// half-open [lo,hi); lo>hi wraps midnight; lo<0 => never.
bool SN_InWin(int cur,int lo,int hi){
   if(lo<0||hi<0||lo==hi) return false;
   if(lo<hi) return (cur>=lo && cur<hi);
   return (cur>=lo || cur<hi);
}
// 1 Asia / 2 London / 3 NY / 0 none, at a reference-tz datetime.
int SN_SessionId(datetime ref){
   MqlDateTime dt; TimeToStruct(ref,dt); int cur=dt.hour*60+dt.min;
   if(SN_InWin(cur,g_asiaLo,g_asiaHi)) return 1;
   if(SN_InWin(cur,g_ldnLo, g_ldnHi))  return 2;
   if(SN_InWin(cur,g_nyLo,  g_nyHi))   return 3;
   return 0;
}
// Per bar: current session id, resetting the per-session counter on a change.
int SN_UpdateSession(datetime ref){
   int id=SN_SessionId(ref);
   if(id!=g_curSessionId){ g_tradesThisSession=0; g_curSessionId=id; }
   return id;
}
bool SN_MaxTradesOk(){ return g_tradesThisSession < InpMaxTradesPerSession; }
void SN_OnFill(){ g_tradesThisSession++; }
bool SN_IsBlockedHour(datetime ref){
   MqlDateTime dt; TimeToStruct(ref,dt);
   return (dt.hour>=0 && dt.hour<24 && g_blockedHour[dt.hour]);
}

// ---- News blackout (CSV of UTC release times; embedded fallback) ----
#ifndef KKMVP_NEWS_FILE
#define KKMVP_NEWS_FILE "KK-MasterVP\\HighImpactNews_USD.csv"
#endif
datetime g_newsTimes[]; int g_newsCount=0; bool g_newsLoaded=false;

datetime SN_ParseNewsDT(string s){
   StringTrimLeft(s); StringTrimRight(s); if(StringLen(s)<16) return 0;
   MqlDateTime dt; dt.sec=0;
   dt.year=(int)StringToInteger(StringSubstr(s,0,4));
   dt.mon =(int)StringToInteger(StringSubstr(s,5,2));
   dt.day =(int)StringToInteger(StringSubstr(s,8,2));
   dt.hour=(int)StringToInteger(StringSubstr(s,11,2));
   dt.min =(int)StringToInteger(StringSubstr(s,14,2));
   if(dt.year<2000||dt.mon<1||dt.mon>12||dt.day<1||dt.day>31) return 0;
   return StructToTime(dt);
}
void SN_ParseNewsLine(string line){
   StringTrimLeft(line); StringTrimRight(line);
   if(StringLen(line)==0) return; if(StringGetCharacter(line,0)=='#') return;
   string p[]; int n=StringSplit(line,',',p); if(n<3) return;
   if(p[0]=="DateTime") return; if(StringFind(p[2],"High")<0) return;
   datetime t=SN_ParseNewsDT(p[0]); if(t<=0) return;
   ArrayResize(g_newsTimes,g_newsCount+1); g_newsTimes[g_newsCount]=t; g_newsCount++;
}
void SN_LoadNews(){
   g_newsLoaded=true; g_newsCount=0; ArrayResize(g_newsTimes,0);
   if(!InpAvoidNews) return;
   int h=FileOpen(KKMVP_NEWS_FILE,FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) h=FileOpen(KKMVP_NEWS_FILE,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h!=INVALID_HANDLE){
      while(!FileIsEnding(h)) SN_ParseNewsLine(FileReadString(h));
      FileClose(h);
      PrintFormat("[KK-MasterVP][NEWS] loaded %d events from %s",g_newsCount,KKMVP_NEWS_FILE);
      return;
   }
   if(InpUseEmbeddedNews){
      string lines[]; int n=StringSplit(EmbeddedNewsCsv(),'\n',lines);
      for(int i=0;i<n;i++) SN_ParseNewsLine(lines[i]);
      PrintFormat("[KK-MasterVP][NEWS] CSV not found — using EMBEDDED calendar (%d events)",g_newsCount);
      return;
   }
   Print("[KK-MasterVP][NEWS] calendar absent and embedded disabled — news filter inert");
}
// True when the UTC time falls in [event-before, event+after] of any high-impact event.
bool SN_InNewsWindow(datetime utc){
   if(!InpAvoidNews) return false;
   if(!g_newsLoaded) SN_LoadNews();
   long before=(long)InpNewsMinsBefore*60, after=(long)InpNewsMinsAfter*60;
   for(int i=0;i<g_newsCount;i++)
      if(utc>=g_newsTimes[i]-before && utc<=g_newsTimes[i]+after) return true;
   return false;
}

#endif // KKMVP_SESSIONNEWS_MQH
