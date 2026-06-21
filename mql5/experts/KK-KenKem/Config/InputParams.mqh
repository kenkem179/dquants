#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// ALL USER INPUT PARAMETERS
// Extracted from main EA for better organization
//================================================================

// Performance settings
// input bool showEntryLabels = true;     // When entry labels won't be displayed
// input bool calcWinrates = true;        // Calculate Winrates

// Configurable inputs
input group "===== GENERAL ACCOUNT AND SYMBOL SETUP ====="
double INITIAL_ACCOUNT_BALANCE = 3500.0;  // Auto-detected from account; fallback if detection fails
int LEVERAGE = 500;
input double MY_STANDARD_LOT_SIZE = 0.15;      // My Standard Lot Size

enum HIGH_RISK_MOMENTUM_LEVEL {
    NONE = -1,         // No additional strict momentum needed
    M1_ONLY = 0,        // M1 momentum only (lenient)
    M3_ONLY = 1,        // M3 momentum only (lenient)
    M1_OR_M3 = 2,       // M1 OR M3 momentum (moderate)
    M1_AND_M3 = 3,      // M1 AND M3 momentum (strict) - RECOMMENDED
    M1_AND_M5 = 4,      // M1 AND M5 momentum (moderate-strict)
    M5_ONLY = 5,         // M5 momentum only
    M3_AND_M5 = 6,      // M3 AND M5 momentum (strict)
    M5_AND_M15 = 7,     // M5 AND M15 momentum (very strict, higher timeframes)
    E1_ACCEL_M1 = 8,   // E1 early trend acceleration on M1 (rising ADX + widening DI)
    E1_ACCEL_M3 = 9,   // E1 early trend acceleration on M3 (rising ADX + widening DI)
    E1_ACCEL_M1_OR_M3 = 10,  // E1 early trend on M1 OR M3
    E1_ACCEL_M1_AND_M3 = 11,  // E1 early trend on M1 and M3
    E1_ACCEL_M3_OR_M5 = 12  // E1 early trend on M3 or M5
};

enum HTF_TREND_MODE {
    HTF_DISABLED = 0,   // Disabled - no HTF trend filter
    HTF_M5_ONLY = 1,    // M5 only
    HTF_M5_AND_M15 = 2, // M5 AND M15 (both must agree)
    HTF_M15_ONLY = 3,   // M15 only
    HTF_M5_OR_M15 = 4   // M5 OR M15 (either one blocks)
};

input int MAX_HIGH_RISK_TRADES_PER_SESSION = 5;
input int MAX_SLTP_COUNT_PER_SESSION = 7;
input int MAX_SESSION_LOSSES = 4;              // Hard stop: block new entries after N real losses per session
bool AUTO_DETECT_SYMBOL_PARAMS = true;  // Auto-detect pip size and contract size from symbol info
double PIP_SIZE = 0.01;                       // Fallback pip size if auto-detect disabled
double CONTRACT_SIZE = 100;                   // Fallback contract size if auto-detect disabled

input group "===== QUICK STRATEGY CUSTOMIZATION ====="
input double MAX_DAILY_LOSS_RATIO = 0.072;
input double ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN = 0.105;
input double ACCOUNT_DD_RATIO_TO_SOFT_BLOCK = 0.13;  // "Soft" block at x% DD (continue with micro lots)
input double SOFT_BLOCK_LOT_MULTIPLIER = 0.3;        // Lot multiplier in soft block mode
input bool ENABLE_E1_ENTRIES = true;  // Enable E1 trend discovery strategy
input bool ENABLE_E2_ENTRIES = true;  // Enable E2 pull back strategy
input bool ENABLE_E3_ENTRIES = false;  // Enable E3 trend reversal strategy
input bool ENABLE_E4_ENTRIES = true;  // Enable E4 smart early trend strategy
input bool ENABLE_E5_ENTRIES = false;  // Enable E5 SuperBros EMA alignment strategy

input double COMMON_MAX_RISK_PER_TRADE = 0.02;
// TODO: Enable per entry max loss ratio later
// double MAX_LOSS_RATIO_E2 = COMMON_MAX_RISK_PER_TRADE;
double MAX_LOSS_RATIO_E1 = COMMON_MAX_RISK_PER_TRADE * 1.05;
double MAX_LOSS_RATIO_E2 = COMMON_MAX_RISK_PER_TRADE * 1;
double MAX_LOSS_RATIO_E3 = COMMON_MAX_RISK_PER_TRADE * 0.97;
double MAX_LOSS_RATIO_E4 = COMMON_MAX_RISK_PER_TRADE * 1.02;
double MAX_LOSS_RATIO_E5 = COMMON_MAX_RISK_PER_TRADE * 1.0;

// Per-entry volatility lot adjustment (ATR-based)
// E1/E2 trend-following: high vol = stronger trends, may want full lots
// E3 counter-trend: high vol = riskier reversals, reducing lots protects
input bool INCREASE_LOT_SIZE_BASED_ON_PROFIT = true;
input bool VOL_LOT_ADJ_E1 = false;             // E1: Scale lots by volatility (default:FALSE)
input bool VOL_LOT_ADJ_E2 = false;             // E2: Scale lots by volatility (default:FALSE)
input bool VOL_LOT_ADJ_E3 = false;              // E3: Scale lots by volatility (default:TRUE)
input bool VOL_LOT_ADJ_E4 = false;             // E4: Scale lots by volatility (default:FALSE)
input bool VOL_LOT_ADJ_E5 = false;             // E5: Scale lots by volatility (default:FALSE)

input group "===== GENERAL RISK MANAGEMENT ====="
double MAX_AGGREGATE_RISK_RATIO = MAX_LOSS_RATIO_E1 * 4;
input double RECOVERY_MODE_TRIGGER_RATIO = 0.9;
input double RECOVERY_MODE_EXIT_RATIO = 0.95;
input double RECOVERY_MODE_LOT_MULTIPLIER = 0.6;
input double RECOVERY_MODE_BOOST_MULTIPLIER = 0.65;
input bool SIGNAL_ONLY_DURING_PROTECTION = true;  // Send signals but block trades in DD/Recovery/SoftBlock modes
input double VOL_LOT_MIN_MULT = 0.4;           // Min lot multiplier for adjustment (high volatility)
input double VOL_LOT_MAX_MULT = 1.2;           // Max lot multiplier for adjustment (low volatility)
bool E1_USE_RECOVERY_LADDER = false;          // E1: Use gradual recovery (OFF for trend-following)
bool E2_USE_RECOVERY_LADDER = false;          // E2: Use gradual recovery (OFF)
bool E3_USE_RECOVERY_LADDER = true;           // E3: Use gradual recovery (ON for counter-trend)
bool E4_USE_RECOVERY_LADDER = false;          // E4: Use gradual recovery (OFF - same as E1)
bool E5_USE_RECOVERY_LADDER = false;          // E5: Use gradual recovery (OFF)
double RECOVERY_LADDER_STEP = 0.10;           // Step size for lot adjustment (10%)
double RECOVERY_LADDER_MIN_MULT = 0.30;       // Minimum recovery lot multiplier (40%)
double RECOVERY_LADDER_MAX_MULT = 1.00;       // Maximum recovery lot multiplier (100%)

input group "===== PEAK BALANCE DECAY (Recovery Escape) ====="
input bool   ENABLE_PEAK_BALANCE_DECAY     = true;   // Gradually ease peak during recovery
input int    PEAK_DECAY_GRACE_HOURS        = 40;     // Hours before decay starts (3 days grace)
input int    PEAK_DECAY_INTERVAL_HOURS     = 20;     // How often to apply decay (daily)
input double PEAK_DECAY_RATE               = 0.10;   // Fraction of gap to close per interval (10%)
input double PEAK_DECAY_MAX_TOTAL          = 0.50;

input group "===== CONVICTION SCORING (0-12 scale) ====="
bool USE_CONVICTION_SCORING_E1 = true;  // E1: DISABLED - Conviction scoring filters GOOD early entries (ADX not yet high)
input int CONVICTION_THRESHOLD_E1 = 7;          // E1: Min score 6/12 (NOT USED when disabled)
bool USE_CONVICTION_SCORING_E2 = true;  // E2: DISABLED - Test E1 first, then enable
input int CONVICTION_THRESHOLD_E2 = 10;          // E2: Min score 5/12 (50%=balanced, 6=conservative)
// Excluded from input params
bool USE_CONVICTION_SCORING_E3 = false;  // E3: DISABLED - Counter-trend needs separate validation
int CONVICTION_THRESHOLD_E3 = 6;          // E3: Min score 6/12 (50%=balanced, 7=58%, 8=67%)
bool USE_HTF_VETO_E1 = false;             // E1: HTF veto (blocks if against M3/M5 trend, integrated in conviction)
bool USE_HTF_VETO_E2 = false;             // E2: HTF veto (blocks if against M3/M5 trend)
bool USE_HTF_VETO_E3 = false;             // E3: HTF veto (not needed for reversal entries)
bool USE_CONVICTION_SCORING_E4 = true;   // E4: Conviction scoring (same as E1 - early trend)
input int CONVICTION_THRESHOLD_E4 = 9;          // E4: Min score 8/12 (stricter than E1 - early entry needs higher quality)
bool USE_HTF_VETO_E4 = false;             // E4: HTF veto (same as E1)

input group "===== TREND QUALITY SCORING (0-11 scale, +1 for ATR) ====="
input bool ENABLE_TREND_QUALITY_GATES = true;  // Gate: require ADX>=1, DI>=1, MTF>=1 before scoring (blocks weak-trend inflation)
input int MIN_TREND_QUALITY_E1 = 6;  // E1: Min score 7/11 (64%=strict, +1 for ATR component)
bool USE_ICHIMOKU_E1 = true;  // E1: Add Ichimoku Cloud alignment bonus (0-2 points)
input int MIN_TREND_QUALITY_E2 = 9;  // E2: Min score 9/11 (82%=strict, +1 for ATR component)
bool USE_ICHIMOKU_E2 = false;  // E2: Add Ichimoku Cloud alignment bonus (0-2 points)
input int MIN_TREND_QUALITY_E4 = 9;  // E4: Min trend quality (v1.7.993: was 7, now HARD BLOCK)
bool USE_ICHIMOKU_E4 = false;        // E4: NO Ichimoku bonus - Pine uses E1's score which excludes Ichimoku (Ichi is the TRIGGER, not quality)
input int MIN_TREND_QUALITY_E5 = 5;  // E5: Min trend quality (Pine v1-stable default 5/11; 0=disabled). NO Ichimoku — score range 0-11.
// E3 uses exhaustion scoring instead of trend quality
input bool USE_ACCELERATION_BONUS = true;  // Add bonus points for trend acceleration
int ICHIMOKU_TENKAN = 9;        // Ichimoku Tenkan-sen period
int ICHIMOKU_KIJUN = 26;        // Ichimoku Kijun-sen period  
int ICHIMOKU_SENKOU = 52;       // Ichimoku Senkou Span B period


input group "===== SIDEWAYS DETECTION FOR ENTRY BLOCKING ====="
input double MAX_SPREAD_PIPS = 0.0;          // Block entries when spread exceeds this (0 = disabled)
input int SPREAD_BLOCK_CONSECUTIVE_BARS = 3;  // Require N consecutive high-spread bars before blocking (avoids single-tick spikes)
input double MAX_SPREAD_ATR_RATIO = 0.30;     // Block if spread > ATR * this ratio (0 = disabled). E.g., 0.30 = 30% of ATR
input double ATR_SIDEWAYS_PERCENTILE = 30.0;     // ATR percentile below this = sideways market (0=disabled)
input int SIDEWAYS_BLOCK_THRESHOLD = 53;         
input int SIDEWAYS_WARNING_THRESHOLD = 43;
input bool ENABLE_SIDEWAY_EARLY_EXIT = false;
input int SIDEWAY_EXIT_CONSECUTIVE_BARS = 4;     
input double EMA_SPREAD_TIGHT_ATR = 1.75;         
input double EMA_SPREAD_MODERATE_ATR = 3.25;      
input double EMA_SPREAD_WIDE_ATR = 4.0; 
input double ATR_PERCENTILE_LOW = 20.0;
input double ATR_PERCENTILE_HIGH = 90.0;        // Block entries when ATR > this percentile (0 = disabled)
input bool ENABLE_ATR_HIGH_BLOCK = true;         // Toggle ATR-too-high entry blocking (false = allow entries in volatile markets)
input double MIN_ENTRY_ATR_PERCENTILE = 65.0;    // Min ATR percentile for all entries (0=disabled, 55=active regime filter)
input int ATR_PERCENTILE_LOOKBACK = 32;
input bool ENABLE_BLACK_SWAN_PROTECTION = true;  // Enable Black Swan volatility spike protection
input int BLACKSWAN_BLOCK_COOLDOWN_MINS = 10;

input group "===== LOT SCALING FINE-TUNING ====="
input double PROFIT_SCALING_WEIGHT_CURRENT = 0.65;  // Weight for current balance in profit scaling (0.65 = 65%)
input double PROFIT_SCALING_WEIGHT_INITIAL = 0.35;  // Weight for initial balance in profit scaling (0.35 = 35%)
input double MIN_RISK_FLOOR_RATIO = 0.005;          // Minimum risk floor (0.5% of account) to allow any trade

input group "===== PROFIT PROTECTION (High Water Mark) ====="
input bool ENABLE_PROFIT_PROTECTION = true;
input double PROFIT_PROTECTION_TRIGGER_RATIO = 0.3;
input double PROFIT_PROTECTION_LOT_MULTIPLIER = 0.75;
input double MIN_PROFIT_TO_PROTECT_RATIO = 0.05;

input group "===== WINNING STREAK COOLDOWN ====="
input bool ENABLE_WIN_STREAK_COOLDOWN = true;
input int WIN_STREAK_COOLDOWN_TRIGGER = 3;
input double WIN_STREAK_COOLDOWN_LOT_MULT = 0.60;
input int WIN_STREAK_COOLDOWN_TRADES = 2;

input int MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE = 3;
input int ENTRY_BLOCK_AFTER_CONSECUTIVE_LOSS_MINS = 60;
input int LOSING_STREAK_ESCALATION_THRESHOLD = 2;
input int MAX_CONCURRENT_POSITIONS_ALLOWED = 2;
input bool BLOCK_OPPOSITE_DIRECTION_ENTRIES = true;  // CRITICAL: Block entries opposing active positions (prevents hedge losses)
input bool CLOSE_ALL_TRADES_AT_SESSION_END = true;

input group "===== ENTRY SETUP AND EXECUTION ====="
input int ENTRY_SHIFT = 1; // Bar shift for entry detection (0=current bar, 1=previous bar)
bool USE_LIVE_PRICE_FOR_ENTRY_NOT_CLOSED_PRICE = false; // Use current live price for entry

input group "===== STOP LOSS CONFIGURATION ====="
// Structure-based SL (E1/E2 default)
input int SL_EMA_DISTANCE = 27;                  // SL distance from EMA 100/200 (in pips)
input double MIN_SL_SPREAD_MULT = 0.5;

// E1/E2: ATR Arbitration - clamps structure SL within ATR bounds (smart hybrid)
input bool E1_USE_ATR_SL_ARBITRATION = true;     // E1: Enable ATR vs Structure SL arbitration
input double E1_ATR_SL_CAP_MULTIPLIER = 4.0;     // E1: Max SL = ATR * this (caps wide SL)
input double E1_ATR_SL_FLOOR_MULTIPLIER = 1.2;   // E1: Min SL = ATR * this (floors tight SL)
input bool E2_USE_ATR_SL_ARBITRATION = true;     // E2: Enable ATR vs Structure SL arbitration
input double E2_ATR_SL_CAP_MULTIPLIER = 3.0;     // E2: Max SL = ATR * this (caps wide SL)
input double E2_ATR_SL_FLOOR_MULTIPLIER = 1.1;   // E2: Min SL = ATR * this (floors tight SL)

// E3: Pure ATR-based SL (counter-trend needs volatility-adaptive SL)
input bool E3_USE_ATR_SL = true;                 // E3: Use pure ATR-based SL
input double E3_ATR_MULTIPLIER_SL = 3.0;         // E3: SL = ATR * this (1.0-1.5 for reversals)

input bool E4_USE_ATR_SL_ARBITRATION = true;     // E4: Use ATR SL arbitration (like E1)
input double E4_ATR_SL_CAP_MULTIPLIER = 4.0;      // E4: ATR SL cap multiplier
input double E4_ATR_SL_FLOOR_MULTIPLIER = 1.25;    // E4: ATR SL floor multiplier

input bool E5_USE_ATR_SL_ARBITRATION = false;    // E5: ATR SL arbitration (OFF by default - Pine uses EMA200)
input double E5_ATR_SL_CAP_MULTIPLIER = 4.0;      // E5: ATR SL cap multiplier
input double E5_ATR_SL_FLOOR_MULTIPLIER = 1.2;    // E5: ATR SL floor multiplier

input int ATR_PERIOD_FOR_SL = 14;                // ATR calculation period
input int ATR_LOOKBACK_FOR_ADAPTIVE = 120;       // Long-term ATR lookback (vol adjustment)
input int TRADE_SLTP_MAX_RETRIES = 12;            // Max retries for SL/TP modification after order
input int TRADE_SLTP_RETRY_DELAY_MS = 80;         // Delay between retries (milliseconds)
input int RANGE_HI_LOW_LOOK_BACK_BARS = 18;    // Range Hi/Lo lookback window (bars)
input int MIN_SECONDS_BETWEEN_ENTRIES = 60; // Minimum seconds between any entries
input int HIGH_RISK_MAX_BARS = 70;  // Max bars to hold high-risk trades (30-50 recommended)

input group "===== MOMENTUM FILTERING ====="
//input bool ENABLE_MOMENTUM_FILTER = true;   // Enable momentum-based entry filtering
input double MIN_MOMENTUM_ADX_REQUIRED = 19.7;        // Minimum ADX for momentum confirmation (v1.7.66: 19.0)
input double ADX_LOW_THRESHOLD = 14.5;             // ADX < this => weak or no trend (v1.7.66: 13.5)
input double ADX_HIGH_THRESHOLD  = 25.0;               // ADX > this => very strong trend
input bool REQUIRE_ADX_CONFLUENCE = true;    // ADX confluence required (v1.7.66: true)
input double EMA_ALIGNMENT_TOLERANCE_PIPS = 23.0;  // Allow EMA misalignment within X pips (0=strict, 25=lenient)

input group "===== RSI DIVERGENCE VETO (E1/E2/E4) ====="
input bool ENABLE_RSI_DIVERGENCE_VETO = true;        // Block entries when RSI diverges against trade direction on M3
input int RSI_DIV_LOOKBACK = 16;                       // M3 bars to scan for divergence (10 = ~30 min window)
input double RSI_DIV_MIN_PRICE_DIFF_PIPS = 60;       // Min price difference between swing points (pips, filters noise)
input double RSI_DIV_MIN_RSI_DIFF = 6.5;               // Min RSI difference for valid divergence (points, filters noise)

input group "===== EXTREME MOMENTUM BYPASS ====="
input double EXTREME_DI_SPREAD_THRESHOLD = 16.0;  // DI spread >= this triggers extreme momentum bypass
input double EXTREME_RSI_THRESHOLD_HIGH = 70.5;   // RSI >= this for long signals extreme momentum
input double EXTREME_RSI_THRESHOLD_LOW = 29.5;    // RSI <= this for short signals extreme momentum

input group "===== DYNAMIC TP/SL SETUP ====="
input bool ENABLE_PRE_BE_STRUCTURE_PROTECTION = true; // Tighten SL before BE on structure break in trade direction
input double PRE_BE_TRIGGER_R = 0.5;                 // Min profit in R before pre-BE structure SL tightening is allowed
input int PRE_BE_BOS_LOOKBACK_BARS = 6;               // Lookback bars (excluding breakout bar) to define prior structure
input double PRE_BE_BOS_BREACH_BUFFER_PIPS = 1.0;     // Minimum breach distance beyond prior structure (pips)
input int PRE_BE_SWING_BUFFER_PIPS = 8;               // SL buffer from breakout candle extreme (pips)
input int PRE_BE_MIN_SL_IMPROVEMENT_PIPS = 2;         // Minimum SL improvement per update (pips)
input bool PRE_BE_REQUIRE_M3_ACCEL_CONFIRM = true;    // Require M3 acceleration confirmation to reduce M1 fake breaks
input double R_MULT_BE_TRIGGER = 0.87;               // Move SL to BE when profit reaches this × risk (1.0=1R, 0.8=0.8R, 0=disabled)
input double R_MULT_BE_BUFFER = 0.055;               // Buffer above entry when moving to BE (2% of risk distance)
input bool ALLOW_PARTIAL_TP = true;
input bool ALLOW_TP_EXTENSION = true;
input double MIN_TP_PROGRESS_FOR_EXTENSION = 0.92;
input double PARTIAL_TP_RETRACE_RATIO = 0.15;
input bool USE_DYNAMIC_TP_EXTENSION = true; 
input bool USE_DYNAMIC_RR_SCALING = true;
input double ATR_TP_EXTENSION_MULTIPLIER = 0.035;
input double TP_EXTENSION_MIN_PIPS = 7.0;
input double TP_EXTENSION_MAX_PIPS = 60.0;
input bool ENABLE_EARLY_CUT_NEAR_SL = false;
input bool ENABLE_FAST_ADX_PANIC_EXIT_E1 = true;
input bool ENABLE_FAST_ADX_PANIC_EXIT_E2 = true;
input bool ENABLE_FAST_ADX_PANIC_EXIT_E3 = true;
input bool ENABLE_FAST_ADX_PANIC_EXIT_E4 = true;
input bool ENABLE_FAST_ADX_PANIC_EXIT_E5 = true;   // E5: Exit when ADX collapses (prevents holding dying trades)

input bool ENABLE_SCORE_DROP_EXIT_E1 = false;
input int SCORE_DROP_THRESHOLD_E1 = 3;
input bool ENABLE_SCORE_DROP_EXIT_E2 = true;
input int SCORE_DROP_THRESHOLD_E2 = 2;
input bool ENABLE_SCORE_DROP_EXIT_E3 = true;
input int SCORE_DROP_THRESHOLD_E3 = 3;
input bool ENABLE_SCORE_DROP_EXIT_E4 = true;    // E4: Exit on momentum score drop (0-6 scale, includes Ichimoku cloud position)
input int SCORE_DROP_THRESHOLD_E4 = 3;           // E4: Momentum drop threshold (2 = moderate sensitivity)
input bool ENABLE_SCORE_DROP_EXIT_E5 = false;    // E5: Score drop exit (OFF - no momentum tracking)
input int SCORE_DROP_THRESHOLD_E5 = 3;           // E5: Score drop threshold
input int SCORE_DROP_CONSECUTIVE_CHECKS = 3;
input bool ENABLE_ADX_DROP_BASED_EXIT = false; 
input int ADX_DROP_EXIT_BARS = 3;             
input double PANIC_MIN_SL_USED_RATIO = 0.6;
input double PANIC_MIN_SL_USED_RATIO_E3 = 0.45;
input double PANIC_MIN_PROFIT_GIVEBACK = 0.5;

input bool ENABLE_DI_FLIP_FAST_EXIT_E1 = false;
input bool ENABLE_DI_FLIP_FAST_EXIT_E2 = false;
input bool ENABLE_DI_FLIP_FAST_EXIT_E3 = false;
input bool ENABLE_DI_FLIP_FAST_EXIT_E4 = false;
input bool ENABLE_DI_FLIP_FAST_EXIT_E5 = false;
input double DI_FLIP_MIN_SPREAD_M1 = 4.0;     // Min opposing DI spread on M1 to confirm flip
input double DI_FLIP_MIN_ADX_M1 = 18.0;       // Min ADX at flip time (below = noise, no energy)
input int DI_FLIP_CONSECUTIVE_M1_BARS = 2;    // Consecutive M1 bars required to confirm flip
input double DI_FLIP_MIN_SL_USED_RATIO = 0.4; // Min fraction of SL consumed before exit fires

input group "===== E1 TRADE MANAGEMENT (Trend Continuation - Let Winners Run) ====="
input bool BLOCK_E1_WHEN_E4_ACTIVE = false;      // E1: Block E1 detection when E4 trade is active
input HTF_TREND_MODE E1_HTF_TREND_FILTER = HTF_M5_ONLY;
input double E1_HTF_MIN_ADX = 18.5;
input double E1_HTF_MIN_DI_SPREAD = 4.0;
input bool ACCEPT_HIGH_RISK_E1_ENTRIES = true;  // Enable high-risk E1 entries with strict momentum filters
input HIGH_RISK_MOMENTUM_LEVEL HIGH_RISK_E1_MOMENTUM_CHECK = M1_AND_M3;  // E1 momentum strictness for high-risk entries (RECOMMENDED: E1_ACCEL_M1_OR_M3)
input double E1_HIGH_RISK_MIN_ADX = 19.5;        // E1: Min ADX for high-risk (early trend, slightly lower OK)
input double E1_HIGH_RISK_MIN_DI_SPREAD = 4.0;   // E1: Min DI spread for high-risk (early trend)
input double HIGH_RISK_TP_MULTIPLIER_ASIA = 0.65;  // High-risk TP % for ASIA session (conservative - low volatility)
input double HIGH_RISK_TP_MULTIPLIER_EU = 0.65;    // High-risk TP % for EU session (baseline - moderate volatility)
input double HIGH_RISK_TP_MULTIPLIER_US = 0.7;    // High-risk TP % for US session (aggressive - high volatility)
input double E1_MIN_MOMENTUM_ADX = 19.5;
input int E1_MAX_CROSS_AGE = 28;                  // E1: Max bars since EMA cross (stale trigger expiry); capped 80->28 to cut late-fire over-trading
input int E1_MOMENTUM_BYPASS_LEVEL = 1;
input double E1_RR = 1.9;                      // Entry 1's Reward (KEM)
input double E1_RR_SIDEWAY = 1.2;              // Entry 1's Reward 2 (CHE in KEM)
input double E1_PARTIAL_TP_TRIGGER = 0.90;      // E1: Take partial at 90% (let trends run longer)
input double E1_PARTIAL_TP_RATIO = 0.20;        // E1: Take only 20% partial (keep 80% riding)
input double E1_SL_TO_BREAKEVEN_BUFFER = 0.07;  // E1: BE buffer (7% - tight protection after partial)
input double E1_TRAILING_SL_FACTOR = 0.40;      // E1: Trailing 40% = generous room for trend continuation
input int E1_MAX_TP_EXTENSIONS = 40;            // E1: More extensions (40x - trends can run far)
input double E1_EARLY_CUT_SL_RATIO = 0.89;      // E1: Early cut at 89% to SL
input bool E1_ENABLE_LADDERED_EXTENSIONS = true;    // E1: Enable Phase 2 laddered TP extensions after partial TP
input double E1_LADDER_STAGE1_MULTIPLIER = 1.05;    // E1: Stage 1 profit target
input double E1_LADDER_STAGE2_MULTIPLIER = 1.11;    // E1: Stage 2 profit target
input double E1_LADDER_STAGE3_MULTIPLIER = 1.17;    // E1: Stage 3 profit target
input double E1_LADDER_STAGE1_TRAIL_RATIO = 0.45;   // E1: Stage 1 trailing SL ratio (45% - wider for runners)
input double E1_LADDER_STAGE2_TRAIL_RATIO = 0.55;   // E1: Stage 2 trailing SL ratio (55%)
input double E1_LADDER_STAGE3_TRAIL_RATIO = 0.65;   // E1: Stage 3 trailing SL ratio (65% - max room)

input group "===== E2 TRADE MANAGEMENT (Secondary Continuation - Balanced) ====="
input bool ACCEPT_HIGH_RISK_E2_ENTRIES = true;  // Enable high-risk E2 entries (more selective than E1)
input HIGH_RISK_MOMENTUM_LEVEL HIGH_RISK_E2_MOMENTUM_CHECK = M1_AND_M3;  // E2 momentum strictness for high-risk entries
input double E2_HIGH_RISK_MIN_ADX = 21.5;        // E2: Min ADX for high-risk (pullback, need stronger)
input double E2_HIGH_RISK_MIN_DI_SPREAD = 5.0;   // E2: Min DI spread for high-risk (pullback)
input double E2_MIN_MOMENTUM_ADX = 20.0;        // E2: Min ADX for momentum (pullback, need stronger)
input int E2_MAX_TOUCH_AGE = 36;               // E2: Max bars since EMA75 touch to allow entry (expire stale triggers)
input HTF_TREND_MODE E2_HTF_TREND_FILTER = HTF_M15_ONLY;  // E2: HTF trend filter mode (matches E1/E4 pattern)
input double E2_HTF_MIN_ADX = 23.0;              // E2: Min HTF ADX for valid trend signal
input double E2_HTF_MIN_DI_SPREAD = 3.0;         // E2: Min HTF DI spread for valid trend signal
input double E2_RR = 1.575;                      // Entry 2's Reward
input double E2_RR_SIDEWAY = 1.1;              // Entry 2's Reward 2 (in sideway market)
input double E2_PARTIAL_TP_TRIGGER = 0.70;      // E2: Partial TP trigger (70% - balanced)
input double E2_PARTIAL_TP_RATIO = 0.25;        // E2: Take 20% partial (keep 80% riding)
input double E2_SL_TO_BREAKEVEN_BUFFER = 0.07;  // E2: BE buffer (7% - balanced)
input double E2_TRAILING_SL_FACTOR = 0.45;      // E2: Trailing SL (45% - moderate room for continuation)
input int E2_MAX_TP_EXTENSIONS = 30;            
input double E2_EARLY_CUT_SL_RATIO = 0.88;      // E2: Early cut at 88% to SL
input bool E2_ENABLE_LADDERED_EXTENSIONS = true;    // E2: Enable Phase 2 laddered TP extensions after partial TP
input double E2_LADDER_STAGE1_MULTIPLIER = 1.04;    // E2: Stage 1 profit target
input double E2_LADDER_STAGE2_MULTIPLIER = 1.09;    // E2: Stage 2 profit target
input double E2_LADDER_STAGE3_MULTIPLIER = 1.14;    // E2: Stage 3 profit target
input double E2_LADDER_STAGE1_TRAIL_RATIO = 0.40;   // E2: Stage 1 trailing SL ratio (40% - balanced)
input double E2_LADDER_STAGE2_TRAIL_RATIO = 0.50;   // E2: Stage 2 trailing SL ratio (50%)
input double E2_LADDER_STAGE3_TRAIL_RATIO = 0.60;   // E2: Stage 3 trailing SL ratio (60%)

input group "===== E3 TRADE MANAGEMENT ====="
input bool ACCEPT_HIGH_RISK_E3_ENTRIES = false;  // Enable high-risk E3 entries (more selective than E1)
input HIGH_RISK_MOMENTUM_LEVEL HIGH_RISK_E3_MOMENTUM_CHECK = M1_ONLY;  // E3: M1 ONLY for faster reversal detection (M3 is too slow)
input double E3_HIGH_RISK_MAX_ADX = 35.0;        // E3: Max ADX for high-risk (counter-trend, lower momentum preferred)
input double E3_HIGH_RISK_MIN_DI_SPREAD = 8.0;   // E3: Min DI spread for high-risk (easier entry for reversals)
input int E3_EXTREME_LOOKBACK_BARS = 10;             // Bars to scan for recent extreme (M3)
input int E3_EXTREME_MAX_DISTANCE = 4;         // Max distance (bars) of the extreme from current bar
input int E3_M3_OHLC_CACHE_BARS = 10;          // E3: M3 OHLC cache bars for wick/stretch checks (clamped to E3_M3_OHLC_CACHE_MIN/MAX)

input group "===== E3 EXHAUSTION DETECTION ====="
input bool E3_BLOCK_WHEN_TREND_ACTIVE = false;    // E3: Block when E1/E2/E4 trend following trades are active
input bool E3_REQUIRE_HTF_TREND_ALIGN = true;    // E3: Require HTF trend alignment (trade WITH flow, not against)
input int E3_HTF_ALIGN_MODE = 1;                 // E3: 0=M5 only, 1=M5 OR M15 (default), 2=M5 AND M15 (strictest)
input bool E3_BLOCK_STRONG_TREND = true;         // E3: Block entries when M15 ADX > threshold (strong trend = no reversal)
input double E3_STRONG_TREND_ADX = 30.0;         // E3: M15 ADX threshold for strong trend block
input bool E3_REQUIRE_H1_ALIGN = true;           // E3: Require H1 trend alignment (most stable anchor)
input double E3_LOT_MULTIPLIER = 0.65;           // E3: Permanent lot size multiplier (50% = half size for counter-trend risk)
input bool E3_USE_EXHAUSTION_SCORING = true;     // Enable multi-factor exhaustion scoring
input int E3_MIN_EXHAUSTION_SCORE = 6;           // Min exhaustion score (0-14, lowered from 8 for more opportunities)
input bool E3_USE_RSI_EXHAUSTION = true;         // RSI extreme + EMA cross + spread widening
input bool E3_USE_ADX_PEAK_DECLINE = true;       // ADX peaked high and now declining
input bool E3_USE_WICK_REJECTION = true;         // Wick rejection at extremes (price structure)

input double E3_MAX_MOMENTUM_ADX = 40.0;        // E3: Max ADX for momentum (counter-trend, lower momentum preferred)
input int E3_MOMENTUM_BYPASS_LEVEL = 1;       

input group "===== E3 REGIME GATE (STABILITY) ====="
input bool E3_ENABLE_REGIME_GATE = true;              // E3: Require fatigue + stretch context before timing triggers
input bool E3_REGIME_REQUIRE_FATIGUE = false;          // E3: Require trend fatigue (ADX rollover or DI compression)
input double E3_REGIME_MIN_ADX_FOR_FATIGUE = 18.0;    // E3: Minimum M3 ADX to consider fatigue signals
input double E3_REGIME_MIN_ADX_ROLLOVER = 21.0;       // E3: ADX must have been strong before rollover counts
input double E3_REGIME_MIN_DI_SPREAD = 3.5;           // E3: Minimum DI spread to qualify as a trend
input double E3_REGIME_MIN_DI_SPREAD_DELTA = 1.4;     // E3: Minimum DI spread compression required
input bool E3_REGIME_REQUIRE_STRETCH = true;         // E3: Require prior extension away from EMAs
input int E3_REGIME_STRETCH_LOOKBACK = 6;             // E3: M3 bars to scan for prior stretch before breakout
input double E3_REGIME_MIN_STRETCH_EMA25_ATR = 0.8;   // E3: Minimum stretch vs EMA25
input double E3_REGIME_MIN_STRETCH_EMA75_ATR = 1.2;   // E3: Minimum stretch vs EMA75

input group "===== E3 M1 ROTATION TRIGGER ====="
input bool E3_M1_REQUIRE_ROTATION = true;             // E3: Require DI rotation (not just DI dominance) on M1
input double E3_M1_MIN_DI_SPREAD = 0.4;               // E3: Minimum DI spread on M1 for rotation to count
input bool E3_M1_REQUIRE_ADX_UPTICK = true;          // E3: Require ADX uptick on M1
input double E3_M1_MIN_ADX_FOR_UPTICK = 15.5;         // E3: Minimum ADX on M1 for uptick check to apply
input bool E3_M1_USE_PRICE_CONFIRMATION = true;       // E3: Use price action (above/below EMA) as alternative M1 confirmation
input int E3_M1_PRICE_EMA_PERIOD = 8;                 // E3: EMA period for price confirmation (8 = fast)

input group "===== E3 RR BY EXHAUSTION SCORE ====="
input bool E3_SCORE_RR_ADJUST_ENABLED = true;         // E3: Adjust RR based on exhaustion score bucket
input int E3_SCORE_RR_REDUCE_BELOW = 9;               // E3: Reduce RR when score is near minimum gate
input int E3_SCORE_RR_BOOST_AT_OR_ABOVE = 12;         // E3: Boost RR slightly when exhaustion is very strong
input double E3_SCORE_RR_REDUCE_MULT = 0.90;          // E3: RR multiplier for low conviction exhaustion
input double E3_SCORE_RR_BOOST_MULT = 1.05;           // E3: RR multiplier for high conviction exhaustion
input double E3_RR = 2.3;                      // E3: RR for counter-trend     
input double E3_RR_SIDEWAY = 1.3;              // E3: Conservative in sideway      
input double E3_PARTIAL_TP_TRIGGER = 0.66;     // E3: Bank profit EARLY (66% - counter-trend needs fast exit)
input double E3_PARTIAL_TP_RATIO = 0.30;       // E3: Bank 30% position (secure wins against trend)        
input double E3_SL_TO_BREAKEVEN_BUFFER = 0.04; // E3: Move to BE after partial     
input double E3_TRAILING_SL_FACTOR = 0.40;     // E3: Tighter trail (40% - lock profits quickly)     
input int E3_MAX_TP_EXTENSIONS = 25;            // E3: More extensions    
input double E3_EARLY_CUT_SL_RATIO = 0.90;     // E3: Cut losers at 90% to SL
input int E3_SL_EMA_BUFFER = 40;               // E3: Fallback buffer from swing extreme (pips, if ATR unavailable)

input group "===== E3 LADDERED TP EXTENSIONS ====="
input bool E3_ENABLE_LADDERED_EXTENSIONS = true;    // E3: Enable Phase 2 laddered TP extensions after partial TP
input double E3_LADDER_STAGE1_MULTIPLIER = 1.05;    // E3: Stage 1 profit target
input double E3_LADDER_STAGE2_MULTIPLIER = 1.11;    // E3: Stage 2 profit target
input double E3_LADDER_STAGE3_MULTIPLIER = 1.18;    // E3: Stage 3 profit target
input double E3_LADDER_STAGE1_TRAIL_RATIO = 0.40;   // E3: Stage 1 trailing SL ratio (40%)
input double E3_LADDER_STAGE2_TRAIL_RATIO = 0.45;   // E3: Stage 2 trailing SL ratio (45%)
input double E3_LADDER_STAGE3_TRAIL_RATIO = 0.50;   // E3: Stage 3 trailing SL ratio (50%)          

input group "===== E4 TRADE MANAGEMENT (Ichimoku Cloud Cross - Early Trend) ====="
input bool BLOCK_E4_WHEN_E1_ACTIVE = false;
input bool E4_LONG_ONLY = false;                 // E4: only take LONG entries (MT5 isolation: E4 shorts net-loser, longs PF~1.40)
input int E4_MAX_SIDEWAY_SCORE = 40;
input bool E4_REQUIRE_M5_DI_ALIGN = true;
input HTF_TREND_MODE E4_HTF_TREND_FILTER = HTF_M5_OR_M15;
input double E4_HTF_MIN_ADX = 20.5;     
input double E4_HTF_MIN_DI_SPREAD = 6.0;
input bool ACCEPT_HIGH_RISK_E4_ENTRIES = true;
input HIGH_RISK_MOMENTUM_LEVEL HIGH_RISK_E4_MOMENTUM_CHECK = E1_ACCEL_M1_AND_M3;
input double E4_HIGH_RISK_MIN_ADX = 20.5;           
input double E4_HIGH_RISK_MIN_DI_SPREAD = 4.0;      
input double E4_MIN_MOMENTUM_ADX = 19.75;         

input group "===== E4 ICHIMOKU QUALITY FILTERS ====="
input double E4_MIN_CLOUD_THICKNESS_ATR_MULT = 0.11;     // Min current cloud thickness (ATR multiplier, 0=disabled)
input bool E4_REQUIRE_TENKAN_KIJUN_ALIGN = true;       // Require Tenkan > Kijun (LONG) / Tenkan < Kijun (SHORT)
input bool E4_REQUIRE_CHIKOU_CLEAR = false;             // Require Chikou span clear of price 26 bars ago

input int E4_MOMENTUM_BYPASS_LEVEL = 1;
input int E4_MAX_CROSS_AGE = 20;               
input double E4_RR = 2.4;                      
input double E4_RR_SHORT = 1.8;                  
input double E4_RR_SIDEWAY = 1.15;                 
input double E4_PARTIAL_TP_TRIGGER = 0.7;         
input double E4_PARTIAL_TP_RATIO = 0.2;          
input double E4_SL_TO_BREAKEVEN_BUFFER = 0.07;    
input double E4_TRAILING_SL_FACTOR = 0.5;         // E4: Disabled - no trailing SL
input int E4_MAX_TP_EXTENSIONS = 30;              // E4: Max TP extensions (same as E1)
input double E4_EARLY_CUT_SL_RATIO = 0.85;         
input bool E4_ENABLE_LADDERED_EXTENSIONS = true; 
input double E4_LADDER_STAGE1_MULTIPLIER = 1.1;   // E4: Stage 1 profit target
input double E4_LADDER_STAGE2_MULTIPLIER = 1.18;   // E4: Stage 2 profit target
input double E4_LADDER_STAGE3_MULTIPLIER = 1.27;   // E4: Stage 3 profit target
input double E4_LADDER_STAGE1_TRAIL_RATIO = 0.45; // E4: Stage 1 trailing SL ratio (same as E1)
input double E4_LADDER_STAGE2_TRAIL_RATIO = 0.55; // E4: Stage 2 trailing SL ratio (same as E1)
input double E4_LADDER_STAGE3_TRAIL_RATIO = 0.65; // E4: Stage 3 trailing SL ratio (same as E1)

input group "===== E5 TRADE MANAGEMENT (SuperBros EMA Alignment - Simple & Clean) ====="
input bool ACCEPT_HIGH_RISK_E5_ENTRIES = true;
input int E5_MAX_EMA_CROSS_AGE = 28;
input double E5_MIN_MOMENTUM_ADX = 18.0;             // E5: Min M1 ADX to enter (0=disabled, filters choppy markets)
input HTF_TREND_MODE E5_HTF_TREND_FILTER = HTF_M5_ONLY;  // E5: Block entries against HTF trend direction
input double E5_HTF_MIN_ADX = 18.0;                  // E5: Min HTF ADX for valid trend signal
input double E5_HTF_MIN_DI_SPREAD = 4.0;             // E5: Min HTF DI spread for valid trend signal
input double E5_RR = 1.5;                           
input double E5_RR_SIDEWAY = 1.2;                   
input double E5_PARTIAL_TP_TRIGGER = 0.54;           
input double E5_PARTIAL_TP_RATIO = 0.50;             
input double E5_SL_TO_BREAKEVEN_BUFFER = 0.05;       
input double E5_TRAILING_SL_FACTOR = 0.38;            // E5: Trail 38% behind price (locks in profit on runners)
input int E5_MAX_TP_EXTENSIONS = 10;                 
input double E5_EARLY_CUT_SL_RATIO = 0.0;            
input double E5_MIN_SL_PIPS = 50.0;                  
input bool E5_ENABLE_LADDERED_EXTENSIONS = true;    
input double E5_DEFERRED_ENTRY_MAX_ATR = 1.0;        
input bool E5_ENABLE_SIDEWAY_ENTRY_BLOCK = true;       // E5: Block new entries during multi-TF sideway (false = ignore sideway at entry)
input int E5_SIDEWAYS_BLOCK_THRESHOLD = 50;
input bool E5_ALLOW_SIDEWAY_EARLY_EXIT = true;        
input double E5_LADDER_STAGE1_MULTIPLIER = 1.05;
input double E5_LADDER_STAGE2_MULTIPLIER = 1.11;
input double E5_LADDER_STAGE3_MULTIPLIER = 1.17;
input double E5_LADDER_STAGE1_TRAIL_RATIO = 0.45;
input double E5_LADDER_STAGE2_TRAIL_RATIO = 0.55;
input double E5_LADDER_STAGE3_TRAIL_RATIO = 0.65;

input group "===== ICHIMOKU CLOUD EARLY EXIT ====="
input bool EXIT_IN_ICHI_CLOUD_E1 = false;         // E1: Exit if price closes inside cloud for N bars
input bool EXIT_IN_ICHI_CLOUD_E2 = false;         // E2: Exit if price closes inside cloud for N bars
input bool EXIT_IN_ICHI_CLOUD_E4 = false;          // E4: Exit if price closes inside cloud for N bars
input int ICHI_CLOUD_EXIT_BARS = 3;               // Consecutive bars in cloud to trigger exit

input group "===== HIGH RISK OVERRIDE (Optional Aggressive Exit) ====="
input bool ALLOW_HIGH_RISK_PARTIAL_TP_OVERRIDE = true;
input double HIGH_RISK_PARTIAL_TP_TRIGGER = 0.55;
input double HIGH_RISK_PARTIAL_TP_RATIO = 0.42;

input group "===== CONSERVATIVE TRADE MANAGEMENT MODE ====="
input bool ENABLE_CONSERVATIVE_TRADE_MGMT = false;  // Master toggle (replaces standard partial TP + trailing when ON)
input double CONS_INITIAL_PARTIAL_R_E1 = 0.30;      // E1: Take initial partial at this R-multiple
input double CONS_INITIAL_PARTIAL_R_E2 = 0.30;      // E2: Take initial partial at this R-multiple
input double CONS_INITIAL_PARTIAL_R_E3 = 0.25;      // E3: Earlier for counter-trend
input double CONS_INITIAL_PARTIAL_R_E4 = 0.30;      // E4: Take initial partial at this R-multiple
input double CONS_INITIAL_PARTIAL_R_E5 = 0.25;      // E5: Earlier partial for EMA alignment
input double CONS_INITIAL_PARTIAL_RATIO_E1 = 0.10;  // E1: Close 10% of position at initial partial
input double CONS_INITIAL_PARTIAL_RATIO_E2 = 0.10;  // E2: Close 10% of position
input double CONS_INITIAL_PARTIAL_RATIO_E3 = 0.15;  // E3: Close 15% (counter-trend, more cautious)
input double CONS_INITIAL_PARTIAL_RATIO_E4 = 0.10;  // E4: Close 10% of position
input double CONS_INITIAL_PARTIAL_RATIO_E5 = 0.12;  // E5: Close 12% of position
input double CONS_POST_PARTIAL_SL_R_E1 = 0.15;      // E1: Move SL to entry + 0.15R after partial
input double CONS_POST_PARTIAL_SL_R_E2 = 0.15;      // E2: Move SL to entry + 0.15R
input double CONS_POST_PARTIAL_SL_R_E3 = 0.10;      // E3: Tighter for reversals
input double CONS_POST_PARTIAL_SL_R_E4 = 0.15;      // E4: Move SL to entry + 0.15R
input double CONS_POST_PARTIAL_SL_R_E5 = 0.12;      // E5: Move SL to entry + 0.12R
input double CONS_TRAIL_R_INCREMENT_E1 = 0.10;      // E1: Trail step every 0.1R gained
input double CONS_TRAIL_R_INCREMENT_E2 = 0.10;      // E2: Trail step every 0.1R gained
input double CONS_TRAIL_R_INCREMENT_E3 = 0.08;      // E3: Tighter steps for counter-trend
input double CONS_TRAIL_R_INCREMENT_E4 = 0.10;      // E4: Trail step every 0.1R gained
input double CONS_TRAIL_R_INCREMENT_E5 = 0.10;      // E5: Trail step every 0.1R gained
input double CONS_TRAIL_SL_STEP_R_E1 = 0.025;       // E1: Move SL up 0.025R per increment (1/4)
input double CONS_TRAIL_SL_STEP_R_E2 = 0.025;       // E2: Move SL up 0.025R per increment
input double CONS_TRAIL_SL_STEP_R_E3 = 0.020;       // E3: Move SL up 0.020R per increment
input double CONS_TRAIL_SL_STEP_R_E4 = 0.025;       // E4: Move SL up 0.025R per increment
input double CONS_TRAIL_SL_STEP_R_E5 = 0.025;       // E5: Move SL up 0.025R per increment

input group "===== LIMIT ORDER EXECUTION ====="
input bool ENABLE_LIMIT_ORDERS = false;              // Master toggle (false = pure market execution)
input bool LIMIT_USE_E1 = true;                      // E1: Use limit orders for EMA bounce entries
input bool LIMIT_USE_E2 = true;                      // E2: Use limit orders for pullback entries
input bool LIMIT_USE_E3 = false;                     // E3: Keep market execution (reversals need speed)
input bool LIMIT_USE_E4 = true;                      // E4: Use limit orders for cloud cross entries
input bool LIMIT_USE_E5 = true;                      // E5: Use limit orders for EMA alignment entries
input double LIMIT_ATR_OFFSET_E1 = 0.15;            // E1: Limit offset = 15% of ATR
input double LIMIT_ATR_OFFSET_E2 = 0.20;            // E2: Limit offset = 20% of ATR (pullback, more room)
input double LIMIT_ATR_OFFSET_E3 = 0.05;            // E3: Minimal offset (just targeting bid side)
input double LIMIT_ATR_OFFSET_E4 = 0.15;            // E4: Limit offset = 15% of ATR
input double LIMIT_ATR_OFFSET_E5 = 0.12;            // E5: Limit offset = 12% of ATR
input double LIMIT_MAX_OFFSET_SL_RATIO = 0.25;      // Max offset as % of SL distance (prevents unreachable limits)
input int LIMIT_EXPIRY_BARS_E1 = 3;                  // E1: Cancel after 3 M1 bars
input int LIMIT_EXPIRY_BARS_E2 = 5;                  // E2: Cancel after 5 bars (pullbacks take longer)
input int LIMIT_EXPIRY_BARS_E3 = 2;                  // E3: Cancel after 2 bars
input int LIMIT_EXPIRY_BARS_E4 = 4;                  // E4: Cancel after 4 bars
input int LIMIT_EXPIRY_BARS_E5 = 3;                  // E5: Cancel after 3 bars
input bool LIMIT_FALLBACK_TO_MARKET = false;         // Fall back to market if limit expires? (OFF = missed = missed)
input int LIMIT_MAX_PENDING = 3;                     // Soft cap on concurrent pending orders (risk budget is real constraint)

//input group "===== INDICATOR PERIODS ====="
int RSI_LEN = 14;                  // RSI period for super trend
int ADX_LEN = 14;                  // ADX period (standard)
double RSI_BULL_LEVEL = 70.0;            // RSI > this => bullish momentum
double RSI_BEAR_LEVEL = 30.0;            // RSI < this => bearish momentum

//input group "===== SESSION SETUP ====="
bool IGNORE_VALID_SESSIONS = false;      // DANGER: Ignore KEM's Valid Sessions

input group "===== NEWS AVOIDANCE SETTINGS ====="
input bool ENABLE_NEWS_FILTER = false;          // Enable economic calendar news filter
input bool AVOID_HIGH_IMPACT_NEWS = true;      // Avoid high impact news events
input bool AVOID_MEDIUM_IMPACT_NEWS = false;    // Avoid medium impact news events
input int NEWS_MINUTES_BEFORE = 10;            // Minutes before news to stop trading
input int NEWS_MINUTES_AFTER = 15;             // Minutes after news to resume trading
bool AVOID_NEWS_TRADING = true;           // For StrategyTester: Avoid US News window (1220-1245 UTC)
// Session windows in UTC (converted 1:1 from the legacy JST values; JST = UTC+9).
int JAPAN_START = 0;                     // Tokyo Session Start  (UTC; was 0900 JST)
int JAPAN_END = 330;                     // Tokyo Session End    (UTC; was 1230 JST)
int LONDON_START = 500;                  // London Session Start (UTC; was 1400 JST)
int LONDON_END = 930;                    // London Session End   (UTC; was 1830 JST)
int NY_START = 1200;                     // New York Session Start (UTC; was 2100 JST)
int NY_END = 1500;                       // New York Session End   (UTC; was 2400 JST)

//group "===== ADAPTIVE LEARNING (OPTIONAL) ====="
bool ENABLE_ADAPTIVE_E1 = false;            // Enable adaptive E1 tracking & optimization
bool ENABLE_ADAPTIVE_E2 = false;            // Enable adaptive E2 tracking & optimization
bool ENABLE_ADAPTIVE_E3 = false;            // Enable adaptive E3 tracking & optimization
bool ENABLE_ADAPTIVE_E4 = false;            // Enable adaptive E4 tracking & optimization
bool ENABLE_ADAPTIVE_E5 = false;            // Enable adaptive E5 tracking & optimization

input group "===== NOTIFICATION SETTINGS ====="
enum NOTIFICATION_MODE {
    NOTIFY_DISABLED = 0,      // Disabled
    NOTIFY_TELEGRAM = 1,      // Telegram
    NOTIFY_DISCORD = 2,       // Discord
    NOTIFY_BOTH = 3           // Telegram + Discord
};
input NOTIFICATION_MODE NotificationMode = NOTIFY_DISABLED;
input bool MADE_FOR_PROP_TRADING = false;     // Simplified alerts, hard block near maximum balance drawdown
string ALLOWED_ACCOUNT_ID = "";  // Internal: empty=any account, set by release script to lock EA to specific account
input bool ENABLE_HEALTH_CHECK_MESSAGES = false;      // Send periodic health check via Discord/Telegram
input int HEALTH_CHECK_INTERVAL_MINUTES = 180;        // Health check frequency (minutes)
input bool ENABLE_NEWS_COUNTDOWN_IN_TELEGRAM = true; // Alert 60min before high-impact news
bool ENABLE_EMA_TOUCH_ALERTS = false;            // Alert when price touches EMA75/100

input group "===== TELEGRAM SETTINGS ====="
bool SEND_LOW_CONFIDENCE_SIGNALS = false;    // NEVER Send alerts for questionable setups (educational - users decide)
input string TELEGRAM_BOT_TOKEN = "";              // Telegram Bot Token (get from @BotFather)
input string TELEGRAM_CHAT_ID_USERS = "";                // Telegram Chat ID for Users (use @userinfobot to get)
input string TELEGRAM_CHAT_ID_ADMINS = "";                // Telegram Chat ID for Admins (use @userinfobot to get)

input group "===== DISCORD SETTINGS ====="
input string DISCORD_WEBHOOK_URL_PUBLIC_USERS = "";
input string DISCORD_WEBHOOK_URL_PRO_USERS = "";
input string DISCORD_WEBHOOK_URL_PREMIUM_USERS = "";
input string DISCORD_WEBHOOK_URL_ADMINS = "";
bool DISCORD_USE_EMBEDS = true;            // Discord: Use rich embeds (recommended)
bool ENABLED_SIGNAL_THREADING = false;           // Discord: Threading requires Bot API (webhooks don't support message_reference) under original BUY/SELL entry
int PNL_UPDATE_COOLDOWN_MINUTES = 3;            // Min minutes between Live Trade Updates per trade

//input group "===== OTHERS ====="
input bool showDebug = true;              // Show Debug Info
input bool E1_GATE_TRACE = false;         // E1 parity: per-bar Print of each E1 gate decision (BLOCK/PASS) for armed triggers
input bool E1_ARM_TRACE  = false;         // E1 parity: per-bar Print of cross-arm decision inputs + trigger ages (KKE1ARM)
bool ENABLE_CSV_EXPORT = false;           // Export trade data to CSV (analytics only - disable for performance)
bool ENABLE_EMAIL_ALERTS = false;           // Enable email alerts
string EMAIL_SUBJECT_PREFIX = "KenKem " + VERSION;   // Email subject prefix

double minimumLotSize = 0.01;          // Minimum Lot Size (0.01 for XAUUSD)
double FEE_PERCENT = 0.01;               // Fee per trade (%)
int MARGIN_LEVEL_PERCENT = 30;           // Maintenance Margin Level (%)
//+------------------------------------------------------------------+
//| ADAPTIVE LEARNING INTERNAL PARAMS (hidden from users)            |
//| These are tuned defaults - users control via ENABLE_ADAPTIVE_E*  |
//+------------------------------------------------------------------+

// TRIGGERS: When to check for adjustments
int ADAPTIVE_MIN_TRADES_FIRST = 15;              // Min trades before first adjustment
int ADAPTIVE_CHECK_EVERY_N_TRADES = 15;          // Check every N trades (4 groups x 15 = 60 trades full cycle)
int ADAPTIVE_MAX_DAYS_BETWEEN_ADJUSTMENTS = 10;   // Max days between adjustments (~7.5 trading days)

// MINIMUM SAMPLES: Statistical significance requirements
int ADAPTIVE_MIN_PARTIAL_TP_SAMPLES = 20;        // Min partial TP trades for adjustment
int ADAPTIVE_MIN_TP_HIT_SAMPLES = 20;            // Min TP hits for RR adjustment
int ADAPTIVE_MIN_TRADES_FOR_FILTERS = 50;        // Min trades for filter adjustment

// THRESHOLDS: How much difference before adjusting
double ADAPTIVE_PARTIAL_TP_THRESHOLD = 1.25;     // PnL ratio threshold for partial TP
double ADAPTIVE_RR_THRESHOLD_HIGH = 1.15;        // Achieved/Target RR ratio to increase
double ADAPTIVE_RR_THRESHOLD_LOW = 0.85;         // Achieved/Target RR ratio to decrease

// STEP SIZES: How much to adjust each time
double ADAPTIVE_PARTIAL_TP_STEP = 0.05;          // Step size for partial TP trigger/ratio
double ADAPTIVE_RR_STEP = 0.10;                  // Step size for reward ratio
double ADAPTIVE_ADX_FILTER_STEP = 0.5;           // Step size for ADX filter
double ADAPTIVE_DI_FILTER_STEP = 0.5;            // Step size for DI spread filter

// BOUNDS: Max deviation from baseline (as percentage)
double ADAPTIVE_PARTIAL_TP_MIN_PCT = 0.70;       // Min % of baseline partial TP
double ADAPTIVE_PARTIAL_TP_MAX_PCT = 1.30;       // Max % of baseline partial TP
double ADAPTIVE_RR_MIN_PCT = 0.8;               // Min % of baseline RR
double ADAPTIVE_RR_MAX_PCT = 1.2;               // Max % of baseline RR
double ADAPTIVE_FILTER_MIN_PCT = 0.80;           // Min % of baseline filters
double ADAPTIVE_FILTER_MAX_PCT = 1.25;           // Max % of baseline filters

// SAFETY GUARDS (derived from global risk settings where possible)
double ADAPTIVE_DRAWDOWN_TRIGGER_PCT = 0.12;     // DD % to revert to baseline (12%)
int ADAPTIVE_PAUSE_TRADES_AFTER_REVERT = 25;     // Trades to skip after revert
double ADAPTIVE_WILSON_CI_CONFIDENCE = 0.95;     // Wilson CI confidence level
double ADAPTIVE_WILSON_CI_THRESHOLD = 0.05;      // CI significance threshold

// ABSOLUTE LIMITS: Hard safety clamps (never exceed these)
double ADAPTIVE_ADX_ABSOLUTE_MIN = 12.0;         // Absolute min ADX
double ADAPTIVE_ADX_ABSOLUTE_MAX = 32.0;         // Absolute max ADX
double ADAPTIVE_DI_SPREAD_ABSOLUTE_MIN = 3.0;    // Absolute min DI spread
double ADAPTIVE_DI_SPREAD_ABSOLUTE_MAX = 12.0;   // Absolute max DI spread
double ADAPTIVE_RR_ABSOLUTE_MIN = 1.1;           // Absolute min RR
double ADAPTIVE_RR_ABSOLUTE_MAX = 2.5;           // Absolute max RR
double ADAPTIVE_PARTIAL_TRIGGER_MIN = 0.55;      // Absolute min partial trigger
double ADAPTIVE_PARTIAL_TRIGGER_MAX = 0.90;      // Absolute max partial trigger
// P1 Trade Management absolute limits (SL, Trailing, Breakeven)
double ADAPTIVE_ATR_MULT_ABSOLUTE_MIN = 0.8;     // Min ATR multiplier for SL (0.8x ATR)
double ADAPTIVE_ATR_MULT_ABSOLUTE_MAX = 3;     // Max ATR multiplier for SL (2.5x ATR)
double ADAPTIVE_TRAILING_ABSOLUTE_MIN = 0.15;    // Min trailing factor (15% distance)
double ADAPTIVE_TRAILING_ABSOLUTE_MAX = 0.70;    // Max trailing factor (70% distance)
double ADAPTIVE_BREAKEVEN_ABSOLUTE_MIN = 0.01;   // Min breakeven buffer (1%)
double ADAPTIVE_BREAKEVEN_ABSOLUTE_MAX = 0.10;   // Max breakeven buffer (10%)
double ADAPTIVE_EARLY_CUT_ABSOLUTE_MIN = 0.65;   // Min early cut ratio (65% to SL)
double ADAPTIVE_EARLY_CUT_ABSOLUTE_MAX = 0.98;   // Max early cut ratio (98% to SL)
int ADAPTIVE_MAX_TP_EXT_ABSOLUTE_MIN = 2;        // Min TP extensions
int ADAPTIVE_MAX_TP_EXT_ABSOLUTE_MAX = 50;       // Max TP extensions
double ADAPTIVE_RR_SIDEWAY_MIN_PCT = 0.70;       // Sideway RR min % of baseline
double ADAPTIVE_RR_SIDEWAY_MAX_PCT = 1.20;       // Sideway RR max % of baseline

// REVERT DEFAULTS: Conservative values when reverting to baseline
double ADAPTIVE_REVERT_SIDEWAY_RR_PCT = 0.85;    // Sideway RR as % of baseline
double ADAPTIVE_REVERT_PARTIAL_TRIGGER = 0.75;   // Partial TP trigger on revert
double ADAPTIVE_REVERT_HIGH_RISK_ADX_ADD = 5.0;  // ADX boost for high-risk
double ADAPTIVE_REVERT_HIGH_RISK_DI_ADD = 2.0;   // DI boost for high-risk

input group "===== TIMEFRAME CONFIGURATION ====="
input ENUM_TIMEFRAMES INPUT_TF0 = PERIOD_M1;    // TF0: Primary entry timeframe
input ENUM_TIMEFRAMES INPUT_TF1 = PERIOD_M3;    // TF1: Confirmation timeframe
input ENUM_TIMEFRAMES INPUT_TF2 = PERIOD_M5;    // TF2: Context timeframe
input ENUM_TIMEFRAMES INPUT_TF3 = PERIOD_M15;   // TF3: Regime timeframe
input ENUM_TIMEFRAMES INPUT_TF4 = PERIOD_H1;    // TF4: Anchor timeframe (reserved)

input group "===== EMA PERIOD CONFIGURATION ====="
input int INPUT_EMA0_PERIOD = 10;    // EMA0: Fast EMA period
input int INPUT_EMA1_PERIOD = 25;    // EMA1: Signal EMA period
input int INPUT_EMA2_PERIOD = 71;    // EMA2: Pullback EMA period
input int INPUT_EMA3_PERIOD = 97;   // EMA3: Bounce EMA period
input int INPUT_EMA4_PERIOD = 192;   // EMA4: Anchor EMA period
