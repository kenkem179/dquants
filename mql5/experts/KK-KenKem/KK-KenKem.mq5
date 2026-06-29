#property copyright "Copyright 2026, KenKem / dquants"
#property link ""
#property version "1.03"
#property strict
#define VERSION "KK-KenKem 1.0-dev"
#property description "KK-KenKem — dquants-native faithful clone of KenKemExpert v1.8.154 (E1/E2/E5; E4 off via .set). Parity baseline for C++-driven optimization; cosmetic pruning deferred until post-P4 parity confirm. See docs/BUILD-PLAN-KENKEM-REWRITE.md."

// Include necessary libraries
#include <Trade\Trade.mqh>

// Shared account-lock guard (common to all KK EAs)
#include "../KK-Common/AccountLock.mqh"
// Shared cross-EA prop Account Risk Guardian (same persistent GVs as KK-MasterVP)
#include "../KK-Common/AccountGuardian.mqh"

// Include modular configuration files
#include "Config/InputParams.mqh"
#include "Core/GlobalState.mqh"
#include "Config/RuntimeConfig.mqh"
#include "Core/MarketCondition.mqh"
#include "Core/Indicators/EMAHelpers.mqh"
#include "Core/Indicators/ADXRSIHelpers.mqh"
#include "Core/TrendIdentifier.mqh"
#include "Entries/EntryHelpers.mqh"

#include "Utils/Helpers.mqh"
#include "Utils/BrokerHelpers.mqh"
#include "Utils/SessionManager.mqh"
#include "Utils/NewsCalendar.mqh"
#include "Utils/LocalNewsFilter.mqh"
#include "DataCollection/CSVExport.mqh"

#include "Alerts/CommonAlerts.mqh"
#include "Alerts/TelegramAlerts.mqh"
#include "Alerts/DiscordAlerts.mqh"
#include "Alerts/TradeAlerts.mqh"
#include "Alerts/SystemAlerts.mqh"

// Global trade object
CTrade trade;

// Include TradeManagement AFTER CTrade declaration
#include "TradeManagement/RiskManager.mqh"

#include "Parity/BarTrace.mqh"   // PARITY: per-bar E5 decision-trace struct (must precede Entry5.mqh)
#include "Parity/RealTrace.mqh"  // PARITY: REAL-PATH E5 entry-decision trace struct (must precede Entry5.mqh)
// Phase 1.5: OOP Entry classes (not yet active, old code still runs)
#include "Entries/Entry1.mqh"
#include "Entries/Entry2.mqh"
#include "Entries/Entry3.mqh"
#include "Entries/Entry4.mqh"
#include "Entries/Entry5.mqh"
#include "TradeManagement/TradeManager.mqh"
#include "Parity/TradeJournal.mqh"

// Magic number base (timestamp format: yyyyddhhmm)
long MAGIC_BASE = 0;

// Cross-EA prop Account Risk Guardian (shares anchors with KK-MasterVP via login-keyed GVs)
KKAccountGuardian g_kkGuard;

// Flatten ONLY KenKem's own positions (comment-tagged "KenKemST"); never touches other EAs.
void KkGuardFlattenOwn() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "KenKemST") < 0) continue;
      trade.PositionClose(tk);
   }
}

// Phase 1.5: OOP class instances (initialized in OnInit, not yet used)
Entry1* entry1 = NULL;
Entry2* entry2 = NULL;
Entry3* entry3 = NULL;
Entry4* entry4 = NULL;
Entry5* entry5 = NULL;
TradeManager* tradeManager = NULL;

// Adaptive learning: Cached ATR handle for performance
int g_atrM1Handle = INVALID_HANDLE;
int g_atrM3Handle = INVALID_HANDLE;  // M3 ATR (E4 cloud + E5 multi-TF sideway)
int g_atrM5Handle = INVALID_HANDLE;  // E5: M5 ATR for multi-TF sideway scoring

bool g_kkAccessExpired = false;   // set true once the baked ACCESS_EXPIRY passes (runtime)

int OnInit() {
    // Account lock: hidden ALLOWED_ACCOUNT_ID (empty=any) is baked per-account
    // by the release script. On mismatch the shared guard Alerts and we abort
    // init so MT5 never ticks the EA (no detection, no execution).
    if (!KK_AccountAuthorized(ALLOWED_ACCOUNT_ID, ALLOWED_ACCOUNT_SERVER))
        return INIT_FAILED;

    // Access expiry: if already past the baked date at attach, start in
    // MANAGE-ONLY mode (no new trades) so any pre-existing position still gets
    // managed (e.g. after a VPS restart). Alert once here; OnTick won't re-alert.
    if (KK_AccessExpired(ACCESS_EXPIRY)) {
        g_kkAccessExpired = true;
        Alert("Expired Access");
        Print("[ACCESS] KK-KenKem access expired (", ACCESS_EXPIRY, ") - no new trades; managing open positions only.");
    }

    // Auto-detect account leverage from broker (overrides fallback value in InputParams.mqh)
    int detectedLeverage = (int)AccountInfoInteger(ACCOUNT_LEVERAGE);
    if (detectedLeverage > 0) {
        LEVERAGE = detectedLeverage;
    }
    Print("[INIT] Leverage: ", LEVERAGE, (detectedLeverage > 0 ? " (auto-detected)" : " (fallback)"));

    // Auto-detect initial account balance from broker
    double detectedBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    if (detectedBalance > 0) {
        INITIAL_ACCOUNT_BALANCE = detectedBalance;
    }
    Print("[INIT] Initial Balance: ", DoubleToString(INITIAL_ACCOUNT_BALANCE, 2),
          (detectedBalance > 0 ? " (auto-detected)" : " (fallback)"));
    
    // STEP 1: Initialize runtime configuration (asymmetric RR, EMA periods, etc.)
    InitializeConfig();
    
    // Generate magic number base from current timestamp (yyyymmddhhmm format)
    datetime now = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(now, dt);
    MAGIC_BASE = (long)(dt.year * 100000000 + dt.mon * 1000000 + dt.day * 10000 + dt.hour * 100 + dt.min);
    
    // Set the magic number for the trade object
    trade.SetExpertMagicNumber(MAGIC_BASE);
    
    Print("KenKem Strategy initialized with MAGIC_BASE: ", MAGIC_BASE);

    // Cross-EA prop Account Risk Guardian — shares persistent anchors with KK-MasterVP
    // (login-keyed terminal GlobalVariables). InitialBalance pins the static floor to the
    // firm line regardless of attach balance.
    KKGuardConfig kkgc;
    kkgc.enabled             = InpGuardEnable;
    kkgc.dailyLossPct        = InpGuardDailyLossPct;
    kkgc.overallDDPct        = InpGuardOverallDDPct;
    kkgc.bufferPct           = InpGuardBufferPct;
    kkgc.ddAnchorMode        = InpGuardDDAnchor;
    kkgc.manualDayAnchor     = InpGuardManualDayAnchor;
    kkgc.staticAnchorOverride= InpGuardInitialBalance;
    kkgc.flattenOnBreach     = InpGuardFlatten;
    g_kkGuard.Init(kkgc);
    
    // DIAGNOSTIC: Verify parameters are loaded correctly
    // Print("=== PARAMETER VERIFICATION ===");
    // Print("E1_PARTIAL_TP_TRIGGER: ", E1_PARTIAL_TP_TRIGGER);
    // Print("E1_PARTIAL_TP_RATIO: ", E1_PARTIAL_TP_RATIO);
    // Print("TP_EXTENSION_MIN_PIPS: ", TP_EXTENSION_MIN_PIPS);
    // Print("E1_RR: ", E1_RR);
    // Print("ALLOW_PARTIAL_TP: ", ALLOW_PARTIAL_TP);
    // Print("ALLOW_TP_EXTENSION: ", ALLOW_TP_EXTENSION);
    // Print("ENABLE_ADAPTIVE_E1: ", ENABLE_ADAPTIVE_E1);
    // Print("ADAPTIVE_MIN_TRADES_FIRST: ", ADAPTIVE_MIN_TRADES_FIRST);
    // Print("ADAPTIVE_PARTIAL_TP_STEP: ", ADAPTIVE_PARTIAL_TP_STEP);
    // Print("==============================");
    
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double detectedContractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    bool isGoldSymbol = (StringFind(_Symbol, "XAUUSD") >= 0 || StringFind(_Symbol, "GOLD") >= 0);

    if (isGoldSymbol) {
        // Gold: pip = _Point directly (NOT the 10x forex convention)
        // Detect from broker digits so EA works on any broker (2-digit or 3-digit gold feeds)
        pipSize = (digits > 0) ? MathPow(10.0, -(double)digits) : 0.01;
        if (detectedContractSize > 0) contractSize = detectedContractSize;
        minimumLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        if (minimumLotSize <= 0) minimumLotSize = 0.01;
        Print("[GOLD SYMBOL] ", _Symbol, " | PipSize=", DoubleToString(pipSize, 5),
              " | ContractSize=", DoubleToString(contractSize, 2), " | MinLot=", DoubleToString(minimumLotSize, 2));
    }
    else if (AUTO_DETECT_SYMBOL_PARAMS) {
        // Auto-detect for forex and other CFDs
        // Detect pip size based on symbol digits
        if (digits == 3 || digits == 5) pipSize = 0.0001;      // Forex pairs (5-digit or 3-digit JPY broker)
        else if (digits == 2) pipSize = 0.01;                   // Indices, 2-digit CFDs
        else if (digits == 1) pipSize = 0.1;                    // Some CFDs
        else pipSize = MathPow(10, -digits);                    // Fallback

        if (detectedContractSize > 0) contractSize = detectedContractSize;

        minimumLotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        if (minimumLotSize <= 0) minimumLotSize = 0.01;

        Print("[SYMBOL] ", _Symbol, " | PipSize=", DoubleToString(pipSize, 5),
            " | ContractSize=", DoubleToString(contractSize, 2),
            " | MinLot=", DoubleToString(minimumLotSize, 2),
            " | StdLot=", DoubleToString(myStandardLotSize, 2),
            " | Leverage=", LEVERAGE);
    }        
    // Symbol-specific overrides (crypto needs special handling)
    if (StringFind(_Symbol, "ETHUSD") >= 0) {
        pipSize = 0.1;
        contractSize = 1;
        myStandardLotSize = myStandardLotSize * 10;
        minimumLotSize = 0.1;
    }
    else if (StringFind(_Symbol, "BTCUSD") >= 0) {
        pipSize = 1;
        contractSize = 1;
        myStandardLotSize = myStandardLotSize * 2;
        minimumLotSize = 0.01;
    }

    // Visual preferences
    ChartSetInteger(0,CHART_SHOW_TRADE_LEVELS,true);
    ChartSetInteger(0,CHART_SHOW_TRADE_HISTORY,true);

    // Initialize account balance
    accountBalance = INITIAL_ACCOUNT_BALANCE;
    maxLossUSD = getMaxLossUSD();
    
    // ================================================================
    // CRITICAL FIX: Reset all static variables to prevent backtest contamination
    // This ensures each Strategy Tester run starts with clean state
    // Addresses "backtesting illusion" concern about static variable state leakage
    // ================================================================
    
    // Reset peak balance tracking (for drawdown calculations)
    peakAccountBalance = INITIAL_ACCOUNT_BALANCE;
    peakBalanceSetTime = 0;
    lastPeakDecayTime = 0;
    originalPeakAtRecovery = 0;
    
    // Reset EA startup time
    eaStartTime = TimeCurrent();
    
    // Reset indicator cache to force fresh calculations
    lastCachedBar = -1;
    cache.valid = false;
    ArrayInitialize(cache.adx, 0.0);
    ArrayInitialize(cache.diPlus, 0.0);
    ArrayInitialize(cache.diMinus, 0.0);
    cache.adxShort = 0.0;
    cache.diPlusShort = 0.0;
    cache.diMinusShort = 0.0;
    cache.currentPrice = 0.0;
    cache.prevPrice = 0.0;
    cache.high = 0.0;
    cache.low = 0.0;
    cache.hasSufficientBullMomentum = false;
    cache.hasSufficientBearMomentum = false;
    cache.superTrendE1 = TREND_NONE;
    cache.superTrendE2 = TREND_NONE;
    
    // Reset risk management tracking
    consecutiveLosses = 0;
    highRiskTradesInSession = 0;
    lastEntryTime = 0;
    lastLossTime = 0;
    
    // Reset per-entry-type consecutive loss tracking
    consecutiveLosses_LE1 = 0; consecutiveLosses_LE2 = 0; consecutiveLosses_LE3 = 0; consecutiveLosses_LE4 = 0;
    consecutiveLosses_SE1 = 0; consecutiveLosses_SE2 = 0; consecutiveLosses_SE3 = 0; consecutiveLosses_SE4 = 0;
    blockedUntil_LE1 = 0; blockedUntil_LE2 = 0; blockedUntil_LE3 = 0; blockedUntil_LE4 = 0;
    blockedUntil_SE1 = 0; blockedUntil_SE2 = 0; blockedUntil_SE3 = 0; blockedUntil_SE4 = 0;
    losingStreakBlockUntil = 0;
    drawdownBlockedUntil = 0;
    drawdownTriggered = false;
    
    // Reset session tracking
    currentDate = 0;
    dailyStartBalance = INITIAL_ACCOUNT_BALANCE;
    dailyLossLimitReached = false;
    tradeSLTPCountInSession = 0;
    
    // Reset entry detection state
    lastEntryBarIndex = -1;
    lastBarIndex = -999;
    currentBar = -1;
    lastSkipAlertBar = -1;
    lastBarProcessedSkips = -1;
    
    // WARNING: Function-local statics (e.g., brokerCheckCounter in TradeManager.mqh)
    // do NOT reset between Strategy Tester optimization runs. They persist within
    // the tester session. Consider moving critical state to class members for proper reset.
    
    if(showDebug) {
        Print("[INIT] All static variables reset - clean state guaranteed for this run");
        Print("   Peak Balance: $", DoubleToString(peakAccountBalance, 2));
        Print("   EA Start Time: ", TimeToString(eaStartTime, TIME_DATE|TIME_MINUTES));
        Print("   Consecutive Losses: ", consecutiveLosses);
        Print("   Cache valid: ", cache.valid ? "true" : "false");
    }
    
    // Load persisted state from previous session (if available)
    LoadStateFromFile();
    
    // Populate runtime TF and EMA period arrays from input params
    TF_ARRAY[TF0] = INPUT_TF0;
    TF_ARRAY[TF1] = INPUT_TF1;
    TF_ARRAY[TF2] = INPUT_TF2;
    TF_ARRAY[TF3] = INPUT_TF3;
    TF_ARRAY[TF4] = INPUT_TF4;
    EMA_PERIOD_ARRAY[EMA0] = INPUT_EMA0_PERIOD;
    EMA_PERIOD_ARRAY[EMA1] = INPUT_EMA1_PERIOD;
    EMA_PERIOD_ARRAY[EMA2] = INPUT_EMA2_PERIOD;
    EMA_PERIOD_ARRAY[EMA3] = INPUT_EMA3_PERIOD;
    EMA_PERIOD_ARRAY[EMA4] = INPUT_EMA4_PERIOD;

    // ================================================================
    // TIMEFRAME VALIDATION: Check for duplicate TFs and broker data availability
    // Must run BEFORE any indicator handle creation to give clear failure reasons
    // ================================================================
    string tfNames[NUM_TF];
    for(int tf = 0; tf < NUM_TF; tf++) {
        tfNames[tf] = EnumToString(TF_ARRAY[tf]);
        
        // Check 1: Broker has bars available for this TF (0 = no native or synthesized data)
        int bars = Bars(_Symbol, TF_ARRAY[tf]);
        if (bars < 10) {
            Print("INIT_FAILED: Timeframe TF", tf, " (", tfNames[tf], ") has only ", bars,
                  " bars on this broker. Check if the broker supports this timeframe.");
            return INIT_FAILED;
        }
        
        // Check 2: Duplicate TF detection (silent logic bugs - all higher indices would share same data)
        for(int prev = 0; prev < tf; prev++) {
            if (TF_ARRAY[tf] == TF_ARRAY[prev]) {
                Print("INIT_FAILED: TF", tf, " (", tfNames[tf], ") duplicates TF", prev,
                      ". Each timeframe slot must be unique.");
                return INIT_FAILED;
            }
        }
        
        Print("[INIT] TF", tf, " = ", tfNames[tf], " | Bars available: ", bars);
    }

    // Initialize EMA handles using configurable TF_ARRAY and EMA_PERIOD_ARRAY
    for(int tf = 0; tf < NUM_TF; tf++) {
        for(int ema = 0; ema < NUM_EMA; ema++) {
            emaHandles[tf][ema] = iMA(_Symbol, TF_ARRAY[tf], EMA_PERIOD_ARRAY[ema], 0, MODE_EMA, PRICE_CLOSE);
        }
    }
    
    // Initialize ADX handles for all timeframes using 2D array
    for(int tf = 0; tf < NUM_TF; tf++) {
        adxHandles[tf] = iADX(_Symbol, TF_ARRAY[tf], ADX_LEN);
    }
    
    // Initialize ADX(9) handle for E3 micro-trend detection
    adxShortHandle = iADX(_Symbol, TF_ARRAY[TF0], 9);

    // Initialize RSI handle for super trend detection
    rsiHandle = iRSI(_Symbol, TF_ARRAY[TF0], RSI_LEN, PRICE_CLOSE);
    
    // Initialize Ichimoku Cloud handles for trend quality bonus (M1 and M3)
    // E4 ALWAYS needs Ichimoku for cloud cross detection
    if (USE_ICHIMOKU_E1 || USE_ICHIMOKU_E2 || ENABLE_E4_ENTRIES) {
        ichimokuHandles[0] = iIchimoku(_Symbol, TF_ARRAY[TF0], ICHIMOKU_TENKAN, ICHIMOKU_KIJUN, ICHIMOKU_SENKOU);
        ichimokuHandles[1] = iIchimoku(_Symbol, TF_ARRAY[TF1], ICHIMOKU_TENKAN, ICHIMOKU_KIJUN, ICHIMOKU_SENKOU);
    }
    
    // Initialize cached ATR handle for adaptive learning (M1, 14-period for 5-40min scalping)
    g_atrM1Handle = iATR(_Symbol, TF_ARRAY[TF0], 14);
    if (g_atrM1Handle == INVALID_HANDLE) {
        Print("ERROR: Failed to create ATR M1(14) handle for adaptive learning");
    }
    
    // Initialize M3 ATR handle (E4 cloud thickness + E5 multi-TF sideway)
    g_atrM3Handle = iATR(_Symbol, TF_ARRAY[TF1], 14);
    if (g_atrM3Handle == INVALID_HANDLE) {
        Print("ERROR: Failed to create ATR M3(14) handle");
    }

    // Initialize M5 ATR handle for E5 multi-TF sideway scoring
    g_atrM5Handle = iATR(_Symbol, TF_ARRAY[TF2], 14);
    if (g_atrM5Handle == INVALID_HANDLE) {
        Print("ERROR: Failed to create ATR M5(14) handle for E5 multi-TF sideway");
    }
    
    // Calculate baseline ATR for volatility-adjusted lot sizing (average of last 50 bars)
    // Only calculate if any entry type uses volatility adjustment
    if ((VOL_LOT_ADJ_E1 || VOL_LOT_ADJ_E2 || VOL_LOT_ADJ_E3 || VOL_LOT_ADJ_E4) && g_atrM1Handle != INVALID_HANDLE) {
        double atrBuffer[50];
        if (CopyBuffer(g_atrM1Handle, 0, 1, 50, atrBuffer) == 50) {
            double sum = 0;
            for (int i = 0; i < 50; i++) sum += atrBuffer[i];
            baselineATR = sum / 50.0;
            Print("[INIT] Baseline ATR for lot sizing: ", DoubleToString(baselineATR / pipSize, 1), " pips");
            Print("[INIT] Vol-adjusted lots: E1=", VOL_LOT_ADJ_E1, " E2=", VOL_LOT_ADJ_E2, " E3=", VOL_LOT_ADJ_E3, " E4=", VOL_LOT_ADJ_E4);
        }
    }
    
    // Initialize EMA buffers - fixed-size array [20][30] to simulate [4][5][bufferSize]
    int bufferSize = ENTRY_SHIFT + 10; // Calculate buffer size for validation
    
    // Check if EMA handles are valid
    for(int tf = 0; tf < NUM_TF; tf++) {
        for(int ema = 0; ema < NUM_EMA; ema++) {
            if(emaHandles[tf][ema] == INVALID_HANDLE) {
                Print("Error creating EMA handle for timeframe ", tf, " period ", EMA_PERIOD_ARRAY[ema]);
                return INIT_FAILED;
            }
        }
    }
    
    // Check ADX handles
    for(int tf = 0; tf < 4; tf++) {
        if(adxHandles[tf] == INVALID_HANDLE) {
            Print("Error creating ADX handle for timeframe ", tf);
            return INIT_FAILED;
        }
    }
    
    // Check ADX(9) handle
    if(adxShortHandle == INVALID_HANDLE) {
        Print("Error creating ADX(9) handle for micro-trend detection");
        return INIT_FAILED;
    }
    
    // Check RSI handle
    if (rsiHandle == INVALID_HANDLE) {
        Print("Error creating RSI indicator handle");
        return INIT_FAILED;
    }
    
    // Check Ichimoku handles (only if ANY entry type uses it)
    if (USE_ICHIMOKU_E1 || USE_ICHIMOKU_E2 || ENABLE_E4_ENTRIES) {
        if (ichimokuHandles[0] == INVALID_HANDLE || ichimokuHandles[1] == INVALID_HANDLE) {
            Print("Error creating Ichimoku indicator handles");
            return INIT_FAILED;
        }
    }
    
    // Initialize trade tracking array
    ArrayResize(trades, 0);
    ArrayResize(tradeExtras, 0);
    
    // Initialize performance statistics
    InitializePerformanceStats();
    
    // Phase 1.5: Initialize OOP classes (not yet used, old code still runs)
    entry1 = new Entry1();
    entry2 = new Entry2();
    entry3 = new Entry3();
    entry3.InitIndicatorHandles();  // Initialize E3 indicator handles (EMA for price confirmation)
    entry4 = new Entry4();
    entry5 = new Entry5();
    tradeManager = new TradeManager();
    if(showDebug) Print("[OOP] Entry classes and TradeManager initialized (standby mode)");
    
    // Load previously saved adaptive parameters (resume learning from last session)
    // BACKTEST STRATEGY:
    //   - DON'T LOAD: Each backtest starts fresh for honest results (no look-ahead bias)
    //   - DO SAVE: Pre-train params for production deployment (saves at end of backtest)
    // PRODUCTION: Load previous params to resume learning
    if(!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION)) {
        if(entry1 != NULL) entry1.LoadAdaptiveParams();
        if(entry2 != NULL) entry2.LoadAdaptiveParams();
        if(entry3 != NULL) entry3.LoadAdaptiveParams();
        if(showDebug) Print("[Adaptive] Loaded saved parameters from previous session");
    } else {
        if(showDebug) Print("[Adaptive] BACKTEST MODE - fresh input params (saves at end for production)");
    }
    
    // Initialize news filter
    if (ENABLE_NEWS_FILTER) {
        if (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
            InitLocalNewsFilter();
            if (showDebug) {
                Print("NEWS FILTER: BACKTEST MODE - Using local CSV cache");
                Print("NEWS FILTER: Buffer = ", NEWS_MINUTES_BEFORE, " min before, ", NEWS_MINUTES_AFTER, " min after");
            }
        } else {
            UpdateNewsEvents();
            InitLocalNewsFilter();
            if (showDebug) {
                Print("NEWS FILTER: Initialized. Monitoring high/medium impact news for USD");
                Print("NEWS FILTER: Buffer = ", NEWS_MINUTES_BEFORE, " min before, ", NEWS_MINUTES_AFTER, " min after");
            }
        }
    }
    
    // Auto-adjust USE_LIVE_PRICE setting for backtesting/optimization
    if (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
        if (USE_LIVE_PRICE_FOR_ENTRY_NOT_CLOSED_PRICE) {
            USE_LIVE_PRICE_FOR_ENTRY_NOT_CLOSED_PRICE = false;
            Print("⚙️ [AUTO-CONFIG] USE_LIVE_PRICE forced to FALSE (backtesting mode - no live prices available)");
        }
    } else {
        if (showDebug) {
            Print("⚙️ [CONFIG] USE_LIVE_PRICE = ", USE_LIVE_PRICE_FOR_ENTRY_NOT_CLOSED_PRICE ? "TRUE (using live prices)" : "FALSE (using closed prices)");
        }
    }
    
    // NOTE: Historical EMA initialization moved to OnTick() to ensure indicators are ready
    // InitializeEMAFlagsFromHistory() will be called after first successful indicator read
    InitializeAdaptiveParams();

    InitKenKemJournal();   // PARITY: per-trade CSV (no-op unless InpExportTradeJournal)
    InitBarTrace();        // PARITY: per-bar E5 decision trace (no-op unless InpExportBarTrace)
    InitRealTrace();       // PARITY: REAL-PATH E5 entry-decision trace (no-op unless InpExportRealTrace)

    EventSetTimer(60);
    return INIT_SUCCEEDED;
}

void InitializeAdaptiveParams() {
        // Initialize adaptive parameters
    adaptiveParams.isActive = ENABLE_ADAPTIVE_E3;
    if (!adaptiveParams.isActive || adaptiveParams.adaptive_ADX_LOW_THRESHOLD == 0.0) {
        // First run or adaptive disabled - use input values
        adaptiveParams.adaptive_ADX_LOW_THRESHOLD = ADX_LOW_THRESHOLD;
        adaptiveParams.adaptive_MIN_MOMENTUM_ADX = MIN_MOMENTUM_ADX_REQUIRED;
    }
    if (adaptiveParams.isActive && showDebug) {
        Print("[ADAPTIVE] Enabled - ADX=", adaptiveParams.adaptive_ADX_LOW_THRESHOLD,
              " MIN_MOMENTUM_ADX=", adaptiveParams.adaptive_MIN_MOMENTUM_ADX);
    }
    
    // Send startup notification (to both Telegram and Discord if enabled)
    string startupMsg = "KENKEM EA STARTED\n\n";
    startupMsg += "- Symbol: " + _Symbol + "\n";
    startupMsg += "\nKenKem v" + VERSION + " | Acc ID: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
    startupMsg += "\n\nEA is now monitoring the market...";
    SendSystemMessage(startupMsg, true);  // Admin-only
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    CloseKenKemJournal();   // PARITY: flush/close per-trade CSV
    CloseBarTrace();        // PARITY: flush/close per-bar E5 decision trace
    CloseRealTrace();       // PARITY: flush/close REAL-PATH E5 entry-decision trace
    // Save adaptive params with skipped trade stats (reuses existing trades[] array)
    int skipped1, wins1, losses1, skipped2, wins2, losses2, skipped3, wins3, losses3;
    if(entry1 != NULL) {
        GetSkippedTradeStats(ENTRY_L_E1, skipped1, wins1, losses1);
        entry1.SaveAdaptiveParams(skipped1, wins1, losses1);
    }
    if(entry2 != NULL) {
        GetSkippedTradeStats(ENTRY_L_E2, skipped2, wins2, losses2);
        entry2.SaveAdaptiveParams(skipped2, wins2, losses2);
    }
    if(entry3 != NULL) {
        GetSkippedTradeStats(ENTRY_L_E3, skipped3, wins3, losses3);
        entry3.SaveAdaptiveParams(skipped3, wins3, losses3);
    }
    if(showDebug) Print("[Adaptive] Saved performance metrics to files");
    
    // Phase 1.5: Cleanup OOP classes
    if(entry1 != NULL) { delete entry1; entry1 = NULL; }
    if(entry2 != NULL) { delete entry2; entry2 = NULL; }
    if(entry3 != NULL) { delete entry3; entry3 = NULL; }
    if(entry4 != NULL) { delete entry4; entry4 = NULL; }
    if(entry5 != NULL) { delete entry5; entry5 = NULL; }
    if(tradeManager != NULL) { delete tradeManager; tradeManager = NULL; }
    MarketCondition::Destroy();  // Clean up singleton to prevent state leakage between optimization runs
    if(showDebug) Print("[OOP] Entry classes, TradeManager, and MarketCondition cleaned up");
    
    // Save state before shutdown
    SaveStateToFile();
    
    EventKillTimer();

    // Release EMA indicator handles using 2D array
    for(int tf = 0; tf < 4; tf++) {
        for(int ema = 0; ema < 5; ema++) {
            IndicatorRelease(emaHandles[tf][ema]);
        }
    }
    
    // Release ADX indicator handles using 2D array
    for(int tf = 0; tf < 4; tf++) {
        IndicatorRelease(adxHandles[tf]);
    }
    
    // Release ADX(9) handle
    IndicatorRelease(adxShortHandle);

    // Release cached RSI handles per timeframe
    for (int tf = 0; tf < 5; tf++) {
        if (rsiHandlesTF[tf] != INVALID_HANDLE) {
            IndicatorRelease(rsiHandlesTF[tf]);
            rsiHandlesTF[tf] = INVALID_HANDLE;
            rsiHandlePeriodTF[tf] = 0;
        }
    }
    
    // Release Ichimoku handles (only if ANY entry type uses it)
    if (USE_ICHIMOKU_E1 || USE_ICHIMOKU_E2 || ENABLE_E4_ENTRIES) {
        IndicatorRelease(ichimokuHandles[0]);
        IndicatorRelease(ichimokuHandles[1]);
    }
    
    // Release ATR and RSI handles
    if (g_atrM1Handle != INVALID_HANDLE) IndicatorRelease(g_atrM1Handle);
    if (g_atrM3Handle != INVALID_HANDLE) IndicatorRelease(g_atrM3Handle);
    if (g_atrM5Handle != INVALID_HANDLE) IndicatorRelease(g_atrM5Handle);
    if (rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);

    // Reset cache
    cache.valid = false;
    lastCachedBar = -1;
    
    // Close CSV file if open
    if (csvFileHandle != INVALID_HANDLE) {
        FlushCSVBuffer();
        FileClose(csvFileHandle);
        csvFileHandle = INVALID_HANDLE;
        Print("CSV Export file closed");
    }
}

// ===== TRADE EXECUTION AND SKIP DECISION FUNCTION =====
// Reusable function to handle entry or skip decisions with consistent logging and alerting
void EnterOrSkipTrade(Trade &detectedTrade, bool isEntering, string reasonMsg) {
    if (detectedTrade.type == "") {
        Print("[ALERT BLOCKED] EnterOrSkipTrade called but detectedTrade.type is EMPTY! Reason: ", reasonMsg);
        return; // No trade to process
    }

    // Access expiry: never OPEN a new trade once expired. This is the single
    // entry choke point (ProcessNewEntry runs only in the isEntering branch
    // below), so flipping isEntering here blocks every entry path while leaving
    // open-position management untouched.
    if (g_kkAccessExpired && isEntering) {
        isEntering = false;
        reasonMsg  = "Expired Access";
    }

    Print("[ALERT] EnterOrSkipTrade: isEntering=", isEntering, " type=", detectedTrade.type, " reason=", reasonMsg);
    
    // Calculate trade details for logging
    double riskDistance = MathAbs(detectedTrade.stopLoss - detectedTrade.entryPrice);
    double riskPips = riskDistance / pipSize;
    double rewardPips = MathAbs(detectedTrade.takeProfit - detectedTrade.entryPrice) / pipSize;
    double rewardRiskRatio = rewardPips / MathMax(riskPips, 0.01);
    
    // Create detailed trade information string (pips only, no USD)
    string tradeDetails = StringFormat("%s | %s | Entry: %.5f | SL: %.5f | TP: %.5f | Lot: %.2f | Risk: %.1f pips | Reward: %.1f pips | RR: %.2f",
                                      _Symbol,
                                      detectedTrade.type,
                                      detectedTrade.entryPrice,
                                      detectedTrade.stopLoss,
                                      detectedTrade.takeProfit,
                                      detectedTrade.lotSize,
                                      riskPips,
                                      rewardPips,
                                      rewardRiskRatio);
    
    if (isEntering) {
        // ENTERING TRADE
        //PrintDebug("[ENTERING] " + reasonMsg + " | " + tradeDetails);
        
        // Ensure ID and Magic exist before logging ENTRY
        if (detectedTrade.id == "") {
            detectedTrade.id = GenerateTradeID(detectedTrade.type);
        }
        long preEntryMagic = GetTradeMagic(detectedTrade.id);
        detectedTrade.magicNumber = preEntryMagic;
        
        // Process the entry FIRST, then notify only on success
        bool entrySuccess = ProcessNewEntry(detectedTrade);
        
        if (entrySuccess) {
            // Send entry alert ONLY after confirmed execution
            string entrySubject = EMAIL_SUBJECT_PREFIX + " - Trade Entry (" + detectedTrade.type + ")";
            string entryMsg = "ENTERING: " + reasonMsg + " | " + tradeDetails;
            SendAlertForTrade(entrySubject, entryMsg, detectedTrade, AlertTypeToString(ALERT_ENTRY), reasonMsg);
            lastEntryTime = TimeCurrent();
        } else {
            // Notify Discord/Telegram that the order FAILED
            string failSubject = EMAIL_SUBJECT_PREFIX + " - Trade FAILED (" + detectedTrade.type + ")";
            string failMsg = "FAILED: Order rejected by broker | " + tradeDetails;
            SendAlertForTrade(failSubject, failMsg, detectedTrade, AlertTypeToString(ALERT_SKIP), "Order rejected by broker");
            Print("[ORDER FAILED] ", detectedTrade.type, " - broker rejected order. Discord notified.");
        }
        //PrintDebug("[SUCCESS] Entry " + detectedTrade.type + " created successfully at " + TimeToString(lastEntryTime));
        
    } else {
        // SKIPPING TRADE - but track it virtually to log outcomes
        //PrintDebug("[SKIPPING] " + reasonMsg + " | " + tradeDetails);
        
        // Generate ID and magic number ONCE for this skipped trade
        if (detectedTrade.id == "") {
            detectedTrade.id = GenerateTradeID(detectedTrade.type);
        }
        
        // Calculate magic number from the generated ID
        long tradeMagic = GetTradeMagic(detectedTrade.id);
        detectedTrade.magicNumber = tradeMagic;
        
        if(showDebug) {
            Print("SKIPPED trade ID: ", detectedTrade.id, " Magic: ", tradeMagic);
        }
        
        // Send skip alert with CSV and Telegram
        string skipSubject = EMAIL_SUBJECT_PREFIX + " - Trade Skipped (" + detectedTrade.type + ")";
        string skipMsg = "SKIPPED: " + reasonMsg + " | " + tradeDetails;
        SendAlertForTrade(skipSubject, skipMsg, detectedTrade, AlertTypeToString(ALERT_SKIP), reasonMsg);
        
        // Add to trades array for virtual tracking ONLY during backtesting (no broker interaction)
        // In live trading, we don't need to track skipped trades to avoid memory bloat
        if (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
            detectedTrade.status = "SKIPPED_" + (StringFind(detectedTrade.type, "L-") == 0 ? "BUY" : "SELL");
            detectedTrade.positionTicket = 0;  // No broker position
            detectedTrade.bestPrice = detectedTrade.entryPrice;
            detectedTrade.bestQualityScore = 0;  // Skipped trades don't need score tracking
            detectedTrade.qualityDropCount = 0;
            detectedTrade.sidewayDriftCount = 0;
            detectedTrade.lastSidewayScore = 0;
            detectedTrade.lastPriceToSL = 0;
            detectedTrade.insideCloudCount = 0;
            detectedTrade.entryBar = currentBar;
            detectedTrade.tpExtensions = 0;  // Initialize to prevent 65536 garbage value
            detectedTrade.hasTakenPartialProfit = false;
            detectedTrade.ladderStageReached = 0;  // Phase 2: No ladder stage reached yet
            detectedTrade.lastLadderUpdate = 0;
            detectedTrade.pnL = 0;  // Initialize P&L for skipped trades
            detectedTrade.earlyExitAlertSent = false;
            
            int newSize = ArraySize(trades) + 1;
            ArrayResize(trades, newSize);
            ArrayResize(tradeExtras, newSize);
            trades[newSize - 1] = detectedTrade;
            tradeExtras[newSize - 1].entryTime = TimeCurrent();
            
            if(showDebug) Print("SKIPPED trade added to virtual tracking: ", detectedTrade.id, " Magic: ", detectedTrade.magicNumber, " (will track virtual TP/SL)");
        }
    }
}

// Update cached indicators for current tick
void UpdateIndicatorCache() {
    currentBar = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
    if (lastCachedBar == currentBar && cache.valid) {
        return; // Already cached for this bar
    }
    
    // Cache price data
    cache.currentPrice = iClose(_Symbol, TF_ARRAY[TF0], 0);
    cache.prevPrice = iClose(_Symbol, TF_ARRAY[TF0], 1);
    cache.high = iHigh(_Symbol, TF_ARRAY[TF0], 0);
    cache.low = iLow(_Symbol, TF_ARRAY[TF0], 0);
    
    // Cache ADX(14) values for all timeframes at once
    // ENTRY_SHIFT applied to DI+/DI- to match getADXValue and avoid forming-bar reads
    // (HTFs at shift=1 = latest closed HTF bar, stable across the HTF window)
    for (int i = 0; i < NUM_TF; i++) {
        cache.adx[i] = getADXValue(TF_ARRAY[i], ENTRY_SHIFT);
        cache.diPlus[i] = getDIPlus(TF_ARRAY[i], ENTRY_SHIFT);
        cache.diMinus[i] = getDIMinus(TF_ARRAY[i], ENTRY_SHIFT);
    }
    
    // Cache ADX(9) values for micro-trend detection (M1 only)
    cache.adxShort = getADXValueByPeriod(TF_ARRAY[TF0], 9, ENTRY_SHIFT);
    cache.diPlusShort = getDIPlusByPeriod(TF_ARRAY[TF0], 9, ENTRY_SHIFT);
    cache.diMinusShort = getDIMinusByPeriod(TF_ARRAY[TF0], 9, ENTRY_SHIFT);
    
    // Cache momentum results
    cache.hasSufficientBullMomentum = CalculateMomentum(TREND_BULL);
    cache.hasSufficientBearMomentum = CalculateMomentum(TREND_BEAR);
    
    // Cache trend weakening detection (for Early Exit, Partial TP, TP Extension)
    // Uses M3 historical data already cached for E3 exhaustion
    cache.isTrendWeakeningBull = CalculateTrendWeakening(TREND_BULL);
    cache.isTrendWeakeningBear = CalculateTrendWeakening(TREND_BEAR);
    
    // Cache super trend states
    cache.superTrendE1 = CalculateSuperTrendForEntry("E1");
    cache.superTrendE2 = CalculateSuperTrendForEntry("E2");
    
    // Cache ATR M1 for E3 SL calculation (uses existing g_atrM1Handle)
    double atrBuffer[1];
    if (g_atrM1Handle != INVALID_HANDLE && CopyBuffer(g_atrM1Handle, 0, 0, 1, atrBuffer) > 0) {
        cache.atrM1 = atrBuffer[0];
    } else {
        cache.atrM1 = 0;
    }
    
    // Cache ATR M3 (E4 cloud thickness + E5 multi-TF sideway)
    if (g_atrM3Handle != INVALID_HANDLE && CopyBuffer(g_atrM3Handle, 0, 0, 1, atrBuffer) > 0) {
        cache.atrM3 = atrBuffer[0];
    } else {
        cache.atrM3 = 0;
    }

    // Cache ATR M5 for E5 multi-TF sideway scoring
    if (g_atrM5Handle != INVALID_HANDLE && CopyBuffer(g_atrM5Handle, 0, 0, 1, atrBuffer) > 0) {
        cache.atrM5 = atrBuffer[0];
    } else {
        cache.atrM5 = 0;
    }
    
    // Cache Ichimoku Cloud values (only if ANY entry type uses it)
    if (USE_ICHIMOKU_E1 || USE_ICHIMOKU_E2 || ENABLE_E4_ENTRIES) {
        double tempBuffer[];  // Dynamic array (required for ArraySetAsSeries)
        ArrayResize(tempBuffer, 1);
        ArraySetAsSeries(tempBuffer, true);
        
        // M1 Current cloud
        if (CopyBuffer(ichimokuHandles[0], 0, ENTRY_SHIFT, 1, tempBuffer) > 0)
            cache.ichimokuSpanA_M1_Current = tempBuffer[0];
        if (CopyBuffer(ichimokuHandles[0], 1, ENTRY_SHIFT, 1, tempBuffer) > 0)
            cache.ichimokuSpanB_M1_Current = tempBuffer[0];
        
        // M1 Future cloud (26 periods ahead)
        if (CopyBuffer(ichimokuHandles[0], 0, -26, 1, tempBuffer) > 0)
            cache.ichimokuSpanA_M1_Future = tempBuffer[0];
        if (CopyBuffer(ichimokuHandles[0], 1, -26, 1, tempBuffer) > 0)
            cache.ichimokuSpanB_M1_Future = tempBuffer[0];
        
        // M3 Current cloud (Pine parity - E4 uses current cloud, not future)
        if (CopyBuffer(ichimokuHandles[1], 0, ENTRY_SHIFT, 1, tempBuffer) > 0)
            cache.ichimokuSpanA_M3_Current = tempBuffer[0];
        if (CopyBuffer(ichimokuHandles[1], 1, ENTRY_SHIFT, 1, tempBuffer) > 0)
            cache.ichimokuSpanB_M3_Current = tempBuffer[0];
        
        // M3 Future cloud (26 periods ahead - used for trend quality scoring)
        if (CopyBuffer(ichimokuHandles[1], 0, -26, 1, tempBuffer) > 0)
            cache.ichimokuSpanA_M3_Future = tempBuffer[0];
        if (CopyBuffer(ichimokuHandles[1], 1, -26, 1, tempBuffer) > 0)
            cache.ichimokuSpanB_M3_Future = tempBuffer[0];
        
        // E4 quality filters: Cache Tenkan/Kijun/Chikou (M3 only)
        if (ENABLE_E4_ENTRIES) {
            // Tenkan-sen (conversion line, buffer 2)
            if (CopyBuffer(ichimokuHandles[1], 2, ENTRY_SHIFT, 1, tempBuffer) > 0)
                cache.ichimokuTenkan_M3 = tempBuffer[0];
            // Kijun-sen (base line, buffer 3)
            if (CopyBuffer(ichimokuHandles[1], 3, ENTRY_SHIFT, 1, tempBuffer) > 0)
                cache.ichimokuKijun_M3 = tempBuffer[0];
            // Chikou Span (lagging span, buffer 4)
            if (CopyBuffer(ichimokuHandles[1], 4, ENTRY_SHIFT, 1, tempBuffer) > 0)
                cache.ichimokuChikou_M3 = tempBuffer[0];
            // M3 price 26 bars ago (for Chikou clearance check)
            cache.priceM3_26BarsAgo = iClose(_Symbol, TF_ARRAY[TF1], ENTRY_SHIFT + 26);
        }
    }
    
    // Cache M3 historical data for E3 exhaustion (once per M3 bar only)
    int currentM3Bar = currentBar / 3;
    if (ENABLE_E3_ENTRIES && currentM3Bar != lastCachedM3Bar) {
        cache.m3HistoryValid = false;
        
        // Ensure RSI M3 handle exists (index 1 = M3, period 14)
        if (rsiHandlesTF[1] == INVALID_HANDLE || rsiHandlePeriodTF[1] != 14) {
            if (rsiHandlesTF[1] != INVALID_HANDLE) IndicatorRelease(rsiHandlesTF[1]);
            rsiHandlesTF[1] = iRSI(_Symbol, TF_ARRAY[TF1], 14, PRICE_CLOSE);
            rsiHandlePeriodTF[1] = 14;
        }
        
        // Get RSI M3 history (use dynamic arrays for ArraySetAsSeries)
        double rsiBuffer[];
        ArrayResize(rsiBuffer, 6);
        ArraySetAsSeries(rsiBuffer, true);
        if (rsiHandlesTF[1] != INVALID_HANDLE && CopyBuffer(rsiHandlesTF[1], 0, 0, 6, rsiBuffer) == 6) {
            for (int i = 0; i < 6; i++) cache.rsiM3[i] = rsiBuffer[i];
            
            // Get ADX M3 history (adxHandles[1] = M3)
            double adxBuffer[], diPlusBuffer[], diMinusBuffer[];
            ArrayResize(adxBuffer, 6);
            ArrayResize(diPlusBuffer, 6);
            ArrayResize(diMinusBuffer, 6);
            ArraySetAsSeries(adxBuffer, true);
            ArraySetAsSeries(diPlusBuffer, true);
            ArraySetAsSeries(diMinusBuffer, true);
            
            if (adxHandles[1] != INVALID_HANDLE &&
                CopyBuffer(adxHandles[1], 0, 0, 6, adxBuffer) == 6 &&
                CopyBuffer(adxHandles[1], 1, 0, 6, diPlusBuffer) == 6 &&
                CopyBuffer(adxHandles[1], 2, 0, 6, diMinusBuffer) == 6) {
                for (int i = 0; i < 6; i++) {
                    cache.adxM3[i] = adxBuffer[i];
                    cache.diPlusM3[i] = diPlusBuffer[i];
                    cache.diMinusM3[i] = diMinusBuffer[i];
                }
                cache.m3HistoryValid = true;
            }
        }
        lastCachedM3Bar = currentM3Bar;
    }
    
    // Track spread for consecutive bar check (avoids blocking on single-tick spikes)
    if (MAX_SPREAD_PIPS > 0) {
        int spreadPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        lastSpreadPips = spreadPoints * _Point / pipSize;
        
        if (lastSpreadPips > MAX_SPREAD_PIPS) {
            highSpreadBarCount++;
        } else {
            highSpreadBarCount = 0;  // Reset on normal spread
        }
    }
    
    // Cache ATR percentile (expensive CopyBuffer call, do once per bar)
    // P2/P3: Always calculate - needed for trend quality and sideways detection
    if (cache.atrM1 > 0) {
        cachedATRPercentile = CalculateATRPercentile(cache.atrM1, ATR_PERCENTILE_LOOKBACK);
    }
    
    // Update sideways score cache (Pine Script parity: multi-factor 0-100 scale)
    UpdateSidewaysScoreCache();
    
    cache.valid = true;
    lastCachedBar = currentBar;
}

// Function to cleanup old trades to manage memory
void CleanupOldTrades()
{
    // PERFORMANCE: Use lower threshold during backtesting (100 vs 500)
    int threshold = (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) ? 100 : MAX_TRADES_IN_MEMORY;
    int currentSize = ArraySize(trades);
    
    if(currentSize > threshold)
    {
        int removeCount = currentSize - threshold;  // Remove down to threshold
        
        // Shift trades array to remove oldest trades
        for(int i = 0; i < currentSize - removeCount; i++)
        {
            trades[i] = trades[i + removeCount];
            tradeExtras[i] = tradeExtras[i + removeCount];
        }
        
        // Resize trades array
        ArrayResize(trades, currentSize - removeCount);
        ArrayResize(tradeExtras, currentSize - removeCount);
    }
}

// ===== ExecutePartialTakeProfit moved to TradeManagement/PartialTP.mqh =====

// ===== Risk Management Functions moved to Utils/RiskManager.mqh =====
// - UpdateLosingStreak()
// - IsBlockedByLosingStreak()
// - IsEntryTypeBlocked()

bool ProcessNewEntry(Trade &detectedTrade) {
    bool isL = detectedTrade.isLong;  // PERFORMANCE: Use boolean instead of StringFind

    // CRITICAL: Pre-execution SL/TP validation - NEVER trade without valid SL/TP
    if (detectedTrade.stopLoss <= 0 || detectedTrade.takeProfit <= 0) {
        Print("ERROR: Invalid SL/TP values - SL=", detectedTrade.stopLoss, " TP=", detectedTrade.takeProfit, " - ENTRY BLOCKED: ", detectedTrade.type);
        return false;
    }
    
    // Validate SL/TP direction for long/short positions
    if (isL && (detectedTrade.stopLoss >= detectedTrade.entryPrice || detectedTrade.takeProfit <= detectedTrade.entryPrice)) {
        Print("ERROR: Invalid LONG SL/TP direction - Entry=", detectedTrade.entryPrice, " SL=", detectedTrade.stopLoss, " TP=", detectedTrade.takeProfit, " - ENTRY BLOCKED: ", detectedTrade.type);
        return false;
    }
    if (!isL && (detectedTrade.stopLoss <= detectedTrade.entryPrice || detectedTrade.takeProfit >= detectedTrade.entryPrice)) {
        Print("ERROR: Invalid SHORT SL/TP direction - Entry=", detectedTrade.entryPrice, " SL=", detectedTrade.stopLoss, " TP=", detectedTrade.takeProfit, " - ENTRY BLOCKED: ", detectedTrade.type);
        return false;
    }

    // Super trend veto
    TREND_STATE st = GetSuperTrendState(detectedTrade.type);
    if( (isL && st == TREND_BEAR && HasBearishMomentum()) || (!isL && st == TREND_BULL && HasBullishMomentum()) ) {
        if(showDebug) Print("ENTRY BLOCKED by super trend: ", detectedTrade.type);
        return false; // Abort entry
    }
    
    // Use existing trade ID if already set (e.g., pre-generated for logging), otherwise generate
    string tradeID = (detectedTrade.id != "") ? detectedTrade.id : GenerateTradeID(detectedTrade.type);
    detectedTrade.id = tradeID;  // Ensure struct carries the same ID
    string tradeComment = "KenKemST " + tradeID;
    
    // Normalize lot size and validate SL/TP distances
    detectedTrade.lotSize = NormalizeLotSize(detectedTrade.lotSize);
    NormalizePriceToTickSize(detectedTrade.entryPrice);
    NormalizePriceToTickSize(detectedTrade.stopLoss);
    NormalizePriceToTickSize(detectedTrade.takeProfit);
    ValidateSLTPDistances(detectedTrade.entryPrice, detectedTrade.stopLoss, detectedTrade.takeProfit, isL);
    //detectedTrade.rewardRatio = MathAbs(detectedTrade.takeProfit - detectedTrade.entryPrice) / MathAbs(detectedTrade.stopLoss - detectedTrade.entryPrice);
    
    // Final validation after normalization
    if (detectedTrade.stopLoss <= 0 || detectedTrade.takeProfit <= 0) {
        Print("ERROR: SL/TP became invalid after normalization - SL=", detectedTrade.stopLoss, " TP=", detectedTrade.takeProfit, " - ENTRY BLOCKED: ", detectedTrade.type);
        return false;
    }

    // Set unique magic number for this trade
    long tradeMagic = GetTradeMagic(tradeID);
    detectedTrade.magicNumber = tradeMagic;  // Store in struct for CSV logging
    trade.SetExpertMagicNumber(tradeMagic);
    
    PrintDebug("Setting magic number " + IntegerToString(tradeMagic) + " for trade: " + tradeID);
    
    // Pre-check: sufficient free margin before sending order (prevents [No money] broker errors)
    double requiredMargin = 0;
    double openPrice = isL ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(OrderCalcMargin(isL ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, detectedTrade.lotSize, openPrice, requiredMargin)) {
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        if(freeMargin < requiredMargin) {
            Print("[ENTRY BLOCKED] Insufficient free margin: required=", DoubleToString(requiredMargin, 2),
                  " available=", DoubleToString(freeMargin, 2),
                  " lot=", detectedTrade.lotSize, " ", detectedTrade.type);
            return false;
        }
    }

    // Limit order execution (when enabled for this entry type)
    if (ENABLE_LIMIT_ORDERS && IsLimitEnabledForEntry(GetEntryNumber(detectedTrade.entryType))) {
        if (CountActivePendingOrders() >= LIMIT_MAX_PENDING) {
            PrintDebug("[LIMIT] Soft cap reached (" + IntegerToString(LIMIT_MAX_PENDING) + " pending). Using market execution.");
        } else {
            return PlaceLimitOrder(detectedTrade, tradeComment);
        }
    }

    // Execute trade with unique comment (standard market execution)
    bool tradeExecuted;
    if(isL)
        tradeExecuted = trade.Buy(detectedTrade.lotSize, _Symbol, 0, detectedTrade.stopLoss, detectedTrade.takeProfit, tradeComment);
    else
        tradeExecuted = trade.Sell(detectedTrade.lotSize, _Symbol, 0, detectedTrade.stopLoss, detectedTrade.takeProfit, tradeComment);
    
    if(!tradeExecuted) {
        Print("[ORDER FAILED] ", detectedTrade.type, " - OrderSend failed. RetCode: ", trade.ResultRetcode(), " Desc: ", trade.ResultRetcodeDescription());
        return false;
    }
    
    {
        // CRITICAL: Immediately set SL/TP after trade execution
        // This handles brokers with Market Execution mode where SL/TP can't be set in the initial order
        ulong newTicket = trade.ResultOrder();
        bool sltpSet = false;
        if (newTicket > 0) {
            // Find and modify the position
            for (int attempts = 0; attempts < TRADE_SLTP_MAX_RETRIES; attempts++) {
                Sleep(TRADE_SLTP_RETRY_DELAY_MS);
                if (PositionSelectByTicket(newTicket)) {
                    // Get the actual position ticket (might be different from order ticket)
                    ulong posTicket = PositionGetInteger(POSITION_TICKET);
                    double executionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                    if (executionPrice > 0) {
                        detectedTrade.entryPrice = executionPrice;
                        detectedTrade.bestPrice = executionPrice;
                        detectedTrade.bufferedSLDistancePips = MathAbs(detectedTrade.entryPrice - detectedTrade.stopLoss) / pipSize;
                    }

                    double currentTP = PositionGetDouble(POSITION_TP);
                    double currentSL = PositionGetDouble(POSITION_SL);
                    
                    // Only modify if there's a meaningful change (more than 1 pip)
                    if(MathAbs(currentTP - detectedTrade.takeProfit) > _Point || MathAbs(currentSL - detectedTrade.stopLoss) > _Point) {
                        sltpSet = trade.PositionModify(posTicket, detectedTrade.stopLoss, detectedTrade.takeProfit);
                        uint resultCode = trade.ResultRetcode();
                        
                        // Check for successful result codes
                        if (sltpSet || resultCode == TRADE_RETCODE_DONE || resultCode == TRADE_RETCODE_PLACED) {
                            PrintDebug("SL/TP SET SUCCESSFULLY for " + detectedTrade.type + " (Ticket: " + IntegerToString(posTicket) + "): SL=" + DoubleToString(detectedTrade.stopLoss, 5) + ", TP=" + DoubleToString(detectedTrade.takeProfit, 5) + " (Code: " + IntegerToString(resultCode) + ")");
                            // Store the position ticket for fast future referencing
                            detectedTrade.positionTicket = posTicket;
                            sltpSet = true; // Ensure flag is set for successful codes
                            break; // Success, exit retry loop
                        } else {
                            Print("WARNING: Failed to set SL/TP for ", detectedTrade.type, " (Attempt ", attempts+1, "/5) - Error: ", resultCode);
                        }
                    } else {
                        // Store the position ticket even when no SL/TP change is needed
                        detectedTrade.positionTicket = posTicket;
                        sltpSet = true; // No change needed, consider it successful
                        break;
                    }
                } else {
                    Print("WARNING: Position not found for SL/TP setting (Attempt ", attempts+1, "/3)");
                }
            }
            if (!sltpSet) { // Failed to set SL/TP, too dangerous to continue => Close the position
                Print("CRITICAL ERROR: Failed to set SL/TP for ", tradeComment, " after 5 attempts - Error: ", trade.ResultRetcode());
                Print("EMERGENCY CLOSE: Closing position immediately to prevent unlimited risk");
                if (!trade.PositionClose(newTicket)) {
                    Print("CRITICAL: Failed to close position without SL/TP - Manual intervention required!");
                    // Send alert if email is enabled
                    if (ENABLE_EMAIL_ALERTS) {
                        SendMail(EMAIL_SUBJECT_PREFIX + " CRITICAL ALERT", 
                                "Position opened without SL/TP and failed to close automatically. Manual intervention required for ticket: " + IntegerToString(newTicket));
                    }
                }
                return false;
            }
        }
        
        // Initialize new Trade struct fields
        detectedTrade.originalTP = detectedTrade.takeProfit;
        detectedTrade.hasTakenPartialProfit = false;
        detectedTrade.ladderStageReached = 0;  // Phase 2: No ladder stage reached yet
        detectedTrade.lastLadderUpdate = 0;
        detectedTrade.tpExtensions = 0;
        detectedTrade.earlyExitAlertSent = false;
        
        // Add to trades array
        int newSize = ArraySize(trades) + 1;
        ArrayResize(trades, newSize);
        ArrayResize(tradeExtras, newSize);
        
        int lastIndex = newSize - 1;
        trades[lastIndex] = detectedTrade;
        tradeExtras[lastIndex].entryTime = TimeCurrent();
        
        // Update performance statistics for new entry (ONLY for actually executed trades with valid positionTicket)
        if (detectedTrade.positionTicket > 0) {
            UpdatePerformanceOnEntry(detectedTrade);
        } else {
            Print("WARNING: Trade executed but no valid position ticket - NOT counting in performance stats: ", detectedTrade.id);
        }
        
        // Generate alert message for logging (matching Pine Script format) with symbol prefix
        alertMessage = StringFormat("%s | %s at %.2f, SL: %.2f, TP: %.2f, Lot: %.2f", 
                                   _Symbol, detectedTrade.id, detectedTrade.entryPrice, detectedTrade.stopLoss, detectedTrade.takeProfit, detectedTrade.lotSize);
        Print("ALERT: ", alertMessage);  // Log to journal for consistency with historical behavior
        
        // Cleanup old trades if needed
        CleanupOldTrades();
    }
    return true;
}


//--------------------------------------------------------------------
// LIMIT ORDER EXECUTION: Helper functions
//--------------------------------------------------------------------
bool IsLimitEnabledForEntry(int n) {
    switch(n) { case 1: return LIMIT_USE_E1; case 2: return LIMIT_USE_E2;
                case 3: return LIMIT_USE_E3; case 4: return LIMIT_USE_E4;
                case 5: return LIMIT_USE_E5; default: return false; }
}
double GetLimitATROffset(int n) {
    switch(n) { case 1: return LIMIT_ATR_OFFSET_E1; case 2: return LIMIT_ATR_OFFSET_E2;
                case 3: return LIMIT_ATR_OFFSET_E3; case 4: return LIMIT_ATR_OFFSET_E4;
                case 5: return LIMIT_ATR_OFFSET_E5; default: return 0.15; }
}
int GetLimitExpiryBars(int n) {
    switch(n) { case 1: return LIMIT_EXPIRY_BARS_E1; case 2: return LIMIT_EXPIRY_BARS_E2;
                case 3: return LIMIT_EXPIRY_BARS_E3; case 4: return LIMIT_EXPIRY_BARS_E4;
                case 5: return LIMIT_EXPIRY_BARS_E5; default: return 3; }
}

int CountActivePendingOrders() {
    int count = 0;
    for (int j = 0; j < ArraySize(pendingOrders); j++)
        if (pendingOrders[j].isActive) count++;
    return count;
}

bool PlaceLimitOrder(Trade &detectedTrade, string tradeComment) {
    bool isL = detectedTrade.isLong;
    int entryNum = GetEntryNumber(detectedTrade.entryType);

    // Calculate limit offset from ATR, capped by SL ratio
    double atrValue = cache.atrM1;
    if (atrValue <= 0) atrValue = 0.50;  // Fallback ~50 pips
    double rawOffset = atrValue * GetLimitATROffset(entryNum);
    double slDistance = MathAbs(detectedTrade.entryPrice - detectedTrade.stopLoss);
    double maxOffset = slDistance * LIMIT_MAX_OFFSET_SL_RATIO;
    double offset = MathMin(rawOffset, maxOffset);
    if (offset < _Point) offset = _Point;  // Minimum 1 point

    // Calculate limit price
    double limitPrice;
    double minStopLevel = MathMax(
        (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point,
        (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point);
    if (minStopLevel <= 0) minStopLevel = 10 * _Point;

    if (isL) {
        limitPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - offset;
        limitPrice = MathMax(limitPrice, detectedTrade.stopLoss + minStopLevel);
        limitPrice = MathMin(limitPrice, SymbolInfoDouble(_Symbol, SYMBOL_ASK) - _Point);
    } else {
        limitPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID) + offset;
        limitPrice = MathMin(limitPrice, detectedTrade.stopLoss - minStopLevel);
        limitPrice = MathMax(limitPrice, SymbolInfoDouble(_Symbol, SYMBOL_BID) + _Point);
    }
    NormalizePriceToTickSize(limitPrice);

    // Place pending limit order
    bool placed;
    if (isL)
        placed = trade.BuyLimit(detectedTrade.lotSize, limitPrice, _Symbol,
                    detectedTrade.stopLoss, detectedTrade.takeProfit, ORDER_TIME_GTC, 0, tradeComment);
    else
        placed = trade.SellLimit(detectedTrade.lotSize, limitPrice, _Symbol,
                    detectedTrade.stopLoss, detectedTrade.takeProfit, ORDER_TIME_GTC, 0, tradeComment);

    if (!placed) {
        Print("[LIMIT FAILED] ", detectedTrade.type, " at ", DoubleToString(limitPrice, 5),
              " - RetCode: ", trade.ResultRetcode(), " Desc: ", trade.ResultRetcodeDescription());
        return false;
    }

    // Store in pendingOrders array
    int sz = ArraySize(pendingOrders);
    ArrayResize(pendingOrders, sz + 1);
    pendingOrders[sz].orderTicket = trade.ResultOrder();
    pendingOrders[sz].tradeType = detectedTrade.type;
    pendingOrders[sz].entryType = detectedTrade.entryType;
    pendingOrders[sz].isLong = isL;
    pendingOrders[sz].limitPrice = limitPrice;
    pendingOrders[sz].stopLoss = detectedTrade.stopLoss;
    pendingOrders[sz].takeProfit = detectedTrade.takeProfit;
    pendingOrders[sz].lotSize = detectedTrade.lotSize;
    pendingOrders[sz].rawSLDistancePips = detectedTrade.rawSLDistancePips;
    pendingOrders[sz].bufferedSLDistancePips = MathAbs(limitPrice - detectedTrade.stopLoss) / pipSize;
    pendingOrders[sz].magicNumber = detectedTrade.magicNumber;
    pendingOrders[sz].id = detectedTrade.id;
    pendingOrders[sz].signalBar = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
    pendingOrders[sz].expiryBars = GetLimitExpiryBars(entryNum);
    pendingOrders[sz].isHighRiskTrade = detectedTrade.isHighRiskTrade;
    pendingOrders[sz].isActive = true;

    double offsetPips = offset / pipSize;
    Print("[LIMIT PLACED] ", detectedTrade.type, " | limit=", DoubleToString(limitPrice, 5),
          " offset=", DoubleToString(offsetPips, 1), " pips | expiry=", pendingOrders[sz].expiryBars, " bars",
          " | ticket=", pendingOrders[sz].orderTicket);
    return true;
}

void ManagePendingOrders() {
    int pendingBar = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
    bool needsRiskRecheck = false;

    for (int j = ArraySize(pendingOrders) - 1; j >= 0; j--) {
        if (!pendingOrders[j].isActive) continue;

        ulong ticket = pendingOrders[j].orderTicket;

        // 1. CHECK IF FILLED: order no longer exists as pending
        if (!OrderSelect(ticket)) {
            // Order gone — check if it became a position
            if (PositionSelectByTicket(ticket)) {
                OnLimitOrderFilled(j);
                needsRiskRecheck = true;
            } else {
                // Order was deleted externally or rejected
                PrintDebug("[LIMIT REMOVED] " + pendingOrders[j].tradeType + " ticket " + IntegerToString(ticket) + " no longer exists");
            }
            pendingOrders[j].isActive = false;
            continue;
        }

        // 2. CHECK EXPIRATION
        int barsSinceSignal = pendingBar - pendingOrders[j].signalBar;
        if (barsSinceSignal >= pendingOrders[j].expiryBars) {
            trade.OrderDelete(ticket);
            Print("[LIMIT EXPIRED] ", pendingOrders[j].tradeType, " | ticket=", ticket,
                  " after ", barsSinceSignal, " bars");
            pendingOrders[j].isActive = false;
            continue;
        }

        // 3. CHECK INVALIDATION: session ended, drawdown block, or opposing position
        bool invalid = false;
        if (!IsNowInValidSession() && !IGNORE_VALID_SESSIONS) invalid = true;
        if (IsDrawdownBlocked()) invalid = true;
        if (HasOpposingDirectionPosition(pendingOrders[j].isLong)) invalid = true;

        if (invalid) {
            trade.OrderDelete(ticket);
            PrintDebug("[LIMIT CANCELLED] " + pendingOrders[j].tradeType + " - conditions invalidated");
            pendingOrders[j].isActive = false;
            continue;
        }
    }

    // After fills, if aggregate risk now exceeds budget, cancel remaining pending orders
    if (needsRiskRecheck) {
        double riskExposure = CalculateTotalRiskExposure();
        if (riskExposure >= MAX_AGGREGATE_RISK_RATIO) {
            for (int j = ArraySize(pendingOrders) - 1; j >= 0; j--) {
                if (!pendingOrders[j].isActive) continue;
                trade.OrderDelete(pendingOrders[j].orderTicket);
                Print("[LIMIT CANCELLED] ", pendingOrders[j].tradeType,
                      " - aggregate risk ", DoubleToString(riskExposure * 100, 1), "% exceeds budget");
                pendingOrders[j].isActive = false;
            }
        }
    }

    // Cleanup: remove inactive entries to prevent array growth
    for (int j = ArraySize(pendingOrders) - 1; j >= 0; j--) {
        if (!pendingOrders[j].isActive) {
            ArrayRemove(pendingOrders, j, 1);
        }
    }
}

void OnLimitOrderFilled(int j) {
    ulong ticket = pendingOrders[j].orderTicket;
    if (!PositionSelectByTicket(ticket)) {
        Print("[LIMIT FILL ERROR] Cannot select position for ticket ", ticket);
        return;
    }

    double executionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    ulong posTicket = (ulong)PositionGetInteger(POSITION_TICKET);

    // Build Trade struct from pending order data
    Trade filledTrade;
    filledTrade.type = pendingOrders[j].tradeType;
    filledTrade.entryType = pendingOrders[j].entryType;
    filledTrade.isLong = pendingOrders[j].isLong;
    filledTrade.entryPrice = executionPrice;
    filledTrade.stopLoss = pendingOrders[j].stopLoss;
    filledTrade.takeProfit = pendingOrders[j].takeProfit;
    filledTrade.originalTP = pendingOrders[j].takeProfit;
    filledTrade.lotSize = pendingOrders[j].lotSize;
    filledTrade.rawSLDistancePips = pendingOrders[j].rawSLDistancePips;
    filledTrade.bufferedSLDistancePips = MathAbs(executionPrice - pendingOrders[j].stopLoss) / pipSize;
    filledTrade.magicNumber = pendingOrders[j].magicNumber;
    filledTrade.id = pendingOrders[j].id;
    filledTrade.positionTicket = posTicket;
    filledTrade.bestPrice = executionPrice;
    filledTrade.isHighRiskTrade = pendingOrders[j].isHighRiskTrade;
    filledTrade.status = "OPEN";
    filledTrade.entryBar = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
    filledTrade.hasTakenPartialProfit = false;
    filledTrade.ladderStageReached = 0;
    filledTrade.lastLadderUpdate = 0;
    filledTrade.tpExtensions = 0;
    filledTrade.earlyExitAlertSent = false;

    // Verify SL/TP are set on position (broker may not accept on pending)
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    if (MathAbs(currentSL - filledTrade.stopLoss) > _Point || MathAbs(currentTP - filledTrade.takeProfit) > _Point) {
        for (int attempts = 0; attempts < TRADE_SLTP_MAX_RETRIES; attempts++) {
            Sleep(TRADE_SLTP_RETRY_DELAY_MS);
            if (trade.PositionModify(posTicket, filledTrade.stopLoss, filledTrade.takeProfit)) break;
            if (attempts >= 4) {
                Print("CRITICAL: Failed to set SL/TP on limit fill - closing position ", posTicket);
                trade.PositionClose(posTicket);
                return;
            }
        }
    }

    // Add to trades array
    int newSize = ArraySize(trades) + 1;
    ArrayResize(trades, newSize);
    ArrayResize(tradeExtras, newSize);
    int lastIndex = newSize - 1;
    trades[lastIndex] = filledTrade;
    tradeExtras[lastIndex].entryTime = TimeCurrent();

    if (filledTrade.positionTicket > 0) {
        UpdatePerformanceOnEntry(filledTrade);
    }

    double savedPips = MathAbs(pendingOrders[j].limitPrice - executionPrice) / pipSize;
    string alertMsg = StringFormat("%s | %s LIMIT FILLED at %.2f (limit was %.2f, saved %.1f pips), SL: %.2f, TP: %.2f, Lot: %.2f",
        _Symbol, filledTrade.id, executionPrice, pendingOrders[j].limitPrice, savedPips,
        filledTrade.stopLoss, filledTrade.takeProfit, filledTrade.lotSize);
    Print("ALERT: ", alertMsg);

    SendAlertForTrade(EMAIL_SUBJECT_PREFIX + " - Limit Order Filled",
        alertMsg, filledTrade, "ENTRY", alertMsg);

    CleanupOldTrades();
}

// Function removed - no longer needed since position ticket is stored directly in Trade struct

void CloseTradeByTicket(ulong positionTicket, string tradeID) {
    if(positionTicket <= 0) {
        if(showDebug) Print("CloseTradeByTicket ERROR: Invalid ticket for ", tradeID);
        return;
    }
    
    if (PositionSelectByTicket(positionTicket)) {
                // Use PositionClose instead of creating opposite positions
        if (SafePositionClose(positionTicket, "CloseTradeByTicket")) {
            //PrintDebug("Successfully closed position: " + IntegerToString(positionTicket) + " for trade " + tradeID);
                } else {
            Print("ERROR: Failed to close position ", positionTicket, " - Error: ", trade.ResultRetcode());
                }
    } else {
        if(showDebug) Print("CloseTradeByTicket ERROR: Position not found for ticket #", positionTicket);
    }
}

// ===== CalculateTrailingSLForTrade moved to TradeManagement/TrailingSL.mqh =====

// ========================================
// PHASE 2: SKIPPED TRADES (NON-CRITICAL) - run once per new bar
// Only process during backtesting/optimization
// ========================================
void ProcessSkippedTradesPhase() {
    if (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
        int barIndexNow = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
        if (lastBarProcessedSkips != barIndexNow) {
            lastBarProcessedSkips = barIndexNow;
            for (int i = ArraySize(trades) - 1; i >= 0; i--) {
                // SAFETY: Validate index at loop start
                if (i >= ArraySize(trades)) continue;
                
                if(StringFind(trades[i].status, "SKIPPED") == 0) {
                    ProcessSkippedTrade(i);
                    
                    // SAFETY: Validate index after ProcessSkippedTrade
                    if (i >= ArraySize(trades)) continue;
                    
                    // Remove if final outcome reached
                    if(trades[i].status == "SKIPPED_BUY_WON" || 
                       trades[i].status == "SKIPPED_SELL_WON" ||
                       trades[i].status == "SKIPPED_BUY_LOST" || 
                       trades[i].status == "SKIPPED_SELL_LOST" || 
                       trades[i].status == "SKIPPED_EARLY_EXIT" ||
                       trades[i].status == "SKIPPED_CLOSED") {
                        ArrayRemove(trades, i, 1);
                        ArrayRemove(tradeExtras, i, 1);
                    }
                }
            }
        }
    }
}

// Process skipped trades (virtual tracking - no broker interaction)
void ProcessSkippedTrade(int tradeIndex) {
    // PERFORMANCE: Skip processing if CSV export is disabled (no point tracking virtual trades)
    if (!ENABLE_CSV_EXPORT) {
        // Just mark as closed to remove from tracking
        trades[tradeIndex].status = "SKIPPED_CLOSED";
        return;
    }
    
    // PERFORMANCE: Timeout stale skipped trades after 500 bars (~8 hours)
    // This prevents infinite accumulation of trades that never hit TP/SL
    int barsSinceEntry = currentBar - trades[tradeIndex].entryBar;
    if (barsSinceEntry > 500) {
        trades[tradeIndex].status = "SKIPPED_CLOSED";
        return;
    }
    
    bool isLong = trades[tradeIndex].isLong;
    
    // PERFORMANCE: Minimal tracking - only check TP/SL hits, skip best price and P&L updates
    // Best price and P&L are not needed for skipped trades in CSV
    
    // Use bar high/low for accurate TP/SL detection (not just current price)
    double barHigh = iHigh(_Symbol, TF_ARRAY[TF0], 0);
    double barLow = iLow(_Symbol, TF_ARRAY[TF0], 0);
    
    // Check for TP hit
    bool tpHit = false;
    if(isLong && barHigh >= trades[tradeIndex].takeProfit) {
        tpHit = true;
    } else if(!isLong && barLow <= trades[tradeIndex].takeProfit) {
        tpHit = true;
    }
    
    // Check for SL hit
    bool slHit = false;
    if(isLong && barLow <= trades[tradeIndex].stopLoss) {
        slHit = true;
    } else if(!isLong && barHigh >= trades[tradeIndex].stopLoss) {
        slHit = true;
    }
    
    // PERFORMANCE: Skip early exit logic for skipped trades (not critical for analytics)
    bool shouldEarlyExit = false;
    
    // Handle trade closure - ONLY log final outcomes (WON/LOST)
    string closeReason = "";
    string newStatus = "";
    
    if(tpHit) {
        closeReason = "TP Hit";
        newStatus = isLong ? "SKIPPED_BUY_WON" : "SKIPPED_SELL_WON";
    } else if(slHit) {
        closeReason = "SL Hit";
        newStatus = isLong ? "SKIPPED_BUY_LOST" : "SKIPPED_SELL_LOST";
    }
    
    // PERFORMANCE: Only log final outcomes, skip intermediate events (TP extensions, trailing SL, etc.)
    if(newStatus != "") {
        // Calculate final P&L only when closing (use bar close price)
        double closePrice = iClose(_Symbol, TF_ARRAY[TF0], 0);
        if(isLong) {
            trades[tradeIndex].pnL = (closePrice - trades[tradeIndex].entryPrice) * trades[tradeIndex].lotSize * contractSize;
        } else {
            trades[tradeIndex].pnL = (trades[tradeIndex].entryPrice - closePrice) * trades[tradeIndex].lotSize * contractSize;
        }
        
        trades[tradeIndex].status = newStatus;
        
        // Log to CSV before removal (using the new status as event type)
        ExportTradeEventToCSV(trades[tradeIndex], newStatus, closeReason);
        
        if(showDebug) Print("SKIPPED trade closed: ", trades[tradeIndex].id, " Status: ", newStatus, " P&L: ", trades[tradeIndex].pnL);
    }
    
    // PERFORMANCE: Skip all intermediate tracking (TP extensions, trailing SL) for skipped trades
    // This eliminates unnecessary CSV writes and processing
    // Only track: SKIP (entry) -> SKIPPED_WON or SKIPPED_LOST (final outcome)
}

// #endregion

// ================================================================
// #region 7) TRADE MANAGEMENT & POSITION MONITORING
// Process existing trades, dynamic SL/TP, early exits
// ================================================================

// Process existing trades - comprehensive trade management from Pine Script lines 563-689
// ProcessExistingTrades moved to TradeManager.mqh


// Function to check for open positions in last 10 detected positions (matching Pine Script lines 238-283)
// Overload 1: Original 6-param version for E1/E2/E3 backward compatibility
void CheckOpenPositions(int &outOpenLE1Index, int &outOpenSE1Index, int &outOpenLE2Index, int &outOpenSE2Index, int &outOpenLE3Index, int &outOpenSE3Index) {
    int dummyLE4 = -1, dummySE4 = -1, dummyLE5 = -1, dummySE5 = -1;
    CheckOpenPositionsInternal(outOpenLE1Index, outOpenSE1Index, outOpenLE2Index, outOpenSE2Index, outOpenLE3Index, outOpenSE3Index, dummyLE4, dummySE4, dummyLE5, dummySE5);
}

// Overload 2: Extended 8-param version including E4
void CheckOpenPositions(int &outOpenLE1Index, int &outOpenSE1Index, int &outOpenLE2Index, int &outOpenSE2Index, int &outOpenLE3Index, int &outOpenSE3Index, int &outOpenLE4Index, int &outOpenSE4Index) {
    int dummyLE5 = -1, dummySE5 = -1;
    CheckOpenPositionsInternal(outOpenLE1Index, outOpenSE1Index, outOpenLE2Index, outOpenSE2Index, outOpenLE3Index, outOpenSE3Index, outOpenLE4Index, outOpenSE4Index, dummyLE5, dummySE5);
}

// Overload 3: Full 10-param version including E5
void CheckOpenPositions(int &outOpenLE1Index, int &outOpenSE1Index, int &outOpenLE2Index, int &outOpenSE2Index, int &outOpenLE3Index, int &outOpenSE3Index, int &outOpenLE4Index, int &outOpenSE4Index, int &outOpenLE5Index, int &outOpenSE5Index) {
    CheckOpenPositionsInternal(outOpenLE1Index, outOpenSE1Index, outOpenLE2Index, outOpenSE2Index, outOpenLE3Index, outOpenSE3Index, outOpenLE4Index, outOpenSE4Index, outOpenLE5Index, outOpenSE5Index);
}

// Internal implementation
void CheckOpenPositionsInternal(int &outOpenLE1Index, int &outOpenSE1Index, int &outOpenLE2Index, int &outOpenSE2Index, int &outOpenLE3Index, int &outOpenSE3Index, int &outOpenLE4Index, int &outOpenSE4Index, int &outOpenLE5Index, int &outOpenSE5Index) {
    // Initialize all outputs to "not found" state (matching Pine Script na/-1 logic)
    outOpenLE1Index = -1;
    outOpenSE1Index = -1;
    outOpenLE2Index = -1;
    outOpenSE2Index = -1;
    outOpenLE3Index = -1;
    outOpenSE3Index = -1;
    outOpenLE4Index = -1;
    outOpenSE4Index = -1;
    outOpenLE5Index = -1;
    outOpenSE5Index = -1;

    int size = ArraySize(trades);
    int maxCheck = MathMin(size, 10);  // Only check up to 10 most recent trades (Pine Script line 257)

    for (int i = 0; i < maxCheck; i++) {
        int idx = size - 1 - i;  // Start from most recent trade (Pine Script line 260)
        if (idx >= 0 && size > idx) {
            string outcome = trades[idx].status;

            // Check if trade is open (Pine Script line 265: na(outcome) or outcome == "OPEN")
            if (outcome == "" || outcome == "OPEN") {
                // Use enum switch instead of 8x string comparisons - 80x faster!
                switch(trades[idx].entryType) {
                    case ENTRY_L_E1: if (outOpenLE1Index == -1) outOpenLE1Index = trades[idx].entryBar; break;
                    case ENTRY_S_E1: if (outOpenSE1Index == -1) outOpenSE1Index = trades[idx].entryBar; break;
                    case ENTRY_L_E2: if (outOpenLE2Index == -1) outOpenLE2Index = trades[idx].entryBar; break;
                    case ENTRY_S_E2: if (outOpenSE2Index == -1) outOpenSE2Index = trades[idx].entryBar; break;
                    case ENTRY_L_E3: if (outOpenLE3Index == -1) outOpenLE3Index = trades[idx].entryBar; break;
                    case ENTRY_S_E3: if (outOpenSE3Index == -1) outOpenSE3Index = trades[idx].entryBar; break;
                    case ENTRY_L_E4: if (outOpenLE4Index == -1) outOpenLE4Index = trades[idx].entryBar; break;
                    case ENTRY_S_E4: if (outOpenSE4Index == -1) outOpenSE4Index = trades[idx].entryBar; break;
                    case ENTRY_L_E5: if (outOpenLE5Index == -1) outOpenLE5Index = trades[idx].entryBar; break;
                    case ENTRY_S_E5: if (outOpenSE5Index == -1) outOpenSE5Index = trades[idx].entryBar; break;
                }
            }
        }
    }
}

// EMA visualization removed - use MT5 built-in EMA indicators instead
// Add EMA indicators manually to chart: Insert -> Indicators -> Trend -> Moving Average
// Configure each EMA with periods 25, 75, 100, 200 and colors Yellow, Green, LightGray, Purple

//+------------------------------------------------------------------+
//| Section 4: Core Entry Detection Logics - Only work on 1m time frame |
//+------------------------------------------------------------------+

// Function to determine current trading session
// Delegates to GetCurrentSession() which uses TimeGMT() for broker-agnostic JST conversion
string getCurrentTradingSession() {
    return GetCurrentSession();
}

void setMaxTPForTrade(Trade &newTrade, bool isAgressiveFlag) {
    // Determine if it's a long or short position
    bool isLong = newTrade.isLong;  // PERFORMANCE: Boolean instead of StringFind
    
    // Calculate risk distance for RR-based TP calculation
    double risk = MathAbs(newTrade.entryPrice - newTrade.stopLoss);
    
    // Determine RR ratio based on entry type and market conditions
    double rrRatio = 1.0;
    bool isInSidewayMarket = IsInSidewayRange(); // Use existing sideway detection
    bool useDetectionRR = false;
    
    // Preserve detection-provided RR for E3 (already sideway + score adjusted)
    if (IsE3Entry(newTrade.entryType) && newTrade.takeProfit > 0 && risk > 0) {
        double detectionRR = MathAbs(newTrade.takeProfit - newTrade.entryPrice) / risk;
        if (detectionRR > 0.0) {
            rrRatio = detectionRR;
            useDetectionRR = true;
        }
    }
    
    // Prefer adaptive per-entry reward ratio; fallback to static inputs if needed
    if (!useDetectionRR) {
        EntryBase* entryForRR = GetEntryForType(newTrade.entryType);
        if (entryForRR != NULL) {
            rrRatio = entryForRR.GetRewardRatio();
        } else {
            // Fallback to static inputs (legacy)
            if (IsE1Entry(newTrade.entryType)) {
                rrRatio = isInSidewayMarket ? E1_RR_SIDEWAY : E1_RR;
            } else if (IsE2Entry(newTrade.entryType)){
                rrRatio = isInSidewayMarket ? E2_RR_SIDEWAY : E2_RR;
            } else if (IsE3Entry(newTrade.entryType)) {
                rrRatio = isInSidewayMarket ? E3_RR_SIDEWAY : E3_RR;
            } else if (IsE4Entry(newTrade.entryType)) {
                rrRatio = isInSidewayMarket ? E4_RR_SIDEWAY : E4_RR;
            } else if (IsE5Entry(newTrade.entryType)) {
                rrRatio = isInSidewayMarket ? E5_RR_SIDEWAY : E5_RR;
            }
        }
    }
    
    // Apply dynamic RR scaling based on ATR percentile and session
    rrRatio *= GetDynamicRRMultiplier();
    
    // Enhanced aggressive flag logic - boost RR ratio
    double finalRR = rrRatio;
    if (isAgressiveFlag) {
        EntryBase* entryForRRBoost = GetEntryForType(newTrade.entryType);
        double boostMult = (entryForRRBoost != NULL) ? entryForRRBoost.GetRRBoostMultiplier() : 1.02;
        finalRR = rrRatio * boostMult;
    }
    
    // Clamp RR when using detection-provided RR to avoid dynamic overshoot
    if (useDetectionRR) {
        finalRR = MathMax(ADAPTIVE_RR_ABSOLUTE_MIN, MathMin(ADAPTIVE_RR_ABSOLUTE_MAX, finalRR));
    }
    
    // Calculate TP using risk-reward ratio
    newTrade.takeProfit = isLong ?
                         (newTrade.entryPrice + finalRR * risk) :
                         (newTrade.entryPrice - finalRR * risk);
}

// Initialize trade object with default values and calculated lot size
void InitializeTrade(Trade &tradeObj, double currentPrice) {
    tradeObj.type = "";
    tradeObj.entryPrice = 0.0;
    tradeObj.stopLoss = 0.0;
    tradeObj.takeProfit = 0.0;
    tradeObj.originalTP = 0.0;
    tradeObj.rawSLDistancePips = 0.0;
    tradeObj.bufferedSLDistancePips = 0.0;
    tradeObj.lastSLModificationAttempt = 0;
    tradeObj.lastTPExtensionAttempt = 0;
    tradeObj.slMovedToBreakeven = false;
    tradeObj.rMultipleBEApplied = false;
    tradeObj.partialTPEligible = false;
    tradeObj.bestPriceSinceEligible = currentPrice;
    tradeObj.slWasTrailed = false;
    tradeObj.hasTakenPartialProfit = false;
    tradeObj.tpExtensions = 0;
    tradeObj.lotSize = NormalizeLotSize(MathMin(getScaledLotSize(), GetMaxLotSize(
                                   currentPrice,
                                   accountBalance,
                                   LEVERAGE,
                                   FEE_PERCENT,
                                   MARGIN_LEVEL_PERCENT)));
}

// Set up detected trade with entry information (for E1/E2/E3 entries)
void SetupDetectedTrade(Trade &tradeObj, string tradeType, double currentPrice, int barIndex, bool useAggressiveTP = false) {
    tradeObj.type = tradeType;
    tradeObj.entryType = GetEntryTypeEnum(tradeType);  // Set enum for fast checking
    tradeObj.entryPrice = currentPrice;
    tradeObj.entryBar = barIndex;
    tradeObj.isLong = (tradeType[0] == 'L');  // PHASE 2.4: Character comparison faster than StringFind
    tradeObj.status = "OPEN";
    tradeObj.bestPrice = currentPrice;
    
    // Initialize best momentum score at entry (will be updated during trade)
    // Uses momentum score (0-5 or 0-6 for E4) for in-trade health, not entry quality score (0-13)
    TREND_STATE trendForScore = tradeObj.isLong ? TREND_BULL : TREND_BEAR;
    int entryNum = GetEntryNumber(tradeObj.entryType);
    tradeObj.bestQualityScore = GetActiveTradeMomentumScore(trendForScore, entryNum);
    tradeObj.qualityDropCount = 0;
    tradeObj.adxDropCount = 0;
    tradeObj.lastAdxValue = 0.0;
    
    // Initialize sideway early exit tracking
    tradeObj.sidewayDriftCount = 0;
    tradeObj.lastSidewayScore = 0;
    tradeObj.lastPriceToSL = 0;
    
    // Initialize Ichimoku cloud early exit tracking
    tradeObj.insideCloudCount = 0;
    
    tradeObj.id = ""; // Will be set in ProcessNewEntry
    tradeObj.hasTakenPartialProfit = false;
    tradeObj.ladderStageReached = 0;  // Phase 2: No ladder stage reached yet
    tradeObj.lastLadderUpdate = 0;
    setMaxTPForTrade(tradeObj, useAggressiveTP);
}

//+------------------------------------------------------------------+
//| Phase 2: Laddered Extension Helpers                              |
//+------------------------------------------------------------------+
void CheckAndApplyLadderStages(int tradeIndex) {
    // Only apply if partial TP was taken and ladder is enabled
    if (!trades[tradeIndex].hasTakenPartialProfit) return;
    
    EntryBase* entry = GetEntryForType(trades[tradeIndex].entryType);
    if (entry == NULL || !entry.GetEnableLadderedExtensions()) return;
    
    // NO THROTTLE for stage advancement - XAUUSD can move 50+ pips in 60 seconds
    // Must catch fast moves to advance Stage 1 → Stage 2 → Stage 3
    
    double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], 0);
    double currentPnL = trades[tradeIndex].isLong ? 
        (currentPrice - trades[tradeIndex].entryPrice) : 
        (trades[tradeIndex].entryPrice - currentPrice);
    
    double origTPDist = MathAbs(trades[tradeIndex].originalTP - trades[tradeIndex].entryPrice);
    
    // Check stages from highest to lowest (only advance, never regress)
    if (trades[tradeIndex].ladderStageReached < 3 && 
        currentPnL >= entry.GetLadderStage3Multiplier() * origTPDist) {
        ApplyLadderStage(tradeIndex, 3, entry.GetLadderStage3TrailRatio());
    }
    else if (trades[tradeIndex].ladderStageReached < 2 && 
             currentPnL >= entry.GetLadderStage2Multiplier() * origTPDist) {
        ApplyLadderStage(tradeIndex, 2, entry.GetLadderStage2TrailRatio());
    }
    else if (trades[tradeIndex].ladderStageReached < 1 && 
             currentPnL >= entry.GetLadderStage1Multiplier() * origTPDist) {
        ApplyLadderStage(tradeIndex, 1, entry.GetLadderStage1TrailRatio());
    }
}

void ApplyLadderStage(int tradeIndex, int stage, double trailRatio) {
    trades[tradeIndex].ladderStageReached = stage;
    trades[tradeIndex].lastLadderUpdate = TimeCurrent();
    
    double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], 0);
    double currentProfit = trades[tradeIndex].isLong ? 
        (currentPrice - trades[tradeIndex].entryPrice) : 
        (trades[tradeIndex].entryPrice - currentPrice);
    
    // Calculate trailing SL: currentPrice - (trailRatio * currentProfit)
    double newSL = trades[tradeIndex].isLong ? 
        currentPrice - (trailRatio * currentProfit) :
        currentPrice + (trailRatio * currentProfit);
    
    // Only move SL if it's better than current
    bool shouldMove = trades[tradeIndex].isLong ? (newSL > trades[tradeIndex].stopLoss) : (newSL < trades[tradeIndex].stopLoss);
    
    if (shouldMove) {
        NormalizePriceToTickSize(newSL);
        
        if (ModifyPositionSLTP(trades[tradeIndex], newSL, trades[tradeIndex].takeProfit, 
                               StringFormat("LADDER STAGE %d (%.0f%% trail)", stage, trailRatio * 100))) {
            // Check if SL just crossed breakeven (before updating stopLoss)
            bool wasBelowBE = trades[tradeIndex].isLong ? 
                (trades[tradeIndex].stopLoss < trades[tradeIndex].entryPrice) : 
                (trades[tradeIndex].stopLoss > trades[tradeIndex].entryPrice);
            bool nowAboveBE = trades[tradeIndex].isLong ? 
                (newSL >= trades[tradeIndex].entryPrice) : 
                (newSL <= trades[tradeIndex].entryPrice);
            bool justCrossedBE = wasBelowBE && nowAboveBE && !trades[tradeIndex].slMovedToBreakeven;
            
            trades[tradeIndex].stopLoss = newSL;
            trades[tradeIndex].slWasTrailed = true;
            
            // Mark breakeven crossed if applicable
            if (justCrossedBE) {
                trades[tradeIndex].slMovedToBreakeven = true;
            }
            
            // Send alert for ALL ladder stage advancements
            double bufferPips = MathAbs(newSL - trades[tradeIndex].entryPrice) / pipSize;
            string slPosition = (trades[tradeIndex].isLong ? (newSL >= trades[tradeIndex].entryPrice) : (newSL <= trades[tradeIndex].entryPrice)) 
                ? StringFormat("entry + %.1f pips", bufferPips) 
                : StringFormat("entry - %.1f pips", bufferPips);
            string beSubject = EMAIL_SUBJECT_PREFIX + " - SL Trailed (#" + IntegerToString(stage) + ")";
            string beReason = StringFormat("Trailing SL #%d: SL moved to %s", stage, slPosition);
            SendAlertForTrade(beSubject, beReason, trades[tradeIndex], AlertTypeToString(ALERT_SL_TO_BREAKEVEN), beReason);
            
            if(showDebug) {
                double trailPips = MathAbs(currentPrice - newSL) / pipSize;
                Print("[LADDER STAGE ", stage, "] Trade #", trades[tradeIndex].id, 
                      ": SL trailed to ", newSL, " (", DoubleToString(trailPips, 1), " pips from current)");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper: Process conviction score and handle low confidence       |
//+------------------------------------------------------------------+
void ProcessEntryConvictionAndConfidence(Trade &detectedTrade, string tradeType, double currentPrice,
                                         bool &isLowConfidenceSetup, string &lowConfidenceReason,
                                         int cachedTrendQualityScore) {
    // Set up detected trade
    bool isAgressiveFlag = false;
    if (currentSession == "US" && getADXValue(TF_ARRAY[TF1], ENTRY_SHIFT) >= 30) {
        isAgressiveFlag = true;
    }
    SetupDetectedTrade(detectedTrade, tradeType, currentPrice, currentBar, isAgressiveFlag);

    // PHASE 4: Apply entry-specific risk allocation and recalculate lot size
    ENTRY_TYPE entryTypeEnum = GetEntryTypeEnum(tradeType);
    EntryBase* entryPtr = GetEntryForType(entryTypeEnum);
    double entryRiskPercent = GetEntrySpecificRiskRatio(entryTypeEnum,
        (entryPtr != NULL) ? entryPtr.GetMaxLossRatio() : 0.0) * 100;
    
    // Use cached score from detection (avoids recalculating - 2x CPU savings)
    int detectionTrendQuality = cachedTrendQualityScore;
    detectedTrade.detectionTrendQualityScore = detectionTrendQuality;
    bool isLongForScore = (tradeType[0] == 'L');  // Still needed for E3 exhaustion score lookup
    detectedTrade.detectionExhaustionScore = 0;  // Will be set for E3 below
    detectedTrade.qualifiesForRecoveryBoost = false;
    
    // Check if this setup qualifies for recovery boost during recovery mode
    double entrySpecificMaxLoss = getMaxLossUSD(entryTypeEnum);  // Default: DD-capped risk
    if (inRecoveryMode) {
        bool qualifiesForBoost = false;
        int scoreUsed = 0;
        int boostThreshold = 0;
        bool skipDDCap = false;  // If true, always use recovery multiplier (skip DD-cap)
        
        // All entry types skip DD-cap during recovery to avoid death spiral
        // High-quality setups get full boost, normal setups get recovery multiplier
        EntryBase* entryForRecovery = GetEntryForType(entryTypeEnum);
        boostThreshold = (entryForRecovery != NULL) ? entryForRecovery.GetRecoveryBoostThreshold() : 0;

        // E3 uses cached exhaustion score; all others use trend quality
        if (IsE3Entry(entryTypeEnum)) {
            scoreUsed = entry3.GetCachedExhaustionScore(isLongForScore);
            detectedTrade.detectionExhaustionScore = scoreUsed;
        } else {
            scoreUsed = detectionTrendQuality;
        }
        qualifiesForBoost = (scoreUsed >= boostThreshold);
        skipDDCap = true;
        
        // Apply recovery risk (skip DD-cap for all entry types)
        if (qualifiesForBoost) {
            detectedTrade.qualifiesForRecoveryBoost = true;
            entrySpecificMaxLoss = GetEntryBoostedMaxLossDuringRecovery(entryTypeEnum);
            Print(StringFormat("[RECOVERY BOOST] %s (score=%d >= %d) | MaxLoss: $%.2f (%.0f%%)",
                  tradeType, scoreUsed, boostThreshold, entrySpecificMaxLoss, RECOVERY_MODE_BOOST_MULTIPLIER * 100));
        } else if (skipDDCap) {
            // Normal quality but still skip DD-cap, use recovery multiplier
            entrySpecificMaxLoss = GetEntryBaseMaxLossDuringRecovery(entryTypeEnum);
            Print(StringFormat("[RECOVERY] %s (score=%d < %d) | MaxLoss: $%.2f (%.0f%%)",
                  tradeType, scoreUsed, boostThreshold, entrySpecificMaxLoss, RECOVERY_MODE_LOT_MULTIPLIER * 100));
        }
    }
    
    // Recalculate lot size with entry-specific risk
    double pointValue = contractSize * pipSize;
    double maxLotsBasedOnRisk = entrySpecificMaxLoss / pointValue;
    double marginPerLot = contractSize * currentPrice / LEVERAGE;
    double maxUsedMargin = accountBalance / (MARGIN_LEVEL_PERCENT / 100.0);
    double maxLotsMargin = maxUsedMargin / marginPerLot;
    double adjustedLotSize = MathMin(maxLotsBasedOnRisk, maxLotsMargin);
    adjustedLotSize = MathMin(adjustedLotSize, getScaledLotSize(entryTypeEnum,
        (entryPtr != NULL) ? entryPtr.GetLotMultiplier() : -1.0,
        (entryPtr != NULL) ? entryPtr.GetVolLotAdjEnabled() : false));  // Apply profit scaling + per-entry vol adjustment
    detectedTrade.lotSize = NormalizeLotSize(adjustedLotSize);
    
    if (showDebug) {
        string boostTag = detectedTrade.qualifiesForRecoveryBoost ? " [BOOSTED]" : "";
        Print(StringFormat("[RISK] %s allocated %.2f%% risk | MaxLoss: $%.2f | Lot: %.2f%s", 
              tradeType, entryRiskPercent, entrySpecificMaxLoss, detectedTrade.lotSize, boostTag));
    }

    // PHASE 2: Conviction Score & HTF Veto (additional quality filters)
    bool isLong = (entryTypeEnum == ENTRY_L_E1 || entryTypeEnum == ENTRY_L_E2 || entryTypeEnum == ENTRY_L_E3 || entryTypeEnum == ENTRY_L_E4);
    
    // Check if conviction scoring is enabled for this entry type
    EntryBase* entryForConv = GetEntryForType(entryTypeEnum);
    bool useConviction = (entryForConv != NULL) ? entryForConv.GetUseConvictionScoring() : false;
    bool useHTFVeto = (entryForConv != NULL) ? entryForConv.GetUseHTFVeto() : false;
    
    // If entry already marked as low confidence by its internal checks (e.g., E3's DI deceleration),
    // respect that decision regardless of conviction scoring settings
    // (This preserves E3's specialized reversal filters even when conviction scoring is disabled)
    if (isLowConfidenceSetup) {
        // Already flagged as low confidence by entry's internal validation
        // lowConfidenceReason already set by entry
    }
    // Only check conviction if enabled for this entry type AND not already flagged
    else if (useConviction) {
        // Get per-entry threshold
        int convictionThreshold = (entryForConv != NULL) ? entryForConv.GetConvictionThreshold() : 5;
        
        int convictionScore = CalculateConvictionScore(isLong, entryTypeEnum, useConviction, useHTFVeto);
        if (convictionScore < convictionThreshold) {
            TrackEntryAttempt(tradeType, false, "conviction");
            isLowConfidenceSetup = true;
            lowConfidenceReason = "Low conviction score " + IntegerToString(convictionScore) + "/10 (min: " + IntegerToString(convictionThreshold) + ")";
        }
    }
    
    // HTF veto check - independent of conviction scoring
    // if (useHTFVeto && !useConviction) {
    //     // If HTF veto enabled but conviction disabled, check veto separately
    //     int htfVetoResult = CheckHTFVeto(isLong, entryTypeEnum, useHTFVeto);
    //     if (htfVetoResult == -999) {
    //         TrackEntryAttempt(tradeType, false, "htf_veto");
    //         EnterOrSkipTrade(detectedTrade, false, "Blocked by HTF Veto (against M5 trend)");
    //         detectedTrade.type = ""; // Prevent execution
    //         return; // Hard block
    //     }
    // }
    // // Note: If conviction enabled, HTF veto is already checked inside CalculateConvictionScore()

    if (isLowConfidenceSetup) {
        if (SEND_LOW_CONFIDENCE_SIGNALS) {
            // LOW CONFIDENCE: Send alert but don't execute
            EnterOrSkipTrade(detectedTrade, false, "Low confidence: " + lowConfidenceReason);
            detectedTrade.type = ""; // Prevent execution
        }
        //Print("[SILENT SKIP] type=", detectedTrade.type, " reason=", lowConfidenceReason);
        detectedTrade.type = ""; // Prevent execution here
    } else {
        // HIGH CONFIDENCE - Execute trade
        TrackEntryAttempt(tradeType, true, "");
    }
}

//+------------------------------------------------------------------+
//| Helper: Check E2 entry prerequisites and quality                 |
//+------------------------------------------------------------------+
bool CheckE2EntryConditions(bool isLong, double currentPrice, string entryType,
                            bool &isLowConfidence, string &lowConfidenceReason) {
    // Reset output parameters
    isLowConfidence = false;
    lowConfidenceReason = "";
    
    // CORE PREREQUISITES
    if (!isAllTimeframeEMAsReadyForEntry("E2", isLong, 1)) {
        TrackEntryAttempt(entryType, false, "mtf");
        return false;
    }
    
    // Price position check (opposite for long vs short)
    double ema25 = GetEMA(TF0, EMA1, ENTRY_SHIFT);
    if ((isLong && currentPrice <= ema25) || (!isLong && currentPrice >= ema25)) {
        TrackEntryAttempt(entryType, false, "mtf");
        return false;
    }
    
    // QUALITY FILTERS - Unified trend quality scoring
    TREND_STATE requiredTrend = isLong ? TREND_BULL : TREND_BEAR;
    int trendQuality = GetTrendQualityScore(requiredTrend);
    
    if (trendQuality < MIN_TREND_QUALITY_E2) {
        TrackEntryAttempt(entryType, false, "trend_quality");
        isLowConfidence = true;
        lowConfidenceReason = StringFormat("Trend quality: %d/8 (min: %d)", 
                                           trendQuality, MIN_TREND_QUALITY_E2);
    }
    
    return true; // Prerequisites met
}

bool isEMAsReadyForEntry(bool isLong, int timeFrame, int barShift, bool isStrict = true) {
    double ema25Val = GetEMA(timeFrame, EMA1, barShift);
    double ema75Val = GetEMA(timeFrame, EMA2, barShift);
    double ema100Val = GetEMA(timeFrame, EMA3, barShift);
    double ema200Val = GetEMA(timeFrame, EMA4, barShift);
    
    // Apply tolerance to all EMA pairs (allows near-alignment during trend formation)
    double tolerance = EMA_ALIGNMENT_TOLERANCE_PIPS * pipSize;
    
    // Check EMA alignment with tolerance based on direction
    if (isLong) {
        // LONG: Check each pair with tolerance
        bool ema25_above_75 = (ema25Val > ema75Val - tolerance);
        bool ema75_above_100 = (ema75Val > ema100Val - tolerance);
        bool ema100_above_200 = !isStrict || (ema100Val > ema200Val - tolerance);
        
        return ema25_above_75 && ema75_above_100 && ema100_above_200;
    } else {
        // SHORT: Check each pair with tolerance
        bool ema25_below_75 = (ema25Val < ema75Val + tolerance);
        bool ema75_below_100 = (ema75Val < ema100Val + tolerance);
        bool ema100_below_200 = !isStrict || (ema100Val < ema200Val + tolerance);
        
        return ema25_below_75 && ema75_below_100 && ema100_below_200;
    }
}

bool isAllTimeframeEMAsReadyForEntry(string type, bool isLong, int barShift) {
    ENTRY_TYPE entryType = GetEntryTypeEnum(type);  // PERFORMANCE: Convert once
    
    if (IsE1Entry(entryType)) {
        // E1: Check M1+M3+M5 alignment with MOMENTUM BYPASS support (Pine parity)
        bool m1_ready = isEMAsReadyForEntry(isLong, TF0, barShift, true);
        bool m3_ready = isEMAsReadyForEntry(isLong, TF1, barShift, true);
        
        // M5 directional check
        double ema25_m5 = emaBuffers[GetEMABufferIndex(TF2, EMA1)][barShift];
        double ema75_m5 = emaBuffers[GetEMABufferIndex(TF2, EMA2)][barShift];
        double ema100_m5 = emaBuffers[GetEMABufferIndex(TF2, EMA3)][barShift];
        double ema200_m5 = emaBuffers[GetEMABufferIndex(TF2, EMA4)][barShift];
        
        bool m5_directional;
        if (isLong) {
            m5_directional = (ema25_m5 > ema75_m5) && (ema75_m5 > ema100_m5) && (ema25_m5 > ema200_m5);
        } else {
            m5_directional = (ema25_m5 < ema75_m5) && (ema75_m5 < ema100_m5) && (ema25_m5 < ema200_m5);
        }
        
        // MOMENTUM BYPASS LOGIC (Pine parity: e1MomentumBypassLevel)
        // Check for extreme momentum using DI spread >= EXTREME_DI_SPREAD_THRESHOLD
        bool extremeMomentum = false;
        if (isLong) {
            extremeMomentum = (cache.diPlus[0] - cache.diMinus[0]) >= EXTREME_DI_SPREAD_THRESHOLD;
        } else {
            extremeMomentum = (cache.diMinus[0] - cache.diPlus[0]) >= EXTREME_DI_SPREAD_THRESHOLD;
        }
        
        bool alignedOrBypassed = false;
        if (E1_MOMENTUM_BYPASS_LEVEL == 0) {
            // Level 0: Full MTF alignment required (M1+M3+M5)
            alignedOrBypassed = m1_ready && m3_ready && m5_directional;
        } else if (E1_MOMENTUM_BYPASS_LEVEL == 1) {
            // Level 1: M1 required, bypass M3/M5 with extreme momentum
            alignedOrBypassed = m1_ready && ((m3_ready && m5_directional) || extremeMomentum);
        } else {
            // Level 2: M1 required OR extreme momentum (most aggressive)
            alignedOrBypassed = m1_ready || extremeMomentum;
        }
        
        if (showDebug && !alignedOrBypassed) {
            PrintDebug("[MTF E1] Rejected - M1:" + (m1_ready?"Y":"N") + " M3:" + (m3_ready?"Y":"N") + 
                      " M5dir:" + (m5_directional?"Y":"N") + " bypass:" + IntegerToString(E1_MOMENTUM_BYPASS_LEVEL) +
                      " extMom:" + (extremeMomentum?"Y":"N"));
        }
        
        return alignedOrBypassed;
    } else {
        // E2/E3: Require ALL 3 timeframes M1 AND M3 AND M5 (with tolerance applied)
        bool m1_ready = isEMAsReadyForEntry(isLong, TF0, barShift);
        bool m3_ready = isEMAsReadyForEntry(isLong, TF1, barShift);
        bool m5_ready = isEMAsReadyForEntry(isLong, TF2, barShift);
        
        if (showDebug && !(m1_ready && m3_ready)) {
            //PrintDebug("[MTF E2] Rejected - M1:" + (m1_ready?"Y":"N") + " M3:" + (m3_ready?"Y":"N"));
        }
        
        return m1_ready && m3_ready && m5_ready;  // All 3 timeframes must align (with tolerance)
    }
}

double TriggerPrice() {
    // if (ENTRY_SHIFT >= 1 && USE_LIVE_PRICE_FOR_ENTRY_NOT_CLOSED_PRICE) {
    //     double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    //     double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    //     return (bid>0 && ask>0) ? (bid+ask)*0.5 : iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
    // }
    return iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
}

void HandleHighRiskEntry(Trade &detectedTrade, double riskDistance, double potentialLossUSD) {
    // P0 RISK CHECKS FIRST (critical fix: high-risk was bypassing aggregate risk limits)
    if (!CanCreateNewEntry()) {
        EnterOrSkipTrade(detectedTrade, false, "High-risk blocked by risk limits");
        return;
    }
    
    // CRITICAL: Check for opposing direction positions (prevents hedge losses)
    if (HasOpposingDirectionPosition(detectedTrade.isLong)) {
        string oppDir = detectedTrade.isLong ? "SHORT" : "LONG";
        EnterOrSkipTrade(detectedTrade, false, "High-risk blocked: opposing " + oppDir + " position active");
        return;
    }
    
    // Check if high-risk entry is allowed for this entry type
    EntryBase* entryForHR = GetEntryForType(detectedTrade.entryType);
    bool entryTypeAllowsHighRisk = (entryForHR != NULL) ? entryForHR.GetAcceptHighRisk() : false;
    
    if (!entryTypeAllowsHighRisk) {
        EnterOrSkipTrade(detectedTrade, false, "High risk " + detectedTrade.type + " not accepted");
        return;
    }
    if (highRiskTradesInSession >= MAX_HIGH_RISK_TRADES_PER_SESSION) {
        EnterOrSkipTrade(detectedTrade, false, "High-risk trades per session limit reached");
        return;
    }
    if (IsInSidewayRange(10)) {
        EnterOrSkipTrade(detectedTrade, false, "High-risk trade rejected: Market in sideway range");
        return;
    }
    
    // Verify strict momentum for high-risk trades
    // For E3: checking reversal direction momentum acts as CONFIRMATION filter
    // (ensures some reversal momentum is building before entering counter-trend)
    TREND_STATE requiredTrend = detectedTrade.isLong ? TREND_BULL : TREND_BEAR;
    HIGH_RISK_MOMENTUM_LEVEL momentumCheck = (HIGH_RISK_MOMENTUM_LEVEL)((entryForHR != NULL) ? entryForHR.GetHighRiskMomentumCheck() : 0);
    
    if (!CheckMomentumForLevel(momentumCheck, requiredTrend, detectedTrade.entryType)) {
        double entryRiskPercent = GetEntrySpecificRiskRatio(detectedTrade.entryType,
            (entryForHR != NULL) ? entryForHR.GetMaxLossRatio() : 0.0) * 100;
        EnterOrSkipTrade(detectedTrade, false, "High risk/far SL without strong trend (max risk " + DoubleToString(entryRiskPercent, 2) + "%)" );
        return;
    }
    
    // Adjust lot size using entry-specific risk
    // During recovery: use recovery max loss to escape DD deadlock (all entry types)
    double entrySpecificMaxLoss;
    if (inRecoveryMode) {
        entrySpecificMaxLoss = detectedTrade.qualifiesForRecoveryBoost ? 
            GetEntryBoostedMaxLossDuringRecovery(detectedTrade.entryType) :
            GetEntryBaseMaxLossDuringRecovery(detectedTrade.entryType);
    } else {
        entrySpecificMaxLoss = getMaxLossUSD(detectedTrade.entryType);
    }
    double targetRiskUSD = entrySpecificMaxLoss * 0.98;
    double adjustedLot = MathMax(targetRiskUSD / (riskDistance * contractSize), minimumLotSize);
    
    // Cap by getScaledLotSize to respect all risk multipliers (soft block, profit protection, win streak)
    double hrLotMult = (entryForHR != NULL) ? entryForHR.GetLotMultiplier() : -1.0;
    bool hrVolAdj = (entryForHR != NULL) ? entryForHR.GetVolLotAdjEnabled() : false;
    adjustedLot = MathMin(adjustedLot, getScaledLotSize(detectedTrade.entryType, hrLotMult, hrVolAdj));

    // Entry-specific lot reduction - apply directly since MathMin may bypass getScaledLotSize's reduction
    if (hrLotMult >= 0.0 && hrLotMult < 1.0) {
        adjustedLot *= hrLotMult;
    }
    detectedTrade.lotSize = adjustedLot;
    
    // Session-aware TP adjustment
    double tpMultiplier = GetHighRiskTPMultiplier();
    double tpDistance = MathAbs(detectedTrade.takeProfit - detectedTrade.entryPrice);
    detectedTrade.takeProfit = detectedTrade.isLong ? 
                              (detectedTrade.entryPrice + tpDistance * tpMultiplier) :
                              (detectedTrade.entryPrice - tpDistance * tpMultiplier);
    
    highRiskTradesInSession++;
    detectedTrade.isHighRiskTrade = true;
    double entryRiskPercent = GetEntrySpecificRiskRatio(detectedTrade.entryType,
        (entryForHR != NULL) ? entryForHR.GetMaxLossRatio() : 0.0) * 100;
    EnterOrSkipTrade(detectedTrade, true, "High risk/far SL with strong trend (risk " + DoubleToString(entryRiskPercent, 2) + "% for " + detectedTrade.type + ")" );
}

// Helper to check momentum at specified level (uses entry-specific ADX/DI thresholds)
bool CheckMomentumForLevel(HIGH_RISK_MOMENTUM_LEVEL level, TREND_STATE requiredTrend, ENTRY_TYPE entryType) {
    // Determine which ADX/DI thresholds to use based on entry type
    EntryBase* entryPtr = GetEntryForType(entryType);
    double adxThreshold = (entryPtr != NULL) ? entryPtr.GetHighRiskADXThreshold() : E3_HIGH_RISK_MAX_ADX;
    double minDISpread = (entryPtr != NULL) ? entryPtr.GetHighRiskMinDISpread() : E3_HIGH_RISK_MIN_DI_SPREAD;
    bool isE3 = (entryPtr != NULL) ? entryPtr.IsCounterTrend() : false;
    
    switch(level) {
        case NONE: return true;
        case M1_ONLY: return isE3 ? HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF0], adxThreshold, minDISpread) 
                                   : HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF0], adxThreshold, minDISpread);
        case M3_ONLY: return isE3 ? HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF1], adxThreshold, minDISpread)
                                   : HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF1], adxThreshold, minDISpread);
        case M1_OR_M3: return isE3 ? (HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF0], adxThreshold, minDISpread) ||
                                      HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF1], adxThreshold, minDISpread))
                                    : (HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF0], adxThreshold, minDISpread) ||
                                       HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF1], adxThreshold, minDISpread));
        case M1_AND_M3: return isE3 ? (HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF0], adxThreshold, minDISpread) &&
                                       HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF1], adxThreshold, minDISpread))
                                     : (HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF0], adxThreshold, minDISpread) &&
                                        HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF1], adxThreshold, minDISpread));
        case M1_AND_M5: return isE3 ? (HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF0], adxThreshold, minDISpread) &&
                                       HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF2], adxThreshold, minDISpread))
                                     : (HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF0], adxThreshold, minDISpread) &&
                                        HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF2], adxThreshold, minDISpread));
        case M5_ONLY: return isE3 ? HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF2], adxThreshold, minDISpread)
                                   : HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF2], adxThreshold, minDISpread);                               
        case M3_AND_M5: return isE3 ? (HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF1], adxThreshold, minDISpread) &&
                                       HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF2], adxThreshold, minDISpread))
                                     : (HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF1], adxThreshold, minDISpread) &&
                                        HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF2], adxThreshold, minDISpread));
        case M5_AND_M15: return isE3 ? (HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF2], adxThreshold, minDISpread) &&
                                        HasReversedMomentumForE3(requiredTrend, TF_ARRAY[TF3], adxThreshold, minDISpread))
                                      : (HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF2], adxThreshold, minDISpread) &&
                                         HasStrictMomentumForHighRisk(requiredTrend, TF_ARRAY[TF3], adxThreshold, minDISpread));
        // E1-specific acceleration checks (rising ADX + widening DI spread)
        case E1_ACCEL_M1: return HasEarlyTrendMomentumForE1(requiredTrend, TF_ARRAY[TF0]);
        case E1_ACCEL_M3: return HasEarlyTrendMomentumForE1(requiredTrend, TF_ARRAY[TF1]);
        case E1_ACCEL_M1_OR_M3: return HasEarlyTrendMomentumForE1(requiredTrend, TF_ARRAY[TF0]) ||
                                       HasEarlyTrendMomentumForE1(requiredTrend, TF_ARRAY[TF1]);
        case E1_ACCEL_M1_AND_M3: return HasEarlyTrendMomentumForE1(requiredTrend, TF_ARRAY[TF0]) &&
                                       HasEarlyTrendMomentumForE1(requiredTrend, TF_ARRAY[TF1]);
        case E1_ACCEL_M3_OR_M5: return HasEarlyTrendMomentumForE1(requiredTrend, TF_ARRAY[TF1]) &&
                                       HasEarlyTrendMomentumForE1(requiredTrend, TF_ARRAY[TF2]);
    }
    return false;
}

void DetectNewEntry(bool signalOnlyMode = false) {
    //if (showDebug && entry1 != NULL) Print("[DEBUG] DetectNewEntry called, entry1 initialized");
    
    // Matching v1.6.5 structure exactly
    bool inValidSession = IsNowInValidSession() || IGNORE_VALID_SESSIONS;
    
    // Get EMA values (CRITICAL - v1.6.5 line 3483)
    if (!GetEMAValues()) {
        Print("Failed to get EMA values");
        return;
    }
    
    // Update account balance for risk calculations
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    maxLossUSD = getMaxLossUSD();
    
    double currentPrice = TriggerPrice();
    Trade detectedTrade;
    detectedTrade.type = "";
    
    int totalBars = Bars(_Symbol, TF_ARRAY[TF0]);
    int minBarsRequired = ENTRY_SHIFT + 2;
    
    bool isInExtremeSidewayRange = IsInExtremeSidewayRange();
    
    // Matching v1.6.5: ALL conditions in ONE if statement
    // Note: signalOnlyMode bypasses IsDrawdownBlocked() check to allow signal detection during protection modes
    bool drawdownCheck = signalOnlyMode ? true : !IsDrawdownBlocked();
    if (inValidSession && !isInExtremeSidewayRange && !IsBlockedByLosingStreak() && drawdownCheck && totalBars >= minBarsRequired) {
        // Update EMA touch tracking first (v1.6.5 line 3505)
        //UpdateEmaTouches();
        
        // Initialize trade detection
        double recentHigh = iHigh(_Symbol, TF_ARRAY[TF0], iHighest(_Symbol, TF_ARRAY[TF0], MODE_HIGH, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
        double recentLow = iLow(_Symbol, TF_ARRAY[TF0], iLowest(_Symbol, TF_ARRAY[TF0], MODE_LOW, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
        
        // Initialize trade with default values and calculated lot size (before any detection)
        InitializeTrade(detectedTrade, currentPrice);
        
        // Run entry detection for enabled entry types
        if (ENABLE_E1_ENTRIES) {
            // Block E1 when same-direction E4 is active (avoid redundant trend entries)
            // Only block if E4 is in same direction - opposite direction E4 doesn't conflict
            bool hasActiveE4SameDirection = false;
            if (BLOCK_E1_WHEN_E4_ACTIVE && entry1 != NULL) {
                // Pre-check E1 direction before full detection (lightweight)
                bool potentialE1IsLong = entry1.PeekDirection();
                for (int idx = 0; idx < ArraySize(trades); idx++) {
                    if (IsE4Entry(trades[idx].entryType) && trades[idx].isLong == potentialE1IsLong) {
                        hasActiveE4SameDirection = true;
                        break;
                    }
                }
            }
            if (!hasActiveE4SameDirection && entry1 != NULL) {
                DetectionResult entry1Result = entry1.Detect();
                
                if (entry1Result.detected) {
                    // Convert OOP result to Trade struct
                    detectedTrade.type = entry1Result.isLong ? "L-E1" : "S-E1";
                    detectedTrade.entryType = entry1Result.entryType;
                    detectedTrade.entryPrice = entry1Result.entryPrice;
                    detectedTrade.stopLoss = entry1Result.stopLoss;
                    detectedTrade.rawSLDistancePips = entry1Result.rawSLDistancePips;
                    detectedTrade.bufferedSLDistancePips = entry1Result.bufferedSLDistancePips;

                    // Process conviction and set TP (uses cached score from detection)
                    ProcessEntryConvictionAndConfidence(detectedTrade, detectedTrade.type, currentPrice,
                                                       entry1Result.isLowConfidence, entry1Result.lowConfidenceReason,
                                                       entry1Result.trendQualityScore);
                }
            }
        }
        if (ENABLE_E2_ENTRIES && detectedTrade.type == "") {
            // E2 OOP CODE
            if (entry2 != NULL) {
                DetectionResult entry2Result = entry2.Detect();
                
                if (entry2Result.detected) {
                    detectedTrade.type = entry2Result.isLong ? "L-E2" : "S-E2";
                    detectedTrade.entryType = entry2Result.entryType;
                    detectedTrade.entryPrice = entry2Result.entryPrice;
                    detectedTrade.stopLoss = entry2Result.stopLoss;
                    detectedTrade.rawSLDistancePips = entry2Result.rawSLDistancePips;
                    detectedTrade.bufferedSLDistancePips = entry2Result.bufferedSLDistancePips;
                    
                    // Process conviction and set TP (uses cached score from detection)
                    ProcessEntryConvictionAndConfidence(detectedTrade, detectedTrade.type, currentPrice,
                                                       entry2Result.isLowConfidence, entry2Result.lowConfidenceReason,
                                                       entry2Result.trendQualityScore);
                }
            }
        }
        if (ENABLE_E3_ENTRIES && detectedTrade.type == "") {
            // Block E3 when trend trades (E1/E2/E4) are active in OPPOSITE direction
            bool hasOpposingTrendTrade = false;
            if (E3_BLOCK_WHEN_TREND_ACTIVE && entry3 != NULL) {
                bool potentialE3IsLong = entry3.PeekDirection();
                for (int idx = 0; idx < ArraySize(trades); idx++) {
                    if (trades[idx].status != "OPEN") continue;
                    // Check E1, E2, E4 trades in opposite direction to E3
                    bool isTrendEntry = IsE1Entry(trades[idx].entryType) ||
                                        IsE2Entry(trades[idx].entryType) ||
                                        IsE4Entry(trades[idx].entryType) ||
                                        IsE5Entry(trades[idx].entryType);
                    if (isTrendEntry && trades[idx].isLong != potentialE3IsLong) {
                        hasOpposingTrendTrade = true;
                        break;
                    }
                }
            }
            // Only call Detect() if M3 exhaustion is active (pre-check is cheap)
            if (!hasOpposingTrendTrade && entry3 != NULL && entry3.ShouldCheckE3()) {
                DetectionResult entry3Result = entry3.Detect();
                
                if (entry3Result.detected) {
                    detectedTrade.type = entry3Result.isLong ? "L-E3" : "S-E3";
                    detectedTrade.entryType = entry3Result.entryType;
                    detectedTrade.entryPrice = entry3Result.entryPrice;
                    detectedTrade.stopLoss = entry3Result.stopLoss;
                    detectedTrade.takeProfit = entry3Result.takeProfit;
                    detectedTrade.rawSLDistancePips = entry3Result.rawSLDistancePips;
                    detectedTrade.bufferedSLDistancePips = entry3Result.bufferedSLDistancePips;
                    
                    // Process conviction and set TP (E3 uses exhaustion score, pass 0 for trendQuality)
                    ProcessEntryConvictionAndConfidence(detectedTrade, detectedTrade.type, currentPrice,
                                                       entry3Result.isLowConfidence, entry3Result.lowConfidenceReason,
                                                       entry3Result.trendQualityScore);
                }
            }
        }
        
        // E4: Ichimoku Cloud Cross (early trend entry)
        if (ENABLE_E4_ENTRIES && detectedTrade.type == "") {
            // Block E4 when same-direction E1 is active (avoid redundant trend entries)
            bool hasActiveE1SameDirection = false;
            if (BLOCK_E4_WHEN_E1_ACTIVE && entry4 != NULL) {
                bool potentialE4IsLong = entry4.PeekDirection();
                for (int idx = 0; idx < ArraySize(trades); idx++) {
                    if (IsE1Entry(trades[idx].entryType) && trades[idx].isLong == potentialE4IsLong) {
                        hasActiveE1SameDirection = true;
                        break;
                    }
                }
            }
            if (!hasActiveE1SameDirection && entry4 != NULL) {
                DetectionResult entry4Result = entry4.Detect();
                
                if (entry4Result.detected) {
                    detectedTrade.type = entry4Result.isLong ? "L-E4" : "S-E4";
                    detectedTrade.entryType = entry4Result.entryType;
                    detectedTrade.entryPrice = entry4Result.entryPrice;
                    detectedTrade.stopLoss = entry4Result.stopLoss;
                    detectedTrade.takeProfit = entry4Result.takeProfit;
                    detectedTrade.rawSLDistancePips = entry4Result.rawSLDistancePips;
                    detectedTrade.bufferedSLDistancePips = entry4Result.bufferedSLDistancePips;
                    
                    // Process conviction and set TP (uses cached score from detection)
                    ProcessEntryConvictionAndConfidence(detectedTrade, detectedTrade.type, currentPrice,
                                                       entry4Result.isLowConfidence, entry4Result.lowConfidenceReason,
                                                       entry4Result.trendQualityScore);
                }
            }
        }
        
        // E5: SuperBros EMA Alignment (simple, no momentum)
        if (ENABLE_E5_ENTRIES && detectedTrade.type == "") {
            if (entry5 != NULL) {
                DetectionResult entry5Result = entry5.Detect();

                if (entry5Result.detected) {
                    detectedTrade.type = entry5Result.isLong ? "L-E5" : "S-E5";
                    detectedTrade.entryType = entry5Result.entryType;
                    detectedTrade.entryPrice = entry5Result.entryPrice;
                    detectedTrade.stopLoss = entry5Result.stopLoss;
                    detectedTrade.takeProfit = entry5Result.takeProfit;
                    detectedTrade.rawSLDistancePips = entry5Result.rawSLDistancePips;
                    detectedTrade.bufferedSLDistancePips = entry5Result.bufferedSLDistancePips;

                    ProcessEntryConvictionAndConfidence(detectedTrade, detectedTrade.type, currentPrice,
                                                       entry5Result.isLowConfidence, entry5Result.lowConfidenceReason,
                                                       entry5Result.trendQualityScore);
                }
            }

            // PARITY: REAL-PATH E5 entry-decision trace (read-only; once per bar that E5 Detect ran).
            // Fills the execution-side gate inputs from globals — NO GetEntryBlockReason() call
            // (it mutates blackSwanBlockedUntil); we replicate the binding MIN_ENTRY gate read-only.
            if (InpExportRealTrace && entry5 != NULL) {
                E5RealRow rr;
                entry5.GetRealTrace(rr);
                if (rr.interesting) {
                    rr.atr_pctile       = cachedATRPercentile;
                    rr.min_entry_pctile = MIN_ENTRY_ATR_PERCENTILE;
                    rr.atr_pctile_low   = ATR_PERCENTILE_LOW;
                    rr.atr_pctile_high  = ATR_PERCENTILE_HIGH;
                    rr.min_entry_block  = (MIN_ENTRY_ATR_PERCENTILE > 0 &&
                                           cachedATRPercentile < MIN_ENTRY_ATR_PERCENTILE) ? 1 : 0;

                    if (StringFind(detectedTrade.type, "E5") >= 0) {
                        double rdist = MathAbs(detectedTrade.stopLoss - detectedTrade.entryPrice);
                        double pLoss = rdist * detectedTrade.lotSize * contractSize;
                        double eMax  = getMaxLossUSD(detectedTrade.entryType);
                        rr.potential_loss_usd = pLoss;
                        rr.entry_max_loss     = eMax;
                        rr.is_high_risk       = (pLoss >= eMax) ? 1 : 0;
                        rr.opposing_pos       = HasOpposingDirectionPosition(detectedTrade.isLong) ? 1 : 0;
                        rr.entrytype_blocked  = IsEntryTypeBlocked(detectedTrade.type) ? 1 : 0;
                        // Mirror DetectNewEntry's execution branch order (read-only; no side effects).
                        if (rr.is_high_risk)            rr.final_decision = "HIGH_RISK_ROUTE";
                        else if (rr.opposing_pos == 1)  rr.final_decision = "BLOCK:opposing";
                        else if (rr.entrytype_blocked == 1) rr.final_decision = "BLOCK:streak";
                        else if (rr.min_entry_block == 1)   rr.final_decision = "BLOCK:min_entry_pctile";
                        else                            rr.final_decision = "FIRE";
                    } else {
                        rr.final_decision = "NOT_DETECTED:" + rr.gate;
                    }
                    WriteRealTraceRow(rr);
                }
            }
        }

        // Count detected entries
        if (detectedTrade.type != "") {
            entryDetectedCount++;
            
            // SIGNAL-ONLY MODE: Send signal but don't execute trade during protection modes
            if (signalOnlyMode) {
                string protectionReason = GetProtectionModeReason();
                EnterOrSkipTrade(detectedTrade, false, "SIGNAL ONLY (" + protectionReason + ") - Trade blocked, signal sent");
            }
            else {
                // Risk management & high-risk handling
                double riskDistance = MathAbs(detectedTrade.stopLoss - detectedTrade.entryPrice);
                double potentialLossUSD = riskDistance * detectedTrade.lotSize * contractSize;
                
                // Handle high-risk trades (potentialLoss >= entry-specific maxLoss)
                double entryMaxLoss = getMaxLossUSD(detectedTrade.entryType);
                if (potentialLossUSD >= entryMaxLoss) {
                    HandleHighRiskEntry(detectedTrade, riskDistance, potentialLossUSD);
                }
                else {
                    // CRITICAL: Check for opposing direction positions FIRST (prevents hedge losses)
                    if (HasOpposingDirectionPosition(detectedTrade.isLong)) {
                        string oppDir = detectedTrade.isLong ? "SHORT" : "LONG";
                        EnterOrSkipTrade(detectedTrade, false, "Blocked: opposing " + oppDir + " position active");
                    }
                    // Normal risk trade - check consecutive losses
                    else if (IsEntryTypeBlocked(detectedTrade.type)) {
                        EnterOrSkipTrade(detectedTrade, false, detectedTrade.type + " blocked by consecutive losses");
                    }
                    // Then final validation
                    else {
                        string blockReason = GetEntryBlockReason();
                        if (blockReason != "") {
                            EnterOrSkipTrade(detectedTrade, false, blockReason);
                        }
                        else {
                            EnterOrSkipTrade(detectedTrade, true, "Good Setup!");
                        }
                    }
                }
            }
        }
    }
    
    // Send accumulated entry failure reasons (if any)
    //SendEntryFailureSummary();
}
void OnTimer()  {
    // Update news events periodically
    if (ENABLE_NEWS_FILTER) {
        UpdateNewsEvents();
    }
    
    // Call monitoring functions (v1.7.447 enhancement)
    SendUnifiedHealthCheck();
    SendUnifiedNewsCountdown();
}

void OnTick() {
    // Initialize EA start time on first tick
    if(eaStartTime == 0) {
        eaStartTime = TimeCurrent();
    }

    // Cross-EA account guardian (shared with KK-MasterVP). On account breach: flatten
    // KenKem's own positions (if configured) and block all new entries this tick. Open
    // positions left in place still carry their broker-side SL.
    if(g_kkGuard.Enabled() && g_kkGuard.Update()) {
        if(g_kkGuard.ShouldFlatten()) KkGuardFlattenOwn();
        return;
    }

    // Access expiry (server-time): once past the baked date, stop opening new
    // trades (the entry choke point EnterOrSkipTrade converts every entry into a
    // skip). Open positions keep being managed below. Alert once.
    if(!g_kkAccessExpired && KK_AccessExpired(ACCESS_EXPIRY)) {
        g_kkAccessExpired = true;
        Alert("Expired Access");
        Print("[ACCESS] KK-KenKem access expired - no new trades; managing open positions only.");
    }
    
    // Update dynamic TP extension parameters based on volatility
    // UpdateDynamicTPExtension moved to TradeManager internal logic

    
    // P1 CHECK: Connection loss detection (with startup grace period)
    datetime currentTime = TimeCurrent();
    bool startupGracePeriod = (currentTime - eaStartTime) < 30;  // 30 second grace period
    
    if(!TerminalInfoInteger(TERMINAL_CONNECTED)) {
        if(!startupGracePeriod && currentTime - lastConnectionAlert > 300) {  // Alert every 5 min
            Print("WARNING: DISCONNECTED FROM BROKER!");
            lastConnectionAlert = currentTime;
        }
        return;
    }
    
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
        if(!startupGracePeriod && currentTime - lastConnectionAlert > 300) {
            Print("WARNING: TRADING NOT ALLOWED! Enable AutoTrading button (toolbar) or check EA settings.");
            lastConnectionAlert = currentTime;
        }
        return;  // Don't process any trading logic if trading is disabled
    }
    
    // NEWS AVOIDANCE: Close all positions 10 minutes before high impact news
    CloseAllPositionsBeforeHighImpactNews();
    
    // New bar detection and bar-based operations (matching v1.6.5 structure)
    currentBar = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
    
    // NEW BAR EVENT - Run all heavy calculations here (once per bar)
    if (currentBar != lastBarIndex) {
        lastBarIndex = currentBar;
        
        // Update session tracking (once per bar is sufficient)
        UpdateSessionTracking();
        
        // Update indicator cache (expensive operations)
        UpdateIndicatorCache();

        // PARITY: dump the per-bar E5 decision (read-only; once per closed bar, cache fresh).
        if(InpExportBarTrace && entry5 != NULL) {
            E5TraceRow btRow;
            entry5.TraceBar(currentBar, btRow);
            WriteBarTraceRow(btRow);
        }

        // Update EMA touch tracking
        UpdateEmaTouches();
        
        // Initialize EMA flags from history on first successful bar (after indicators are ready)
        if (!emaHistoryInitialized) {
            InitializeEMAFlagsFromHistory();
            emaHistoryInitialized = true;
        }
        
        // Session end closure
        CloseAllTradesAtSessionEnd();
    }
    
    // CRITICAL: Process existing trades BEFORE safety checks
    // This ensures TP/SL alerts are always sent even when new entries are blocked
    if(tradeManager != NULL) {
        tradeManager.ProcessAllTrades();
    }
    
    // SAFETY CHECKS: Daily loss limit and drawdown protection
    // These checks block NEW ENTRIES only - existing positions continue with their SL/TP
    bool signalOnlyMode = false;  // Flag to indicate signal-only mode (no trade execution)
    
    if (!IsWithinDailyLossLimit()) {
        if (!SIGNAL_ONLY_DURING_PROTECTION) return;  // Block completely if signal-only disabled
        signalOnlyMode = true;  // Allow detection for signal sending only
    }
    
    // Check drawdown cooldown first (resets peak if cooldown expired)
    if (IsDrawdownBlocked()) {
        if (!SIGNAL_ONLY_DURING_PROTECTION) return;  // Block completely if signal-only disabled
        signalOnlyMode = true;  // Allow detection for signal sending only
    }
    
    // Then check if new drawdown limit triggered
    if (!IsWithinDrawdownLimit()) {
        if (!SIGNAL_ONLY_DURING_PROTECTION) return;  // Block completely if signal-only disabled
        signalOnlyMode = true;  // Allow detection for signal sending only
    }
    
    // Note: Recovery mode and soft block mode should ALLOW trading with reduced lots
    // Only hard drawdown block (IsDrawdownBlocked) triggers signal-only mode
    // Do NOT add inRecoveryMode or inSoftBlockMode here - they need to trade to recover
    
    // LIMIT ORDER MANAGEMENT - Process pending orders every tick (before new entry detection)
    if (ENABLE_LIMIT_ORDERS) ManagePendingOrders();

    // ENTRY DETECTION - Only once per bar (after safety checks pass)
    if (currentBar != lastEntryBarIndex) {
        lastEntryBarIndex = currentBar;  // Mark bar as processed
        DetectNewEntry(signalOnlyMode);
    }

    // PARITY: poll position transitions LAST so opens (DetectNewEntry) and closes
    // (ProcessAllTrades) on this same tick are both captured with zero lag.
    if(InpExportTradeJournal)
        KenKemJournalPoll(SymbolInfoDouble(_Symbol, SYMBOL_BID),
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK));
} // End of OnTick() function

//+------------------------------------------------------------------+
//| CSV EXPORT & TELEGRAM FUNCTIONS (Analytics Only - No Trading Impact) |
//+------------------------------------------------------------------+

// ===== Telegram functions moved to Utils/TelegramAlerts.mqh =====
// - SendTelegramMessage()
// - SendAlertForTrade()




// ===== CSV Export functions moved to Utils/CSVExport.mqh =====
// - CsvEscape()
// - FlushCSVBuffer()
// - InitializeCSVExport()
// - ExportTradeEventToCSV()

//+------------------------------------------------------------------+
//| Performance Statistics Structure for E1/E2 Tracking             |
//+------------------------------------------------------------------+
struct PerformanceStats {
    int totalE1Entries, e1Wins, e1Losses;
    int totalE2Entries, e2Wins, e2Losses;
    int e2LongWins, e2LongLosses, e2ShortWins, e2ShortLosses;
    int totalE3Entries, e3Wins, e3Losses;
    int totalE4Entries, e4Wins, e4Losses;
    int totalE5Entries, e5Wins, e5Losses;
    int totalTrades, totalWins, totalLosses;
    double totalPnL;
};

// Global performance statistics
PerformanceStats perfStats;

//+------------------------------------------------------------------+
//| Initialize Performance Statistics                                |
//+------------------------------------------------------------------+
void InitializePerformanceStats() {
    perfStats.totalE1Entries = 0;
    perfStats.e1Wins = 0;
    perfStats.e1Losses = 0;
    
    
    perfStats.totalE2Entries = 0;
    perfStats.e2Wins = 0;
    perfStats.e2Losses = 0;
    perfStats.e2LongWins = 0;
    perfStats.e2LongLosses = 0;
    perfStats.e2ShortWins = 0;
    perfStats.e2ShortLosses = 0;
    
    perfStats.totalE3Entries = 0;
    perfStats.e3Wins = 0;
    perfStats.e3Losses = 0;
    
    perfStats.totalE4Entries = 0;
    perfStats.e4Wins = 0;
    perfStats.e4Losses = 0;

    perfStats.totalE5Entries = 0;
    perfStats.e5Wins = 0;
    perfStats.e5Losses = 0;

    perfStats.totalTrades = 0;
    perfStats.totalWins = 0;
    perfStats.totalLosses = 0;
    perfStats.totalPnL = 0.0;
}

//+------------------------------------------------------------------+
//| Update Performance Statistics on Trade Entry                    |
//+------------------------------------------------------------------+
void UpdatePerformanceOnEntry(const Trade &dtrade) {
    perfStats.totalTrades++;
    
    // PERFORMANCE: Count E1-E4 entries using enum (faster than StringFind)
    if (IsE1Entry(dtrade.entryType)) {
        perfStats.totalE1Entries++;
    }
    else if (IsE2Entry(dtrade.entryType)) {
        perfStats.totalE2Entries++;
    } else if (IsE3Entry(dtrade.entryType)) {
        perfStats.totalE3Entries++;
    } else if (IsE4Entry(dtrade.entryType)) {
        perfStats.totalE4Entries++;
    } else if (IsE5Entry(dtrade.entryType)) {
        perfStats.totalE5Entries++;
    }
}

//+------------------------------------------------------------------+
//| Get Entry Instance for Adaptive Tracking                         |
//+------------------------------------------------------------------+
EntryBase* GetEntryForType(ENTRY_TYPE entryType) {
    if (entryType == ENTRY_L_E1 || entryType == ENTRY_S_E1) {
        return entry1;
    }
    else if (entryType == ENTRY_L_E2 || entryType == ENTRY_S_E2) {
        return entry2;
    }
    else if (entryType == ENTRY_L_E3 || entryType == ENTRY_S_E3) {
        return entry3;
    }
    else if (entryType == ENTRY_L_E4 || entryType == ENTRY_S_E4) {
        return entry4;
    }
    else if (entryType == ENTRY_L_E5 || entryType == ENTRY_S_E5) {
        return entry5;
    }
    return NULL;
}

//+------------------------------------------------------------------+
//| Update Performance Statistics on Trade Exit                     |
//+------------------------------------------------------------------+
void UpdatePerformanceOnExit(const Trade &dtrade) {
    // CRITICAL: Only count actually executed trades (skip virtual/skipped trades)
    if (dtrade.positionTicket == 0) {
        PrintDebug("SKIP UpdatePerformanceOnExit: Virtual/skipped trade " + dtrade.id + " - NOT counting in stats");
        return;
    }
    
    PrintDebug("UpdatePerformanceOnExit: " + dtrade.id + " | status: " + dtrade.status + " | PnL: " + DoubleToString(dtrade.pnL, 2));
    perfStats.totalPnL += dtrade.pnL;
    
    // Track volatility context for adaptive learning
    EntryBase* entry = GetEntryForType(dtrade.entryType);
    if (entry != NULL) {
        double atrBuffer[1];
        if (CopyBuffer(g_atrM1Handle, 0, 0, 1, atrBuffer) > 0) {
            double currentATR = atrBuffer[0];
            entry.UpdateVolatilityContext(currentATR);
        }
    }
    
    // Determine if trade was won or lost
    bool tradeWon = (StringFind(dtrade.status, "WON") >= 0);    
    if (tradeWon) {
        perfStats.totalWins++;
        // PERFORMANCE: Enum checks instead of StringFind
        if (IsE1Entry(dtrade.entryType)) {
            perfStats.e1Wins++;
        }
        else if (IsE2Entry(dtrade.entryType)) {
            perfStats.e2Wins++;
            if (dtrade.entryType == ENTRY_L_E2) perfStats.e2LongWins++;
            else perfStats.e2ShortWins++;
        } else if (IsE3Entry(dtrade.entryType)) {
            perfStats.e3Wins++;
        } else if (IsE4Entry(dtrade.entryType)) {
            perfStats.e4Wins++;
        } else if (IsE5Entry(dtrade.entryType)) {
            perfStats.e5Wins++;
        }
    }
    else {
        // Trade was lost
        perfStats.totalLosses++;
        // PERFORMANCE: Enum checks instead of StringFind
        if (IsE1Entry(dtrade.entryType)) {
            perfStats.e1Losses++;
        }
        else if (IsE2Entry(dtrade.entryType)) {
            perfStats.e2Losses++;
            if (dtrade.entryType == ENTRY_L_E2) perfStats.e2LongLosses++;
            else perfStats.e2ShortLosses++;
        } else if (IsE3Entry(dtrade.entryType)) {
            perfStats.e3Losses++;
        } else if (IsE4Entry(dtrade.entryType)) {
            perfStats.e4Losses++;
        } else if (IsE5Entry(dtrade.entryType)) {
            perfStats.e5Losses++;
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Win Rate Percentage                                   |
//+------------------------------------------------------------------+
double CalculateWinRate(int wins, int losses) {
    int total = wins + losses;
    if (total == 0) return 0.0;
    return (double)wins / total * 100.0;
}

// Reusable function to calculate and print entry type statistics
// NOTE: Only counts ACTUALLY EXECUTED trades (skipped/virtual trades are excluded)
void PrintEntryTypeStats(string entryType, int totalEntries, int wins, int losses) {
    double winRate = CalculateWinRate(wins, losses);
    
    Print("--- ", entryType, " Entry Statistics ---");
    Print("Total ", entryType, " Entries: ", totalEntries, " (executed trades only)");
    Print(entryType, " Wins: ", wins);
    Print(entryType, " Losses: ", losses);
    Print(entryType, " Win Rate: ", DoubleToString(winRate, 2), "%");
    Print(""); // Empty line for readability
}

// Count skipped trades from existing trades[] array (REUSE, no new memory!)
// Checks BOTH long and short entry types (e.g., E1 = ENTRY_L_E1 + ENTRY_S_E1)
// ONLY counts RESOLVED skipped trades (WON or LOST), excludes still-active skipped trades
void GetSkippedTradeStats(ENTRY_TYPE longEntryType, int &totalSkipped, int &skippedWins, int &skippedLosses) {
    totalSkipped = 0;
    skippedWins = 0;
    skippedLosses = 0;
    
    // Determine short entry type (add 1 to enum: L_E1=0→S_E1=1, L_E2=2→S_E2=3, etc.)
    ENTRY_TYPE shortEntryType = (ENTRY_TYPE)(longEntryType + 1);
    
    for(int i = 0; i < ArraySize(trades); i++) {
        // Check if trade matches EITHER long OR short entry type
        if(trades[i].entryType != longEntryType && trades[i].entryType != shortEntryType) continue;
        
        string status = trades[i].status;
        if(StringFind(status, "SKIPPED") < 0) continue;
        
        // ONLY count RESOLVED skipped trades (exclude "SKIPPED_BUY" or "SKIPPED_SELL" without outcome)
        if(StringFind(status, "WON") >= 0) {
            totalSkipped++;
            skippedWins++;
        } else if(StringFind(status, "LOST") >= 0) {
            totalSkipped++;
            skippedLosses++;
        }
        // Else: Unresolved skipped trade (still active) - skip counting
    }
}

//+------------------------------------------------------------------+
//| OnTester - Performance Analysis for E1/E2 Win Rates           |
//+------------------------------------------------------------------+
double OnTester() {
    Print("=== KenKenKemST Performance Report ===");
    Print("NOTE: All statistics below reflect ONLY actually executed trades");
    Print("      Skipped/virtual trades (positionTicket == 0) are excluded");
    Print("");
    
    // Process any remaining open trades and update final statistics
    for (int i = 0; i < ArraySize(trades); i++) {
        if (trades[i].status == "OPEN") {
            // Mark open trades as incomplete for reporting
            Print("WARNING: Trade ", trades[i].id, " (", trades[i].type, ") still open at test end");
            continue;
        }
        
        // CRITICAL: Skip virtual/skipped trades (positionTicket == 0) from final report
        // This ensures we only count trades that were actually executed on the broker
        if (trades[i].positionTicket == 0) {
            continue;
        }
        
        // Verify that closed trades were properly counted
        // (This should already be done during trade lifecycle, but double-check)
        bool isWin = (trades[i].status == "WON" || trades[i].status == "WON-TP" || trades[i].status == "WON-PARTIAL");  // PHASE 2.1: Direct comparison faster
        PrintDebug("Trade #" + IntegerToString(trades[i].positionTicket) + " " + trades[i].id + " (" + trades[i].type + "): " + trades[i].status + " - " + (isWin ? "WIN" : "LOSS"));
    }
    
    // Debug: Show raw counts
    PrintDebug("DEBUG - Raw Stats: E1(W:" + IntegerToString(perfStats.e1Wins) + "/L:" + IntegerToString(perfStats.e1Losses) + ") E2(W:" + IntegerToString(perfStats.e2Wins) + "/L:" + IntegerToString(perfStats.e2Losses) + ") E3(W:" + IntegerToString(perfStats.e3Wins) + "/L:" + IntegerToString(perfStats.e3Losses) + ") E4(W:" + IntegerToString(perfStats.e4Wins) + "/L:" + IntegerToString(perfStats.e4Losses) + ") E5(W:" + IntegerToString(perfStats.e5Wins) + "/L:" + IntegerToString(perfStats.e5Losses) + ")");
    
    // Print statistics for all entry types using reusable function
    PrintEntryTypeStats("E1", perfStats.totalE1Entries, perfStats.e1Wins, perfStats.e1Losses);
    PrintEntryTypeStats("E2", perfStats.totalE2Entries, perfStats.e2Wins, perfStats.e2Losses);
    PrintEntryTypeStats("E2-LONG", perfStats.e2LongWins + perfStats.e2LongLosses, perfStats.e2LongWins, perfStats.e2LongLosses);
    PrintEntryTypeStats("E2-SHORT", perfStats.e2ShortWins + perfStats.e2ShortLosses, perfStats.e2ShortWins, perfStats.e2ShortLosses);
    PrintEntryTypeStats("E3", perfStats.totalE3Entries, perfStats.e3Wins, perfStats.e3Losses);
    PrintEntryTypeStats("E4", perfStats.totalE4Entries, perfStats.e4Wins, perfStats.e4Losses);
    PrintEntryTypeStats("E5", perfStats.totalE5Entries, perfStats.e5Wins, perfStats.e5Losses);
    
    // Print Overall Statistics
    double overallWinRate = CalculateWinRate(perfStats.totalWins, perfStats.totalLosses);
    Print("--- Overall Statistics ---");
    Print("Total Trades: ", perfStats.totalTrades);
    Print("Total Wins: ", perfStats.totalWins);
    Print("Total Losses: ", perfStats.totalLosses);
    Print("Overall Win Rate: ", DoubleToString(overallWinRate, 2), "%");
    Print("Total P&L: $", DoubleToString(perfStats.totalPnL, 2));
    
    Print("=== End Performance Report ===");
    
    // Print CSV file location if CSV export was enabled
    if (ENABLE_CSV_EXPORT && currentCSVFileName != "") {
        string terminalDataPath = TerminalInfoString(TERMINAL_DATA_PATH);
        string csvFullPath = terminalDataPath + "\\MQL5\\Files\\" + currentCSVFileName;
        Print("--- CSV Export Information ---");
        Print("CSV File: ", currentCSVFileName);
        Print("Full Path: ", csvFullPath);
        Print("Location: MT5 Terminal -> File -> Open Data Folder -> MQL5\\Files\\");
    }
    
    // ========== FILTER REJECTION ANALYSIS ==========
    Print("");
    Print("=== FILTER REJECTION ANALYSIS ===");
    Print("Shows why entry attempts were rejected (for parameter optimization)");
    Print("");
    
    // E1 LONG Analysis
    int e1_long_total_fails = entryStats.le1_attempts - entryStats.le1_success;
    if (e1_long_total_fails > 0) {
        Print("--- E1 LONG Rejections (", e1_long_total_fails, " total) ---");
        if (entryStats.le1_conviction_fail > 0) 
            Print("  Conviction Score: ", entryStats.le1_conviction_fail, " (", DoubleToString(entryStats.le1_conviction_fail*100.0/e1_long_total_fails,1), "%)");
        if (entryStats.le1_trend_quality_fail > 0) 
            Print("  Trend Quality: ", entryStats.le1_trend_quality_fail, " (", DoubleToString(entryStats.le1_trend_quality_fail*100.0/e1_long_total_fails,1), "%)");
        if (entryStats.le1_momentum_fail > 0) 
            Print("  Momentum: ", entryStats.le1_momentum_fail, " (", DoubleToString(entryStats.le1_momentum_fail*100.0/e1_long_total_fails,1), "%)");
        if (entryStats.le1_mtf_fail > 0) 
            Print("  MTF/EMA: ", entryStats.le1_mtf_fail, " (", DoubleToString(entryStats.le1_mtf_fail*100.0/e1_long_total_fails,1), "%)");
        if (entryStats.le1_no_cross > 0) 
            Print("  No Cross: ", entryStats.le1_no_cross, " (", DoubleToString(entryStats.le1_no_cross*100.0/e1_long_total_fails,1), "%)");
        if (entryStats.le1_htf_trend_fail > 0) 
            Print("  HTF Trend: ", entryStats.le1_htf_trend_fail, " (", DoubleToString(entryStats.le1_htf_trend_fail*100.0/e1_long_total_fails,1), "%)");
    }
    
    // E1 SHORT Analysis
    int e1_short_total_fails = entryStats.se1_attempts - entryStats.se1_success;
    if (e1_short_total_fails > 0) {
        Print("--- E1 SHORT Rejections (", e1_short_total_fails, " total) ---");
        if (entryStats.se1_conviction_fail > 0) 
            Print("  Conviction Score: ", entryStats.se1_conviction_fail, " (", DoubleToString(entryStats.se1_conviction_fail*100.0/e1_short_total_fails,1), "%)");
        if (entryStats.se1_trend_quality_fail > 0) 
            Print("  Trend Quality: ", entryStats.se1_trend_quality_fail, " (", DoubleToString(entryStats.se1_trend_quality_fail*100.0/e1_short_total_fails,1), "%)");
        if (entryStats.se1_momentum_fail > 0) 
            Print("  Momentum: ", entryStats.se1_momentum_fail, " (", DoubleToString(entryStats.se1_momentum_fail*100.0/e1_short_total_fails,1), "%)");
        if (entryStats.se1_mtf_fail > 0) 
            Print("  MTF/EMA: ", entryStats.se1_mtf_fail, " (", DoubleToString(entryStats.se1_mtf_fail*100.0/e1_short_total_fails,1), "%)");
        if (entryStats.se1_no_cross > 0) 
            Print("  No Cross: ", entryStats.se1_no_cross, " (", DoubleToString(entryStats.se1_no_cross*100.0/e1_short_total_fails,1), "%)");
        if (entryStats.se1_htf_trend_fail > 0) 
            Print("  HTF Trend: ", entryStats.se1_htf_trend_fail, " (", DoubleToString(entryStats.se1_htf_trend_fail*100.0/e1_short_total_fails,1), "%)");
    }
    
    // E2 LONG Analysis
    int e2_long_total_fails = entryStats.le2_attempts - entryStats.le2_success;
    if (e2_long_total_fails > 0) {
        Print("--- E2 LONG Rejections (", e2_long_total_fails, " total) ---");
        if (entryStats.le2_htf_trend_fail > 0) 
            Print("  HTF Trend: ", entryStats.le2_htf_trend_fail, " (", DoubleToString(entryStats.le2_htf_trend_fail*100.0/e2_long_total_fails,1), "%)");
        if (entryStats.le2_conviction_fail > 0) 
            Print("  Conviction Score: ", entryStats.le2_conviction_fail, " (", DoubleToString(entryStats.le2_conviction_fail*100.0/e2_long_total_fails,1), "%)");
        if (entryStats.le2_trend_quality_fail > 0) 
            Print("  Trend Quality: ", entryStats.le2_trend_quality_fail, " (", DoubleToString(entryStats.le2_trend_quality_fail*100.0/e2_long_total_fails,1), "%)");
        if (entryStats.le2_momentum_fail > 0) 
            Print("  Momentum: ", entryStats.le2_momentum_fail, " (", DoubleToString(entryStats.le2_momentum_fail*100.0/e2_long_total_fails,1), "%)");
        if (entryStats.le2_mtf_fail > 0) 
            Print("  MTF/EMA: ", entryStats.le2_mtf_fail, " (", DoubleToString(entryStats.le2_mtf_fail*100.0/e2_long_total_fails,1), "%)");
        if (entryStats.le2_volume_fail > 0) 
            Print("  Volume: ", entryStats.le2_volume_fail, " (", DoubleToString(entryStats.le2_volume_fail*100.0/e2_long_total_fails,1), "%)");
        if (entryStats.le2_no_touch > 0) 
            Print("  No Touch: ", entryStats.le2_no_touch, " (", DoubleToString(entryStats.le2_no_touch*100.0/e2_long_total_fails,1), "%)");
    }
    
    // E2 SHORT Analysis
    int e2_short_total_fails = entryStats.se2_attempts - entryStats.se2_success;
    if (e2_short_total_fails > 0) {
        Print("--- E2 SHORT Rejections (", e2_short_total_fails, " total) ---");
        if (entryStats.se2_htf_trend_fail > 0) 
            Print("  HTF Trend: ", entryStats.se2_htf_trend_fail, " (", DoubleToString(entryStats.se2_htf_trend_fail*100.0/e2_short_total_fails,1), "%)");
        if (entryStats.se2_conviction_fail > 0) 
            Print("  Conviction Score: ", entryStats.se2_conviction_fail, " (", DoubleToString(entryStats.se2_conviction_fail*100.0/e2_short_total_fails,1), "%)");
        if (entryStats.se2_trend_quality_fail > 0) 
            Print("  Trend Quality: ", entryStats.se2_trend_quality_fail, " (", DoubleToString(entryStats.se2_trend_quality_fail*100.0/e2_short_total_fails,1), "%)");
        if (entryStats.se2_momentum_fail > 0) 
            Print("  Momentum: ", entryStats.se2_momentum_fail, " (", DoubleToString(entryStats.se2_momentum_fail*100.0/e2_short_total_fails,1), "%)");
        if (entryStats.se2_mtf_fail > 0) 
            Print("  MTF/EMA: ", entryStats.se2_mtf_fail, " (", DoubleToString(entryStats.se2_mtf_fail*100.0/e2_short_total_fails,1), "%)");
        if (entryStats.se2_volume_fail > 0) 
            Print("  Volume: ", entryStats.se2_volume_fail, " (", DoubleToString(entryStats.se2_volume_fail*100.0/e2_short_total_fails,1), "%)");
        if (entryStats.se2_no_touch > 0) 
            Print("  No Touch: ", entryStats.se2_no_touch, " (", DoubleToString(entryStats.se2_no_touch*100.0/e2_short_total_fails,1), "%)");
    }
    
    // E3 LONG Analysis
    int e3_long_total_fails = entryStats.le3_attempts - entryStats.le3_success;
    if (e3_long_total_fails > 0) {
        Print("--- E3 LONG Rejections (", e3_long_total_fails, " total) ---");
        if (entryStats.le3_conviction_fail > 0) 
            Print("  Conviction Score: ", entryStats.le3_conviction_fail, " (", DoubleToString(entryStats.le3_conviction_fail*100.0/e3_long_total_fails,1), "%)");
        if (entryStats.le3_trend_quality_fail > 0) 
            Print("  Trend Quality: ", entryStats.le3_trend_quality_fail, " (", DoubleToString(entryStats.le3_trend_quality_fail*100.0/e3_long_total_fails,1), "%)");
        if (entryStats.le3_trend_context_fail > 0) 
            Print("  Trend Context: ", entryStats.le3_trend_context_fail, " (", DoubleToString(entryStats.le3_trend_context_fail*100.0/e3_long_total_fails,1), "%)");
        if (entryStats.le3_ema10_m3_fail > 0) 
            Print("  EMA10 M3 Break: ", entryStats.le3_ema10_m3_fail, " (", DoubleToString(entryStats.le3_ema10_m3_fail*100.0/e3_long_total_fails,1), "%)");
        if (entryStats.le3_ema10_m1_fail > 0) 
            Print("  EMA10 M1 Break: ", entryStats.le3_ema10_m1_fail, " (", DoubleToString(entryStats.le3_ema10_m1_fail*100.0/e3_long_total_fails,1), "%)");
        if (entryStats.le3_extreme_distance_fail > 0) 
            Print("  Extreme Distance: ", entryStats.le3_extreme_distance_fail, " (", DoubleToString(entryStats.le3_extreme_distance_fail*100.0/e3_long_total_fails,1), "%)");
        if (entryStats.le3_di_reversal_fail > 0) 
            Print("  DI Reversal: ", entryStats.le3_di_reversal_fail, " (", DoubleToString(entryStats.le3_di_reversal_fail*100.0/e3_long_total_fails,1), "%)");
    }
    
    // E3 SHORT Analysis
    int e3_short_total_fails = entryStats.se3_attempts - entryStats.se3_success;
    if (e3_short_total_fails > 0) {
        Print("--- E3 SHORT Rejections (", e3_short_total_fails, " total) ---");
        if (entryStats.se3_conviction_fail > 0) 
            Print("  Conviction Score: ", entryStats.se3_conviction_fail, " (", DoubleToString(entryStats.se3_conviction_fail*100.0/e3_short_total_fails,1), "%)");
        if (entryStats.se3_trend_quality_fail > 0) 
            Print("  Trend Quality: ", entryStats.se3_trend_quality_fail, " (", DoubleToString(entryStats.se3_trend_quality_fail*100.0/e3_short_total_fails,1), "%)");
        if (entryStats.se3_trend_context_fail > 0) 
            Print("  Trend Context: ", entryStats.se3_trend_context_fail, " (", DoubleToString(entryStats.se3_trend_context_fail*100.0/e3_short_total_fails,1), "%)");
        if (entryStats.se3_ema10_m3_fail > 0) 
            Print("  EMA10 M3 Break: ", entryStats.se3_ema10_m3_fail, " (", DoubleToString(entryStats.se3_ema10_m3_fail*100.0/e3_short_total_fails,1), "%)");
        if (entryStats.se3_ema10_m1_fail > 0) 
            Print("  EMA10 M1 Break: ", entryStats.se3_ema10_m1_fail, " (", DoubleToString(entryStats.se3_ema10_m1_fail*100.0/e3_short_total_fails,1), "%)");
        if (entryStats.se3_extreme_distance_fail > 0) 
            Print("  Extreme Distance: ", entryStats.se3_extreme_distance_fail, " (", DoubleToString(entryStats.se3_extreme_distance_fail*100.0/e3_short_total_fails,1), "%)");
        if (entryStats.se3_di_reversal_fail > 0) 
            Print("  DI Reversal: ", entryStats.se3_di_reversal_fail, " (", DoubleToString(entryStats.se3_di_reversal_fail*100.0/e3_short_total_fails,1), "%)");
    }
    
    // E4 LONG Analysis
    int e4_long_total_fails = entryStats.le4_attempts - entryStats.le4_success;
    if (e4_long_total_fails > 0) {
        Print("--- E4 LONG Rejections (", e4_long_total_fails, " total) ---");
        if (entryStats.le4_htf_trend_fail > 0) 
            Print("  HTF Trend: ", entryStats.le4_htf_trend_fail, " (", DoubleToString(entryStats.le4_htf_trend_fail*100.0/e4_long_total_fails,1), "%)");
        if (entryStats.le4_sideway_fail > 0) 
            Print("  Sideway: ", entryStats.le4_sideway_fail, " (", DoubleToString(entryStats.le4_sideway_fail*100.0/e4_long_total_fails,1), "%)");
        if (entryStats.le4_conviction_fail > 0) 
            Print("  Conviction Score: ", entryStats.le4_conviction_fail, " (", DoubleToString(entryStats.le4_conviction_fail*100.0/e4_long_total_fails,1), "%)");
        if (entryStats.le4_trend_quality_fail > 0) 
            Print("  Trend Quality: ", entryStats.le4_trend_quality_fail, " (", DoubleToString(entryStats.le4_trend_quality_fail*100.0/e4_long_total_fails,1), "%)");
        if (entryStats.le4_momentum_fail > 0) 
            Print("  Momentum: ", entryStats.le4_momentum_fail, " (", DoubleToString(entryStats.le4_momentum_fail*100.0/e4_long_total_fails,1), "%)");
        if (entryStats.le4_mtf_fail > 0) 
            Print("  MTF/EMA: ", entryStats.le4_mtf_fail, " (", DoubleToString(entryStats.le4_mtf_fail*100.0/e4_long_total_fails,1), "%)");
        if (entryStats.le4_no_cross > 0) 
            Print("  No Cross: ", entryStats.le4_no_cross, " (", DoubleToString(entryStats.le4_no_cross*100.0/e4_long_total_fails,1), "%)");
        if (entryStats.le4_thin_cloud > 0) 
            Print("  Thin Cloud: ", entryStats.le4_thin_cloud, " (", DoubleToString(entryStats.le4_thin_cloud*100.0/e4_long_total_fails,1), "%)");
        if (entryStats.le4_tenkan_kijun > 0) 
            Print("  Tenkan/Kijun: ", entryStats.le4_tenkan_kijun, " (", DoubleToString(entryStats.le4_tenkan_kijun*100.0/e4_long_total_fails,1), "%)");
        if (entryStats.le4_chikou_blocked > 0) 
            Print("  Chikou Blocked: ", entryStats.le4_chikou_blocked, " (", DoubleToString(entryStats.le4_chikou_blocked*100.0/e4_long_total_fails,1), "%)");
    }
    
    // E4 SHORT Analysis
    int e4_short_total_fails = entryStats.se4_attempts - entryStats.se4_success;
    if (e4_short_total_fails > 0) {
        Print("--- E4 SHORT Rejections (", e4_short_total_fails, " total) ---");
        if (entryStats.se4_htf_trend_fail > 0) 
            Print("  HTF Trend: ", entryStats.se4_htf_trend_fail, " (", DoubleToString(entryStats.se4_htf_trend_fail*100.0/e4_short_total_fails,1), "%)");
        if (entryStats.se4_sideway_fail > 0) 
            Print("  Sideway: ", entryStats.se4_sideway_fail, " (", DoubleToString(entryStats.se4_sideway_fail*100.0/e4_short_total_fails,1), "%)");
        if (entryStats.se4_conviction_fail > 0) 
            Print("  Conviction Score: ", entryStats.se4_conviction_fail, " (", DoubleToString(entryStats.se4_conviction_fail*100.0/e4_short_total_fails,1), "%)");
        if (entryStats.se4_trend_quality_fail > 0) 
            Print("  Trend Quality: ", entryStats.se4_trend_quality_fail, " (", DoubleToString(entryStats.se4_trend_quality_fail*100.0/e4_short_total_fails,1), "%)");
        if (entryStats.se4_momentum_fail > 0) 
            Print("  Momentum: ", entryStats.se4_momentum_fail, " (", DoubleToString(entryStats.se4_momentum_fail*100.0/e4_short_total_fails,1), "%)");
        if (entryStats.se4_mtf_fail > 0) 
            Print("  MTF/EMA: ", entryStats.se4_mtf_fail, " (", DoubleToString(entryStats.se4_mtf_fail*100.0/e4_short_total_fails,1), "%)");
        if (entryStats.se4_no_cross > 0) 
            Print("  No Cross: ", entryStats.se4_no_cross, " (", DoubleToString(entryStats.se4_no_cross*100.0/e4_short_total_fails,1), "%)");
        if (entryStats.se4_thin_cloud > 0) 
            Print("  Thin Cloud: ", entryStats.se4_thin_cloud, " (", DoubleToString(entryStats.se4_thin_cloud*100.0/e4_short_total_fails,1), "%)");
        if (entryStats.se4_tenkan_kijun > 0) 
            Print("  Tenkan/Kijun: ", entryStats.se4_tenkan_kijun, " (", DoubleToString(entryStats.se4_tenkan_kijun*100.0/e4_short_total_fails,1), "%)");
        if (entryStats.se4_chikou_blocked > 0) 
            Print("  Chikou Blocked: ", entryStats.se4_chikou_blocked, " (", DoubleToString(entryStats.se4_chikou_blocked*100.0/e4_short_total_fails,1), "%)");
    }
    
    // E5 LONG Analysis
    int e5_long_total_fails = entryStats.le5_attempts - entryStats.le5_success;
    if (e5_long_total_fails > 0) {
        Print("--- E5 LONG Rejections (", e5_long_total_fails, " total) ---");
        if (entryStats.le5_sideway_fail > 0)
            Print("  Sideway: ", entryStats.le5_sideway_fail, " (", DoubleToString(entryStats.le5_sideway_fail*100.0/e5_long_total_fails,1), "%)");
        if (entryStats.le5_stale_signal > 0)
            Print("  Stale Signal: ", entryStats.le5_stale_signal, " (", DoubleToString(entryStats.le5_stale_signal*100.0/e5_long_total_fails,1), "%)");
    }

    // E5 SHORT Analysis
    int e5_short_total_fails = entryStats.se5_attempts - entryStats.se5_success;
    if (e5_short_total_fails > 0) {
        Print("--- E5 SHORT Rejections (", e5_short_total_fails, " total) ---");
        if (entryStats.se5_sideway_fail > 0)
            Print("  Sideway: ", entryStats.se5_sideway_fail, " (", DoubleToString(entryStats.se5_sideway_fail*100.0/e5_short_total_fails,1), "%)");
        if (entryStats.se5_stale_signal > 0)
            Print("  Stale Signal: ", entryStats.se5_stale_signal, " (", DoubleToString(entryStats.se5_stale_signal*100.0/e5_short_total_fails,1), "%)");
    }

    Print("");
    Print("=== END FILTER ANALYSIS ===");
    Print("");
    
    // Return overall win rate as optimization criterion
    return overallWinRate;
}

//+------------------------------------------------------------------+
//| MONITORING & ALERT FUNCTIONS (from v1.7.52x - NO EMOJIS)       |
//+------------------------------------------------------------------+

// ===== Alert helper functions moved to Alerts/TradeAlerts.mqh =====
// - GetMarketStatusText()
// - GetMomentumStatusText()
// - GetEABlockReasonText()
// - CheckAndSendEMACrossAlert()
// - SendEMA75TouchSetupAlert()

// ===== Entry statistics helpers moved to Alerts/TradeAlerts.mqh =====
// - GetEntrySuccessRate()
// - GetTopEntryFailure()

void TrackEntryAttempt(string entryType, bool success, string failReason = "") {
    // Track attempts and success
    if (entryType == "L-E1") {
        entryStats.le1_attempts++;
        if (success) entryStats.le1_success++;
        else {
            if (failReason == "no_cross") entryStats.le1_no_cross++;
            else if (failReason == "mtf") entryStats.le1_mtf_fail++;
            else if (failReason == "momentum") entryStats.le1_momentum_fail++;
            else if (failReason == "conviction") entryStats.le1_conviction_fail++;
            else if (failReason == "trend_quality") entryStats.le1_trend_quality_fail++;
            else if (failReason == "htf_trend") entryStats.le1_htf_trend_fail++;
        }
    }
    else if (entryType == "S-E1") {
        entryStats.se1_attempts++;
        if (success) entryStats.se1_success++;
        else {
            if (failReason == "no_cross") entryStats.se1_no_cross++;
            else if (failReason == "mtf") entryStats.se1_mtf_fail++;
            else if (failReason == "momentum") entryStats.se1_momentum_fail++;
            else if (failReason == "conviction") entryStats.se1_conviction_fail++;
            else if (failReason == "trend_quality") entryStats.se1_trend_quality_fail++;
            else if (failReason == "htf_trend") entryStats.se1_htf_trend_fail++;
        }
    }
    else if (entryType == "L-E2") {
        entryStats.le2_attempts++;
        if (success) entryStats.le2_success++;
        else {
            if (failReason == "no_touch") entryStats.le2_no_touch++;
            else if (failReason == "htf_trend") entryStats.le2_htf_trend_fail++;
            else if (failReason == "mtf") entryStats.le2_mtf_fail++;
            else if (failReason == "momentum") entryStats.le2_momentum_fail++;
            else if (failReason == "volume") entryStats.le2_volume_fail++;
            else if (failReason == "conviction") entryStats.le2_conviction_fail++;
            else if (failReason == "trend_quality") entryStats.le2_trend_quality_fail++;
        }
    }
    else if (entryType == "S-E2") {
        entryStats.se2_attempts++;
        if (success) entryStats.se2_success++;
        else {
            if (failReason == "no_touch") entryStats.se2_no_touch++;
            else if (failReason == "htf_trend") entryStats.se2_htf_trend_fail++;
            else if (failReason == "mtf") entryStats.se2_mtf_fail++;
            else if (failReason == "momentum") entryStats.se2_momentum_fail++;
            else if (failReason == "volume") entryStats.se2_volume_fail++;
            else if (failReason == "conviction") entryStats.se2_conviction_fail++;
            else if (failReason == "trend_quality") entryStats.se2_trend_quality_fail++;
        }
    }
    else if (entryType == "L-E3") {
        entryStats.le3_attempts++;
        if (success) entryStats.le3_success++;
        else {
            if (failReason == "trend_context") entryStats.le3_trend_context_fail++;
            else if (failReason == "ema9_m3" || failReason == "ema12_m3" || failReason == "ema8_m3" || failReason == "ema10_m3") entryStats.le3_ema10_m3_fail++;
            else if (failReason == "ema9_m1" || failReason == "ema12_m1" || failReason == "ema8_m1" || failReason == "ema8_breakout" || failReason == "ema10_m1" || failReason == "ema10_breakout") entryStats.le3_ema10_m1_fail++;
            else if (failReason == "extreme_distance") entryStats.le3_extreme_distance_fail++;
            else if (failReason == "conviction") entryStats.le3_conviction_fail++;
            else if (failReason == "trend_quality") entryStats.le3_trend_quality_fail++;
            else if (failReason == "di_reversal") entryStats.le3_di_reversal_fail++;
        }
    }
    else if (entryType == "S-E3") {
        entryStats.se3_attempts++;
        if (success) entryStats.se3_success++;
        else {
            if (failReason == "trend_context") entryStats.se3_trend_context_fail++;
            else if (failReason == "ema9_m3" || failReason == "ema12_m3" || failReason == "ema8_m3" || failReason == "ema10_m3") entryStats.se3_ema10_m3_fail++;
            else if (failReason == "ema9_m1" || failReason == "ema12_m1" || failReason == "ema8_m1" || failReason == "ema8_breakout" || failReason == "ema10_m1" || failReason == "ema10_breakout") entryStats.se3_ema10_m1_fail++;
            else if (failReason == "extreme_distance") entryStats.se3_extreme_distance_fail++;
            else if (failReason == "conviction") entryStats.se3_conviction_fail++;
            else if (failReason == "trend_quality") entryStats.se3_trend_quality_fail++;
            else if (failReason == "di_reversal") entryStats.se3_di_reversal_fail++;
        }
    }
    else if (entryType == "L-E4") {
        entryStats.le4_attempts++;
        if (success) entryStats.le4_success++;
        else {
            if (failReason == "no_cross") entryStats.le4_no_cross++;
            else if (failReason == "sideway") entryStats.le4_sideway_fail++;
            else if (failReason == "htf_trend") entryStats.le4_htf_trend_fail++;
            else if (failReason == "mtf" || failReason == "ema_m1" || failReason == "ema_alignment" || failReason == "price_position" || failReason == "m5_di") entryStats.le4_mtf_fail++;
            else if (failReason == "momentum") entryStats.le4_momentum_fail++;
            else if (failReason == "conviction") entryStats.le4_conviction_fail++;
            else if (failReason == "trend_quality") entryStats.le4_trend_quality_fail++;
            else if (failReason == "thin_cloud") entryStats.le4_thin_cloud++;
            else if (failReason == "tenkan_kijun") entryStats.le4_tenkan_kijun++;
            else if (failReason == "chikou_blocked") entryStats.le4_chikou_blocked++;
        }
    }
    else if (entryType == "S-E4") {
        entryStats.se4_attempts++;
        if (success) entryStats.se4_success++;
        else {
            if (failReason == "no_cross") entryStats.se4_no_cross++;
            else if (failReason == "sideway") entryStats.se4_sideway_fail++;
            else if (failReason == "htf_trend") entryStats.se4_htf_trend_fail++;
            else if (failReason == "mtf" || failReason == "ema_m1" || failReason == "ema_alignment" || failReason == "price_position" || failReason == "m5_di") entryStats.se4_mtf_fail++;
            else if (failReason == "momentum") entryStats.se4_momentum_fail++;
            else if (failReason == "conviction") entryStats.se4_conviction_fail++;
            else if (failReason == "trend_quality") entryStats.se4_trend_quality_fail++;
            else if (failReason == "thin_cloud") entryStats.se4_thin_cloud++;
            else if (failReason == "tenkan_kijun") entryStats.se4_tenkan_kijun++;
            else if (failReason == "chikou_blocked") entryStats.se4_chikou_blocked++;
        }
    }
    else if (entryType == "L-E5") {
        entryStats.le5_attempts++;
        if (success) entryStats.le5_success++;
        else {
            if (failReason == "sideway") entryStats.le5_sideway_fail++;
            else if (failReason == "stale_signal") entryStats.le5_stale_signal++;
        }
    }
    else if (entryType == "S-E5") {
        entryStats.se5_attempts++;
        if (success) entryStats.se5_success++;
        else {
            if (failReason == "sideway") entryStats.se5_sideway_fail++;
            else if (failReason == "stale_signal") entryStats.se5_stale_signal++;
        }
    }
}
