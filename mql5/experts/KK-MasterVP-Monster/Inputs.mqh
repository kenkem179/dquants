//+------------------------------------------------------------------+
//|  KK-MasterVP-Monster/Inputs.mqh — INHERITS the KK-MasterVP input    |
//|  schema (mirrors cpp_core kk::Params 1:1) and adds the impulse-      |
//|  thrust group. Compiled-in DEFAULTS == the LOCKED BTCUSD-M3 Monster  |
//|  preset (research/monster_parity sweeps: OOS PF 1.131, impulse       |
//|  additive at adx 28). Load the shipped .set to override. Inp* keys   |
//|  match the C++ keys exactly for parity.                              |
//+------------------------------------------------------------------+
#ifndef KKMON_INPUTS_MQH
#define KKMON_INPUTS_MQH

input group "===== VP core (master = 200 bars = 50x4, OOS-robust) ====="
input int    InpVpLookback     = 50;
input int    InpVpBins         = 40;
input double InpVaPct          = 70.0;
input int    InpMasterMult     = 4;
input int    InpAtrLen         = 14;
input bool   InpAtrMt5Mode     = false;   // false = textbook Wilder ATR (Pine ta.atr = RMA)

input group "===== Node engine ====="
input double InpNodeTouchAtr   = 0.05;
input double InpNodeDecay      = 0.94;
input double InpNodeNeutralBand= 0.15;
input double InpNodeSaturation = 4.0;
input bool   InpNodeGateEnabled= true;
input bool   InpUsePriorBarVP  = false;
input bool   InpBrkRequireFlow = false;
input double InpSfpFlowMin      = 0.15;

input group "===== Regime (selective base: adx 28 makes impulse additive) ====="
input int    InpEmaFast        = 24;
input int    InpEmaSlow        = 194;
input int    InpAdxLen         = 14;
input double InpAdxTrendMin    = 28.0;
input double InpDiSpreadMin     = 4.0;     // WF re-lock 2026-06-20 (was 6.0): lifts worst fold
input double InpEmaSepAtr       = 0.25;

input group "===== Breakout (base path, fires BELOW the vol ceiling) ====="
input bool   InpEnableBreakout = true;
input double InpBreakBufAtr      = 0.1;     // anti-chase opt 2026-06-20 (was 0.25): WF 6/6 folds
input double InpBreakMaxAtr       = 3.0;    // anti-chase opt 2026-06-20 (was 5.0): PF 1.140->1.199, dd 13.7->10.6%, +31% net
input double InpRrBrk             = 3.0;
input double InpSlAtrBrk          = 3.7;
input bool   InpBrkVetoSfp        = false;

input group "===== Reversion (OFF — Monster default) ====="
input bool   InpEnableReversion = false;
input double InpRetestAtr         = 0.5;
input double InpBodyPctMin        = 0.4;
input double InpRrRev             = 1.35;
input double InpSlAtrRev          = 1.45;

input group "===== Impulse-thrust (the Monster delta; fires ABOVE the vol ceiling) ====="
input bool   InpEnableImpulse        = true;   // master toggle for the impulse path
input double InpImpulseCandleAtr     = 1.7;    // min thrust-bar range (h-l) in ATR
input double InpImpulseEntryBufAtr   = 0.4;    // min close beyond master VAH/VAL in ATR
input double InpImpulseNetMin        = 0.95;   // min one-sided M1 near-price net tick volume
input double InpImpulseMaxDistAtr    = 2.5;    // anti-chase vs the PREDICTED edge in ATR; 0 = off
input double InpImpulseRr            = 3.0;    // impulse TP RR (inert while the trail is ON)
input int    InpImpulseTrendSlopeBars= 6;      // WF re-lock 2026-06-20 (was 10): dominant lever, impNet +45%
input int    InpImpulsePredictBars   = 10;     // bars aged out for the predicted master VP; 0 = current
input int    InpTfNetLook            = 50;     // M1 net: bars summed for the near-price net
input double InpTfNetWinAtr           = 1.5;   // M1 net: near-price window half-width in ATR

input group "===== Extreme Reversion (XRev) — failed-breakout liquidity-sweep reversal (OFF) ====="
// Fires BELOW the vol ceiling (base band), priority over the base breakout/reversion signal. OFF by
// default => Monster byte-identical. Engine BTC M3: additive HELP (base PF 1.202->1.252 OOS, +9 tr).
// Tiny sample + BTC/Exness feed is historically MT5-over-optimistic on reversion — MT5-confirm first.
input bool   InpEnableExtremeReversion = false;  // master toggle (OFF = base unchanged)
input int    InpXRevHHLookback     = 5;     // N: swing-high/low sweep level lookback
input int    InpXRevFailLookback   = 14;    // M: window for the failed-acceptance count
input int    InpXRevMinClosesBeyond= 2;     // min closes beyond mVAH in M (trapped positioning)
input int    InpXRevMaxClosesBeyond= 0;     // cap to exclude a real sustained breakout; 0 = off
input int    InpXRevMinAgeBars     = 40;    // min bars since the opposite-edge cross (aged round-trip)
input double InpXRevBigCandleAtr   = 1.0;   // rejection-bar range >= x*ATR (keep <=0.6 per OOS; 1.0 overfits)
input double InpXRevBodyPctMin     = 0.4;   // body fraction of range
input double InpXRevWickFrac       = 1.0;   // sweep-tail wick >= x*body (the strongest discriminator)
input double InpXRevNetDeltaMin    = 0.6;   // near-price node net magnitude (sell/buy-dominated flow)
input bool   InpXRevUseNodeGate    = true;  // require selling/absorption at mVAH
input double InpXRevSlAtr           = 0.7;  // SL distance above the swept high
input double InpXRevRrMin           = 2.0;  // min RR (entry->target vs SL) to take the trade
input bool   InpXRevTpMpoc          = false;// XRev TP = master POC (full bank, humble RR) vs far edge
input bool   InpRevTpMpoc           = false;// base reversion TP = master POC instead of rr_rev multiple

input group "===== Exit ====="
input double InpTp1R            = 1.0;
input double InpTp1ClosePct     = 0.0;     // WF re-lock 2026-06-20 (was 15.0): no TP1 bank; BE-after-TP1 de-risks
input bool   InpBeAfterTp1      = true;
input double InpBeBufAtr        = 0.05;
input bool   InpTrailRunner     = true;     // ATR chandelier trail on the runner
input double InpRunnerRr        = 5.3;
input double InpTrailAtrMult    = 2.6;

input group "===== Risk sizing ====="
input int    InpRiskUnit        = 0;        // 0=%acct,1=USD,2=min,3=max
input double InpRiskAccPct      = 0.9;      // % balance risked/trade
input double InpRiskUsd         = 180.0;
input double InpMaxLot          = 0.0;      // 0 = broker VOLUME_MAX
input int    InpDeviationPoints = 200;
input bool   InpSkipIfMinLotOverRisk = false;

input group "===== Risk-management limiters ====="
input double InpMaxDailyDDPct   = 6.0;      // predictive daily-DD cap
input double InpDailyDDCooldownHrs = 12.0;
input double InpMaxPeakDDPct    = 30.0;
input double InpSoftBlockDDPct  = 15.0;
input double InpSoftBlockLotMult= 0.55;
input int    InpLossStreakCount = 3;
input double InpLossStreakCooldownHrs = 4.0;

input group "===== Safety / volatility (band 0.0156..0.158; impulse fires ABOVE 0.158) ====="
input double InpMinAtrPct       = 0.0156;
input double InpMaxAtrPct        = 0.158;
input double InpMinAtrTicks      = 0.0;
input int    InpMaxTradesPerSession = 4;
input double InpMaxSpreadPips    = 0.0;     // spread gate OFF
input double InpMaxSpreadTp1Frac = 0.0;     // TP1 cost-clearance OFF

input group "===== Quality gates (Monster has NEITHER) ====="
input bool   InpUseMtfAgree     = false;
input bool   InpMtfHardVeto     = true;
input bool   InpUseMomVeto      = false;
input double InpRsiMidline      = 50.0;
input int    InpRsiLen          = 14;

input group "===== Sessions (best_btc edge hours; BTC's edge concentrates by hour) ====="
input int    InpBrokerGMTOffset = 0;
input string InpAsiaSess        = "00:00-06:00";
input string InpLdnSess         = "07:00-11:00";
input string InpNySess          = "12:30-16:30";
input string InpBlockedHoursStr = "8,10,11,16";
input bool   InpForceCloseSessNews = true;

input group "===== News avoidance (live-safety overlay; CSV of UTC release times) ====="
input bool   InpAvoidNews       = false;
input int    InpNewsMinsBefore  = 15;
input int    InpNewsMinsAfter   = 15;
input bool   InpUseEmbeddedNews = true;

input group "===== Misc ====="
input ulong  InpMVPMagic        = 88260620;

input group "===== Parity (trade-level CSV vs C++ engine; OFF in live) ====="
input bool   InpExportParity    = false;    // ON in the MT5 tester to emit trades_<sym>_<tf>.csv for parity_diff.py

#endif // KKMON_INPUTS_MQH
