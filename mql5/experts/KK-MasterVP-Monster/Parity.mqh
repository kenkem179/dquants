//+------------------------------------------------------------------+
//|  KK-MasterVP/Parity.mqh — TRADE-LEVEL parity journal.              |
//|                                                                    |
//|  Emits one row per CLOSED position, byte-compatible with the C++   |
//|  kk::to_trades_csv ledger (cpp_core/include/kk/common/             |
//|  trade_journal.hpp). Diff the MT5-tester output against the engine |
//|  trades_*.csv with research/validation/parity_diff.py to PROVE the |
//|  shipped EA reproduces the locked C++ backtest trade-for-trade.    |
//|                                                                    |
//|  Column order + per-field rounding mirror trades_csv_header():     |
//|    entryTimeUTC,dir,rev,retest,regimeTrend,session,entry,riskPrice, |
//|    mfeR,maeR,realizedUsd,entryReason,brkDistAtr,bodyPct,adx,        |
//|    diSpread,runwayAtr,nodeNet,spreadPips,spreadAtr,exitTag          |
//|                                                                    |
//|  Output: MQL5/Files/KK-MasterVP/trades_<sym>_<tf>.csv (gated by    |
//|  InpExportParity; default OFF so live/forward runs are unaffected).|
//+------------------------------------------------------------------+
#ifndef KKMVPM_PARITY_MQH
#define KKMVPM_PARITY_MQH

int g_parityHandle = INVALID_HANDLE;

// --- per-trade context captured at fill, finalized at full close ---
struct ParityCtx {
   bool     active;
   ulong    position;        // position id we are journaling
   datetime entryUtc;        // UTC bar-open time at fill
   bool     isLong, isRev, regimeTrend;
   int      session;
   double   entry, riskPrice;
   double   bestPrice, worstPrice;          // for MFE/MAE in price terms
   double   realizedUsd;                    // accumulated across partial+final out-deals
   string   reason;
   double   brkDistAtr, bodyPct, adx, diSpread, runwayAtr, nodeNet;
   double   spreadPips, spreadAtr;
};
ParityCtx g_pc;

void ParityInit()
{
   g_pc.active = false; g_pc.position = 0;
   if(!InpExportParity) return;
   string fname = StringFormat("KK-MasterVP-Monster\\trades_%s_%s.csv", _Symbol, EnumToString((ENUM_TIMEFRAMES)Period()));
   g_parityHandle = FileOpen(fname, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(g_parityHandle == INVALID_HANDLE){
      Print("[PARITY] cannot open ", fname, " err=", GetLastError());
      return;
   }
   FileWriteString(g_parityHandle,
      "entryTimeUTC,dir,rev,retest,regimeTrend,session,entry,riskPrice,mfeR,maeR,"
      "realizedUsd,entryReason,brkDistAtr,bodyPct,adx,diSpread,runwayAtr,nodeNet,"
      "spreadPips,spreadAtr,exitTag\n");
   FileFlush(g_parityHandle);
   Print("[PARITY] trade-level export -> ", fname);
}

void ParityClose()
{
   if(g_parityHandle != INVALID_HANDLE){ FileClose(g_parityHandle); g_parityHandle = INVALID_HANDLE; }
}

// Capture entry context the moment a fill succeeds (called from OnNewBar after Buy/Sell).
void ParityOnFill(ulong position, datetime entryUtc, const Signal &sig, int session,
                  bool regimeTrend, double entry, double sl, double spreadPrice, double atr1)
{
   if(g_parityHandle == INVALID_HANDLE) return;
   g_pc.active       = true;
   g_pc.position     = position;
   g_pc.entryUtc     = entryUtc;
   g_pc.isLong       = sig.is_long;
   g_pc.isRev        = sig.is_rev;
   g_pc.regimeTrend  = regimeTrend;
   g_pc.session      = session;
   g_pc.entry        = entry;
   g_pc.riskPrice    = MathAbs(entry - sl);
   g_pc.bestPrice    = entry;
   g_pc.worstPrice   = entry;
   g_pc.realizedUsd  = 0.0;
   g_pc.reason       = sig.reason;
   g_pc.brkDistAtr   = sig.f_brk_dist_atr;
   g_pc.bodyPct      = sig.f_body_pct;
   g_pc.adx          = sig.f_adx;
   g_pc.diSpread     = sig.f_di_spread;
   g_pc.runwayAtr    = sig.f_runway_atr;
   g_pc.nodeNet      = sig.f_node_net;
   g_pc.spreadPips   = (g_pip > 0.0) ? spreadPrice / g_pip : 0.0;
   g_pc.spreadAtr    = (atr1   > 0.0) ? spreadPrice / atr1  : 0.0;
}

// Track MFE/MAE each tick while the position is live (called from MvpManage).
void ParityTrackExcursion(double price)
{
   if(!g_pc.active) return;
   if(price > g_pc.bestPrice)  g_pc.bestPrice  = price;
   if(price < g_pc.worstPrice) g_pc.worstPrice = price;
}

// exitTag from the closing deal reason, sign-disambiguating SL into WIN/LOSS like the C++ engine.
string ParityExitTag(ENUM_DEAL_REASON reason, double realized)
{
   if(reason == DEAL_REASON_TP) return "TP";
   if(reason == DEAL_REASON_SL) return (realized > 0.0) ? "SL-WIN" : "SL-LOSS";
   return "EA";   // expert/client force-close (session exit etc.)
}

// Fired from OnTradeTransaction on each DEAL_ENTRY_OUT; emits the row once the position is fully closed.
void ParityOnDealOut(ulong dealTicket, ulong position)
{
   if(g_parityHandle == INVALID_HANDLE || !g_pc.active) return;
   if(position != g_pc.position) return;
   if(!HistoryDealSelect(dealTicket)) return;

   double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                 + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                 + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   g_pc.realizedUsd += profit;

   // Still open (this was a TP1 partial)? keep accumulating, emit on the final out-deal.
   if(PositionSelectByTicket(position)) return;

   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
   string tag = ParityExitTag(reason, g_pc.realizedUsd);

   double mfeR = (g_pc.riskPrice > 0.0)
               ? (g_pc.isLong ? (g_pc.bestPrice  - g_pc.entry) : (g_pc.entry - g_pc.worstPrice)) / g_pc.riskPrice : 0.0;
   double maeR = (g_pc.riskPrice > 0.0)
               ? (g_pc.isLong ? (g_pc.entry - g_pc.worstPrice) : (g_pc.bestPrice  - g_pc.entry)) / g_pc.riskPrice : 0.0;

   string row = StringFormat("%s,%s,%d,%d,%d,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
      TimeToString(g_pc.entryUtc, TIME_DATE|TIME_MINUTES),
      (g_pc.isLong ? "L" : "S"),
      (g_pc.isRev ? 1 : 0),
      0,                                   // retest (always 0 in v1 parity config)
      (g_pc.regimeTrend ? 1 : 0),
      g_pc.session,
      DoubleToString(g_pc.entry, 3),
      DoubleToString(g_pc.riskPrice, 3),
      DoubleToString(mfeR, 2),
      DoubleToString(maeR, 2),
      DoubleToString(g_pc.realizedUsd, 2),
      g_pc.reason,
      DoubleToString(g_pc.brkDistAtr, 2),
      DoubleToString(g_pc.bodyPct, 2),
      DoubleToString(g_pc.adx, 1),
      DoubleToString(g_pc.diSpread, 1),
      DoubleToString(g_pc.runwayAtr, 2),
      DoubleToString(g_pc.nodeNet, 2),
      DoubleToString(g_pc.spreadPips, 1),
      DoubleToString(g_pc.spreadAtr, 3),
      tag);
   FileWriteString(g_parityHandle, row);
   FileFlush(g_parityHandle);
   g_pc.active = false; g_pc.position = 0;
}

#endif // KKMVPM_PARITY_MQH
