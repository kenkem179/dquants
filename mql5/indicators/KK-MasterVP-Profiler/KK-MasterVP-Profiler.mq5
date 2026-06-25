//+------------------------------------------------------------------+
//|                                        KK-MasterVP-Profiler.mq5  |
//|  Standalone master/local volume-profile + net-volume indicator.  |
//|                                                                  |
//|  Visual twin of kenkem-pine/kk-vp/KK-MasterVP-Monster.pine VP    |
//|  layer (f_vp value-area expansion, node-state engine, near-price |
//|  net tick volume, master histogram, predicted aged-out POC),     |
//|  upgraded with what only MT5 can do: the real broker tick stream |
//|  (CopyTicksRange) for true volume-at-price, tick-rule signed     |
//|  delta, time-at-price dwell, HVN structure rays and a            |
//|  POC-migration price projection.                                 |
//|                                                                  |
//|  Display only - contains no trading logic. Heavy work is gated   |
//|  to once per completed chart bar; per-tick work is O(bins) and   |
//|  throttled. Falls back to bar-feed math (exact Pine parity) when |
//|  the broker tick history is not available.                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, KenKem MasterVP Indicator"
#property link      "https://kenkem.biz"
#property version   "1.01"
#property description "KK-MasterVP Profiler - display-only volume-profile cockpit."
#property description "Shows master/local POC & value area, a net-flow histogram, EMA"
#property description "trend context and historical breakout setup markers (WON/LOST)."
#property description "Draws context only - it places no orders and gives no signals."
#property description "Educational tool only - not financial advice. Trading carries risk."
#property description "For more details, visit https://kenkem.biz"
#property indicator_chart_window
#property indicator_buffers 11
#property indicator_plots   9

// Trail buffers stay computed (the mPOC slope/regime read depends on them)
// but are hidden by default - flip a plot to DRAW_LINE in the Colors tab to
// inspect a trail without recompiling.
#property indicator_label1  "mPOC trail"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "mVAH trail"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "mVAL trail"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "POC trail (local)"
#property indicator_type4   DRAW_NONE

// EMA overlay (KenKem SuperBros twin) - colors/widths match the Pine plots:
// EMA25 yellow w1, EMA75 green w1, EMA100 sky blue w1, EMA200 purple w2.
#property indicator_label5  "EMA 25"
#property indicator_type5   DRAW_LINE
#property indicator_color5  C'255,235,59'
#property indicator_width5  1
#property indicator_label6  "EMA 75"
#property indicator_type6   DRAW_LINE
#property indicator_color6  C'76,175,80'
#property indicator_width6  1
#property indicator_label7  "EMA 100"
#property indicator_type7   DRAW_LINE
#property indicator_color7  C'135,206,235'
#property indicator_width7  1
#property indicator_label8  "EMA 200"
#property indicator_type8   DRAW_LINE
#property indicator_color8  C'156,39,176'
#property indicator_width8  2

// EMA zone ribbon (Pine bgcolor twin): thin fill between EMA25 and EMA75,
// shown only while the FULL stack is aligned (25>75>100>200 bull / inverted
// bear) - exactly the Pine bullishZone/bearishZone condition.
#property indicator_label9  "EMA zone"
#property indicator_type9   DRAW_COLOR_HISTOGRAM2
#property indicator_color9  C'0,100,45',C'110,28,28'
#property indicator_width9  1

// Shared KK access guard (account lock + expiry). Same module the EAs use; the
// per-account release script bakes the hidden globals below. See AccountLock.mqh.
#include "../../experts/KK-Common/AccountLock.mqh"

//+------------------------------------------------------------------+
//| Inputs - defaults mirror KK-MasterVP-Monster.pine                |
//+------------------------------------------------------------------+
input group "Trade Setups (breakout)"
input bool   InpSetShow        = true;  // Show past breakout setups (Entry/SL/TP1/TP2 + WON/LOST history)
input int    InpSetLookback    = 1800;   // How many bars back to scan for past setups
input int    InpSetKeep        = 12;    // Max setups shown at once (oldest removed first)
double InpSetEntryBufAtr = 0.85;  // LOCK: confirmed close must clear master VAH/VAL by this x ATR (EA InpBreakBufAtr=0.85)
double InpSetNetMin      = 0.80;  // LOCK: min same-direction near-price net at the signal bar (the EA trades 0.80)
double InpSetSlAtrMult   = 1.2;   // LOCK: SL = close -/+ this x ATR (EA InpSlAtrBrk=1.2)
input double InpSetTp1R        = 0.8;   // First target distance, in risk units (R). Reaching it before SL = WON
input double InpSetTp2R        = 1.8;   // Second target distance, in risk units (R)
input double InpSetRiskPct     = 1.0;   // Risk % used to show an example lot on the entry label (display only - places no trades)
input bool   InpSetShowRejects = false; // Also mark setups that were skipped, with a short reason
input bool   InpSetBeRatchet   = false; // Illustrate the stop moving to break-even once a setup is in profit (OFF = plain TP1-vs-SL)
input bool   InpSetEmaFilter     = false; // Only show setups that agree with the EMA trend
//--- hidden (fixed): lock mirrors (anti-chase off, pure close-based SL) + BE/reject fine knobs ---
double InpSetMaxDistAtr  = 0.0;   // Anti-chase cap (x ATR); 0 = off - matches the lock (EA InpBreakMaxAtr huge = no cap)
double InpSetSlBufAtr    = 0.0;   // Edge-anchor SL term; 0 = pure close-based SL like the EA
int    InpSetRejKeep     = 20;    // Max rejection markers kept on the chart (newest first)
double InpSetBeTrigR     = 0.3;   // Profit (R) a setup must reach before the BE ratchet arms
double InpSetBeBufAtr    = 0.05;  // BE stop offset (x ATR) in the profit direction

//--- hidden (fixed): node-state internals ---
double InpNodeTouchAtr    = 0.05;  // Node touch distance (x ATR): a bar "touches" a bin within this of its center
double InpNodeDecay       = 0.94;  // Per-bar node memory decay (~11-bar half-life at 0.94)
double InpNodeNeutralBand = 0.15;  // |net| at/below this = balanced (no buy/sell dominance)
double InpNodeSaturation  = 4.0;   // Touch count at/over which a balanced node counts as DEAD (absorbed)

//input group "Net Tick Volume (multi-TF)"
double InpNetWinAtr     = 1.5;   // Near-price window half-width (x ATR) for the net reads
bool   InpWeightedNet   = true;  // ON: chart-TF net weights each bin by HVN/MED/LVN tier; OFF: flat weights
double InpVerdictAtr    = 1.2;   // CENTER "Net" verdict window half-width (x ATR) + near-vol HIGH/LOW magnitude window (MUST match the ring at RebuildAll)
//--- hidden (fixed): tier weights, verdict reach + flicker, net lookbacks ---
int    InpTfNetLook      = 50;    // Bars summed per timeframe for the near-price net read
int    InpNearVolLook    = 100;   // Bars of near-volume history for the HIGH/med/LOW magnitude rank
double InpWHvn           = 1.5;   // Tier weight for high-volume bins (> 66% of near-window max)
double InpWMvn           = 1.0;   // Tier weight for mid-volume bins
double InpWLvn           = 0.5;   // Tier weight for low-volume bins (< 33% of near-window max)
double InpVerdictInnerAtr= 1.2;   // over/under NEAR reach (x ATR) into the OPPOSITE zone (overlap -> stability)
double InpVerdictOuterAtr= 1.8;   // over/under FAR reach (x ATR) into its OWN zone
int    InpVerdictBalPct  = 15;    // |net| percent below which the verdict reads balanced
int    InpVerdictHoldSec = 4;     // Seconds a flipped direction must HOLD before the headline arrow changes

int    InpAtrLen          = 14;    // ATR period used for all ATR-scaled distances
int    InpNearStrongPct = 70;    // Percentile at/over which near volume tags HIGH
int    InpNearWeakPct   = 35;    // Percentile at/under which near volume tags LOW
double InpHvnPct        = 70.0;  // Bin-volume percentile (vs occupied bins) at/over which a bin is an HVN
double InpLvnPct        = 35.0;  // Bin-volume percentile at/under which a bin is an LVN (vacuum, fast travel)

//--- hidden (fixed): structure + projection internals ---
bool   InpShowHvnLines  = false; // Draw marker stubs at high-volume-node bins ON the profile zone (off: the histogram rows already tell the story)
bool   InpShowProjection = true; // Draw the bias arrow toward the projected magnet (next HVN / POC / predicted edge)
double InpBiasShowMin   = 0.50;  // Min |bias score| before the arrow is drawn ON the chart - weaker reads are noise and live only in the table
int    InpSlopeBars     = 10;    // Master-POC slope lookback (bars), ATR-normalized - the regime read
double InpTrendSlopeMin = 0.30;  // |master-POC slope| (x ATR over the slope lookback) at/over which the panel headline upgrades UP/DOWN to TREND
//--- hidden (fixed) ---
int    InpMaxHvnLines    = 4;     // Max HVN rays drawn (strongest first)
double InpBiasBalanced   = 0.15;  // |bias score| below which the projection is "rotation back to POC"
double InpPocStableAtr   = 0.2;   // Predicted-vs-current master-POC gap (x ATR) at/under which the POC is STABLE

// input group "Execution Health"
bool   InpShowExecRow   = true;  // Panel row: CURRENT spread + tape speed vs their averages over the master VP window (100% = average conditions)
//--- hidden (fixed): warn/alarm thresholds ---
int    InpExecWindowSec  = 60;    // Seconds of recent ticks behind the CURRENT spread/speed reads
int    InpExecWarnPct    = 140;   // Ratio percent at/over which a reading colors orange (elevated)
int    InpExecAlarmPct   = 250;   // Ratio percent at/over which a reading colors red (hostile fills likely)

input group "Visuals"
input int    InpVpLookback   = 100;   // Volume-profile window (bars); the master profile covers this x the multiplier
input bool   InpShowMasterLines = true;  // Show master profile levels: POC + value-area high/low (mPOC/mVAH/mVAL)
input bool   InpShowLocalLines  = true;  // Show local (recent) profile levels (lPOC/lVAH/lVAL)
input bool   InpShowHistogram   = true;  // Show the volume histogram (green/red = recent buy/sell lean)
input bool   InpHistFront       = true;  // Draw the histogram in front of the candles (OFF = behind them)
bool   InpShowPredictedPoc = true; // Predicted master POC line (age-out preview)
bool   InpShowPanel       = true;  // Compact top-right telemetry card: feed, net M1/chart/M5/M15, ATR%/slope, POC stability, bias
bool   InpShowVerdict     = true;  // Near-price verdict tag above the histogram
double InpAtrRulerMult    = 1.0;   // Guide lines at live price +/- this x ATR; 0 = hidden
//--- hidden (fixed): histogram layout / trail history ---
int    InpHistShiftBars  = 70;    // Bars LEFT of the current candle the histogram zone starts (keeps the live price area clear)
int    InpHistWidthBars  = 25;    // Max histogram row length (bars, growing rightward)
int    InpVerdLabelGapBars = 6;   // Gap (bars) left of the histogram baseline for the Net Vol / over / under labels
int    InpTrailBars      = 1500;  // How many recent bars get the POC/VAH/VAL trail plots (history cost cap)

// input group "Master Volume Profile Core"
int    InpVpBins       = 75;    // LOCK: node bins for POC/VAH/VAL + node-state math (EA InpVpBins=30)
double InpMasterMult   = 4.0;   // Master window = round(local x this)
bool   InpUseRealTicks = false; // OFF (default): bar tick_volume at hlc3 (bar-feed), no CopyTicksRange flicker. ON: real broker tick stream (higher-res but the large master window can fail to fetch and flip resolution)
bool   InpHistTickDelta = true;  // HYBRID (when InpUseRealTicks=OFF): bar-feed structure (stable rows) + REAL tick-rule signed-delta tint on the recent window; bins beyond coverage fall back to bar-direction net
bool   InpHistRecency  = true;  // ON: weight ticks by the node decay per bar of age (TV twin look - RECENT flow dominates); OFF: classic undecayed volume profile
bool   InpHistNetScale = true;  // ON: green/red slice scaled by the strongest bin imbalance (visible on any TF); OFF: raw delta share (near-invisible on high TFs)
//--- hidden (fixed): display resolution / tick-delta internals ---
int    InpHistBins       = 240;   // Display bins - resolution of the drawn histogram rows (higher = thinner/finer rows)
int    InpHistTickBars   = 200;   // Hybrid tick-delta lookback cap (bars) - kept short so the fetch stays reliable
int    InpDwellCapSec    = 120;   // Cap (seconds) on the per-tick dwell credit so session gaps cannot dominate time-at-price
// hard coded params
double InpVaPct        = 70.0;  // Value-area percent of total volume around the POC
int    InpPredictBars  = 10;    // Predicted-POC age-out (bars): drop the oldest N bars to preview the next master POC/VAH/VAL; 0 = off

input group "EMA Overlay"
input bool   InpShowEmas = true;  // Show the four EMA trend lines
input int    InpEma1Len  = 24;    // Fast EMA period
input int    InpEma2Len  = 72;    // Medium EMA period
int    InpEma3Len  = 96;   // EMA 3 period (sky blue) - visual only, no EA equivalent
input int    InpEma4Len  = 194;   // Slow EMA period
input bool   InpShowEmaZone = true; // Shade a buy/sell zone between the fast & medium EMA when all EMAs line up

input group "Chart Theme"
input bool   InpApplyTheme = true;  // Apply a dark, easy-to-read chart theme on attach (OFF = keep your own colors)

//+------------------------------------------------------------------+
//| Types + globals                                                  |
//+------------------------------------------------------------------+
struct VPResult {
   double poc, vah, val, hi, lo;
   bool   valid;
};
struct NodeState {
   int    state;      // +1 buy-dominant, -1 sell-dominant, 0 balanced/absorbed
   double net;        // (buy-sell)/(buy+sell)
   double touch;      // decayed touch count
   bool   absorbed;   // DEAD node: saturated touches + balanced net
};

#define OBJPFX "KKVPP_"

// ----- Access lock (hidden internals; NOT inputs) -----
// All empty by default = runs on any account, never expires. The per-account
// release script bakes these in: ALLOWED_ACCOUNT_ID/SERVER lock the indicator to
// one login@server; ACCESS_EXPIRY ("YYYY.MM.DD 23:59:59") time-limits it. On a
// wrong account OnInit aborts; on expiry OnCalculate/OnTimer stop ALL calculation
// (clear levels/objects) and Alert "Expired Access". Enforced on broker server time.
string ALLOWED_ACCOUNT_ID     = "";  // Internal: empty=any account
string ALLOWED_ACCOUNT_SERVER = "";  // Internal: empty=any server
string ACCESS_EXPIRY          = "";  // Internal: empty=perpetual; baked per-account
bool   g_blocked        = false;     // true once access is denied/expired -> no calculation
bool   g_expiredAlerted = false;     // Alert("Expired Access") fired once

double BufMPoc[], BufMVah[], BufMVal[], BufLPoc[];
double BufEma1[], BufEma2[], BufEma3[], BufEma4[];
double BufZoneA[], BufZoneB[], BufZoneC[];   // EMA zone ribbon (two edges + color index)

int  g_hEma[4] = {INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE};
bool g_emaSynced = false;   // false until every EMA buffer has a full history copy
ulong g_tickRetryMs = 0;    // last tick-feed retry attempt (ms tick count)
int    g_feedLogged  = -1;  // last feed state written to the Experts log (-1 none, 0 bar, 1 tick)
string g_tickFailWhy = "";  // why the last real-tick build fell back to the bar feed

// Detected trade setups - rebuilt deterministically from bar data on every
// new bar (an indicator owns no positions, so history = a stateless rescan,
// exactly how the Pine strategy reproduces its trade list after reload).
struct TradeSetup {
   datetime t0;       // signal bar open time
   datetime tEnd;     // resolution bar open time (0 while still open)
   int      dir;      // +1 long, -1 short
   int      status;   // 0 open, 1 won (TP1 before SL), 2 lost, 3 break-even (ratchet stop-out)
   double   entry, sl, tp1, tp2;
   double   edge;     // master edge broken at the signal bar (VAH long / VAL short)
};
TradeSetup g_setups[];
int        g_nSetups = 0;

// Rejected triggers - the "decision was made, here is why NOT" telemetry
// (the chart analog of the EA's EnterOrSkipTrade isEntering=false log line).
struct SetupReject {
   datetime t;        // trigger bar open time
   int      dir;      // +1 long trigger, -1 short trigger
   double   py;       // marker price (above the high / below the low)
   string   why;      // short reason tag
};
SetupReject g_rejects[];
int         g_nRejects = 0;

void AddReject(datetime t, int dir, double py, string why) {
   if(g_nRejects >= ArraySize(g_rejects)) ArrayResize(g_rejects, g_nRejects + 32);
   g_rejects[g_nRejects].t   = t;
   g_rejects[g_nRejects].dir = dir;
   g_rejects[g_nRejects].py  = py;
   g_rejects[g_nRejects].why = why;
   g_nRejects++;
}

ENUM_TIMEFRAMES g_tf = PERIOD_CURRENT;
double g_mintick   = 0.0;
int    g_digits    = 2;
int    g_bins      = 40;   // validated copies of the inputs
int    g_histBins  = 50;
int    g_localLen  = 50;
int    g_masterLen = 150;

int g_hAtrChart = INVALID_HANDLE;
int g_hAtrM1    = INVALID_HANDLE;
int g_hAtrM5    = INVALID_HANDLE;
int g_hAtrM15   = INVALID_HANDLE;

// Node-state engine (vpBins grid over the committed master range)
double g_nodeBuy[], g_nodeSell[], g_nodeTouch[];
double g_mLo = 0.0, g_mHi = 0.0, g_mStep = 0.0;
datetime g_nodeBarTime = 0;

// Display histogram (histBins grid over the same master range)
double g_dLo = 0.0, g_dHi = 0.0, g_dStep = 0.0;
double g_binBuy[], g_binSell[], g_binTimeMs[];
// Hybrid net-delta tint: real tick-rule signed volume over the recent window,
// binned on the SAME grid as the bar-feed structure. Drives only the bright
// delta slice + near readout when InpHistTickDelta is on and structure is bar.
double g_binTBuy[], g_binTSell[], g_binTDwell[];
bool   g_binTickOk = false;   // true when the tick-delta pass populated this bar
// Forming-bar live overlay (kept separate so committed state never repaints)
double g_liveBuy[], g_liveSell[], g_liveTimeMs[];
ulong  g_liveLastMs = 0, g_liveLastTickMs = 0;
double g_livePrevMid = 0.0;
int    g_liveDir = 0, g_liveLastBin = -1;

// Rolling master tick cache (fetch only the new tail each bar)
MqlTick g_ticks[];
ulong   g_tkFrom = 0, g_tkTo = 0;
bool    g_tkCached = false;
bool    g_tickFeed = false;   // true when the current profile was built from real ticks

VPResult g_master, g_local, g_pred;

// Near-volume magnitude history (newest at [0], strict-less percentrank)
double g_nearRing[];
int    g_nearCount = 0;

// Headline-verdict flip hysteresis: the displayed arrow only changes after
// the candidate direction has held for InpVerdictHoldSec.
int   g_verdShownDir = 0;
int   g_verdCandDir  = 0;
ulong g_verdCandSince = 0;

// Per-bar context for the panel/projection
double g_netM1 = 0, g_netM5 = 0, g_netM15 = 0, g_netChartNode = 0, g_netChartTick = 0;
bool   g_hasM1 = false, g_hasM5 = false, g_hasM15 = false;
double g_slopeNorm = 0.0;
bool   g_slopeKnown = false;
double g_bias = 0.0, g_biasTarget = 0.0;
string g_biasKind = "";

// Execution-health baselines over the master tick window (per-bar rebuild)
// + a rolling live sample tape for the CURRENT spread/speed reads.
double g_execBaseSpread = 0.0;   // mean ask-bid (price units) across the window
double g_execBaseSpeed  = 0.0;   // mean |mid change| per second (gap-capped)
double g_exsMs[], g_exsSpr[], g_exsMid[];
int    g_exsN = 0;
int    g_execRowX = 0, g_execRowY = -1;   // panel slot the live exec row writes into

datetime g_lastBarTime = 0;
ulong    g_lastUiTick  = 0;
int      g_rt = 0;            // rates_total snapshot for buffer-history reads

// Palette (Pine hex twins)
const color COL_LOCAL    = C'255,167,38';   // #FFA726 (local VP levels)
const color COL_MASTER   = C'0,229,255';    // light cyan - master KEY levels, reads bright on dark and is unmistakable vs the orange local set
const color COL_BUY      = C'67,160,71';    // #43A047
const color COL_SELL     = C'229,57,53';    // #E53935
const color COL_BUY_DIM  = C'27,77,33';
const color COL_SELL_DIM = C'96,26,24';
const color COL_GRAY     = C'130,130,130';
const color COL_GRAY_DIM = C'70,70,70';
const color COL_HVN      = C'255,213,79';
const color COL_UP_TXT   = C'76,175,80';
const color COL_DN_TXT   = C'239,83,80';

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
int    ClampI(int v, int lo, int hi)       { return (int)MathMax(lo, MathMin(hi, v)); }
double ClampD(double v, double lo, double hi) { return MathMax(lo, MathMin(hi, v)); }
string SymUp()   { return ShortToString(0x25B2); }   // up triangle
string SymDn()   { return ShortToString(0x25BC); }   // down triangle

double AtrFromHandle(int handle, int shift) {
   if(handle == INVALID_HANDLE) return 0.0;
   double v[];
   if(CopyBuffer(handle, 0, shift, 1, v) != 1) return 0.0;
   return (v[0] > 0.0 && v[0] != EMPTY_VALUE) ? v[0] : 0.0;
}
double AtrAt(int shift) { return AtrFromHandle(g_hAtrChart, shift); }
double AtrTfAt(ENUM_TIMEFRAMES tf, int shift) {
   int h = (tf == PERIOD_M1)  ? g_hAtrM1
         : (tf == PERIOD_M5)  ? g_hAtrM5
         : (tf == PERIOD_M15) ? g_hAtrM15
         : (tf == g_tf)       ? g_hAtrChart : INVALID_HANDLE;
   return AtrFromHandle(h, shift);
}

// Percentile threshold over the occupied (vol > 0) bins, pct in [0,100].
double PercentileOf(double &vals[], int n, double pct) {
   if(n <= 0) return 0.0;
   double tmp[];
   ArrayResize(tmp, n);
   for(int i = 0; i < n; i++) tmp[i] = vals[i];
   ArraySort(tmp);
   int idx = ClampI((int)MathCeil(pct / 100.0 * (n - 1)), 0, n - 1);
   return tmp[idx];
}

// Strict-less percentrank vs the stored previous values (Pine ta.percentrank).
double PrStrict(const double &ring[], int count, int look, double cur, bool &valid) {
   valid = (look > 0 && count >= look);
   if(!valid) return 0.0;
   int less = 0;
   for(int i = 0; i < look; i++) if(ring[i] < cur) less++;
   return 100.0 * less / look;
}


//+------------------------------------------------------------------+
//| Object helpers (create-once, update-in-place, all prefixed)      |
//+------------------------------------------------------------------+
void ObjCommon(string id) {
   ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
}
void Seg(string id, datetime t1, double p1, datetime t2, double p2,
         color c, int w, ENUM_LINE_STYLE st, bool arrowed = false) {
   ENUM_OBJECT type = arrowed ? OBJ_ARROWED_LINE : OBJ_TREND;
   if(ObjectFind(0, id) < 0) {
      if(!ObjectCreate(0, id, type, 0, t1, p1, t2, p2)) return;
      ObjCommon(id);
      ObjectSetInteger(0, id, OBJPROP_RAY_RIGHT, false);
   }
   ObjectSetInteger(0, id, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, id, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, id, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, id, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, id, OBJPROP_COLOR, c);
   ObjectSetInteger(0, id, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, id, OBJPROP_STYLE, st);
}
void Rect(string id, datetime t1, double p1, datetime t2, double p2, color c, bool back = true) {
   if(ObjectFind(0, id) < 0) {
      if(!ObjectCreate(0, id, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return;
      ObjCommon(id);
      ObjectSetInteger(0, id, OBJPROP_FILL, true);
   }
   ObjectSetInteger(0, id, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, id, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, id, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, id, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, id, OBJPROP_BACK, back);
   ObjectSetInteger(0, id, OBJPROP_COLOR, c);
}
void Txt(string id, datetime t, double p, string s, color c, int sz, ENUM_ANCHOR_POINT a) {
   if(ObjectFind(0, id) < 0) {
      if(!ObjectCreate(0, id, OBJ_TEXT, 0, t, p)) return;
      ObjCommon(id);
   }
   ObjectSetInteger(0, id, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, id, OBJPROP_PRICE, 0, p);
   ObjectSetString(0, id, OBJPROP_TEXT, s);
   ObjectSetInteger(0, id, OBJPROP_COLOR, c);
   ObjectSetInteger(0, id, OBJPROP_FONTSIZE, sz);
   ObjectSetInteger(0, id, OBJPROP_ANCHOR, a);
}
// Top-right telemetry card: one rectangle backdrop + monospace label rows,
// so the text stays readable over candles and never collides with the scale.
void PanelBg(string id, int x, int y, int w, int h) {
   if(ObjectFind(0, id) < 0) {
      if(!ObjectCreate(0, id, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;
      ObjCommon(id);
      ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, id, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, id, OBJPROP_BGCOLOR, C'18,22,28');
      ObjectSetInteger(0, id, OBJPROP_COLOR, C'70,80,90');
   }
   ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, id, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, id, OBJPROP_YSIZE, h);
}
void Lbl(string id, int x, int y, string s, color c) {
   if(ObjectFind(0, id) < 0) {
      if(!ObjectCreate(0, id, OBJ_LABEL, 0, 0, 0)) return;
      ObjCommon(id);
      ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, id, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetString(0, id, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, id, OBJPROP_FONTSIZE, 8);
   }
   ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, id, OBJPROP_TEXT, s);
   ObjectSetInteger(0, id, OBJPROP_COLOR, c);
}
void Kill(string id) { if(ObjectFind(0, id) >= 0) ObjectDelete(0, id); }

// Pixel width of panel text at the label font. TextSetFont with a NEGATIVE
// size (tenths of a point) is DPI-scaled exactly like OBJ_LABEL rendering, so
// the measured width matches what MT5 draws on any display (Retina included).
int PanelTextW1(string s) {
   TextSetFont("Consolas", -80, 0, 0);      // -80 = 8.0pt, DPI-aware
   uint w = 0, h = 0;
   if(!TextGetSize(s, w, h)) return 8 * StringLen(s);   // estimate if unavailable
   return (int)w;
}
int PanelTextW(string &rows[], int cnt) {
   TextSetFont("Consolas", -80, 0, 0);
   int mx = 0; uint w = 0, h = 0;
   for(int i = 0; i < cnt; i++)
      if(TextGetSize(rows[i], w, h) && (int)w > mx) mx = (int)w;
   return mx;
}

//+------------------------------------------------------------------+
//| VP core - Pine f_vp value-area expansion (verbatim port)         |
//+------------------------------------------------------------------+
void BuildVAFromHist(const double &hist[], int bins, double lo, double step,
                     double vaPct, VPResult &res) {
   double total = 0.0;
   int    pocIdx = 0;
   double pocVol = -1.0;
   for(int b = 0; b < bins; b++) {
      double hv = hist[b];
      total += hv;
      if(hv > pocVol) { pocVol = hv; pocIdx = b; }
   }
   double target = total * (vaPct * 0.01);
   double acc    = hist[pocIdx];
   int    loIdx  = pocIdx;
   int    hiIdx  = pocIdx;
   while(acc < target && (loIdx > 0 || hiIdx < bins - 1)) {
      double nextL = (loIdx > 0)        ? hist[loIdx - 1] : -1.0;
      double nextH = (hiIdx < bins - 1) ? hist[hiIdx + 1] : -1.0;
      if(nextH >= nextL) { hiIdx += 1; acc += hist[hiIdx]; }
      else               { loIdx -= 1; acc += hist[loIdx]; }
   }
   res.poc = lo + (pocIdx + 0.5) * step;
   res.vah = lo + (hiIdx + 1.0) * step;
   res.val = lo + loIdx * step;
}

// Bar-feed profile over completed bars [startShift .. startShift+len-1]
// (whole-bar tick_volume into the hlc3 bin - exact Pine f_vp parity).
bool ComputeVPBar(int startShift, int len, int bins, double vaPct, VPResult &res) {
   res.valid = false;
   res.poc = 0.0; res.vah = 0.0; res.val = 0.0; res.hi = 0.0; res.lo = 0.0;
   if(len <= 0 || bins < 2) return false;
   double highs[], lows[], closes[];
   long   vols[];
   if(CopyHigh(_Symbol, g_tf, startShift, len, highs)       != len) return false;
   if(CopyLow(_Symbol, g_tf, startShift, len, lows)         != len) return false;
   if(CopyClose(_Symbol, g_tf, startShift, len, closes)     != len) return false;
   if(CopyTickVolume(_Symbol, g_tf, startShift, len, vols)  != len) return false;
   double lo = lows[0], hi = highs[0];
   for(int i = 1; i < len; i++) {
      if(lows[i]  < lo) lo = lows[i];
      if(highs[i] > hi) hi = highs[i];
   }
   double step = (hi - lo) / bins;
   res.hi = hi; res.lo = lo;
   if(step <= 0.0) return false;
   double hist[];
   ArrayResize(hist, bins);
   ArrayInitialize(hist, 0.0);
   for(int i = 0; i < len; i++) {
      double p  = (highs[i] + lows[i] + closes[i]) / 3.0;
      int    bi = ClampI((int)MathFloor((p - lo) / step), 0, bins - 1);
      hist[bi] += (double)vols[i];
   }
   BuildVAFromHist(hist, bins, lo, step, vaPct, res);
   res.valid = true;
   return true;
}

//+------------------------------------------------------------------+
//| Real-tick engine: rolling cache + signed delta + dwell binning   |
//+------------------------------------------------------------------+
// Sync the cache to the ticks in [fromMs, toMs]; incremental when the
// window slid forward with overlap. Returns logical count or -1.
int TickCacheSync(ulong fromMs, ulong toMs) {
   bool canIncrement = g_tkCached && toMs >= g_tkTo
                       && fromMs >= g_tkFrom && fromMs <= g_tkTo + 1;
   if(!canIncrement) {
      int got = CopyTicksRange(_Symbol, g_ticks, COPY_TICKS_ALL, fromMs, toMs);
      if(got < 0) { g_tkCached = false; return -1; }
      g_tkFrom = fromMs; g_tkTo = toMs; g_tkCached = true;
      return got;
   }
   if(toMs > g_tkTo) {
      MqlTick tail[];
      int n = CopyTicksRange(_Symbol, tail, COPY_TICKS_ALL, g_tkTo + 1, toMs);
      if(n < 0) { g_tkCached = false; return -1; }
      if(n > 0) {
         int old = ArraySize(g_ticks);
         ArrayResize(g_ticks, old + n, 8192);
         for(int i = 0; i < n; i++) g_ticks[old + i] = tail[i];
      }
      g_tkTo = toMs;
   }
   if(fromMs > g_tkFrom) {
      int sz = ArraySize(g_ticks);
      int drop = 0;
      while(drop < sz && (ulong)g_ticks[drop].time_msc < fromMs) drop++;
      if(drop > 0) ArrayRemove(g_ticks, 0, drop);
      g_tkFrom = fromMs;
   }
   return ArraySize(g_ticks);
}

double TickPx(const MqlTick &tk) {
   if(tk.last > 0.0) return tk.last;
   if(tk.bid > 0.0 && tk.ask > 0.0) return (tk.bid + tk.ask) / 2.0;
   return tk.bid;
}

// Aggressor side: exchange flags when present, else the tick rule on the
// mid (up-tick = buy, down-tick = sell, flat inherits the last direction).
int TickSide(const MqlTick &tk, double px, double &prevMid, int &lastDir) {
   int side = 0;
   if((tk.flags & TICK_FLAG_BUY)  != 0) side = 1;
   if((tk.flags & TICK_FLAG_SELL) != 0) side = (side == 1) ? lastDir : -1;
   if(side == 0) {
      if(prevMid > 0.0) {
         if(px > prevMid + g_mintick * 0.5)      side = 1;
         else if(px < prevMid - g_mintick * 0.5) side = -1;
         else                                    side = lastDir;
      }
   }
   prevMid = px;
   if(side != 0) lastDir = side;
   return side;
}

// Bin ticks at/after fromMs into buy/sell volume + dwell-time histograms
// on the [lo, lo+bins*step] grid. When InpHistRecency is ON each tick's
// volume is weighted by InpNodeDecay^(chart bars of age) - the same memory
// the Pine node engine applies per bar - so RECENT one-sided flow shows as
// a large green/red fraction instead of being averaged away by the whole
// window (an undecayed 150-bar sum nets out near zero almost everywhere).
// Dwell time stays UNWEIGHTED: it measures true time-at-price.
// barOpen0 = open time of the forming chart bar (age reference).
// Returns the number of ticks consumed.
int BinTicksDelta(ulong fromMs, double lo, double step, int bins, datetime barOpen0,
                  double &buy[], double &sell[], double &timeMs[]) {
   ArrayResize(buy, bins);    ArrayInitialize(buy, 0.0);
   ArrayResize(sell, bins);   ArrayInitialize(sell, 0.0);
   ArrayResize(timeMs, bins); ArrayInitialize(timeMs, 0.0);
   int n = ArraySize(g_ticks);
   if(n <= 0 || step <= 0.0) return 0;
   long ps = (long)PeriodSeconds(g_tf);
   if(ps <= 0) return 0;
   // Per-bar-age weight table: shift-1 bar = decay^0, shift-k = decay^(k-1).
   double w[];
   ArrayResize(w, g_masterLen + 2);
   w[0] = 1.0; w[1] = 1.0;
   for(int k = 2; k < g_masterLen + 2; k++) w[k] = w[k - 1] * InpNodeDecay;
   double prevMid = 0.0;
   int    lastDir = 0;
   double capMs   = (double)MathMax(InpDwellCapSec, 1) * 1000.0;
   int    used    = 0;
   for(int i = 0; i < n; i++) {
      if((ulong)g_ticks[i].time_msc < fromMs) {
         // Pre-window ticks still seed the tick-rule state for continuity.
         double p0 = TickPx(g_ticks[i]);
         if(p0 > 0.0) { TickSide(g_ticks[i], p0, prevMid, lastDir); }
         continue;
      }
      double px = TickPx(g_ticks[i]);
      if(px <= 0.0) continue;
      int side = TickSide(g_ticks[i], px, prevMid, lastDir);
      double vol = (g_ticks[i].volume > 0) ? (double)g_ticks[i].volume : 1.0;
      if(InpHistRecency) {
         long age = ((long)barOpen0 - (long)(g_ticks[i].time_msc / 1000)) / ps + 1;
         vol *= w[(int)ClampD((double)age, 1.0, (double)(g_masterLen + 1))];
      }
      int bi = ClampI((int)MathFloor((px - lo) / step), 0, bins - 1);
      if(side >= 0) buy[bi]  += (side == 0 ? vol * 0.5 : vol);
      if(side <= 0) sell[bi] += (side == 0 ? vol * 0.5 : vol);
      if(i < n - 1) {
         double dt = (double)(g_ticks[i + 1].time_msc - g_ticks[i].time_msc);
         timeMs[bi] += ClampD(dt, 0.0, capMs);
      }
      used++;
   }
   return used;
}

// Real-tick master profile over completed bars [1 .. masterLen]: levels,
// display histogram (buy/sell/dwell) and the value area, all from the
// broker tick stream. Falls back to the bar feed when ticks are missing.
bool ComputeMasterTick(VPResult &res) {
   res.valid = false;
   double highs[], lows[];
   if(CopyHigh(_Symbol, g_tf, 1, g_masterLen, highs) != g_masterLen) { g_tickFailWhy = "CopyHigh short read"; return false; }
   if(CopyLow(_Symbol, g_tf, 1, g_masterLen, lows)   != g_masterLen) { g_tickFailWhy = "CopyLow short read";  return false; }
   double lo = lows[0], hi = highs[0];
   for(int i = 1; i < g_masterLen; i++) {
      if(lows[i]  < lo) lo = lows[i];
      if(highs[i] > hi) hi = highs[i];
   }
   res.hi = hi; res.lo = lo;
   double step = (hi - lo) / g_histBins;
   if(step <= 0.0) { g_tickFailWhy = "zero price range"; return false; }
   datetime tOldest = iTime(_Symbol, g_tf, g_masterLen);
   datetime tBar0   = iTime(_Symbol, g_tf, 0);
   if(tOldest <= 0 || tBar0 <= 0) { g_tickFailWhy = "bar times unavailable"; return false; }
   ulong fromMs = (ulong)tOldest * 1000;
   ulong toMs   = (ulong)tBar0 * 1000 - 1;
   int got = TickCacheSync(fromMs, toMs);
   if(got <= 0) {
      g_tickFailWhy = StringFormat("TickCacheSync got=%d err=%d", got, GetLastError());
      return false;
   }
   if(BinTicksDelta(fromMs, lo, step, g_histBins, tBar0, g_binBuy, g_binSell, g_binTimeMs) <= 0) {
      g_tickFailWhy = StringFormat("BinTicksDelta consumed 0 of %d cached ticks", got);
      return false;
   }
   double tot[];
   ArrayResize(tot, g_histBins);
   for(int b = 0; b < g_histBins; b++) tot[b] = g_binBuy[b] + g_binSell[b];
   BuildVAFromHist(tot, g_histBins, lo, step, InpVaPct, res);
   res.valid = true;
   return true;
}

// Predicted (aged-out) master profile: same newest-anchored window with the
// oldest InpPredictBars dropped (floored at vpBins bars) - previews where
// POC/VAH/VAL migrate when the current oldest nodes expire. Uses the same
// tick cache (filtered by time) on the tick feed, bar math otherwise.
bool ComputePredicted(VPResult &res) {
   res.valid = false;
   if(InpPredictBars <= 0) return false;
   int agedLen = (int)MathMax(g_bins, g_masterLen - InpPredictBars);
   if(!g_tickFeed) return ComputeVPBar(1, agedLen, g_bins, InpVaPct, res);
   double highs[], lows[];
   if(CopyHigh(_Symbol, g_tf, 1, agedLen, highs) != agedLen) return false;
   if(CopyLow(_Symbol, g_tf, 1, agedLen, lows)   != agedLen) return false;
   double lo = lows[0], hi = highs[0];
   for(int i = 1; i < agedLen; i++) {
      if(lows[i]  < lo) lo = lows[i];
      if(highs[i] > hi) hi = highs[i];
   }
   res.hi = hi; res.lo = lo;
   double step = (hi - lo) / g_histBins;
   if(step <= 0.0) return false;
   datetime tOldest = iTime(_Symbol, g_tf, agedLen);
   datetime tBar0   = iTime(_Symbol, g_tf, 0);
   if(tOldest <= 0 || tBar0 <= 0) return false;
   double buy[], sell[], tms[];
   if(BinTicksDelta((ulong)tOldest * 1000, lo, step, g_histBins, tBar0, buy, sell, tms) <= 0)
      return false;
   double tot[];
   ArrayResize(tot, g_histBins);
   for(int b = 0; b < g_histBins; b++) tot[b] = buy[b] + sell[b];
   BuildVAFromHist(tot, g_histBins, lo, step, InpVaPct, res);
   res.valid = true;
   return true;
}

// Bar-feed display histogram fallback: bar tick_volume split by the
// close-position direction proxy, SPREAD across the bins the bar's high->low
// range actually traded (not dumped at a single hlc3 point). This is a
// DISPLAY-ONLY change: in bar mode the histogram feeds no level or decision
// (master POC/VAH/VAL come from ComputeVPBar at g_bins; tick mode is untouched),
// so spreading only closes the comb gaps a per-bar single-point deposit leaves
// when g_histBins >> bar count - bins the candle crossed get their share of the
// volume instead of rendering empty. Dwell = bar seconds, spread the same way.
bool ComputeDisplayBar(double lo, double step) {
   ArrayResize(g_binBuy, g_histBins);    ArrayInitialize(g_binBuy, 0.0);
   ArrayResize(g_binSell, g_histBins);   ArrayInitialize(g_binSell, 0.0);
   ArrayResize(g_binTimeMs, g_histBins); ArrayInitialize(g_binTimeMs, 0.0);
   if(step <= 0.0) return false;
   double opens[], highs[], lows[], closes[];
   long   vols[];
   if(CopyOpen(_Symbol, g_tf, 1, g_masterLen, opens)       != g_masterLen) return false;
   if(CopyHigh(_Symbol, g_tf, 1, g_masterLen, highs)       != g_masterLen) return false;
   if(CopyLow(_Symbol, g_tf, 1, g_masterLen, lows)         != g_masterLen) return false;
   if(CopyClose(_Symbol, g_tf, 1, g_masterLen, closes)     != g_masterLen) return false;
   if(CopyTickVolume(_Symbol, g_tf, 1, g_masterLen, vols)  != g_masterLen) return false;
   double barMs = (double)PeriodSeconds(g_tf) * 1000.0;
   for(int i = 0; i < g_masterLen; i++) {
      if(closes[i] <= 0.0 || highs[i] < lows[i]) continue;
      double rng = MathMax(highs[i] - lows[i], g_mintick);
      double dp  = (closes[i] - opens[i]) / rng;
      double v   = (double)vols[i];
      if(InpHistRecency) {
         // Same per-bar memory decay as the tick path (and the Pine twin's
         // histBuy/histSell) - an undecayed 150-bar proxy sum nets out near
         // zero in every bin, which renders as an all-gray histogram.
         // i=0 is the OLDEST bar (shift g_masterLen), i=len-1 is shift 1.
         v *= MathPow(InpNodeDecay, (double)(g_masterLen - 1 - i));
      }
      // Distribute the bar's volume/dwell evenly across the bins its
      // high->low range spans, so the rows reflect every price the bar
      // actually traded instead of a single hlc3 point.
      int loIdx = ClampI((int)MathFloor((lows[i]  - lo) / step), 0, g_histBins - 1);
      int hiIdx = ClampI((int)MathFloor((highs[i] - lo) / step), 0, g_histBins - 1);
      int span  = hiIdx - loIdx + 1;
      double vShare    = v / span;
      double buyShare  = vShare * MathMax(dp, 0.0);
      double sellShare = vShare * MathMax(-dp, 0.0);
      double dwellShare = barMs / span;
      for(int b = loIdx; b <= hiIdx; b++) {
         g_binBuy[b]    += buyShare;
         g_binSell[b]   += sellShare;
         g_binTimeMs[b] += dwellShare;
      }
   }
   return true;
}

// Hybrid net-delta: fill g_binTBuy/g_binTSell with REAL tick-rule signed volume
// on the bar-feed grid [lo, lo+step*g_histBins], over a recent capped window so
// the CopyTicksRange fetch stays reliable (the full master window does not).
// Returns true when ticks were binned; the structure is untouched either way.
bool ComputeTickDelta(double lo, double step) {
   if(step <= 0.0) return false;
   int tickBars = (int)MathMin(g_masterLen, ClampI(InpHistTickBars, 20, 5000));
   datetime tStart = iTime(_Symbol, g_tf, tickBars);
   datetime tBar0  = iTime(_Symbol, g_tf, 0);
   if(tStart <= 0 || tBar0 <= 0) return false;
   ulong fromMs = (ulong)tStart * 1000;
   ulong toMs   = (ulong)tBar0 * 1000 - 1;
   if(TickCacheSync(fromMs, toMs) <= 0) return false;
   return (BinTicksDelta(fromMs, lo, step, g_histBins, tBar0,
                         g_binTBuy, g_binTSell, g_binTDwell) > 0);
}

//+------------------------------------------------------------------+
//| Node-state engine (Pine nodeBuy/nodeSell/nodeTouch, verbatim)    |
//+------------------------------------------------------------------+
void InitNodeEngine() {
   ArrayResize(g_nodeBuy,   g_bins);
   ArrayResize(g_nodeSell,  g_bins);
   ArrayResize(g_nodeTouch, g_bins);
   ArrayInitialize(g_nodeBuy,   0.0);
   ArrayInitialize(g_nodeSell,  0.0);
   ArrayInitialize(g_nodeTouch, 0.0);
   g_nodeBarTime = 0;
}

void UpdateNodeEngine(const VPResult &master) {
   if(!master.valid) return;
   datetime barT = iTime(_Symbol, g_tf, 1);
   if(barT <= 0 || barT == g_nodeBarTime) return;   // one update per closed bar
   double mLo = master.lo, mHi = master.hi;
   double mStep = (mHi - mLo) / g_bins;
   if(mStep <= 0.0) return;
   g_mLo = mLo; g_mHi = mHi; g_mStep = mStep;
   double o = iOpen(_Symbol, g_tf, 1);
   double h = iHigh(_Symbol, g_tf, 1);
   double l = iLow(_Symbol, g_tf, 1);
   double c = iClose(_Symbol, g_tf, 1);
   long   vraw[];
   if(CopyTickVolume(_Symbol, g_tf, 1, 1, vraw) != 1) return;
   double vol = (double)vraw[0];
   double atr = AtrAt(1);
   if(o <= 0.0 || h <= 0.0 || l <= 0.0 || c <= 0.0 || h < l) return;
   double touchDist = MathMax(InpNodeTouchAtr * atr, 2.0 * g_mintick);
   double dirProxy  = (c - o) / MathMax(h - l, g_mintick);
   double buyProxy  = vol * MathMax(dirProxy, 0.0);
   double sellProxy = vol * MathMax(-dirProxy, 0.0);
   for(int b = 0; b < g_bins; b++) {
      g_nodeBuy[b]   *= InpNodeDecay;
      g_nodeSell[b]  *= InpNodeDecay;
      g_nodeTouch[b] *= InpNodeDecay;
   }
   int lowIdx  = ClampI((int)MathFloor((l - mLo) / mStep), 0, g_bins - 1);
   int highIdx = ClampI((int)MathFloor((h - mLo) / mStep), 0, g_bins - 1);
   double span = MathMax(highIdx - lowIdx + 1, 1.0);
   for(int b = lowIdx; b <= highIdx; b++) {
      double nodePx = mLo + (b + 0.5) * mStep;
      bool touched = (MathAbs(c - nodePx) <= touchDist) || (l <= nodePx && h >= nodePx);
      if(touched) {
         g_nodeTouch[b] += 1.0;
         g_nodeBuy[b]   += buyProxy / span;
         g_nodeSell[b]  += sellProxy / span;
      }
   }
   g_nodeBarTime = barT;
}

int NodePickIdx(double px) {
   if(g_mStep <= 0.0) return 0;
   return ClampI((int)MathFloor((px - g_mLo) / g_mStep), 0, g_bins - 1);
}

NodeState NodeStateAt(int idx) {
   NodeState ns;
   ns.state = 0; ns.net = 0.0; ns.touch = 0.0; ns.absorbed = false;
   if(idx < 0 || idx >= g_bins || ArraySize(g_nodeBuy) != g_bins) return ns;
   double b = g_nodeBuy[idx];
   double s = g_nodeSell[idx];
   double t = g_nodeTouch[idx];
   double net = (b - s) / MathMax(b + s, 1.0);
   bool absorbed = (t >= InpNodeSaturation) && (MathAbs(net) <= InpNodeNeutralBand);
   ns.state = absorbed ? 0 : (net > InpNodeNeutralBand ? 1 : (net < -InpNodeNeutralBand ? -1 : 0));
   ns.net = net; ns.touch = t; ns.absorbed = absorbed;
   return ns;
}

string TagText(const NodeState &ns) {
   if(ns.absorbed)   return "~";
   if(ns.state > 0)  return SymUp();
   if(ns.state < 0)  return SymDn();
   return "flat";
}
color TagColor(const NodeState &ns) {
   if(ns.absorbed)  return clrSilver;
   if(ns.state > 0) return COL_UP_TXT;
   if(ns.state < 0) return COL_DN_TXT;
   return clrGray;
}

//+------------------------------------------------------------------+
//| Multi-TF near-price net tick volume (Pine f_tfNetNear family)    |
//+------------------------------------------------------------------+
double TfNetNearAt(ENUM_TIMEFRAMES tf, int shift, bool &valid) {
   valid = false;
   if(shift < 0) return 0.0;
   MqlRates rates[];
   int got = CopyRates(_Symbol, tf, shift, InpTfNetLook, rates);
   if(got <= 0) return 0.0;
   double px = rates[got - 1].close;
   if(px <= 0.0) return 0.0;
   valid = true;
   double a = AtrTfAt(tf, shift);
   if(a <= 0.0) return 0.0;
   double win = InpNetWinAtr * a;
   double tB = 0.0, tS = 0.0;
   for(int i = 0; i < got; i++) {
      double hi = rates[i].high, lo = rates[i].low;
      double op = rates[i].open, cl = rates[i].close;
      if(cl <= 0.0 || hi < lo) continue;
      double rng = MathMax(hi - lo, g_mintick);
      double dp  = (cl - op) / rng;
      double p   = (hi + lo + cl) / 3.0;
      if(MathAbs(p - px) <= win) {
         double v = (double)rates[i].tick_volume;
         tB += v * MathMax(dp, 0.0);
         tS += v * MathMax(-dp, 0.0);
      }
   }
   double tot = tB + tS;
   return (tot > 0.0) ? (tB - tS) / tot : 0.0;
}

int NetLastClosedShift(ENUM_TIMEFRAMES tf, datetime decisionT) {
   int s0 = iBarShift(_Symbol, tf, (datetime)(decisionT - 1), false);
   if(s0 < 0) return -1;
   datetime barClose = iTime(_Symbol, tf, s0) + (datetime)PeriodSeconds(tf);
   return (barClose <= decisionT) ? s0 : s0 + 1;
}

double NetPrevAtTime(ENUM_TIMEFRAMES tf, datetime decisionT, bool &valid) {
   valid = false;
   int sClosed = NetLastClosedShift(tf, decisionT);
   if(sClosed < 0) return 0.0;
   return TfNetNearAt(tf, sClosed + 1, valid);
}

// Chart-TF near net from the NODE arrays, HVN/MED/LVN tier-weighted
// (Pine f_near_net_weighted).
double NetChartNode(double px, double atrChart) {
   if(g_mStep <= 0.0 || atrChart <= 0.0) return 0.0;
   double nd = InpNetWinAtr * atrChart;
   double mx = 0.0;
   if(InpWeightedNet) {
      for(int b = 0; b < g_bins; b++) {
         double bpx = g_mLo + (b + 0.5) * g_mStep;
         if(MathAbs(bpx - px) <= nd)
            mx = MathMax(mx, g_nodeBuy[b] + g_nodeSell[b]);
      }
   }
   double tB = 0.0, tS = 0.0;
   for(int b = 0; b < g_bins; b++) {
      double bpx = g_mLo + (b + 0.5) * g_mStep;
      if(MathAbs(bpx - px) > nd) continue;
      double bv = g_nodeBuy[b], sv = g_nodeSell[b];
      double w  = 1.0;
      if(InpWeightedNet && mx > 0.0) {
         double tier = (bv + sv) / mx;
         w = (tier > 0.66) ? InpWHvn : (tier < 0.33 ? InpWLvn : InpWMvn);
      }
      if(bv > sv) tB += (bv - sv) * w;
      else        tS += (sv - bv) * w;
   }
   double tot = tB + tS;
   return (tot > 0.0) ? (tB - tS) / tot : 0.0;
}

// Real-tick near net from the display bins (committed + live overlay).
double NetChartTick(double px, double atrChart, double winAtr) {
   if(g_dStep <= 0.0 || atrChart <= 0.0) return 0.0;
   double nd = winAtr * atrChart;
   double tB = 0.0, tS = 0.0;
   for(int b = 0; b < g_histBins; b++) {
      double bpx = g_dLo + (b + 0.5) * g_dStep;
      if(MathAbs(bpx - px) > nd) continue;
      tB += g_binBuy[b]  + g_liveBuy[b];
      tS += g_binSell[b] + g_liveSell[b];
   }
   double tot = tB + tS;
   return (tot > 0.0) ? (tB - tS) / tot : 0.0;
}

//+------------------------------------------------------------------+
//| Execution health: master-window spread/speed baseline vs now     |
//+------------------------------------------------------------------+
// Baseline from the cached master tick window, once per closed bar - the
// same completed-bar data the profile is built from, so it never repaints.
// Speed = price travel per second; tick gaps are capped at the dwell cap
// so session breaks cannot dilute the average.
void ComputeExecBaseline() {
   g_execBaseSpread = 0.0;
   g_execBaseSpeed  = 0.0;
   if(!InpShowExecRow || !g_tickFeed) return;
   int n = ArraySize(g_ticks);
   if(n < 50) return;
   double sprSum = 0.0;
   long   sprN   = 0;
   double trav = 0.0, durMs = 0.0, prevMid = 0.0;
   double capMs = (double)MathMax(InpDwellCapSec, 1) * 1000.0;
   for(int i = 0; i < n; i++) {
      double b = g_ticks[i].bid, a = g_ticks[i].ask;
      if(b > 0.0 && a >= b) { sprSum += a - b; sprN++; }
      double mid = TickPx(g_ticks[i]);
      if(mid <= 0.0) continue;
      if(prevMid > 0.0 && i > 0) {
         trav  += MathAbs(mid - prevMid);
         durMs += ClampD((double)(g_ticks[i].time_msc - g_ticks[i - 1].time_msc), 0.0, capMs);
      }
      prevMid = mid;
   }
   if(sprN > 0)        g_execBaseSpread = sprSum / sprN;
   if(durMs > 1000.0)  g_execBaseSpeed  = trav / (durMs / 1000.0);
}

// One live sample per fresh tick into the rolling tape (newest at the end).
void ExecSample() {
   if(!InpShowExecRow) return;
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk)) return;
   if(tk.bid <= 0.0 || tk.ask < tk.bid) return;
   int cap = 512;
   if(ArraySize(g_exsMs) != cap) {
      ArrayResize(g_exsMs, cap);
      ArrayResize(g_exsSpr, cap);
      ArrayResize(g_exsMid, cap);
      g_exsN = 0;
   }
   double nowMs = (double)tk.time_msc;
   if(g_exsN > 0 && nowMs <= g_exsMs[g_exsN - 1]) return;   // no new tick yet
   if(g_exsN >= cap) {
      int keep = cap / 2;
      ArrayCopy(g_exsMs,  g_exsMs,  0, cap - keep, keep);
      ArrayCopy(g_exsSpr, g_exsSpr, 0, cap - keep, keep);
      ArrayCopy(g_exsMid, g_exsMid, 0, cap - keep, keep);
      g_exsN = keep;
   }
   g_exsMs[g_exsN]  = nowMs;
   g_exsSpr[g_exsN] = tk.ask - tk.bid;
   g_exsMid[g_exsN] = (tk.bid + tk.ask) / 2.0;
   g_exsN++;
}

// CURRENT spread/speed over the last InpExecWindowSec seconds of samples.
bool ExecCurrent(double &spr, double &spd) {
   spr = 0.0; spd = 0.0;
   if(g_exsN < 4) return false;
   double nowMs = g_exsMs[g_exsN - 1];
   double winMs = (double)MathMax(InpExecWindowSec, 5) * 1000.0;
   int i0 = g_exsN - 1;
   while(i0 > 0 && nowMs - g_exsMs[i0 - 1] <= winMs) i0--;
   if(g_exsN - i0 < 4) return false;
   double capMs = (double)MathMax(InpDwellCapSec, 1) * 1000.0;
   double sprSum = 0.0, trav = 0.0, durMs = 0.0;
   int n = 0;
   for(int i = i0; i < g_exsN; i++) {
      sprSum += g_exsSpr[i]; n++;
      if(i > i0) {
         trav  += MathAbs(g_exsMid[i] - g_exsMid[i - 1]);
         durMs += ClampD(g_exsMs[i] - g_exsMs[i - 1], 0.0, capMs);
      }
   }
   if(n <= 0 || durMs < 2000.0) return false;
   spr = sprSum / n;
   spd = trav / (durMs / 1000.0);
   return true;
}

// Repaint the exec panel row in place (the label object is created by
// DrawPanel after the backdrop, so updating here keeps the z-order).
void UpdateExecRow() {
   if(!InpShowPanel || !InpShowExecRow || g_execRowY < 0) return;
   if(ObjectFind(0, OBJPFX "tblEx") < 0) return;
   string s = "spr n/a  slip n/a";
   color  c = clrSilver;
   double spr = 0.0, spd = 0.0;
   if(!g_tickFeed) {
      s = "exec n/a (bar feed)";
   } else if(g_execBaseSpread > 0.0 && g_execBaseSpeed > 0.0 && ExecCurrent(spr, spd)) {
      int rs = (int)MathRound(spr / g_execBaseSpread * 100.0);
      int rv = (int)MathRound(spd / g_execBaseSpeed  * 100.0);
      string fs = (rs >= InpExecAlarmPct) ? "!!" : (rs >= InpExecWarnPct ? "!" : "");
      string fv = (rv >= InpExecAlarmPct) ? "!!" : (rv >= InpExecWarnPct ? "!" : "");
      s = StringFormat("spr %d%%%s slip %d%%%s", rs, fs, rv, fv);
      int worst = (int)MathMax(rs, rv);
      c = (worst >= InpExecAlarmPct) ? COL_DN_TXT
          : (worst >= InpExecWarnPct ? clrOrange : clrSilver);
   }
   Lbl(OBJPFX "tblEx", g_execRowX, g_execRowY, s, c);
}

//+------------------------------------------------------------------+
//| Live forming-bar tick overlay (kept apart from committed state)  |
//+------------------------------------------------------------------+
void ResetLiveOverlay() {
   ArrayResize(g_liveBuy, g_histBins);    ArrayInitialize(g_liveBuy, 0.0);
   ArrayResize(g_liveSell, g_histBins);   ArrayInitialize(g_liveSell, 0.0);
   ArrayResize(g_liveTimeMs, g_histBins); ArrayInitialize(g_liveTimeMs, 0.0);
   datetime bo = iTime(_Symbol, g_tf, 0);
   g_liveLastMs    = (bo > 0) ? (ulong)bo * 1000 - 1 : 0;
   g_liveLastTickMs = 0;
   g_liveLastBin    = -1;
   // prevMid/dir intentionally survive the bar roll for tick-rule continuity
}

void UpdateLiveTicks() {
   if(!g_tickFeed || g_dStep <= 0.0 || g_liveLastMs == 0) return;
   ulong nowMs = (ulong)TimeCurrent() * 1000 + 999;
   if(nowMs <= g_liveLastMs) return;
   MqlTick t[];
   int n = CopyTicksRange(_Symbol, t, COPY_TICKS_ALL, g_liveLastMs + 1, nowMs);
   if(n <= 0) return;
   double capMs = (double)MathMax(InpDwellCapSec, 1) * 1000.0;
   for(int i = 0; i < n; i++) {
      double px = TickPx(t[i]);
      if(px <= 0.0) continue;
      int side = TickSide(t[i], px, g_livePrevMid, g_liveDir);
      double vol = (t[i].volume > 0) ? (double)t[i].volume : 1.0;
      int bi = ClampI((int)MathFloor((px - g_dLo) / g_dStep), 0, g_histBins - 1);
      if(side >= 0) g_liveBuy[bi]  += (side == 0 ? vol * 0.5 : vol);
      if(side <= 0) g_liveSell[bi] += (side == 0 ? vol * 0.5 : vol);
      // dwell credit for the gap since the previous tick goes to its bin
      if(g_liveLastTickMs > 0 && g_liveLastBin >= 0 && g_liveLastBin < g_histBins) {
         double dt = (double)((ulong)t[i].time_msc - g_liveLastTickMs);
         g_liveTimeMs[g_liveLastBin] += ClampD(dt, 0.0, capMs);
      }
      g_liveLastTickMs = (ulong)t[i].time_msc;
      g_liveLastBin    = bi;
   }
   g_liveLastMs = (ulong)t[n - 1].time_msc;
}

//+------------------------------------------------------------------+
//| Init / deinit                                                    |
//+------------------------------------------------------------------+
// Stop ALL calculation: alert once, wipe every plotted level + drawn object,
// and leave an on-chart notice. Idempotent (safe to call every calc/timer).
void VizBlock() {
   if(!g_blocked) {
      Print("KK-MasterVP-Profiler: access expired (", ACCESS_EXPIRY, ") - calculation stopped.");
      ObjectsDeleteAll(0, OBJPFX);
   }
   g_blocked = true;
   if(!g_expiredAlerted) { Alert("Expired Access"); g_expiredAlerted = true; }
   if(ArraySize(BufMPoc) > 0) {
      ArrayInitialize(BufMPoc, EMPTY_VALUE); ArrayInitialize(BufMVah, EMPTY_VALUE);
      ArrayInitialize(BufMVal, EMPTY_VALUE); ArrayInitialize(BufLPoc, EMPTY_VALUE);
      ArrayInitialize(BufEma1, EMPTY_VALUE); ArrayInitialize(BufEma2, EMPTY_VALUE);
      ArrayInitialize(BufEma3, EMPTY_VALUE); ArrayInitialize(BufEma4, EMPTY_VALUE);
      ArrayInitialize(BufZoneA, EMPTY_VALUE); ArrayInitialize(BufZoneB, EMPTY_VALUE);
   }
   Comment("KK-MasterVP-Profiler: Expired Access");
   ChartRedraw();
}

int OnInit() {
   // ----- access guard (account lock + expiry) -----
   // Wrong account can never become valid -> remove the indicator. Expiry is
   // time-based -> stay loaded but blocked so the on-chart notice persists and
   // OnCalculate/OnTimer no-op (and keep re-checking is moot once expired).
   if(!KK_AccountAuthorized(ALLOWED_ACCOUNT_ID, ALLOWED_ACCOUNT_SERVER))
      return INIT_FAILED;
   if(KK_AccessExpired(ACCESS_EXPIRY)) {
      g_blocked = true; g_expiredAlerted = true;
      Alert("Expired Access");
      Comment("KK-MasterVP-Profiler: Expired Access");
      Print("KK-MasterVP-Profiler: access expired (", ACCESS_EXPIRY, ") - calculation disabled.");
      return INIT_SUCCEEDED;
   }

   g_tf = (ENUM_TIMEFRAMES)_Period;
   g_mintick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_mintick <= 0.0) g_mintick = _Point;
   if(g_mintick <= 0.0) g_mintick = 0.01;
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   g_bins      = ClampI(InpVpBins, 4, 200);
   g_histBins  = ClampI(InpHistBins, 4, 600);
   g_localLen  = ClampI(InpVpLookback, 10, 1000);
   g_masterLen = (int)MathRound(g_localLen * MathMax(0.5, MathMin(10.0, InpMasterMult)));

   g_hAtrChart = iATR(_Symbol, g_tf, InpAtrLen);
   g_hAtrM1    = (g_tf == PERIOD_M1)  ? g_hAtrChart : iATR(_Symbol, PERIOD_M1,  InpAtrLen);
   g_hAtrM5    = (g_tf == PERIOD_M5)  ? g_hAtrChart : iATR(_Symbol, PERIOD_M5,  InpAtrLen);
   g_hAtrM15   = (g_tf == PERIOD_M15) ? g_hAtrChart : iATR(_Symbol, PERIOD_M15, InpAtrLen);
   if(g_hAtrChart == INVALID_HANDLE || g_hAtrM1 == INVALID_HANDLE ||
      g_hAtrM5 == INVALID_HANDLE    || g_hAtrM15 == INVALID_HANDLE) {
      Print("KK-MasterVP-Profiler: ATR handle creation failed");
      return INIT_FAILED;
   }

   SetIndexBuffer(0, BufMPoc, INDICATOR_DATA);
   SetIndexBuffer(1, BufMVah, INDICATOR_DATA);
   SetIndexBuffer(2, BufMVal, INDICATOR_DATA);
   SetIndexBuffer(3, BufLPoc, INDICATOR_DATA);
   for(int p = 0; p < 4; p++) {
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
      PlotIndexSetInteger(p, PLOT_DRAW_BEGIN, g_masterLen);
   }
   // EMA overlay: plots 4-7. Handles only exist while the switch is ON; with
   // it OFF the plots flip to DRAW_NONE and the buffers stay EMPTY_VALUE.
   SetIndexBuffer(4, BufEma1, INDICATOR_DATA);
   SetIndexBuffer(5, BufEma2, INDICATOR_DATA);
   SetIndexBuffer(6, BufEma3, INDICATOR_DATA);
   SetIndexBuffer(7, BufEma4, INDICATOR_DATA);
   int emaLens[4];
   emaLens[0] = ClampI(InpEma1Len, 1, 5000);
   emaLens[1] = ClampI(InpEma2Len, 1, 5000);
   emaLens[2] = ClampI(InpEma3Len, 1, 5000);
   emaLens[3] = ClampI(InpEma4Len, 1, 5000);
   g_emaSynced = false;
   // Handles are needed for the DISPLAY and for the setup-engine EMA veto -
   // the veto must work even with the lines hidden.
   bool needEma = InpShowEmas || InpSetEmaFilter;
   for(int e = 0; e < 4; e++) {
      PlotIndexSetDouble(4 + e, PLOT_EMPTY_VALUE, EMPTY_VALUE);
      PlotIndexSetInteger(4 + e, PLOT_DRAW_BEGIN, emaLens[e]);
      if(needEma) {
         g_hEma[e] = iMA(_Symbol, g_tf, emaLens[e], 0, MODE_EMA, PRICE_CLOSE);
         if(g_hEma[e] == INVALID_HANDLE) {
            Print("KK-MasterVP-Profiler: EMA handle creation failed (len ", emaLens[e], ")");
            return INIT_FAILED;
         }
      }
      if(!InpShowEmas)
         PlotIndexSetInteger(4 + e, PLOT_DRAW_TYPE, DRAW_NONE);
   }
   // EMA zone ribbon: plot 8 consumes buffers 8/9 (edges) + 10 (color index).
   SetIndexBuffer(8,  BufZoneA, INDICATOR_DATA);
   SetIndexBuffer(9,  BufZoneB, INDICATOR_DATA);
   SetIndexBuffer(10, BufZoneC, INDICATOR_COLOR_INDEX);
   PlotIndexSetDouble(8, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   int maxEmaLen = (int)MathMax(MathMax(emaLens[0], emaLens[1]),
                                MathMax(emaLens[2], emaLens[3]));
   PlotIndexSetInteger(8, PLOT_DRAW_BEGIN, maxEmaLen);
   if(!InpShowEmas || !InpShowEmaZone)
      PlotIndexSetInteger(8, PLOT_DRAW_TYPE, DRAW_NONE);
   IndicatorSetInteger(INDICATOR_DIGITS, g_digits);
   IndicatorSetString(INDICATOR_SHORTNAME, "KK-MasterVP Profiler");

   InitNodeEngine();
   ArrayResize(g_binBuy, g_histBins);    ArrayInitialize(g_binBuy, 0.0);
   ArrayResize(g_binSell, g_histBins);   ArrayInitialize(g_binSell, 0.0);
   ArrayResize(g_binTimeMs, g_histBins); ArrayInitialize(g_binTimeMs, 0.0);
   ArrayResize(g_liveBuy, g_histBins);    ArrayInitialize(g_liveBuy, 0.0);
   ArrayResize(g_liveSell, g_histBins);   ArrayInitialize(g_liveSell, 0.0);
   ArrayResize(g_liveTimeMs, g_histBins); ArrayInitialize(g_liveTimeMs, 0.0);
   int ringCap = (int)MathMax(InpNearVolLook, 1);
   ArrayResize(g_nearRing, ringCap);
   ArrayInitialize(g_nearRing, 0.0);
   g_nearCount = 0;

   g_master.valid = false; g_local.valid = false; g_pred.valid = false;
   g_lastBarTime = 0;
   g_tkCached = false;
   g_tickFeed = false;

   // The histogram/tags/projection live in the future margin right of the
   // last candle, and auto-scroll fights any attempt to scroll back into
   // history - configure the chart once so both work out of the box. Shift
   // size 30% buys ~30 future bars at a typical zoom, enough for the zone.
   ChartSetInteger(0, CHART_AUTOSCROLL, false);
   ChartSetInteger(0, CHART_SHIFT, true);
   ChartSetDouble(0, CHART_SHIFT_SIZE, 30.0);

   // Eye-friendly dark theme: hue contrast instead of brightness contrast.
   // Bodies use the TradingView teal/red pair, background is a soft
   // blue-black (pure black + neon lime is what causes the eye strain),
   // grid is barely-there. One toggle restores the user's own colors.
   if(InpApplyTheme) {
      ChartSetInteger(0, CHART_COLOR_BACKGROUND, C'16,18,24');
      ChartSetInteger(0, CHART_COLOR_FOREGROUND, C'140,150,160');
      ChartSetInteger(0, CHART_COLOR_GRID,       C'33,38,46');
      ChartSetInteger(0, CHART_COLOR_CHART_UP,   C'8,153,129');    // wick/border up
      ChartSetInteger(0, CHART_COLOR_CHART_DOWN, C'242,54,69');    // wick/border down
      ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, C'8,153,129');   // body up (TV teal)
      ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, C'242,54,69');   // body down (TV red)
      ChartSetInteger(0, CHART_COLOR_CHART_LINE, C'120,130,140');
      ChartSetInteger(0, CHART_COLOR_VOLUME,     C'52,76,88');
      ChartSetInteger(0, CHART_COLOR_BID,        C'70,110,150');
      ChartSetInteger(0, CHART_COLOR_ASK,        C'150,80,80');
      ChartSetInteger(0, CHART_COLOR_LAST,       C'120,130,140');
      ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, C'255,152,0');
   }

   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   EventKillTimer();
   Comment("");
   ObjectsDeleteAll(0, OBJPFX);
   if(g_hAtrM15 != INVALID_HANDLE && g_hAtrM15 != g_hAtrChart) IndicatorRelease(g_hAtrM15);
   if(g_hAtrM5  != INVALID_HANDLE && g_hAtrM5  != g_hAtrChart) IndicatorRelease(g_hAtrM5);
   if(g_hAtrM1  != INVALID_HANDLE && g_hAtrM1  != g_hAtrChart) IndicatorRelease(g_hAtrM1);
   if(g_hAtrChart != INVALID_HANDLE) IndicatorRelease(g_hAtrChart);
   g_hAtrChart = g_hAtrM1 = g_hAtrM5 = g_hAtrM15 = INVALID_HANDLE;
   for(int e = 0; e < 4; e++) {
      if(g_hEma[e] != INVALID_HANDLE) IndicatorRelease(g_hEma[e]);
      g_hEma[e] = INVALID_HANDLE;
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Trails: per-bar bar-feed profile history (capped by InpTrailBars)|
//+------------------------------------------------------------------+
void TrailAt(const double &high[], const double &low[], const double &close[],
             const long &tvol[], int iEnd, int len,
             double &poc, double &vah, double &val) {
   poc = EMPTY_VALUE; vah = EMPTY_VALUE; val = EMPTY_VALUE;
   int i0 = iEnd - len + 1;
   if(i0 < 0) return;
   double lo = low[i0], hi = high[i0];
   for(int i = i0 + 1; i <= iEnd; i++) {
      if(low[i]  < lo) lo = low[i];
      if(high[i] > hi) hi = high[i];
   }
   double step = (hi - lo) / g_bins;
   if(step <= 0.0) return;
   double hist[];
   ArrayResize(hist, g_bins);
   ArrayInitialize(hist, 0.0);
   for(int i = i0; i <= iEnd; i++) {
      double p  = (high[i] + low[i] + close[i]) / 3.0;
      int    bi = ClampI((int)MathFloor((p - lo) / step), 0, g_bins - 1);
      hist[bi] += (double)tvol[i];
   }
   VPResult r;
   BuildVAFromHist(hist, g_bins, lo, step, InpVaPct, r);
   poc = r.poc; vah = r.vah; val = r.val;
}

//+------------------------------------------------------------------+
//| Per-bar rebuild: profiles, node engine, nets, HVNs, projection   |
//+------------------------------------------------------------------+
void RebuildAll() {
   double atr1 = AtrAt(1);

   // --- master profile: real ticks first, bar feed as parity fallback ---
   g_tickFeed = false;
   bool ok = false;
   if(InpUseRealTicks) {
      ok = ComputeMasterTick(g_master);
      if(ok) g_tickFeed = true;
   }
   if(!ok) {
      ok = ComputeVPBar(1, g_masterLen, g_bins, InpVaPct, g_master);
      if(ok) {
         double step = (g_master.hi - g_master.lo) / g_histBins;
         ComputeDisplayBar(g_master.lo, step);
      }
   }
   if(!ok) return;
   // Feed-state telemetry: one Experts-log line per state CHANGE only.
   int feedNow = g_tickFeed ? 1 : 0;
   if(feedNow != g_feedLogged) {
      g_feedLogged = feedNow;
      if(g_tickFeed)
         Print("Profiler feed: TICK (", ArraySize(g_ticks), " ticks cached, recency=",
               InpHistRecency ? "on" : "off", ")");
      else
         Print("Profiler feed: BAR fallback - ", InpUseRealTicks ? g_tickFailWhy : "real ticks disabled by input");
   }
   g_dLo = g_master.lo; g_dHi = g_master.hi;
   g_dStep = (g_dHi - g_dLo) / g_histBins;

   // --- hybrid net-delta tint: bar-feed structure (above) stays the rows;
   // real tick-rule signed volume tints only the bright delta slice + near
   // readout. Skipped when the structure already IS ticks (g_tickFeed). ---
   g_binTickOk = false;
   if(!g_tickFeed && InpHistTickDelta)
      g_binTickOk = ComputeTickDelta(g_dLo, g_dStep);

   // --- execution-health baseline from the same committed tick window ---
   ComputeExecBaseline();

   // --- local + predicted profiles ---
   ComputeVPBar(1, g_localLen, g_bins, InpVaPct, g_local);
   ComputePredicted(g_pred);

   // --- node-state engine: one decayed update per closed bar ---
   UpdateNodeEngine(g_master);

   // --- live overlay restarts on the fresh forming bar ---
   ResetLiveOverlay();
   UpdateLiveTicks();

   // --- multi-TF near-price nets at the decision time (forming bar open) ---
   datetime decisionT = iTime(_Symbol, g_tf, 0);
   double close1 = iClose(_Symbol, g_tf, 1);
   g_netM1  = NetPrevAtTime(PERIOD_M1,  decisionT, g_hasM1);
   g_netM5  = NetPrevAtTime(PERIOD_M5,  decisionT, g_hasM5);
   g_netM15 = NetPrevAtTime(PERIOD_M15, decisionT, g_hasM15);
   g_netChartNode = NetChartNode(close1, atr1);
   g_netChartTick = NetChartTick(close1, atr1, InpNetWinAtr);

   // --- near-volume magnitude ring (per confirmed bar, newest at [0]) ---
   if(g_dStep > 0.0 && atr1 > 0.0) {
      double nearVol = 0.0;
      double nd = InpVerdictAtr * atr1;
      for(int b = 0; b < g_histBins; b++) {
         double bpx = g_dLo + (b + 0.5) * g_dStep;
         if(MathAbs(bpx - close1) <= nd) nearVol += g_binBuy[b] + g_binSell[b];
      }
      int cap = ArraySize(g_nearRing);
      if(cap > 0) {
         int top = (int)MathMin(g_nearCount, cap - 1);
         for(int i = top; i > 0; i--) g_nearRing[i] = g_nearRing[i - 1];
         g_nearRing[0] = nearVol;
         if(g_nearCount < cap) g_nearCount++;
      }
   }

   // --- master-POC slope (regime read) from the trail buffer history ---
   g_slopeKnown = false; g_slopeNorm = 0.0;
   int iNow = g_rt - 2;                    // last closed bar in buffer indexing
   int iOld = iNow - ClampI(InpSlopeBars, 1, 500);
   if(atr1 > 0.0 && iNow >= 0 && iOld >= 0 && iNow < g_rt &&
      BufMPoc[iNow] != EMPTY_VALUE && BufMPoc[iOld] != EMPTY_VALUE) {
      g_slopeNorm  = (BufMPoc[iNow] - BufMPoc[iOld]) / atr1;
      g_slopeKnown = true;
   }

   // --- bias + projected magnet ---
   ComputeProjection(close1, atr1);

   DrawAll(close1, atr1);
}

//+------------------------------------------------------------------+
//| Projection: delta bias -> next magnet through the HVN/LVN map    |
//+------------------------------------------------------------------+
void ComputeProjection(double close1, double atr1) {
   g_bias = 0.0; g_biasTarget = 0.0; g_biasKind = "";
   if(!g_master.valid || atr1 <= 0.0 || g_dStep <= 0.0) return;
   double nearDelta = (g_tickFeed || g_binTickOk) ? g_netChartTick : g_netChartNode;
   double mig = (g_pred.valid) ? ClampD((g_pred.poc - g_master.poc) / atr1, -1.0, 1.0) : 0.0;
   double pos = ClampD((close1 - g_master.poc) / (2.0 * atr1), -1.0, 1.0);
   g_bias = 0.50 * nearDelta + 0.35 * mig + 0.15 * pos;

   if(MathAbs(g_bias) < InpBiasBalanced) {
      g_biasTarget = g_master.poc;
      g_biasKind   = "POC rotation";
      return;
   }
   // HVN threshold over occupied display bins (committed + live)
   double occ[];
   ArrayResize(occ, g_histBins);
   int nOcc = 0;
   for(int b = 0; b < g_histBins; b++) {
      double tot = g_binBuy[b] + g_binSell[b] + g_liveBuy[b] + g_liveSell[b];
      if(tot > 0.0) { occ[nOcc] = tot; nOcc++; }
   }
   double hvnTh = PercentileOf(occ, nOcc, InpHvnPct);
   int dir = (g_bias > 0.0) ? 1 : -1;
   double minGap = 0.3 * atr1;   // skip the bins price already sits in
   for(int k = 0; k < g_histBins; k++) {
      int b = (dir > 0) ? k : g_histBins - 1 - k;
      double bpx = g_dLo + (b + 0.5) * g_dStep;
      if(dir > 0 && bpx < close1 + minGap) continue;
      if(dir < 0 && bpx > close1 - minGap) continue;
      double tot = g_binBuy[b] + g_binSell[b] + g_liveBuy[b] + g_liveSell[b];
      if(hvnTh > 0.0 && tot >= hvnTh) {
         g_biasTarget = bpx;
         g_biasKind   = "HVN magnet";
         return;
      }
   }
   // No HVN ahead inside the profile: project to the (predicted) edge.
   if(dir > 0) g_biasTarget = g_pred.valid ? MathMax(g_pred.vah, g_master.vah) : g_master.vah;
   else        g_biasTarget = g_pred.valid ? MathMin(g_pred.val, g_master.val) : g_master.val;
   g_biasKind = "VA edge (vacuum)";
}

//+------------------------------------------------------------------+
//| Drawing                                                          |
//+------------------------------------------------------------------+
void DrawAll(double close1, double atr1) {
   datetime tLast = iTime(_Symbol, g_tf, 0);
   if(tLast <= 0) return;
   int ps = PeriodSeconds(g_tf);
   // Histogram zone sits back in history (InpHistShiftBars left of the live
   // candle), rows growing rightward - the live price area stays clear.
   datetime tHistL = tLast - (datetime)(InpHistShiftBars * ps);
   datetime tHistR = tHistL + (datetime)(InpHistWidthBars * ps);
   // Level lines all start at the VP zone's left anchor and run right
   // through the live price into the margin where their tags sit.
   datetime tLocL  = tHistL;
   datetime tMstL  = tHistL;
   datetime tLocR  = tLast + (datetime)(8 * ps);
   datetime tMstR  = tLast + (datetime)(19 * ps);

   // --- level rays + node-state tags ---
   if(InpShowMasterLines && g_master.valid) {
      Seg(OBJPFX "mPOC", tMstL, g_master.poc, tMstR, g_master.poc, COL_MASTER, 3, STYLE_SOLID);
      Seg(OBJPFX "mVAH", tMstL, g_master.vah, tMstR, g_master.vah, COL_MASTER, 1, STYLE_DASH);
      Seg(OBJPFX "mVAL", tMstL, g_master.val, tMstR, g_master.val, COL_MASTER, 1, STYLE_DASH);
      NodeState np = NodeStateAt(NodePickIdx(g_master.poc));
      NodeState nh = NodeStateAt(NodePickIdx(g_master.vah));
      NodeState nl = NodeStateAt(NodePickIdx(g_master.val));
      Txt(OBJPFX "mPOCt", tMstR, g_master.poc, "mPOC " + TagText(np), TagColor(np), 8, ANCHOR_LEFT);
      Txt(OBJPFX "mVAHt", tMstR, g_master.vah, "mVAH " + TagText(nh), TagColor(nh), 8, ANCHOR_LEFT);
      Txt(OBJPFX "mVALt", tMstR, g_master.val, "mVAL " + TagText(nl), TagColor(nl), 8, ANCHOR_LEFT);
   } else {
      Kill(OBJPFX "mPOC"); Kill(OBJPFX "mVAH"); Kill(OBJPFX "mVAL");
      Kill(OBJPFX "mPOCt"); Kill(OBJPFX "mVAHt"); Kill(OBJPFX "mVALt");
   }
   if(InpShowLocalLines && g_local.valid) {
      Seg(OBJPFX "lPOC", tLocL, g_local.poc, tLocR, g_local.poc, COL_LOCAL, 2, STYLE_SOLID);
      Seg(OBJPFX "lVAH", tLocL, g_local.vah, tLocR, g_local.vah, COL_LOCAL, 1, STYLE_DASH);
      Seg(OBJPFX "lVAL", tLocL, g_local.val, tLocR, g_local.val, COL_LOCAL, 1, STYLE_DASH);
      NodeState np = NodeStateAt(NodePickIdx(g_local.poc));
      NodeState nh = NodeStateAt(NodePickIdx(g_local.vah));
      NodeState nl = NodeStateAt(NodePickIdx(g_local.val));
      Txt(OBJPFX "lPOCt", tLocR, g_local.poc, "POC " + TagText(np), TagColor(np), 8, ANCHOR_LEFT);
      Txt(OBJPFX "lVAHt", tLocR, g_local.vah, "VAH " + TagText(nh), TagColor(nh), 8, ANCHOR_LEFT);
      Txt(OBJPFX "lVALt", tLocR, g_local.val, "VAL " + TagText(nl), TagColor(nl), 8, ANCHOR_LEFT);
   } else {
      Kill(OBJPFX "lPOC"); Kill(OBJPFX "lVAH"); Kill(OBJPFX "lVAL");
      Kill(OBJPFX "lPOCt"); Kill(OBJPFX "lVAHt"); Kill(OBJPFX "lVALt");
   }

   // --- predicted master POC ---
   // Twice as long as before (6 bars) and the "pPOC" tag sits centered ON TOP
   // of the line (ANCHOR_LOWER at the midpoint) so it reads distinctly from the
   // master/local VP rays, which tag at their right end.
   if(InpShowPredictedPoc && g_pred.valid) {
      Seg(OBJPFX "pPOC", tLast, g_pred.poc, tLast + (datetime)(6 * ps), g_pred.poc, clrDodgerBlue, 2, STYLE_SOLID);
      Txt(OBJPFX "pPOCt", tLast + (datetime)(3 * ps), g_pred.poc,
          "pPOC", clrDodgerBlue, 8, ANCHOR_LOWER);
   } else {
      Kill(OBJPFX "pPOC"); Kill(OBJPFX "pPOCt");
   }

   DrawHvnLines(tLast, ps);
   DrawProjection(tLast, ps, close1);
   DrawPanel(atr1);
   // Histogram is drawn inside the per-tick refresh (UpdateVerdictAndRuler)
   // so its live green/red delta slices move intra-bar, not once per bar.
   UpdateVerdictAndRuler(true);
}

// Net delta for a bin: real tick-rule signed share when the hybrid tick pass
// covered this bin, otherwise the bar-direction net. The +/- magnitude drives
// the bright delta slice's colour and length; the structure (bv/sv) is bar-fed.
double BinDeltaNet(int b, double bv, double sv) {
   if(g_binTickOk) {
      double tb = g_binTBuy[b], ts = g_binTSell[b], tt = tb + ts;
      if(tt > 0.0) return (tb - ts) / tt;
   }
   double tot = bv + sv;
   return (tot > 0.0) ? (bv - sv) / tot : 0.0;
}

void DrawHistogram(datetime tHistL, datetime tHistR) {
   if(!InpShowHistogram || !g_master.valid || g_dStep <= 0.0) {
      for(int b = 0; b < g_histBins; b++) {
         Kill(OBJPFX "hN" + IntegerToString(b));
         Kill(OBJPFX "hG" + IntegerToString(b));
         Kill(OBJPFX "hD" + IntegerToString(b));
      }
      return;
   }
   double maxTot = 0.0, netRef = 0.0;
   for(int b = 0; b < g_histBins; b++) {
      double bv = g_binBuy[b]  + g_liveBuy[b];
      double sv = g_binSell[b] + g_liveSell[b];
      double tot = bv + sv;
      maxTot = MathMax(maxTot, tot);
      if(tot > 0.0) netRef = MathMax(netRef, MathAbs(BinDeltaNet(b, bv, sv)));
   }
   double zoneSec = (double)(tHistR - tHistL);
   double halfH   = g_dStep / 2.0;
   for(int b = 0; b < g_histBins; b++) {
      string idN = OBJPFX "hN" + IntegerToString(b);
      string idG = OBJPFX "hG" + IntegerToString(b);
      string idD = OBJPFX "hD" + IntegerToString(b);
      double bv = g_binBuy[b]  + g_liveBuy[b];
      double sv = g_binSell[b] + g_liveSell[b];
      double tot = bv + sv;
      if(maxTot <= 0.0 || tot <= 0.0) { Kill(idN); Kill(idG); Kill(idD); continue; }
      double binPx  = g_dLo + (b + 0.5) * g_dStep;
      double net    = BinDeltaNet(b, bv, sv);   // tick-rule tint when available, else bar-net
      double frac   = tot / maxTot;
      bool   outVA  = (binPx > g_master.vah || binPx < g_master.val);
      datetime xFull = tHistL + (datetime)(zoneSec * frac);
      color cBuy  = C'18,50,23';
      color cSell = C'66,18,18';
      color cDelta = (net >= 0.0) ? COL_BUY : COL_SELL;
      double buyShare = bv / tot;
      double sellShare = sv / tot;
      bool histBack = !InpHistFront;
      datetime xSplit  = tHistL + (datetime)(zoneSec * frac * sellShare);
      if(sellShare > 0.001)
         Rect(idG, tHistL, binPx + halfH * 0.85, xSplit, binPx - halfH * 0.85,
              cSell, histBack);
      else Kill(idG);
      if(buyShare > 0.001)
         Rect(idN, xSplit, binPx + halfH * 0.85, xFull, binPx - halfH * 0.85,
              cBuy, histBack);
      else Kill(idN);
      double deltaStrength = MathAbs(net);
      if(InpHistNetScale && netRef > 0.0)
         deltaStrength = MathMin(1.0, MathAbs(net) / netRef);
      if(deltaStrength > 0.0)
         deltaStrength = MathMax(MathSqrt(deltaStrength), 0.10);
      double deltaFrac = frac * deltaStrength;
      deltaFrac = MathMin(frac, deltaFrac + 5.0 / MathMax(zoneSec, 1.0));
      datetime xDelta = tHistL + (datetime)(zoneSec * deltaFrac);
      if(deltaFrac > 0.001)
         Rect(idD, tHistL, binPx + halfH * 0.85, xDelta, binPx - halfH * 0.85,
              cDelta, histBack);
      else Kill(idD);
   }
 }

// Short marker stubs at the strongest HVN bins - just long enough to notice,
// no text (the histogram row itself carries the volume/delta story).
void DrawHvnLines(datetime tLast, int ps) {
   int used = 0;
   if(InpShowHvnLines && g_master.valid && g_dStep > 0.0) {
      double occ[];
      ArrayResize(occ, g_histBins);
      int nOcc = 0;
      for(int b = 0; b < g_histBins; b++) {
         double tot = g_binBuy[b] + g_binSell[b] + g_liveBuy[b] + g_liveSell[b];
         if(tot > 0.0) { occ[nOcc] = tot; nOcc++; }
      }
      double hvnTh = PercentileOf(occ, nOcc, InpHvnPct);
      // strongest-first selection, capped at InpMaxHvnLines
      double vols[];  int idxs[];
      ArrayResize(vols, g_histBins); ArrayResize(idxs, g_histBins);
      int nH = 0;
      for(int b = 0; b < g_histBins; b++) {
         double tot = g_binBuy[b] + g_binSell[b] + g_liveBuy[b] + g_liveSell[b];
         if(hvnTh > 0.0 && tot >= hvnTh) { vols[nH] = tot; idxs[nH] = b; nH++; }
      }
      for(int i = 0; i < nH - 1; i++)            // selection sort, nH is tiny
         for(int j = i + 1; j < nH; j++)
            if(vols[j] > vols[i]) {
               double tv = vols[i]; vols[i] = vols[j]; vols[j] = tv;
               int    ti = idxs[i]; idxs[i] = idxs[j]; idxs[j] = ti;
            }
      int lim = (int)MathMin(nH, ClampI(InpMaxHvnLines, 1, 24));
      // Stubs live ON the profile zone, poking a few bars past its right
      // edge - never near the live candles.
      datetime tL = tLast - (datetime)(InpHistShiftBars * ps);
      datetime tR = tL + (datetime)((InpHistWidthBars + 4) * ps);
      for(int i = 0; i < lim; i++) {
         int b = idxs[i];
         double bpx = g_dLo + (b + 0.5) * g_dStep;
         string sid = IntegerToString(i);
         Seg(OBJPFX "hvn" + sid, tL, bpx, tR, bpx, COL_HVN, (i < 3 ? 2 : 1), STYLE_DOT);
         used++;
      }
   }
   for(int i = used; i < 24; i++) {
      Kill(OBJPFX "hvn" + IntegerToString(i));
      Kill(OBJPFX "hvnT" + IntegerToString(i));
   }
}

void DrawProjection(datetime tLast, int ps, double close1) {
   // On-chart bias arrow (price -> projected magnet, with % text) removed by
   // request: it read as a "prediction" and cluttered the live price area. The
   // signed bias score still lives in the panel headline row. Kill any leftover
   // objects from a previous build so nothing lingers on re-attach.
   Kill(OBJPFX "proj"); Kill(OBJPFX "projT");
}

string TfShort() {
   string s = EnumToString((ENUM_TIMEFRAMES)_Period);
   StringReplace(s, "PERIOD_", "");
   return s;
}

void DrawPanel(double atr1) {
   if(!InpShowPanel) {
      Kill(OBJPFX "tblBg"); Kill(OBJPFX "tblEx");
      for(int i = 0; i < 6; i++) Kill(OBJPFX "tbl" + IntegerToString(i));
      return;
   }
   int rowH = 16, pad = 6;
   int gutter = 64;                  // price-scale strip width to stay clear of
   int y = 22;

   double close1 = iClose(_Symbol, g_tf, 1);
   double atrPct = (close1 > 0.0 && atr1 > 0.0) ? atr1 / close1 * 100.0 : 0.0;
   string feedTag = g_tickFeed ? "TICK" : (g_binTickOk ? "BAR+tickD" : "BAR");
   color  feedCol = g_tickFeed ? clrDeepSkyBlue : (g_binTickOk ? clrMediumTurquoise : clrOrange);

   // Plain-language headline: arrow + direction word + the magnet PRICE the
   // bias engine projects to. TREND only when the master-POC slope agrees;
   // a trailing ? marks a weak (sub-arrow-threshold) read.
   string ht; color hc;
   if(g_biasKind == "") {
      ht = "bias n/a";
      hc = clrSilver;
   } else if(MathAbs(g_bias) < InpBiasBalanced) {
      ht = ShortToString(0x2194) + " RANGE  POC " + DoubleToString(g_biasTarget, g_digits);
      hc = clrSilver;
   } else {
      bool up = (g_bias > 0.0);
      bool trending = g_slopeKnown && MathAbs(g_slopeNorm) >= InpTrendSlopeMin &&
                      ((g_slopeNorm > 0.0) == up);
      string word = trending ? (up ? "TREND UP" : "TREND DN") : (up ? "UP" : "DOWN");
      if(!trending && MathAbs(g_bias) < InpBiasShowMin) word += "?";
      ht = (up ? SymUp() : SymDn()) + " " + word + " " +
           IntegerToString((int)MathRound(MathAbs(g_bias) * 100.0)) + "% " +
           ShortToString(0x2192) + " " + DoubleToString(g_biasTarget, g_digits);
      hc = up ? COL_UP_TXT : COL_DN_TXT;
   }

   // Build every row up front so the backdrop can be sized to the real,
   // DPI-rendered text width (a fixed width overflows on Retina/scaled Macs).
   string txt[]; color col[];
   int n = 0;
   ArrayResize(txt, 8); ArrayResize(col, 8);
   txt[n] = StringFormat("KK-VP %s [%s]", TfShort(), feedTag); col[n] = feedCol; n++;
   txt[n] = StringFormat("net M5 %+d%% M15 %+d%%",
            (int)MathRound((g_hasM5 ? g_netM5 : 0.0) * 100.0),
            (int)MathRound((g_hasM15 ? g_netM15 : 0.0) * 100.0)); col[n] = clrWhite; n++;
   txt[n] = StringFormat("ATR%% %.3f slp %s", atrPct,
            g_slopeKnown ? StringFormat("%+.2f", g_slopeNorm) : "n/a"); col[n] = clrSilver; n++;
   // Exec-health row only carries information on the real-tick feed (live spread
   // vs slip ratios). In bar-feed mode it could only ever say "exec n/a (bar
   // feed)", which was pure noise, so the row is suppressed unless ticks are on.
   int execIdx = -1;
   if(InpShowExecRow && g_tickFeed) { execIdx = n; txt[n] = "spr n/a  slip n/a"; col[n] = clrSilver; n++; }
   txt[n] = ht; col[n] = hc; n++;

   // Measure the widest row at the label font (Consolas 8pt). TextGetSize is
   // DPI-aware, so the box tracks the real pixels MT5 will draw. Include a
   // worst-case exec string so the per-tick repaint never spills the border.
   int textW = PanelTextW(txt, n);
   if(execIdx >= 0) textW = MathMax(textW, PanelTextW1("spr 999%!! slip 999%!!"));
   int innerPad = 12;
   int w = MathMax(textW + 2 * innerPad, 120);
   int tx = gutter + innerPad;       // label right edge, INSIDE the box right edge
   int x  = w + gutter;

   // Recreate in z-order on every refresh - creation order is the ONLY
   // stacking rule MT5 has, and a backdrop recreated after the labels
   // would cover the whole table.
   Kill(OBJPFX "tblBg"); Kill(OBJPFX "tblEx");
   for(int i = 0; i < 6; i++) Kill(OBJPFX "tbl" + IntegerToString(i));
   PanelBg(OBJPFX "tblBg", x, y - 3, w, n * rowH + pad * 2);

   int ty = y + pad - 2;
   int li = 0;                       // tbl0..tbl5 object index (exec uses tblEx)
   g_execRowX = tx; g_execRowY = -1;
   for(int i = 0; i < n; i++) {
      if(i == execIdx) {
         g_execRowY = ty;
         Lbl(OBJPFX "tblEx", tx, ty, txt[i], col[i]);
         UpdateExecRow();
      } else {
         Lbl(OBJPFX "tbl" + IntegerToString(li), tx, ty, txt[i], col[i]);
         li++;
      }
      ty += rowH;
   }
}

//+------------------------------------------------------------------+
//| Per-tick light updates: verdict tag, guides, ATR ruler           |
//+------------------------------------------------------------------+
void UpdateVerdictAndRuler(bool force) {
   ulong nowTk = GetTickCount64();
   if(!force && nowTk - g_lastUiTick < 250) return;
   g_lastUiTick = nowTk;

   datetime tLast = iTime(_Symbol, g_tf, 0);
   if(tLast <= 0) return;
   int ps = PeriodSeconds(g_tf);
   double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr1 = AtrAt(1);
   datetime tHistL = tLast - (datetime)(InpHistShiftBars * ps);
   datetime tHistR = tHistL + (datetime)(InpHistWidthBars * ps);

   // Live histogram refresh: committed bins + the forming-bar tick overlay,
   // so the green/red delta slices breathe with the incoming tick flow.
   DrawHistogram(tHistL, tHistR);

   // Execution-health row: sample the live tick tape, repaint in place.
   ExecSample();
   UpdateExecRow();

   // ATR ruler
   if(InpAtrRulerMult > 0.0 && atr1 > 0.0 && px > 0.0) {
      Seg(OBJPFX "atrH", tLast, px + InpAtrRulerMult * atr1, tLast + (datetime)(4 * ps), px + InpAtrRulerMult * atr1, clrDarkGray, 1, STYLE_SOLID);
      Seg(OBJPFX "atrL", tLast, px - InpAtrRulerMult * atr1, tLast + (datetime)(4 * ps), px - InpAtrRulerMult * atr1, clrDarkGray, 1, STYLE_SOLID);
   } else {
      Kill(OBJPFX "atrH"); Kill(OBJPFX "atrL");
   }

   // Near-price verdict
   if(!InpShowVerdict || !g_master.valid || g_dStep <= 0.0 || atr1 <= 0.0 || px <= 0.0) {
      Kill(OBJPFX "verd");
      Kill(OBJPFX "verdU"); Kill(OBJPFX "verdO");
      return;
   }
   // Spike-aware window: ATR(14) lags a news candle badly, so the window
   // floor is the forming bar's own range - the zone tracks the move
   // instead of reading a band price has already left.
   double range0 = iHigh(_Symbol, g_tf, 0) - iLow(_Symbol, g_tf, 0);
   double effAtr = MathMax(atr1, range0);
   // Three INDEPENDENT (overlapping) ATR windows, all configurable so the user
   // can tune/lock the feel. over/under reach FAR into their own zone (outer)
   // and a little PAST price into the other zone (inner) - the shared center
   // band dilutes the still-forming live ticks, so the % stops flickering:
   //   over  : [px - inner, px + outer]   (resistance shelf)
   //   under : [px - outer, px + inner]   (support shelf)
   //   Net   : [px - netW , px + netW ]   (center read + HIGH/LOW magnitude)
   // The center window MUST equal the ring push in RebuildAll (InpVerdictAtr)
   // so the nearVol percentrank stays apples-to-apples.
   double inner = InpVerdictInnerAtr * effAtr;
   double outer = InpVerdictOuterAtr * effAtr;
   double netW  = InpVerdictAtr      * effAtr;
   double tBu = 0.0, tSu = 0.0, tBo = 0.0, tSo = 0.0, tBn = 0.0, tSn = 0.0, nearVol = 0.0;
   for(int b = 0; b < g_histBins; b++) {
      double bpx = g_dLo + (b + 0.5) * g_dStep;
      double d   = bpx - px;
      // Skip bins outside every window (outer is the widest reach either side).
      if(MathAbs(d) > outer) continue;
      double bv = g_binBuy[b]  + g_liveBuy[b];
      double sv = g_binSell[b] + g_liveSell[b];
      double binVol = bv + sv;
      if(binVol <= 0.0) continue;
      // Tick-rule net direction (when the hybrid pass covered this bin),
      // weighted by the bar-feed volume so the sums stay scale-consistent.
      // With no ticks this collapses to (bv - sv).
      double signedV = BinDeltaNet(b, bv, sv) * binVol;
      if(d >= -inner && d <= outer) { if(signedV >= 0.0) tBo += signedV; else tSo += -signedV; }  // over
      if(d >= -outer && d <=  inner) { if(signedV >= 0.0) tBu += signedV; else tSu += -signedV; }  // under
      if(MathAbs(d) <= netW) {                                                                     // center Net + magnitude
         if(signedV >= 0.0) tBn += signedV; else tSn += -signedV;
         nearVol += binVol;
      }
   }
   double totU = tBu + tSu, totO = tBo + tSo;
   double netU = (totU > 0.0) ? (tBu - tSu) / totU : 0.0;
   double netO = (totO > 0.0) ? (tBo - tSo) / totO : 0.0;
   double tot  = tBn + tSn;
   double net  = (tot > 0.0) ? (tBn - tSn) / tot : 0.0;
   int    pct  = (int)MathRound(MathAbs(net) * 100.0);
   bool   bal  = (pct < InpVerdictBalPct) || (tot <= 0.0);
   // Flip hysteresis: live magnitude, gated direction - the arrow only
   // changes after the new direction survives InpVerdictHoldSec.
   int cand = bal ? 0 : (net > 0.0 ? 1 : -1);
   ulong nowMs = GetTickCount64();
   if(cand != g_verdShownDir) {
      if(cand != g_verdCandDir) { g_verdCandDir = cand; g_verdCandSince = nowMs; }
      else if(nowMs - g_verdCandSince >= (ulong)(MathMax(InpVerdictHoldSec, 0) * 1000))
         g_verdShownDir = cand;
   } else g_verdCandDir = cand;
   int shown = g_verdShownDir;
   bool prOk = false;
   double pr = PrStrict(g_nearRing, g_nearCount, (int)MathMax(InpNearVolLook, 1), nearVol, prOk);
   string mag = !prOk ? "" : (pr >= InpNearStrongPct ? "  HIGH" : (pr <= InpNearWeakPct ? "  LOW" : "  med"));
   long remS = (long)(tLast + ps) - (long)TimeCurrent();
   if(remS < 0) remS = 0;
   string cd = StringFormat("%dm %02ds", (int)(remS / 60), (int)(remS % 60));
   string txt = (shown == 0) ? "Net ~" + mag + "  " + cd
                : "Net " + (shown > 0 ? SymUp() : SymDn()) + " " +
                  IntegerToString(pct) + "%" + mag + "  " + cd;
   color vc = (shown == 0) ? clrSilver : (shown > 0 ? COL_UP_TXT : COL_DN_TXT);
   // All three readouts sit in clear space InpVerdLabelGapBars LEFT of the
   // histogram baseline so they never overprint the gray rows. Right-anchored
   // into a tidy column: over (price + inner) / Net (price midline) / under
   // (price - inner) - anchored at the NEAR reach so the labels stay close to
   // price and readable no matter how wide outer/Net get.
   datetime tLbl = tHistL - (datetime)(MathMax(InpVerdLabelGapBars, 0) * ps);
   int pU = (int)MathRound(MathAbs(netU) * 100.0);
   int pO = (int)MathRound(MathAbs(netO) * 100.0);
   bool balU = (pU < InpVerdictBalPct) || (totU <= 0.0);
   bool balO = (pO < InpVerdictBalPct) || (totO <= 0.0);
   string sU = balU ? "under ~" : "under " + (netU > 0.0 ? SymUp() : SymDn()) + IntegerToString(pU) + "%";
   string sO = balO ? "over ~"  : "over "  + (netO > 0.0 ? SymUp() : SymDn()) + IntegerToString(pO) + "%";
   color cU = balU ? clrSilver : (netU > 0.0 ? COL_UP_TXT : COL_DN_TXT);
   color cO = balO ? clrSilver : (netO > 0.0 ? COL_UP_TXT : COL_DN_TXT);
   Txt(OBJPFX "verdO", tLbl, px + inner, sO, cO, 8, ANCHOR_RIGHT);
   Txt(OBJPFX "verd",  tLbl, px,         txt, vc, 9, ANCHOR_RIGHT);
   Txt(OBJPFX "verdU", tLbl, px - inner, sU, cU, 8, ANCHOR_RIGHT);
}

//+------------------------------------------------------------------+
//| Trade setups - Monster breakout core on the bar-feed trail        |
//| (simplified twin: edge-clear trigger + anti-chase + net confirm;  |
//| the EA's opt-in gates - session/news/regime/overhead - are NOT    |
//| here, so this shows MORE setups than the EA would take)           |
//+------------------------------------------------------------------+

// Chart-TF near-price net at a CONFIRMED bar from the bar proxy - the same
// formula as the EA's TfNetNearAt, evaluated on the OnCalculate arrays.
double SetupNetAt(int i, double atr, const double &open[], const double &high[],
                  const double &low[], const double &close[], const long &tvol[]) {
   if(atr <= 0.0) return 0.0;
   double win = InpNetWinAtr * atr, px = close[i];
   double tB = 0.0, tS = 0.0;
   int j0 = (int)MathMax(0, i - InpTfNetLook + 1);
   for(int j = j0; j <= i; j++) {
      if(close[j] <= 0.0 || high[j] < low[j]) continue;
      double rng = MathMax(high[j] - low[j], g_mintick);
      double dp  = (close[j] - open[j]) / rng;
      double p   = (high[j] + low[j] + close[j]) / 3.0;
      if(MathAbs(p - px) <= win) {
         double v = (double)tvol[j];
         tB += v * MathMax(dp, 0.0);
         tS += v * MathMax(-dp, 0.0);
      }
   }
   double tot = tB + tS;
   return (tot > 0.0) ? (tB - tS) / tot : 0.0;
}

// Stateless rescan: walk the confirmed bars, detect breakout signals against
// the master-VP trail (BufMVah/BufMVal - levels INCLUDE the signal bar, same
// as the EA's shift-1 window), resolve each setup forward with bar extremes.
// Single-position rule: no new signal while one is unresolved (EA v1).
// Same-bar SL+TP1 touch counts as LOST (conservative - intrabar order unknown).
void RescanSetups(int rates_total, const datetime &time[], const double &open[],
                  const double &high[], const double &low[], const double &close[],
                  const long &tvol[]) {
   g_nSetups  = 0;
   g_nRejects = 0;
   if(!InpSetShow) return;
   int last = rates_total - 2;                       // newest confirmed bar
   int lb   = ClampI(InpSetLookback, 50, 5000);
   int i0   = (int)MathMax(g_masterLen + 1, rates_total - lb);
   if(last < i0 + 2) return;
   // ATR aligned to bar index: arr[0] = bar i0-1 (oldest), arr[k] = bar i0-1+k.
   int nAtr = last - (i0 - 1) + 1;
   double atrArr[];
   if(CopyBuffer(g_hAtrChart, 0, rates_total - 1 - last, nAtr, atrArr) != nAtr) return;
   int activeEnd = -1;        // bar index where the open setup resolves (last+1 = still open)
   for(int i = i0; i <= last; i++) {
      double vah  = BufMVah[i],     val  = BufMVal[i];
      double vahP = BufMVah[i - 1], valP = BufMVal[i - 1];
      double atr  = atrArr[i - (i0 - 1)];
      double atrP = atrArr[i - 1 - (i0 - 1)];
      if(vah == EMPTY_VALUE || vahP == EMPTY_VALUE || atr <= 0.0 || atrP <= 0.0) continue;
      double dL  = close[i] - vah,      dS  = val - close[i];
      double dLP = close[i - 1] - vahP, dSP = valP - close[i - 1];
      // RAW trigger = fresh edge clear only; the gates below decide its fate
      // (so every decision - taken or skipped - is visible on the chart).
      bool rawLong  = dL > InpSetEntryBufAtr * atr && dLP <= InpSetEntryBufAtr * atrP;
      bool rawShort = dS > InpSetEntryBufAtr * atr && dSP <= InpSetEntryBufAtr * atrP;
      if(!rawLong && !rawShort) continue;
      int    dir  = rawLong ? 1 : -1;
      double edge = rawLong ? vah : val;
      double dist = rawLong ? dL : dS;
      double mpy  = (dir > 0) ? high[i] + 0.4 * atr : low[i] - 0.4 * atr;
      if(i <= activeEnd) {
         AddReject(time[i], dir, mpy, "pos open");
         continue;
      }
      if(InpSetMaxDistAtr > 0.0 && dist > InpSetMaxDistAtr * atr) {
         AddReject(time[i], dir, mpy, StringFormat("chase %.1fATR", dist / atr));
         continue;
      }
      double net = SetupNetAt(i, atr, open, high, low, close, tvol);
      if((dir > 0 && net < InpSetNetMin) || (dir < 0 && net > -InpSetNetMin)) {
         // Direction language instead of signed-percent algebra: a long needs
         // BUY flow, a short needs SELL flow. Same-side-but-weak reads as
         // "buy 33% < 50%" (had < required); WRONG side reads as "opp buy 79%".
         int pct  = (int)MathRound(MathAbs(net) * 100.0);
         int need = (int)MathRound(InpSetNetMin * 100.0);
         bool sameSide = (dir > 0) ? (net >= 0.0) : (net <= 0.0);
         string whyTxt;
         if(sameSide)
            whyTxt = StringFormat("%s %d%% < %d%%", dir > 0 ? "buy" : "sell", pct, need);
         else
            whyTxt = StringFormat("opp %s %d%%", dir > 0 ? "sell" : "buy", pct);
         AddReject(time[i], dir, mpy, whyTxt);
         continue;
      }
      // Regime veto (opt-in): a FULL EMA stack aligned AGAINST the trade
      // blocks the entry even with volume confirmation. Checked after the
      // net gate so the marker means "volume said yes, EMA regime said no".
      if(InpSetEmaFilter && g_emaSynced) {
         double e1 = BufEma1[i], e2 = BufEma2[i], e3 = BufEma3[i], e4 = BufEma4[i];
         bool emaOk = (e1 > 0.0 && e2 > 0.0 && e3 > 0.0 && e4 > 0.0 &&
                       e1 != EMPTY_VALUE && e2 != EMPTY_VALUE &&
                       e3 != EMPTY_VALUE && e4 != EMPTY_VALUE);
         bool oppAligned = emaOk &&
            ((dir > 0) ? (e1 < e2 && e2 < e3 && e3 < e4)
                       : (e1 > e2 && e2 > e3 && e3 > e4));
         if(oppAligned) {
            AddReject(time[i], dir, mpy, "EMA opp");
            continue;
         }
      }
      double entry = close[i];
      double sl = (dir > 0) ? MathMin(edge - InpSetSlBufAtr * atr, entry - InpSetSlAtrMult * atr)
                            : MathMax(edge + InpSetSlBufAtr * atr, entry + InpSetSlAtrMult * atr);
      double risk = MathAbs(entry - sl);
      if(risk <= g_mintick) continue;
      double tp1 = entry + dir * InpSetTp1R * risk;
      double tp2 = entry + dir * InpSetTp2R * risk;
      int status = 0, jEnd = -1;
      // BE ratchet (opt-in): once a bar's extreme reaches the trigger profit,
      // the working stop jumps to entry +/- the BE buffer. The lift applies
      // from the NEXT bar - the intrabar arm-then-stop order is unknowable
      // from OHLC, so a same-bar trigger+retrace stays a LOST (conservative).
      double slEff  = sl;
      bool   beDone = false;
      double beTrig = entry + dir * InpSetBeTrigR * risk;
      double beLvl  = entry + dir * InpSetBeBufAtr * atr;
      for(int j = i + 1; j <= last; j++) {
         bool hitSl = (dir > 0) ? (low[j]  <= slEff) : (high[j] >= slEff);
         bool hitTp = (dir > 0) ? (high[j] >= tp1)   : (low[j]  <= tp1);
         if(hitSl) { status = beDone ? 3 : 2; jEnd = j; break; }
         if(hitTp) { status = 1; jEnd = j; break; }
         if(InpSetBeRatchet && !beDone &&
            ((dir > 0) ? (high[j] >= beTrig) : (low[j] <= beTrig))) {
            beDone = true;
            slEff  = (dir > 0) ? MathMax(slEff, beLvl) : MathMin(slEff, beLvl);
         }
      }
      if(g_nSetups >= ArraySize(g_setups)) ArrayResize(g_setups, g_nSetups + 32);
      g_setups[g_nSetups].t0     = time[i];
      g_setups[g_nSetups].tEnd   = (jEnd > 0) ? time[jEnd] : 0;
      g_setups[g_nSetups].dir    = dir;
      g_setups[g_nSetups].status = status;
      g_setups[g_nSetups].entry  = entry;
      g_setups[g_nSetups].sl     = sl;
      g_setups[g_nSetups].tp1    = tp1;
      g_setups[g_nSetups].tp2    = tp2;
      g_setups[g_nSetups].edge   = edge;
      g_nSetups++;
      activeEnd = (jEnd > 0) ? jEnd : last + 1;    // single open setup at a time
   }
}

// Display-only position size for the E label: risk InpSetRiskPct of the account
// balance across the entry->SL distance, normalized to the broker volume grid.
// Mirrors the EA's ComputeLot (TICK_VALUE/TICK_SIZE value-per-price, contract-size
// fallback). Returns 0 when there is no risk budget or distance to size against.
double SetupLot(double riskDist) {
   if(riskDist <= 0.0) return 0.0;
   double budget = MathMax(AccountInfoDouble(ACCOUNT_BALANCE) * InpSetRiskPct / 100.0, 0.0);
   if(budget <= 0.0) return 0.0;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double valPerPricePerLot = (tv > 0.0 && ts > 0.0) ? (tv / ts)
                              : SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(valPerPricePerLot <= 0.0) return 0.0;
   double lot = budget / (riskDist * valPerPricePerLot);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot > maxLot) lot = maxLot;
   if(step > 0.0)   lot = MathFloor(lot / step + 1e-9) * step;   // quantize down only
   if(lot < minLot) lot = minLot;
   return lot;
}

void DrawSetups(int rates_total, const datetime &time[]) {
   ObjectsDeleteAll(0, OBJPFX "st");
   if(!InpSetShow || g_nSetups <= 0) return;
   int ps = PeriodSeconds(g_tf);
   int keep  = ClampI(InpSetKeep, 1, 100);
   int first = (int)MathMax(0, g_nSetups - keep);
   datetime tNow = time[rates_total - 1];
   color colTp2 = C'38,166,154';
   for(int k = first; k < g_nSetups; k++) {
      string idp = OBJPFX "st" + IntegerToString(k) + "_";
      datetime tR = (g_setups[k].tEnd > 0) ? g_setups[k].tEnd : tNow;
      if(tR < g_setups[k].t0 + 5 * ps) tR = g_setups[k].t0 + (datetime)(5 * ps);
      // The broken master edge AT the signal bar: a short dim-cyan dash
      // leading into the entry - shows which level this breakout cleared
      // without dragging full history trails across the chart.
      Seg(idp + "vp", g_setups[k].t0 - (datetime)(6 * ps), g_setups[k].edge,
          g_setups[k].t0 + (datetime)(2 * ps), g_setups[k].edge, C'0,140,156', 1, STYLE_DASH);
      Seg(idp + "e",  g_setups[k].t0, g_setups[k].entry, tR, g_setups[k].entry, clrSilver, 2, STYLE_SOLID);
      Seg(idp + "sl", g_setups[k].t0, g_setups[k].sl,    tR, g_setups[k].sl,    COL_SELL,  1, STYLE_SOLID);
      Seg(idp + "t1", g_setups[k].t0, g_setups[k].tp1,   tR, g_setups[k].tp1,   COL_BUY,   1, STYLE_SOLID);
      Seg(idp + "t2", g_setups[k].t0, g_setups[k].tp2,   tR, g_setups[k].tp2,   colTp2,    1, STYLE_DOT);
      double lot = SetupLot(MathAbs(g_setups[k].entry - g_setups[k].sl));
      Txt(idp + "eT",  g_setups[k].t0, g_setups[k].entry,
          "E - " + DoubleToString(lot, 2) + " - " + DoubleToString(g_setups[k].entry, g_digits),
          clrSilver, 8, ANCHOR_LEFT_LOWER);
      Txt(idp + "slT", g_setups[k].t0, g_setups[k].sl,  "SL "  + DoubleToString(g_setups[k].sl,  g_digits), COL_DN_TXT, 8, ANCHOR_LEFT_LOWER);
      Txt(idp + "t1T", g_setups[k].t0, g_setups[k].tp1, "TP1 " + DoubleToString(g_setups[k].tp1, g_digits), COL_UP_TXT, 8, ANCHOR_LEFT_LOWER);
      Txt(idp + "t2T", g_setups[k].t0, g_setups[k].tp2, "TP2 " + DoubleToString(g_setups[k].tp2, g_digits), colTp2,     8, ANCHOR_LEFT_LOWER);
      string oc  = (g_setups[k].status == 1) ? "WON"
                   : (g_setups[k].status == 2) ? "LOST"
                   : (g_setups[k].status == 3) ? "BE" : "OPEN";
      color  occ = (g_setups[k].status == 1) ? COL_UP_TXT
                   : (g_setups[k].status == 2) ? COL_DN_TXT : clrSilver;
      // Verdict sits to the LEFT of (in front of) the entry label: anchored on its
      // right edge one bar before the entry bar so the two never overlap.
      Txt(idp + "o", g_setups[k].t0 - (datetime)ps, g_setups[k].entry, oc + " ", occ, 9, ANCHOR_RIGHT_LOWER);
   }
   // Rejected triggers: a small x + reason at the trigger bar (above the
   // high for long triggers, below the low for shorts).
   if(InpSetShowRejects && g_nRejects > 0) {
      int rKeep  = ClampI(InpSetRejKeep, 1, 200);
      int rFirst = (int)MathMax(0, g_nRejects - rKeep);
      string xMark = ShortToString(0x00D7);     // multiplication sign as the x glyph
      for(int k = rFirst; k < g_nRejects; k++) {
         string rid = OBJPFX "stR" + IntegerToString(k);
         ENUM_ANCHOR_POINT a = (g_rejects[k].dir > 0) ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER;
         Txt(rid, g_rejects[k].t, g_rejects[k].py,
             xMark + (g_rejects[k].dir > 0 ? "L " : "S ") + g_rejects[k].why,
             C'255,152,0', 7, a);
      }
   }
}

// EMA zone ribbon fill: Pine bullishZone/bearishZone verbatim - the ribbon
// (drawn between EMA 1 and 2) lights only while the FULL stack is aligned.
void FillEmaZone(int from, int rates_total) {
   if(!InpShowEmaZone) return;
   for(int i = (int)MathMax(from, 0); i < rates_total; i++) {
      double e1 = BufEma1[i], e2 = BufEma2[i], e3 = BufEma3[i], e4 = BufEma4[i];
      bool ok = (e1 > 0.0 && e2 > 0.0 && e3 > 0.0 && e4 > 0.0 &&
                 e1 != EMPTY_VALUE && e2 != EMPTY_VALUE &&
                 e3 != EMPTY_VALUE && e4 != EMPTY_VALUE);
      bool bull = ok && e1 > e2 && e2 > e3 && e3 > e4;
      bool bear = ok && e1 < e2 && e2 < e3 && e3 < e4;
      if(bull || bear) {
         BufZoneA[i] = e1;
         BufZoneB[i] = e2;
         BufZoneC[i] = bull ? 0.0 : 1.0;
      } else {
         BufZoneA[i] = EMPTY_VALUE;
         BufZoneB[i] = EMPTY_VALUE;
      }
   }
}

//+------------------------------------------------------------------+
//| OnCalculate / OnTimer                                            |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[]) {
   // Access expiry (server-time): stop ALL calculation once past the baked date.
   if(g_blocked) return rates_total;
   if(KK_AccessExpired(ACCESS_EXPIRY)) { VizBlock(); return rates_total; }
   g_rt = rates_total;
   if(rates_total < g_masterLen + InpAtrLen + 5) return rates_total;

   // --- trail buffers (bar feed, capped to the most recent InpTrailBars) ---
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   if(prev_calculated <= 0) {
      ArrayInitialize(BufMPoc, EMPTY_VALUE);
      ArrayInitialize(BufMVah, EMPTY_VALUE);
      ArrayInitialize(BufMVal, EMPTY_VALUE);
      ArrayInitialize(BufLPoc, EMPTY_VALUE);
   }
   // --- EMA overlay buffers (also feed the setup-engine EMA veto) ---
   if(InpShowEmas || InpSetEmaFilter) {
      // Full history on the first successful pass (a handle may still be
      // calculating right after init - retry until all four copies land),
      // then only the live tail. A short/failed copy never poisons a buffer:
      // it just re-arms the full sync.
      bool wasSynced = g_emaSynced;
      int need = wasSynced ? rates_total - prev_calculated + 1 : rates_total;
      if(prev_calculated <= 0) need = rates_total;
      bool allOk = true;
      if(CopyBuffer(g_hEma[0], 0, 0, need, BufEma1) < need) allOk = false;
      if(CopyBuffer(g_hEma[1], 0, 0, need, BufEma2) < need) allOk = false;
      if(CopyBuffer(g_hEma[2], 0, 0, need, BufEma3) < need) allOk = false;
      if(CopyBuffer(g_hEma[3], 0, 0, need, BufEma4) < need) allOk = false;
      g_emaSynced = allOk;
      if(allOk)
         FillEmaZone((wasSynced && prev_calculated > 0) ? prev_calculated - 1 : 0, rates_total);
   } else if(prev_calculated <= 0) {
      ArrayInitialize(BufEma1, EMPTY_VALUE);
      ArrayInitialize(BufEma2, EMPTY_VALUE);
      ArrayInitialize(BufEma3, EMPTY_VALUE);
      ArrayInitialize(BufEma4, EMPTY_VALUE);
      ArrayInitialize(BufZoneA, EMPTY_VALUE);
      ArrayInitialize(BufZoneB, EMPTY_VALUE);
   }

   int firstWanted = (int)MathMax(g_masterLen - 1, rates_total - ClampI(InpTrailBars, 50, 100000));
   if(start < firstWanted) start = firstWanted;
   for(int i = start; i < rates_total; i++) {
      double poc, vah, val;
      TrailAt(high, low, close, tick_volume, i, g_masterLen, poc, vah, val);
      BufMPoc[i] = poc; BufMVah[i] = vah; BufMVal[i] = val;
      if(i >= g_localLen - 1) {
         TrailAt(high, low, close, tick_volume, i, g_localLen, poc, vah, val);
         BufLPoc[i] = poc;
      } else BufLPoc[i] = EMPTY_VALUE;
   }

   // --- heavy rebuild once per completed chart bar ---
   datetime barT = time[rates_total - 1];
   if(barT != g_lastBarTime) {
      RebuildAll();
      RescanSetups(rates_total, time, open, high, low, close, tick_volume);
      DrawSetups(rates_total, time);
      g_lastBarTime = barT;
   } else {
      UpdateLiveTicks();
      UpdateVerdictAndRuler(false);
   }
   ChartRedraw();
   return rates_total;
}

void OnTimer() {
   // Access expiry: in a quiet market OnCalculate may not fire, so enforce here too.
   if(g_blocked) return;
   if(KK_AccessExpired(ACCESS_EXPIRY)) { VizBlock(); return; }
   // Right after attach the broker tick history may still be syncing and the
   // first CopyTicksRange comes back empty, dropping the build onto the bar
   // fallback until the NEXT bar. Retry the full rebuild until the tick feed
   // lands, then this path goes quiet (per-bar rebuilds take over).
   if(InpUseRealTicks && !g_tickFeed) {
      ulong now = GetTickCount64();
      if(now - g_tickRetryMs >= 5000) {
         g_tickRetryMs = now;
         RebuildAll();
      }
   }
   // keeps the countdown/verdict moving in quiet markets with no inbound ticks
   UpdateLiveTicks();
   UpdateVerdictAndRuler(true);
   ChartRedraw();
}
//+------------------------------------------------------------------+
