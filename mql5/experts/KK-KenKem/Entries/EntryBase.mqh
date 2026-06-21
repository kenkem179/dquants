//+------------------------------------------------------------------+
//| EntryBase.mqh - Abstract base class for all entry types         |
//| Phase 1.1: OOP Foundation - Entry Detection & Adaptive Params   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef ENTRYBASE_MQH
#define ENTRYBASE_MQH

// Forward declarations
#include "../Core/GlobalState.mqh"
#include "../Config/InputParams.mqh"
#include "../Utils/Helpers.mqh"
#include "../Entries/EntryHelpers.mqh"

//+------------------------------------------------------------------+
//| DetectionResult: Struct for entry detection results             |
//+------------------------------------------------------------------+
struct DetectionResult {
    bool detected;
    bool isLong;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    ENTRY_TYPE entryType;       // ENTRY_L_E1, ENTRY_S_E1, etc.
    double rawSLDistancePips;
    double bufferedSLDistancePips;
    string reason;              // Why detected or why skipped
    int convictionScore;
    bool isHighRisk;
    bool isLowConfidence;       // Low confidence setup flag
    string lowConfidenceReason; // Why low confidence
    int trendQualityScore;      // Cached score from detection (avoid recalculating)
};

double CalculateBufferedStopWithSpread(bool isLong, double entryPrice, double structuredStop,
                                       double spreadMultiplier, double &rawSLDistancePips,
                                       double &bufferedSLDistancePips) {
    rawSLDistancePips = 0.0;
    bufferedSLDistancePips = 0.0;

    double finalStop = structuredStop;
    double rawDistancePrice = MathAbs(entryPrice - structuredStop);
    rawSLDistancePips = rawDistancePrice / pipSize;

    int spreadPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    double minDistancePrice = MathMax(0.0, spreadMultiplier) * spreadPoints * _Point;

    if (minDistancePrice > 0.0 && rawDistancePrice < minDistancePrice) {
        finalStop = isLong ? entryPrice - minDistancePrice : entryPrice + minDistancePrice;
    }

    bufferedSLDistancePips = MathAbs(entryPrice - finalStop) / pipSize;

    return finalStop;
}

//+------------------------------------------------------------------+
//| EntryBase: Abstract base class for E1, E2, E3 entries          |
//+------------------------------------------------------------------+
class EntryBase {
protected:
    //--------------------------------------------------------------------
    // ADAPTIVE CONFIGURATION (per entry instance)
    //--------------------------------------------------------------------
    // Coordinate Descent: Adjust ONE group per cycle for clear attribution
    // 4 GROUPS: Entry → Setup → Profit Taking → Loss Protection
    // Full cycle: 4 x 15 trades = 60 trades (~30 trading days)
    enum ADAPT_TARGET {
        ADAPT_ENTRY_QUALITY = 0,    // Group 1: minADX, minDISpread (which trades to take)
        ADAPT_TRADE_SETUP,          // Group 2: atrMultiplier, rewardRatio, rewardRatioSideway (initial SL/TP)
        ADAPT_PROFIT_TAKING,        // Group 3: partialTPTrigger, partialTPRatio, maxTPExtensions (maximize profits)
        ADAPT_LOSS_PROTECTION       // Group 4: trailingFactor, breakevenBuffer, earlyCutSLRatio (minimize losses)
    };
    
    struct AdaptiveConfig {
        bool isActive;
        datetime lastAdjustment;
        int adjustmentCycle;
        ADAPT_TARGET nextTarget;  // Which parameter to adjust next
        
        // Per-entry adaptive timing (different entries have different trade frequencies)
        int adaptiveMinTradesFirst;     // Min trades before first adjustment (default from global)
        int adaptiveCheckInterval;       // Check every N trades (default from global)
        int adaptiveMaxDaysBetween;      // Max days between adjustments (default from global)
        
        // Performance tracking
        int tradeCount;
        int winCount;
        double winrate;
        double avgPnL;
        double avgRR_achieved;
        int consecutiveWins;
        int consecutiveLosses;
        
        // BASELINE VALUES (original input params - never changed, used for bounded adaptation)
        double baselineRewardRatio;
        double baselineRewardRatioSideway;
        double baselinePartialTPRatio;
        double baselineMinADX;
        double baselineMinDISpread;
        double baselineAtrMultiplier;
        double baselineTrailingFactor;
        double baselineBreakevenBuffer;
        double baselineEarlyCutSLRatio;
        int baselineMaxTPExtensions;
        
        // ADAPTIVE: Entry Filters (ADX/DI thresholds)
        double minADX;
        double maxADX;              // For E3 counter-trend
        double minDISpread;
        double highRiskMinADX;
        double highRiskMinDISpread;
        
        // ADAPTIVE: Take Profit (RR and Partial TP)
        double rewardRatio;
        double rewardRatioSideway;
        double partialTPTrigger;
        double partialTPRatio;
        
        // FIXED (not adaptive - read from input params)
        double atrMultiplier;           // SL calculation (ATR multiplier)
        double emaDistancePips;         // SL EMA distance
        bool useATRBased;               // Use ATR for SL
        double minSLSpreadMultiplier;   // SL spread buffer
        int maxTPExtensions;            // TP extensions
        double trailingFactor;          // Trailing SL
        double breakevenBuffer;         // Breakeven trigger
        bool useADXFilter;              // ADX filter for trailing
        double earlyCutSLRatio;         // Early cut exit
        int adxPeriodForExit;           // ADX period for exit
        double minADXToHold;            // Min ADX to hold position
        bool enableLadderedExtensions;  // Ladder mode
        double ladderStage1Multiplier;
        double ladderStage2Multiplier;
        double ladderStage3Multiplier;
        double ladderStage1TrailRatio;
        double ladderStage2TrailRatio;
        double ladderStage3TrailRatio;
    };
    
    AdaptiveConfig m_config;
    
    //--------------------------------------------------------------------
    // STATIC PROPERTIES (set once, don't adapt)
    //--------------------------------------------------------------------
    string m_entryName;             // "E1", "E2", "E3"
    ENTRY_TYPE m_entryTypeEnum;     // ENTRY_L_E1, ENTRY_S_E1, etc.
    bool m_isEnabled;               // ENABLE_E1_ENTRIES, etc.
    DetectionResult m_lastDetection;  // Last detection result
    
    //--------------------------------------------------------------------
    // CONDITION TRACKING (for statistics/reporting)
    //--------------------------------------------------------------------
    struct ConditionLog {
        int totalChecks;
        int passedAll;
        int failedMomentum;
        int failedADX;
        int failedDISpread;
        int failedHTFVeto;
        int failedConviction;
        int failedRiskManagement;
        int failedSession;
    };
    
    struct PerformanceStats {
        // Basic metrics
        int totalTrades;
        int winCount;
        int lossCount;
        double totalPnL;
        double winrate;
        
        // SL performance tracking
        int slHits;                    // How many times SL was hit
        double avgLossPips;            // Average loss in pips when SL hit
        double slHitRate;              // slHits / totalTrades
        double totalLossPips;          // Sum of all losses in pips
        
        // TP performance tracking
        int tpHits;                    // How many times TP was hit
        double avgWinPips;             // Average win in pips when TP hit
        double avgRR_achieved;         // Average actual RR when closed
        double avgRR_best;             // Average best RR reached during trade
        double avgDrawbackFromBest;    // Average % given back from best price
        double totalWinPips;           // Sum of all wins in pips
        
        // SL Cap tracking (NEW)
        int slCapped;                  // How many times SL hit the cap
        int slCappedWins;              // Capped trades that won
        int slCappedLosses;            // Capped trades that lost
        double avgPipsWhenCapped;      // Average SL distance when cap applied
        double totalCappedPips;        // Sum of SL distances when capped
        
        // Partial TP tracking (NEW)
        int partialsTaken;             // How many partial TPs executed
        int partialThenTPHit;          // Partial → Full TP hit
        int partialThenSLHit;          // Partial → Stopped out
        int partialThenReversed;       // Partial → Price reversed significantly
        double avgPnLWithPartial;      // Average PnL when partial taken
        double avgPnLWithoutPartial;   // Simulated PnL if held full position
        double totalPartialPnL;        // Sum of PnL from partial TPs
        
        // TP Extension tracking (NEW)
        int extensionsAttempted;       // How many times TP was extended
        int extensionsSuccessful;      // Extended TP was hit
        int extensionsFailed;          // Price reversed after extension
        double avgPipsGainedFromExtension;  // Average extra pips from extensions
        double avgPipsLostFromExtension;    // Average pips lost from extensions
        int maxExtensionsReached;      // How often hit max extension limit
        double totalExtensionPips;     // Sum of pips gained/lost from extensions
        
        // Trailing SL tracking (NEW)
        int trailingSLHits;            // How many times trailing SL was hit
        int trailingThenReversed;      // Would have hit TP without trailing
        int trailingSaved;             // Trailing SL saved from larger loss
        double avgPnLWhenTrailed;      // Average PnL when trailing SL hit
        double totalTrailingPnL;       // Sum of PnL from trailing SL hits
        
        // Breakeven tracking (NEW)
        int breakevenHits;             // How many times BE was hit
        int breakevenWins;             // BE hit then went to TP
        int breakevenLosses;           // BE hit and closed at BE
        
        // Volatility context (NEW)
        double avgVolatility;          // Average ATR during trades
        double totalVolatility;        // Sum of ATR values
        
        // Timestamps
        datetime lastAdaptation;       // Last time parameters were adapted
        datetime firstTrade;           // First trade timestamp
        datetime lastTrade;            // Most recent trade timestamp
    };
    
    ConditionLog m_conditionStats;
    PerformanceStats m_stats;

public:
    //--------------------------------------------------------------------
    // CONSTRUCTOR
    //--------------------------------------------------------------------
    EntryBase(string entryName, ENTRY_TYPE entryType, bool isEnabled) {
        m_entryName = entryName;
        m_entryTypeEnum = entryType;
        m_isEnabled = isEnabled;
        
        // Initialize stats
        ZeroMemory(m_conditionStats);
        ZeroMemory(m_stats);
        ZeroMemory(m_config);
        
        // Initialize coordinate descent (start with Group 1)
        m_config.nextTarget = ADAPT_ENTRY_QUALITY;
        
        // NOTE: Cannot call InitializeDefaults() here (pure virtual function)
        // Derived classes must call it in their constructor
    }
    
    virtual ~EntryBase() {}
    
    //--------------------------------------------------------------------
    // PUBLIC INTERFACE
    //--------------------------------------------------------------------
    
    // Load adaptive parameters from persistent storage
    virtual bool LoadAdaptiveParams() {
        if(!m_config.isActive) return false;
        
        // Include account ID to differentiate between different broker accounts
        long accountId = AccountInfoInteger(ACCOUNT_LOGIN);
        string filename = "KenKem_Adaptive_" + m_entryName + "_" + _Symbol + "_" + IntegerToString(accountId) + ".txt";
        int handle = FileOpen(filename, FILE_READ|FILE_TXT);
        
        if(handle == INVALID_HANDLE) {
            if(showDebug) Print("[", m_entryName, "] No existing adaptive params file");
            return false;
        }
        
        while(!FileIsEnding(handle)) {
            string line = FileReadString(handle);
            if(StringLen(line) == 0) continue;
            
            string parts[];
            int count = StringSplit(line, '=', parts);
            if(count != 2) continue;
            
            string key = parts[0];
            double value = StringToDouble(parts[1]);
            
            // Parse and apply parameters (must match keys in SaveAdaptiveParams)
            if(key == "minADX") m_config.minADX = value;
            else if(key == "minDISpread") m_config.minDISpread = value;
            else if(key == "rewardRatio") m_config.rewardRatio = value;
            else if(key == "highRiskMinADX") m_config.highRiskMinADX = value;
            else if(key == "highRiskMinDISpread") m_config.highRiskMinDISpread = value;
            else if(key == "partialTPTrigger") m_config.partialTPTrigger = value;
            else if(key == "partialTPRatio") m_config.partialTPRatio = value;
            // Group 2: Trade Setup
            else if(key == "atrMultiplier") m_config.atrMultiplier = value;
            else if(key == "rewardRatioSideway") m_config.rewardRatioSideway = value;
            // Group 3: Profit Taking
            else if(key == "maxTPExtensions") m_config.maxTPExtensions = (int)value;
            // Group 4: Loss Protection
            else if(key == "trailingFactor") m_config.trailingFactor = value;
            else if(key == "breakevenBuffer") m_config.breakevenBuffer = value;
            else if(key == "earlyCutSLRatio") m_config.earlyCutSLRatio = value;
        }
        
        FileClose(handle);
        if(showDebug) Print("[", m_entryName, "] Loaded adaptive params from ", filename);
        return true;
    }
    
    // Save adaptive parameters to persistent storage
    // NOTE: We SAVE in backtesting mode to "pre-train" params for production
    // But we DON'T LOAD in backtesting mode (see KenKemExpert.mq5 OnInit)
    // This gives honest backtest results while still providing trained params for deployment
    virtual void SaveAdaptiveParams(int skippedTotal = 0, int skippedWins = 0, int skippedLosses = 0) {
        if(!m_config.isActive) return;
        
        // Recalculate all derived metrics with final trade counts
        CalculateDerivedMetrics();
        
        // ATOMIC WRITE: Write to .tmp file first, then rename
        // Include account ID to differentiate between different broker accounts
        long accountId = AccountInfoInteger(ACCOUNT_LOGIN);
        string filename = "KenKem_Adaptive_" + m_entryName + "_" + _Symbol + "_" + IntegerToString(accountId) + ".txt";
        string tmpFilename = "KenKem_Adaptive_" + m_entryName + "_" + _Symbol + "_" + IntegerToString(accountId) + ".tmp";
        
        int handle = FileOpen(tmpFilename, FILE_WRITE|FILE_TXT);
        
        if(handle == INVALID_HANDLE) {
            Print("[", m_entryName, "] Failed to save adaptive params: ", GetLastError());
            return;
        }
        
        // Write header
        FileWriteString(handle, "# KenKem Adaptive Params - " + m_entryName + "\n");
        FileWriteString(handle, "symbol=" + _Symbol + "\n");
        FileWriteString(handle, "timestamp=" + TimeToString(TimeCurrent()) + "\n\n");
        
        // Write performance stats
        FileWriteString(handle, "[Performance]\n");
        FileWriteString(handle, "tradeCount=" + IntegerToString(m_stats.totalTrades) + "\n");
        FileWriteString(handle, "winCount=" + IntegerToString(m_stats.winCount) + "\n");
        FileWriteString(handle, "lossCount=" + IntegerToString(m_stats.lossCount) + "\n");
        FileWriteString(handle, "winrate=" + DoubleToString(GetWinrate(), 4) + "\n");
        FileWriteString(handle, "totalPnL=" + DoubleToString(m_stats.totalPnL, 2) + "\n\n");
        
        FileWriteString(handle, "[SL_Performance]\n");
        FileWriteString(handle, "slHits=" + IntegerToString(m_stats.slHits) + "\n");
        FileWriteString(handle, "avgLossPips=" + DoubleToString(m_stats.avgLossPips, 2) + "\n");
        FileWriteString(handle, "slHitRate=" + DoubleToString(m_stats.slHitRate, 4) + "\n");
        FileWriteString(handle, "slCapped=" + IntegerToString(m_stats.slCapped) + "\n");
        FileWriteString(handle, "slCappedWins=" + IntegerToString(m_stats.slCappedWins) + "\n");
        FileWriteString(handle, "slCappedLosses=" + IntegerToString(m_stats.slCappedLosses) + "\n");
        FileWriteString(handle, "avgPipsWhenCapped=" + DoubleToString(m_stats.avgPipsWhenCapped, 2) + "\n\n");
        
        FileWriteString(handle, "[TP_Performance]\n");
        FileWriteString(handle, "tpHits=" + IntegerToString(m_stats.tpHits) + "\n");
        FileWriteString(handle, "avgWinPips=" + DoubleToString(m_stats.avgWinPips, 2) + "\n");
        FileWriteString(handle, "avgRR_achieved=" + DoubleToString(m_stats.avgRR_achieved, 3) + "\n");
        FileWriteString(handle, "avgRR_best=" + DoubleToString(m_stats.avgRR_best, 3) + "\n");
        FileWriteString(handle, "avgDrawbackFromBest=" + DoubleToString(m_stats.avgDrawbackFromBest, 4) + "\n\n");
        
        FileWriteString(handle, "[PartialTP_Performance]\n");
        FileWriteString(handle, "partialsTaken=" + IntegerToString(m_stats.partialsTaken) + "\n");
        FileWriteString(handle, "partialThenTPHit=" + IntegerToString(m_stats.partialThenTPHit) + "\n");
        FileWriteString(handle, "partialThenSLHit=" + IntegerToString(m_stats.partialThenSLHit) + "\n");
        FileWriteString(handle, "partialThenReversed=" + IntegerToString(m_stats.partialThenReversed) + "\n");
        FileWriteString(handle, "avgPnLWithPartial=" + DoubleToString(m_stats.avgPnLWithPartial, 2) + "\n");
        FileWriteString(handle, "avgPnLWithoutPartial=" + DoubleToString(m_stats.avgPnLWithoutPartial, 2) + "\n\n");
        
        FileWriteString(handle, "[TPExtension_Performance]\n");
        FileWriteString(handle, "extensionsAttempted=" + IntegerToString(m_stats.extensionsAttempted) + "\n");
        FileWriteString(handle, "extensionsSuccessful=" + IntegerToString(m_stats.extensionsSuccessful) + "\n");
        FileWriteString(handle, "extensionsFailed=" + IntegerToString(m_stats.extensionsFailed) + "\n");
        FileWriteString(handle, "avgPipsGainedFromExtension=" + DoubleToString(m_stats.avgPipsGainedFromExtension, 2) + "\n");
        FileWriteString(handle, "avgPipsLostFromExtension=" + DoubleToString(m_stats.avgPipsLostFromExtension, 2) + "\n");
        FileWriteString(handle, "maxExtensionsReached=" + IntegerToString(m_stats.maxExtensionsReached) + "\n\n");
        
        FileWriteString(handle, "[TrailingSL_Performance]\n");
        FileWriteString(handle, "trailingSLHits=" + IntegerToString(m_stats.trailingSLHits) + "\n");
        FileWriteString(handle, "trailingThenReversed=" + IntegerToString(m_stats.trailingThenReversed) + "\n");
        FileWriteString(handle, "trailingSaved=" + IntegerToString(m_stats.trailingSaved) + "\n");
        FileWriteString(handle, "avgPnLWhenTrailed=" + DoubleToString(m_stats.avgPnLWhenTrailed, 2) + "\n\n");
        
        FileWriteString(handle, "[Breakeven_Performance]\n");
        FileWriteString(handle, "breakevenHits=" + IntegerToString(m_stats.breakevenHits) + "\n");
        FileWriteString(handle, "breakevenWins=" + IntegerToString(m_stats.breakevenWins) + "\n");
        FileWriteString(handle, "breakevenLosses=" + IntegerToString(m_stats.breakevenLosses) + "\n\n");
        
        FileWriteString(handle, "[Volatility_Context]\n");
        FileWriteString(handle, "avgVolatility=" + DoubleToString(m_stats.avgVolatility, 3) + "\n\n");
        
        // Write skipped trade analysis (Phase 3.5 - reuses existing trades[] array)
        FileWriteString(handle, "[SkippedTrade_Analysis]\n");
        FileWriteString(handle, "skippedTotal=" + IntegerToString(skippedTotal) + "\n");
        FileWriteString(handle, "skippedWins=" + IntegerToString(skippedWins) + "\n");
        FileWriteString(handle, "skippedLosses=" + IntegerToString(skippedLosses) + "\n");
        double skippedWinrate = (skippedTotal > 0) ? ((double)skippedWins / skippedTotal) : 0.0;
        FileWriteString(handle, "skippedWinrate=" + DoubleToString(skippedWinrate, 4) + "\n");
        FileWriteString(handle, "missedProfitable=" + IntegerToString(skippedWins) + "\n");
        FileWriteString(handle, "correctlySkipped=" + IntegerToString(skippedLosses) + "\n\n");
        
        // Write adaptive parameters (only the 3 categories being adapted)
        FileWriteString(handle, "[AdaptiveParams]\n");
        // Entry Filters (ADAPT_FILTERS)
        FileWriteString(handle, "minADX=" + DoubleToString(m_config.minADX, 2) + "\n");
        FileWriteString(handle, "minDISpread=" + DoubleToString(m_config.minDISpread, 2) + "\n");
        FileWriteString(handle, "highRiskMinADX=" + DoubleToString(m_config.highRiskMinADX, 2) + "\n");
        FileWriteString(handle, "highRiskMinDISpread=" + DoubleToString(m_config.highRiskMinDISpread, 2) + "\n");
        // Take Profit (ADAPT_REWARD_RATIO + ADAPT_PARTIAL_TP)
        FileWriteString(handle, "rewardRatio=" + DoubleToString(m_config.rewardRatio, 2) + "\n");
        FileWriteString(handle, "partialTPTrigger=" + DoubleToString(m_config.partialTPTrigger, 2) + "\n");
        FileWriteString(handle, "partialTPRatio=" + DoubleToString(m_config.partialTPRatio, 2) + "\n");
        // Group 2: Trade Setup (SL/TP initial placement)
        FileWriteString(handle, "atrMultiplier=" + DoubleToString(m_config.atrMultiplier, 2) + "\n");
        FileWriteString(handle, "rewardRatioSideway=" + DoubleToString(m_config.rewardRatioSideway, 2) + "\n");
        // Group 3: Profit Taking (maximize winners)
        FileWriteString(handle, "maxTPExtensions=" + IntegerToString(m_config.maxTPExtensions) + "\n");
        // Group 4: Loss Protection (minimize losses)
        FileWriteString(handle, "trailingFactor=" + DoubleToString(m_config.trailingFactor, 2) + "\n");
        FileWriteString(handle, "breakevenBuffer=" + DoubleToString(m_config.breakevenBuffer, 2) + "\n");
        FileWriteString(handle, "earlyCutSLRatio=" + DoubleToString(m_config.earlyCutSLRatio, 2) + "\n");
        
        FileClose(handle);
        
        // ATOMIC RENAME: Move tmp file to final location
        // Delete old file first, then rename (MQL5 doesn't have atomic rename)
        if(FileIsExist(filename)) FileDelete(filename);
        if(!FileMove(tmpFilename, 0, filename, 0)) {
            Print("[", m_entryName, "] Failed to rename tmp file: ", GetLastError());
            return;
        }
        
        if(showDebug) Print("[", m_entryName, "] Saved adaptive params to ", filename, " (atomic write)");
    }
    
    // Main entry detection logic (pure virtual - must override)
    virtual DetectionResult Detect() = 0;
    
    // Lightweight direction check for conflict detection (no full detection)
    // Returns true if potential entry would be LONG, false if SHORT
    // Used to check if opposing/same-direction trades are active before running full Detect()
    // Default implementation - derived classes should override with entry-specific logic
    virtual bool PeekDirection() {
        // Default: return true (LONG bias) - derived classes must override
        return true;
    }
    
    // Ichimoku Quality Filters - Reusable for E4
    // Validates cloud thickness, Tenkan/Kijun alignment, and Chikou clearance
    // Uses ATR-based thresholds to adapt to volatility (not fixed pips)
    bool CheckIchimokuQuality(bool isLong, string entryType,
                             double minCloudThicknessATR,
                             bool requireTenkanKijun, bool requireChikou) {
        // 1. CLOUD THICKNESS CHECK (prevent choppy/thin clouds) - HELPS PROFITABILITY
        if (minCloudThicknessATR > 0) {
            double currentCloudTop = MathMax(cache.ichimokuSpanA_M3_Current, cache.ichimokuSpanB_M3_Current);
            double currentCloudBottom = MathMin(cache.ichimokuSpanA_M3_Current, cache.ichimokuSpanB_M3_Current);
            double currentCloudThickness = currentCloudTop - currentCloudBottom;
            double minThickness = cache.atrM3 * minCloudThicknessATR;
            
            if (currentCloudThickness < minThickness) {
                if (showDebug) {
                    Print("[", m_entryName, "] ", entryType, " blocked: Thin cloud (", 
                          DoubleToString(currentCloudThickness / pipSize, 1), " pips < ",
                          DoubleToString(minThickness / pipSize, 1), " pips [", 
                          DoubleToString(minCloudThicknessATR, 2), "x ATR])");
                }
                TrackEntryAttempt(entryType, false, "thin_cloud");
                return false;
            }
        }
        
        // 2. TENKAN/KIJUN ALIGNMENT (momentum confirmation)
        if (requireTenkanKijun) {
            bool tkAligned = isLong ? (cache.ichimokuTenkan_M3 > cache.ichimokuKijun_M3) : 
                                     (cache.ichimokuTenkan_M3 < cache.ichimokuKijun_M3);
            if (!tkAligned) {
                if (showDebug) {
                    Print("[", m_entryName, "] ", entryType, " blocked: Tenkan/Kijun not aligned (T=",
                          DoubleToString(cache.ichimokuTenkan_M3, 2), " K=", 
                          DoubleToString(cache.ichimokuKijun_M3, 2), ")");
                }
                TrackEntryAttempt(entryType, false, "tenkan_kijun");
                return false;
            }
        }
        
        // 3. CHIKOU SPAN CLEARANCE (no resistance behind)
        if (requireChikou) {
            bool chikouClear = isLong ? (cache.ichimokuChikou_M3 > cache.priceM3_26BarsAgo) : 
                                        (cache.ichimokuChikou_M3 < cache.priceM3_26BarsAgo);
            if (!chikouClear) {
                if (showDebug) {
                    Print("[", m_entryName, "] ", entryType, " blocked: Chikou blocked (C=",
                          DoubleToString(cache.ichimokuChikou_M3, 2), " vs P26=", 
                          DoubleToString(cache.priceM3_26BarsAgo, 2), ")");
                }
                TrackEntryAttempt(entryType, false, "chikou_blocked");
                return false;
            }
        }
        
        return true;
    }
    
    // HTF Trend Alignment Check (M5/M15) - Reusable for E2/E3/E4
    // For trend-following (E2): Only enter if HTF trend matches entry direction
    // For counter-trend (E3): Only enter if HTF trend opposes entry direction (reversal setup)
    // Returns true if HTF alignment passes, false if blocked
    bool CheckHTFTrendAlignment(bool isLong, string entryType, bool requireHTF, int htfMode, 
                                bool blockStrongCounter, double strongCounterADX, bool isCounterTrend = false) {
        if (!requireHTF) return true;  // Feature disabled
        
        // Get M5 DI values (TF2 = index 2)
        double diPlusM5 = cache.diPlus[TF2];
        double diMinusM5 = cache.diMinus[TF2];
        double adxM5 = cache.adx[TF2];
        
        // Get M15 DI values (TF3 = index 3)
        double diPlusM15 = cache.diPlus[TF3];
        double diMinusM15 = cache.diMinus[TF3];
        double adxM15 = cache.adx[TF3];
        
        // BLOCK during strong counter-trend - trend-following entries fail when opposing strong trend
        if (blockStrongCounter && adxM15 >= strongCounterADX) {
            // For trend-following (E2): block if M15 trend opposes entry direction
            // For counter-trend (E3): block if M15 trend is too strong (reversal unlikely)
            bool m15OpposingTrend = isLong ? (diMinusM15 > diPlusM15) : (diPlusM15 > diMinusM15);
            
            if ((!isCounterTrend && m15OpposingTrend) || (isCounterTrend && !m15OpposingTrend)) {
                if (showDebug) {
                    Print("[", m_entryName, "] ", entryType, " blocked: Strong ", 
                          (isCounterTrend ? "trend" : "counter-trend"),
                          " (M15 ADX=", DoubleToString(adxM15, 1), " >= ", DoubleToString(strongCounterADX, 1), ")");
                }
                TrackEntryAttempt(entryType, false, "strong_counter");
                return false;
            }
        }
        
        // Check trend direction on each timeframe (only if ADX shows valid trend)
        bool m5Valid = (adxM5 >= ADX_LOW_THRESHOLD);
        bool m15Valid = (adxM15 >= ADX_LOW_THRESHOLD);
        
        bool m5Aligned = false;
        bool m15Aligned = false;
        
        if (isLong) {
            // For trend-following: want bullish HTF (DI+ > DI-)
            // For counter-trend: want bullish HTF to buy dip in uptrend
            if (m5Valid) m5Aligned = (diPlusM5 > diMinusM5);
            else m5Aligned = true;  // Ranging = neutral, allow
            
            if (m15Valid) m15Aligned = (diPlusM15 > diMinusM15);
            else m15Aligned = true;  // Ranging = neutral, allow
        } else {
            // For trend-following: want bearish HTF (DI- > DI+)
            // For counter-trend: want bearish HTF to sell rally in downtrend
            if (m5Valid) m5Aligned = (diMinusM5 > diPlusM5);
            else m5Aligned = true;  // Ranging = neutral, allow
            
            if (m15Valid) m15Aligned = (diMinusM15 > diPlusM15);
            else m15Aligned = true;  // Ranging = neutral, allow
        }
        
        // Apply alignment mode
        bool htfAligned = false;
        switch (htfMode) {
            case 0:  // M5 only
                htfAligned = m5Aligned;
                break;
            case 1:  // M5 OR M15 (default - more opportunities)
                htfAligned = m5Aligned || m15Aligned;
                break;
            case 2:  // M5 AND M15 (strictest - fewer but higher quality)
                htfAligned = m5Aligned && m15Aligned;
                break;
            default:
                htfAligned = m5Aligned || m15Aligned;
        }
        
        if (!htfAligned) {
            if (showDebug) {
                Print("[", m_entryName, "] ", entryType, " blocked: HTF not aligned (M5:", m5Aligned ? "OK" : "NO",
                      " M15:", m15Aligned ? "OK" : "NO", " mode=", htfMode, ")");
            }
            TrackEntryAttempt(entryType, false, "htf_trend");
            return false;
        }
        
        return true;
    }
    
    // Check all entry conditions with detailed logging
    virtual bool CheckEntryConditions(bool isLong, DetectionResult &result) {
        m_conditionStats.totalChecks++;
        result.reason = "";
        
        // TODO: Implement full condition checking
        // For now, just basic validation
        if (!m_isEnabled) {
            result.reason = "Entry type disabled";
            return false;
        }
        
        m_conditionStats.passedAll++;
        return true;
    }
    
    double ApplySpreadBuffer(bool isLong, double entryPrice, double structuredStop,
                             double &rawSLDistancePips, double &bufferedSLDistancePips) const {
        return CalculateBufferedStopWithSpread(isLong, entryPrice, structuredStop,
                                               m_config.minSLSpreadMultiplier,
                                               rawSLDistancePips, bufferedSLDistancePips);
    }
    
    // REMOVED: ApplySLCapping() - SL capping removed per user request
    // ATR-based SL calculation still available but no hard caps applied

    double CalculateStopLoss(bool isLong, double currentPrice, double recentHigh, double recentLow,
                             int emaReference, string entryLabel, int entryType,
                             double &rawSLDistancePips, double &bufferedSLDistancePips) {
        double emaValue = GetEMA(TF0, emaReference, ENTRY_SHIFT);
        return CalculateStopLossWithCustomEMA(isLong, currentPrice, recentHigh, recentLow, emaValue, entryLabel, entryType,
                                              rawSLDistancePips, bufferedSLDistancePips);
    }
    
    // Overload: Calculate SL with a custom EMA level (price value, not period)
    // P1: Now includes ATR-based arbitration - intelligent choice between structure and ATR SL
    // entryType: 1=E1, 2=E2, 3=E3 (E3 has own ATR SL logic, won't use this)
    double CalculateStopLossWithCustomEMA(bool isLong, double currentPrice, double recentHigh, double recentLow,
                                          double customEMALevel, string entryLabel, int entryType,
                                          double &rawSLDistancePips, double &bufferedSLDistancePips) {
        double baseSL = isLong ? MathMin(recentLow, customEMALevel)
                               : MathMax(recentHigh, customEMALevel);

        double structuredStop = isLong ? baseSL - SL_EMA_DISTANCE * pipSize
                                       : baseSL + SL_EMA_DISTANCE * pipSize;
        
        // P1: ATR vs Structure SL Arbitration (per-entry settings)
        // Uses ATR as CAP (prevents too wide SL) and FLOOR (prevents too tight SL)
        bool useAtrArbitration = (entryType == 1) ? E1_USE_ATR_SL_ARBITRATION : E2_USE_ATR_SL_ARBITRATION;
        double atrCapMult = (entryType == 1) ? E1_ATR_SL_CAP_MULTIPLIER : E2_ATR_SL_CAP_MULTIPLIER;
        double atrFloorMult = (entryType == 1) ? E1_ATR_SL_FLOOR_MULTIPLIER : E2_ATR_SL_FLOOR_MULTIPLIER;
        
        if (useAtrArbitration && cache.atrM1 > 0) {
            double structureDistPips = MathAbs(currentPrice - structuredStop) / pipSize;
            double atrPips = cache.atrM1 / pipSize;
            double atrCapPips = atrPips * atrCapMult;    // Max SL from ATR
            double atrFloorPips = atrPips * atrFloorMult; // Min SL from ATR
            
            double finalDistPips = structureDistPips;
            string arbitrationResult = "STRUCTURE";
            
            // CAP: If structure SL is too wide, use ATR cap
            if (structureDistPips > atrCapPips) {
                finalDistPips = atrCapPips;
                arbitrationResult = "ATR_CAP";
            }
            // FLOOR: If result is too tight, use ATR floor
            if (finalDistPips < atrFloorPips) {
                finalDistPips = atrFloorPips;
                arbitrationResult = "ATR_FLOOR";
            }
            
            // Recalculate stop if arbitration changed it
            if (finalDistPips != structureDistPips) {
                structuredStop = isLong ? currentPrice - (finalDistPips * pipSize)
                                        : currentPrice + (finalDistPips * pipSize);
                if (showDebug) {
                    Print("[ATR ARBITRATION] ", entryLabel, " ", arbitrationResult,
                          ": Structure=", DoubleToString(structureDistPips, 1), "pips",
                          " ATR=", DoubleToString(atrPips, 1), "pips",
                          " Cap=", DoubleToString(atrCapPips, 1), "pips",
                          " Floor=", DoubleToString(atrFloorPips, 1), "pips",
                          " -> Final=", DoubleToString(finalDistPips, 1), "pips");
                }
            }
        }

        double bufferedStop = ApplySpreadBuffer(isLong, currentPrice, structuredStop,
                                                rawSLDistancePips, bufferedSLDistancePips);
        
        return bufferedStop;
    }
    
    // Calculate maximum take profit for this entry
    virtual double CalculateMaxTP(bool isLong, double entryPrice, double stopLoss) {
        // TODO: Implement adaptive TP calculation
        // For now, use existing logic
        return 0.0;
    }
    
    //--------------------------------------------------------------------
    // GETTERS (for TradeManager)
    //--------------------------------------------------------------------
    double GetPartialTPTrigger() const { return m_config.partialTPTrigger; }
    double GetPartialTPRatio() const { return m_config.partialTPRatio; }
    double GetTrailingFactor() const { return m_config.trailingFactor; }
    double GetBreakevenBuffer() const { return m_config.breakevenBuffer; }
    // TP extension trigger/pips removed - use GetTPExtensionTriggerPips(type) and GetTPExtensionPips(type) from Helpers.mqh
    int GetMaxTPExtensions() const { return m_config.maxTPExtensions; }
    double GetEarlyCutRatio() const { return m_config.earlyCutSLRatio; }
    int GetADXPeriodForExit() const { return m_config.adxPeriodForExit; }
    double GetMinADX() const { return m_config.minADX; }
    double GetRewardRatio() const { return m_config.rewardRatio; }
    int GetTradeCount() const { return m_stats.totalTrades; }
    double GetWinrate() const { 
        if(m_stats.totalTrades == 0) return 0.0;
        return (double)m_stats.winCount / (double)m_stats.totalTrades;
    }
    
    // Phase 2: Laddered extension getters
    bool GetEnableLadderedExtensions() const { return m_config.enableLadderedExtensions; }
    double GetLadderStage1Multiplier() const { return m_config.ladderStage1Multiplier; }
    double GetLadderStage2Multiplier() const { return m_config.ladderStage2Multiplier; }
    double GetLadderStage3Multiplier() const { return m_config.ladderStage3Multiplier; }
    double GetLadderStage1TrailRatio() const { return m_config.ladderStage1TrailRatio; }
    double GetLadderStage2TrailRatio() const { return m_config.ladderStage2TrailRatio; }
    double GetLadderStage3TrailRatio() const { return m_config.ladderStage3TrailRatio; }

    //--------------------------------------------------------------------
    // ENTRY-SPECIFIC CONFIG GETTERS (Phase: Entry Encapsulation)
    // Override in Entry1-4 to return entry-specific values.
    // Replaces scattered IsE*Entry() if/else chains across the codebase.
    //--------------------------------------------------------------------
    virtual double GetRRBoostMultiplier() const { return 1.02; }
    virtual double GetRewardRatioSideway() const { return m_config.rewardRatioSideway; }
    virtual bool GetUsesDetectionRR() const { return false; }
    virtual bool IsCounterTrend() const { return false; }

    // Conviction & HTF
    virtual bool GetUseConvictionScoring() const { return false; }
    virtual bool GetUseHTFVeto() const { return false; }
    virtual int GetConvictionThreshold() const { return 5; }

    // High-risk entry config
    virtual bool GetAcceptHighRisk() const { return false; }
    virtual int GetHighRiskMomentumCheck() const { return 0; }
    virtual double GetHighRiskADXThreshold() const { return m_config.highRiskMinADX; }
    virtual double GetHighRiskMinDISpread() const { return m_config.highRiskMinDISpread; }

    // Risk & lot sizing
    virtual double GetLotMultiplier() const { return 1.0; }
    virtual double GetMaxLossRatio() const { return COMMON_MAX_RISK_PER_TRADE; }
    virtual bool GetVolLotAdjEnabled() const { return false; }

    // Recovery
    virtual bool GetRecoveryLadderEnabled() const { return false; }
    virtual int GetRecoveryBoostThreshold() const { return 0; }

    // Exit config
    virtual bool GetEnableScoreDropExit() const { return false; }
    virtual int GetScoreDropThreshold() const { return 3; }
    virtual bool GetEnableDIFlipExit() const { return false; }
    virtual bool GetExitInIchiCloud() const { return false; }
    virtual bool GetEnablePanicADXExit() const { return true; }
    virtual double GetPanicMinSLUsedRatio() const { return PANIC_MIN_SL_USED_RATIO; }

    //--------------------------------------------------------------------
    // PERFORMANCE TRACKING METHODS (Phase 1 - Harmless Data Collection)
    //--------------------------------------------------------------------
    
    // Track SL hit event (metrics only - trade counting done by UpdatePerformance)
    void TrackSLHit(double lossPips, double currentATR, bool wasCapped) {
        // NOTE: totalTrades/lossCount incremented by UpdatePerformance to avoid double counting
        m_stats.slHits++;
        m_stats.totalLossPips += lossPips;
        m_stats.totalVolatility += currentATR;
        
        if (wasCapped) {
            m_stats.totalCappedPips += lossPips;
        }
        
        // Update averages
        if (m_stats.slHits > 0) {
            m_stats.avgLossPips = m_stats.totalLossPips / m_stats.slHits;
            m_stats.slHitRate = (double)m_stats.slHits / MathMax(1, m_stats.totalTrades);
        }
        if (m_stats.slCapped > 0) {
            m_stats.avgPipsWhenCapped = m_stats.totalCappedPips / m_stats.slCapped;
        }
    }
    
    // Track TP hit event (metrics only - trade counting done by UpdatePerformance)
    void TrackTPHit(double winPips, double rrAchieved, double rrBest, double drawbackPct) {
        // NOTE: totalTrades/winCount incremented by UpdatePerformance to avoid double counting
        m_stats.tpHits++;
        m_stats.totalWinPips += winPips;
        
        // Update RR tracking
        double totalRR_achieved = m_stats.avgRR_achieved * MathMax(1, m_stats.tpHits - 1) + rrAchieved;
        double totalRR_best = m_stats.avgRR_best * MathMax(1, m_stats.tpHits - 1) + rrBest;
        double totalDrawback = m_stats.avgDrawbackFromBest * MathMax(1, m_stats.tpHits - 1) + drawbackPct;
        
        m_stats.avgRR_achieved = totalRR_achieved / m_stats.tpHits;
        m_stats.avgRR_best = totalRR_best / m_stats.tpHits;
        m_stats.avgDrawbackFromBest = totalDrawback / m_stats.tpHits;
        
        // Update averages
        if (m_stats.tpHits > 0) {
            m_stats.avgWinPips = m_stats.totalWinPips / m_stats.tpHits;
        }
    }
    
    // Track partial TP event
    void TrackPartialTP(double partialPnL, double simulatedFullPnL) {
        m_stats.partialsTaken++;
        m_stats.totalPartialPnL += partialPnL;
        
        // Update running average
        double totalWithPartial = m_stats.avgPnLWithPartial * MathMax(1, m_stats.partialsTaken - 1) + partialPnL;
        double totalWithoutPartial = m_stats.avgPnLWithoutPartial * MathMax(1, m_stats.partialsTaken - 1) + simulatedFullPnL;
        
        m_stats.avgPnLWithPartial = totalWithPartial / m_stats.partialsTaken;
        m_stats.avgPnLWithoutPartial = totalWithoutPartial / m_stats.partialsTaken;
    }
    
    // Track partial TP outcome (called when trade closes after partial)
    void TrackPartialOutcome(bool hitTP, bool hitSL, bool reversed) {
        if (hitTP) m_stats.partialThenTPHit++;
        if (hitSL) m_stats.partialThenSLHit++;
        if (reversed) m_stats.partialThenReversed++;
    }
    
    // Track TP extension event
    void TrackTPExtension(bool wasSuccessful, double pipsGained, bool hitMaxExtensions) {
        m_stats.extensionsAttempted++;
        
        if (wasSuccessful) {
            m_stats.extensionsSuccessful++;
            m_stats.totalExtensionPips += pipsGained;
        } else {
            m_stats.extensionsFailed++;
            m_stats.totalExtensionPips -= MathAbs(pipsGained); // Lost pips
        }
        
        if (hitMaxExtensions) {
            m_stats.maxExtensionsReached++;
        }
        
        // Update averages
        if (m_stats.extensionsSuccessful > 0) {
            m_stats.avgPipsGainedFromExtension = m_stats.totalExtensionPips / m_stats.extensionsSuccessful;
        }
        if (m_stats.extensionsFailed > 0) {
            m_stats.avgPipsLostFromExtension = MathAbs(m_stats.totalExtensionPips) / m_stats.extensionsFailed;
        }
    }
    
    // Track trailing SL event
    void TrackTrailingSL(double pnl, bool wouldHaveHitTP, bool savedFromLoss) {
        m_stats.trailingSLHits++;
        m_stats.totalTrailingPnL += pnl;
        
        if (wouldHaveHitTP) m_stats.trailingThenReversed++;
        if (savedFromLoss) m_stats.trailingSaved++;
        
        // Update average
        if (m_stats.trailingSLHits > 0) {
            m_stats.avgPnLWhenTrailed = m_stats.totalTrailingPnL / m_stats.trailingSLHits;
        }
    }
    
    // Track breakeven event
    void TrackBreakeven(bool thenWon, bool thenLost) {
        m_stats.breakevenHits++;
        if (thenWon) m_stats.breakevenWins++;
        if (thenLost) m_stats.breakevenLosses++;
    }
    
    // Track SL cap outcome
    void TrackSLCapOutcome(bool won) {
        m_stats.slCapped++;  // Count total capped trades (both wins and losses)
        if (won) {
            m_stats.slCappedWins++;
        } else {
            m_stats.slCappedLosses++;
        }
    }
    
    // Update volatility context
    void UpdateVolatilityContext(double currentATR) {
        m_stats.totalVolatility += currentATR;
        if (m_stats.totalTrades > 0) {
            m_stats.avgVolatility = m_stats.totalVolatility / m_stats.totalTrades;
        }
    }
    
    // Wilson Confidence Interval for winrate (robust for small samples)
    // Returns lower bound of 95% CI for proportion
    double WilsonScoreLowerBound(int successes, int total, double z = 1.96) {
        if (total == 0) return 0.0;
        
        double p = (double)successes / total;
        double z2 = z * z;
        double denominator = 1 + z2 / total;
        double center = (p + z2 / (2 * total)) / denominator;
        double margin = (z * MathSqrt((p * (1 - p) / total) + (z2 / (4 * total * total)))) / denominator;
        
        return MathMax(0.0, center - margin);
    }
    
    // Wilson Confidence Interval - Upper Bound
    double WilsonScoreUpperBound(int successes, int total, double z = 1.96) {
        if (total == 0) return 1.0;
        
        double p = (double)successes / total;
        double z2 = z * z;
        double denominator = 1 + z2 / total;
        double center = (p + z2 / (2 * total)) / denominator;
        double margin = (z * MathSqrt((p * (1 - p) / total) + (z2 / (4 * total * total)))) / denominator;
        
        return MathMin(1.0, center + margin);
    }
    
    // Calculate derived metrics (called before adaptation)
    void CalculateDerivedMetrics() {
        if (m_stats.totalTrades > 0) {
            m_stats.winrate = (double)m_stats.winCount / m_stats.totalTrades;
            m_stats.slHitRate = (double)m_stats.slHits / m_stats.totalTrades;
            m_stats.avgVolatility = m_stats.totalVolatility / m_stats.totalTrades;
        }
    }
    
    // Update performance metrics (called by TradeManager after trade close)
    virtual void UpdatePerformance(bool isWin, double pnl, double rrAchieved) {
        m_stats.totalTrades++;
        m_stats.totalPnL += pnl;
        
        if (isWin) {
            m_stats.winCount++;
        } else {
            m_stats.lossCount++;
        }
        
        // FORCED LOGGING - Always print to verify this is being called
        Print("*** [", m_entryName, "] UpdatePerformance #", m_stats.totalTrades, 
              " | Win:", isWin, " | PnL:", DoubleToString(pnl, 2), 
              " | Adaptive:", m_config.isActive ? "ON" : "OFF");
        
        // Check if adaptation needed (every N trades - PER ENTRY TYPE)
        int checkInterval = (m_config.adaptiveCheckInterval > 0) ? m_config.adaptiveCheckInterval : ADAPTIVE_CHECK_EVERY_N_TRADES;
        if (m_config.isActive && m_stats.totalTrades % checkInterval == 0) {
            Print("*** [", m_entryName, "] TRIGGERING ADAPTIVE at trade #", m_stats.totalTrades, " (interval: ", checkInterval, ")");
            AdaptParameters();
        }
    }
    
    // Get condition statistics for reporting
    ConditionLog GetConditionStats() const { return m_conditionStats; }
    
    void ResetConditionStats() { 
        ZeroMemory(m_conditionStats);
    }
    
protected:
    //--------------------------------------------------------------------
    // PROTECTED HELPER METHODS
    //--------------------------------------------------------------------
    
    // Initialize default parameters from input variables (must override per entry type)
    virtual void InitializeDefaults() = 0;
    
    // Save baseline values AFTER InitializeDefaults() sets them (call from derived constructor)
    void SaveBaselines() {
        // Group 1: Entry Quality
        m_config.baselineMinADX = m_config.minADX;
        m_config.baselineMinDISpread = m_config.minDISpread;
        // Group 2: Trade Setup
        m_config.baselineAtrMultiplier = m_config.atrMultiplier;
        m_config.baselineRewardRatio = m_config.rewardRatio;
        m_config.baselineRewardRatioSideway = m_config.rewardRatioSideway;
        // Group 3: Profit Taking
        m_config.baselinePartialTPRatio = m_config.partialTPRatio;
        m_config.baselineMaxTPExtensions = m_config.maxTPExtensions;
        // Group 4: Loss Protection
        m_config.baselineTrailingFactor = m_config.trailingFactor;
        m_config.baselineBreakevenBuffer = m_config.breakevenBuffer;
        m_config.baselineEarlyCutSLRatio = m_config.earlyCutSLRatio;
        
        if(showDebug) Print("[", m_entryName, "] Baselines saved: ADX=", DoubleToString(m_config.baselineMinADX, 1),
                           ", RR=", DoubleToString(m_config.baselineRewardRatio, 2),
                           ", ATRMult=", DoubleToString(m_config.baselineAtrMultiplier, 2),
                           ", Trail=", DoubleToString(m_config.baselineTrailingFactor, 2));
    }
    
    // Validate and clamp parameters to safe bounds (all 4 adaptive groups)
    void ValidateAndClampParams() {
        // Group 1: Entry Quality
        m_config.minADX = MathMax(ADAPTIVE_ADX_ABSOLUTE_MIN, MathMin(ADAPTIVE_ADX_ABSOLUTE_MAX, m_config.minADX));
        m_config.minDISpread = MathMax(ADAPTIVE_DI_SPREAD_ABSOLUTE_MIN, MathMin(ADAPTIVE_DI_SPREAD_ABSOLUTE_MAX, m_config.minDISpread));
        
        // Group 2: Trade Setup
        m_config.atrMultiplier = MathMax(ADAPTIVE_ATR_MULT_ABSOLUTE_MIN, MathMin(ADAPTIVE_ATR_MULT_ABSOLUTE_MAX, m_config.atrMultiplier));
        m_config.rewardRatio = MathMax(ADAPTIVE_RR_ABSOLUTE_MIN, MathMin(ADAPTIVE_RR_ABSOLUTE_MAX, m_config.rewardRatio));
        double minRRSideway = m_config.baselineRewardRatioSideway * ADAPTIVE_RR_SIDEWAY_MIN_PCT;
        double maxRRSideway = m_config.baselineRewardRatioSideway * ADAPTIVE_RR_SIDEWAY_MAX_PCT;
        m_config.rewardRatioSideway = MathMax(minRRSideway, MathMin(maxRRSideway, m_config.rewardRatioSideway));
        
        // Group 3: Profit Taking
        m_config.partialTPTrigger = MathMax(ADAPTIVE_PARTIAL_TRIGGER_MIN, MathMin(ADAPTIVE_PARTIAL_TRIGGER_MAX, m_config.partialTPTrigger));
        m_config.partialTPRatio = MathMax(0.10, MathMin(0.60, m_config.partialTPRatio)); // 10-60% partial
        m_config.maxTPExtensions = MathMax(ADAPTIVE_MAX_TP_EXT_ABSOLUTE_MIN, MathMin(ADAPTIVE_MAX_TP_EXT_ABSOLUTE_MAX, m_config.maxTPExtensions));
        
        // Group 4: Loss Protection
        m_config.trailingFactor = MathMax(ADAPTIVE_TRAILING_ABSOLUTE_MIN, MathMin(ADAPTIVE_TRAILING_ABSOLUTE_MAX, m_config.trailingFactor));
        m_config.breakevenBuffer = MathMax(ADAPTIVE_BREAKEVEN_ABSOLUTE_MIN, MathMin(ADAPTIVE_BREAKEVEN_ABSOLUTE_MAX, m_config.breakevenBuffer));
        m_config.earlyCutSLRatio = MathMax(ADAPTIVE_EARLY_CUT_ABSOLUTE_MIN, MathMin(ADAPTIVE_EARLY_CUT_ABSOLUTE_MAX, m_config.earlyCutSLRatio));
    }
    
    //--------------------------------------------------------------------
    // PHASE 1 SAFETY FEATURES: Wilson CI, Drawdown Guard, Baseline Revert
    //--------------------------------------------------------------------
    
    // Wilson score interval for binomial proportion (more accurate than normal approximation for small samples)
    // Returns lower and upper bounds of confidence interval for winrate
    struct WilsonInterval {
        double lower;
        double upper;
    };
    
    WilsonInterval CalculateWilsonCI(int successes, int trials) {
        WilsonInterval interval;
        interval.lower = 0.0;
        interval.upper = 1.0;
        
        if(trials <= 0) return interval;
        
        double p = (double)successes / (double)trials;
        double confidence = ADAPTIVE_WILSON_CI_CONFIDENCE;  // From InputParams.mqh
        double z = 1.96;  // Default 95% confidence (z-score)
        
        if(confidence >= 0.99) z = 2.576;      // 99% confidence
        else if(confidence >= 0.95) z = 1.96;  // 95% confidence
        else if(confidence >= 0.90) z = 1.645; // 90% confidence
        
        double n = (double)trials;
        double z_squared = z * z;
        
        // Wilson score interval formula
        double denominator = 1.0 + z_squared / n;
        double center = (p + z_squared / (2.0 * n)) / denominator;
        double margin = z * MathSqrt((p * (1.0 - p) / n) + (z_squared / (4.0 * n * n))) / denominator;
        
        interval.lower = center - margin;
        interval.upper = center + margin;
        
        // Clamp to [0, 1]
        interval.lower = MathMax(0.0, interval.lower);
        interval.upper = MathMin(1.0, interval.upper);
        
        return interval;
    }
    
    // Check if drawdown guard should trigger (from peak balance)
    bool IsDrawdownGuardTriggered(double &currentDD) {
        double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        
        // Use peak balance as baseline (from GlobalState.mqh)
        if(peakAccountBalance <= 0 || currentBalance > peakAccountBalance) {
            currentDD = 0.0;
            return false;
        }
        
        // Calculate drawdown percentage from peak balance
        double loss = peakAccountBalance - currentBalance;
        currentDD = loss / peakAccountBalance;
        
        // Trigger based on configured threshold (default 10%)
        if(currentDD >= ADAPTIVE_DRAWDOWN_TRIGGER_PCT) {
            Print("[", m_entryName, "] DRAWDOWN GUARD TRIGGERED: ", 
                  DoubleToString(currentDD * 100, 2), "% loss from peak $", 
                  DoubleToString(peakAccountBalance, 2), 
                  " (Current: $", DoubleToString(currentBalance, 2), 
                  " | Trigger: ", DoubleToString(ADAPTIVE_DRAWDOWN_TRIGGER_PCT * 100, 1), "%)");
            return true;
        }
        
        return false;
    }
    
    // Revert all adaptive parameters to baseline and pause adaptations
    void RevertToBaseline(string reason = "Drawdown Guard") {
        Print("[", m_entryName, "] REVERTING TO BASELINE - Reason: ", reason);
        Print("[", m_entryName, "]   Before: RR=", DoubleToString(m_config.rewardRatio, 2),
              " | PartialTP=", DoubleToString(m_config.partialTPRatio, 2),
              " | MinADX=", DoubleToString(m_config.minADX, 2));
        
        // Revert ADAPTIVE parameters to baseline using configurable defaults from InputParams.mqh
        m_config.rewardRatio = m_config.baselineRewardRatio;
        m_config.rewardRatioSideway = m_config.baselineRewardRatio * ADAPTIVE_REVERT_SIDEWAY_RR_PCT;
        m_config.partialTPRatio = m_config.baselinePartialTPRatio;
        m_config.partialTPTrigger = ADAPTIVE_REVERT_PARTIAL_TRIGGER;
        m_config.minADX = m_config.baselineMinADX;
        m_config.minDISpread = m_config.baselineMinDISpread;
        m_config.highRiskMinADX = m_config.baselineMinADX + ADAPTIVE_REVERT_HIGH_RISK_ADX_ADD;
        m_config.highRiskMinDISpread = m_config.baselineMinDISpread + ADAPTIVE_REVERT_HIGH_RISK_DI_ADD;
        
        // NOTE: SL params (maxSLPips, etc.) are FIXED and don't need reverting
        
        // Reset adaptation state
        m_config.adjustmentCycle = 0;
        m_config.nextTarget = ADAPT_ENTRY_QUALITY;  // Start from Group 1
        
        // Validate all params
        ValidateAndClampParams();
        
        // Save to file
        SaveAdaptiveParams();
        
        Print("[", m_entryName, "]   After:  RR=", DoubleToString(m_config.rewardRatio, 2),
              " | PartialTP=", DoubleToString(m_config.partialTPRatio, 2),
              " | MinADX=", DoubleToString(m_config.minADX, 2));
        
        // Telegram alert
        string msg = "ADAPTIVE PARAMETERS RESET FOR " + m_entryName + "\n\n";
        msg += "Reason: " + reason + "\n\n";
        msg += "All parameters reverted to baseline values.\n";
        msg += "Adaptation cycle reset to 0.\n\n";
        msg += "System will adapt conservatively from this point.";
        SendSystemMessage(msg, true);  // Admin-only
    }
    
    // Adaptive parameter adjustment logic (called every 15 trades)
    virtual void AdaptParameters() {
        if (!m_config.isActive) return;
        
        // SAFETY: Minimum trades before first adjustment (PER ENTRY TYPE)
        int minTradesFirst = (m_config.adaptiveMinTradesFirst > 0) ? m_config.adaptiveMinTradesFirst : ADAPTIVE_MIN_TRADES_FIRST;
        if (m_stats.totalTrades < minTradesFirst) {
            if(showDebug) Print("[", m_entryName, "] AdaptParameters() - Need ", minTradesFirst, "+ trades (current: ", m_stats.totalTrades, ")");
            return;
        }
        
        // PHASE 1 SAFETY: Drawdown Guard - Revert to baseline and pause if in significant DD
        double currentDD = 0.0;
        if(IsDrawdownGuardTriggered(currentDD)) {
            RevertToBaseline("Drawdown Guard - " + DoubleToString(currentDD * 100, 1) + "% DD");
            
            // Pause adaptations for configured number of trades
            int pauseDays = ADAPTIVE_PAUSE_TRADES_AFTER_REVERT * ADAPTIVE_MAX_DAYS_BETWEEN_ADJUSTMENTS;
            m_config.lastAdjustment = TimeCurrent() + (pauseDays * 86400);
            
            if(showDebug) Print("[", m_entryName, "] Adaptations PAUSED for ", 
                               ADAPTIVE_PAUSE_TRADES_AFTER_REVERT, " trades due to drawdown");
            return;
        }
        
        // DUAL TRIGGER: Adjust if max days passed since last adjustment (prevents waiting forever on low volume) - PER ENTRY TYPE
        datetime currentTime = TimeCurrent();
        bool timeTriggered = false;
        int maxDaysBetween = (m_config.adaptiveMaxDaysBetween > 0) ? m_config.adaptiveMaxDaysBetween : ADAPTIVE_MAX_DAYS_BETWEEN_ADJUSTMENTS;
        int checkInterval = (m_config.adaptiveCheckInterval > 0) ? m_config.adaptiveCheckInterval : ADAPTIVE_CHECK_EVERY_N_TRADES;
        
        if (m_config.lastAdjustment > 0) {
            int daysSinceLastAdjustment = (int)((currentTime - m_config.lastAdjustment) / 86400);
            if (daysSinceLastAdjustment >= maxDaysBetween) {
                timeTriggered = true;
                if(showDebug) Print("[", m_entryName, "] TIME TRIGGER: ", daysSinceLastAdjustment, " days since last adjustment (max: ", maxDaysBetween, ")");
            }
        }
        
        // Skip if neither trade count nor time trigger met - PER ENTRY TYPE
        if (!timeTriggered && m_stats.totalTrades % checkInterval != 0) return;
        
        if(showDebug) Print("[", m_entryName, "] AdaptParameters() - Cycle #", m_config.adjustmentCycle, 
                           " with ", m_stats.totalTrades, " trades (DD: ", DoubleToString(currentDD * 100, 1), "%)");
        
        // COORDINATE DESCENT: Adjust ONE group per cycle for clear attribution
        // 4 GROUPS: Entry Quality -> Trade Setup -> Profit Taking -> Loss Protection
        switch(m_config.nextTarget) {
            case ADAPT_ENTRY_QUALITY:
                AdaptEntryFilters();
                if(showDebug) Print("[", m_entryName, "] Group 1 adjusted: Entry Quality (minADX, minDISpread)");
                break;
            case ADAPT_TRADE_SETUP:
                AdaptTradeSetup();
                if(showDebug) Print("[", m_entryName, "] Group 2 adjusted: Trade Setup (atrMultiplier, rewardRatio, rewardRatioSideway)");
                break;
            case ADAPT_PROFIT_TAKING:
                AdaptProfitTaking();
                if(showDebug) Print("[", m_entryName, "] Group 3 adjusted: Profit Taking (partialTP, maxTPExtensions)");
                break;
            case ADAPT_LOSS_PROTECTION:
                AdaptLossProtection();
                if(showDebug) Print("[", m_entryName, "] Group 4 adjusted: Loss Protection (trailing, breakeven, earlyCut)");
                break;
        }
        
        // Move to next target (round-robin: 0->1->2->3->0)
        m_config.nextTarget = (ADAPT_TARGET)((m_config.nextTarget + 1) % 4);
        
        // Validate and clamp all parameters to safe ranges
        ValidateAndClampParams();
        
        m_config.lastAdjustment = TimeCurrent();
        m_config.adjustmentCycle++;
        
        // Save updated parameters
        SaveAdaptiveParams();
        
        if(showDebug) Print("[", m_entryName, "] AdaptParameters() - Cycle #", m_config.adjustmentCycle, " complete");
    }
    
    //--------------------------------------------------------------------
    // PHASE 3.1: Partial TP Ratio Adjustment (LOWEST RISK)
    //--------------------------------------------------------------------
    void AdaptPartialTPRatio() {
        // Skip if no partial TP data
        if (m_stats.partialsTaken < ADAPTIVE_MIN_PARTIAL_TP_SAMPLES) return;
        
        double pnlWithPartial = m_stats.avgPnLWithPartial;
        double pnlWithoutPartial = m_stats.avgPnLWithoutPartial;
        
        // Safety: Skip if data looks invalid
        if (pnlWithPartial <= 0 || pnlWithoutPartial <= 0) return;
        
        // Calculate performance difference
        double pnlRatio = pnlWithoutPartial / pnlWithPartial;
        double oldRatio = m_config.partialTPRatio;
        double oldTrigger = m_config.partialTPTrigger;
        
        // BOUNDS based on BASELINE from input parameters
        double minRatio = m_config.baselinePartialTPRatio * ADAPTIVE_PARTIAL_TP_MIN_PCT;
        double maxRatio = m_config.baselinePartialTPRatio * ADAPTIVE_PARTIAL_TP_MAX_PCT;
        double minTrigger = 0.60;  // Don't take partial too early
        double maxTrigger = 0.95;  // Don't wait too long
        
        // Decision logic: If not taking partial is significantly better
        if (pnlRatio > ADAPTIVE_PARTIAL_TP_THRESHOLD) {
            // Strategy 1: Delay the trigger (take partial later, closer to TP)
            m_config.partialTPTrigger = MathMin(maxTrigger, m_config.partialTPTrigger + ADAPTIVE_PARTIAL_TP_STEP);
            
            // Strategy 2: Reduce ratio (take less when we do take partial)
            m_config.partialTPRatio = MathMax(minRatio, m_config.partialTPRatio - ADAPTIVE_PARTIAL_TP_STEP);
            
            if(showDebug) Print("[", m_entryName, "] Partial TP: Without partial is ", DoubleToString(pnlRatio, 2), 
                               "x better → DELAY trigger ", DoubleToString(oldTrigger, 2), "→", DoubleToString(m_config.partialTPTrigger, 2),
                               " & REDUCE ratio ", DoubleToString(oldRatio, 2), "→", DoubleToString(m_config.partialTPRatio, 2));
        }
        // If taking partial is significantly better
        else if (pnlRatio < (1.0 / ADAPTIVE_PARTIAL_TP_THRESHOLD)) {
            // Strategy 1: Take partial earlier (more aggressive profit taking)
            m_config.partialTPTrigger = MathMax(minTrigger, m_config.partialTPTrigger - ADAPTIVE_PARTIAL_TP_STEP);
            
            // Strategy 2: Increase ratio (take more when we do take partial)
            m_config.partialTPRatio = MathMin(maxRatio, m_config.partialTPRatio + ADAPTIVE_PARTIAL_TP_STEP);
            
            if(showDebug) Print("[", m_entryName, "] Partial TP: With partial is ", DoubleToString(1/pnlRatio, 2), 
                               "x better → EARLIER trigger ", DoubleToString(oldTrigger, 2), "→", DoubleToString(m_config.partialTPTrigger, 2),
                               " & INCREASE ratio ", DoubleToString(oldRatio, 2), "→", DoubleToString(m_config.partialTPRatio, 2));
        }
        else {
            if(showDebug) Print("[", m_entryName, "] Partial TP: No significant difference (ratio=", 
                               DoubleToString(pnlRatio, 2), ") - keeping settings");
        }
    }
    
    //--------------------------------------------------------------------
    // PHASE 3.2: Reward Ratio Adjustment (LOW RISK)
    //--------------------------------------------------------------------
    void AdaptRewardRatio() {
        // Skip if insufficient TP data
        if (m_stats.tpHits < ADAPTIVE_MIN_TP_HIT_SAMPLES) return;
        
        double achievedRR = m_stats.avgRR_achieved;
        double targetRR = m_config.rewardRatio;
        
        // Safety: Skip if data looks invalid
        if (achievedRR <= 0 || targetRR <= 0) return;
        
        double rrRatio = achievedRR / targetRR;
        double oldRR = targetRR;
        
        // BOUNDS based on BASELINE from input parameters
        double minRR = m_config.baselineRewardRatio * ADAPTIVE_RR_MIN_PCT;
        double maxRR = m_config.baselineRewardRatio * ADAPTIVE_RR_MAX_PCT;
        
        // If consistently achieving MORE than target → INCREASE target
        if (rrRatio > ADAPTIVE_RR_THRESHOLD_HIGH) {
            // Increase reward ratio
            double adjustment = ADAPTIVE_RR_STEP;
            m_config.rewardRatio = MathMin(maxRR, m_config.rewardRatio + adjustment);
            
            if(showDebug) Print("[", m_entryName, "] Reward Ratio: Achieving ", DoubleToString(achievedRR, 2),
                               " vs target ", DoubleToString(oldRR, 2), " (", DoubleToString((rrRatio-1)*100, 1),
                               "% better) → INCREASE from ", DoubleToString(oldRR, 2),
                               " to ", DoubleToString(m_config.rewardRatio, 2),
                               " (baseline=", DoubleToString(m_config.baselineRewardRatio, 2), ")");
        }
        // If consistently achieving LESS than target → DECREASE target
        else if (rrRatio < ADAPTIVE_RR_THRESHOLD_LOW) {
            // Decrease reward ratio
            double adjustment = -ADAPTIVE_RR_STEP;
            m_config.rewardRatio = MathMax(minRR, m_config.rewardRatio + adjustment);
            
            if(showDebug) Print("[", m_entryName, "] Reward Ratio: Only achieving ", DoubleToString(achievedRR, 2),
                               " vs target ", DoubleToString(oldRR, 2), " (",DoubleToString((1-rrRatio)*100, 1),
                               "% worse) → DECREASE from ", DoubleToString(oldRR, 2),
                               " to ", DoubleToString(m_config.rewardRatio, 2),
                               " (baseline=", DoubleToString(m_config.baselineRewardRatio, 2), ")");
        }
        else {
            if(showDebug) Print("[", m_entryName, "] Reward Ratio: Achieving ", DoubleToString(achievedRR, 2),
                               " vs target ", DoubleToString(targetRR, 2), " (within 20%) - keeping at ",
                               DoubleToString(m_config.rewardRatio, 2));
        }
    }
    
    // REMOVED: AdaptSLCap() - SL capping removed from adaptive learning (use fixed input params)
    
    //--------------------------------------------------------------------
    // PHASE 3.5: Entry Filter Adjustment (HIGH RISK)
    //--------------------------------------------------------------------
    void AdaptEntryFilters() {
        // Skip if insufficient data
        if (m_stats.totalTrades < ADAPTIVE_MIN_TRADES_FOR_FILTERS) return;
        
        double currentWinrate = m_stats.winrate;
        double targetWinrate = GetTargetWinrate();
        
        // Safety: Skip if data looks invalid
        if (currentWinrate < 0 || targetWinrate <= 0) return;
        
        // PHASE 1 SAFETY: Use Wilson CI instead of raw winrate
        WilsonInterval winrateCI = CalculateWilsonCI(m_stats.winCount, m_stats.totalTrades);
        
        if(showDebug) Print("[", m_entryName, "] Winrate CI: ", 
                           DoubleToString(winrateCI.lower * 100, 1), "% - ", 
                           DoubleToString(winrateCI.upper * 100, 1), "% (point estimate: ",
                           DoubleToString(currentWinrate * 100, 1), "%)");
        
        double oldMinADX = m_config.minADX;
        double oldMinDISpread = m_config.minDISpread;
        
        // BOUNDS based on BASELINE from input parameters
        double minADX_floor = m_config.baselineMinADX * ADAPTIVE_FILTER_MIN_PCT;
        double minADX_ceil = m_config.baselineMinADX * ADAPTIVE_FILTER_MAX_PCT;
        double minDI_floor = m_config.baselineMinDISpread * ADAPTIVE_FILTER_MIN_PCT;
        double minDI_ceil = m_config.baselineMinDISpread * ADAPTIVE_FILTER_MAX_PCT;
        
        // Use upper bound of CI for tightening (conservative)
        // Use lower bound of CI for loosening (conservative)
        double threshold = ADAPTIVE_WILSON_CI_THRESHOLD;  // From InputParams.mqh
        
        // If upper CI bound is below target - TIGHTEN filters (be more selective)
        if (winrateCI.upper < (targetWinrate - threshold)) {
            double adxAdjustment = ADAPTIVE_ADX_FILTER_STEP;
            double diAdjustment = ADAPTIVE_DI_FILTER_STEP;
            
            m_config.minADX = MathMin(minADX_ceil, m_config.minADX + adxAdjustment);
            m_config.minDISpread = MathMin(minDI_ceil, m_config.minDISpread + diAdjustment);
            
            if(showDebug) Print("[", m_entryName, "] Filters: Winrate CI upper ", 
                               DoubleToString(winrateCI.upper * 100, 1), "% < target ", 
                               DoubleToString(targetWinrate * 100, 1), "% → TIGHTEN filters: ADX ",
                               DoubleToString(oldMinADX, 1), "→", DoubleToString(m_config.minADX, 1),
                               ", DI ", DoubleToString(oldMinDISpread, 1), "→", DoubleToString(m_config.minDISpread, 1));
        }
        // If lower CI bound is above target - LOOSEN filters (be less selective)
        else if (winrateCI.lower > (targetWinrate + threshold)) {
            double adxAdjustment = -ADAPTIVE_ADX_FILTER_STEP;
            double diAdjustment = -ADAPTIVE_DI_FILTER_STEP;
            
            m_config.minADX = MathMax(minADX_floor, m_config.minADX + adxAdjustment);
            m_config.minDISpread = MathMax(minDI_floor, m_config.minDISpread + diAdjustment);
            
            if(showDebug) Print("[", m_entryName, "] Filters: Winrate CI lower ", 
                               DoubleToString(winrateCI.lower * 100, 1), "% > target ", 
                               DoubleToString(targetWinrate * 100, 1), "% → LOOSEN filters: ADX ",
                               DoubleToString(oldMinADX, 1), "→", DoubleToString(m_config.minADX, 1),
                               ", DI ", DoubleToString(oldMinDISpread, 1), "→", DoubleToString(m_config.minDISpread, 1));
        }
        else {
            if(showDebug) Print("[", m_entryName, "] Filters: Winrate ", 
                               DoubleToString(currentWinrate * 100, 1), "% near target ",
                               DoubleToString(targetWinrate * 100, 1), "% - keeping filters");
        }
    }
    
    //--------------------------------------------------------------------
    // GROUP 2: Trade Setup Adjustment (atrMultiplier, rewardRatio, rewardRatioSideway)
    //--------------------------------------------------------------------
    void AdaptTradeSetup() {
        // Skip if insufficient TP data
        if (m_stats.tpHits < ADAPTIVE_MIN_TP_HIT_SAMPLES) return;
        
        double achievedRR = m_stats.avgRR_achieved;
        double targetRR = m_config.rewardRatio;
        
        // Safety: Skip if data looks invalid
        if (achievedRR <= 0 || targetRR <= 0) return;
        
        double rrRatio = achievedRR / targetRR;
        double oldRR = m_config.rewardRatio;
        double oldRRSideway = m_config.rewardRatioSideway;
        
        // BOUNDS based on BASELINE from input parameters
        double minRR = m_config.baselineRewardRatio * ADAPTIVE_RR_MIN_PCT;
        double maxRR = m_config.baselineRewardRatio * ADAPTIVE_RR_MAX_PCT;
        
        // If consistently achieving MORE than target -> INCREASE target
        if (rrRatio > ADAPTIVE_RR_THRESHOLD_HIGH) {
            m_config.rewardRatio = MathMin(maxRR, m_config.rewardRatio + ADAPTIVE_RR_STEP);
            // Sideway RR follows main RR proportionally
            m_config.rewardRatioSideway = m_config.rewardRatio * (m_config.baselineRewardRatioSideway / m_config.baselineRewardRatio);
            
            if(showDebug) Print("[", m_entryName, "] Trade Setup: RR achieved ", DoubleToString(achievedRR, 2),
                               " > target -> INCREASE RR to ", DoubleToString(m_config.rewardRatio, 2),
                               ", RR_Sideway to ", DoubleToString(m_config.rewardRatioSideway, 2));
        }
        // If consistently achieving LESS than target -> DECREASE target
        else if (rrRatio < ADAPTIVE_RR_THRESHOLD_LOW) {
            m_config.rewardRatio = MathMax(minRR, m_config.rewardRatio - ADAPTIVE_RR_STEP);
            m_config.rewardRatioSideway = m_config.rewardRatio * (m_config.baselineRewardRatioSideway / m_config.baselineRewardRatio);
            
            if(showDebug) Print("[", m_entryName, "] Trade Setup: RR achieved ", DoubleToString(achievedRR, 2),
                               " < target -> DECREASE RR to ", DoubleToString(m_config.rewardRatio, 2),
                               ", RR_Sideway to ", DoubleToString(m_config.rewardRatioSideway, 2));
        }
        else {
            if(showDebug) Print("[", m_entryName, "] Trade Setup: RR within threshold - no change");
        }
        
        // ATR Multiplier adjustment based on SL hit analysis
        // If avgLossPips is much higher than expected, tighten SL (reduce multiplier)
        // If avgLossPips is reasonable but winrate is low, widen SL (increase multiplier)
        // For now, keep ATR multiplier stable - tune manually based on backtest results
    }
    
    //--------------------------------------------------------------------
    // GROUP 3: Profit Taking Adjustment (partialTP, maxTPExtensions)
    //--------------------------------------------------------------------
    void AdaptProfitTaking() {
        // Partial TP adjustment
        if (m_stats.partialsTaken >= ADAPTIVE_MIN_PARTIAL_TP_SAMPLES) {
            double pnlWithPartial = m_stats.avgPnLWithPartial;
            double pnlWithoutPartial = m_stats.avgPnLWithoutPartial;
            
            if (pnlWithPartial > 0 && pnlWithoutPartial > 0) {
                double pnlRatio = pnlWithoutPartial / pnlWithPartial;
                double oldTrigger = m_config.partialTPTrigger;
                double oldRatio = m_config.partialTPRatio;
                
                // BOUNDS based on BASELINE
                double minRatio = m_config.baselinePartialTPRatio * ADAPTIVE_PARTIAL_TP_MIN_PCT;
                double maxRatio = m_config.baselinePartialTPRatio * ADAPTIVE_PARTIAL_TP_MAX_PCT;
                
                // If not taking partial is significantly better
                if (pnlRatio > ADAPTIVE_PARTIAL_TP_THRESHOLD) {
                    m_config.partialTPTrigger = MathMin(0.95, m_config.partialTPTrigger + ADAPTIVE_PARTIAL_TP_STEP);
                    m_config.partialTPRatio = MathMax(minRatio, m_config.partialTPRatio - ADAPTIVE_PARTIAL_TP_STEP);
                    if(showDebug) Print("[", m_entryName, "] Profit Taking: Delay partial, reduce ratio");
                }
                // If taking partial is significantly better
                else if (pnlRatio < (1.0 / ADAPTIVE_PARTIAL_TP_THRESHOLD)) {
                    m_config.partialTPTrigger = MathMax(0.55, m_config.partialTPTrigger - ADAPTIVE_PARTIAL_TP_STEP);
                    m_config.partialTPRatio = MathMin(maxRatio, m_config.partialTPRatio + ADAPTIVE_PARTIAL_TP_STEP);
                    if(showDebug) Print("[", m_entryName, "] Profit Taking: Earlier partial, increase ratio");
                }
            }
        }
        
        // TP Extensions adjustment based on extension success rate
        if (m_stats.extensionsAttempted >= 10) {
            double extSuccessRate = (double)m_stats.extensionsSuccessful / m_stats.extensionsAttempted;
            int oldMaxExt = m_config.maxTPExtensions;
            
            // If extensions are consistently successful, allow more
            if (extSuccessRate > 0.70 && m_stats.maxExtensionsReached > 3) {
                m_config.maxTPExtensions = MathMin(m_config.baselineMaxTPExtensions + 10, m_config.maxTPExtensions + 2);
                if(showDebug) Print("[", m_entryName, "] Profit Taking: Extensions successful, increasing max to ", m_config.maxTPExtensions);
            }
            // If extensions often fail, reduce limit
            else if (extSuccessRate < 0.40) {
                m_config.maxTPExtensions = MathMax(m_config.baselineMaxTPExtensions - 5, m_config.maxTPExtensions - 2);
                if(showDebug) Print("[", m_entryName, "] Profit Taking: Extensions failing, reducing max to ", m_config.maxTPExtensions);
            }
        }
    }
    
    //--------------------------------------------------------------------
    // GROUP 4: Loss Protection Adjustment (trailing, breakeven, earlyCut)
    //--------------------------------------------------------------------
    void AdaptLossProtection() {
        double currentWinrate = m_stats.winrate;
        double targetWinrate = GetTargetWinrate();
        
        // Trailing SL adjustment based on trailing hit outcomes
        if (m_stats.trailingSLHits >= 5) {
            double trailPnL = m_stats.avgPnLWhenTrailed;
            double oldTrail = m_config.trailingFactor;
            
            // If trailing is locking in good profits, tighten trail
            if (trailPnL > 0 && m_stats.trailingSaved > m_stats.trailingThenReversed) {
                m_config.trailingFactor = MathMax(ADAPTIVE_TRAILING_ABSOLUTE_MIN, m_config.trailingFactor - 0.03);
                if(showDebug) Print("[", m_entryName, "] Loss Protection: Trailing working, tightening to ", DoubleToString(m_config.trailingFactor, 2));
            }
            // If trailing is cutting winners short, loosen trail
            else if (m_stats.trailingThenReversed > m_stats.trailingSaved * 2) {
                m_config.trailingFactor = MathMin(ADAPTIVE_TRAILING_ABSOLUTE_MAX, m_config.trailingFactor + 0.03);
                if(showDebug) Print("[", m_entryName, "] Loss Protection: Trailing cutting winners, loosening to ", DoubleToString(m_config.trailingFactor, 2));
            }
        }
        
        // Breakeven adjustment based on BE outcomes
        if (m_stats.breakevenHits >= 10) {
            double beWinRate = (double)m_stats.breakevenWins / m_stats.breakevenHits;
            double oldBE = m_config.breakevenBuffer;
            
            // If BE is protecting well, keep tight
            if (beWinRate > 0.60) {
                // Good performance, slight tightening
                m_config.breakevenBuffer = MathMax(ADAPTIVE_BREAKEVEN_ABSOLUTE_MIN, m_config.breakevenBuffer - 0.005);
            }
            // If BE is getting hit and then reversing, widen buffer
            else if (beWinRate < 0.40) {
                m_config.breakevenBuffer = MathMin(ADAPTIVE_BREAKEVEN_ABSOLUTE_MAX, m_config.breakevenBuffer + 0.005);
            }
            if(showDebug && m_config.breakevenBuffer != oldBE) 
                Print("[", m_entryName, "] Loss Protection: BE buffer adjusted to ", DoubleToString(m_config.breakevenBuffer, 3));
        }
        
        // Early Cut adjustment based on loss sizes
        if (m_stats.slHits >= 10) {
            double avgLossPips = m_stats.avgLossPips;
            double oldEarlyCut = m_config.earlyCutSLRatio;
            
            // If average losses are large, cut earlier
            // (Lower ratio = cut earlier, closer to entry)
            if (avgLossPips > 50 && currentWinrate < targetWinrate) {
                m_config.earlyCutSLRatio = MathMax(ADAPTIVE_EARLY_CUT_ABSOLUTE_MIN, m_config.earlyCutSLRatio - 0.03);
                if(showDebug) Print("[", m_entryName, "] Loss Protection: Large losses, earlier cut at ", DoubleToString(m_config.earlyCutSLRatio, 2));
            }
            // If winrate is good but losses are small, can afford to wait longer
            else if (avgLossPips < 25 && currentWinrate > targetWinrate) {
                m_config.earlyCutSLRatio = MathMin(ADAPTIVE_EARLY_CUT_ABSOLUTE_MAX, m_config.earlyCutSLRatio + 0.02);
                if(showDebug) Print("[", m_entryName, "] Loss Protection: Good winrate, later cut at ", DoubleToString(m_config.earlyCutSLRatio, 2));
            }
        }
    }
    
    // Get target winrate (must override: E1/E2=55%, E3=65%)
    virtual double GetTargetWinrate() = 0;
};

#endif // ENTRYBASE_MQH
