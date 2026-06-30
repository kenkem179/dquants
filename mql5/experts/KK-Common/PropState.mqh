//+------------------------------------------------------------------+
//|  KK-Common/PropState.mqh                                         |
//|  ACCOUNT-LEVEL prop state, persisted to ONE shared COMMON file.   |
//|                                                                   |
//|  Why: the prop drawdown guard (trailing-peak DD halt + soft-block)|
//|  anchors on an equity HIGH-WATER MARK. If that HWM lives only in  |
//|  EA memory it RESETS on every reload/restart -> a VPS reboot would |
//|  forget the peak and silently re-arm a fresh drawdown allowance,  |
//|  defeating the guard on a funded account. This module persists the|
//|  HWM (+ day anchors) to a single file keyed by ACCOUNT ID in the  |
//|  shared COMMON folder, so:                                        |
//|    - it survives EA reloads / terminal restarts, and              |
//|    - EVERY KK EA on the same account (KenKem + MasterVP legs)      |
//|      reads/writes the SAME joint account-level state.             |
//|                                                                   |
//|  RESET (real life): delete the file. The next EA init reseeds the |
//|  HWM to current equity -> drawdown allowance starts fresh.        |
//|    File: <Terminal COMMON>\Files\KK_PropState_<accountId>.txt     |
//|    (MT5: File -> Open Data Folder is per-terminal; the COMMON one  |
//|     is Terminal\Common\Files, shared across terminals.)           |
//|                                                                   |
//|  Disabled inside the Strategy Tester / Optimizer (no file I/O),   |
//|  so backtests are byte-identical to the in-memory behaviour.      |
//+------------------------------------------------------------------+
#ifndef KKC_PROPSTATE_MQH
#define KKC_PROPSTATE_MQH

struct KKPropState
{
   double   peakEquity;       // account equity high-water mark (trailing-DD anchor)
   double   dayStartEquity;   // equity at the start of the current trading day
   double   dayPeakEquity;    // intraday equity peak (giveback tracking)
   long     dayKey;           // YYYYMMDD of dayStartEquity (-1 = unset)
   datetime updated;          // last write time (server)
   KKPropState(){ peakEquity=0.0; dayStartEquity=0.0; dayPeakEquity=0.0; dayKey=-1; updated=0; }
};

// One file per account, in the shared COMMON folder so all KK EAs on the account
// see the same state. Keyed by login so a different account never inherits a HWM.
string KKPropStateFile()
{
   return "KK_PropState_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+".txt";
}

// Parse the KEY=VALUE file into `st`. Returns false in tester, on missing/unreadable
// file, or on a torn/partial write (no valid peakEquity) -> caller seeds fresh.
bool KKPropStateLoad(KKPropState &st)
{
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return false;
   int h=FileOpen(KKPropStateFile(),
                  FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h==INVALID_HANDLE) return false;
   bool gotPeak=false;
   while(!FileIsEnding(h))
   {
      string line=FileReadString(h);
      int eq=StringFind(line,"=");
      if(eq<=0) continue;
      string k=StringSubstr(line,0,eq);
      string v=StringSubstr(line,eq+1);
      if(k=="peakEquity")        { st.peakEquity=StringToDouble(v); gotPeak=true; }
      else if(k=="dayStartEquity") st.dayStartEquity=StringToDouble(v);
      else if(k=="dayPeakEquity")  st.dayPeakEquity=StringToDouble(v);
      else if(k=="dayKey")         st.dayKey=(long)StringToInteger(v);
      else if(k=="updated")        st.updated=(datetime)StringToInteger(v);
   }
   FileClose(h);
   return gotPeak && st.peakEquity>0.0;
}

// Persist `st`, but MONOTONICALLY for the HWM: read the file's current peak first
// and keep the MAX, so a stale writer (another leg holding an older peak in memory)
// can never regress the shared high-water mark. Full-file rewrite each call -> a
// reader either sees the previous complete file or the new one. No-op in tester.
void KKPropStateSave(KKPropState &st)
{
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   KKPropState cur;
   if(KKPropStateLoad(cur) && cur.peakEquity>st.peakEquity) st.peakEquity=cur.peakEquity;
   int h=FileOpen(KKPropStateFile(),
                  FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h==INVALID_HANDLE) return;
   FileWriteString(h,"peakEquity="+DoubleToString(st.peakEquity,2)+"\n");
   FileWriteString(h,"dayStartEquity="+DoubleToString(st.dayStartEquity,2)+"\n");
   FileWriteString(h,"dayPeakEquity="+DoubleToString(st.dayPeakEquity,2)+"\n");
   FileWriteString(h,"dayKey="+IntegerToString(st.dayKey)+"\n");
   FileWriteString(h,"updated="+IntegerToString((long)TimeCurrent())+"\n");
   FileClose(h);
}

#endif // KKC_PROPSTATE_MQH
