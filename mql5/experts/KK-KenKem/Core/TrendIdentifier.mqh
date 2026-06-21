#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef TREND_IDENTIFIER_MQH
#define TREND_IDENTIFIER_MQH

// NOTE: This file is included AFTER all variable declarations in the main script,
// so all global variables and functions are visible here.

// Per-entry log throttle for [TREND QUALITY GATE] BLOCKED — without this, the gate
// would print every tick under calc_on_every_tick. Indexed by entryNum (0..5).
// Set to true on first block; cleared when the gate passes again for that entry.
bool g_tqGateBlockLogged[6] = {false, false, false, false, false, false};

//+------------------------------------------------------------------+
//| Trend Identifier Functions                                       |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Unified momentum checker with configurable thresholds            |
//| checkAcceleration: true = check rising/widening (E1 style)       |
//|                    false = check absolute values only (E2 style) |
//+------------------------------------------------------------------+
bool HasMomentumForTrend(TREND_STATE trendState, ENUM_TIMEFRAMES timeFrame,
                         double minADX, double minDISpread, 
                         bool checkAcceleration = false,
                         int accelerationLookback = 3) {
    if (!cache.valid) {
        if(showDebug) Print("ERROR: Cache not updated before momentum check!");
        return false;
    }
    
    // Get array index for cache (M1/M3/M5/M15 at indices 0/1/2/3)
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0]) arrayIndex = 0;
    else if (timeFrame == TF_ARRAY[TF1]) arrayIndex = 1;
    else if (timeFrame == TF_ARRAY[TF2]) arrayIndex = 2;
    else {
        if(showDebug) Print("ERROR: Unsupported timeframe in momentum check");
        return false;
    }
    
    // Check 1: ADX threshold
    double adxCurrent = cache.adx[arrayIndex];
    if (adxCurrent < minADX) return false;
    
    // Check 2: ADX acceleration (optional for E1 early trend detection)
    if (checkAcceleration) {
        double adxBuffer[];
        ArraySetAsSeries(adxBuffer, true);
        if (CopyBuffer(adxHandles[arrayIndex], 0, 0, accelerationLookback, adxBuffer) < accelerationLookback) {
            return false;
        }
        if (!IsAccelerating(adxBuffer, accelerationLookback)) return false;
    }
    
    // Check 3: DI spread threshold
    double diPlus = cache.diPlus[arrayIndex];
    double diMinus = cache.diMinus[arrayIndex];
    double diSpread = (trendState == TREND_BULL) ? (diPlus - diMinus) : (diMinus - diPlus);
    if (diSpread < minDISpread) return false;
    
    // Check 4: DI spread widening (optional for E1 early trend detection)
    if (checkAcceleration) {
        double diPlusBuffer[], diMinusBuffer[];
        ArraySetAsSeries(diPlusBuffer, true);
        ArraySetAsSeries(diMinusBuffer, true);
        
        if (CopyBuffer(adxHandles[arrayIndex], 1, 0, accelerationLookback, diPlusBuffer) < accelerationLookback ||
            CopyBuffer(adxHandles[arrayIndex], 2, 0, accelerationLookback, diMinusBuffer) < accelerationLookback) {
            return false;
        }
        
        // Build DI spread buffer for acceleration check
        double diSpreadBuffer[];
        ArrayResize(diSpreadBuffer, accelerationLookback);
        ArraySetAsSeries(diSpreadBuffer, true);
        for (int i = 0; i < accelerationLookback; i++) {
            diSpreadBuffer[i] = (trendState == TREND_BULL) ? 
                               (diPlusBuffer[i] - diMinusBuffer[i]) : 
                               (diMinusBuffer[i] - diPlusBuffer[i]);
        }
        
        if (!IsAccelerating(diSpreadBuffer, accelerationLookback)) return false;
    }
    
    return true;
}



// Helper: Check Ichimoku Cloud alignment for trend quality bonus (0-2 points)
// Checks future cloud color on M1 and M3, and price position vs current cloud
// PERFORMANCE: Reads from cache instead of CopyBuffer (cached once per bar in UpdateIndicatorCache)
int CheckIchimokuCloudAlignment(bool isLong, int entryNum) {
    // Check if Ichimoku is enabled for this entry type
    bool useIchimoku = false;
    if (entryNum == 1) useIchimoku = USE_ICHIMOKU_E1;
    else if (entryNum == 2) useIchimoku = USE_ICHIMOKU_E2;
    // E3 uses exhaustion scoring, not Ichimoku
    
    if (!useIchimoku) return 0;
    
    int score = 0;
    
    // Check M1 Ichimoku alignment (using cached values)
    bool m1FutureCloudBullish = (cache.ichimokuSpanA_M1_Future > cache.ichimokuSpanB_M1_Future);
    bool m1CloudMatchesTrend = (isLong && m1FutureCloudBullish) || (!isLong && !m1FutureCloudBullish);
    
    // Check price position vs current M1 cloud (using cached values)
    double cloudTop = MathMax(cache.ichimokuSpanA_M1_Current, cache.ichimokuSpanB_M1_Current);
    double cloudBottom = MathMin(cache.ichimokuSpanA_M1_Current, cache.ichimokuSpanB_M1_Current);
    bool priceCorrectlyPositioned = (isLong && cache.currentPrice > cloudTop) || (!isLong && cache.currentPrice < cloudBottom);
    
    if (m1CloudMatchesTrend && priceCorrectlyPositioned) score += 1;
    
    // Check M3 Ichimoku alignment (using cached values)
    bool m3FutureCloudBullish = (cache.ichimokuSpanA_M3_Future > cache.ichimokuSpanB_M3_Future);
    bool m3CloudMatchesTrend = (isLong && m3FutureCloudBullish) || (!isLong && !m3FutureCloudBullish);
    
    if (m3CloudMatchesTrend) score += 1;
    
    return score; // 0-2 points
}

// Unified trend quality scoring system (0-13 points with Ichimoku + ATR bonus)
// Replaces separate volume/momentum checks with single comprehensive metric
// Components: ADX strength (0-2) + DI spread (0-2) + M1 Acceleration (0-2) + MTF alignment (0-2) + Price Action (0-1) + M3 Accel (0-1) + Ichimoku (0-2) + ATR Health (0-1)
int GetTrendQualityScore(TREND_STATE trendState, int entryNum = 0) {
    int score = 0;
    string components = "";  // For detailed logging
    
    // COMPONENT 1: ADX Strength (0-2 points)
    // Measures trend strength on M1 timeframe
    double adx = cache.adx[0];  // M1 ADX from cache
    int adxPoints = 0;
    if (adx >= ADX_HIGH_THRESHOLD)  adxPoints = 2;   // Strong trend (25+)
    else if (adx >= MIN_MOMENTUM_ADX_REQUIRED)           adxPoints = 1;   // Moderate trend
    // else 0
    
    score += adxPoints;
    components += StringFormat("ADX:%d(%.1f) ", adxPoints, adx);
    
    // COMPONENT 2: DI Spread (0-2 points)
    // Measures directional bias strength
    double spread = (trendState == TREND_BULL) ? 
                    (cache.diPlus[0] - cache.diMinus[0]) : 
                    (cache.diMinus[0] - cache.diPlus[0]);
    int spreadPoints = 0;
    if (spread >= 3.0)       spreadPoints = 2;   // Strong directional bias
    else if (spread >= 1.0)  spreadPoints = 1;   // Moderate bias
    // else 0
    
    score += spreadPoints;
    components += StringFormat("DI:%d(%.1f) ", spreadPoints, spread);
    
    // COMPONENT 3: M1 Acceleration Strength (0-2 points)
    // Graduated: 3-bar vs 5-bar sustained acceleration
    int accelPoints = 0;
    if (USE_ACCELERATION_BONUS) {
        bool accel3 = HasTrendAcceleration(TF_ARRAY[TF0], trendState, 3);   // Short-term
        bool accel5 = HasTrendAcceleration(TF_ARRAY[TF0], trendState, 5);   // Sustained
        
        if (accel5)       accelPoints = 2;   // Strong sustained acceleration
        else if (accel3)  accelPoints = 1;   // Short-term acceleration
        // else 0
    }
    
    score += accelPoints;
    components += StringFormat("Accel:%d ", accelPoints);
    
    // COMPONENT 4: Multi-Timeframe Alignment (0-2 points)
    // Checks if M1, M3, and M5 DI spreads agree on direction
    bool m1Aligned = (trendState == TREND_BULL) ? 
                     (cache.diPlus[0] > cache.diMinus[0]) : 
                     (cache.diMinus[0] > cache.diPlus[0]);
    bool m3Aligned = (trendState == TREND_BULL) ? 
                     (cache.diPlus[1] > cache.diMinus[1]) : 
                     (cache.diMinus[1] > cache.diPlus[1]);
    bool m5Aligned = (trendState == TREND_BULL) ? 
                     (cache.diPlus[2] > cache.diMinus[2]) : 
                     (cache.diMinus[2] > cache.diPlus[2]);
    
    int alignedCount = (m1Aligned ? 1 : 0) + (m3Aligned ? 1 : 0) + (m5Aligned ? 1 : 0);
    int mtfPoints = 0;
    if (alignedCount == 3)       mtfPoints = 2;   // Full 3-TF alignment
    else if (alignedCount >= 2)  mtfPoints = 1;   // 2/3 alignment
    // else 0
    
    score += mtfPoints;
    components += StringFormat("MTF:%d(%d/3) ", mtfPoints, alignedCount);
    
    // GATE CHECK: Core components must each score >= 1 to proceed
    // Prevents weak trends from inflating score via secondary components.
    // E5 (entryNum=5) skips this hard gate to match Pine v1-stable semantics —
    // Pine sums components and compares to minTrendQualityScore directly with no
    // per-component minimum. E5 has its own ADX gate at Entry5.mqh:122.
    int tqLogIdx = (entryNum >= 0 && entryNum <= 5) ? entryNum : 0;
    if (entryNum != 5 && ENABLE_TREND_QUALITY_GATES && (adxPoints == 0 || spreadPoints == 0 || mtfPoints == 0)) {
        if (showDebug && !g_tqGateBlockLogged[tqLogIdx]) {
            string failedGate = (adxPoints == 0) ? "ADX" : (spreadPoints == 0) ? "DI" : "MTF";
            Print("[TREND QUALITY GATE] BLOCKED E", entryNum, " - ", failedGate,
                  " scored 0 | ", components);
            g_tqGateBlockLogged[tqLogIdx] = true;
        }
        return 0;
    }
    g_tqGateBlockLogged[tqLogIdx] = false;  // gate passed — re-arm log on next block
    
    // COMPONENT 5: Price Action Strength (0-1 point)
    // Validates with trending candle pattern
    bool strongPA = HasStrongTrendingPriceActions(trendState, TF_ARRAY[TF0], 5, ENTRY_SHIFT);
    int paPoints = strongPA ? 1 : 0;
    
    score += paPoints;
    components += StringFormat("PA:%d ", paPoints);
    
    // COMPONENT 6: M3 Acceleration Confirmation (0-1 point)
    // Checks M3 also accelerating (confirms M1 isn't noise)
    bool m3Accel = HasTrendAcceleration(TF_ARRAY[TF1], trendState, 3);
    int m3AccelPoints = m3Accel ? 1 : 0;
    
    score += m3AccelPoints;
    components += StringFormat("M3Acc:%d ", m3AccelPoints);
    
    // COMPONENT 7: Ichimoku Cloud Alignment Bonus (0-2 points)
    // Checks future cloud color on M1 and M3, and price position vs current cloud
    int ichimokuPoints = CheckIchimokuCloudAlignment(trendState == TREND_BULL, entryNum);
    if (ichimokuPoints > 0) {
        score += ichimokuPoints;
        components += StringFormat("Ichimoku:%d ", ichimokuPoints);
    }
    
    // P2: COMPONENT 8: ATR Health (0-1 point)
    // A trend with dead volatility (low ATR) is unreliable even if ADX is high
    // Award point when ATR is above ATR_PERCENTILE_LOW (reuse existing param, no separate threshold needed)
    int atrPoints = (cachedATRPercentile >= ATR_PERCENTILE_LOW) ? 1 : 0;
    score += atrPoints;
    components += StringFormat("ATR:%d(%.0f%%) ", atrPoints, cachedATRPercentile);
    
    // Optional debug logging
    if (showDebug && score > 0) {
        // Determine max score based on whether Ichimoku is enabled for this entry
        // E3 uses exhaustion scoring, not trend quality
        bool useIchimoku = (entryNum == 1 && USE_ICHIMOKU_E1) || 
                          (entryNum == 2 && USE_ICHIMOKU_E2) ||
                          (entryNum == 4 && USE_ICHIMOKU_E4);
        int maxScore = useIchimoku ? 13 : 11;  // +1 for ATR component
        //Print("[TREND QUALITY] ", (trendState == TREND_BULL ? "BULL" : "BEAR"), " E", entryNum, " Score=", score, "/", maxScore, " | ", components);
    }
    
    return score;  // Max: 13 points (with Ichimoku + ATR) or 11 points (without Ichimoku)
}


// Active trade momentum score - used for in-trade health monitoring
// Unlike GetTrendQualityScore (entry-timing), this focuses on whether directional bias is still alive
// Base components (0-5): DI direction M1 (0-2) + ADX alive (0-1) + DI direction M3 (0-1) + Price vs EMA75 (0-1)
// E4 bonus (0-1): Ichimoku cloud position — E4 relies on cloud as trigger, so cloud health matters in-trade
int GetActiveTradeMomentumScore(TREND_STATE trendState, int entryNum = 0) {
    int score = 0;
    bool isLong = (trendState == TREND_BULL);
    
    // COMPONENT 1: M1 DI direction still correct (0-2 points)
    double m1Spread = isLong ? 
                      (cache.diPlus[0] - cache.diMinus[0]) : 
                      (cache.diMinus[0] - cache.diPlus[0]);
    if (m1Spread >= 5.0)       score += 2;   // Strong directional bias alive
    else if (m1Spread > 0.0)   score += 1;   // Bias still correct direction
    // else 0 = DI flipped against trade
    
    // COMPONENT 2: ADX not collapsed (0-1 point)
    // ADX below 15 = no trend at all, dead market
    double adx = cache.adx[0];
    if (adx >= 15.0) score += 1;
    
    // COMPONENT 3: M3 DI direction confirmation (0-1 point)
    double m3Spread = isLong ? 
                      (cache.diPlus[1] - cache.diMinus[1]) : 
                      (cache.diMinus[1] - cache.diPlus[1]);
    if (m3Spread > 0.0) score += 1;
    
    // COMPONENT 4: Price above/below EMA75 - structural check (0-1 point)
    double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
    double ema75 = GetEMA(TF0, EMA2, ENTRY_SHIFT);
    bool priceOK = isLong ? (currentPrice > ema75) : (currentPrice < ema75);
    if (priceOK) score += 1;
    
    // COMPONENT 5 (E4 only): Ichimoku cloud position (0-1 point)
    // E4 uses Ichimoku cloud as its primary trigger — if price drifts into/through the cloud,
    // the setup thesis is invalidated. Price must remain on the correct side of the cloud.
    if (entryNum == 4) {
        double cloudTop = MathMax(cache.ichimokuSpanA_M1_Current, cache.ichimokuSpanB_M1_Current);
        double cloudBottom = MathMin(cache.ichimokuSpanA_M1_Current, cache.ichimokuSpanB_M1_Current);
        bool priceOutsideCloud = isLong ? (currentPrice > cloudTop) : (currentPrice < cloudBottom);
        if (priceOutsideCloud) score += 1;
    }
    
    return score;  // Max: 5 (E1/E2/E3) or 6 (E4)
}

// 4. Strong trending price actions validation
bool HasStrongTrendingPriceActions(TREND_STATE trendState, ENUM_TIMEFRAMES timeFrame, int lookbackBars, int entryShift) {
    if (lookbackBars < 2) lookbackBars = 2; // Minimum 2 bars needed
    
    double closes[], opens[], highs[], lows[];
    ArraySetAsSeries(closes, true);
    ArraySetAsSeries(opens, true);
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    
    if (CopyClose(_Symbol, timeFrame, entryShift, lookbackBars, closes) <= 0 ||
        CopyOpen(_Symbol, timeFrame, entryShift, lookbackBars, opens) <= 0 ||
        CopyHigh(_Symbol, timeFrame, entryShift, lookbackBars, highs) <= 0 ||
        CopyLow(_Symbol, timeFrame, entryShift, lookbackBars, lows) <= 0) {
        PrintDebug("Failed to copy price data for strong trending price actions");
        return false;
    }
    
    if (trendState == TREND_BULL) {
        // Bullish trend validation
        int bullishBars = 0;
        int engulfingBars = 0;
        
        for (int i = 0; i < lookbackBars; i++) {
            // Count bullish bars (close > open)
            if (closes[i] > opens[i]) bullishBars++;
            
            // Check for bullish engulfing (current bar engulfs previous)
            if (i < lookbackBars - 1) {
                bool currentBullish = (closes[i] > opens[i]);
                bool previousBearish = (closes[i+1] < opens[i+1]);
                bool engulfs = (opens[i] < closes[i+1] && closes[i] > opens[i+1]);
                
                if (currentBullish && previousBearish && engulfs) {
                    engulfingBars++;
                }
            }
        }
        
        // Strong bullish: majority bullish bars OR at least one engulfing pattern
        return (bullishBars >= (lookbackBars * 0.7)) || (engulfingBars > 0);
        
    } else if (trendState == TREND_BEAR) {
        // Bearish trend validation
        int bearishBars = 0;
        int engulfingBars = 0;
        
        for (int i = 0; i < lookbackBars; i++) {
            // Count bearish bars (close < open)
            if (closes[i] < opens[i]) bearishBars++;
            
            // Check for bearish engulfing
            if (i < lookbackBars - 1) {
                bool currentBearish = (closes[i] < opens[i]);
                bool previousBullish = (closes[i+1] > opens[i+1]);
                bool engulfs = (opens[i] > closes[i+1] && closes[i] < opens[i+1]);
                
                if (currentBearish && previousBullish && engulfs) {
                    engulfingBars++;
                }
            }
        }
        
        // Strong bearish: majority bearish bars OR at least one engulfing pattern
        return (bearishBars >= (lookbackBars * 0.7)) || (engulfingBars > 0);
    }
    
    return false;
}


// 6. Strong momentum combining RSI, ADX and price actions
bool HasStrongMomentum(TREND_STATE trendState, ENUM_TIMEFRAMES timeFrame, int lastBars, int entryShift) {
    // RSI confluence check (using 7, 14, 21 periods with threshold 50)
    bool rsiConfluence = HasRSIConfluence(trendState, timeFrame, 7, 14, 21, 50.0, entryShift);
    
    // ADX confluence check (uses E2 baseline)
    bool adxConfluence = HasADXConfluence(trendState, timeFrame, lastBars, E2_MIN_MOMENTUM_ADX, entryShift);
    
    // Price action confirmation
    bool priceActions = HasStrongTrendingPriceActions(trendState, timeFrame, lastBars, entryShift);
    
    return rsiConfluence && adxConfluence && priceActions;
}

// Multi-Factor Sideways Scoring (0-100 scale) - Pine Script parity with multi-bar robustness
// Components: EMA Convergence(0-25) + ADX Weakness(0-25) + DI Indecision(0-20) + RSI Neutral(0-15) + ATR Compression(0-15)
int GetSidewaysScore(int barShift = 1, int avgBars = 5) {
    int score = 0;
    
    // Get EMA values at specified bar (single bar is fine for EMA spread)
    double ema25 = GetEMA(TF0, EMA1, barShift);
    double ema75 = GetEMA(TF0, EMA2, barShift);
    double ema100 = GetEMA(TF0, EMA3, barShift);
    double ema200 = GetEMA(TF0, EMA4, barShift);
    
    // Use AVERAGED values over avgBars for noise filtering (MQL robustness)
    double atr = cache.atrM1;
    double adx_m1 = GetADXAverage(TF_ARRAY[TF0], avgBars);   // Averaged TF0 ADX
    double adx_m3 = GetADXAverage(TF_ARRAY[TF1], avgBars);   // Averaged TF1 ADX
    double diplus = cache.diPlus[0];   // M1 DI+ (current for direction)
    double diminus = cache.diMinus[0]; // M1 DI- (current for direction)
    
    // Get RSI average over avgBars
    double rsi = GetRSIAverage(TF_ARRAY[TF0], RSI_LEN, avgBars);
    
    // COMPONENT 1: EMA Convergence (0-25 points)
    double maxEMA = MathMax(MathMax(ema25, ema75), MathMax(ema100, ema200));
    double minEMA = MathMin(MathMin(ema25, ema75), MathMin(ema100, ema200));
    double emaSpread = (atr > 0) ? (maxEMA - minEMA) / atr : 999.0;
    
    if (emaSpread < EMA_SPREAD_TIGHT_ATR)
        score += 25;      // Very tight = maximum convergence
    else if (emaSpread < EMA_SPREAD_MODERATE_ATR)
        score += 15;      // Moderate convergence
    else if (emaSpread < EMA_SPREAD_WIDE_ATR)
        score += 8;       // Mild convergence
    
    // COMPONENT 2: ADX Weakness (0-25 points)
    int adxScore = 0;
    // M1 ADX weakness
    if (adx_m1 < 15)
        adxScore += 15;   // Very weak
    else if (adx_m1 < 20)
        adxScore += 10;   // Weak
    else if (adx_m1 < 25)
        adxScore += 5;    // Borderline
    
    // M3 ADX weakness confirmation
    if (adx_m3 < 18)
        adxScore += 10;
    else if (adx_m3 < 22)
        adxScore += 5;
    
    score += MathMin(25, adxScore);  // Cap at 25
    
    // COMPONENT 3: DI Indecision (0-20 points)
    double diSpread = MathAbs(diplus - diminus);
    
    if (diSpread < 2.0)
        score += 12;      // Very tight = high indecision
    else if (diSpread < 4.0)
        score += 8;       // Tight
    else if (diSpread < 6.0)
        score += 4;       // Borderline
    
    // COMPONENT 4: RSI Neutral Zone (0-15 points)
    if (rsi >= 45 && rsi <= 55)
        score += 15;      // Perfect neutral
    else if (rsi >= 40 && rsi <= 60)
        score += 10;      // Soft neutral
    else if (rsi >= 35 && rsi <= 65)
        score += 5;       // Borderline
    
    // COMPONENT 5: ATR Compression (0-15 points)
    double atrPctl = cachedATRPercentile;  // Use cached percentile
    if (atrPctl < 15)
        score += 15;      // Very compressed
    else if (atrPctl < 25)
        score += 10;      // Compressed
    else if (atrPctl < 35)
        score += 5;       // Mild compression
    
    return score;  // Max: 25+25+20+15+15 = 100
}

// Cached sideways score (updated each tick like Pine Script)
int cachedSidewaysScore = 0;

// Update sideways score cache (call from OnTick or indicator update)
void UpdateSidewaysScoreCache() {
    cachedSidewaysScore = GetSidewaysScore(ENTRY_SHIFT);
}

// Get cached sideways score
int GetCachedSidewaysScore() {
    return cachedSidewaysScore;
}

// Function to detect if we're in an extreme sideway range - Pine Script parity
bool IsInExtremeSidewayRange(int lastBars = 5) {
    // Use scoring system for Pine Script parity
    return cachedSidewaysScore >= SIDEWAYS_BLOCK_THRESHOLD;
}

// Standard sideway (warning level, reduce RR) - Pine Script parity
bool IsInSidewayRange(int lastBars = 5) {
    // Warning level: score >= warning threshold but < block threshold
    return cachedSidewaysScore >= SIDEWAYS_WARNING_THRESHOLD && cachedSidewaysScore < SIDEWAYS_BLOCK_THRESHOLD;
}


// ============================================================================
// E5 Multi-TF Sideway Scoring (Pine SuperBros v1 parity)
// Each TF computes its own 5-component score using TF-local indicators.
// Multi-TF sideway = 2/3 of M1/M3/M5 >= threshold on bar[1] or bar[2].
// ============================================================================

// Compute sideway score for a specific timeframe (M1, M3, M5)
// Mirrors Pine f_tfSidewayScore() -- both ADX slots use the same TF's ADX
int GetSidewaysScoreForTF(int tfIdx, int barShift = 1, int avgBars = 5) {
    int score = 0;

    // EMAs at barShift for this TF
    double ema25  = GetEMA(tfIdx, EMA1, barShift);
    double ema75  = GetEMA(tfIdx, EMA2, barShift);
    double ema100 = GetEMA(tfIdx, EMA3, barShift);
    double ema200 = GetEMA(tfIdx, EMA4, barShift);

    // ATR for this TF (from cache or handle)
    double atr = 0.0;
    if (tfIdx == TF0) {
        atr = cache.atrM1;
    } else if (tfIdx == TF1) {
        atr = cache.atrM3;
    } else if (tfIdx == TF2) {
        atr = cache.atrM5;
    }
    if (atr <= 0) return 0;  // No ATR data = can't score

    // ADX average for this TF (Pine uses same ADX for both M1 and M3 slots in per-TF scoring)
    double adxAvg = GetADXAverage(TF_ARRAY[tfIdx], avgBars);

    // DI values for this TF (read from ADX handle buffers 1 and 2)
    double dipBuf[], dimBuf[];
    ArraySetAsSeries(dipBuf, true);
    ArraySetAsSeries(dimBuf, true);
    double diplus = 0.0, diminus = 0.0;
    if (tfIdx >= 0 && tfIdx < 4) {
        if (CopyBuffer(adxHandles[tfIdx], 1, barShift, avgBars, dipBuf) > 0 &&
            CopyBuffer(adxHandles[tfIdx], 2, barShift, avgBars, dimBuf) > 0) {
            double sumP = 0, sumM = 0;
            int cnt = ArraySize(dipBuf);
            for (int i = 0; i < cnt; i++) { sumP += dipBuf[i]; sumM += dimBuf[i]; }
            diplus = cnt > 0 ? sumP / cnt : 0;
            diminus = cnt > 0 ? sumM / cnt : 0;
        }
    }

    // RSI average for this TF
    double rsi = GetRSIAverage(TF_ARRAY[tfIdx], RSI_LEN, avgBars);

    // ATR percentile for this TF (compute on the fly)
    double atrPctl = 50.0;  // default
    int atrHandle = INVALID_HANDLE;
    if (tfIdx == TF0) atrHandle = g_atrM1Handle;
    else if (tfIdx == TF1) atrHandle = g_atrM3Handle;
    else if (tfIdx == TF2) atrHandle = g_atrM5Handle;
    if (atrHandle != INVALID_HANDLE) {
        int lookback = 100;
        double atrBuf[];
        ArraySetAsSeries(atrBuf, true);
        if (CopyBuffer(atrHandle, 0, barShift, lookback, atrBuf) == lookback) {
            double currentATR = atrBuf[0];
            int below = 0;
            for (int i = 1; i < lookback; i++) {
                if (atrBuf[i] < currentATR) below++;
            }
            atrPctl = (double)below / (double)(lookback - 1) * 100.0;
        }
    }

    // COMPONENT 1: EMA Convergence (0-25 points)
    double maxEMA = MathMax(MathMax(ema25, ema75), MathMax(ema100, ema200));
    double minEMA = MathMin(MathMin(ema25, ema75), MathMin(ema100, ema200));
    double emaSpread = (maxEMA - minEMA) / atr;

    if (emaSpread < EMA_SPREAD_TIGHT_ATR)
        score += 25;
    else if (emaSpread < EMA_SPREAD_MODERATE_ATR)
        score += 15;
    else if (emaSpread < EMA_SPREAD_WIDE_ATR)
        score += 8;

    // COMPONENT 2: ADX Weakness (0-25 points) -- Pine uses same ADX for both slots
    int adxScore = 0;
    if (adxAvg < 15)      adxScore += 15;
    else if (adxAvg < 20)  adxScore += 10;
    else if (adxAvg < 25)  adxScore += 5;
    // Second slot: same TF ADX (Pine f_tfSidewayScore passes _adxA twice)
    if (adxAvg < 18)      adxScore += 10;
    else if (adxAvg < 22)  adxScore += 5;
    score += MathMin(25, adxScore);

    // COMPONENT 3: DI Indecision (0-20 points)
    double diSpread = MathAbs(diplus - diminus);
    if (diSpread < 2.0)       score += 12;
    else if (diSpread < 4.0)  score += 8;
    else if (diSpread < 6.0)  score += 4;

    // COMPONENT 4: RSI Neutral Zone (0-15 points)
    if (rsi >= 45 && rsi <= 55)       score += 15;
    else if (rsi >= 40 && rsi <= 60)  score += 10;
    else if (rsi >= 35 && rsi <= 65)  score += 5;

    // COMPONENT 5: ATR Compression (0-15 points)
    if (atrPctl < 15)       score += 15;
    else if (atrPctl < 25)  score += 10;
    else if (atrPctl < 35)  score += 5;

    return score;
}

// Multi-TF sideway check: 2/3 of M1/M3/M5 >= threshold (Pine SuperBros parity)
// Checks both bar[1] and bar[2] like Pine: multiTfSideway = swCountBar1 >= 2 or swCountBar2 >= 2
bool IsMultiTfSideway(int threshold = 0) {
    if (threshold <= 0) threshold = E5_SIDEWAYS_BLOCK_THRESHOLD;

    // Bar 1 (most recent completed bar)
    int scoreM1_1 = GetSidewaysScoreForTF(TF0, 1);
    int scoreM3_1 = GetSidewaysScoreForTF(TF1, 0);  // M3 shift 0 = latest closed M3 bar
    int scoreM5_1 = GetSidewaysScoreForTF(TF2, 0);  // M5 shift 0 = latest closed M5 bar

    int count1 = (scoreM1_1 >= threshold ? 1 : 0)
               + (scoreM3_1 >= threshold ? 1 : 0)
               + (scoreM5_1 >= threshold ? 1 : 0);

    if (count1 >= 2) return true;

    // Bar 2 (previous bar)
    int scoreM1_2 = GetSidewaysScoreForTF(TF0, 2);
    int scoreM3_2 = GetSidewaysScoreForTF(TF1, 1);  // Previous M3 bar
    int scoreM5_2 = GetSidewaysScoreForTF(TF2, 1);  // Previous M5 bar

    int count2 = (scoreM1_2 >= threshold ? 1 : 0)
               + (scoreM3_2 >= threshold ? 1 : 0)
               + (scoreM5_2 >= threshold ? 1 : 0);

    return (count2 >= 2);
}

// Helper function: Check for low volatility using price range
bool IsLowVolatility(ENUM_TIMEFRAMES timeFrame, int lastBars) {
    if (lastBars <= 0) return false;
    double highs[]; double lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    int copiedH = CopyHigh(_Symbol, timeFrame, 0, lastBars, highs);
    int copiedL = CopyLow(_Symbol, timeFrame, 0, lastBars, lows);
    if (copiedH <= 0 || copiedL <= 0) return false;
    double highestHigh = highs[0];
    double lowestLow = lows[0];
    int limit = MathMin(copiedH, copiedL);
    for (int i = 0; i < limit; i++) {
        double h = highs[i];
        double l = lows[i];
        if (h > highestHigh) highestHigh = h;
        if (l < lowestLow) lowestLow = l;
    }
    if (highestHigh <= 0 || lowestLow <= 0) return false;
    double currentPrice = iClose(_Symbol, timeFrame, 0);
    if (currentPrice <= 0) return false;
    double range = highestHigh - lowestLow;
    double rangePercent = (range / currentPrice) * 100.0;
    return rangePercent < 0.3;
}


//+------------------------------------------------------------------+
//| Momentum confirmation helpers                                    |
//+------------------------------------------------------------------+
bool HasBullishMomentum() {
    // Cache already updated in OnTick per new bar
    double close1 = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT + 1);
    double close2 = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT + 2);

    // Require 2-bar bullish momentum: current > previous AND net gain over 2 bars
    return (cache.currentPrice > close1) && ((cache.currentPrice - close2) > 0);
}

bool HasBearishMomentum() {
    // Cache already updated in OnTick per new bar
    double close1 = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT + 1);
    double close2 = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT + 2);
    
    // Require 2-bar bearish momentum: current < previous AND net loss over 2 bars
    return (cache.currentPrice < close1) && ((cache.currentPrice - close2) < 0);
}


// Enhanced momentum filter for entry validation (now uses cache)
bool HasSufficientMomentum(TREND_STATE trendState) {
    // Cache already updated in OnTick per new bar - no need to call again
    return (trendState == TREND_BULL) ? cache.hasSufficientBullMomentum : cache.hasSufficientBearMomentum;
}

// Trend weakening detection - returns cached value (for Early Exit, Partial TP, TP Extension)
// Uses M3 timeframe for stability (less noise than M1)
bool IsTrendWeakening(bool isLong) {
    return isLong ? cache.isTrendWeakeningBull : cache.isTrendWeakeningBear;
}

// Calculate trend weakening using cached M3 historical data
// Returns true if ADX is declining OR DI spread is narrowing (either = trend losing steam)
bool CalculateTrendWeakening(TREND_STATE trendState) {
    // Require valid M3 history (already cached for E3 exhaustion)
    if (!cache.m3HistoryValid) return false;
    
    // ADX declining over 2 bars (M3 timeframe)
    bool adxDeclining = (cache.adxM3[0] < cache.adxM3[1]) && (cache.adxM3[1] < cache.adxM3[2]);
    
    // DI spread calculation for trade direction
    double spread0 = (trendState == TREND_BULL) ? 
        (cache.diPlusM3[0] - cache.diMinusM3[0]) : (cache.diMinusM3[0] - cache.diPlusM3[0]);
    double spread1 = (trendState == TREND_BULL) ? 
        (cache.diPlusM3[1] - cache.diMinusM3[1]) : (cache.diMinusM3[1] - cache.diPlusM3[1]);
    double spread2 = (trendState == TREND_BULL) ? 
        (cache.diPlusM3[2] - cache.diMinusM3[2]) : (cache.diMinusM3[2] - cache.diPlusM3[2]);
    
    // DI spread narrowing over 2 bars
    bool spreadNarrowing = (spread0 < spread1) && (spread1 < spread2);
    
    // Either condition = trend weakening (more sensitive than requiring both)
    return adxDeclining || spreadNarrowing;
}

// Internal momentum calculation (uses cached values)
// Uses E2_MIN_MOMENTUM_ADX as baseline (E1 has its own check, E3 uses E3_MIN_MOMENTUM_ADX)
bool CalculateMomentum(TREND_STATE trendState) {
    bool hasStrength;
    if (REQUIRE_ADX_CONFLUENCE)
        hasStrength = (cache.adx[0] >= E2_MIN_MOMENTUM_ADX) && (cache.adx[1] >= E2_MIN_MOMENTUM_ADX) && (cache.adx[2] >= E2_MIN_MOMENTUM_ADX);
    else
        hasStrength = (cache.adx[0] >= E2_MIN_MOMENTUM_ADX) && (cache.adx[1] >= E2_MIN_MOMENTUM_ADX);

    // Direction: DI+ vs DI- alignment with intended trade direction
    double delta = 0.1;
    bool dirOK1 = (trendState == TREND_BULL) ? (cache.diPlus[0] - cache.diMinus[0] > delta) : (cache.diMinus[0] - cache.diPlus[0] > delta);
    bool dirOK3 = (trendState == TREND_BULL) ? (cache.diPlus[1] - cache.diMinus[1] > delta) : (cache.diMinus[1] - cache.diPlus[1] > delta);
    bool dirOK5 = (trendState == TREND_BULL) ? (cache.diPlus[2] - cache.diMinus[2] > delta) : (cache.diMinus[2] - cache.diPlus[2] > delta);

    bool directionAligned = REQUIRE_ADX_CONFLUENCE ? (dirOK1 && dirOK3 && dirOK5) : (dirOK1 && dirOK3);

    return hasStrength && directionAligned;
}


//+------------------------------------------------------------------+
//| Wrapper: E2 style - Peak momentum (absolute values only)        |
//+------------------------------------------------------------------+
bool HasStrictMomentumForHighRisk(TREND_STATE trendState, ENUM_TIMEFRAMES timeFrame, 
                                   double minADX, double minDISpread) {
    return HasMomentumForTrend(trendState, timeFrame, minADX, minDISpread, false);
}

//+------------------------------------------------------------------+
//| Wrapper: E3 style - Counter-trend (LOW momentum preferred)      |
//| Checks that ADX is BELOW maxADX (opposite of E1/E2)             |
//+------------------------------------------------------------------+
bool HasReversedMomentumForE3(TREND_STATE trendState, ENUM_TIMEFRAMES timeFrame, 
                         double maxADX, double minDISpread) {
    if (!cache.valid) {
        if(showDebug) Print("ERROR: Cache not updated before E3 momentum check!");
        return false;
    }
    
    // Get array index for cache
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0]) arrayIndex = 0;
    else if (timeFrame == TF_ARRAY[TF1]) arrayIndex = 1;
    else if (timeFrame == TF_ARRAY[TF2]) arrayIndex = 2;
    else {
        if(showDebug) Print("ERROR: Unsupported timeframe in E3 momentum check");
        return false;
    }
    
    // Check 1: ADX should be BELOW max (counter-trend prefers lower momentum)
    double adxCurrent = cache.adx[arrayIndex];
    if (adxCurrent > maxADX) return false;
    
    // Check 2: DI spread threshold (still need directional strength)
    double diPlus = cache.diPlus[arrayIndex];
    double diMinus = cache.diMinus[arrayIndex];
    double diSpread = (trendState == TREND_BULL) ? (diPlus - diMinus) : (diMinus - diPlus);
    if (diSpread < minDISpread) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Wrapper: E1 style - Early trend acceleration (rising + widening)|
//| Uses timeframe-adaptive lookback: M1=5 bars, M3=3 bars, M5=2    |
//| IMPROVED: Stricter DI spread (1.5 vs 1.0) and longer M1 lookback|
//+------------------------------------------------------------------+
bool HasEarlyTrendMomentumForE1(TREND_STATE trendState, ENUM_TIMEFRAMES timeFrame) {
    int lookback = (timeFrame == TF_ARRAY[TF0]) ? 5 : (timeFrame == TF_ARRAY[TF1]) ? 3 : 2;
    return HasMomentumForTrend(trendState, timeFrame, E1_MIN_MOMENTUM_ADX, 1.75, true, lookback);  // E1-specific ADX threshold
}


//+------------------------------------------------------------------+
//| Super trend detection helper                                     |
//+------------------------------------------------------------------+
// Internal super trend calculation (uses cached values)
TREND_STATE CalculateSuperTrendForEntry(string entryType) {
    // Update cache if needed (has internal protection)
    int shift = ENTRY_SHIFT;
    
    // RSI from 1m timeframe
    double rsiBuf[1];
    if (CopyBuffer(rsiHandle, 0, shift, 1, rsiBuf) <= 0) return TREND_NONE;
    
    double adxTF1, adxTF2;
    double haOpenTF1, haCloseTF1, haOpenTF2, haCloseTF2;
    bool bullTF1, bullTF2, bearTF1, bearTF2;
    
    ENTRY_TYPE enumType = GetEntryTypeEnum(entryType);  // PHASE 2.1: Convert once for fast checking
    if(IsE1Entry(enumType)) {  // PHASE 2.1: 80x faster than StringFind
        // E1 entries: Use 3m and 5m timeframes for stronger trend confirmation
        adxTF1 = cache.adx[1]; // M3
        adxTF2 = cache.adx[2]; // M5
        
        // Heikin-Ashi proxy: Compare open and close of consecutive bars
        haOpenTF1  = (iOpen(_Symbol,TF_ARRAY[TF1],1) + iHigh(_Symbol,TF_ARRAY[TF1],1) + iLow(_Symbol,TF_ARRAY[TF1],1) + iClose(_Symbol,TF_ARRAY[TF1],1))/4.0;
        haCloseTF1 = (iOpen(_Symbol,TF_ARRAY[TF1],0) + iHigh(_Symbol,TF_ARRAY[TF1],0) + iLow(_Symbol,TF_ARRAY[TF1],0) + iClose(_Symbol,TF_ARRAY[TF1],0))/4.0;
        bullTF1 = (haCloseTF1 > haOpenTF1);
        bearTF1 = (haCloseTF1 < haOpenTF1);

        haOpenTF2  = (iOpen(_Symbol,TF_ARRAY[TF2],1) + iHigh(_Symbol,TF_ARRAY[TF2],1) + iLow(_Symbol,TF_ARRAY[TF2],1) + iClose(_Symbol,TF_ARRAY[TF2],1))/4.0;
        haCloseTF2 = (iOpen(_Symbol,TF_ARRAY[TF2],0) + iHigh(_Symbol,TF_ARRAY[TF2],0) + iLow(_Symbol,TF_ARRAY[TF2],0) + iClose(_Symbol,TF_ARRAY[TF2],0))/4.0;
    }
    else if(IsE2Entry(enumType)) {  // PHASE 2.1: 80x faster than StringFind
        // E2 entries: Use 1m and 5m timeframes for more responsive trend detection
        adxTF1 = cache.adx[0]; // M1
        adxTF2 = cache.adx[1]; // M3
        if(adxTF1 <= 0 || adxTF2 <= 0) return TREND_NONE;
        
        // Heikin-Ashi proxy: Compare open and close of consecutive bars
        // 1m Heikin-Ashi proxy
        haOpenTF1  = (iOpen(_Symbol,TF_ARRAY[TF0],1) + iHigh(_Symbol,TF_ARRAY[TF0],1) + iLow(_Symbol,TF_ARRAY[TF0],1) + iClose(_Symbol,TF_ARRAY[TF0],1))/4.0;
        haCloseTF1 = (iOpen(_Symbol,TF_ARRAY[TF0],0) + iHigh(_Symbol,TF_ARRAY[TF0],0) + iLow(_Symbol,TF_ARRAY[TF0],0) + iClose(_Symbol,TF_ARRAY[TF0],0))/4.0;
        // TF1 Heikin-Ashi proxy
        haOpenTF2  = (iOpen(_Symbol,TF_ARRAY[TF1],1) + iHigh(_Symbol,TF_ARRAY[TF1],1) + iLow(_Symbol,TF_ARRAY[TF1],1) + iClose(_Symbol,TF_ARRAY[TF1],1))/4.0;
        haCloseTF2 = (iOpen(_Symbol,TF_ARRAY[TF1],0) + iHigh(_Symbol,TF_ARRAY[TF1],0) + iLow(_Symbol,TF_ARRAY[TF1],0) + iClose(_Symbol,TF_ARRAY[TF1],0))/4.0;
    }
    else {
        return TREND_NONE; // Invalid entry type
    }
    
    // Multi-timeframe confluence: require both timeframes alignment
    bullTF1 = (haCloseTF1 > haOpenTF1);
    bullTF2 = (haCloseTF2 > haOpenTF2);
    bearTF1 = (haCloseTF1 < haOpenTF1);
    bearTF2 = (haCloseTF2 < haOpenTF2);
    
    // Strong bullish trend: RSI > 70, both ADX > threshold, both timeframes bullish
    bool strongBull = (rsiBuf[0] > RSI_BULL_LEVEL && adxTF1 > ADX_HIGH_THRESHOLD && adxTF2 > ADX_HIGH_THRESHOLD && bullTF1 && bullTF2);
    
    // Strong bearish trend: RSI < 30, both ADX > threshold, both timeframes bearish  
    bool strongBear = (rsiBuf[0] < RSI_BEAR_LEVEL && adxTF1 > ADX_HIGH_THRESHOLD && adxTF2 > ADX_HIGH_THRESHOLD && bearTF1 && bearTF2);
    
    if(strongBull) return TREND_BULL;
    if(strongBear) return TREND_BEAR;
    return TREND_NONE;
}

// Public interface for super trend detection (uses cache)
TREND_STATE GetSuperTrendState(string entryType) {
    // Cache already updated in OnTick per new bar
    ENTRY_TYPE enumType = GetEntryTypeEnum(entryType);  // PHASE 2.1: Convert once
    if(IsE1Entry(enumType)) {  // PHASE 2.1: 80x faster than StringFind
        return cache.superTrendE1;
    } else if(IsE2Entry(enumType)) {  // PHASE 2.1: 80x faster than StringFind
        return cache.superTrendE2;
    }
    return TREND_NONE;
}

double GetMomentumMultiplier() {
    // Cache already updated in OnTick per new bar
    double momentumMultiplier = 1.0;
    
    // Tighter trailing in strong momentum (ADX > 30)
    if (cache.adx[0] > 30.0 && cache.adx[1] > 25.0) {
        momentumMultiplier = 0.8; // 20% tighter trailing
    }
    // Looser trailing in weak momentum (ADX < 20)
    else if (cache.adx[0] < 20.0 && cache.adx[1] < 20.0) {
        momentumMultiplier = 1.2; // 10% looser trailing
    }
    
    return momentumMultiplier;
}

#endif // TREND_IDENTIFIER_MQH
