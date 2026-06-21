//+------------------------------------------------------------------+
//|                                                  BarTrace.mqh     |
//|     KenKem — per-bar E5 DECISION trace (diagnostics only).        |
//|                                                                  |
//|     One CSV row per CLOSED M1 bar, schema-IDENTICAL to the        |
//|     dquants C++ golden trace (cpp_core/tools/kenkem/trace_dumper). |
//|     Diffed field-by-field (join key = ts_ms / dt in UTC) to       |
//|     localize the residual E5 over-fire + entry-lag: the FIRST     |
//|     bar where any column diverges pins the bug to indicator-drift  |
//|     vs trigger-state vs a specific gate decision.                  |
//|                                                                  |
//|     The 61 columns are produced by Entry5::TraceBar(), a READ-ONLY |
//|     mirror of Detect() that maintains its OWN onset state (does    |
//|     NOT touch the live trigger), computes every sub-decision with  |
//|     NO early-return and NO trade side effect, and consumes its own  |
//|     trigger on a fire — exactly like trace_dumper's eval_e5.        |
//|                                                                  |
//|     ts_ms/dt are emitted in UTC (server time minus the live broker  |
//|     offset, TimeCurrent()-TimeGMT()), matching TradeJournal.mqh.    |
//|                                                                  |
//|     NOTE on non-gate columns: E5 has no M1 Ichimoku, so tenkan/    |
//|     kijun are emitted 0; senkouA_m3/senkouB_m3 come from the M3     |
//|     cache only when E4 is active (else 0). L_tcore/S_tcore map to   |
//|     E5's EMA-alignment hard gate (E5 has no separate trend-core).   |
//|     Ignore those columns in the diff — they are not E5 gate inputs. |
//|                                                                  |
//|     Output: MQL5/Files/KenKem/trace_<sym>.csv. Include AFTER the    |
//|     EA inputs and BEFORE Entry5.mqh (the struct must be visible).   |
//+------------------------------------------------------------------+
#property strict

#ifndef KENKEM_BARTRACE_MQH
#define KENKEM_BARTRACE_MQH

input bool InpExportBarTrace = false;   // PARITY: write per-bar E5 decision trace (diagnostics only)

// One row of the per-bar E5 decision trace. Field order MUST match the C++ trace header.
struct E5TraceRow {
   long   ts_ms;                       // bar open time, UTC epoch ms (join key)
   string dt;                          // "YYYY.MM.DD HH:MM" UTC
   double ema0, ema1, ema2, ema3, ema4;
   double adx_m1, adx_m3, adx_m5, adx_m15;
   double diP_m1, diP_m3, diP_m5, diP_m15;
   double diM_m1, diM_m3, diM_m5, diM_m15;
   double adxS, diPS, diMS;
   double atr, rsi, close, high, low;
   double tenkan, kijun, senkouA_m3, senkouB_m3;
   int    sideways;
   double atr_pctile;
   int    e5up_age, e5dn_age;
   int    L_inage, L_swblk, L_atrlo, L_atrhi, L_price, L_tcore, L_tq, L_tqok, L_adx, L_htf, L_pass, L_fire;
   int    S_inage, S_swblk, S_atrlo, S_atrhi, S_price, S_tcore, S_tq, S_tqok, S_adx, S_htf, S_pass, S_fire;
   int    session, fire_dir;
};

int g_btHandle = INVALID_HANDLE;

void InitBarTrace() {
   if(!InpExportBarTrace) return;
   string fname = StringFormat("KenKem\\trace_%s.csv", _Symbol);
   g_btHandle = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(g_btHandle == INVALID_HANDLE) {
      Print("[BARTRACE] cannot open ", fname, " err=", GetLastError());
      return;
   }
   FileWrite(g_btHandle,
      "ts_ms","dt",
      "ema0","ema1","ema2","ema3","ema4",
      "adx_m1","adx_m3","adx_m5","adx_m15","diP_m1","diP_m3","diP_m5","diP_m15","diM_m1","diM_m3","diM_m5","diM_m15",
      "adxS","diPS","diMS","atr","rsi","close","high","low","tenkan","kijun","senkouA_m3","senkouB_m3","sideways","atr_pctile",
      "e5up_age","e5dn_age",
      "L_inage","L_swblk","L_atrlo","L_atrhi","L_price","L_tcore","L_tq","L_tqok","L_adx","L_htf","L_pass","L_fire",
      "S_inage","S_swblk","S_atrlo","S_atrhi","S_price","S_tcore","S_tq","S_tqok","S_adx","S_htf","S_pass","S_fire",
      "session","fire_dir");
   Print("[BARTRACE] per-bar E5 decision trace -> ", fname);
}

void WriteBarTraceRow(const E5TraceRow &r) {
   if(g_btHandle == INVALID_HANDLE) return;
   FileWrite(g_btHandle,
      IntegerToString(r.ts_ms), r.dt,
      DoubleToString(r.ema0,5), DoubleToString(r.ema1,5), DoubleToString(r.ema2,5), DoubleToString(r.ema3,5), DoubleToString(r.ema4,5),
      DoubleToString(r.adx_m1,3), DoubleToString(r.adx_m3,3), DoubleToString(r.adx_m5,3), DoubleToString(r.adx_m15,3),
      DoubleToString(r.diP_m1,3), DoubleToString(r.diP_m3,3), DoubleToString(r.diP_m5,3), DoubleToString(r.diP_m15,3),
      DoubleToString(r.diM_m1,3), DoubleToString(r.diM_m3,3), DoubleToString(r.diM_m5,3), DoubleToString(r.diM_m15,3),
      DoubleToString(r.adxS,3), DoubleToString(r.diPS,3), DoubleToString(r.diMS,3),
      DoubleToString(r.atr,5), DoubleToString(r.rsi,3), DoubleToString(r.close,5), DoubleToString(r.high,5), DoubleToString(r.low,5),
      DoubleToString(r.tenkan,5), DoubleToString(r.kijun,5), DoubleToString(r.senkouA_m3,5), DoubleToString(r.senkouB_m3,5),
      IntegerToString(r.sideways), DoubleToString(r.atr_pctile,2),
      IntegerToString(r.e5up_age), IntegerToString(r.e5dn_age),
      IntegerToString(r.L_inage), IntegerToString(r.L_swblk), IntegerToString(r.L_atrlo), IntegerToString(r.L_atrhi),
      IntegerToString(r.L_price), IntegerToString(r.L_tcore), IntegerToString(r.L_tq), IntegerToString(r.L_tqok),
      IntegerToString(r.L_adx), IntegerToString(r.L_htf), IntegerToString(r.L_pass), IntegerToString(r.L_fire),
      IntegerToString(r.S_inage), IntegerToString(r.S_swblk), IntegerToString(r.S_atrlo), IntegerToString(r.S_atrhi),
      IntegerToString(r.S_price), IntegerToString(r.S_tcore), IntegerToString(r.S_tq), IntegerToString(r.S_tqok),
      IntegerToString(r.S_adx), IntegerToString(r.S_htf), IntegerToString(r.S_pass), IntegerToString(r.S_fire),
      IntegerToString(r.session), IntegerToString(r.fire_dir));
}

void CloseBarTrace() {
   if(g_btHandle != INVALID_HANDLE) { FileClose(g_btHandle); g_btHandle = INVALID_HANDLE; }
}

#endif // KENKEM_BARTRACE_MQH
