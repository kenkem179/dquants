//+------------------------------------------------------------------+
//|  KK-MasterVP/Inputs.mqh - trading input schema (mirrors            |
//|  cpp_core kk::Params 1:1). Compiled-in DEFAULTS == the locked,     |
//|  OOS- + MT5-validated XAUUSD M5 lock (PF 1.341 / OOS 1.393),       |
//|  so the EA runs tuned out-of-the-box; load the shipped .set to     |
//|  override. Key names match the C++ Inp* keys exactly for parity.   |
//+------------------------------------------------------------------+
#ifndef KKMVP_INPUTS_MQH
#define KKMVP_INPUTS_MQH

// ----- KK_IN: visibility macro for the INTERNAL/DEBUG sweep build -----
// Strategy params that are deliberately HIDDEN in the curated personal/market
// build are declared `KK_IN <type> Inp...`. In the normal build KK_IN expands
// to nothing (-> plain hidden global, exactly as before, and invisible to the
// market-edition text transform which greps for a literal `input`). The
// internal sweep EA (KK-MasterVP-Debug.mq5) defines KK_DEBUG_EXPOSE_ALL first,
// flipping KK_IN to `input` so EVERY sweepable param shows in the Strategy
// Tester optimizer. Account-lock / expiry globals are NOT KK_IN (never exposed).
#ifdef KK_DEBUG_EXPOSE_ALL
   #define KK_IN input
#else
   #define KK_IN
#endif

input group "===== Risk sizing ====="
input int    InpRiskUnit        = 0;        // Risk basis: 0=% balance, 1=fixed USD, 2=min lot, 3=max lot
input double InpRiskAccPct      = 1.0;      // Risk per trade (% of balance) - used when Risk basis=0
input double InpRiskUsd         = 180.0;    // Risk per trade in USD - used when Risk basis=1
input double InpMaxLot          = 0.0;      // Lot-size cap (0 = broker maximum)
KK_IN int    InpDeviationPoints = 200;
input bool   InpSkipIfMinLotOverRisk = false; // Skip trade if even the min lot exceeds the risk limit

input group "===== Risk-management limiters ====="
input double InpMaxDailyDDPct   = 10.0;     // Daily drawdown % that pauses trading (0 = off)
input double InpDailyDDCooldownHrs = 12.0;  // Pause length (hours) after a daily-DD hit
input double InpSoftBlockDDPct  = 0.0;      // Account DD % to start trading smaller (0 = off)
input double InpMaxPeakDDPct    = 0.0;      // Account DD % that halts trading (0 = off)
input double InpSoftBlockLotMult= 0.55;     // Lot multiplier while trading smaller (e.g. 0.55 = 55%)
input int    InpLossStreakCount = 0;        // Consecutive losses that pause trading (0 = off)
input double InpLossStreakCooldownHrs = 4.0;// Pause length (hours) after a loss streak
// H10c session-giveback stop (default OFF; KK_IN = hidden in market, exposed in Debug for the optimizer).
KK_IN double InpGivebackPct     = 0.0;      // Halt new entries after handing back this % of the day's peak gain (0 = off)


// Sessions are configured + evaluated in UTC. The EA auto-detects the broker/VPS
// offset internally, so these UTC windows trade the same wall-clock hours on any
// broker. Windows below are the validated XAU-M5 lock (UTC, JST for reference):
//   Asia   : UTC 21:00-03:00  (JST 06:00-12:00 next day)
//   Europe : UTC 03:00-11:00  (JST 12:00-20:00)
//   US     : UTC 14:00-21:00  (JST 23:00-06:00 next day)   -> dead-zone UTC 11:00-14:00
KK_IN string InpAsiaSess        = "21:00-03:00";  // Asia session, UTC (JST 06:00-12:00 next day)
KK_IN string InpLdnSess         = "03:00-11:00";  // Europe session, UTC (JST 12:00-20:00)
KK_IN string InpNySess          = "14:00-21:00";  // US session, UTC (JST 23:00-06:00 next day)
input group "===== Trading Time Settings ====="
input string InpBlockedHoursStr = "4,16,17";      // No-trade UTC hours, e.g. "4,16,17" or "8,9-11" (empty = none)
input bool   InpForceCloseSessNews = false; // Close open trades at session end / before news
input bool   InpAvoidNews       = false;    // Block new entries around high-impact news
input int    InpNewsMinsBefore  = 15;       // News blackout: minutes before the event
input int    InpNewsMinsAfter   = 15;       // News blackout: minutes after the event
KK_IN bool   InpUseEmbeddedNews = true;     // fall back to the compiled-in calendar if no CSV

//input group "===== Master Volume Profile Settings ====="
KK_IN int    InpVpLookback     = 108;     // Local VP window (bars)
KK_IN int    InpVpBins         = 30;
KK_IN double InpVaPct          = 70.0;
KK_IN double InpMasterMult     = 4.0;     // master VP = round(lookback*mult) = 432 bars (XAUUSD M5 lock)
KK_IN int    InpAtrLen         = 14;
KK_IN bool   InpAtrMt5Mode     = false;   // false = textbook Wilder ATR (Pine ta.atr = RMA)

//input group "===== Node engine ====="
KK_IN double InpNodeTouchAtr   = 0.05;
KK_IN double InpNodeDecay      = 0.94;
KK_IN double InpNodeNeutralBand= 0.15;
KK_IN double InpNodeSaturation = 4.0;
KK_IN bool   InpNodeGateEnabled= false;   // OFF = Pine-faithful baseline
// H12c node-absorption veto (default OFF): skip a breakout when the decayed VP node-net at the level being
// broken (VAH long / VAL short) is AGAINST the trade. One-sided <Min cut (autopsy PASS; do NOT sweep Min).
KK_IN bool   InpEnableNodeAbsorbVeto = false;
KK_IN double InpNodeAbsorbVetoMin    = 0.0;
KK_IN bool   InpUsePriorBarVP  = false;
KK_IN bool   InpBrkRequireFlow = false;
KK_IN double InpSfpFlowMin      = 0.15;

//input group "===== Regime ====="
KK_IN int    InpEmaFast        = 24;
KK_IN int    InpEmaSlow        = 194;
KK_IN int    InpAdxLen         = 14;
KK_IN double InpAdxTrendMin    = 22.0;
KK_IN double InpDiSpreadMin     = 8.0;
KK_IN double InpEmaSepAtr       = 0.25;

//input group "===== Breakout (the active entry path) ====="
KK_IN bool   InpEnableBreakout = true;
KK_IN double InpBreakBufAtr      = 0.85;     // swept (S1)
KK_IN double InpBreakMaxAtr       = 1000000;// anti-chase OFF - swept (Q2): capping hurts on this feed
KK_IN double InpRrBrk             = 1.8;
KK_IN double InpSlAtrBrk          = 1.2;    // swept (S4)
KK_IN bool   InpBrkVetoSfp        = false;

input group "===== Reversion ====="
input bool   InpEnableReversion = true;     // Enable mean-reversion entries
KK_IN double InpRetestAtr         = 0.1;
KK_IN double InpBodyPctMin        = 0.6;
KK_IN double InpRrRev             = 1.2;
KK_IN double InpSlAtrRev          = 1.5;

//input group "===== Impulse-thrust (the Monster delta; fires ABOVE the vol ceiling) (OFF) ====="
// A single decisive thrust candle that fires ONLY in the high-vol band the base ceiling
// (InpMaxAtrPct) vetoes, so impulse and the base breakout/reversion never compete on the same bar.
// OFF by default => MasterVP byte-identical to the locked base. Was the sole entry-model delta of the
// (now-removed) KK-MasterVP-Monster edition; defaults = that edition's WF-locked BTCUSD-M3 values.
// NOTE: impulse needs InpMaxAtrPct>0 (the ceiling it fires above) AND M1 history (M1 net tick vol).
KK_IN bool   InpEnableImpulse        = false;  // master toggle for the impulse path
KK_IN double InpImpulseCandleAtr     = 1.7;    // min thrust-bar range (h-l) in ATR
KK_IN double InpImpulseEntryBufAtr   = 0.4;    // min close beyond master VAH/VAL in ATR
KK_IN double InpImpulseNetMin        = 0.95;   // min one-sided M1 near-price net tick volume
KK_IN double InpImpulseMaxDistAtr    = 2.5;    // anti-chase vs the PREDICTED edge in ATR; 0 = off
KK_IN double InpImpulseRr            = 3.0;    // impulse TP RR (inert while the trail is ON)
KK_IN int    InpImpulseTrendSlopeBars= 6;      // master-POC slope lookback (bars)
KK_IN int    InpImpulsePredictBars   = 10;     // bars aged out for the predicted master VP; 0 = current
KK_IN int    InpTfNetLook            = 50;     // M1 net: bars summed for the near-price net
KK_IN double InpTfNetWinAtr          = 1.5;   // M1 net: near-price window half-width in ATR

//input group "===== Extreme Reversion (XRev) - failed-breakout liquidity-sweep reversal ====="
// A failed breakout above master VAH that SWEEPS the recent swing-high then snaps back BELOW mVAH
// on a big sell-flow candle = trapped-breakout SHORT toward mVAL (long mirrors at mVAL). OFF by
// default => EA byte-identical to the locked base. Engine sweeps: additive HELP on M3 (BTC+XAU),
// slight HURT on XAU M5; tiny sample (rare setup) - MT5-confirm before trusting (BTC esp.).
KK_IN bool   InpEnableExtremeReversion = false;  // master toggle (OFF = base unchanged)
KK_IN int    InpXRevHHLookback     = 5;     // N: swing-high/low sweep level lookback
KK_IN int    InpXRevFailLookback   = 14;    // M: window for the failed-acceptance count
KK_IN int    InpXRevMinClosesBeyond= 2;     // min closes beyond mVAH in M (trapped positioning)
KK_IN int    InpXRevMaxClosesBeyond= 0;     // cap to exclude a real sustained breakout; 0 = off
KK_IN int    InpXRevMinAgeBars     = 40;    // min bars since the opposite-edge cross (aged round-trip)
KK_IN double InpXRevBigCandleAtr   = 1.0;   // rejection-bar range >= x*ATR (keep <=0.6 per OOS; 1.0 overfits)
KK_IN double InpXRevBodyPctMin     = 0.4;   // body fraction of range
KK_IN double InpXRevWickFrac       = 1.0;   // sweep-tail wick >= x*body (the strongest discriminator)
KK_IN double InpXRevNetDeltaMin    = 0.6;   // near-price node net magnitude (sell/buy-dominated flow)
KK_IN bool   InpXRevUseNodeGate    = true;  // require selling/absorption at mVAH
KK_IN double InpXRevSlAtr           = 0.7;  // SL distance above the swept high
KK_IN double InpXRevRrMin           = 2.0;  // min RR (entry->target vs SL) to take the trade
KK_IN bool   InpXRevTpMpoc          = false;// XRev TP = master POC (full bank, humble RR) vs far edge

//input group "===== Reversion TP-at-mPOC (full bank, humble RR) ====="
KK_IN bool   InpRevTpMpoc           = false;// base reversion TP = master POC instead of rr_rev multiple

input group "===== Exit ====="
input double InpTp1R            = 0.8;    // First target distance (x risk)
input double InpTp1ClosePct     = 0.0;    // % of position to bank at first target (0=off, e.g. 20=close 20%)
input bool   InpBeAfterTp1      = true;   // Move stop to break-even after the first target
input double InpBeBufAtr        = 0.02;   // Break-even buffer (x ATR; lower=tighter)
input bool   InpTrailRunner     = true;   // Trail the runner to ride trends
input double InpRunnerRr        = 4.0;    // Runner take-profit cap (x risk)
input double InpTrailAtrMult    = 2.75;    // Trail distance (x ATR; lower=tighter)

// Per-entry-type trail override (tri-state: -1 inherit InpTrailRunner / 0 fixed-TP no-trail / 1 force trail).
// Lets reversion/XRev bank a fixed TP (e.g. mPOC via InpRevTpMpoc/InpXRevTpMpoc) while breakout keeps
// trailing. Default -1 everywhere => identical to the global flag => base byte-identical.
KK_IN int    InpTrailBrk        = -1;       // breakout path
KK_IN int    InpTrailRev        = -1;       // base reversion
KK_IN int    InpTrailImp        = -1;       // impulse-thrust path (active only when InpEnableImpulse)
KK_IN int    InpTrailXRev       = -1;       // extreme reversion (XRev)

//input group "===== Profit-lock ladder (ProfitManager; default OFF) ====="
// 1:1 mirror of cpp_core kk::common::pm_evaluate. Every toggle OFF => MvpProfitManager() returns the stop
// unchanged => the EA is byte-identical to its pre-ProfitManager behaviour. R is measured against the
// ORIGINAL risk captured at fill (g_riskOpen), NOT the moving stop. Composes tighten-only with BE+chandelier.
// (1) be_protect: at >= trigger_r CURRENT gain, move SL to entry + buffer_r*risk.
KK_IN bool   InpPmBeProtect       = false;
KK_IN double InpPmBeTriggerR      = 1.0;
KK_IN double InpPmBeBufferR       = 0.0;
// (2) prog_trail: SL->entry at trigger_r, then advance step_r per increment_r of EXTRA gain (smooth ratchet
//     that fills the 0.8R..chandelier dead zone — the "trail SL nicely to bank profit" behaviour).
// LOCKED 2026-06-26 (H9 MT5 optimizer): late-arm ladder ON. The master TOGGLE is a real `input` (user-facing
// in personal + Market builds, whitelisted) so traders can switch the auto profit-banking OFF and let winners
// run to the runner cap. The 3 tuning params stay HIDDEN KK_IN globals baked at the optimized lock values
// (Trigger 2.0R / Inc 0.75 / Step 0.2) — advanced internals, not exposed.
input bool   InpPmProgTrail       = true;   // Profit-lock trail: ratchet the stop up to bank a runner's gains (ON=lock; OFF=let it run to the cap)
KK_IN double InpPmProgTriggerR    = 2.0;
KK_IN double InpPmProgIncrementR  = 0.75;
KK_IN double InpPmProgStepR       = 0.20;
// (3) giveback: once PEAK gain (MFE) >= arm_r, keep >= (1-cap_frac) of peak locked as SL. Hard profit floor.
KK_IN bool   InpPmGiveback        = false;
KK_IN double InpPmGivebackArmR    = 2.0;
KK_IN double InpPmGivebackCapFrac = 0.30;
// (4) tp_extension: push final TP further while price nears it (needs trend signal; inert here = engine).
KK_IN bool   InpPmTpExtension     = false;
KK_IN double InpPmTpExtProgress   = 0.90;
KK_IN double InpPmTpExtAtrMult    = 1.0;
KK_IN int    InpPmTpExtMax        = 5;
// (5) pre_be_structure: tighten to a prior swing before BE (needs structure level; inert here = engine).
KK_IN bool   InpPmPreBeStructure  = false;
KK_IN double InpPmPreBeTriggerR   = 0.5;
KK_IN double InpPmPreBeBuffer     = 0.0;
// (6) partial_tp: one-shot fractional close once CURRENT gain >= trigger_r.
KK_IN bool   InpPmPartialTp       = false;
KK_IN double InpPmPartialTriggerR = 1.0;
KK_IN double InpPmPartialFrac     = 0.5;


KK_IN double InpMinAtrPct       = 0.0;      // ATR% band OFF
KK_IN double InpMaxAtrPct        = 0.0;
KK_IN double InpMinAtrTicks      = 40.0;    // Pine atrTicks floor (atr/mintick >= this)
KK_IN double InpMaxSpreadTp1Frac = 0.0;     // TP1 cost-clearance OFF
input group "===== Safety / volatility ====="
input int    InpMaxTradesPerSession = 4; // Max trades per session
input double InpMaxSpreadPips    = 0.0;     // Max spread (pips) allowed to enter (0 = off)


//input group "===== Quality gates (Pine has NEITHER) ====="
KK_IN bool   InpUseMtfAgree     = false;    // MTF EMA agreement gate OFF
KK_IN bool   InpMtfHardVeto     = true;     // (semantics when MTF on; inert while off)
KK_IN bool   InpUseMomVeto      = false;    // RSI momentum veto OFF
KK_IN double InpRsiMidline      = 50.0;
KK_IN int    InpRsiLen          = 14;


//input group "===== Misc ====="
KK_IN ulong  InpMVPMagic        = 5252510;

input group "===== Log Trade Details to CSV  ====="
input bool   InpExportParity    = false;    // Log each closed trade to a CSV file

// ===== DEPLOYMENT / OPS (Layer 4, live MT5 only - inert in Tester) =====
// These have no C++ engine analog, so they never affect parity or the locked
// backtest. All default OFF/empty => MasterVP byte-identical to the lock.

input group "===== Account Risk Guardian (D1; cross-EA, live only) ====="
input bool   InpGuardEnable          = false; // Enable the prop account risk guardian
input double InpGuardDailyLossPct    = 4.0;   // Daily loss limit (% of day-start equity)
input double InpGuardOverallDDPct    = 8.0;   // Max overall drawdown limit (%)
input double InpGuardBufferPct       = 0.5;   // Act this many % BEFORE each line (safety margin)
input int    InpGuardDDAnchor        = 0;     // Max-DD anchor: 0=trailing peak, 1=initial balance
input double InpGuardManualDayAnchor = 0.0;   // Manual day-start equity anchor (0 = auto/reconstruct)
input bool   InpGuardFlatten         = true;  // On breach: true=close all positions, false=block new only

input group "===== Live trade CSV log (D2; live only) ====="
input bool   InpLiveTradeCsv         = false; // Append each closed trade to KKTrades_<EA>_<symbol>_<login>.csv

input group "===== Notifications (D3; live only) ====="
input int    InpNotifyChannel        = 0;     // 0 None 1 Email 2 Discord 3 Telegram 4 Email+Disc 5 Email+TG 6 Disc+TG 7 All
input int    InpNotifyMode           = 1;     // 1 Full, 2 Simplified (prop-safe: symbol+action+result only)
input string InpDiscordWebhookUrl    = "";    // Discord webhook URL
input string InpTelegramBotToken     = "";    // Telegram bot token
input string InpTelegramChatId       = "";    // Telegram chat ID (group IDs are negative)

// ----- Account lock (hidden internals; NOT inputs) -----
// Empty by default = runs on any account. The per-account release script bakes
// one (id, server) pair in to lock a build to a single MT5 account. A login
// number is only unique within a server, so both are pinned together.
string ALLOWED_ACCOUNT_ID     = "";  // Internal: empty=any account
string ALLOWED_ACCOUNT_SERVER = "";  // Internal: empty=any server

// ----- Access expiry (hidden internals; NOT an input) -----
// Empty = never expires. The per-account release script bakes a date
// ("YYYY.MM.DD 23:59:59") in to time-limit a build. Enforced on broker SERVER
// time (KK_AccessExpired in KK-Common/AccountLock.mqh): once past, the EA stops
// opening new trades and Alerts "Expired Access" (open positions stay managed).
string ACCESS_EXPIRY          = "";  // Internal: empty=perpetual; baked per-account

#endif // KKMVP_INPUTS_MQH
