//+------------------------------------------------------------------+
//| Entry4.mqh - E4 Ichimoku Cloud Cross Entry (Early Trend)         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef ENTRY4_MQH
#define ENTRY4_MQH

#include "EntryBase.mqh"

//+------------------------------------------------------------------+
//| Entry4: E4 Ichimoku Cloud Cross (earlier entry than E1)          |
//| Based on E1 structure but uses Ichimoku cloud crossing trigger   |
//+------------------------------------------------------------------+
class Entry4 : public EntryBase {
public:
    Entry4() : EntryBase("E4", ENTRY_L_E4, ENABLE_E4_ENTRIES) {
        InitializeDefaults();
        SaveBaselines();
    }
    
protected:
    virtual void InitializeDefaults() override {
        m_config.isActive = ENABLE_ADAPTIVE_E4;
        
        // E4 Adaptive timing (same as E1)
        m_config.adaptiveMinTradesFirst = ADAPTIVE_MIN_TRADES_FIRST;
        m_config.adaptiveCheckInterval = ADAPTIVE_CHECK_EVERY_N_TRADES;
        m_config.adaptiveMaxDaysBetween = ADAPTIVE_MAX_DAYS_BETWEEN_ADJUSTMENTS;
        
        // Entry filters (same as E1)
        m_config.minADX = E1_MIN_MOMENTUM_ADX;
        m_config.minDISpread = 5.0;
        m_config.highRiskMinADX = E1_HIGH_RISK_MIN_ADX;
        m_config.highRiskMinDISpread = E1_HIGH_RISK_MIN_DI_SPREAD;
        
        // Stop Loss (E4 uses same logic as E1)
        m_config.emaDistancePips = SL_EMA_DISTANCE;
        m_config.atrMultiplier = E4_ATR_SL_CAP_MULTIPLIER;
        m_config.useATRBased = E4_USE_ATR_SL_ARBITRATION;
        m_config.minSLSpreadMultiplier = MIN_SL_SPREAD_MULT;

        // Take Profit
        m_config.rewardRatio = E4_RR;
        m_config.rewardRatioSideway = E4_RR_SIDEWAY;
        m_config.partialTPTrigger = E4_PARTIAL_TP_TRIGGER;
        m_config.partialTPRatio = E4_PARTIAL_TP_RATIO;
        
        // TP Extension
        m_config.maxTPExtensions = E4_MAX_TP_EXTENSIONS;
        
        // Trailing SL
        m_config.trailingFactor = E4_TRAILING_SL_FACTOR;
        m_config.breakevenBuffer = E4_SL_TO_BREAKEVEN_BUFFER;
        m_config.useADXFilter = false;
        
        // Early Exit
        m_config.earlyCutSLRatio = E4_EARLY_CUT_SL_RATIO;
        m_config.adxPeriodForExit = 14;
        m_config.minADXToHold = 18.0;
        
        // Phase 2: Laddered Extensions (same as E1)
        m_config.enableLadderedExtensions = E4_ENABLE_LADDERED_EXTENSIONS;
        m_config.ladderStage1Multiplier = E4_LADDER_STAGE1_MULTIPLIER;
        m_config.ladderStage2Multiplier = E4_LADDER_STAGE2_MULTIPLIER;
        m_config.ladderStage3Multiplier = E4_LADDER_STAGE3_MULTIPLIER;
        m_config.ladderStage1TrailRatio = E4_LADDER_STAGE1_TRAIL_RATIO;
        m_config.ladderStage2TrailRatio = E4_LADDER_STAGE2_TRAIL_RATIO;
        m_config.ladderStage3TrailRatio = E4_LADDER_STAGE3_TRAIL_RATIO;
        
        ValidateAndClampParams();
    }
    
public:
    // E4-specific detection logic (based on Ichimoku cloud cross)
    virtual DetectionResult Detect() override {
        DetectionResult result;
        result.detected = false;
        result.rawSLDistancePips = 0.0;
        result.bufferedSLDistancePips = 0.0;
        
        // Session loss limit check (hard stop after N real losses)
        if (sessionLossCount >= MAX_SESSION_LOSSES) {
            if(showDebug) Print("[E4] Session loss limit reached: ", sessionLossCount, "/", MAX_SESSION_LOSSES);
            return result;
        }
        
        // Session total trade limit check (legacy, emergency brake)
        if (tradeSLTPCountInSession > MAX_SLTP_COUNT_PER_SESSION) {
            if(showDebug) Print("[E4] Session trade limit reached: ", tradeSLTPCountInSession);
            return result;
        }
        
        // Get current price
        double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
        
        // Check open positions (including E4)
        int checkOpenLE1, checkOpenSE1, checkOpenLE2, checkOpenSE2, checkOpenLE3, checkOpenSE3;
        int checkOpenLE4, checkOpenSE4;
        CheckOpenPositions(checkOpenLE1, checkOpenSE1, checkOpenLE2, checkOpenSE2, checkOpenLE3, checkOpenSE3, checkOpenLE4, checkOpenSE4);
        
        // === LONG E4 Detection ===
        if (lastIchiCloudCrossUp != -1 && checkOpenLE4 == -1) {
            // Check cross age - expire stale triggers (Pine parity)
            int crossAge = currentBar - lastIchiCloudCrossUp;
            if (crossAge > E4_MAX_CROSS_AGE) {
                lastIchiCloudCrossUp = -1;
                if(showDebug) Print("[E4] L-E4 cross expired (age=", crossAge, " > max=", E4_MAX_CROSS_AGE, ")");
            } else {
                bool isLowConfidence = false;
                string lowConfidenceReason = "";
                int trendQuality = 0;
                
                if (CheckE4EntryConditions_Internal(true, currentPrice, "L-E4", isLowConfidence, lowConfidenceReason, trendQuality)) {
                    // Consume trigger after conditions pass
                    lastIchiCloudCrossUp = -1;
                    
                    // Always report detection - let ProcessEntryConvictionAndConfidence handle filtering
                    result.detected = true;
                    result.isLong = true;
                    result.entryPrice = currentPrice;
                    
                    // Calculate SL/TP (same logic as E1)
                    double recentHigh = iHigh(_Symbol, TF_ARRAY[TF0], iHighest(_Symbol, TF_ARRAY[TF0], MODE_HIGH, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    double recentLow = iLow(_Symbol, TF_ARRAY[TF0], iLowest(_Symbol, TF_ARRAY[TF0], MODE_LOW, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    
                    // E4 SL: Same as E1 - EMA100 with distance to EMA200
                    double ema100 = GetEMA(TF0, EMA3, ENTRY_SHIFT);
                    double ema200 = GetEMA(TF0, EMA4, ENTRY_SHIFT);
                    double emaDistance = MathAbs(ema100 - ema200);
                    double e4SLLevel = ema100 - (emaDistance * 0.75);
                    
                    double rawSLDistancePips = 0.0;
                    double bufferedSLDistancePips = 0.0;
                    result.stopLoss = CalculateStopLossWithCustomEMA(true, currentPrice, recentHigh, recentLow,
                                                                     e4SLLevel, "E4", 4,
                                                                     rawSLDistancePips, bufferedSLDistancePips);
                    result.rawSLDistancePips = rawSLDistancePips;
                    result.bufferedSLDistancePips = bufferedSLDistancePips;
                    
                    // Calculate TP based on RR ratio (use sideway RR if in sideway market)
                    double slDistance = MathAbs(currentPrice - result.stopLoss);
                    double e4RRToUse = IsInSidewayRange() ? E4_RR_SIDEWAY : CFG.rrLongE4;
                    result.takeProfit = currentPrice + (slDistance * e4RRToUse);
                    
                    result.entryType = ENTRY_L_E4;
                    result.isLowConfidence = isLowConfidence;
                    result.lowConfidenceReason = lowConfidenceReason;
                    result.trendQualityScore = trendQuality;
                }
            }
        }
        
        // === SHORT E4 Detection (only if LONG didn't trigger) ===
        // E4_LONG_ONLY: MT5 isolation showed E4 shorts are net-loser (PF 0.555) while longs are PF~1.40.
        if (!result.detected && !E4_LONG_ONLY && lastIchiCloudCrossDown != -1 && checkOpenSE4 == -1) {
            // Check cross age - expire stale triggers (Pine parity)
            int crossAge = currentBar - lastIchiCloudCrossDown;
            if (crossAge > E4_MAX_CROSS_AGE) {
                lastIchiCloudCrossDown = -1;
                if(showDebug) Print("[E4] S-E4 cross expired (age=", crossAge, " > max=", E4_MAX_CROSS_AGE, ")");
            } else {
                bool isLowConfidence = false;
                string lowConfidenceReason = "";
                int trendQuality = 0;
                
                if (CheckE4EntryConditions_Internal(false, currentPrice, "S-E4", isLowConfidence, lowConfidenceReason, trendQuality)) {
                    // Consume trigger after conditions pass
                    lastIchiCloudCrossDown = -1;
                    
                    // Always report detection - let ProcessEntryConvictionAndConfidence handle filtering
                    result.detected = true;
                    result.isLong = false;
                    result.entryPrice = currentPrice;
                    
                    double recentHigh = iHigh(_Symbol, TF_ARRAY[TF0], iHighest(_Symbol, TF_ARRAY[TF0], MODE_HIGH, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    double recentLow = iLow(_Symbol, TF_ARRAY[TF0], iLowest(_Symbol, TF_ARRAY[TF0], MODE_LOW, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    
                    // E4 SL: Same as E1 - EMA100 with distance to EMA200
                    double ema100 = GetEMA(TF0, EMA3, ENTRY_SHIFT);
                    double ema200 = GetEMA(TF0, EMA4, ENTRY_SHIFT);
                    double emaDistance = MathAbs(ema100 - ema200);
                    double e4SLLevel = ema100 + (emaDistance * 0.75);
                    
                    double rawSLDistancePips = 0.0;
                    double bufferedSLDistancePips = 0.0;
                    result.stopLoss = CalculateStopLossWithCustomEMA(false, currentPrice, recentHigh, recentLow,
                                                                     e4SLLevel, "E4", 4,
                                                                     rawSLDistancePips, bufferedSLDistancePips);
                    result.rawSLDistancePips = rawSLDistancePips;
                    result.bufferedSLDistancePips = bufferedSLDistancePips;
                    
                    // Calculate TP based on RR ratio (use sideway RR if in sideway market)
                    double slDistance = MathAbs(currentPrice - result.stopLoss);
                    double e4RRToUse = IsInSidewayRange() ? E4_RR_SIDEWAY : CFG.rrShortE4;
                    result.takeProfit = currentPrice - (slDistance * e4RRToUse);
                    
                    result.entryType = ENTRY_S_E4;
                    result.isLowConfidence = isLowConfidence;
                    result.lowConfidenceReason = lowConfidenceReason;
                    result.trendQualityScore = trendQuality;
                }
            }
        }
        
        return result;
    }
    
    virtual double GetTargetWinrate() override { 
        return 0.60;  // 60% target for E4 (slightly lower than E1 due to earlier entries)
    }
    
private:
    //--------------------------------------------------------------------
    // E4-SPECIFIC CONDITION CHECKING (Pine Script parity)
    //--------------------------------------------------------------------
    bool CheckE4EntryConditions_Internal(bool isLong, double currentPrice, string entryType,
                                        bool &isLowConfidence, string &lowConfidenceReason,
                                        int &trendQualityOut) {
        isLowConfidence = false;
        lowConfidenceReason = "";
        
        // STEP 0: Ichimoku Quality Filters (cloud thickness helps profitability)
        if (!CheckIchimokuQuality(isLong, entryType,
                                 E4_MIN_CLOUD_THICKNESS_ATR_MULT,
                                 E4_REQUIRE_TENKAN_KIJUN_ALIGN,
                                 E4_REQUIRE_CHIKOU_CLEAR)) {
            return false;
        }
        
        // STEP 0.1: E4-specific sideway filter (stricter than global threshold)
        if (cachedSidewaysScore > E4_MAX_SIDEWAY_SCORE) {
            TrackEntryAttempt(entryType, false, "sideway");
            return false;
        }
        
        // STEP 0.5: HTF Trend Direction Filter - block entries against higher timeframe trend
        // Uses cached ADX/DI values (index 2 = M5, index 3 = M15)
        if (E4_HTF_TREND_FILTER != HTF_DISABLED) {
            bool m5Bullish = false, m5Bearish = false, m5Valid = false;
            bool m15Bullish = false, m15Bearish = false, m15Valid = false;
            
            // Check M5 trend if needed
            if (E4_HTF_TREND_FILTER == HTF_M5_ONLY || E4_HTF_TREND_FILTER == HTF_M5_AND_M15 || E4_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                double m5ADX = cache.adx[2];
                double m5DISpread = MathAbs(cache.diPlus[2] - cache.diMinus[2]);
                if (m5ADX >= E4_HTF_MIN_ADX && m5DISpread >= E4_HTF_MIN_DI_SPREAD) {
                    m5Valid = true;
                    m5Bullish = (cache.diPlus[2] > cache.diMinus[2]);
                    m5Bearish = !m5Bullish;
                }
            }
            
            // Check M15 trend if needed
            if (E4_HTF_TREND_FILTER == HTF_M15_ONLY || E4_HTF_TREND_FILTER == HTF_M5_AND_M15 || E4_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                double m15ADX = cache.adx[3];
                double m15DISpread = MathAbs(cache.diPlus[3] - cache.diMinus[3]);
                if (m15ADX >= E4_HTF_MIN_ADX && m15DISpread >= E4_HTF_MIN_DI_SPREAD) {
                    m15Valid = true;
                    m15Bullish = (cache.diPlus[3] > cache.diMinus[3]);
                    m15Bearish = !m15Bullish;
                }
            }
            
            // Apply filter based on mode
            bool blockLong = false, blockShort = false;
            if (E4_HTF_TREND_FILTER == HTF_M5_ONLY && m5Valid) {
                blockLong = m5Bearish;
                blockShort = m5Bullish;
            } else if (E4_HTF_TREND_FILTER == HTF_M15_ONLY && m15Valid) {
                blockLong = m15Bearish;
                blockShort = m15Bullish;
            } else if (E4_HTF_TREND_FILTER == HTF_M5_AND_M15 && m5Valid && m15Valid) {
                // Both must agree to block
                blockLong = (m5Bearish && m15Bearish);
                blockShort = (m5Bullish && m15Bullish);
            } else if (E4_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                // Either one blocks (more aggressive filtering)
                blockLong = (m5Valid && m5Bearish) || (m15Valid && m15Bearish);
                blockShort = (m5Valid && m5Bullish) || (m15Valid && m15Bullish);
            }
            
            if (isLong && blockLong) {
                if (showDebug) Print("[E4] L-E4 blocked: HTF bearish");
                TrackEntryAttempt(entryType, false, "htf_trend");
                return false;
            }
            if (!isLong && blockShort) {
                if (showDebug) Print("[E4] S-E4 blocked: HTF bullish");
                TrackEntryAttempt(entryType, false, "htf_trend");
                return false;
            }
        }
        
        // STEP 1: M5 DI Directional Alignment (trade WITH M5 momentum)
        if (E4_REQUIRE_M5_DI_ALIGN && !CheckM5DIAlignment(isLong, entryType)) {
            return false;
        }
        
        // E4 requires EMA 3-stack alignment on M1 (ALWAYS required)
        // M3 alignment can be bypassed with momentum (based on E4_MOMENTUM_BYPASS_LEVEL)
        bool m1Aligned = CheckE4EMAAlignmentM1(isLong);
        bool m3Aligned = CheckE4EMAAlignmentM3(isLong);
        
        // M1 is ALWAYS required - Pine: "M1 alignment is ALWAYS required"
        if (!m1Aligned) {
            TrackEntryAttempt(entryType, false, "ema_m1");
            return false;
        }
        
        // M3 alignment check with momentum bypass
        // Level 0: require both M1+M3
        // Level 1/2: bypass M3 if extreme momentum present (M1 still required)
        bool emasAlignedOrBypassed = false;
        if (E4_MOMENTUM_BYPASS_LEVEL == 0) {
            emasAlignedOrBypassed = m1Aligned && m3Aligned;
        } else {
            // Check for extreme momentum (using cached DI spread)
            bool extremeMomentum = false;
            if (isLong) {
                extremeMomentum = (cache.diPlus[0] - cache.diMinus[0]) >= EXTREME_DI_SPREAD_THRESHOLD;
            } else {
                extremeMomentum = (cache.diMinus[0] - cache.diPlus[0]) >= EXTREME_DI_SPREAD_THRESHOLD;
            }
            emasAlignedOrBypassed = m1Aligned && (m3Aligned || extremeMomentum);
        }
        
        if (!emasAlignedOrBypassed) {
            TrackEntryAttempt(entryType, false, "ema_alignment");
            return false;
        }
        
        // Price position check with 5-pip TOLERANCE (Pine parity)
        // Pine: close_1m > (ema25_1m - e4PriceTol) and close_1m > (cloudTop_m1 - e4PriceTol)
        double e4Tolerance = 5.0 * pipSize;
        double ema25 = GetEMA(TF0, EMA1, ENTRY_SHIFT);
        double cloudTop = MathMax(cache.ichimokuSpanA_M1_Current, cache.ichimokuSpanB_M1_Current);
        double cloudBottom = MathMin(cache.ichimokuSpanA_M1_Current, cache.ichimokuSpanB_M1_Current);
        
        if (isLong) {
            // Price must be above BOTH EMA25 AND cloud top (with tolerance)
            if (currentPrice <= (ema25 - e4Tolerance) || currentPrice <= (cloudTop - e4Tolerance)) {
                TrackEntryAttempt(entryType, false, "price_position");
                return false;
            }
        } else {
            // Price must be below BOTH EMA25 AND cloud bottom (with tolerance)
            if (currentPrice >= (ema25 + e4Tolerance) || currentPrice >= (cloudBottom + e4Tolerance)) {
                TrackEntryAttempt(entryType, false, "price_position");
                return false;
            }
        }
        
        // E4-specific minimum momentum ADX check (critical for early trend entries)
        double m1ADX = cache.adx[0];
        if (m1ADX < E4_MIN_MOMENTUM_ADX) {
            TrackEntryAttempt(entryType, false, "momentum");
            if (showDebug) Print("[E4] ", entryType, " blocked: M1 ADX ", DoubleToString(m1ADX, 1), " < min ", DoubleToString(E4_MIN_MOMENTUM_ADX, 1));
            return false;
        }
        
        // Trend quality - HARD BLOCK for E4 (early trend needs strong conviction)
        TREND_STATE requiredTrend = isLong ? TREND_BULL : TREND_BEAR;
        trendQualityOut = GetTrendQualityScore(requiredTrend, 4);  // Pass 4 for E4
        
        if (trendQualityOut < MIN_TREND_QUALITY_E4) {
            TrackEntryAttempt(entryType, false, "trend_quality");
            if (showDebug) Print("[E4] ", entryType, " blocked: Trend quality ", trendQualityOut, "/11 < min ", MIN_TREND_QUALITY_E4);
            return false;  // HARD BLOCK - E4 needs strong trend confirmation
        }
        
        // RSI divergence veto: block if M3 RSI diverges against trade direction
        if (HasRSIDivergenceAgainstTrade(isLong, entryType)) {
            TrackEntryAttempt(entryType, false, "rsi_div");
            return false;
        }
        
        return true;
    }
    
    // M5 DI Directional Alignment - trade WITH M5 momentum direction
    // L-E4: M5 DI+ > DI- (bullish M5)
    // S-E4: M5 DI- > DI+ (bearish M5)
    bool CheckM5DIAlignment(bool isLong, string entryType) {
        double diPlusM5 = cache.diPlus[TF2];
        double diMinusM5 = cache.diMinus[TF2];
        double adxM5 = cache.adx[TF2];
        
        // If M5 is ranging (low ADX), allow entry
        if (adxM5 < ADX_LOW_THRESHOLD) {
            return true;
        }
        
        if (isLong) {
            if (diPlusM5 <= diMinusM5) {
                if (showDebug) Print("[E4] L-E4 blocked: M5 not bullish (DI+=", 
                    DoubleToString(diPlusM5, 1), " DI-=", DoubleToString(diMinusM5, 1), ")");
                TrackEntryAttempt(entryType, false, "m5_di_align");
                return false;
            }
        } else {
            if (diMinusM5 <= diPlusM5) {
                if (showDebug) Print("[E4] S-E4 blocked: M5 not bearish (DI+=", 
                    DoubleToString(diPlusM5, 1), " DI-=", DoubleToString(diMinusM5, 1), ")");
                TrackEntryAttempt(entryType, false, "m5_di_align");
                return false;
            }
        }
        
        return true;
    }
    
    // E4 EMA alignment M1: 3-stack (25 > 75 > 100 for long)
    bool CheckE4EMAAlignmentM1(bool isLong) {
        double ema25 = GetEMA(TF0, EMA1, ENTRY_SHIFT);
        double ema75 = GetEMA(TF0, EMA2, ENTRY_SHIFT);
        double ema100 = GetEMA(TF0, EMA3, ENTRY_SHIFT);
        
        if (isLong) {
            return (ema25 > ema75 && ema75 > ema100);
        } else {
            return (ema25 < ema75 && ema75 < ema100);
        }
    }
    
    // E4 EMA alignment M3: 3-stack (25 > 75 > 100 for long)
    bool CheckE4EMAAlignmentM3(bool isLong) {
        double ema25 = GetEMA(TF1, EMA1, ENTRY_SHIFT);
        double ema75 = GetEMA(TF1, EMA2, ENTRY_SHIFT);
        double ema100 = GetEMA(TF1, EMA3, ENTRY_SHIFT);
        
        if (isLong) {
            return (ema25 > ema75 && ema75 > ema100);
        } else {
            return (ema25 < ema75 && ema75 < ema100);
        }
    }
    
public:
    // Lightweight direction check for E1 conflict detection (no full detection)
    // Returns true if potential E4 would be LONG, false if SHORT
    bool PeekDirection() {
        // E4 uses Ichimoku cloud crossing triggers
        if (lastIchiCloudCrossUp != -1 && lastIchiCloudCrossDown == -1) {
            return true;  // Long trigger active
        }
        if (lastIchiCloudCrossDown != -1 && lastIchiCloudCrossUp == -1) {
            return false;  // Short trigger active
        }
        // Both or neither active - use price position vs cloud as tiebreaker
        double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
        double senkouA = cache.ichimokuSpanA_M1_Current;
        double senkouB = cache.ichimokuSpanB_M1_Current;
        double cloudTop = MathMax(senkouA, senkouB);
        return (currentPrice > cloudTop);  // Above cloud = potential long
    }

    // Entry-specific config overrides
    virtual double GetRRBoostMultiplier() const { return 1.02; }
    virtual bool GetUseConvictionScoring() const { return USE_CONVICTION_SCORING_E4; }
    virtual bool GetUseHTFVeto() const { return USE_HTF_VETO_E4; }
    virtual int GetConvictionThreshold() const { return CONVICTION_THRESHOLD_E4; }
    virtual bool GetAcceptHighRisk() const { return ACCEPT_HIGH_RISK_E4_ENTRIES; }
    virtual int GetHighRiskMomentumCheck() const { return (int)HIGH_RISK_E4_MOMENTUM_CHECK; }
    virtual double GetMaxLossRatio() const { return MAX_LOSS_RATIO_E4; }
    virtual bool GetVolLotAdjEnabled() const { return VOL_LOT_ADJ_E4; }
    virtual bool GetRecoveryLadderEnabled() const { return E4_USE_RECOVERY_LADDER; }
    virtual int GetRecoveryBoostThreshold() const { return MIN_TREND_QUALITY_E4 + 1; }
    virtual bool GetEnableScoreDropExit() const { return ENABLE_SCORE_DROP_EXIT_E4; }
    virtual int GetScoreDropThreshold() const { return SCORE_DROP_THRESHOLD_E4; }
    virtual bool GetEnableDIFlipExit() const { return ENABLE_DI_FLIP_FAST_EXIT_E4; }
    virtual bool GetExitInIchiCloud() const { return EXIT_IN_ICHI_CLOUD_E4; }
    virtual bool GetEnablePanicADXExit() const { return ENABLE_FAST_ADX_PANIC_EXIT_E4; }
};

#endif // ENTRY4_MQH
