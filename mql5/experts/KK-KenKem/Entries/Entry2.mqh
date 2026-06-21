//+------------------------------------------------------------------+
//| Entry2.mqh - E2 Pullback Entry (EMA100/200 Touch)               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef ENTRY2_MQH
#define ENTRY2_MQH

#include "EntryBase.mqh"

//+------------------------------------------------------------------+
//| Entry2: E2 Pullback (EMA100/200 touch detection)                |
//+------------------------------------------------------------------+
class Entry2 : public EntryBase {
public:
    Entry2() : EntryBase("E2", ENTRY_L_E2, ENABLE_E2_ENTRIES) {
        InitializeDefaults();  // Call after base constructor completes
        SaveBaselines();  // Save original input values as baselines for adaptation
    }
    
protected:
    // Initialize defaults from E2_* input parameters
    virtual void InitializeDefaults() override {
        m_config.isActive = ENABLE_ADAPTIVE_E2;
        
        // E2 Adaptive timing (use global defaults - adjust after observing actual frequency)
        m_config.adaptiveMinTradesFirst = ADAPTIVE_MIN_TRADES_FIRST;
        m_config.adaptiveCheckInterval = ADAPTIVE_CHECK_EVERY_N_TRADES;
        m_config.adaptiveMaxDaysBetween = ADAPTIVE_MAX_DAYS_BETWEEN_ADJUSTMENTS;
        
        // Entry filters
        m_config.minADX = E2_MIN_MOMENTUM_ADX;
        m_config.minDISpread = 5.0;
        m_config.highRiskMinADX = E2_HIGH_RISK_MIN_ADX;
        m_config.highRiskMinDISpread = E2_HIGH_RISK_MIN_DI_SPREAD;
        
        // Stop Loss (E2 uses EMA-based SL with optional ATR arbitration)
        m_config.emaDistancePips = SL_EMA_DISTANCE;
        m_config.atrMultiplier = E2_ATR_SL_CAP_MULTIPLIER;  // Used for ATR arbitration cap
        m_config.useATRBased = E2_USE_ATR_SL_ARBITRATION;   // From input param
        m_config.minSLSpreadMultiplier = MIN_SL_SPREAD_MULT;

        // Take Profit
        m_config.rewardRatio = E2_RR;
        m_config.rewardRatioSideway = E2_RR_SIDEWAY;
        m_config.partialTPTrigger = E2_PARTIAL_TP_TRIGGER;
        m_config.partialTPRatio = E2_PARTIAL_TP_RATIO;
        
        // TP Extension (trigger/pips now use dynamic global values)
        m_config.maxTPExtensions = E2_MAX_TP_EXTENSIONS;
        
        // Trailing SL
        m_config.trailingFactor = E2_TRAILING_SL_FACTOR;
        m_config.breakevenBuffer = E2_SL_TO_BREAKEVEN_BUFFER;
        
        // Early Exit
        m_config.earlyCutSLRatio = E2_EARLY_CUT_SL_RATIO;
        m_config.adxPeriodForExit = 14;
        
        // Phase 2: Laddered Extensions (E2 - Conservative)
        m_config.enableLadderedExtensions = E2_ENABLE_LADDERED_EXTENSIONS;
        m_config.ladderStage1Multiplier = E2_LADDER_STAGE1_MULTIPLIER;
        m_config.ladderStage2Multiplier = E2_LADDER_STAGE2_MULTIPLIER;
        m_config.ladderStage3Multiplier = E2_LADDER_STAGE3_MULTIPLIER;
        m_config.ladderStage1TrailRatio = E2_LADDER_STAGE1_TRAIL_RATIO;
        m_config.ladderStage2TrailRatio = E2_LADDER_STAGE2_TRAIL_RATIO;
        m_config.ladderStage3TrailRatio = E2_LADDER_STAGE3_TRAIL_RATIO;
        
        ValidateAndClampParams();
    }
    
public:
    virtual DetectionResult Detect() override {
        DetectionResult result;
        result.detected = false;
        result.rawSLDistancePips = 0.0;
        result.bufferedSLDistancePips = 0.0;

        // Session loss limit check (hard stop after N real losses)
        if (sessionLossCount >= MAX_SESSION_LOSSES) {
            if(showDebug) Print("[E2] Session loss limit reached: ", sessionLossCount, "/", MAX_SESSION_LOSSES);
            return result;
        }
        
        // Session total trade limit check (legacy, emergency brake)
        if (tradeSLTPCountInSession > MAX_SLTP_COUNT_PER_SESSION) {
            if(showDebug) Print("[E2] Session trade limit reached: ", tradeSLTPCountInSession);
            return result;
        }
        
        // Get current price
        double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
        
        // Check open positions
        int checkOpenLE1, checkOpenSE1, checkOpenLE2, checkOpenSE2, checkOpenLE3, checkOpenSE3;
        CheckOpenPositions(checkOpenLE1, checkOpenSE1, checkOpenLE2, checkOpenSE2, checkOpenLE3, checkOpenSE3);
        
        // === LONG E2 Detection ===
        // Expire stale touch triggers
        int barIndex = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
        if (lastEma75TouchUp != -1 && (barIndex - lastEma75TouchUp) > E2_MAX_TOUCH_AGE) {
            if(showDebug) Print("[E2] L-E2 touch expired: age=", (barIndex - lastEma75TouchUp), " > max=", E2_MAX_TOUCH_AGE);
            lastEma75TouchUp = -1;
        }
        if (lastEma75TouchUp != -1 && checkOpenLE2 == -1) {
            bool isLowConfidence = false;
            string lowConfidenceReason = "";
            int trendQuality = 0;
            
            if (CheckE2EntryConditions_Internal(true, currentPrice, "L-E2", isLowConfidence, lowConfidenceReason, trendQuality)) {
                if (!isLowConfidence || SEND_LOW_CONFIDENCE_SIGNALS) {
                    result.detected = true;
                    result.isLong = true;
                    result.entryPrice = currentPrice;
                    
                    double recentHigh = iHigh(_Symbol, TF_ARRAY[TF0], iHighest(_Symbol, TF_ARRAY[TF0], MODE_HIGH, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    double recentLow = iLow(_Symbol, TF_ARRAY[TF0], iLowest(_Symbol, TF_ARRAY[TF0], MODE_LOW, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    
                    double rawSLDistancePips = 0.0;
                    double bufferedSLDistancePips = 0.0;
                    result.stopLoss = CalculateStopLoss(true, currentPrice, recentHigh, recentLow, EMA3, "E2", 2,
                                                        rawSLDistancePips, bufferedSLDistancePips);
                    result.rawSLDistancePips = rawSLDistancePips;
                    result.bufferedSLDistancePips = bufferedSLDistancePips;
                    
                    // Calculate TP
                    double slDistance = MathAbs(currentPrice - result.stopLoss);
                    result.takeProfit = currentPrice + (slDistance * CFG.rrLongE2);
                    
                    result.entryType = ENTRY_L_E2;
                    result.isLowConfidence = isLowConfidence;
                    result.lowConfidenceReason = lowConfidenceReason;
                    result.trendQualityScore = trendQuality;
                    
                    lastEma75TouchUp = -1;
                    
                    //if(showDebug) Print("[E2] LONG detected at ", currentPrice);
                }
            }
        }
        
        // === SHORT E2 Detection ===
        // Expire stale touch triggers
        if (lastEma75TouchDown != -1 && (barIndex - lastEma75TouchDown) > E2_MAX_TOUCH_AGE) {
            if(showDebug) Print("[E2] S-E2 touch expired: age=", (barIndex - lastEma75TouchDown), " > max=", E2_MAX_TOUCH_AGE);
            lastEma75TouchDown = -1;
        }
        if (!result.detected && lastEma75TouchDown != -1 && checkOpenSE2 == -1) {
            bool isLowConfidence = false;
            string lowConfidenceReason = "";
            int trendQuality = 0;
            
            if (CheckE2EntryConditions_Internal(false, currentPrice, "S-E2", isLowConfidence, lowConfidenceReason, trendQuality)) {
                if (!isLowConfidence || SEND_LOW_CONFIDENCE_SIGNALS) {
                    result.detected = true;
                    result.isLong = false;
                    result.entryPrice = currentPrice;
                    
                    double recentHigh = iHigh(_Symbol, TF_ARRAY[TF0], iHighest(_Symbol, TF_ARRAY[TF0], MODE_HIGH, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    double recentLow = iLow(_Symbol, TF_ARRAY[TF0], iLowest(_Symbol, TF_ARRAY[TF0], MODE_LOW, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    
                    double rawSLDistancePips = 0.0;
                    double bufferedSLDistancePips = 0.0;
                    result.stopLoss = CalculateStopLoss(false, currentPrice, recentHigh, recentLow, EMA3, "E2", 2,
                                                        rawSLDistancePips, bufferedSLDistancePips);
                    result.rawSLDistancePips = rawSLDistancePips;
                    result.bufferedSLDistancePips = bufferedSLDistancePips;
                    
                    // Calculate TP
                    double slDistance = MathAbs(currentPrice - result.stopLoss);
                    result.takeProfit = currentPrice - (slDistance * CFG.rrShortE2);
                    
                    result.entryType = ENTRY_S_E2;
                    result.isLowConfidence = isLowConfidence;
                    result.lowConfidenceReason = lowConfidenceReason;
                    result.trendQualityScore = trendQuality;
                    
                    lastEma75TouchDown = -1;
                    
                    //if(showDebug) Print("[E2] SHORT detected at ", currentPrice);
                }
            }
        }
        
        return result;
    }
    
    virtual double GetTargetWinrate() override { return 0.66; }  // E2 target 66%

private:
    bool CheckE2EntryConditions_Internal(bool isLong, double currentPrice, string entryType,
                                        bool &isLowConfidence, string &lowConfidenceReason,
                                        int &trendQualityOut) {
        isLowConfidence = false;
        lowConfidenceReason = "";
        
        // HTF Trend Strength Filter - REQUIRE strong aligned macro trend for pullback entries
        // Unlike E1/E4 which only block counter-trend, E2 also blocks when HTF trend is WEAK.
        // Pullbacks in weak macro trends have poor follow-through.
        // Uses cached ADX/DI values (index 2 = M5, index 3 = M15)
        if (E2_HTF_TREND_FILTER != HTF_DISABLED) {
            bool m5Aligned = false;  // true = strong & matches trade direction
            bool m15Aligned = false;
            
            if (E2_HTF_TREND_FILTER == HTF_M5_ONLY || E2_HTF_TREND_FILTER == HTF_M5_AND_M15 || E2_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                double m5ADX = cache.adx[2];
                double m5DISpread = MathAbs(cache.diPlus[2] - cache.diMinus[2]);
                if (m5ADX >= E2_HTF_MIN_ADX && m5DISpread >= E2_HTF_MIN_DI_SPREAD) {
                    bool m5Bullish = (cache.diPlus[2] > cache.diMinus[2]);
                    m5Aligned = (isLong && m5Bullish) || (!isLong && !m5Bullish);
                }
            }
            
            if (E2_HTF_TREND_FILTER == HTF_M15_ONLY || E2_HTF_TREND_FILTER == HTF_M5_AND_M15 || E2_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                double m15ADX = cache.adx[3];
                double m15DISpread = MathAbs(cache.diPlus[3] - cache.diMinus[3]);
                if (m15ADX >= E2_HTF_MIN_ADX && m15DISpread >= E2_HTF_MIN_DI_SPREAD) {
                    bool m15Bullish = (cache.diPlus[3] > cache.diMinus[3]);
                    m15Aligned = (isLong && m15Bullish) || (!isLong && !m15Bullish);
                }
            }
            
            // Require aligned signal (block if weak OR counter-trend)
            bool htfOK = false;
            if (E2_HTF_TREND_FILTER == HTF_M5_ONLY)
                htfOK = m5Aligned;
            else if (E2_HTF_TREND_FILTER == HTF_M15_ONLY)
                htfOK = m15Aligned;
            else if (E2_HTF_TREND_FILTER == HTF_M5_AND_M15)
                htfOK = m5Aligned && m15Aligned;
            else if (E2_HTF_TREND_FILTER == HTF_M5_OR_M15)
                htfOK = m5Aligned || m15Aligned;
            
            if (!htfOK) {
                if (showDebug) Print("[E2] ", entryType, " blocked: HTF not strongly aligned");
                TrackEntryAttempt(entryType, false, "htf_trend");
                return false;
            }
        }
        
        // Multi-timeframe EMA check
        if (!isAllTimeframeEMAsReadyForEntry("E2", isLong, 1)) {
            TrackEntryAttempt(entryType, false, "mtf");
            return false;
        }
        
        // Price position check
        double ema25 = GetEMA(TF0, EMA1, ENTRY_SHIFT);
        if ((isLong && currentPrice <= ema25) || (!isLong && currentPrice >= ema25)) {
            TrackEntryAttempt(entryType, false, "mtf");
            return false;
        }
        
        // Trend quality
        TREND_STATE requiredTrend = isLong ? TREND_BULL : TREND_BEAR;
        trendQualityOut = GetTrendQualityScore(requiredTrend, 2);  // Pass 2 for E2
        if (trendQualityOut < MIN_TREND_QUALITY_E2) {
            TrackEntryAttempt(entryType, false, "trend_quality");
            return false;  // Hard block: preserves trigger for re-check next bar
        }
        
        // NOTE: HasSufficientMomentum() deliberately omitted for E2.
        // E2 is a pullback entry — M1 DI temporarily flips counter-direction during pullbacks,
        // causing CalculateMomentum() to block every attempt. E2 momentum is already gated by
        // trend quality (9/11), HTF filter (M5/M15), and multi-TF EMA alignment.
        
        // RSI divergence veto: block if M3 RSI diverges against trade direction
        if (HasRSIDivergenceAgainstTrade(isLong, entryType)) {
            TrackEntryAttempt(entryType, false, "rsi_div");
            return false;
        }
        
        return true;
    }

    // Entry-specific config overrides
    virtual double GetRRBoostMultiplier() const { return 1.04; }
    virtual bool GetUseConvictionScoring() const { return USE_CONVICTION_SCORING_E2; }
    virtual bool GetUseHTFVeto() const { return USE_HTF_VETO_E2; }
    virtual int GetConvictionThreshold() const { return CONVICTION_THRESHOLD_E2; }
    virtual bool GetAcceptHighRisk() const { return ACCEPT_HIGH_RISK_E2_ENTRIES; }
    virtual int GetHighRiskMomentumCheck() const { return (int)HIGH_RISK_E2_MOMENTUM_CHECK; }
    virtual double GetMaxLossRatio() const { return MAX_LOSS_RATIO_E2; }
    virtual bool GetVolLotAdjEnabled() const { return VOL_LOT_ADJ_E2; }
    virtual bool GetRecoveryLadderEnabled() const { return E2_USE_RECOVERY_LADDER; }
    virtual int GetRecoveryBoostThreshold() const { return MIN_TREND_QUALITY_E2 + 1; }
    virtual bool GetEnableScoreDropExit() const { return ENABLE_SCORE_DROP_EXIT_E2; }
    virtual int GetScoreDropThreshold() const { return SCORE_DROP_THRESHOLD_E2; }
    virtual bool GetEnableDIFlipExit() const { return ENABLE_DI_FLIP_FAST_EXIT_E2; }
    virtual bool GetExitInIchiCloud() const { return EXIT_IN_ICHI_CLOUD_E2; }
    virtual bool GetEnablePanicADXExit() const { return ENABLE_FAST_ADX_PANIC_EXIT_E2; }
};

#endif // ENTRY2_MQH
