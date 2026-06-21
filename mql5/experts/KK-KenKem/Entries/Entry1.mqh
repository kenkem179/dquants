//+------------------------------------------------------------------+
//| Entry1.mqh - E1 Trend Continuation Entry (EMA75 Cross)          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef ENTRY1_MQH
#define ENTRY1_MQH

#include "EntryBase.mqh"

//+------------------------------------------------------------------+
//| Entry1: E1 Trend Continuation (EMA75 crossover detection)       |
//+------------------------------------------------------------------+
class Entry1 : public EntryBase {
public:
    Entry1() : EntryBase("E1", ENTRY_L_E1, ENABLE_E1_ENTRIES) {
        InitializeDefaults();  // Call after base constructor completes
        SaveBaselines();  // Save original input values as baselines for adaptation
    }
    
protected:
    // Initialize defaults from E1_* input parameters
    virtual void InitializeDefaults() override {
        m_config.isActive = ENABLE_ADAPTIVE_E1;
        
        // E1 Adaptive timing (most frequent entry - use global defaults)
        m_config.adaptiveMinTradesFirst = ADAPTIVE_MIN_TRADES_FIRST;   // 10 trades
        m_config.adaptiveCheckInterval = ADAPTIVE_CHECK_EVERY_N_TRADES; // 15 trades
        m_config.adaptiveMaxDaysBetween = ADAPTIVE_MAX_DAYS_BETWEEN_ADJUSTMENTS; // 7 days
        
        // Entry filters
        m_config.minADX = E1_MIN_MOMENTUM_ADX;
        m_config.minDISpread = 5.0;
        m_config.highRiskMinADX = E1_HIGH_RISK_MIN_ADX;
        m_config.highRiskMinDISpread = E1_HIGH_RISK_MIN_DI_SPREAD;
        
        // Stop Loss (E1 uses EMA-based SL with optional ATR arbitration)
        m_config.emaDistancePips = SL_EMA_DISTANCE;
        m_config.atrMultiplier = E1_ATR_SL_CAP_MULTIPLIER;  // Used for ATR arbitration cap
        m_config.useATRBased = E1_USE_ATR_SL_ARBITRATION;   // From input param
        m_config.minSLSpreadMultiplier = MIN_SL_SPREAD_MULT;

        // Take Profit
        m_config.rewardRatio = E1_RR;
        m_config.rewardRatioSideway = E1_RR_SIDEWAY;
        m_config.partialTPTrigger = E1_PARTIAL_TP_TRIGGER;
        m_config.partialTPRatio = E1_PARTIAL_TP_RATIO;
        
        // TP Extension (trigger/pips now use dynamic global values)
        m_config.maxTPExtensions = E1_MAX_TP_EXTENSIONS;
        
        // Trailing SL
        m_config.trailingFactor = E1_TRAILING_SL_FACTOR;
        m_config.breakevenBuffer = E1_SL_TO_BREAKEVEN_BUFFER;
        m_config.useADXFilter = false;
        
        // Early Exit
        m_config.earlyCutSLRatio = E1_EARLY_CUT_SL_RATIO;
        m_config.adxPeriodForExit = 14;  // Start with 14, adapt later
        m_config.minADXToHold = 18.0;
        
        // Phase 2: Laddered Extensions (E1 - Aggressive)
        m_config.enableLadderedExtensions = E1_ENABLE_LADDERED_EXTENSIONS;
        m_config.ladderStage1Multiplier = E1_LADDER_STAGE1_MULTIPLIER;
        m_config.ladderStage2Multiplier = E1_LADDER_STAGE2_MULTIPLIER;
        m_config.ladderStage3Multiplier = E1_LADDER_STAGE3_MULTIPLIER;
        m_config.ladderStage1TrailRatio = E1_LADDER_STAGE1_TRAIL_RATIO;
        m_config.ladderStage2TrailRatio = E1_LADDER_STAGE2_TRAIL_RATIO;
        m_config.ladderStage3TrailRatio = E1_LADDER_STAGE3_TRAIL_RATIO;
        
        ValidateAndClampParams();
    }
    
public:
    // E1-specific detection logic
    virtual DetectionResult Detect() override {
        DetectionResult result;
        result.detected = false;
        result.rawSLDistancePips = 0.0;
        result.bufferedSLDistancePips = 0.0;
        
        // Session loss limit check (hard stop after N real losses)
        if (sessionLossCount >= MAX_SESSION_LOSSES) {
            if(showDebug) Print("[E1] Session loss limit reached: ", sessionLossCount, "/", MAX_SESSION_LOSSES);
            return result;
        }
        
        // Session total trade limit check (legacy, emergency brake)
        if (tradeSLTPCountInSession > MAX_SLTP_COUNT_PER_SESSION) {
            if(showDebug) Print("[E1] Session trade limit reached: ", tradeSLTPCountInSession);
            return result;
        }
        
        // Get current price
        double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
        
        // Check open positions
        int checkOpenLE1, checkOpenSE1, checkOpenLE2, checkOpenSE2, checkOpenLE3, checkOpenSE3;
        CheckOpenPositions(checkOpenLE1, checkOpenSE1, checkOpenLE2, checkOpenSE2, checkOpenLE3, checkOpenSE3);
        
        // Expire stale EMA crossing triggers
        if (lastEMACrossingUp != -1 && (currentBar - lastEMACrossingUp) > E1_MAX_CROSS_AGE) {
            if(showDebug) Print("[E1] Expired stale LONG crossing (age ", currentBar - lastEMACrossingUp, " > ", E1_MAX_CROSS_AGE, ")");
            lastEMACrossingUp = -1;
        }
        if (lastEMACrossingDown != -1 && (currentBar - lastEMACrossingDown) > E1_MAX_CROSS_AGE) {
            if(showDebug) Print("[E1] Expired stale SHORT crossing (age ", currentBar - lastEMACrossingDown, " > ", E1_MAX_CROSS_AGE, ")");
            lastEMACrossingDown = -1;
        }
        
        // === LONG E1 Detection ===
        if (lastEMACrossingUp != -1 && checkOpenLE1 == -1) {
            bool isLowConfidence = false;
            string lowConfidenceReason = "";
            int trendQuality = 0;
            
            if (CheckE1EntryConditions_Internal(true, currentPrice, "L-E1", isLowConfidence, lowConfidenceReason, trendQuality)) {
                if (!isLowConfidence || SEND_LOW_CONFIDENCE_SIGNALS) {
                    result.detected = true;
                    result.isLong = true;
                    result.entryPrice = currentPrice;
                    
                    // Calculate range for SL
                    double recentHigh = iHigh(_Symbol, TF_ARRAY[TF0], iHighest(_Symbol, TF_ARRAY[TF0], MODE_HIGH, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    double recentLow = iLow(_Symbol, TF_ARRAY[TF0], iLowest(_Symbol, TF_ARRAY[TF0], MODE_LOW, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    
                    // E1-specific SL: EMA100 - 50% of distance to EMA200 (breathing room beyond EMA100)
                    double ema100 = GetEMA(TF0, EMA3, ENTRY_SHIFT);
                    double ema200 = GetEMA(TF0, EMA4, ENTRY_SHIFT);
                    double emaDistance = MathAbs(ema100 - ema200);
                    double e1SLLevel = ema100 - (emaDistance * 0.75);  // 75% below EMA100 toward EMA200
                    
                    double rawSLDistancePips = 0.0;
                    double bufferedSLDistancePips = 0.0;
                    result.stopLoss = CalculateStopLossWithCustomEMA(true, currentPrice, recentHigh, recentLow,
                                                                     e1SLLevel, "E1", 1,
                                                                     rawSLDistancePips, bufferedSLDistancePips);
                    result.rawSLDistancePips = rawSLDistancePips;
                    result.bufferedSLDistancePips = bufferedSLDistancePips;
                    
                    // Calculate TP based on RR ratio
                    double slDistance = MathAbs(currentPrice - result.stopLoss);
                    result.takeProfit = currentPrice + (slDistance * CFG.rrLongE1);
                    
                    result.entryType = ENTRY_L_E1;
                    result.isLowConfidence = isLowConfidence;
                    result.lowConfidenceReason = lowConfidenceReason;
                    result.trendQualityScore = trendQuality;
                    
                    // Reset trigger
                    lastEMACrossingUp = -1;
                    
                    //if(showDebug) Print("[E1] LONG detected at ", currentPrice);
                }
            }
        }
        
        // === SHORT E1 Detection (only if LONG didn't trigger) ===
        if (!result.detected && lastEMACrossingDown != -1 && checkOpenSE1 == -1) {
            bool isLowConfidence = false;
            string lowConfidenceReason = "";
            int trendQuality = 0;
            
            if (CheckE1EntryConditions_Internal(false, currentPrice, "S-E1", isLowConfidence, lowConfidenceReason, trendQuality)) {
                if (!isLowConfidence || SEND_LOW_CONFIDENCE_SIGNALS) {
                    result.detected = true;
                    result.isLong = false;
                    result.entryPrice = currentPrice;
                    
                    double recentHigh = iHigh(_Symbol, TF_ARRAY[TF0], iHighest(_Symbol, TF_ARRAY[TF0], MODE_HIGH, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    double recentLow = iLow(_Symbol, TF_ARRAY[TF0], iLowest(_Symbol, TF_ARRAY[TF0], MODE_LOW, RANGE_HI_LOW_LOOK_BACK_BARS, ENTRY_SHIFT));
                    
                    // E1-specific SL: EMA100 + 50% of distance to EMA200 (breathing room beyond EMA100)
                    double ema100 = GetEMA(TF0, EMA3, ENTRY_SHIFT);
                    double ema200 = GetEMA(TF0, EMA4, ENTRY_SHIFT);
                    double emaDistance = MathAbs(ema100 - ema200);
                    double e1SLLevel = ema100 + (emaDistance * 0.75);  // 75% above EMA100 toward EMA200
                    
                    double rawSLDistancePips = 0.0;
                    double bufferedSLDistancePips = 0.0;
                    result.stopLoss = CalculateStopLossWithCustomEMA(false, currentPrice, recentHigh, recentLow,
                                                                     e1SLLevel, "E1", 1,
                                                                     rawSLDistancePips, bufferedSLDistancePips);
                    result.rawSLDistancePips = rawSLDistancePips;
                    result.bufferedSLDistancePips = bufferedSLDistancePips;
                    
                    // Calculate TP based on RR ratio
                    double slDistance = MathAbs(currentPrice - result.stopLoss);
                    result.takeProfit = currentPrice - (slDistance * CFG.rrShortE1);
                    
                    result.entryType = ENTRY_S_E1;
                    result.isLowConfidence = isLowConfidence;
                    result.lowConfidenceReason = lowConfidenceReason;
                    result.trendQualityScore = trendQuality;
                    
                    lastEMACrossingDown = -1;
                    
                    //if(showDebug) Print("[E1] SHORT detected at ", currentPrice);
                }
            }
        }
        
        return result;
    }
    
    virtual double GetTargetWinrate() override { 
        return 0.66;  // 66% target for E1
    }
    
private:
    //--------------------------------------------------------------------
    // E1-SPECIFIC CONDITION CHECKING
    //--------------------------------------------------------------------
    bool CheckE1EntryConditions_Internal(bool isLong, double currentPrice, string entryType,
                                        bool &isLowConfidence, string &lowConfidenceReason,
                                        int &trendQualityOut) {
        isLowConfidence = false;
        lowConfidenceReason = "";

        // E1 parity gate trace: per-bar BLOCK/PASS at the armed-trigger bar (ENTRY_SHIFT-labeled).
        // Parse with regex ^KKE1GATE,  -> ts,dir,result,gate,detail
        string _gtTs  = TimeToString(iTime(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
        string _gtDir = isLong ? "L" : "S";

        // Trend Strength Filter - reuses E1_MIN_MOMENTUM_ADX (avoids weak/choppy trends)
        if (cache.adx[0] < E1_MIN_MOMENTUM_ADX) {
            if (showDebug) Print("[E1] Blocked: M1 ADX ", DoubleToString(cache.adx[0], 1),
                                 " < ", DoubleToString(E1_MIN_MOMENTUM_ADX, 1), " (weak trend)");
            if (E1_GATE_TRACE) Print("KKE1GATE,", _gtTs, ",", _gtDir, ",BLOCK,trend_strength,adx=",
                                     DoubleToString(cache.adx[0], 2), ",min=", DoubleToString(E1_MIN_MOMENTUM_ADX, 2));
            TrackEntryAttempt(entryType, false, "trend_strength");
            return false;
        }
        
        // HTF Trend Direction Filter - block entries against higher timeframe trend
        // Uses cached ADX/DI values (index 2 = M5, index 3 = M15)
        if (E1_HTF_TREND_FILTER != HTF_DISABLED) {
            bool m5Bullish = false, m5Bearish = false, m5Valid = false;
            bool m15Bullish = false, m15Bearish = false, m15Valid = false;
            
            if (E1_HTF_TREND_FILTER == HTF_M5_ONLY || E1_HTF_TREND_FILTER == HTF_M5_AND_M15 || E1_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                double m5ADX = cache.adx[2];
                double m5DISpread = MathAbs(cache.diPlus[2] - cache.diMinus[2]);
                if (m5ADX >= E1_HTF_MIN_ADX && m5DISpread >= E1_HTF_MIN_DI_SPREAD) {
                    m5Valid = true;
                    m5Bullish = (cache.diPlus[2] > cache.diMinus[2]);
                    m5Bearish = !m5Bullish;
                }
            }
            
            if (E1_HTF_TREND_FILTER == HTF_M15_ONLY || E1_HTF_TREND_FILTER == HTF_M5_AND_M15 || E1_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                double m15ADX = cache.adx[3];
                double m15DISpread = MathAbs(cache.diPlus[3] - cache.diMinus[3]);
                if (m15ADX >= E1_HTF_MIN_ADX && m15DISpread >= E1_HTF_MIN_DI_SPREAD) {
                    m15Valid = true;
                    m15Bullish = (cache.diPlus[3] > cache.diMinus[3]);
                    m15Bearish = !m15Bullish;
                }
            }
            
            bool blockLong = false, blockShort = false;
            if (E1_HTF_TREND_FILTER == HTF_M5_ONLY && m5Valid) {
                blockLong = m5Bearish;
                blockShort = m5Bullish;
            } else if (E1_HTF_TREND_FILTER == HTF_M15_ONLY && m15Valid) {
                blockLong = m15Bearish;
                blockShort = m15Bullish;
            } else if (E1_HTF_TREND_FILTER == HTF_M5_AND_M15 && m5Valid && m15Valid) {
                blockLong = (m5Bearish && m15Bearish);
                blockShort = (m5Bullish && m15Bullish);
            } else if (E1_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                blockLong = (m5Valid && m5Bearish) || (m15Valid && m15Bearish);
                blockShort = (m5Valid && m5Bullish) || (m15Valid && m15Bullish);
            }
            
            if (isLong && blockLong) {
                if (showDebug) Print("[E1] L-E1 blocked: HTF bearish");
                if (E1_GATE_TRACE) Print("KKE1GATE,", _gtTs, ",", _gtDir, ",BLOCK,htf_trend,");
                TrackEntryAttempt(entryType, false, "htf_trend");
                return false;
            }
            if (!isLong && blockShort) {
                if (showDebug) Print("[E1] S-E1 blocked: HTF bullish");
                if (E1_GATE_TRACE) Print("KKE1GATE,", _gtTs, ",", _gtDir, ",BLOCK,htf_trend,");
                TrackEntryAttempt(entryType, false, "htf_trend");
                return false;
            }
        }

        // Multi-timeframe EMA check
        if (!isAllTimeframeEMAsReadyForEntry("E1", isLong, ENTRY_SHIFT)) {
            if (E1_GATE_TRACE) Print("KKE1GATE,", _gtTs, ",", _gtDir, ",BLOCK,mtf,");
            TrackEntryAttempt(entryType, false, "mtf");
            return false;
        }

        // Price position check
        double ema25 = GetEMA(TF0, EMA1, ENTRY_SHIFT);
        if ((isLong && currentPrice <= ema25) || (!isLong && currentPrice >= ema25)) {
            if (E1_GATE_TRACE) Print("KKE1GATE,", _gtTs, ",", _gtDir, ",BLOCK,price_pos,px=",
                                     DoubleToString(currentPrice, _Digits), ",ema25=", DoubleToString(ema25, _Digits));
            TrackEntryAttempt(entryType, false, "mtf");
            return false;
        }

        // Trend quality (includes DI spread check - no separate momentum check needed)
        TREND_STATE requiredTrend = isLong ? TREND_BULL : TREND_BEAR;
        trendQualityOut = GetTrendQualityScore(requiredTrend, 1);  // Pass 1 for E1
        if (trendQualityOut < MIN_TREND_QUALITY_E1) {
            if (E1_GATE_TRACE) Print("KKE1GATE,", _gtTs, ",", _gtDir, ",BLOCK,trend_quality,tq=",
                                     trendQualityOut, ",min=", MIN_TREND_QUALITY_E1);
            TrackEntryAttempt(entryType, false, "trend_quality");
            return false;  // Hard block: preserves trigger for re-check next bar
        }
        // Momentum check
        if (!HasSufficientMomentum(requiredTrend)) {
            if (E1_GATE_TRACE) Print("KKE1GATE,", _gtTs, ",", _gtDir, ",BLOCK,momentum,");
            TrackEntryAttempt(entryType, false, "momentum");
            return false;  // Hard block: preserves trigger for re-check next bar
        }

        // RSI divergence veto: block if M3 RSI diverges against trade direction
        if (HasRSIDivergenceAgainstTrade(isLong, entryType)) {
            if (E1_GATE_TRACE) Print("KKE1GATE,", _gtTs, ",", _gtDir, ",BLOCK,rsi_div,");
            TrackEntryAttempt(entryType, false, "rsi_div");
            return false;
        }

        if (E1_GATE_TRACE) Print("KKE1GATE,", _gtTs, ",", _gtDir, ",PASS,all,tq=", trendQualityOut);
        return true;
    }
    
public:
    // Lightweight direction check for E4 conflict detection (no full detection)
    // Returns true if potential E1 would be LONG, false if SHORT
    // Used to check if same-direction E4 is active before running full Detect()
    bool PeekDirection() {
        // E1 uses EMA crossing triggers - check which one is active
        // If both are active or neither, default to checking price vs EMA
        if (lastEMACrossingUp != -1 && lastEMACrossingDown == -1) {
            return true;  // Long trigger active
        }
        if (lastEMACrossingDown != -1 && lastEMACrossingUp == -1) {
            return false;  // Short trigger active
        }
        // Both or neither active - use price position vs EMA75 as tiebreaker
        double ema75 = GetEMA(TF0, EMA2, ENTRY_SHIFT);
        double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
        return (currentPrice > ema75);  // Above EMA = potential long
    }

    // Entry-specific config overrides
    virtual double GetRRBoostMultiplier() const { return 1.08; }
    virtual bool GetUseConvictionScoring() const { return USE_CONVICTION_SCORING_E1; }
    virtual bool GetUseHTFVeto() const { return USE_HTF_VETO_E1; }
    virtual int GetConvictionThreshold() const { return CONVICTION_THRESHOLD_E1; }
    virtual bool GetAcceptHighRisk() const { return ACCEPT_HIGH_RISK_E1_ENTRIES; }
    virtual int GetHighRiskMomentumCheck() const { return (int)HIGH_RISK_E1_MOMENTUM_CHECK; }
    virtual double GetMaxLossRatio() const { return MAX_LOSS_RATIO_E1; }
    virtual bool GetVolLotAdjEnabled() const { return VOL_LOT_ADJ_E1; }
    virtual bool GetRecoveryLadderEnabled() const { return E1_USE_RECOVERY_LADDER; }
    virtual int GetRecoveryBoostThreshold() const { return MIN_TREND_QUALITY_E1 + 1; }
    virtual bool GetEnableScoreDropExit() const { return ENABLE_SCORE_DROP_EXIT_E1; }
    virtual int GetScoreDropThreshold() const { return SCORE_DROP_THRESHOLD_E1; }
    virtual bool GetEnableDIFlipExit() const { return ENABLE_DI_FLIP_FAST_EXIT_E1; }
    virtual bool GetExitInIchiCloud() const { return EXIT_IN_ICHI_CLOUD_E1; }
    virtual bool GetEnablePanicADXExit() const { return ENABLE_FAST_ADX_PANIC_EXIT_E1; }
};

#endif // ENTRY1_MQH
