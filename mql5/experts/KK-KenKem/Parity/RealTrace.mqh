//+------------------------------------------------------------------+
//|                                                 RealTrace.mqh      |
//|     KenKem — REAL-PATH E5 entry-decision trace (diagnostics only). |
//|                                                                  |
//|     Unlike BarTrace.mqh (a read-only MIRROR of Detect() that keeps |
//|     its OWN onset state and checks ATR_PERCENTILE_LOW=20), this    |
//|     trace is filled FROM the live Detect() execution itself —      |
//|     the ACTUAL m_lastBullishSignal/m_lastBearishSignal onset, the  |
//|     ACTUAL cache.adx[0] the ADX gate read, and the ACTUAL gate     |
//|     that short-circuited the entry. The execution-side columns     |
//|     (ATR-percentile gate inputs, high-risk routing, opposing /     |
//|     streak blocks) are filled by the EA right after Detect()       |
//|     using READ-ONLY globals — no GetEntryBlockReason() call (which |
//|     mutates blackSwanBlockedUntil) so the trace never perturbs     |
//|     real trading.                                                  |
//|                                                                  |
//|     Purpose: crack the 2026 E5 gate-SELECTION divergence (engine   |
//|     75/-683 vs MT5 108/+949) by exposing, per ARMED E5 trigger     |
//|     bar, the exact real-path inputs the engine can be diffed       |
//|     against — chiefly cachedATRPercentile vs MIN_ENTRY_ATR_PERCENTILE |
//|     (the binding =65 block BarTrace never models) and the real     |
//|     onset age / cache.adx[0].                                      |
//|                                                                  |
//|     One CSV row per bar where an E5 trigger is ARMED or fires.     |
//|     ts_ms/dt in UTC (server time minus broker offset), join key.   |
//|     Output: MQL5/Files/KenKem/realtrace_<sym>.csv.                 |
//|     Include AFTER the EA inputs and BEFORE Entry5.mqh.             |
//+------------------------------------------------------------------+
#property strict

#ifndef KENKEM_REALTRACE_MQH
#define KENKEM_REALTRACE_MQH

input bool InpExportRealTrace = false;   // PARITY: write REAL-PATH E5 entry-decision trace (diagnostics only)

// One row of the real-path E5 entry-decision trace.
// Gate-side fields are filled inside Entry5::Detect() (live state); execution-side
// fields are filled by the EA after Detect() from read-only globals.
struct E5RealRow {
   // --- identity ---
   long   ts_ms;              // bar open time, UTC epoch ms (join key)
   string dt;                 // "YYYY.MM.DD HH:MM" UTC
   int    bar;                // currentBar index
   int    interesting;        // 1 if an E5 trigger was armed/fired this bar (write gate)
   // --- live Detect() state (REAL trigger, not the BarTrace mirror) ---
   int    armed_dir;          // +1 bull armed, -1 bear armed, 0 none (m_lastBullishSignal/Bearish)
   int    up_age, dn_age;     // REAL onset age = thisBar - m_lastBullishSignal/Bearish (-1 if none)
   int    aligned_bull, aligned_bear;
   double price, ema25, ema200, atr_m1;
   double adx_m1, min_adx;    // cache.adx[0] the gate read, and E5_MIN_MOMENTUM_ADX
   int    adx_pass;           // 1 if ADX gate passed (or disabled), 0 if it short-circuited Detect
   int    trend_quality, tq_pass;
   int    htf_block_long, htf_block_short;
   int    sideway_block;
   int    price_ok;           // armed dir on the right side of EMA25
   int    in_session;
   int    detected, det_long; // Detect() result (captured BEFORE signal consume)
   string gate;               // real-path block stage: adx_gate|session_limit|sideway|no_trigger|
                              //   age_expired|price|tq|htf|session|align_flip|deferred|fired|other
   // --- execution-side (EA fills, read-only; only meaningful when detected) ---
   double atr_pctile;         // cachedATRPercentile (global)
   double min_entry_pctile;   // MIN_ENTRY_ATR_PERCENTILE (the binding =65 gate)
   double atr_pctile_low, atr_pctile_high;
   int    min_entry_block;    // 1 if blocked by MIN_ENTRY_ATR_PERCENTILE (read-only replica of the real gate)
   int    is_high_risk;       // potentialLossUSD >= entry-specific maxLoss -> HandleHighRiskEntry route
   double potential_loss_usd, entry_max_loss;
   int    opposing_pos, entrytype_blocked;
   string final_decision;     // FIRE | HIGH_RISK_ROUTE | BLOCK:* | NOT_DETECTED:<gate>
   // --- value-diff columns (added to decompose the 48 detection-misses) ---
   // 26 unarmed: complete the M1 4-EMA strict-alignment stack (ema25/ema200 above).
   double ema75, ema100;      // GetEMA(TF0,EMA2/EMA3,shift) — middle of the M1 alignment stack
   // 7 trend_core: M1 DI± the trend-core check reads (cache.diPlus/diMinus[0]); adx_m1 above.
   double m1_diplus, m1_diminus;
   // 15 htf: exact M5/M15 ADX + DI± the E5 HTF filter reads (cache idx 2=M5, 3=M15).
   double m5_adx, m5_diplus, m5_diminus;
   double m15_adx, m15_diplus, m15_diminus;
};

int g_rtHandle = INVALID_HANDLE;

void InitRealTrace() {
   if(!InpExportRealTrace) return;
   string fname = StringFormat("KenKem\\realtrace_%s.csv", _Symbol);
   g_rtHandle = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(g_rtHandle == INVALID_HANDLE) {
      Print("[REALTRACE] cannot open ", fname, " err=", GetLastError());
      return;
   }
   FileWrite(g_rtHandle,
      "ts_ms","dt","bar","interesting",
      "armed_dir","up_age","dn_age","aligned_bull","aligned_bear",
      "price","ema25","ema200","atr_m1",
      "adx_m1","min_adx","adx_pass",
      "trend_quality","tq_pass","htf_block_long","htf_block_short","sideway_block",
      "price_ok","in_session","detected","det_long","gate",
      "atr_pctile","min_entry_pctile","atr_pctile_low","atr_pctile_high","min_entry_block",
      "is_high_risk","potential_loss_usd","entry_max_loss","opposing_pos","entrytype_blocked",
      "final_decision",
      "ema75","ema100","m1_diplus","m1_diminus",
      "m5_adx","m5_diplus","m5_diminus","m15_adx","m15_diplus","m15_diminus");
   Print("[REALTRACE] real-path E5 entry-decision trace -> ", fname);
}

void WriteRealTraceRow(const E5RealRow &r) {
   if(g_rtHandle == INVALID_HANDLE) return;
   FileWrite(g_rtHandle,
      IntegerToString(r.ts_ms), r.dt, IntegerToString(r.bar), IntegerToString(r.interesting),
      IntegerToString(r.armed_dir), IntegerToString(r.up_age), IntegerToString(r.dn_age),
      IntegerToString(r.aligned_bull), IntegerToString(r.aligned_bear),
      DoubleToString(r.price,5), DoubleToString(r.ema25,5), DoubleToString(r.ema200,5), DoubleToString(r.atr_m1,5),
      DoubleToString(r.adx_m1,3), DoubleToString(r.min_adx,3), IntegerToString(r.adx_pass),
      IntegerToString(r.trend_quality), IntegerToString(r.tq_pass),
      IntegerToString(r.htf_block_long), IntegerToString(r.htf_block_short), IntegerToString(r.sideway_block),
      IntegerToString(r.price_ok), IntegerToString(r.in_session), IntegerToString(r.detected), IntegerToString(r.det_long), r.gate,
      DoubleToString(r.atr_pctile,2), DoubleToString(r.min_entry_pctile,2),
      DoubleToString(r.atr_pctile_low,2), DoubleToString(r.atr_pctile_high,2), IntegerToString(r.min_entry_block),
      IntegerToString(r.is_high_risk), DoubleToString(r.potential_loss_usd,2), DoubleToString(r.entry_max_loss,2),
      IntegerToString(r.opposing_pos), IntegerToString(r.entrytype_blocked),
      r.final_decision,
      DoubleToString(r.ema75,5), DoubleToString(r.ema100,5),
      DoubleToString(r.m1_diplus,3), DoubleToString(r.m1_diminus,3),
      DoubleToString(r.m5_adx,3), DoubleToString(r.m5_diplus,3), DoubleToString(r.m5_diminus,3),
      DoubleToString(r.m15_adx,3), DoubleToString(r.m15_diplus,3), DoubleToString(r.m15_diminus,3));
}

void CloseRealTrace() {
   if(g_rtHandle != INVALID_HANDLE) { FileClose(g_rtHandle); g_rtHandle = INVALID_HANDLE; }
}

#endif // KENKEM_REALTRACE_MQH
