//+------------------------------------------------------------------+
//|  KK-MasterVP/Inputs.mqh - input schema.                           |
//|                                                                   |
//|  Two sections:                                                    |
//|   (1) USER-FACING inputs (shown in the dialog) - risk, profit-    |
//|       taking, trading hours, news, basic execution safety.        |
//|   (2) INTERNAL strategy parameters - kept as fixed globals (NOT   |
//|       `input`), so they do not appear in the dialog. Their values |
//|       are the locked, OOS- + MT5-validated XAUUSD M5 configuration |
//|       (PF 1.341, OOS PF 1.393; research/mastervp_parity). The EA   |
//|       runs fully tuned out-of-the-box; users only adjust the few   |
//|       knobs in section (1).                                        |
//|                                                                   |
//|  To re-expose the internals for research/MT5 sweeps, prepend       |
//|  `input ` to the section-(2) declarations (or revert this file).   |
//|  Names match the cpp_core kk::Params keys 1:1 for engine parity.   |
//+------------------------------------------------------------------+
#ifndef KKMVP_INPUTS_MQH
#define KKMVP_INPUTS_MQH

//==================================================================//
//   (1) USER-FACING INPUTS                                         //
//==================================================================//

input group "===== Risk per trade ====="
input int    InpRiskUnit        = 0;        // Risk basis: 0 = % of balance, 1 = fixed USD
input double InpRiskAccPct      = 1.0;      // Risk per trade as % of balance (used when basis = 0)
input double InpRiskUsd         = 180.0;    // Risk per trade in account currency (used when basis = 1)
input double InpMaxLot          = 0.0;      // Hard cap on lot size (0 = broker maximum)
input bool   InpSkipIfMinLotOverRisk = false; // Skip a trade if the broker min-lot would exceed your risk budget
input int    InpDeviationPoints = 200;      // Max entry slippage allowed, in points

input group "===== Account protection ====="
input double InpMaxDailyDDPct   = 10.0;     // Pause new trades if the day's loss reaches this % (0 = off)
input double InpDailyDDCooldownHrs = 12.0;  // Hours to stay paused after a daily-loss breach
input double InpMaxPeakDDPct    = 0.0;      // Halt trading if total drawdown reaches this % (0 = off)

input group "===== Profit taking ====="
input double InpTp1ClosePct     = 0.0;      // % of the position to bank at the first target (0 = bank nothing, let the runner work)
input bool   InpBeAfterTp1      = true;     // Move stop to break-even once the first target is reached

input group "===== Trading hours to avoid ====="
input int    InpBrokerGMTOffset = 10;       // Analysis reference tz (UTC + this) the sessions/blocked-hours were tuned in. NOT your broker clock — that is auto-detected (TimeTradeServer-TimeGMT), so this works unchanged on any broker. Keep 10 for XAUUSD, 0 for BTCUSD; do NOT set it to your broker's offset.
input string InpBlockedHoursStr = "2,3,14"; // Hours to skip, expressed in the reference tz above (10 => these are UTC 16,17,04). Blank = trade all hours.

input group "===== News filter ====="
input bool   InpAvoidNews       = false;    // Block new entries around high-impact news releases
input int    InpNewsMinsBefore  = 15;       // Start of the blackout: minutes before an event
input int    InpNewsMinsAfter   = 15;       // End of the blackout: minutes after an event
input bool   InpUseEmbeddedNews = true;     // Use the built-in news calendar when no custom file is supplied

input group "===== Execution safety ====="
input double InpMaxSpreadPips    = 0.0;     // Refuse entries when spread is wider than this (0 = off)
input int    InpMaxTradesPerSession = 4;    // Max new trades opened per session

input group "===== Misc ====="
input ulong  InpMVPMagic        = 5252510;  // Order magic number (use a unique value per running instance)


//==================================================================//
//   (2) INTERNAL STRATEGY PARAMETERS - fixed; not shown in dialog. //
//       Values = locked XAUUSD M5 configuration. Do not edit unless //
//       you are running a research sweep (then prepend `input `).   //
//==================================================================//

// ----- VP core -----
int    InpVpLookback     = 108;
int    InpVpBins         = 30;
double InpVaPct          = 70.0;
double InpMasterMult     = 4.0;     // master VP = round(lookback*mult) = 432 bars
int    InpAtrLen         = 14;
bool   InpAtrMt5Mode     = false;   // false = textbook Wilder ATR (Pine ta.atr = RMA)

// ----- Node engine -----
double InpNodeTouchAtr   = 0.05;
double InpNodeDecay      = 0.94;
double InpNodeNeutralBand= 0.15;
double InpNodeSaturation = 4.0;
bool   InpNodeGateEnabled= false;
bool   InpUsePriorBarVP  = false;
bool   InpBrkRequireFlow = false;
double InpSfpFlowMin      = 0.15;

// ----- Regime -----
int    InpEmaFast        = 24;
int    InpEmaSlow        = 194;
int    InpAdxLen         = 14;
double InpAdxTrendMin    = 22.0;
double InpDiSpreadMin     = 8.0;
double InpEmaSepAtr       = 0.25;

// ----- Breakout (the active entry path) -----
bool   InpEnableBreakout = true;
double InpBreakBufAtr      = 0.85;
double InpBreakMaxAtr       = 1000000;// anti-chase OFF
double InpRrBrk             = 1.8;
double InpSlAtrBrk          = 1.2;
bool   InpBrkVetoSfp        = false;

// ----- Reversion -----
bool   InpEnableReversion = true;
double InpRetestAtr         = 0.1;
double InpBodyPctMin        = 0.6;
double InpRrRev             = 1.2;
double InpSlAtrRev          = 1.5;

// ----- Impulse-thrust (fires ABOVE the vol ceiling; OFF) -----
bool   InpEnableImpulse        = false;
double InpImpulseCandleAtr     = 1.7;
double InpImpulseEntryBufAtr   = 0.4;
double InpImpulseNetMin        = 0.95;
double InpImpulseMaxDistAtr    = 2.5;
double InpImpulseRr            = 3.0;
int    InpImpulseTrendSlopeBars= 6;
int    InpImpulsePredictBars   = 10;
int    InpTfNetLook            = 50;
double InpTfNetWinAtr           = 1.5;

// ----- Extreme Reversion (XRev) - failed-breakout liquidity-sweep reversal (OFF) -----
bool   InpEnableExtremeReversion = false;
int    InpXRevHHLookback     = 5;
int    InpXRevFailLookback   = 14;
int    InpXRevMinClosesBeyond= 2;
int    InpXRevMaxClosesBeyond= 0;
int    InpXRevMinAgeBars     = 40;
double InpXRevBigCandleAtr   = 1.0;
double InpXRevBodyPctMin     = 0.4;
double InpXRevWickFrac       = 1.0;
double InpXRevNetDeltaMin    = 0.6;
bool   InpXRevUseNodeGate    = true;
double InpXRevSlAtr           = 0.7;
double InpXRevRrMin           = 2.0;
bool   InpXRevTpMpoc          = false;

// ----- Reversion TP-at-mPOC (OFF) -----
bool   InpRevTpMpoc           = false;

// ----- Exit -----
double InpTp1R            = 0.8;
double InpBeBufAtr        = 0.05;
bool   InpTrailRunner     = true;
double InpRunnerRr        = 10.0;
double InpTrailAtrMult    = 2.5;
// Per-entry-type trail override (-1 inherit InpTrailRunner / 0 fixed-TP no-trail / 1 force trail).
int    InpTrailBrk        = -1;
int    InpTrailRev        = -1;
int    InpTrailImp        = -1;
int    InpTrailXRev       = -1;

// ----- Profit manager (BE / progressive-trail / giveback / TP-extension / partial; all OFF in the lock) -----
bool   InpPmBeProtect       = false;
double InpPmBeTriggerR      = 1.0;
double InpPmBeBufferR       = 0.0;
bool   InpPmProgTrail       = false;
double InpPmProgTriggerR    = 1.0;
double InpPmProgIncrementR  = 0.5;
double InpPmProgStepR       = 0.10;
bool   InpPmGiveback        = false;
double InpPmGivebackArmR    = 2.0;
double InpPmGivebackCapFrac = 0.30;
bool   InpPmTpExtension     = false;
double InpPmTpExtProgress   = 0.90;
double InpPmTpExtAtrMult    = 1.0;
int    InpPmTpExtMax        = 5;
bool   InpPmPreBeStructure  = false;
double InpPmPreBeTriggerR   = 0.5;
double InpPmPreBeBuffer     = 0.0;
bool   InpPmPartialTp       = false;
double InpPmPartialTriggerR = 1.0;
double InpPmPartialFrac     = 0.5;

// ----- Risk-management limiters (extras; OFF) -----
double InpSoftBlockDDPct  = 0.0;
double InpSoftBlockLotMult= 0.55;
int    InpLossStreakCount = 0;
double InpLossStreakCooldownHrs = 4.0;

// ----- Safety / volatility -----
double InpMinAtrPct       = 0.0;
double InpMaxAtrPct        = 0.0;
double InpMinAtrTicks      = 40.0;
double InpMaxSpreadTp1Frac = 0.0;

// ----- Quality gates -----
bool   InpUseMtfAgree     = false;
bool   InpMtfHardVeto     = true;
bool   InpUseMomVeto      = false;
double InpRsiMidline      = 50.0;
int    InpRsiLen          = 14;

// ----- Sessions (reference tz = UTC + InpBrokerGMTOffset) -----
string InpAsiaSess        = "00:00-07:00";
string InpLdnSess         = "07:00-13:00";
string InpNySess          = "13:00-21:00";
bool   InpForceCloseSessNews = false;

// ----- Parity (dev only) -----
bool   InpExportParity    = false;

#endif // KKMVP_INPUTS_MQH
