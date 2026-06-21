//+------------------------------------------------------------------+
//| Entry3.mqh - E3 Counter-Trend Entry (Reversal Detection)        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef ENTRY3_MQH
#define ENTRY3_MQH

#include "EntryBase.mqh"

// E3-specific constants (EMA shift remains fixed; other values configurable via inputs)
#define E3_EMA_BAR_SHIFT 1
#define E3_M3_OHLC_CACHE_MAX 20
#define E3_M3_OHLC_CACHE_MIN 6
#define E3_M1_ROTATION_LOOKBACK 3

class Entry3 : public EntryBase {
private:
    // Cached indicator handles for performance (created once, reused)
    int m_rsiHandleM3;
    int m_adxHandleM3;
    int m_adxHandleH1;  // H1 ADX for stable trend anchor
    int m_emaHandleM1;  // M1 EMA for price confirmation
    bool m_handlesInitialized;
    
    // M3 bar caching - avoid recalculating on every M1 tick
    int m_lastM1BarForM3Cache;  // Track M1 bar count, recalc every 3 bars
    int m_cachedExhaustionScoreLong;
    int m_cachedExhaustionScoreShort;
    bool m_m3ConditionsMetLong;
    bool m_m3ConditionsMetShort;
    
    // Cached M3 OHLC for wick rejection (avoid 4 CopyBuffer calls)
    double m_cachedM3Open[E3_M3_OHLC_CACHE_MAX];
    double m_cachedM3High[E3_M3_OHLC_CACHE_MAX];
    double m_cachedM3Low[E3_M3_OHLC_CACHE_MAX];
    double m_cachedM3Close[E3_M3_OHLC_CACHE_MAX];
    bool m_m3OHLCCached;
    
    // Cached HTF decline bonus and regime gate state (recomputed on M3 bar close)
    int m_cachedHTFADXDeclineBonus;
    bool m_regimeGateMetLong;
    bool m_regimeGateMetShort;
    
public:
    Entry3() : EntryBase("E3", ENTRY_L_E3, ENABLE_E3_ENTRIES) {
        m_rsiHandleM3 = INVALID_HANDLE;
        m_adxHandleM3 = INVALID_HANDLE;
        m_adxHandleH1 = INVALID_HANDLE;
        m_emaHandleM1 = INVALID_HANDLE;
        m_handlesInitialized = false;
        m_lastM1BarForM3Cache = -999;  // Force first calculation
        m_cachedExhaustionScoreLong = -1;
        m_cachedExhaustionScoreShort = -1;
        m_m3ConditionsMetLong = false;
        m_m3ConditionsMetShort = false;
        m_m3OHLCCached = false;
        m_cachedHTFADXDeclineBonus = 0;
        m_regimeGateMetLong = true;
        m_regimeGateMetShort = true;
        InitializeDefaults();  // Call after base constructor completes
        SaveBaselines();  // Save original input values as baselines for adaptation
    }
    
    ~Entry3() {
        // Release indicator handles
        if (m_rsiHandleM3 != INVALID_HANDLE) IndicatorRelease(m_rsiHandleM3);
        if (m_adxHandleM3 != INVALID_HANDLE) IndicatorRelease(m_adxHandleM3);
        if (m_adxHandleH1 != INVALID_HANDLE) IndicatorRelease(m_adxHandleH1);
        if (m_emaHandleM1 != INVALID_HANDLE) IndicatorRelease(m_emaHandleM1);
    }
    
    // Initialize indicator handles (call once from OnInit)
    void InitIndicatorHandles() {
        if (m_handlesInitialized) return;
        m_rsiHandleM3 = iRSI(_Symbol, TF_ARRAY[TF1], 14, PRICE_CLOSE);
        m_adxHandleM3 = iADX(_Symbol, TF_ARRAY[TF1], 14);
        m_adxHandleH1 = iADX(_Symbol, TF_ARRAY[TF4], 14);  // H1 ADX for stable trend anchor
        m_emaHandleM1 = iMA(_Symbol, TF_ARRAY[TF0], E3_M1_PRICE_EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);  // M1 EMA for price confirmation
        m_handlesInitialized = true;
    }
    
    // Lightweight pre-check: called from main loop BEFORE Detect()
    // Updates M3 cache if needed, returns true if exhaustion is active
    bool ShouldCheckE3() {
        // Update M3 cache only on M3 bar close (once per 3 M1 bars)
        int currentM3BarIndex = currentBar / 3;
        int lastM3BarIndex = m_lastM1BarForM3Cache / 3;
        
        if (currentM3BarIndex != lastM3BarIndex || m_lastM1BarForM3Cache < 0) {
            UpdateM3Cache();
        }
        
        // Return true only if M3 exhaustion detected for at least one direction
        if (!E3_USE_EXHAUSTION_SCORING && !E3_ENABLE_REGIME_GATE) return true;  // No filtering if both disabled
        
        bool longReady = m_m3ConditionsMetLong && (!E3_ENABLE_REGIME_GATE || m_regimeGateMetLong);
        bool shortReady = m_m3ConditionsMetShort && (!E3_ENABLE_REGIME_GATE || m_regimeGateMetShort);
        return (longReady || shortReady);
    }
    
    // Lightweight direction check for E3 conflict detection (no full detection)
    // Returns true if potential E3 would be LONG, false if SHORT
    // Used to check if opposing-direction trend trades are active before running full Detect()
    bool PeekDirection() {
        // E3 is counter-trend - check which direction has exhaustion conditions met
        // If both are met, default to LONG (arbitrary choice, shouldn't happen often)
        if (m_m3ConditionsMetLong && (!E3_ENABLE_REGIME_GATE || m_regimeGateMetLong)) {
            return true;  // E3 LONG potential
        }
        if (m_m3ConditionsMetShort && (!E3_ENABLE_REGIME_GATE || m_regimeGateMetShort)) {
            return false;  // E3 SHORT potential
        }
        // Default to LONG if neither condition met (shouldn't be called in this case)
        return true;
    }
    
protected:
    virtual void InitializeDefaults() override {
        m_config.isActive = ENABLE_ADAPTIVE_E3;
        
        // E3 Adaptive timing (use global defaults - adjust after observing actual frequency)
        m_config.adaptiveMinTradesFirst = ADAPTIVE_MIN_TRADES_FIRST;
        m_config.adaptiveCheckInterval = ADAPTIVE_CHECK_EVERY_N_TRADES;
        m_config.adaptiveMaxDaysBetween = ADAPTIVE_MAX_DAYS_BETWEEN_ADJUSTMENTS;
        
        m_config.minADX = ADX_LOW_THRESHOLD;
        m_config.maxADX = E3_HIGH_RISK_MAX_ADX;
        m_config.minDISpread = E3_HIGH_RISK_MIN_DI_SPREAD;
        m_config.highRiskMinADX = E3_HIGH_RISK_MAX_ADX;
        m_config.highRiskMinDISpread = E3_HIGH_RISK_MIN_DI_SPREAD;
        // Stop Loss (per-entry ATR toggle - E3 benefits from ATR-based SL)
        m_config.atrMultiplier = E3_ATR_MULTIPLIER_SL;  // Per-entry multiplier (tighter for counter-trend)
        m_config.useATRBased = E3_USE_ATR_SL;  // Per-entry ATR SL setting
        m_config.minSLSpreadMultiplier = MIN_SL_SPREAD_MULT;
        m_config.rewardRatio = E3_RR;
        m_config.rewardRatioSideway = E3_RR_SIDEWAY;
        m_config.partialTPTrigger = E3_PARTIAL_TP_TRIGGER;
        m_config.partialTPRatio = E3_PARTIAL_TP_RATIO;
        // TP Extension (trigger/pips now use dynamic global values)
        m_config.maxTPExtensions = E3_MAX_TP_EXTENSIONS;
        m_config.trailingFactor = E3_TRAILING_SL_FACTOR;
        m_config.breakevenBuffer = E3_SL_TO_BREAKEVEN_BUFFER;
        m_config.earlyCutSLRatio = E3_EARLY_CUT_SL_RATIO;
        m_config.adxPeriodForExit = 14;
        
        // Phase 2: Laddered Extensions (E3 - Ultra-Conservative)
        m_config.enableLadderedExtensions = E3_ENABLE_LADDERED_EXTENSIONS;
        m_config.ladderStage1Multiplier = E3_LADDER_STAGE1_MULTIPLIER;
        m_config.ladderStage2Multiplier = E3_LADDER_STAGE2_MULTIPLIER;
        m_config.ladderStage3Multiplier = E3_LADDER_STAGE3_MULTIPLIER;
        m_config.ladderStage1TrailRatio = E3_LADDER_STAGE1_TRAIL_RATIO;
        m_config.ladderStage2TrailRatio = E3_LADDER_STAGE2_TRAIL_RATIO;
        m_config.ladderStage3TrailRatio = E3_LADDER_STAGE3_TRAIL_RATIO;
        
        ValidateAndClampParams();
    }
    
public:
    virtual DetectionResult Detect() override {
        DetectionResult result;
        result.detected = false;
        result.rawSLDistancePips = 0.0;
        result.bufferedSLDistancePips = 0.0;
        
        // NOTE: ShouldCheckE3() already called from main loop - M3 cache is fresh
        // This function only runs when M3 exhaustion is active
        
        // P0: Session loss limit (hard stop after N real losses)
        if (sessionLossCount >= MAX_SESSION_LOSSES) {
            return result;
        }
        
        // P0b: Session total trade limit (legacy, emergency brake)
        if (tradeSLTPCountInSession >= MAX_SLTP_COUNT_PER_SESSION) {
            return result;
        }
        
        // P1: M1 momentum confirmation - find precise entry timing
        if (!CheckM1MomentumConfirmation()) {
            // Track M1 rotation failure for whichever direction had exhaustion/regime alignment
            if (m_m3ConditionsMetLong && (!E3_ENABLE_REGIME_GATE || m_regimeGateMetLong)) {
                TrackEntryAttempt("L-E3", false, "di_reversal");
            }
            if (m_m3ConditionsMetShort && (!E3_ENABLE_REGIME_GATE || m_regimeGateMetShort)) {
                TrackEntryAttempt("S-E3", false, "di_reversal");
            }
            return result;  // M1 momentum not aligned yet
        }
        
        double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
        
        int checkOpenLE1, checkOpenSE1, checkOpenLE2, checkOpenSE2, checkOpenLE3, checkOpenSE3;
        CheckOpenPositions(checkOpenLE1, checkOpenSE1, checkOpenLE2, checkOpenSE2, checkOpenLE3, checkOpenSE3);
        
        // Try LONG first (only if exhaustion passed for long)
        if (checkOpenLE3 == -1 && m_m3ConditionsMetLong) {
            result = TryDetectLong(currentPrice, "L-E3");
        }
        
        // Try SHORT if LONG didn't detect (only if exhaustion passed for short)
        if (!result.detected && checkOpenSE3 == -1 && m_m3ConditionsMetShort) {
            result = TryDetectShort(currentPrice, "S-E3");
        }
        
        return result;
    }
    
    virtual double GetTargetWinrate() override { return 0.73; }
    
private:
    //--------------------------------------------------------------------
    // DETECTION HELPERS
    //--------------------------------------------------------------------
    DetectionResult TryDetectLong(double currentPrice, string entryType) {
        DetectionResult result;
        result.detected = false;
        
        // Note: UpdateM3Cache() and exhaustion check already done in Detect()
        
        bool isLowConfidence = false;
        string lowConfidenceReason = "";
        double recentExtreme = 0.0;
        
        if (CheckE3EntryConditions_Internal(true, currentPrice, entryType, recentExtreme, isLowConfidence, lowConfidenceReason)) {
            result.detected = true;
            result.isLong = true;
            result.entryPrice = currentPrice;
            
            // E3-specific ATR-based SL (tighter than E1/E2)
            double structuredStop = CalculateE3StopLoss(true, currentPrice, recentExtreme);
            result.stopLoss = ApplySpreadBuffer(true, currentPrice, structuredStop, result.rawSLDistancePips, result.bufferedSLDistancePips);
            
            // NOTE: No SL capping for E3 - let ATR-based SL work naturally

            int exhaustionScore = GetCachedExhaustionScore(true);
            result.takeProfit = CalculateTakeProfit(currentPrice, result.stopLoss, true, exhaustionScore);
            result.entryType = ENTRY_L_E3;
            result.isLowConfidence = isLowConfidence;
            result.lowConfidenceReason = lowConfidenceReason;
            
            //if(showDebug) Print("[E3] LONG detected at ", currentPrice);
        }
        
        return result;
    }
    
    DetectionResult TryDetectShort(double currentPrice, string entryType) {
        DetectionResult result;
        result.detected = false;
        
        // Note: UpdateM3Cache() and exhaustion check already done in Detect()
        
        bool isLowConfidence = false;
        string lowConfidenceReason = "";
        double recentExtreme = 0.0;
        
        if (CheckE3EntryConditions_Internal(false, currentPrice, entryType, recentExtreme, isLowConfidence, lowConfidenceReason)) {
            result.detected = true;
            result.isLong = false;
            result.entryPrice = currentPrice;
            
            // E3-specific ATR-based SL (tighter than E1/E2)
            double structuredStop = CalculateE3StopLoss(false, currentPrice, recentExtreme);
            result.stopLoss = ApplySpreadBuffer(false, currentPrice, structuredStop, result.rawSLDistancePips, result.bufferedSLDistancePips);
            
            // NOTE: No SL capping for E3 - let ATR-based SL work naturally

            int exhaustionScore = GetCachedExhaustionScore(false);
            result.takeProfit = CalculateTakeProfit(currentPrice, result.stopLoss, false, exhaustionScore);
            result.entryType = ENTRY_S_E3;
            result.isLowConfidence = isLowConfidence;
            result.lowConfidenceReason = lowConfidenceReason;
            
            //if(showDebug) Print("[E3] SHORT detected at ", currentPrice);
        }
        
        return result;
    }
    
    double CalculateTakeProfit(double entryPrice, double stopLoss, bool isLong, int exhaustionScore) {
        double slDistance = MathAbs(entryPrice - stopLoss);
        bool isSideway = IsInSidewayRange();
        double baseRR = isSideway ? m_config.rewardRatioSideway : m_config.rewardRatio;
        
        // Preserve existing long/short asymmetry but anchor it to adaptive RR
        double shortFactor = (CFG.rrLongE3 > 0.0) ? (CFG.rrShortE3 / CFG.rrLongE3) : 0.778;
        double rrRatio = isLong ? baseRR : baseRR * shortFactor;
        
        // Regime-aware RR by exhaustion bucket (high conviction gets a small boost)
        if (E3_SCORE_RR_ADJUST_ENABLED) {
            if (exhaustionScore < E3_SCORE_RR_REDUCE_BELOW) {
                rrRatio *= E3_SCORE_RR_REDUCE_MULT;
            } else if (exhaustionScore >= E3_SCORE_RR_BOOST_AT_OR_ABOVE) {
                rrRatio *= E3_SCORE_RR_BOOST_MULT;
            }
        }
        
        rrRatio = MathMax(ADAPTIVE_RR_ABSOLUTE_MIN, MathMin(ADAPTIVE_RR_ABSOLUTE_MAX, rrRatio));
        return isLong ? entryPrice + (slDistance * rrRatio) : entryPrice - (slDistance * rrRatio);
    }
    
    // E3-specific ATR-based SL calculation (uses cached ATR from GlobalState)
    double CalculateE3StopLoss(bool isLong, double currentPrice, double swingExtreme) {
        double slDistance;
        
        if (m_config.useATRBased && cache.atrM1 > 0) {
            // Use cached ATR M1(14) from UpdateIndicatorCache() - no new handle creation
            // CRITICAL: Use adaptive m_config.atrMultiplier, NOT input param E3_ATR_MULTIPLIER_SL
            double atrPips = (cache.atrM1 * m_config.atrMultiplier) / pipSize;
            // NOTE: No hard capping - ATR-based SL used directly
            slDistance = atrPips * pipSize;
            
            if (showDebug) {
                Print("[E3 ATR SL] Cached ATR=", DoubleToString(cache.atrM1, 5),
                      " x", DoubleToString(m_config.atrMultiplier, 2),
                      " = ", DoubleToString(atrPips, 1), " pips");
            }
        } else {
            // Fallback to fixed E3-specific buffer (smaller than E1/E2's SL_EMA_DISTANCE)
            slDistance = E3_SL_EMA_BUFFER * pipSize;
        }
        
        // Calculate SL from swing extreme
        double stopLoss = isLong ? (swingExtreme - slDistance) : (swingExtreme + slDistance);
        return stopLoss;
    }
    
    //--------------------------------------------------------------------
    // E3-SPECIFIC CONDITION CHECKING
    //--------------------------------------------------------------------
    
    // M1 momentum confirmation - lightweight check using cached values
    // Returns true if M1 momentum aligns with at least one exhaustion direction
    // FIXED: Added price-based confirmation as alternative to strict DI rotation
    bool CheckM1MomentumConfirmation() {
        // Use cached M1 ADX and DI values (already calculated in UpdateIndicatorCache)
        double adxM1 = cache.adx[TF0];
        double diPlusM1 = cache.diPlus[TF0];
        double diMinusM1 = cache.diMinus[TF0];
        
        // Require minimum M1 momentum (but much lower threshold for reversals)
        // Reversals often start with ADX dropping, so use 70% of normal threshold
        double adxThreshold = ADX_LOW_THRESHOLD * 0.70;
        if (adxM1 < adxThreshold) {
            return false;  // M1 too weak
        }
        
        bool longReady = m_m3ConditionsMetLong && (!E3_ENABLE_REGIME_GATE || m_regimeGateMetLong);
        bool shortReady = m_m3ConditionsMetShort && (!E3_ENABLE_REGIME_GATE || m_regimeGateMetShort);
        
        // PRICE-BASED CONFIRMATION (Alternative path - more reliable for reversals)
        // For counter-trend E3, we DON'T require DI to have flipped yet
        // Price crossing above/below fast EMA is the early reversal signal
        if (E3_M1_USE_PRICE_CONFIRMATION && m_emaHandleM1 != INVALID_HANDLE) {
            double currentClose = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
            double emaBuf[1];
            if (CopyBuffer(m_emaHandleM1, 0, ENTRY_SHIFT, 1, emaBuf) == 1) {
                bool longPriceOk = longReady && (currentClose > emaBuf[0]);
                bool shortPriceOk = shortReady && (currentClose < emaBuf[0]);
                if (longPriceOk || shortPriceOk) {
                    return true;  // Price action confirms reversal direction
                }
            }
        }
        
        // TRADITIONAL DI ROTATION CHECK (stricter path)
        double adxBuf[E3_M1_ROTATION_LOOKBACK], diPlusBuf[E3_M1_ROTATION_LOOKBACK], diMinusBuf[E3_M1_ROTATION_LOOKBACK];
        bool haveHistory = (adxHandles[TF0] != INVALID_HANDLE) &&
                           (CopyBuffer(adxHandles[TF0], 0, 0, E3_M1_ROTATION_LOOKBACK, adxBuf) == E3_M1_ROTATION_LOOKBACK) &&
                           (CopyBuffer(adxHandles[TF0], 1, 0, E3_M1_ROTATION_LOOKBACK, diPlusBuf) == E3_M1_ROTATION_LOOKBACK) &&
                           (CopyBuffer(adxHandles[TF0], 2, 0, E3_M1_ROTATION_LOOKBACK, diMinusBuf) == E3_M1_ROTATION_LOOKBACK);
        
        // If we can't get history, fall back to simple DI dominance
        if (!haveHistory) {
            bool longDominant = longReady && (diPlusM1 > diMinusM1);
            bool shortDominant = shortReady && (diMinusM1 > diPlusM1);
            return longDominant || shortDominant;
        }
        
        // ADX uptick check (optional - OFF by default for reversals)
        bool adxUptick = true;
        if (E3_M1_REQUIRE_ADX_UPTICK && adxBuf[0] >= E3_M1_MIN_ADX_FOR_UPTICK) {
            adxUptick = (adxBuf[0] > adxBuf[1]);
        }
        
        // DI rotation: look for spread improvement or a recent cross with sufficient spread
        double spread0Long = diPlusBuf[0] - diMinusBuf[0];
        double spread1Long = diPlusBuf[1] - diMinusBuf[1];
        double spread2Long = diPlusBuf[2] - diMinusBuf[2];
        bool longDominant = (diPlusM1 > diMinusM1) && (spread0Long >= E3_M1_MIN_DI_SPREAD);
        bool longCrossed = (spread0Long > 0.0) && (spread1Long <= 0.0 || spread2Long <= 0.0);
        bool longImproving = (spread0Long > spread1Long);
        
        double spread0Short = diMinusBuf[0] - diPlusBuf[0];
        double spread1Short = diMinusBuf[1] - diPlusBuf[1];
        double spread2Short = diMinusBuf[2] - diPlusBuf[2];
        bool shortDominant = (diMinusM1 > diPlusM1) && (spread0Short >= E3_M1_MIN_DI_SPREAD);
        bool shortCrossed = (spread0Short > 0.0) && (spread1Short <= 0.0 || spread2Short <= 0.0);
        bool shortImproving = (spread0Short > spread1Short);
        
        bool longRotationOk = longDominant && (longCrossed || longImproving);
        bool shortRotationOk = shortDominant && (shortCrossed || shortImproving);
        
        if (!E3_M1_REQUIRE_ROTATION) {
            longRotationOk = longDominant;
            shortRotationOk = shortDominant;
        }
        
        return (longReady && longRotationOk && adxUptick) ||
               (shortReady && shortRotationOk && adxUptick);
    }
    
    // Check if M3 bar changed and pre-calculate exhaustion scores
    // This avoids duplicate CopyBuffer calls when checking long then short
    // Uses global currentBar (M1 count) - recalculate every 3 M1 bars
    void UpdateM3Cache() {
        // Only recalculate when M3 bar changes (every 3 M1 bars)
        int currentM3BarIndex = currentBar / 3;
        int lastM3BarIndex = m_lastM1BarForM3Cache / 3;
        
        if (currentM3BarIndex != lastM3BarIndex || m_lastM1BarForM3Cache < 0) {
            m_lastM1BarForM3Cache = currentBar;
            m_m3OHLCCached = false;  // Mark OHLC as stale
            m_cachedHTFADXDeclineBonus = 0;
            
            // Cache M3 OHLC once (used by wick rejection and regime stretch)
            EnsureM3OHLCCache();
            m_cachedHTFADXDeclineBonus = CalculateHTFADXDeclineBonus();
            
            // Pre-calculate exhaustion scores for BOTH directions
            if (E3_USE_EXHAUSTION_SCORING) {
                m_cachedExhaustionScoreLong = CalculateExhaustionScore(true);
                m_cachedExhaustionScoreShort = CalculateExhaustionScore(false);
                m_m3ConditionsMetLong = (m_cachedExhaustionScoreLong >= E3_MIN_EXHAUSTION_SCORE);
                m_m3ConditionsMetShort = (m_cachedExhaustionScoreShort >= E3_MIN_EXHAUSTION_SCORE);
            } else {
                m_cachedExhaustionScoreLong = 0;
                m_cachedExhaustionScoreShort = 0;
                m_m3ConditionsMetLong = true;
                m_m3ConditionsMetShort = true;
            }
            
            // Pre-calculate regime gate state (no tracking at cache time)
            if (E3_ENABLE_REGIME_GATE) {
                m_regimeGateMetLong = EvaluateRegimeGate(true, "L-E3", false);
                m_regimeGateMetShort = EvaluateRegimeGate(false, "S-E3", false);
            } else {
                m_regimeGateMetLong = true;
                m_regimeGateMetShort = true;
            }
        }
    }
    
    int GetM3OHLCCacheBars() {
        int bars = E3_M3_OHLC_CACHE_BARS;
        if (bars < E3_M3_OHLC_CACHE_MIN) bars = E3_M3_OHLC_CACHE_MIN;
        if (bars > E3_M3_OHLC_CACHE_MAX) bars = E3_M3_OHLC_CACHE_MAX;
        return bars;
    }
    
    // Ensure cached M3 OHLC data is available (used by wick rejection and regime stretch)
    bool EnsureM3OHLCCache() {
        if (m_m3OHLCCached) return true;
        
        int bars = GetM3OHLCCacheBars();
        double tempO[], tempH[], tempL[], tempC[];
        ArraySetAsSeries(tempO, true);
        ArraySetAsSeries(tempH, true);
        ArraySetAsSeries(tempL, true);
        ArraySetAsSeries(tempC, true);
        
        ArrayResize(tempO, bars);
        ArrayResize(tempH, bars);
        ArrayResize(tempL, bars);
        ArrayResize(tempC, bars);
        
        if (CopyOpen(_Symbol, TF_ARRAY[TF1], 0, bars, tempO) == bars &&
            CopyHigh(_Symbol, TF_ARRAY[TF1], 0, bars, tempH) == bars &&
            CopyLow(_Symbol, TF_ARRAY[TF1], 0, bars, tempL) == bars &&
            CopyClose(_Symbol, TF_ARRAY[TF1], 0, bars, tempC) == bars) {
            for (int i = 0; i < bars; i++) {
                m_cachedM3Open[i] = tempO[i];
                m_cachedM3High[i] = tempH[i];
                m_cachedM3Low[i] = tempL[i];
                m_cachedM3Close[i] = tempC[i];
            }
            m_m3OHLCCached = true;
        }
        
        return m_m3OHLCCached;
    }
    
    double GetDirectionalDISpread(int index, bool isLong) {
        if (!cache.m3HistoryValid) return 0.0;
        return isLong ? (cache.diPlusM3[index] - cache.diMinusM3[index])
                      : (cache.diMinusM3[index] - cache.diPlusM3[index]);
    }
    
    bool CheckRegimeFatigue(bool isLong, string entryType, bool trackFailure) {
        if (!E3_REGIME_REQUIRE_FATIGUE) return true;
        
        double adx0 = cache.adxM3[0];
        double adx1 = cache.adxM3[1];
        double adx2 = cache.adxM3[2];
        double maxAdx = MathMax(adx0, MathMax(adx1, adx2));
        bool adxEligible = (maxAdx >= E3_REGIME_MIN_ADX_FOR_FATIGUE);
        
        double diSpread0 = GetDirectionalDISpread(0, isLong);
        double diSpread2 = GetDirectionalDISpread(2, isLong);
        bool diTrendValid = (diSpread2 >= E3_REGIME_MIN_DI_SPREAD);
        bool diCompressing = diTrendValid && ((diSpread2 - diSpread0) >= E3_REGIME_MIN_DI_SPREAD_DELTA);
        
        bool adxRollingOver = adxEligible &&
                              (adx2 >= E3_REGIME_MIN_ADX_ROLLOVER) &&
                              (adx0 < adx1) && (adx1 <= adx2);
        bool htfDeclining = (m_cachedHTFADXDeclineBonus > 0);
        
        bool fatigueOk = (adxEligible && (adxRollingOver || diCompressing)) || htfDeclining;
        
        if (!fatigueOk && trackFailure) {
            TrackEntryAttempt(entryType, false, "trend_context");
        }
        
        if (showDebug && trackFailure && !fatigueOk) {
            string dir = isLong ? "L-E3" : "S-E3";
            Print("[E3] ", dir, " fatigue gate failed | ADX0=", DoubleToString(adx0, 1),
                  " ADX2=", DoubleToString(adx2, 1),
                  " DI0=", DoubleToString(diSpread0, 1),
                  " DI2=", DoubleToString(diSpread2, 1),
                  " HTFDecline=", htfDeclining ? "Y" : "N");
        }
        
        return fatigueOk;
    }
    
    bool CheckRegimeStretch(bool isLong, string entryType, bool trackFailure) {
        if (!E3_REGIME_REQUIRE_STRETCH) return true;
        
        double atrForStretch = cache.atrM1;
        if (atrForStretch <= 0.0) {
            if (trackFailure) TrackEntryAttempt(entryType, false, "trend_context");
            return false;
        }
        
        if (!EnsureM3OHLCCache()) {
            if (trackFailure) TrackEntryAttempt(entryType, false, "trend_context");
            return false;
        }
        
        int bars = GetM3OHLCCacheBars();
        int maxLookback = (bars - 1) - E3_EMA_BAR_SHIFT;
        int lookback = MathMax(1, MathMin(E3_REGIME_STRETCH_LOOKBACK, maxLookback));
        
        double maxStretch25 = 0.0;
        double maxStretch75 = 0.0;
        
        for (int shift = E3_EMA_BAR_SHIFT; shift < E3_EMA_BAR_SHIFT + lookback; shift++) {
            double ema25 = GetEMA(TF1, EMA1, shift);
            double ema75 = GetEMA(TF1, EMA2, shift);
            double anchorPrice = isLong ? m_cachedM3Low[shift] : m_cachedM3High[shift];
            
            double stretch25 = isLong ? MathMax(0.0, ema25 - anchorPrice) : MathMax(0.0, anchorPrice - ema25);
            double stretch75 = isLong ? MathMax(0.0, ema75 - anchorPrice) : MathMax(0.0, anchorPrice - ema75);
            
            maxStretch25 = MathMax(maxStretch25, stretch25 / atrForStretch);
            maxStretch75 = MathMax(maxStretch75, stretch75 / atrForStretch);
        }
        
        bool stretchedEnough = (maxStretch25 >= E3_REGIME_MIN_STRETCH_EMA25_ATR) ||
                               (maxStretch75 >= E3_REGIME_MIN_STRETCH_EMA75_ATR);
        
        if (!stretchedEnough && trackFailure) {
            TrackEntryAttempt(entryType, false, "trend_context");
        }
        
        if (showDebug && trackFailure && !stretchedEnough) {
            string dir = isLong ? "L-E3" : "S-E3";
            Print("[E3] ", dir, " stretch gate failed | stretch25=", DoubleToString(maxStretch25, 2),
                  " stretch75=", DoubleToString(maxStretch75, 2),
                  " ATR=", DoubleToString(atrForStretch, 5));
        }
        
        return stretchedEnough;
    }
    
    bool EvaluateRegimeGate(bool isLong, string entryType, bool trackFailure) {
        if (!E3_ENABLE_REGIME_GATE) return true;
        if (!cache.m3HistoryValid) {
            if (trackFailure) TrackEntryAttempt(entryType, false, "trend_context");
            return false;
        }
        
        if (!CheckRegimeFatigue(isLong, entryType, trackFailure)) return false;
        if (!CheckRegimeStretch(isLong, entryType, trackFailure)) return false;
        return true;
    }
    
    bool CheckE3EntryConditions_Internal(bool isLong, double currentPrice, string entryType,
                                         double &recentExtreme, bool &isLowConfidence, 
                                         string &lowConfidenceReason) {
        isLowConfidence = false;
        lowConfidenceReason = "";
        
        // STEP 0: HTF Trend Alignment (CRITICAL - trade WITH the larger trend)
        // L-E3 (long reversal): Only if M5/M15 is bullish (buying dip in uptrend)
        // S-E3 (short reversal): Only if M5/M15 is bearish (selling rally in downtrend)
        if (E3_REQUIRE_HTF_TREND_ALIGN && !CheckHTFTrendAlignment(isLong, entryType)) {
            return false;
        }
        
        // STEP 0b: Regime gate (fatigue + stretch) to avoid continuation traps
        if (E3_ENABLE_REGIME_GATE && !EvaluateRegimeGate(isLong, entryType, true)) {
            return false;
        }
        
        if (!CheckDISpreadDeceleration(isLong, entryType, isLowConfidence, lowConfidenceReason)) {
            TrackEntryAttempt(entryType, false, "di_spread");
            return false;
        }
        
        // Note: Exhaustion score already checked in Detect() before calling this function
        
        // STEP 1: EMA alignment check - ensure existing trend context
        // SKIP if HTF alignment is enabled - HTF direction replaces M3 EMA alignment
        // (HTF bullish + M3 bearish EMAs is contradictory - trust the HTF direction instead)
        if (!E3_REQUIRE_HTF_TREND_ALIGN) {
            // L-E3: EMAs must be in bearish order (12 < 25 < 75 < 100) - counter-trend long into bearish trend
            // S-E3: EMAs must be in bullish order (12 > 25 > 75 > 100) - counter-trend short into bullish trend
            if (!CheckEMAAlignment(isLong, entryType)) {
                return false;
            }
        }
        
        // STEP 2: EMA 10 breakout check (M3 only - require actual breakout)
        if (!CheckEMA10Breakout(isLong, entryType)) {
            return false;
        }
        
        // STEP 3: Recent extreme validation (lookback scan)
        if (!GetRecentExtreme(isLong, recentExtreme, entryType)) {
            return false;
        }
        
        // (Quality filters commented out - already handled by exhaustion scoring)
        
        return true;
    }
    
    // EMA alignment check - ensure existing trend context for counter-trend entry
    // L-E3: EMAs must be in bearish order (10 < 25 < 75 < 100) - we're going long against bearish trend
    // S-E3: EMAs must be in bullish order (10 > 25 > 75 > 100) - we're going short against bullish trend
    bool CheckEMAAlignment(bool isLong, string entryType) {
        double ema10_m3 = GetEMA(TF1, EMA0, E3_EMA_BAR_SHIFT);
        double ema25_m3 = GetEMA(TF1, EMA1, E3_EMA_BAR_SHIFT);
        double ema75_m3 = GetEMA(TF1, EMA2, E3_EMA_BAR_SHIFT);
        double ema100_m3 = GetEMA(TF1, EMA3, E3_EMA_BAR_SHIFT);
        
        bool alignmentValid;
        if (isLong) {
            // L-E3: bearish alignment (10 < 25 < 75 < 100)
            alignmentValid = (ema10_m3 < ema25_m3) && (ema25_m3 < ema75_m3) && (ema75_m3 < ema100_m3);
        } else {
            // S-E3: bullish alignment (10 > 25 > 75 > 100)
            alignmentValid = (ema10_m3 > ema25_m3) && (ema25_m3 > ema75_m3) && (ema75_m3 > ema100_m3);
        }
        
        // E3 MOMENTUM BYPASS (Pine parity: e3MomentumBypassLevel)
        // Level 0: Require M3 alignment (default for E3 counter-trend)
        // Level 1/2: Bypass M3 alignment check
        bool alignmentOrBypassed = alignmentValid || (E3_MOMENTUM_BYPASS_LEVEL > 0);
        
        if (!alignmentOrBypassed) {
            TrackEntryAttempt(entryType, false, "ema_alignment");
            return false;
        }
        return true;
    }
    
    // M3 EMA10 FRESH breakout check - must be a NEW breakout, not continuation
    // L-E3: Current bar closed above EMA10, but previous 2 bars did NOT
    // S-E3: Current bar closed below EMA10, but previous 2 bars did NOT
    bool CheckEMA10Breakout(bool isLong, string entryType) {
        // Get EMA10 values for current and previous bars
        double ema10_bar1 = GetEMA(TF1, EMA0, E3_EMA_BAR_SHIFT);      // Current closed bar
        double ema10_bar2 = GetEMA(TF1, EMA0, E3_EMA_BAR_SHIFT + 1);  // Previous bar
        double ema10_bar3 = GetEMA(TF1, EMA0, E3_EMA_BAR_SHIFT + 2);  // Bar before that
        
        // Get close prices for each bar
        double close1 = iClose(_Symbol, TF_ARRAY[TF1], E3_EMA_BAR_SHIFT);
        double close2 = iClose(_Symbol, TF_ARRAY[TF1], E3_EMA_BAR_SHIFT + 1);
        double close3 = iClose(_Symbol, TF_ARRAY[TF1], E3_EMA_BAR_SHIFT + 2);
        
        bool freshBreakout;
        if (isLong) {
            // L-E3: Current bar above EMA10, previous 2 bars were NOT above
            bool currentAbove = (close1 > ema10_bar1);
            bool prev1NotAbove = (close2 <= ema10_bar2);
            bool prev2NotAbove = (close3 <= ema10_bar3);
            freshBreakout = currentAbove && prev1NotAbove && prev2NotAbove;
        } else {
            // S-E3: Current bar below EMA10, previous 2 bars were NOT below
            bool currentBelow = (close1 < ema10_bar1);
            bool prev1NotBelow = (close2 >= ema10_bar2);
            bool prev2NotBelow = (close3 >= ema10_bar3);
            freshBreakout = currentBelow && prev1NotBelow && prev2NotBelow;
        }
        
        if (!freshBreakout) {
            TrackEntryAttempt(entryType, false, "ema10_breakout");
            return false;
        }
        return true;
    }
    
    bool GetRecentExtreme(bool isLong, double &recentExtreme, string entryType) {
        int extremeBarIndex = isLong ? GetRecentExtremeBarIndex(TF_ARRAY[TF1], E3_EXTREME_LOOKBACK_BARS, true) : 
                                       GetRecentExtremeBarIndex(TF_ARRAY[TF1], E3_EXTREME_LOOKBACK_BARS, false);
        
        if (extremeBarIndex < 0 || extremeBarIndex > E3_EXTREME_MAX_DISTANCE) {
            TrackEntryAttempt(entryType, false, "extreme_distance");
            return false;
        }
        
        // Get the actual extreme value for SL calculation
        if (isLong) {
            double lows[];
            ArraySetAsSeries(lows, true);
            if (CopyLow(_Symbol, TF_ARRAY[TF1], 0, E3_EXTREME_MAX_DISTANCE+1, lows) > 0) {
                recentExtreme = lows[extremeBarIndex];
                return true;
            }
        } else {
            double highs[];
            ArraySetAsSeries(highs, true);
            if (CopyHigh(_Symbol, TF_ARRAY[TF1], 0, E3_EXTREME_MAX_DISTANCE+1, highs) > 0) {
                recentExtreme = highs[extremeBarIndex];
                return true;
            }
        }
        
        return false;
    }
    
    void CheckQualityFilters(bool isLong, string entryType, bool &isLowConfidence, string &lowConfidenceReason) {
        // E3 reversal: Skip trend quality check!
        // Trend quality measures STRONG trend, but at reversal points the trend is WEAKENING
        // This conflicts with exhaustion scoring - can't have both strong AND dying trend!
        // We already validate trend context via EMA alignment in CheckTrendContext
    }
    
    bool CheckDISpreadDeceleration(bool isLong, string entryType, bool &isLowConfidence, string &lowConfidenceReason) {
        // Exhaustion scoring is now checked first in CheckE3EntryConditions_Internal
        // This function is kept for backward compatibility when exhaustion scoring is disabled
        if (E3_USE_EXHAUSTION_SCORING) {
            return true;  // Already checked and passed in STEP 1
        }
        
        TREND_STATE reversalDirection = isLong ? TREND_BULL : TREND_BEAR;
        bool diDecelerationM3 = HasDISpreadDeceleration(TF_ARRAY[TF1], reversalDirection, 3);
        bool diDecelerationM1 = HasDISpreadDeceleration(TF_ARRAY[TF0], reversalDirection, 3);
        double adx_1m = GetADXCurrent(TF_ARRAY[TF0]);
        double adx_3m = GetADXCurrent(TF_ARRAY[TF1]);
        
        bool diConfirmed = diDecelerationM3 ;//&& diDecelerationM1;
        bool adxConfirmed = (adx_3m >= ADX_LOW_THRESHOLD);//|| (adx_1m >= ADX_LOW_THRESHOLD);
        if (!diConfirmed || !adxConfirmed) {
            TrackEntryAttempt(entryType, false, "di_reversal");
            isLowConfidence = true;
            lowConfidenceReason = "ADX and DI spread not showing clear reversal pattern";
            return true;
        }
        
        return true;
    }
    
    // HTF Trend Alignment Check (M5/M15) - CRITICAL for avoiding counter-HTF trades
    // L-E3: Only enter long if HTF trend is bullish (DI+ > DI-) - buying dip in uptrend
    // S-E3: Only enter short if HTF trend is bearish (DI- > DI+) - selling rally in downtrend
    // E3_HTF_ALIGN_MODE: 0=M5 only, 1=M5 OR M15, 2=M5 AND M15
    bool CheckHTFTrendAlignment(bool isLong, string entryType) {
        // Get M5 DI values (TF2 = index 2)
        double diPlusM5 = cache.diPlus[TF2];
        double diMinusM5 = cache.diMinus[TF2];
        double adxM5 = cache.adx[TF2];
        
        // Get M15 DI values (TF3 = index 3)
        double diPlusM15 = cache.diPlus[TF3];
        double diMinusM15 = cache.diMinus[TF3];
        double adxM15 = cache.adx[TF3];
        
        // BLOCK during strong trends - reversals rarely work when momentum is high
        if (E3_BLOCK_STRONG_TREND && adxM15 >= E3_STRONG_TREND_ADX) {
            if (showDebug) {
                string dir = isLong ? "L-E3" : "S-E3";
                Print("[E3] ", dir, " blocked: Strong trend (M15 ADX=", DoubleToString(adxM15, 1), 
                      " >= ", DoubleToString(E3_STRONG_TREND_ADX, 1), ")");
            }
            TrackEntryAttempt(entryType, false, "strong_trend");
            return false;
        }
        
        // H1 Trend Anchor - most stable trend direction
        if (E3_REQUIRE_H1_ALIGN && m_adxHandleH1 != INVALID_HANDLE) {
            double h1Buf[3];  // ADX, DI+, DI-
            if (CopyBuffer(m_adxHandleH1, 0, 0, 1, h1Buf) == 1) {
                double adxH1 = h1Buf[0];
                double diPlusH1Buf[1], diMinusH1Buf[1];
                CopyBuffer(m_adxHandleH1, 1, 0, 1, diPlusH1Buf);
                CopyBuffer(m_adxHandleH1, 2, 0, 1, diMinusH1Buf);
                double diPlusH1 = diPlusH1Buf[0];
                double diMinusH1 = diMinusH1Buf[0];
                
                // Only check if H1 is trending
                if (adxH1 >= ADX_LOW_THRESHOLD) {
                    bool h1Aligned = isLong ? (diPlusH1 > diMinusH1) : (diMinusH1 > diPlusH1);
                    if (!h1Aligned) {
                        if (showDebug) {
                            string dir = isLong ? "L-E3" : "S-E3";
                            Print("[E3] ", dir, " blocked: H1 not aligned (DI+=", 
                                  DoubleToString(diPlusH1, 1), " DI-=", DoubleToString(diMinusH1, 1), ")");
                        }
                        TrackEntryAttempt(entryType, false, "h1_align");
                        return false;
                    }
                }
            }
        }
        
        // Check trend direction on each timeframe (only if ADX shows valid trend)
        bool m5Valid = (adxM5 >= ADX_LOW_THRESHOLD);
        bool m15Valid = (adxM15 >= ADX_LOW_THRESHOLD);
        
        bool m5Aligned = false;
        bool m15Aligned = false;
        
        if (isLong) {
            // L-E3: Want to buy dip - need bullish HTF
            if (m5Valid) m5Aligned = (diPlusM5 > diMinusM5);
            else m5Aligned = true;  // Ranging = neutral, allow
            
            if (m15Valid) m15Aligned = (diPlusM15 > diMinusM15);
            else m15Aligned = true;  // Ranging = neutral, allow
        } else {
            // S-E3: Want to sell rally - need bearish HTF
            if (m5Valid) m5Aligned = (diMinusM5 > diPlusM5);
            else m5Aligned = true;  // Ranging = neutral, allow
            
            if (m15Valid) m15Aligned = (diMinusM15 > diPlusM15);
            else m15Aligned = true;  // Ranging = neutral, allow
        }
        
        // Apply alignment mode
        bool htfAligned = false;
        switch (E3_HTF_ALIGN_MODE) {
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
                string dir = isLong ? "L-E3" : "S-E3";
                Print("[E3] ", dir, " blocked: HTF not aligned (M5:", m5Aligned ? "OK" : "NO",
                      " M15:", m15Aligned ? "OK" : "NO", " mode=", E3_HTF_ALIGN_MODE, ")");
            }
            TrackEntryAttempt(entryType, false, "htf_trend");
            return false;
        }
        
        return true;
    }
    
public:
    // Get cached exhaustion score (pre-calculated when M3 bar changes)
    // Public for recovery boost logic in KenKemExpert.mq5
    int GetCachedExhaustionScore(bool isLong) {
        UpdateM3Cache();  // Ensures cache is fresh, calculates both directions if needed
        return isLong ? m_cachedExhaustionScoreLong : m_cachedExhaustionScoreShort;
    }
    
    // Multi-factor exhaustion scoring (0-12 points) - public for recovery boost logic
    // GRADUATED scoring: each component awards 1-3 points based on strength
    int CalculateExhaustionScore(bool isLong) {
        int score = 0;
        
        // Component 1: RSI Exhaustion Pattern (0-3 points, graduated)
        if (E3_USE_RSI_EXHAUSTION) {
            score += GetRSIExhaustionPoints(TF_ARRAY[TF1], isLong);
        }
        
        // Component 2: ADX Peak + Decline (0-3 points, graduated)
        if (E3_USE_ADX_PEAK_DECLINE) {
            score += GetADXDeclinePoints(TF_ARRAY[TF1]);
        }
        
        // Component 3: DI Spread Deceleration - NOW MANDATORY (checked separately)
        // Points still awarded for strength grading
        score += GetDIDecelerationPoints(isLong);
        
        // Component 4: Wick Rejection (0-3 points, graduated)
        if (E3_USE_WICK_REJECTION) {
            score += GetWickRejectionPoints(isLong);
        }
        
        // Component 5: HTF ADX Declining Bonus (0-2 points) - M5/M15 momentum fading
        score += GetHTFADXDeclineBonus();
        
        return score; // Max: 14 points (4 components × 3 + HTF bonus 2)
    }
    
private:
    // RSI exhaustion points (0-3, graduated) - USES CACHED M3 HISTORY
    // 1 pt: RSI was extreme (oversold/overbought recently)
    // 2 pts: + RSI crossed EMA or is on correct side
    // 3 pts: + Spread widening (momentum building)
    int GetRSIExhaustionPoints(ENUM_TIMEFRAMES timeFrame, bool isLong) {
        // Use cached M3 history (no CopyBuffer!)
        if (timeFrame != TF_ARRAY[TF1] || !cache.m3HistoryValid) return 0;
        
        // Calculate RSI EMA using cached values
        double rsiEMA = cache.rsiM3[5];
        double alpha = 2.0 / 15.0;
        for (int i = 4; i >= 0; i--) {
            rsiEMA = cache.rsiM3[i] * alpha + rsiEMA * (1 - alpha);
        }
        
        int points = 0;
        
        if (isLong) {
            // Long E3: looking for oversold recovery
            bool wasOversold = (cache.rsiM3[3] < 30 || cache.rsiM3[2] < 30 || cache.rsiM3[4] < 30);
            bool crossedAbove = (cache.rsiM3[1] < rsiEMA) && (cache.rsiM3[0] > rsiEMA);
            bool aboveEMA = (cache.rsiM3[0] > rsiEMA);
            double spread = cache.rsiM3[0] - rsiEMA;
            
            if (wasOversold) points += 1;
            if (points > 0 && (crossedAbove || aboveEMA)) points += 1;
            if (points > 1 && spread > 2.0) points += 1;
        } else {
            // Short E3: looking for overbought exhaustion
            bool wasOverbought = (cache.rsiM3[3] > 70 || cache.rsiM3[2] > 70 || cache.rsiM3[4] > 70);
            bool crossedBelow = (cache.rsiM3[1] > rsiEMA) && (cache.rsiM3[0] < rsiEMA);
            bool belowEMA = (cache.rsiM3[0] < rsiEMA);
            double spread = rsiEMA - cache.rsiM3[0];
            
            if (wasOverbought) points += 1;
            if (points > 0 && (crossedBelow || belowEMA)) points += 1;
            if (points > 1 && spread > 2.0) points += 1;
        }
        
        return points;
    }
    
    // ADX decline points (0-3, graduated) - USES CACHED M3 HISTORY
    // 1 pt: ADX declining for 1 bar
    // 2 pts: ADX declining for 2 bars
    // 3 pts: + Was strong (>25) before decline
    int GetADXDeclinePoints(ENUM_TIMEFRAMES timeFrame) {
        // Use cached M3 history (no CopyBuffer!)
        if (timeFrame != TF_ARRAY[TF1] || !cache.m3HistoryValid) return 0;
        
        // Must be above minimum threshold to count
        if (cache.adxM3[0] <= ADX_LOW_THRESHOLD) return 0;
        
        int points = 0;
        
        bool declining1 = (cache.adxM3[0] < cache.adxM3[1]);
        bool declining2 = declining1 && (cache.adxM3[1] < cache.adxM3[2]);
        bool wasStrong = (cache.adxM3[2] > 25 || cache.adxM3[3] > 25 || cache.adxM3[4] > 25);
        
        if (declining1) points += 1;
        if (declining2) points += 1;
        if (points > 0 && wasStrong) points += 1;
        
        return points;
    }
    
    // DI deceleration points (0-3, graduated) - USES CACHED M3 HISTORY
    // Uses M3 only since this is cached on M3 bar change
    // 1 pt: DI spread contracting on M3
    // 2 pts: Strong deceleration pattern
    // 3 pts: + ADX above MIN_MOMENTUM_ADX threshold
    int GetDIDecelerationPoints(bool isLong) {
        if (!cache.m3HistoryValid) return 0;
        
        // Check DI spread deceleration using cached history (no CopyBuffer!)
        bool diDecM3 = false;
        if (isLong) {
            // Bullish reversal: DI+ rising, DI- falling
            if (cache.diPlusM3[0] > cache.diPlusM3[1] && cache.diMinusM3[0] < cache.diMinusM3[1]) {
                double spreadCurrent = cache.diPlusM3[0] - cache.diMinusM3[0];
                double spreadPrev = cache.diPlusM3[2] - cache.diMinusM3[2];
                if (spreadCurrent > spreadPrev) diDecM3 = true;
            }
        } else {
            // Bearish reversal: DI- rising, DI+ falling
            if (cache.diMinusM3[0] > cache.diMinusM3[1] && cache.diPlusM3[0] < cache.diPlusM3[1]) {
                double spreadCurrent = cache.diMinusM3[0] - cache.diPlusM3[0];
                double spreadPrev = cache.diMinusM3[2] - cache.diPlusM3[2];
                if (spreadCurrent > spreadPrev) diDecM3 = true;
            }
        }
        
        bool adxStrong = (cache.adxM3[0] >= MIN_MOMENTUM_ADX_REQUIRED);
        
        int points = 0;
        if (diDecM3) points += 2;
        if (points > 0 && adxStrong) points += 1;
        
        return points;
    }
    
    // Wick rejection points (0-3, graduated) - uses CACHED M3 OHLC
    // 1 pt: Recent candle has rejection wick (>40% of range) in exhaustion direction
    // 2 pts: + Wick at/near recent extreme (within 3 bars of high/low)
    // 3 pts: + Multiple rejection wicks in last 3 bars
    int GetWickRejectionPoints(bool isLong) {
        // Use cached M3 OHLC (populated in UpdateM3Cache) - no CopyBuffer calls!
        if (!m_m3OHLCCached) return 0;
        
        int points = 0;
        int rejectionCount = 0;
        
        // Check last 3 bars for rejection wicks (using cached arrays)
        int bars = GetM3OHLCCacheBars();
        for (int i = 1; i <= 3 && i < bars; i++) {
            double range = m_cachedM3High[i] - m_cachedM3Low[i];
            if (range <= 0) continue;
            
            double upperWick = m_cachedM3High[i] - MathMax(m_cachedM3Open[i], m_cachedM3Close[i]);
            double lowerWick = MathMin(m_cachedM3Open[i], m_cachedM3Close[i]) - m_cachedM3Low[i];
            
            if (isLong) {
                // Long E3: looking for lower wick rejection (buyers stepping in)
                double wickRatio = lowerWick / range;
                if (wickRatio >= 0.4) rejectionCount++;
            } else {
                // Short E3: looking for upper wick rejection (sellers stepping in)
                double wickRatio = upperWick / range;
                if (wickRatio >= 0.4) rejectionCount++;
            }
        }
        
        if (rejectionCount >= 1) points += 1;       // 1 pt: at least 1 rejection wick
        
        // Check if rejection occurred near extreme (use cached OHLC)
        if (points > 0) {
            int extremeBar = isLong ? GetCachedLowBarIndex() : GetCachedHighBarIndex();
            if (extremeBar >= 0 && extremeBar <= 3) points += 1;  // 2 pts: near extreme
        }
        
        if (rejectionCount >= 2) points += 1;       // 3 pts: multiple rejections
        
        return points;
    }
    
    // HTF ADX Decline Bonus (0-2 points) - M5/M15 momentum fading confirms exhaustion
    // Uses cached ADX values from GlobalState - no new indicator handles needed
    // 1 pt: M5 ADX declining (current < previous bar)
    // 2 pts: + M15 ADX also declining (stronger HTF confirmation)
    int CalculateHTFADXDeclineBonus() {
        int points = 0;
        
        double adxM5Buf[2];
        if (adxHandles[TF2] != INVALID_HANDLE && CopyBuffer(adxHandles[TF2], 0, 0, 2, adxM5Buf) == 2) {
            bool m5Declining = (adxM5Buf[0] < adxM5Buf[1]);
            if (m5Declining && adxM5Buf[0] >= ADX_LOW_THRESHOLD) {
                points += 1;  // M5 ADX was trending and now declining
            }
        }
        
        // Check M15 ADX decline (TF3 = index 3)
        double adxM15Buf[2];
        if (adxHandles[TF3] != INVALID_HANDLE && CopyBuffer(adxHandles[TF3], 0, 0, 2, adxM15Buf) == 2) {
            bool m15Declining = (adxM15Buf[0] < adxM15Buf[1]);
            if (m15Declining && adxM15Buf[0] >= ADX_LOW_THRESHOLD) {
                points += 1;  // M15 ADX also declining - stronger confirmation
            }
        }
        
        return points;
    }
    
    int GetHTFADXDeclineBonus() {
        return m_cachedHTFADXDeclineBonus;
    }
    
    //--------------------------------------------------------------------
    // EXTREME BAR INDEX HELPERS (cached versions for M3)
    //--------------------------------------------------------------------
    
    // Use cached M3 OHLC - no CopyBuffer!
    int GetCachedLowBarIndex() {
        if (!m_m3OHLCCached) return -1;
        int lowestIdx = 0;
        double lowestVal = m_cachedM3Low[0];
        int bars = GetM3OHLCCacheBars();
        for (int i = 1; i < bars; i++) {
            if (m_cachedM3Low[i] < lowestVal) {
                lowestVal = m_cachedM3Low[i];
                lowestIdx = i;
            }
        }
        return lowestIdx;
    }
    
    int GetCachedHighBarIndex() {
        if (!m_m3OHLCCached) return -1;
        int highestIdx = 0;
        double highestVal = m_cachedM3High[0];
        int bars = GetM3OHLCCacheBars();
        for (int i = 1; i < bars; i++) {
            if (m_cachedM3High[i] > highestVal) {
                highestVal = m_cachedM3High[i];
                highestIdx = i;
            }
        }
        return highestIdx;
    }
    
    // Original functions kept for GetRecentExtreme (used in SL calculation)
    int GetRecentExtremeBarIndex(ENUM_TIMEFRAMES timeFrame, int lookbackBars, bool findLow) {
        if (findLow) {
            return GetRecentLowBarIndex(timeFrame, lookbackBars);
        } else {
            return GetRecentHighBarIndex(timeFrame, lookbackBars);
        }
    }
    
    int GetRecentLowBarIndex(ENUM_TIMEFRAMES timeFrame, int lookbackBars) {
        double lows[];
        ArraySetAsSeries(lows, true);
        if (CopyLow(_Symbol, timeFrame, 0, lookbackBars, lows) <= 0) return -1;
        
        int lowestIndex = 0;
        double lowestLow = lows[0];
        for (int i = 1; i < lookbackBars; i++) {
            if (lows[i] < lowestLow) {
                lowestLow = lows[i];
                lowestIndex = i;
            }
        }
        return lowestIndex;
    }
    
    int GetRecentHighBarIndex(ENUM_TIMEFRAMES timeFrame, int lookbackBars) {
        double highs[];
        ArraySetAsSeries(highs, true);
        if (CopyHigh(_Symbol, timeFrame, 0, lookbackBars, highs) <= 0) return -1;
        
        int highestIndex = 0;
        double highestHigh = highs[0];
        for (int i = 1; i < lookbackBars; i++) {
            if (highs[i] > highestHigh) {
                highestHigh = highs[i];
                highestIndex = i;
            }
        }
        return highestIndex;
    }

    // Entry-specific config overrides
    virtual double GetRRBoostMultiplier() const { return 1.02; }
    virtual bool GetUsesDetectionRR() const { return true; }
    virtual bool IsCounterTrend() const { return true; }
    virtual bool GetUseConvictionScoring() const { return USE_CONVICTION_SCORING_E3; }
    virtual bool GetUseHTFVeto() const { return USE_HTF_VETO_E3; }
    virtual int GetConvictionThreshold() const { return CONVICTION_THRESHOLD_E3; }
    virtual bool GetAcceptHighRisk() const { return ACCEPT_HIGH_RISK_E3_ENTRIES; }
    virtual int GetHighRiskMomentumCheck() const { return (int)HIGH_RISK_E3_MOMENTUM_CHECK; }
    virtual double GetLotMultiplier() const { return E3_LOT_MULTIPLIER; }
    virtual double GetMaxLossRatio() const { return MAX_LOSS_RATIO_E3; }
    virtual bool GetVolLotAdjEnabled() const { return VOL_LOT_ADJ_E3; }
    virtual bool GetRecoveryLadderEnabled() const { return E3_USE_RECOVERY_LADDER; }
    virtual int GetRecoveryBoostThreshold() const { return E3_MIN_EXHAUSTION_SCORE + 1; }
    virtual bool GetEnableScoreDropExit() const { return ENABLE_SCORE_DROP_EXIT_E3; }
    virtual int GetScoreDropThreshold() const { return SCORE_DROP_THRESHOLD_E3; }
    virtual bool GetEnableDIFlipExit() const { return ENABLE_DI_FLIP_FAST_EXIT_E3; }
    virtual bool GetEnablePanicADXExit() const { return ENABLE_FAST_ADX_PANIC_EXIT_E3; }
    virtual double GetPanicMinSLUsedRatio() const { return PANIC_MIN_SL_USED_RATIO_E3; }
};

#endif // ENTRY3_MQH
