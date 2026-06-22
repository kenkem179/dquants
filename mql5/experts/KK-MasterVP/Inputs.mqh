//+------------------------------------------------------------------+
//|  KK-MasterVP/Inputs.mqh — trading input schema (mirrors            |
//|  cpp_core kk::Params 1:1). Compiled-in DEFAULTS == the locked,     |
//|  OOS-validated XAUUSD-M3 preset (research/mastervp_parity sweeps), |
//|  so the EA runs tuned out-of-the-box; load the shipped .set to     |
//|  override. Key names match the C++ Inp* keys exactly for parity.   |
//+------------------------------------------------------------------+
#ifndef KKMVP_INPUTS_MQH
#define KKMVP_INPUTS_MQH

input group "===== VP core ====="
input int    InpVpLookback     = 120;     // local VP window (bars) — swept (S8b); long-window OOS plateau
input int    InpVpBins         = 30;
input double InpVaPct          = 70.0;
input double InpMasterMult     = 4.0;     // master VP = round(lookback*mult) = 480 bars; OOS PF 1.114 (float; 0.5-step swept)
input int    InpAtrLen         = 14;
input bool   InpAtrMt5Mode     = false;   // false = textbook Wilder ATR (Pine ta.atr = RMA)

input group "===== Node engine ====="
input double InpNodeTouchAtr   = 0.05;
input double InpNodeDecay      = 0.94;
input double InpNodeNeutralBand= 0.15;
input double InpNodeSaturation = 4.0;
input bool   InpNodeGateEnabled= false;   // OFF = Pine-faithful baseline
input bool   InpUsePriorBarVP  = false;
input bool   InpBrkRequireFlow = false;
input double InpSfpFlowMin      = 0.15;

input group "===== Regime ====="
input int    InpEmaFast        = 24;
input int    InpEmaSlow        = 194;
input int    InpAdxLen         = 14;
input double InpAdxTrendMin    = 22.0;
input double InpDiSpreadMin     = 8.0;
input double InpEmaSepAtr       = 0.25;

input group "===== Breakout (the active entry path) ====="
input bool   InpEnableBreakout = true;
input double InpBreakBufAtr      = 0.7;     // swept (S1)
input double InpBreakMaxAtr       = 1000000;// anti-chase OFF — swept (Q2): capping hurts on this feed
input double InpRrBrk             = 1.8;
input double InpSlAtrBrk          = 1.0;    // swept (S4)
input bool   InpBrkVetoSfp        = false;

input group "===== Reversion (OFF) ====="
input bool   InpEnableReversion = false;
input double InpRetestAtr         = 0.1;
input double InpBodyPctMin        = 0.6;
input double InpRrRev             = 1.2;
input double InpSlAtrRev          = 1.5;

input group "===== Impulse-thrust (the Monster delta; fires ABOVE the vol ceiling) (OFF) ====="
// A single decisive thrust candle that fires ONLY in the high-vol band the base ceiling
// (InpMaxAtrPct) vetoes, so impulse and the base breakout/reversion never compete on the same bar.
// OFF by default => MasterVP byte-identical to the locked base. Was the sole entry-model delta of the
// (now-removed) KK-MasterVP-Monster edition; defaults = that edition's WF-locked BTCUSD-M3 values.
// NOTE: impulse needs InpMaxAtrPct>0 (the ceiling it fires above) AND M1 history (M1 net tick vol).
input bool   InpEnableImpulse        = false;  // master toggle for the impulse path
input double InpImpulseCandleAtr     = 1.7;    // min thrust-bar range (h-l) in ATR
input double InpImpulseEntryBufAtr   = 0.4;    // min close beyond master VAH/VAL in ATR
input double InpImpulseNetMin        = 0.95;   // min one-sided M1 near-price net tick volume
input double InpImpulseMaxDistAtr    = 2.5;    // anti-chase vs the PREDICTED edge in ATR; 0 = off
input double InpImpulseRr            = 3.0;    // impulse TP RR (inert while the trail is ON)
input int    InpImpulseTrendSlopeBars= 6;      // master-POC slope lookback (bars)
input int    InpImpulsePredictBars   = 10;     // bars aged out for the predicted master VP; 0 = current
input int    InpTfNetLook            = 50;     // M1 net: bars summed for the near-price net
input double InpTfNetWinAtr           = 1.5;   // M1 net: near-price window half-width in ATR

input group "===== Extreme Reversion (XRev) — failed-breakout liquidity-sweep reversal (OFF) ====="
// A failed breakout above master VAH that SWEEPS the recent swing-high then snaps back BELOW mVAH
// on a big sell-flow candle = trapped-breakout SHORT toward mVAL (long mirrors at mVAL). OFF by
// default => EA byte-identical to the locked base. Engine sweeps: additive HELP on M3 (BTC+XAU),
// slight HURT on XAU M5; tiny sample (rare setup) — MT5-confirm before trusting (BTC esp.).
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

input group "===== Reversion TP-at-mPOC (full bank, humble RR; OFF) ====="
input bool   InpRevTpMpoc           = false;// base reversion TP = master POC instead of rr_rev multiple

input group "===== Exit ====="
input double InpTp1R            = 0.8;
input double InpTp1ClosePct     = 20.0;
input bool   InpBeAfterTp1      = true;
input double InpBeBufAtr        = 0.05;
input bool   InpTrailRunner     = true;     // ATR chandelier trail on runner (GLOBAL default)
input double InpRunnerRr        = 10.0;     // runner TP cap (effectively trail-to-exit)
input double InpTrailAtrMult    = 2.0;      // swept (S4)
// Per-entry-type trail override (tri-state: -1 inherit InpTrailRunner / 0 fixed-TP no-trail / 1 force trail).
// Lets reversion/XRev bank a fixed TP (e.g. mPOC via InpRevTpMpoc/InpXRevTpMpoc) while breakout keeps
// trailing. Default -1 everywhere => identical to the global flag => base byte-identical.
input int    InpTrailBrk        = -1;       // breakout path
input int    InpTrailRev        = -1;       // base reversion
input int    InpTrailImp        = -1;       // impulse-thrust path (active only when InpEnableImpulse)
input int    InpTrailXRev       = -1;       // extreme reversion (XRev)

input group "===== Risk sizing ====="
input int    InpRiskUnit        = 0;        // 0=%acct,1=USD,2=min,3=max
input double InpRiskAccPct      = 1.0;      // % balance risked/trade — swept (S6b lowest-DD plateau)
input double InpRiskUsd         = 180.0;    // used only when InpRiskUnit!=0
input double InpMaxLot          = 0.0;      // 0 = broker VOLUME_MAX
input int    InpDeviationPoints = 200;
input bool   InpSkipIfMinLotOverRisk = false;

input group "===== Risk-management limiters ====="
input double InpMaxDailyDDPct   = 10.0;     // daily-DD cap (predictive) — swept (S6b); plateau 8/10/12
input double InpDailyDDCooldownHrs = 12.0;  // cooldown armed on a daily-DD breach
input double InpMaxPeakDDPct    = 0.0;      // peak-DD halt OFF (curve-fits the train peak)
input double InpSoftBlockDDPct  = 0.0;      // soft-block OFF
input double InpSoftBlockLotMult= 0.55;
input int    InpLossStreakCount = 0;        // OFF — swept (S6b): streak limiter hurts PF
input double InpLossStreakCooldownHrs = 4.0;

input group "===== Safety / volatility ====="
input double InpMinAtrPct       = 0.0;      // ATR% band OFF
input double InpMaxAtrPct        = 0.0;
input double InpMinAtrTicks      = 40.0;    // Pine atrTicks floor (atr/mintick >= this)
input int    InpMaxTradesPerSession = 4;
input double InpMaxSpreadPips    = 0.0;     // spread gate OFF (0 = off)
input double InpMaxSpreadTp1Frac = 0.0;     // TP1 cost-clearance OFF

input group "===== Quality gates (Pine has NEITHER) ====="
input bool   InpUseMtfAgree     = false;    // MTF EMA agreement gate OFF
input bool   InpMtfHardVeto     = true;     // (semantics when MTF on; inert while off)
input bool   InpUseMomVeto      = false;    // RSI momentum veto OFF
input double InpRsiMidline      = 50.0;
input int    InpRsiLen          = 14;

input group "===== Sessions (chart-tz = UTC + offset; offset 10 matches the TV calibration) ====="
input int    InpBrokerGMTOffset = 10;       // hours ADDED to UTC to reach the session reference tz
input string InpAsiaSess        = "00:00-07:00";
input string InpLdnSess         = "07:00-13:00";
input string InpNySess          = "13:00-21:00";
input string InpBlockedHoursStr = "";       // low-liquidity veto, ref-tz hours: "8,16" or "9-11"
input bool   InpForceCloseSessNews = false; // Pine never force-closes on session exit

input group "===== News avoidance (live-safety overlay; CSV of UTC release times) ====="
input bool   InpAvoidNews       = false;    // ON = block NEW entries in the blackout window
input int    InpNewsMinsBefore  = 15;       // blackout starts N min before each high-impact event
input int    InpNewsMinsAfter   = 15;       // blackout ends N min after
input bool   InpUseEmbeddedNews = true;     // fall back to the compiled-in calendar if no CSV

input group "===== Misc ====="
input ulong  InpMVPMagic        = 5252510;

input group "===== Parity (trade-level CSV vs C++ engine; OFF in live) ====="
input bool   InpExportParity    = false;    // ON in the MT5 tester to emit trades_<sym>_<tf>.csv for parity_diff.py

#endif // KKMVP_INPUTS_MQH
