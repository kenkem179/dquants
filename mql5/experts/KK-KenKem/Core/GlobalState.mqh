#ifndef GLOBALSTATE_MQH
#define GLOBALSTATE_MQH
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// GLOBAL VARIABLES & STATE
// Trade tracking, indicators, runtime state, and state persistence
//================================================================

// Risk management tracking variables
double peakAccountBalance = 0;  // Track all-time peak balance for drawdown calculation
int consecutiveLosses = 0;
int highRiskTradesInSession = 0;  // Track high-risk trades per session (configurable limit)

// Per-entry-type consecutive loss tracking (8 types: L-E1, L-E2, L-E3, L-E4, S-E1, S-E2, S-E3, S-E4)
int consecutiveLosses_LE1 = 0, consecutiveLosses_LE2 = 0, consecutiveLosses_LE3 = 0, consecutiveLosses_LE4 = 0;
int consecutiveLosses_SE1 = 0, consecutiveLosses_SE2 = 0, consecutiveLosses_SE3 = 0, consecutiveLosses_SE4 = 0;
datetime blockedUntil_LE1 = 0, blockedUntil_LE2 = 0, blockedUntil_LE3 = 0, blockedUntil_LE4 = 0;
datetime blockedUntil_SE1 = 0, blockedUntil_SE2 = 0, blockedUntil_SE3 = 0, blockedUntil_SE4 = 0;

// Account-level drawdown tracking
datetime drawdownBlockedUntil = 0;
datetime blackSwanBlockedUntil = 0;
bool drawdownTriggered = false;
bool inRecoveryMode = false;  // Recovery mode: reduced lot size until drawdown recovers
bool inSoftBlockMode = false; // Soft block: extreme DD reached, trade with SOFT_BLOCK_LOT_MULTIPLIER (default 20%)
bool inPropHardBlock = false; // Prop hard block: MADE_FOR_PROP_TRADING + extreme DD = zero trading

// Profit Protection (High Water Mark) tracking
bool inProfitProtectionMode = false;  // Protect profits by reducing risk when giving back gains
double profitFloor = 0;               // Minimum equity to protect (calculated from peak)

// Winning Streak Cooldown tracking
int consecutiveWins = 0;              // Track consecutive wins
bool inWinStreakCooldown = false;     // Cooldown mode after winning streak
int winStreakCooldownRemaining = 0;   // Trades remaining in cooldown

// Recovery Lot Ladder: gradual 10% step adjustments per entry
double recoveryLotMult_E1 = 1.0;      // E1 current multiplier (0.4-1.0)
double recoveryLotMult_E2 = 1.0;      // E2 current multiplier (0.4-1.0)
double recoveryLotMult_E3 = 1.0;      // E3 current multiplier (0.4-1.0)
double recoveryLotMult_E4 = 1.0;      // E4 current multiplier (0.4-1.0)
double recoveryLotMult_E5 = 1.0;      // E5 current multiplier (0.4-1.0)

// Peak Balance Decay: gradual peak easing during recovery mode
datetime peakBalanceSetTime      = 0;   // When peak was last set (for grace period calc)
datetime lastPeakDecayTime       = 0;   // When decay was last applied
double   originalPeakAtRecovery  = 0;   // Peak snapshot when recovery started (for max cap)

// Daily loss tracking (P0 protection)
double dailyStartBalance = 0;
datetime currentDate = 0;
bool dailyLossLimitReached = false;

// Daily logging for entry detection statistics (write-only, no reload)
datetime lastEntryStatsLogDate = 0;

// News filter variables
struct NewsEvent {
    datetime time;
    string currency;
    string event;
    int importance;  // 1=Low, 2=Medium, 3=High
};
NewsEvent upcomingNews[];
datetime lastNewsUpdate = 0;
const int NEWS_UPDATE_INTERVAL = 3600; // Update news every hour

// Global variables
double accountBalance;
double maxLossUSD;
string alertMessage = "";

// SESSION TRACKING
string currentSession = "NONE";       // Current trading session: "ASIA", "EU", "US", or "NONE"
int tradeSLTPCountInSession = 0;      // Count of trades that hit SL/TP in current session (legacy, informational)
int sessionLossCount = 0;             // Actual losses (negative PnL) in current session
int sessionWinCount = 0;              // Actual wins (positive PnL) in current session
int sessionBreakEvenCount = 0;        // Break-even exits (SL at entry, ~0 PnL) in current session

// DUPLICATE ENTRY PREVENTION
datetime lastEntryTime = 0;           // Track last entry timestamp

// LOSING STREAK PREVENTION
datetime lastLossTime = 0;            // Timestamp of last losing trade
datetime losingStreakBlockUntil = 0;  // Block entries until this time after 2+ losses

// Entry detection control - prevent multiple entries on same bar
int lastEntryBarIndex = -1;  // Track the last bar where an entry detection was DONE
int lastBarIndex = -999;
int currentBar = -1;
int lastSkipAlertBar = -1;  // Track last bar where skip alert was sent (prevent duplicate alerts)
int lastAlertedCrossBar = -1;
int lastBarProcessedSkips = -1;
datetime lastConnectionAlert = 0;     // Last connection alert timestamp
ulong lastProcessTickTime = 0;        // Last ProcessExistingTrades() execution time (milliseconds)
datetime lastHealthCheckTime = 0;
datetime lastNewsCountdownAlert = 0;
datetime lastNewsClosureTime = 0;     // Tracks when positions were last closed due to upcoming news
datetime lastNewsAvoidanceCheck = 0;  // Throttle news avoidance checks (once per minute)

// Startup grace period (don't alert immediately on load)
datetime eaStartTime = 0;
int entryDetectedCount = 0;           // Entry detected counter

// Entry detection failure tracking (for diagnostic alerts)
// Statistics-based tracking (minimal memory, no string operations)
struct EntryStats {
    int le1_attempts, le1_success;
    int se1_attempts, se1_success;
    int le2_attempts, le2_success;
    int se2_attempts, se2_success;
    int le3_attempts, le3_success;
    int se3_attempts, se3_success;
    int le4_attempts, le4_success;
    int se4_attempts, se4_success;
    // Track most common failure reasons (simple counters)
    int le1_no_cross, le1_mtf_fail, le1_momentum_fail, le1_conviction_fail, le1_trend_quality_fail, le1_htf_trend_fail;
    int se1_no_cross, se1_mtf_fail, se1_momentum_fail, se1_conviction_fail, se1_trend_quality_fail, se1_htf_trend_fail;
    int le2_no_touch, le2_mtf_fail, le2_volume_fail, le2_conviction_fail, le2_trend_quality_fail, le2_htf_trend_fail, le2_momentum_fail;
    int se2_no_touch, se2_mtf_fail, se2_volume_fail, se2_conviction_fail, se2_trend_quality_fail, se2_htf_trend_fail, se2_momentum_fail;
    int le3_trend_context_fail, le3_ema10_m3_fail, le3_ema10_m1_fail, le3_extreme_distance_fail, le3_conviction_fail, le3_trend_quality_fail, le3_di_reversal_fail;
    int se3_trend_context_fail, se3_ema10_m3_fail, se3_ema10_m1_fail, se3_extreme_distance_fail, se3_conviction_fail, se3_trend_quality_fail, se3_di_reversal_fail;
    int le4_no_cross, le4_mtf_fail, le4_momentum_fail, le4_conviction_fail, le4_trend_quality_fail, le4_sideway_fail, le4_htf_trend_fail;
    int le4_thin_cloud, le4_tenkan_kijun, le4_chikou_blocked;
    int se4_no_cross, se4_mtf_fail, se4_momentum_fail, se4_conviction_fail, se4_trend_quality_fail, se4_sideway_fail, se4_htf_trend_fail;
    int se4_thin_cloud, se4_tenkan_kijun, se4_chikou_blocked;
    int le5_attempts, le5_success;
    int se5_attempts, se5_success;
    int le5_sideway_fail, le5_stale_signal;
    int se5_sideway_fail, se5_stale_signal;
};
EntryStats entryStats;
datetime lastEntryFailureAlert = 0;

// Adaptive parameter optimization (minimal tracking)
struct AdaptiveParams {
    // E3 performance tracking
    int E3_tradeCount;
    int E3_winCount;
    double E3_winrate;
    
    // Adaptive thresholds (override inputs when active)
    double adaptive_ADX_LOW_THRESHOLD;
    double adaptive_MIN_MOMENTUM_ADX;
    
    datetime lastAdjustment;
    bool isActive;
};
AdaptiveParams adaptiveParams;

// CSV Export variables (analytics only - no trading impact)
int csvFileHandle = INVALID_HANDLE;
string currentCSVFileName = "";
int lastLoggedMonth = -1;
int lastSkippedMinute = -1;  // Track last minute when a skipped trade was logged
int lastCSVInitMinute = -1;  // Avoid repeated monthly init checks per second

// Risk cap logging - avoid repetitive logs
double lastLoggedRiskCapValue = 0;
// CSV Buffering for performance (batch writes)
struct CSVBuffer {
    string data[50];  // Buffer up to 50 rows
    int count;
};
CSVBuffer csvBuffer;
datetime lastCSVFlush = 0;
const int CSV_FLUSH_INTERVAL = 600;  // Flush every 10 minutes
const int CSV_BUFFER_SIZE = 50;     // Max buffer size

enum TIMEFRAMES {TF_1M = 0, TF_3M = 1, TF_5M = 2, TF_15M = 3};  // Removed M10 (unused)
enum EMA_PERIODS {EMA_10 = 0, EMA_25 = 1, EMA_75 = 2, EMA_100 = 3, EMA_200 = 4};

// Timeframe index constants - match TIMEFRAMES enum values above
// TF0-TF3 are active; TF4 reserved for future H1 anchor role
#define TF0 0    // Primary (default M1)
#define TF1 1    // Confirmation (default M3)
#define TF2 2    // Context (default M5)
#define TF3 3    // Regime (default M15)
#define TF4 4    // Anchor (default H1, reserved)
#define NUM_TF 4 // Active timeframe count

// EMA index constants - match EMA_PERIODS enum values above
#define EMA0 0    // Fast (default 10)
#define EMA1 1    // Signal (default 25)
#define EMA2 2    // Pullback (default 75)
#define EMA3 3    // Bounce (default 100)
#define EMA4 4    // Anchor (default 200)
#define NUM_EMA 5 // EMA count

// Runtime-configurable arrays (populated in OnInit from INPUT_TFn / INPUT_EMAn_PERIOD)
ENUM_TIMEFRAMES TF_ARRAY[5];
int EMA_PERIOD_ARRAY[5];

int emaHandles[NUM_TF][NUM_EMA];  // [timeframe][ema_period] - 4 TFs (M1,M3,M5,M15) x 5 EMAs
// EMA buffers - 3D array structure using dynamic arrays
// [timeframe][ema_period] - same indexing as emaHandles
double emaBuffers[NUM_TF * NUM_EMA][30]; // Fixed-size array to simulate [4][5][bufferSize]

// ADX handles for different timeframes using 2D array
// Array structure: adxHandles[timeframe_index][0] where timeframe_index:
// 0=M1, 1=M3, 2=M5, 3=M15
int adxHandles[4];
int adxShortHandle;  // ADX(9) for E3 micro-trend detection (faster reversal signals)
int rsiHandle; // RSI for super trend detection (M1)

// Ichimoku Cloud handles for trend quality bonus (M1 and M3 only)
int ichimokuHandles[2];  // 0=M1, 1=M3

// Cached RSI handles per timeframe to avoid re-creating handles repeatedly
// Index mapping matches TIMEFRAMES enum: 0=M1, 1=M3, 2=M5, 3=M10, 4=M15
int rsiHandlesTF[5] = {INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE};
int rsiHandlePeriodTF[5] = {0,0,0,0,0};

// Trend state enum
enum TREND_STATE {TREND_NONE, TREND_BULL, TREND_BEAR};

// Entry type enum for fast trade type identification (replaces StringFind)
enum ENTRY_TYPE {
    ENTRY_UNKNOWN = 0,
    ENTRY_L_E1 = 1,
    ENTRY_S_E1 = 2,
    ENTRY_L_E2 = 3,
    ENTRY_S_E2 = 4,
    ENTRY_L_E3 = 5,
    ENTRY_S_E3 = 6,
    ENTRY_L_E4 = 7,
    ENTRY_S_E4 = 8,
    ENTRY_L_E5 = 9,
    ENTRY_S_E5 = 10
};

// Alert type enum for fast message type identification (replaces string comparison)
enum ALERT_TYPE {
    ALERT_ENTRY = 0,
    ALERT_SKIP = 1,
    ALERT_CLOSED_WON = 2,
    ALERT_CLOSED_LOST = 3,
    ALERT_PARTIAL_TP = 4,
    ALERT_EARLY_EXIT = 5,
    ALERT_SL_TO_BREAKEVEN = 6,
};

// Helper function to convert ALERT_TYPE to string for CSV export
string AlertTypeToString(ALERT_TYPE alertType) {
    switch(alertType) {
        case ALERT_ENTRY: return "ENTRY";
        case ALERT_SKIP: return "SKIP";
        case ALERT_CLOSED_WON: return "CLOSED_WON";
        case ALERT_CLOSED_LOST: return "CLOSED_LOST";
        case ALERT_PARTIAL_TP: return "PARTIAL_TP";
        case ALERT_EARLY_EXIT: return "EARLY_EXIT";
        case ALERT_SL_TO_BREAKEVEN: return "SL_TO_BREAKEVEN";
        default: return "UNKNOWN";
    }
}

// Get entry number (1, 2, 3, or 4) from ENTRY_TYPE enum
int GetEntryNumber(ENTRY_TYPE entryType) {
    if (entryType == ENTRY_L_E1 || entryType == ENTRY_S_E1) return 1;
    if (entryType == ENTRY_L_E2 || entryType == ENTRY_S_E2) return 2;
    if (entryType == ENTRY_L_E3 || entryType == ENTRY_S_E3) return 3;
    if (entryType == ENTRY_L_E4 || entryType == ENTRY_S_E4) return 4;
    if (entryType == ENTRY_L_E5 || entryType == ENTRY_S_E5) return 5;
    return 0;
}

// Helper functions for entry type identification
bool IsE4Entry(ENTRY_TYPE entryType) {
    return (entryType == ENTRY_L_E4 || entryType == ENTRY_S_E4);
}

bool IsE5Entry(ENTRY_TYPE entryType) {
    return (entryType == ENTRY_L_E5 || entryType == ENTRY_S_E5);
}

// Per-tick caching to avoid redundant indicator calls
int lastCachedBar = -1;
int lastCachedM3Bar = -1;  // Track M3 bar separately for E3 history caching
struct CachedIndicators {
    // ADX(14) values [M1, M3, M5, M15]
    double adx[4];
    double diPlus[4];
    double diMinus[4];
    // ADX(9) values for micro-trend detection (M1 only)
    double adxShort;
    double diPlusShort;
    double diMinusShort;
    // M3 historical data for E3 exhaustion (updated once per M3 bar)
    double rsiM3[6];      // M3 RSI history [0]=current, [5]=oldest
    double adxM3[6];      // M3 ADX history
    double diPlusM3[6];   // M3 DI+ history
    double diMinusM3[6];  // M3 DI- history
    bool m3HistoryValid;  // True if M3 history was fetched successfully
    // Common price points
    double currentPrice;
    double prevPrice;
    double high;
    double low;
    // Momentum results
    bool hasSufficientBullMomentum;
    bool hasSufficientBearMomentum;
    TREND_STATE superTrendE1;
    TREND_STATE superTrendE2;
    // Ichimoku Cloud values (M1 and M3)
    double ichimokuSpanA_M1_Current;
    double ichimokuSpanB_M1_Current;
    double ichimokuSpanA_M1_Future;
    double ichimokuSpanB_M1_Future;
    double ichimokuSpanA_M3_Current;  // E4: Current cloud for cross detection (Pine parity)
    double ichimokuSpanB_M3_Current;  // E4: Current cloud for cross detection (Pine parity)
    double ichimokuSpanA_M3_Future;
    double ichimokuSpanB_M3_Future;
    // E4 quality filters: Tenkan/Kijun/Chikou (M3 only for efficiency)
    double ichimokuTenkan_M3;
    double ichimokuKijun_M3;
    double ichimokuChikou_M3;
    double priceM3_26BarsAgo;  // E4: M3 price 26 bars ago for Chikou clearance check
    // ATR values for SL calculation (M1 only, period 14)
    double atrM1;
    double atrM3;  // M3 ATR (E4 cloud + E5 multi-TF sideway)
    double atrM5;  // E5: M5 ATR for multi-TF sideway scoring
    // Trend weakening detection (for Early Exit, Partial TP, TP Extension)
    bool isTrendWeakeningBull;  // True if bullish trend losing steam (ADX declining OR DI narrowing)
    bool isTrendWeakeningBear;  // True if bearish trend losing steam
    bool valid;
};
CachedIndicators cache;

// Trade structure to replace parallel arrays
struct Trade {
    string type;           // "L-E1", "S-E1", "L-E2", "S-E2" (kept for display/logging)
    ENTRY_TYPE entryType;  // Fast enum for type checking (replaces StringFind)
    string id;             // unique timestamp-based trade ID
    double entryPrice;     // entry price
    double stopLoss;       // stop loss price
    double takeProfit;     // take profit price
    double originalTP;     // original TP for reference
    double rawSLDistancePips;      // Structural SL distance before buffering
    double bufferedSLDistancePips; // Final SL distance after spread buffer/capping
    int entryBar;          // bar index when trade was entered
    bool isLong;           // true for long, false for short
    string status;         // "OPEN", "WIN", "LOSS"
    double bestPrice;      // best price achieved during trade
    int bestQualityScore;  // best trend quality score during trade (for early exit on quality drop)
    int qualityDropCount;  // consecutive ticks where quality dropped below threshold
    int detectionTrendQualityScore;   // quality score captured at detection (for recovery boost logic)
    int detectionExhaustionScore;     // exhaustion score captured at detection (E3 only)
    double lotSize;        // lot size used for this trade
    int tpExtensions;      // count of TP extensions
    bool hasTakenPartialProfit;
    int ladderStageReached;    // Phase 2: 0=none, 1=stage1, 2=stage2, 3=stage3
    datetime lastLadderUpdate; // Track last ladder update to prevent spam
    ulong positionTicket;  // MT5 position ticket for fast referencing
    double pnL;            // current profit/loss in price points
    long magicNumber;      // Magic number based on timestamp (yyyyMMddHHmmss)
    bool isHighRiskTrade;  // Flag to identify high-risk trades (for time-based exit)
    datetime lastTPExtensionAttempt;  // Timestamp of last TP extension attempt (prevents spam)
    datetime lastSLModificationAttempt; // Timestamp of last SL modification attempt (prevents spam)
    bool slWasTrailed;     // Flag to track if SL was moved due to trailing (for adaptive learning)
    bool slMovedToBreakeven;  // Flag to track if SL was moved to breakeven (for adaptive learning)
    bool rMultipleBEApplied;  // Flag to track if R-Multiple BE protection was applied (independent of partial TP)
    bool qualifiesForRecoveryBoost;   // Whether trade qualified for elevated recovery risk
    long telegramMsgId;    // Telegram message ID for reply threading (0 = not set)
    long discordMsgId;     // Discord message ID for reply threading (0 = not set)
    // Smart Partial TP fields
    bool partialTPEligible;           // True once partial TP trigger is reached (wait for weakness/retrace)
    double bestPriceSinceEligible;    // Track best price after trigger for retrace calculation
    bool earlyExitAlertSent;          // Flag to prevent duplicate alert after early exit
    // Sideway early exit tracking
    int sidewayDriftCount;            // Consecutive bars where price drifts toward SL + sideway score rising
    int lastSidewayScore;             // Previous sideway score for comparison
    double lastPriceToSL;             // Previous distance to SL for comparison
    // Ichimoku cloud early exit tracking
    int insideCloudCount;             // Consecutive M1 bars where price closed inside the cloud
    // ADX drop-based exit tracking
    int adxDropCount;                 // Consecutive bars where ADX declined
    double lastAdxValue;              // ADX value recorded at previous bar check
};

// Trade tracking array - single array of Trade structs
Trade trades[];

// Companion struct for extra per-trade data added after v1.7.996
// IMPORTANT: Do NOT add fields to Trade struct directly - it causes MQL5 compiler/runtime
// issues that break backtest profitability. Use this parallel array instead.
struct TradeExtras {
    datetime entryTime;               // timestamp when trade was executed
    long discordPublicMsgId;          // Discord PUBLIC channel message ID for threading (0 = not set)
    int lastPnLZone;                  // Last reported P&L zone for premium (0=entry, 1=20%, 2=40%, etc.)
    int lastPublicPnLZone;            // Last reported P&L zone for public channel (0=entry, 1=35%, 2=70%, etc.)
    datetime lastPnLUpdateTime;       // Cooldown: last time a P&L update was sent for this trade
    int diFlipCount;                  // Consecutive M1 bars where opposing DI crossed with sufficient spread
    // Conservative Trade Management state
    bool   consInitialPartialTaken;    // Has the initial R-based partial been executed?
    double consLastActionedRLevel;     // Last R-level where SL was ratcheted
    double consCumulativeSLShift;      // Total SL shift from entry (in R units)
};
TradeExtras tradeExtras[];

// Pending limit order tracking (Phase B: Limit Order Execution)
struct PendingLimitOrder {
    ulong      orderTicket;            // MT5 order ticket from trade.BuyLimit/SellLimit
    string     tradeType;              // "L-E1", "S-E2", etc.
    ENTRY_TYPE entryType;              // Fast enum for type checking
    bool       isLong;
    double     limitPrice;             // The limit price we set
    double     stopLoss;               // SL for when it fills
    double     takeProfit;             // TP for when it fills
    double     lotSize;
    double     rawSLDistancePips;
    double     bufferedSLDistancePips;
    long       magicNumber;
    string     id;                     // Trade ID (pre-generated)
    int        signalBar;              // Bar index when signal detected (for expiration)
    int        expiryBars;             // How many bars before cancellation
    bool       isHighRiskTrade;
    bool       isActive;               // Is this slot occupied?
};
PendingLimitOrder pendingOrders[];

// Memory management
const int MAX_TRADES_IN_MEMORY = 500;

// Entry tracking variables
int openLE1Index = -1;
double openLE1EntryPrice = 0;
double openLE1SL = 0;
int openSE1Index = -1;
double openSE1EntryPrice = 0;
double openSE1SL = 0;
int openLE2Index = -1;
double openLE2EntryPrice = 0;
double openLE2SL = 0;
int openSE2Index = -1;
double openSE2EntryPrice = 0;
double openSE2SL = 0;

// EMA touch tracking variables
int lastEMACrossingUp = -1;
int lastEMACrossingDown = -1;
int lastEma75TouchUp = -1;
int lastEma75TouchDown = -1;
int lastIchiCloudCrossUp = -1;    // E4: Ichimoku cloud turned green on M1+M3
int lastIchiCloudCrossDown = -1;  // E4: Ichimoku cloud turned red on M1+M3
double lastTouchEma75Price = 0;
bool emaHistoryInitialized = false;  // Flag to track if historical EMA scan completed
double lastTouchEma100Price = 0;

string shortTermStatus = "";
int lastEma75TouchIndex = -1;
int lastEma100TouchIndex = -1;

double pipSize = PIP_SIZE;
double contractSize = CONTRACT_SIZE;
double myStandardLotSize = MY_STANDARD_LOT_SIZE;

// Spread tracking for consecutive bar check
int highSpreadBarCount = 0;
double lastSpreadPips = 0;

// Volatility-adjusted lot sizing: baseline ATR (calculated on init)
double baselineATR = 0;  // Set in OnInit from first 50 bars

// ATR percentile cache (expensive to calculate, cache per bar)
double cachedATRPercentile = 50.0;

// Dynamic TP Extension variables (ATR-based)
double dynamicTPExtensionTrigger = 25.0;  // Calculated trigger distance in pips
double dynamicTPExtensionPips = 6.0;      // Calculated extension size in pips

// Recovery Lot Ladder: Get current multiplier for entry type
double GetRecoveryLadderMult(ENTRY_TYPE entryType) {
    if (IsE1Entry(entryType)) return recoveryLotMult_E1;
    if (IsE2Entry(entryType)) return recoveryLotMult_E2;
    if (IsE3Entry(entryType)) return recoveryLotMult_E3;
    if (IsE4Entry(entryType)) return recoveryLotMult_E4;
    if (IsE5Entry(entryType)) return recoveryLotMult_E5;
    return 1.0;
}

// Recovery Lot Ladder: Check if ladder enabled for entry type
bool IsRecoveryLadderEnabled(ENTRY_TYPE entryType) {
    if (IsE1Entry(entryType)) return E1_USE_RECOVERY_LADDER;
    if (IsE2Entry(entryType)) return E2_USE_RECOVERY_LADDER;
    if (IsE3Entry(entryType)) return E3_USE_RECOVERY_LADDER;
    if (IsE4Entry(entryType)) return E4_USE_RECOVERY_LADDER;
    if (IsE5Entry(entryType)) return E5_USE_RECOVERY_LADDER;
    return false;
}

// Recovery Lot Ladder: Update multiplier on win/loss (called from RiskManager)
void UpdateRecoveryLadder(ENTRY_TYPE entryType, bool isWin) {
    if (!inRecoveryMode || !IsRecoveryLadderEnabled(entryType)) return;
    
    double step = RECOVERY_LADDER_STEP;
    double minMult = RECOVERY_LADDER_MIN_MULT;
    double maxMult = RECOVERY_LADDER_MAX_MULT;
    string entryName = "";
    
    double oldMult = 1.0;
    double newMult = 1.0;
    
    if (IsE1Entry(entryType)) {
        oldMult = recoveryLotMult_E1;
        newMult = isWin ? MathMin(maxMult, oldMult + step) : MathMax(minMult, oldMult - step);
        recoveryLotMult_E1 = newMult;
        entryName = "E1";
    } else if (IsE2Entry(entryType)) {
        oldMult = recoveryLotMult_E2;
        newMult = isWin ? MathMin(maxMult, oldMult + step) : MathMax(minMult, oldMult - step);
        recoveryLotMult_E2 = newMult;
        entryName = "E2";
    } else if (IsE3Entry(entryType)) {
        oldMult = recoveryLotMult_E3;
        newMult = isWin ? MathMin(maxMult, oldMult + step) : MathMax(minMult, oldMult - step);
        recoveryLotMult_E3 = newMult;
        entryName = "E3";
    } else if (IsE4Entry(entryType)) {
        oldMult = recoveryLotMult_E4;
        newMult = isWin ? MathMin(maxMult, oldMult + step) : MathMax(minMult, oldMult - step);
        recoveryLotMult_E4 = newMult;
        entryName = "E4";
    } else if (IsE5Entry(entryType)) {
        oldMult = recoveryLotMult_E5;
        newMult = isWin ? MathMin(maxMult, oldMult + step) : MathMax(minMult, oldMult - step);
        recoveryLotMult_E5 = newMult;
        entryName = "E5";
    }

    Print("[RECOVERY LADDER] ", entryName, " ", (isWin ? "WIN" : "LOSS"), 
          " -> Lot mult: ", DoubleToString(oldMult * 100, 0), "% -> ", DoubleToString(newMult * 100, 0), "%");
}

// Recovery Lot Ladder: Reset all multipliers to starting value
void ResetRecoveryLadders() {
    recoveryLotMult_E1 = RECOVERY_LADDER_MIN_MULT;
    recoveryLotMult_E2 = RECOVERY_LADDER_MIN_MULT;
    recoveryLotMult_E3 = RECOVERY_LADDER_MIN_MULT;
    recoveryLotMult_E4 = RECOVERY_LADDER_MIN_MULT;
    recoveryLotMult_E5 = RECOVERY_LADDER_MIN_MULT;
}

// Recovery Lot Ladder: Reset to full lots when exiting recovery
void ExitRecoveryLadders() {
    recoveryLotMult_E1 = 1.0;
    recoveryLotMult_E2 = 1.0;
    recoveryLotMult_E3 = 1.0;
    recoveryLotMult_E4 = 1.0;
    recoveryLotMult_E5 = 1.0;
    
    // Reset peak decay state
    peakBalanceSetTime     = 0;
    lastPeakDecayTime      = 0;
    originalPeakAtRecovery = 0;
}

// Simple lot size scaling when account grows (with recovery mode and volatility adjustment)
// entryType parameter enables per-entry volatility adjustment
double getScaledLotSize(ENTRY_TYPE entryType = ENTRY_L_E1, double lotMultiplier = -1.0, bool volLotAdj = false) {
    double baseLotSize = myStandardLotSize;
    
    // Scale up if account has grown
    if (consecutiveLosses <= 0 && accountBalance > INITIAL_ACCOUNT_BALANCE && INCREASE_LOT_SIZE_BASED_ON_PROFIT) {
        double growthRatio = accountBalance / INITIAL_ACCOUNT_BALANCE;
        double scaleFactor = MathMin(2, 1.0 + (growthRatio - 1.0) * 0.5);
        baseLotSize = myStandardLotSize * scaleFactor;
    }
    
    // Apply risk reduction multipliers in priority order (most severe first)
    // SOFT BLOCK: Extreme DD - micro lots (highest priority)
    if (inSoftBlockMode) {
        baseLotSize = myStandardLotSize * SOFT_BLOCK_LOT_MULTIPLIER;
    }
    // RECOVERY MODE: Account in drawdown (overrides growth scaling)
    else if (inRecoveryMode) {
        if (IsRecoveryLadderEnabled(entryType)) {
            baseLotSize = myStandardLotSize * GetRecoveryLadderMult(entryType);
        } else {
            baseLotSize = myStandardLotSize * RECOVERY_MODE_LOT_MULTIPLIER;
        }
    }
    // PROFIT PROTECTION: Giving back gains
    else if (inProfitProtectionMode) {
        baseLotSize *= PROFIT_PROTECTION_LOT_MULTIPLIER;
    }
    // WIN STREAK COOLDOWN: Reduce after consecutive wins
    else if (inWinStreakCooldown) {
        baseLotSize *= WIN_STREAK_COOLDOWN_LOT_MULT;
    }
    
    // Per-entry permanent lot reduction (e.g., E3 counter-trend is inherently riskier)
    // When caller passes lotMultiplier from EntryBase, use it directly
    if (lotMultiplier >= 0.0 && lotMultiplier < 1.0) {
        baseLotSize *= lotMultiplier;
    }
    // Fallback: resolve via IsE*Entry dispatch (backward compatibility)
    else if (lotMultiplier < 0.0 && IsE3Entry(entryType) && E3_LOT_MULTIPLIER < 1.0) {
        baseLotSize *= E3_LOT_MULTIPLIER;
    }

    // Per-entry volatility adjustment: E1/E2 trend-following may want full lots
    // E3 counter-trend benefits from reduced lots in high vol
    // When caller passes volLotAdj from EntryBase, use it directly
    bool useVolAdj = volLotAdj;
    // Fallback: resolve via IsE*Entry dispatch when lotMultiplier not passed (backward compatibility)
    if (lotMultiplier < 0.0) {
        if (IsE1Entry(entryType)) useVolAdj = VOL_LOT_ADJ_E1;
        else if (IsE2Entry(entryType)) useVolAdj = VOL_LOT_ADJ_E2;
        else if (IsE3Entry(entryType)) useVolAdj = VOL_LOT_ADJ_E3;
        else if (IsE4Entry(entryType)) useVolAdj = VOL_LOT_ADJ_E4;
        else if (IsE5Entry(entryType)) useVolAdj = VOL_LOT_ADJ_E5;
    }
    
    if (useVolAdj && baselineATR > 0 && cache.atrM1 > 0) {
        double volMultiplier = baselineATR / cache.atrM1;
        volMultiplier = MathMax(VOL_LOT_MIN_MULT, MathMin(VOL_LOT_MAX_MULT, volMultiplier));
        double preMult = baseLotSize;
        baseLotSize *= volMultiplier;
        if (showDebug) {
            PrintDebug("[VOL LOT] Base=" + DoubleToString(preMult, 2) + 
                       " x" + DoubleToString(volMultiplier, 2) + 
                       " = " + DoubleToString(baseLotSize, 2) +
                       " (ATR: " + DoubleToString(cache.atrM1/pipSize, 1) + " vs baseline " + DoubleToString(baselineATR/pipSize, 1) + ")");
        }
    }
    
    return baseLotSize;
}

// Get entry-specific risk ratio based on entry type reliability
double GetEntrySpecificRiskRatio(ENTRY_TYPE entryType, double entryMaxLossRatio = 0.0) {
    // When caller passes entry-specific ratio from EntryBase, use it directly
    if (entryMaxLossRatio > 0.0) return entryMaxLossRatio;
    // Fallback: resolve via IsE*Entry dispatch (backward compatibility)
    if (IsE1Entry(entryType))      return MAX_LOSS_RATIO_E1;  // 2.0% - early trend uncertain
    else if (IsE2Entry(entryType)) return MAX_LOSS_RATIO_E2;  // 2.8% - most reliable
    else if (IsE3Entry(entryType)) return MAX_LOSS_RATIO_E3;  // 1.5% - counter-trend risky
    else if (IsE4Entry(entryType)) return MAX_LOSS_RATIO_E4;  // E4: Same as E1 - early trend
    else if (IsE5Entry(entryType)) return MAX_LOSS_RATIO_E5;  // E5: Same as E1
    return MAX_LOSS_RATIO_E2;  // Default to E2 if unknown
}

// Calculate total unrealized P&L from all open positions
double GetTotalUnrealizedPnL() {
    double totalPnL = 0.0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol) {
            totalPnL += PositionGetDouble(POSITION_PROFIT);
        }
    }
    return totalPnL;
}

// Calculate total maximum potential loss from all open positions (distance to SL)
// This is the worst-case scenario if all trades hit their stop losses
double GetTotalMaxPotentialLoss() {
    double totalMaxLoss = 0.0;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol) {
            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double lotSize = PositionGetDouble(POSITION_VOLUME);
            long posType = PositionGetInteger(POSITION_TYPE);
            
            if(sl > 0) {  // Only count if SL is set
                double slDistance = 0;
                if(posType == POSITION_TYPE_BUY) {
                    slDistance = entryPrice - sl;  // For long, loss if price drops to SL
                } else {
                    slDistance = sl - entryPrice;  // For short, loss if price rises to SL
                }
                
                // Convert price distance to monetary loss
                double potentialLoss = (slDistance / tickSize) * tickValue * lotSize;
                totalMaxLoss += MathMax(0, potentialLoss);  // Only count positive losses
            }
        }
    }
    return totalMaxLoss;
}

// Helper: Calculate base max loss (before any multiplier)
double GetBaseMaxLoss(ENTRY_TYPE entryType = ENTRY_UNKNOWN) {
    double riskRatio = (entryType == ENTRY_UNKNOWN) ? MAX_LOSS_RATIO_E2 : GetEntrySpecificRiskRatio(entryType);
    if (consecutiveLosses <= 0 && accountBalance > INITIAL_ACCOUNT_BALANCE && INCREASE_LOT_SIZE_BASED_ON_PROFIT) {
        double scaledBalance = (accountBalance * PROFIT_SCALING_WEIGHT_CURRENT) + (INITIAL_ACCOUNT_BALANCE * PROFIT_SCALING_WEIGHT_INITIAL);
        return scaledBalance * riskRatio;
    }
    return MathMin(accountBalance * riskRatio, INITIAL_ACCOUNT_BALANCE * riskRatio);
}

// Returns reduced max loss during recovery mode (normal quality setups)
// Uses RECOVERY_MODE_LOT_MULTIPLIER x base risk (ignores DD room cap)
// SOFT BLOCK uses SOFT_BLOCK_LOT_MULTIPLIER instead (more aggressive reduction)
double GetEntryBaseMaxLossDuringRecovery(ENTRY_TYPE entryType = ENTRY_UNKNOWN) {
    double multiplier = inSoftBlockMode ? SOFT_BLOCK_LOT_MULTIPLIER : RECOVERY_MODE_LOT_MULTIPLIER;
    return GetBaseMaxLoss(entryType) * multiplier;
}

// Returns boosted max loss for high-quality setups during recovery mode
// Uses RECOVERY_MODE_BOOST_MULTIPLIER x base risk (ignores DD room cap)
// SOFT BLOCK: No boost - still uses SOFT_BLOCK_LOT_MULTIPLIER (max risk reduction)
double GetEntryBoostedMaxLossDuringRecovery(ENTRY_TYPE entryType = ENTRY_UNKNOWN) {
    // In soft block mode, even "boosted" trades use the soft block multiplier (no boost)
    double multiplier = inSoftBlockMode ? SOFT_BLOCK_LOT_MULTIPLIER : RECOVERY_MODE_BOOST_MULTIPLIER;
    return GetBaseMaxLoss(entryType) * multiplier;
}

double getMaxLossUSD(ENTRY_TYPE entryType = ENTRY_UNKNOWN) {
    // Get entry-specific risk ratio (defaults to E2 if unknown)
    double riskRatio = (entryType == ENTRY_UNKNOWN) ? MAX_LOSS_RATIO_E2 : GetEntrySpecificRiskRatio(entryType);
    
    // Calculate base max loss from entry-specific ratio
    double entryMaxLoss;
    if (consecutiveLosses <= 0 && accountBalance > INITIAL_ACCOUNT_BALANCE && INCREASE_LOT_SIZE_BASED_ON_PROFIT) {
        double scaledBalance = (accountBalance * PROFIT_SCALING_WEIGHT_CURRENT) + (INITIAL_ACCOUNT_BALANCE * PROFIT_SCALING_WEIGHT_INITIAL);
        entryMaxLoss = scaledBalance * riskRatio;
    } else {
        entryMaxLoss = MathMin(accountBalance * riskRatio, INITIAL_ACCOUNT_BALANCE * riskRatio);
    }
    
    // === DRAWDOWN PROTECTION: Cap max loss to stay within daily and account limits ===
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Use MAX POTENTIAL LOSS (worst-case if all trades hit SL) instead of floating P&L
    // This is more conservative and accurate for risk management
    double maxPotentialLoss = GetTotalMaxPotentialLoss();
    
    // Daily limit: How much room left before hitting MAX_DAILY_LOSS_RATIO
    double realizedLossToday = dailyStartBalance - currentBalance;
    double dailyLossAllowance = dailyStartBalance * MAX_DAILY_LOSS_RATIO;
    double dailyRoomLeft = dailyLossAllowance - realizedLossToday - maxPotentialLoss;
    
    // Account drawdown limit: How much room left before hitting ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN
    double lossFromPeak = peakAccountBalance - currentBalance;
    double drawdownAllowance = peakAccountBalance * ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN;
    double drawdownRoomLeft = drawdownAllowance - lossFromPeak - maxPotentialLoss;
    
    // Take the minimum of entry-specific, daily, and drawdown limits
    double cappedMaxLoss = MathMin(entryMaxLoss, MathMin(dailyRoomLeft, drawdownRoomLeft));
    
    // Never go below a minimum threshold (prevent 0 or negative lot sizes)
    double minMaxLoss = accountBalance * MIN_RISK_FLOOR_RATIO;  // Minimum risk floor to allow any trade
    cappedMaxLoss = MathMax(cappedMaxLoss, minMaxLoss);
    
    // Only log when capped value changes by more than 5% to reduce noise
    if(showDebug && (dailyRoomLeft < entryMaxLoss || drawdownRoomLeft < entryMaxLoss)) {
        if (MathAbs(cappedMaxLoss - lastLoggedRiskCapValue) > lastLoggedRiskCapValue * 0.05 || lastLoggedRiskCapValue == 0) {
            Print(StringFormat("[RISK CAP] Entry: $%.2f → Capped: $%.2f | Daily room: $%.2f | DD room: $%.2f | MaxPotLoss: $%.2f",
                  entryMaxLoss, cappedMaxLoss, dailyRoomLeft, drawdownRoomLeft, maxPotentialLoss));
            lastLoggedRiskCapValue = cappedMaxLoss;
        }
    }
    
    return cappedMaxLoss;
}

// Helper function to convert 3D indices to 2D index for emaBuffers
int GetEMABufferIndex(int timeframe, int period) {
    return timeframe * 5 + period; // Maps [tf][period] to single index (5 EMAs now)
}

//================================================================
// STATE PERSISTENCE FUNCTIONS
// Save and restore critical state variables across EA restarts
//================================================================

string GetStateFilePath() {
    // Include account ID to differentiate between different broker accounts
    long accountId = AccountInfoInteger(ACCOUNT_LOGIN);
    return "KenKem_State_" + _Symbol + "_" + IntegerToString(accountId) + ".txt";
}

string SerializeState() {
    string content = "VERSION=" + VERSION + "\n";
    content += "TIMESTAMP=" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n";
    content += "SYMBOL=" + _Symbol + "\n";
    
    // Doubles
    content += "dailyStartBalance=" + DoubleToString(dailyStartBalance, 2) + "\n";
    content += "peakAccountBalance=" + DoubleToString(peakAccountBalance, 2) + "\n";
    
    // Datetimes
    content += "drawdownBlockedUntil=" + IntegerToString(drawdownBlockedUntil) + "\n";
    content += "blackSwanBlockedUntil=" + IntegerToString(blackSwanBlockedUntil) + "\n";
    content += "lastLossTime=" + IntegerToString(lastLossTime) + "\n";
    content += "losingStreakBlockUntil=" + IntegerToString(losingStreakBlockUntil) + "\n";
    content += "lastEntryTime=" + IntegerToString(lastEntryTime) + "\n";
    
    // Bools
    content += "drawdownTriggered=" + IntegerToString(drawdownTriggered ? 1 : 0) + "\n";
    content += "inRecoveryMode=" + IntegerToString(inRecoveryMode ? 1 : 0) + "\n";
    content += "inSoftBlockMode=" + IntegerToString(inSoftBlockMode ? 1 : 0) + "\n";
    content += "dailyLossLimitReached=" + IntegerToString(dailyLossLimitReached ? 1 : 0) + "\n";
    
    // Ints
    content += "consecutiveLosses=" + IntegerToString(consecutiveLosses) + "\n";
    content += "tradeSLTPCountInSession=" + IntegerToString(tradeSLTPCountInSession) + "\n";
    content += "sessionLossCount=" + IntegerToString(sessionLossCount) + "\n";
    content += "sessionWinCount=" + IntegerToString(sessionWinCount) + "\n";
    content += "sessionBreakEvenCount=" + IntegerToString(sessionBreakEvenCount) + "\n";
    content += "highRiskTradesInSession=" + IntegerToString(highRiskTradesInSession) + "\n";
    
    // Per-entry-type arrays (compact loop)
    int consLosses[8] = {consecutiveLosses_LE1, consecutiveLosses_LE2, consecutiveLosses_LE3, consecutiveLosses_LE4,
                         consecutiveLosses_SE1, consecutiveLosses_SE2, consecutiveLosses_SE3, consecutiveLosses_SE4};
    datetime blocked[8] = {blockedUntil_LE1, blockedUntil_LE2, blockedUntil_LE3, blockedUntil_LE4,
                           blockedUntil_SE1, blockedUntil_SE2, blockedUntil_SE3, blockedUntil_SE4};
    string types[8] = {"LE1", "LE2", "LE3", "LE4", "SE1", "SE2", "SE3", "SE4"};
    
    for(int i = 0; i < 8; i++) {
        content += "consecutiveLosses_" + types[i] + "=" + IntegerToString(consLosses[i]) + "\n";
        content += "blockedUntil_" + types[i] + "=" + IntegerToString(blocked[i]) + "\n";
    }
    
    // String (session tracking for session counter reset detection)
    content += "currentSession=" + currentSession + "\n";
    
    // Adaptive parameters
    content += "adaptive_isActive=" + IntegerToString(adaptiveParams.isActive ? 1 : 0) + "\n";
    content += "adaptive_E3_tradeCount=" + IntegerToString(adaptiveParams.E3_tradeCount) + "\n";
    content += "adaptive_E3_winCount=" + IntegerToString(adaptiveParams.E3_winCount) + "\n";
    content += "adaptive_E3_winrate=" + DoubleToString(adaptiveParams.E3_winrate, 4) + "\n";
    content += "adaptive_ADX_LOW_THRESHOLD=" + DoubleToString(adaptiveParams.adaptive_ADX_LOW_THRESHOLD, 2) + "\n";
    content += "adaptive_MIN_MOMENTUM_ADX=" + DoubleToString(adaptiveParams.adaptive_MIN_MOMENTUM_ADX, 2) + "\n";
    content += "adaptive_lastAdjustment=" + IntegerToString(adaptiveParams.lastAdjustment) + "\n";
    
    // Serialize active trades with positionTicket
    content += "\n[ActiveTrades]\n";
    int activeCount = 0;
    for(int i = 0; i < ArraySize(trades); i++) {
        if(trades[i].status == "OPEN") {
            // Save ALL Trade struct fields for complete restoration
            string p = "trade_" + IntegerToString(activeCount) + "_";
            content += p + "type=" + trades[i].type + "\n";
            content += p + "entryType=" + IntegerToString(trades[i].entryType) + "\n";
            content += p + "id=" + trades[i].id + "\n";
            content += p + "entryPrice=" + DoubleToString(trades[i].entryPrice, _Digits) + "\n";
            content += p + "stopLoss=" + DoubleToString(trades[i].stopLoss, _Digits) + "\n";
            content += p + "takeProfit=" + DoubleToString(trades[i].takeProfit, _Digits) + "\n";
            content += p + "originalTP=" + DoubleToString(trades[i].originalTP, _Digits) + "\n";
            content += p + "rawSLDistancePips=" + DoubleToString(trades[i].rawSLDistancePips, 2) + "\n";
            content += p + "bufferedSLDistancePips=" + DoubleToString(trades[i].bufferedSLDistancePips, 2) + "\n";
            content += p + "entryBar=" + IntegerToString(trades[i].entryBar) + "\n";
            content += p + "entryTime=" + IntegerToString(tradeExtras[i].entryTime) + "\n";
            content += p + "isLong=" + IntegerToString(trades[i].isLong ? 1 : 0) + "\n";
            content += p + "status=" + trades[i].status + "\n";
            content += p + "bestPrice=" + DoubleToString(trades[i].bestPrice, _Digits) + "\n";
            content += p + "bestQualityScore=" + IntegerToString(trades[i].bestQualityScore) + "\n";
            content += p + "qualityDropCount=" + IntegerToString(trades[i].qualityDropCount) + "\n";
            content += p + "detectionTrendQualityScore=" + IntegerToString(trades[i].detectionTrendQualityScore) + "\n";
            content += p + "detectionExhaustionScore=" + IntegerToString(trades[i].detectionExhaustionScore) + "\n";
            content += p + "lotSize=" + DoubleToString(trades[i].lotSize, 2) + "\n";
            content += p + "tpExtensions=" + IntegerToString(trades[i].tpExtensions) + "\n";
            content += p + "hasTakenPartialProfit=" + IntegerToString(trades[i].hasTakenPartialProfit ? 1 : 0) + "\n";
            content += p + "ladderStageReached=" + IntegerToString(trades[i].ladderStageReached) + "\n";
            content += p + "lastLadderUpdate=" + IntegerToString(trades[i].lastLadderUpdate) + "\n";
            content += p + "positionTicket=" + IntegerToString(trades[i].positionTicket) + "\n";
            content += p + "pnL=" + DoubleToString(trades[i].pnL, 2) + "\n";
            content += p + "magicNumber=" + IntegerToString(trades[i].magicNumber) + "\n";
            content += p + "isHighRiskTrade=" + IntegerToString(trades[i].isHighRiskTrade ? 1 : 0) + "\n";
            content += p + "lastTPExtensionAttempt=" + IntegerToString(trades[i].lastTPExtensionAttempt) + "\n";
            content += p + "lastSLModificationAttempt=" + IntegerToString(trades[i].lastSLModificationAttempt) + "\n";
            content += p + "slWasTrailed=" + IntegerToString(trades[i].slWasTrailed ? 1 : 0) + "\n";
            content += p + "slMovedToBreakeven=" + IntegerToString(trades[i].slMovedToBreakeven ? 1 : 0) + "\n";
            content += p + "qualifiesForRecoveryBoost=" + IntegerToString(trades[i].qualifiesForRecoveryBoost ? 1 : 0) + "\n";
            content += p + "telegramMsgId=" + IntegerToString(trades[i].telegramMsgId) + "\n";
            content += p + "discordMsgId=" + IntegerToString(trades[i].discordMsgId) + "\n";
            activeCount++;
        }
    }
    content += "activeTradeCount=" + IntegerToString(activeCount) + "\n";
    
    return content;
}

bool DeserializeState(string content) {
    string lines[];
    int lineCount = StringSplit(content, '\n', lines);
    
    string fileVersion = "";
    string fileSymbol = "";
    datetime fileTimestamp = 0;
    
    for(int i = 0; i < lineCount; i++) {
        string line = lines[i];
        if(StringLen(line) == 0) continue;
        
        int sepPos = StringFind(line, "=");
        if(sepPos < 0) continue;
        
        string key = StringSubstr(line, 0, sepPos);
        string value = StringSubstr(line, sepPos + 1);
        
        // Metadata
        if(key == "VERSION") fileVersion = value;
        else if(key == "SYMBOL") fileSymbol = value;
        else if(key == "TIMESTAMP") fileTimestamp = StringToTime(value);
        
        // Doubles
        else if(key == "dailyStartBalance") dailyStartBalance = StringToDouble(value);
        else if(key == "peakAccountBalance") peakAccountBalance = StringToDouble(value);
        
        // Datetimes
        else if(key == "drawdownBlockedUntil") drawdownBlockedUntil = (datetime)StringToInteger(value);
        else if(key == "blackSwanBlockedUntil") blackSwanBlockedUntil = (datetime)StringToInteger(value);
        else if(key == "lastLossTime") lastLossTime = (datetime)StringToInteger(value);
        else if(key == "losingStreakBlockUntil") losingStreakBlockUntil = (datetime)StringToInteger(value);
        else if(key == "lastEntryTime") lastEntryTime = (datetime)StringToInteger(value);
        
        // Bools
        else if(key == "drawdownTriggered") drawdownTriggered = (StringToInteger(value) == 1);
        else if(key == "inRecoveryMode") inRecoveryMode = (StringToInteger(value) == 1);
        else if(key == "inSoftBlockMode") inSoftBlockMode = (StringToInteger(value) == 1);
        else if(key == "dailyLossLimitReached") dailyLossLimitReached = (StringToInteger(value) == 1);
        
        // Ints
        else if(key == "consecutiveLosses") consecutiveLosses = (int)StringToInteger(value);
        else if(key == "tradeSLTPCountInSession") tradeSLTPCountInSession = (int)StringToInteger(value);
        else if(key == "sessionLossCount") sessionLossCount = (int)StringToInteger(value);
        else if(key == "sessionWinCount") sessionWinCount = (int)StringToInteger(value);
        else if(key == "sessionBreakEvenCount") sessionBreakEvenCount = (int)StringToInteger(value);
        else if(key == "highRiskTradesInSession") highRiskTradesInSession = (int)StringToInteger(value);
        
        // Per-entry-type
        else if(key == "consecutiveLosses_LE1") consecutiveLosses_LE1 = (int)StringToInteger(value);
        else if(key == "consecutiveLosses_LE2") consecutiveLosses_LE2 = (int)StringToInteger(value);
        else if(key == "consecutiveLosses_LE3") consecutiveLosses_LE3 = (int)StringToInteger(value);
        else if(key == "consecutiveLosses_SE1") consecutiveLosses_SE1 = (int)StringToInteger(value);
        else if(key == "consecutiveLosses_SE2") consecutiveLosses_SE2 = (int)StringToInteger(value);
        else if(key == "consecutiveLosses_SE3") consecutiveLosses_SE3 = (int)StringToInteger(value);
        else if(key == "blockedUntil_LE1") blockedUntil_LE1 = (datetime)StringToInteger(value);
        else if(key == "blockedUntil_LE2") blockedUntil_LE2 = (datetime)StringToInteger(value);
        else if(key == "blockedUntil_LE3") blockedUntil_LE3 = (datetime)StringToInteger(value);
        else if(key == "blockedUntil_SE1") blockedUntil_SE1 = (datetime)StringToInteger(value);
        else if(key == "blockedUntil_SE2") blockedUntil_SE2 = (datetime)StringToInteger(value);
        else if(key == "blockedUntil_SE3") blockedUntil_SE3 = (datetime)StringToInteger(value);
        
        // String (session tracking)
        else if(key == "currentSession") currentSession = value;
        
        // Adaptive parameters
        else if(key == "adaptive_isActive") adaptiveParams.isActive = (StringToInteger(value) == 1);
        else if(key == "adaptive_E3_tradeCount") adaptiveParams.E3_tradeCount = (int)StringToInteger(value);
        else if(key == "adaptive_E3_winCount") adaptiveParams.E3_winCount = (int)StringToInteger(value);
        else if(key == "adaptive_E3_winrate") adaptiveParams.E3_winrate = StringToDouble(value);
        else if(key == "adaptive_ADX_LOW_THRESHOLD") adaptiveParams.adaptive_ADX_LOW_THRESHOLD = StringToDouble(value);
        else if(key == "adaptive_MIN_MOMENTUM_ADX") adaptiveParams.adaptive_MIN_MOMENTUM_ADX = StringToDouble(value);
        else if(key == "adaptive_lastAdjustment") adaptiveParams.lastAdjustment = (datetime)StringToInteger(value);
    }
    
    // Deserialize active trades
    int activeCount = 0;
    for(int i = 0; i < lineCount; i++) {
        string line = lines[i];
        if(StringLen(line) == 0) continue;
        
        int sepPos = StringFind(line, "=");
        if(sepPos < 0) continue;
        
        string key = StringSubstr(line, 0, sepPos);
        string value = StringSubstr(line, sepPos + 1);
        
        if(key == "activeTradeCount") {
            activeCount = (int)StringToInteger(value);
            if(activeCount > 0) {
                ArrayResize(trades, activeCount);
                ArrayResize(tradeExtras, activeCount);
            }
            break;
        }
    }
    
    // Parse each trade's properties
    for(int idx = 0; idx < activeCount; idx++) {
        Trade t;
        t.status = "OPEN";
        
        for(int i = 0; i < lineCount; i++) {
            string line = lines[i];
            if(StringLen(line) == 0) continue;
            
            int sepPos = StringFind(line, "=");
            if(sepPos < 0) continue;
            
            string key = StringSubstr(line, 0, sepPos);
            string value = StringSubstr(line, sepPos + 1);
            
            string prefix = "trade_" + IntegerToString(idx) + "_";
            if(StringFind(key, prefix) != 0) continue;
            
            string field = StringSubstr(key, StringLen(prefix));
            
            // Load ALL Trade struct fields (safe: unknown fields are ignored)
            if(field == "type") t.type = value;
            else if(field == "entryType") t.entryType = (ENTRY_TYPE)StringToInteger(value);
            else if(field == "id") t.id = value;
            else if(field == "entryPrice") t.entryPrice = StringToDouble(value);
            else if(field == "stopLoss") t.stopLoss = StringToDouble(value);
            else if(field == "takeProfit") t.takeProfit = StringToDouble(value);
            else if(field == "originalTP") t.originalTP = StringToDouble(value);
            else if(field == "rawSLDistancePips") t.rawSLDistancePips = StringToDouble(value);
            else if(field == "bufferedSLDistancePips") t.bufferedSLDistancePips = StringToDouble(value);
            else if(field == "entryBar") t.entryBar = (int)StringToInteger(value);
            else if(field == "entryTime") {
                if (idx < ArraySize(tradeExtras)) tradeExtras[idx].entryTime = (datetime)StringToInteger(value);
            }
            else if(field == "isLong") t.isLong = (StringToInteger(value) == 1);
            else if(field == "status") t.status = value;
            else if(field == "bestPrice") t.bestPrice = StringToDouble(value);
            else if(field == "bestQualityScore") t.bestQualityScore = (int)StringToInteger(value);
            else if(field == "qualityDropCount") t.qualityDropCount = (int)StringToInteger(value);
            else if(field == "detectionTrendQualityScore") t.detectionTrendQualityScore = (int)StringToInteger(value);
            else if(field == "detectionExhaustionScore") t.detectionExhaustionScore = (int)StringToInteger(value);
            else if(field == "lotSize") t.lotSize = StringToDouble(value);
            else if(field == "tpExtensions") t.tpExtensions = (int)StringToInteger(value);
            else if(field == "hasTakenPartialProfit") t.hasTakenPartialProfit = (StringToInteger(value) == 1);
            else if(field == "ladderStageReached") t.ladderStageReached = (int)StringToInteger(value);
            else if(field == "lastLadderUpdate") t.lastLadderUpdate = (datetime)StringToInteger(value);
            else if(field == "positionTicket") t.positionTicket = (ulong)StringToInteger(value);
            else if(field == "pnL") t.pnL = StringToDouble(value);
            else if(field == "magicNumber") t.magicNumber = (long)StringToInteger(value);
            else if(field == "isHighRiskTrade") t.isHighRiskTrade = (StringToInteger(value) == 1);
            else if(field == "lastTPExtensionAttempt") t.lastTPExtensionAttempt = (datetime)StringToInteger(value);
            else if(field == "lastSLModificationAttempt") t.lastSLModificationAttempt = (datetime)StringToInteger(value);
            else if(field == "slWasTrailed") t.slWasTrailed = (StringToInteger(value) == 1);
            else if(field == "slMovedToBreakeven") t.slMovedToBreakeven = (StringToInteger(value) == 1);
            else if(field == "qualifiesForRecoveryBoost") t.qualifiesForRecoveryBoost = (StringToInteger(value) == 1);
            else if(field == "telegramMsgId") t.telegramMsgId = (long)StringToInteger(value);
            else if(field == "discordMsgId") t.discordMsgId = (long)StringToInteger(value);
            // Unknown fields are safely ignored (forward compatibility)
        }
        
        trades[idx] = t;
    }
    
    if(activeCount > 0) {
        Print("[STATE] Loaded ", activeCount, " active trade(s) with positionTickets");
    }
    
    if(fileSymbol != _Symbol) {
        Print("[STATE] Symbol mismatch: file=", fileSymbol, " current=", _Symbol, " - using defaults");
        return false;
    }
    
    if(fileVersion != VERSION) {
        Print("[STATE] Version mismatch: file=", fileVersion, " current=", VERSION, " - attempting to use data anyway");
    }
    
    datetime now = TimeCurrent();
    int daysDiff = (int)((now - fileTimestamp) / 86400);
    if(daysDiff > 7) {
        Print("[STATE] Stale data (", daysDiff, " days old) - using defaults");
        return false;
    }
    
    if(daysDiff > 1) {
        Print("[STATE] Data is ", daysDiff, " days old - resetting drawdown state");
        drawdownBlockedUntil = 0;
        blackSwanBlockedUntil = 0;
        drawdownTriggered = false;
    }
    
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(currentBalance < peakAccountBalance * 0.5) {
        Print("[STATE] Account balance changed significantly - resetting peak balance");
        peakAccountBalance = currentBalance;
    }
    
    // Check if session changed - reset session counters if needed
    string detectedSession = GetCurrentSession();
    if(currentSession != detectedSession) {
        Print("[STATE] Session changed from ", currentSession, " to ", detectedSession, " - resetting session counters");
        tradeSLTPCountInSession = 0;
        sessionLossCount = 0;
        sessionWinCount = 0;
        sessionBreakEvenCount = 0;
        highRiskTradesInSession = 0;
        currentSession = detectedSession;
    }
    
    // Validate loaded trades against broker positions
    ValidateLoadedTradesWithBroker();
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate loaded trades still exist on broker                      |
//| Removes stale trades and recovers orphan broker positions        |
//+------------------------------------------------------------------+
void ValidateLoadedTradesWithBroker() {
    int removedCount = 0;
    int recoveredCount = 0;
    
    // Step 1: Process loaded trades that no longer exist on broker
    for (int i = ArraySize(trades) - 1; i >= 0; i--) {
        if (trades[i].status != "OPEN") continue;
        if (trades[i].positionTicket == 0) continue;
        
        // Check if position still exists on broker
        if (!PositionSelectByTicket(trades[i].positionTicket)) {
            Print("[STATE] Trade ", trades[i].id, " (ticket #", trades[i].positionTicket, 
                  ") no longer exists on broker - detecting closure reason and sending alert");
            
            // CRITICAL: Call closure detection to determine SL/TP hit and send alert
            CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
            
            // Trade status is now updated (BUY_WON, BUY_LOST, etc.)
            // The alert has been sent by CheckTradeStatusOnBrokerBeforeUpdating
            removedCount++;
        }
    }
    
    // Step 2: Check for orphan positions on broker (our positions not in trades array)
    for (int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        
        // Check if this is our trade (by comment)
        string comment = PositionGetString(POSITION_COMMENT);
        if (StringFind(comment, "KenKemST") < 0) continue;
        
        // Check if already tracked
        bool found = false;
        for (int j = 0; j < ArraySize(trades); j++) {
            if (trades[j].positionTicket == ticket) {
                found = true;
                break;
            }
        }
        
        if (!found) {
            // Orphan position - add to tracking
            Trade orphanTrade;
            orphanTrade.positionTicket = ticket;
            orphanTrade.entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            orphanTrade.stopLoss = PositionGetDouble(POSITION_SL);
            orphanTrade.takeProfit = PositionGetDouble(POSITION_TP);
            orphanTrade.originalTP = orphanTrade.takeProfit;
            orphanTrade.lotSize = PositionGetDouble(POSITION_VOLUME);
            orphanTrade.isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            orphanTrade.status = "OPEN";
            orphanTrade.id = "ORPHAN_" + IntegerToString(ticket);
            orphanTrade.type = orphanTrade.isLong ? "L-ORPHAN" : "S-ORPHAN";
            orphanTrade.entryType = ENTRY_L_E1;  // Default
            orphanTrade.entryBar = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
            orphanTrade.bestPrice = orphanTrade.entryPrice;
            
            int newSize = ArraySize(trades) + 1;
            ArrayResize(trades, newSize);
            ArrayResize(tradeExtras, newSize);
            trades[newSize - 1] = orphanTrade;
            tradeExtras[newSize - 1].entryTime = (datetime)PositionGetInteger(POSITION_TIME);
            recoveredCount++;
            
            Print("[STATE] Recovered orphan position #", ticket, " | ", orphanTrade.type,
                  " | Entry: ", DoubleToString(orphanTrade.entryPrice, _Digits),
                  " | Lots: ", DoubleToString(orphanTrade.lotSize, 2));
        }
    }
    
    if (removedCount > 0 || recoveredCount > 0) {
        Print("[STATE] Broker sync complete: ", removedCount, " stale removed, ", recoveredCount, " orphans recovered");
    }
}

void TrackE4ForAdaptive(bool isWin) {
    if (!adaptiveParams.isActive) return;
    
    adaptiveParams.E3_tradeCount++;
    if (isWin) adaptiveParams.E3_winCount++;
    
    // Calculate rolling winrate
    adaptiveParams.E3_winrate = (double)adaptiveParams.E3_winCount / (double)adaptiveParams.E3_tradeCount;
    
    // Adjust every 14 E3 trades
    if (adaptiveParams.E3_tradeCount >= 14) {
        AdaptE3Parameters();
        adaptiveParams.E3_tradeCount = 0;
        adaptiveParams.E3_winCount = 0;
    }
}

void AdaptE3Parameters() {
    double targetWinrate = 0.65;  // 65% target
    double tolerance = 0.03;      // 3% tolerance
    
    if (adaptiveParams.E3_winrate < (targetWinrate - tolerance)) {
        // Performance dropping - tighten
        adaptiveParams.adaptive_ADX_LOW_THRESHOLD = MathMin(20.0, adaptiveParams.adaptive_ADX_LOW_THRESHOLD + 0.5);
        
        Print("[ADAPTIVE] E3 winrate low (", DoubleToString(adaptiveParams.E3_winrate * 100, 1), 
              "%) - Tightening: ADX=", adaptiveParams.adaptive_ADX_LOW_THRESHOLD);
              
    } else if (adaptiveParams.E3_winrate > (targetWinrate + tolerance)) {
        // Performance good - can loosen slightly
        adaptiveParams.adaptive_ADX_LOW_THRESHOLD = MathMax(14.0, adaptiveParams.adaptive_ADX_LOW_THRESHOLD - 0.5);
        
        Print("[ADAPTIVE] E3 winrate high (", DoubleToString(adaptiveParams.E3_winrate * 100, 1), 
              "%) - Loosening: ADX=", adaptiveParams.adaptive_ADX_LOW_THRESHOLD);
    }
    
    adaptiveParams.lastAdjustment = TimeCurrent();
    SaveStateToFile();  // Persist changes
}

void SaveStateToFile() {
    if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
        return;
    }
    
    string filename = GetStateFilePath();
    int handle = FileOpen(filename, FILE_WRITE|FILE_TXT);
    
    if(handle == INVALID_HANDLE) {
        Print("[STATE] Failed to save state file: ", filename, " Error: ", GetLastError());
        return;
    }
    
    string content = SerializeState();
    FileWriteString(handle, content);
    FileClose(handle);
    
    if(showDebug) {
        Print("[STATE] State saved to ", filename);
    }
}

// Write entry-detection statistics to a dedicated separate log file (once per day)
// This is 100% safe and does not touch the state file
void AppendEntryStatsToStateFile(string summaryLine) {
    if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
        return;
    }
    
    // Use dedicated entry stats log file - completely separate from state file
    string filename = "KenKem_EntryStats_" + _Symbol + "_" + IntegerToString(MAGIC_BASE) + ".log";
    
    // Open in append mode
    int handle = FileOpen(filename, FILE_READ|FILE_WRITE|FILE_TXT);
    if(handle == INVALID_HANDLE) {
        // Create new file if doesn't exist
        handle = FileOpen(filename, FILE_WRITE|FILE_TXT);
        if(handle == INVALID_HANDLE) {
            Print("[ENTRY_STATS] Failed to open log file: ", filename, " Error: ", GetLastError());
            return;
        }
    } else {
        // Append to end
        FileSeek(handle, 0, SEEK_END);
    }
    
    string line = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + " | " + summaryLine + "\n";
    FileWriteString(handle, line);
    FileClose(handle);
    
    if(showDebug) {
        Print("[ENTRY_STATS] Logged to: ", filename);
    }
}

bool LoadStateFromFile() {
    if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
        if(showDebug) Print("[STATE] Skipping state load in backtest/optimization mode");
        return false;
    }
    
    string filename = GetStateFilePath();
    
    if(!FileIsExist(filename)) {
        if(showDebug) Print("[STATE] No state file found - using defaults (first run)");
        return false;
    }
    
    int handle = FileOpen(filename, FILE_READ|FILE_TXT);
    if(handle == INVALID_HANDLE) {
        Print("[STATE] Failed to open state file: ", filename, " Error: ", GetLastError());
        return false;
    }
    
    string content = "";
    while(!FileIsEnding(handle)) {
        content += FileReadString(handle) + "\n";
    }
    FileClose(handle);
    
    bool success = DeserializeState(content);
    
    if(success) {
        // Validate loaded peak balance is reasonable
        double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        
        if(peakAccountBalance > currentBalance * 1.1) {
            Print("[STATE] WARNING: Loaded peak balance ($", DoubleToString(peakAccountBalance, 2), 
                  ") exceeds current balance ($", DoubleToString(currentBalance, 2), ") by >10%");
            Print("[STATE] Resetting peak balance to current balance");
            peakAccountBalance = currentBalance;
        }
        
        Print("[STATE] State restored from ", filename);
        Print("[STATE]   Daily Start Balance: $", DoubleToString(dailyStartBalance, 2), " | Peak Balance: $", DoubleToString(peakAccountBalance, 2));
        Print("[STATE]   Consecutive Losses: ", consecutiveLosses, " (LE1:", consecutiveLosses_LE1, " LE2:", consecutiveLosses_LE2, " LE3:", consecutiveLosses_LE3, " LE4:", consecutiveLosses_LE4, " SE1:", consecutiveLosses_SE1, " SE2:", consecutiveLosses_SE2, " SE3:", consecutiveLosses_SE3, " SE4:", consecutiveLosses_SE4, ")");
        Print("[STATE]   Session: ", currentSession, " | W:", sessionWinCount, " L:", sessionLossCount, " BE:", sessionBreakEvenCount, " | Total:", tradeSLTPCountInSession, " | High-Risk:", highRiskTradesInSession);
        Print("[STATE]   Drawdown: ", drawdownTriggered ? "BLOCKED" : "OK", " | Recovery Mode: ", inRecoveryMode ? "ON" : "OFF", " | Soft Block: ", inSoftBlockMode ? "ON" : "OFF", " | Daily Loss Limit: ", dailyLossLimitReached ? "REACHED" : "OK");
        Print("[STATE]   High-Risk Trades in Session: ", highRiskTradesInSession);
        if(drawdownTriggered) {
            Print("[STATE]   Drawdown blocked until: ", TimeToString(drawdownBlockedUntil, TIME_DATE|TIME_MINUTES));
        }
        if(inRecoveryMode) {
            double recoveryTrigger = ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN * RECOVERY_MODE_TRIGGER_RATIO;
            double recoveryExit = recoveryTrigger * RECOVERY_MODE_EXIT_RATIO;
            Print("[STATE]   RECOVERY MODE: Lot ", DoubleToString(RECOVERY_MODE_LOT_MULTIPLIER * 100, 0), 
                  "% (boost ", DoubleToString(RECOVERY_MODE_BOOST_MULTIPLIER * 100, 0), "%) | Exit when DD < ", 
                  DoubleToString(recoveryExit * 100, 1), "%");
        }
        if(inProfitProtectionMode) {
            Print("[STATE]   PROFIT PROTECTION: Lot ", DoubleToString(PROFIT_PROTECTION_LOT_MULTIPLIER * 100, 0), 
                  "% | Floor: $", DoubleToString(profitFloor, 2));
        }
    } else {
        Print("[STATE] Failed to restore state - using defaults");
    }
    
    return success;
}

#endif // GLOBALSTATE_MQH
