#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef ENTRY_HELPERS_MQH
#define ENTRY_HELPERS_MQH

//+------------------------------------------------------------------+
//| Entry Helpers                                                    |
//+------------------------------------------------------------------+

int CalculateConvictionScore(bool isLong, ENTRY_TYPE entryType, bool convictionEnabled, bool applyTrendVeto) {
    if(!convictionEnabled) return 999; // Bypass if disabled for this entry type (always passes)

    int score = 0;
    string components = "";  // For detailed logging

    // ========== HTF VETO: Hard Block if Against Higher Timeframe Trend ==========
    if(applyTrendVeto) {
        // Use adaptive confirmation TF EMAs (fast=75, slow=100) as trend proxy
        double conf_fast = emaBuffers[GetEMABufferIndex(CFG.confirmationTFIndex, EMA2)][ENTRY_SHIFT];
        double conf_slow = emaBuffers[GetEMABufferIndex(CFG.confirmationTFIndex, EMA3)][ENTRY_SHIFT];
        
        bool confTrendUp = (conf_fast > conf_slow);
        bool confTrendDown = (conf_fast < conf_slow);
        
        // Return -999 to block entry if against higher TF trend
        if(isLong && confTrendDown) {
            if(showDebug) {
                string tfName = CFG.useS30 ? "M3" : "M5";
                Print("[CONVICTION HTF VETO] LONG blocked - ", tfName, " downtrend (EMA75=", 
                      DoubleToString(conf_fast,2), " < EMA100=", DoubleToString(conf_slow,2), ")");
            }
            return -999; // Hard block
        }
        if(!isLong && confTrendUp) {
            if(showDebug) {
                string tfName = CFG.useS30 ? "M3" : "M5";
                Print("[CONVICTION HTF VETO] SHORT blocked - ", tfName, " uptrend (EMA75=", 
                      DoubleToString(conf_fast,2), " > EMA100=", DoubleToString(conf_slow,2), ")");
            }
            return -999; // Hard block
        }
    }
    
    // ========== COMPONENT 1: M1 DI Spread (0-2 points) ==========
    // Critical directional strength on entry timeframe
    double m1_spread = isLong ? (cache.diPlus[0] - cache.diMinus[0]) : 
                                 (cache.diMinus[0] - cache.diPlus[0]);
    int diPoints = 0;
    if (m1_spread >= 3.0)      diPoints = 2;  // Strong directional bias
    else if (m1_spread >= 1.0) diPoints = 1;  // Moderate bias
    // else 0 points
    
    score += diPoints;
    components += StringFormat("M1_DI:%d(%.1f) ", diPoints, m1_spread);
    
    // ========== COMPONENT 2: EMA Stack Separation Quality (0-2 points) ==========
    double separation = Calculate4EMAStackSeparation(isLong);
    int emaPoints = 0;
    if (separation >= 0.8)      emaPoints = 2;  // Excellent separation (24+ pips avg)
    else if (separation >= 0.5) emaPoints = 1;  // Moderate separation (15+ pips avg)
    // else 0 points
    
    score += emaPoints;
    components += StringFormat("EMA:%d(%.2f) ", emaPoints, separation);
    
    // ========== COMPONENT 3: RSI Momentum Quality (0-2 points) ==========
    // Simplified for M1/M3 scalping: RSI level + velocity (no EMA lag)
    double rsi_m1 = GetRSIValue(TF_ARRAY[TF0], 14, ENTRY_SHIFT);
    double rsi_m1_prev = GetRSIValue(TF_ARRAY[TF0], 14, ENTRY_SHIFT + 2);
    double rsi_m3 = GetRSIValue(TF_ARRAY[TF1], 14, ENTRY_SHIFT);
    
    int rsiPoints = 0;
    if (isLong) {
        // Level check: RSI above 50 = bullish bias
        bool m1Above50 = (rsi_m1 > 50.0);
        bool m3Above50 = (rsi_m3 > 50.0);
        
        // Velocity check: RSI accelerating upward
        double velocity = (rsi_m1 - rsi_m1_prev) / 2.0;  // Points per bar
        bool accelerating = (velocity > 1.5);  // Rising at least 1.5 pts/bar
        
        // Scoring
        if (m1Above50 && m3Above50)           rsiPoints += 2;  // Both timeframes bullish
        else if (m1Above50 || m3Above50)      rsiPoints += 1;  // Partial alignment
        
        if (accelerating && m1Above50)        rsiPoints += 1;  // Bonus for momentum (can exceed 2, clamped below)
        
    } else {
        // SHORT: Mirror logic
        bool m1Below50 = (rsi_m1 < 50.0);
        bool m3Below50 = (rsi_m3 < 50.0);
        
        double velocity = (rsi_m1_prev - rsi_m1) / 2.0;  // Falling = positive velocity for shorts
        bool accelerating = (velocity > 1.5);
        
        if (m1Below50 && m3Below50)           rsiPoints += 2;
        else if (m1Below50 || m3Below50)      rsiPoints += 1;
        
        if (accelerating && m1Below50)        rsiPoints += 1;
    }
    
    rsiPoints = MathMax(0, MathMin(2, rsiPoints));  // Clamp 0-2
    score += rsiPoints;
    components += StringFormat("RSI:%d(M1:%.1f,M3:%.1f,v%.1f) ", rsiPoints, rsi_m1, rsi_m3, (rsi_m1 - rsi_m1_prev)/2.0);
    
    // ========== COMPONENT 4: ADX Strength + Acceleration (0-2 points) ==========
    double adx_1m = cache.adx[0];
    
    // Check ADX acceleration
    bool hasAccel = false;
    double adxBuffer[];
    ArraySetAsSeries(adxBuffer, true);
    if (CopyBuffer(adxHandles[0], 0, 0, 3, adxBuffer) == 3) {
        hasAccel = IsAccelerating(adxBuffer, 3);
    }
    
    int adxPoints = 0;
    // Level scoring
    if (adx_1m >= 23.0)      adxPoints += 1;   // Strong trend
    else if (adx_1m < 15.0)  adxPoints -= 1;   // Weak (penalty)
    
    // Acceleration bonus
    if (hasAccel)            adxPoints += 1;
    
    adxPoints = MathMax(0, MathMin(2, adxPoints));  // Clamp 0-2
    score += adxPoints;
    components += StringFormat("ADX:%d(%.1f%s) ", adxPoints, adx_1m, hasAccel?"↑":"");
    
    // ========== COMPONENT 5: M3+M5 Multi-Timeframe Confirmation (0-2 points) ==========
    // Adjusted to 0-2 scale for total 0-10 scoring
    double adx_3m = cache.adx[1];
    double adx_5m = cache.adx[2];
    TREND_STATE trendState = isLong ? TREND_BULL : TREND_BEAR;
    
    double spread_3m = (trendState == TREND_BULL) ? 
                       (cache.diPlus[1] - cache.diMinus[1]) :
                       (cache.diMinus[1] - cache.diPlus[1]);
    double spread_5m = (trendState == TREND_BULL) ? 
                       (cache.diPlus[2] - cache.diMinus[2]) :
                       (cache.diMinus[2] - cache.diPlus[2]);
    
    // Check M3 strength
    bool m3Strong  = (adx_3m >= 22.0 && spread_3m >= 2.0);
    bool m3Support = (adx_3m >= 16.0 && spread_3m > 0.5);
    
    // Check M5 strength
    bool m5Strong  = (adx_5m >= 22.0 && spread_5m >= 2.0);
    bool m5Support = (adx_5m >= 16.0 && spread_5m > 0.5);
    
    int mtfPoints = 0;
    if (m3Strong && m5Strong)           mtfPoints = 2;   // Both strong (highest confidence)
    else if (m3Strong || m5Strong)      mtfPoints = 1;   // One strong
    else if (m3Support && m5Support)    mtfPoints = 1;   // Both moderate support
    // else 0 (neither support)
    
    score += mtfPoints;
    components += StringFormat("MTF:%d(M3:%.1f/%.1f,M5:%.1f/%.1f) ", mtfPoints, adx_3m, spread_3m, adx_5m, spread_5m);
    
    // ========== COMPONENT 6: Price Action Structure (0-2 points) ==========
    bool hasBullishPA = CheckBullishPriceAction(3);
    bool hasBearishPA = CheckBearishPriceAction(3);
    
    int paPoints = 0;
    if (isLong && hasBullishPA)           paPoints = 2;   // Aligned structure
    else if (!isLong && hasBearishPA)     paPoints = 2;   // Aligned structure
    else if (isLong && !hasBearishPA)     paPoints = 1;   // Neutral OK
    else if (!isLong && !hasBullishPA)    paPoints = 1;   // Neutral OK
    // else 0 (conflicting structure)
    
    score += paPoints;
    components += StringFormat("PA:%d(%s)", paPoints, 
                              isLong ? (hasBullishPA?"bull":"neut") : (hasBearishPA?"bear":"neut"));
    
    return score;  // Max: 12 points (M1_DI:2 + EMA:2 + RSI:2 + ADX:2 + MTF:2 + PA:2)
}


//+------------------------------------------------------------------+
//| Calculate Conviction Score (0-4) for Entry Quality              |
//| Phase 2: Flattens boolean gates into single numeric score       |
//| entryType: ENTRY_L_E1, ENTRY_S_E1, ENTRY_L_E2, etc.            |
//+------------------------------------------------------------------+
// NEW: HTF Veto Check - Independent from conviction scoring
int CheckHTFVeto(bool isLong, ENTRY_TYPE entryType, bool applyTrendVeto) {
    if(!applyTrendVeto) return 0; // No penalty if veto disabled
    
    // Use adaptive confirmation TF EMAs (fast=75, slow=100) as trend proxy
    double conf_fast = emaBuffers[GetEMABufferIndex(CFG.confirmationTFIndex, EMA2)][ENTRY_SHIFT];
    double conf_slow = emaBuffers[GetEMABufferIndex(CFG.confirmationTFIndex, EMA3)][ENTRY_SHIFT];
    
    bool confTrendUp = (conf_fast > conf_slow);
    bool confTrendDown = (conf_fast < conf_slow);
    
    // Return -999 to block entry if against higher TF trend
    if(isLong && confTrendDown) {
        if(showDebug) {
            string tfName = CFG.useS30 ? "M3" : "M5";
            Print("[HTF VETO] LONG entry blocked - ", tfName, " in downtrend (EMA75=", 
                  DoubleToString(conf_fast,2), " < EMA100=", DoubleToString(conf_slow,2), ")");
        }
        return -999; // Block entry
    }
    if(!isLong && confTrendUp) {
        if(showDebug) {
            string tfName = CFG.useS30 ? "M3" : "M5";
            Print("[HTF VETO] SHORT entry blocked - ", tfName, " in uptrend (EMA75=", 
                  DoubleToString(conf_fast,2), " > EMA100=", DoubleToString(conf_slow,2), ")");
        }
        return -999; // Block entry
    }
    
    return 0; // No veto, entry allowed
}

//+------------------------------------------------------------------+
//| Helper: Calculate EMA stack separation quality (0.0 - 1.0)      |
//| Returns normalized score based on how well EMAs are separated    |
//+------------------------------------------------------------------+
double Calculate4EMAStackSeparation(bool isLong) {
    double e25  = emaBuffers[GetEMABufferIndex(TF0, EMA1)][ENTRY_SHIFT];
    double e75  = emaBuffers[GetEMABufferIndex(TF0, EMA2)][ENTRY_SHIFT];
    double e100 = emaBuffers[GetEMABufferIndex(TF0, EMA3)][ENTRY_SHIFT];
    double e200 = emaBuffers[GetEMABufferIndex(TF0, EMA4)][ENTRY_SHIFT];
    
    // Check proper ordering first
    bool ordered = isLong ? (e25 > e75 && e75 > e100 && e100 >= e200) :
                            (e25 < e75 && e75 < e100 && e100 <= e200);
    if (!ordered) return 0.0;
    
    // Calculate average gap between EMAs (normalized to pips)
    double gap1 = MathAbs(e25 - e75) / pipSize;
    double gap2 = MathAbs(e75 - e100) / pipSize;
    double gap3 = MathAbs(e100 - e200) / pipSize;
    double avgGap = (gap1 + gap2 + gap3) / 3.0;
    
    // Normalize: 10 pips = 0.33, 20 pips = 0.67, 30+ pips = 1.0
    double normalized = avgGap / 30.0;
    return MathMin(1.0, normalized);
}

//+------------------------------------------------------------------+
//| Helper: Check for bullish price action structure                |
//| Returns true if majority of recent bars are bullish             |
//+------------------------------------------------------------------+
bool CheckBullishPriceAction(int lookback) {
    if (lookback < 2) lookback = 2;
    
    double closes[], opens[];
    ArraySetAsSeries(closes, true);
    ArraySetAsSeries(opens, true);
    
    if (CopyClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT, lookback, closes) < lookback ||
        CopyOpen(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT, lookback, opens) < lookback)
        return false;
    
    // Count bullish bars (close > open)
    int bullishBars = 0;
    for (int i = 0; i < lookback; i++) {
        if (closes[i] > opens[i]) bullishBars++;
    }
    
    // Require at least (n-1)/n bars bullish (e.g., 2/3 or 3/3)
    return bullishBars >= (lookback - 1);
}

//+------------------------------------------------------------------+
//| Helper: Check for bearish price action structure                |
//| Returns true if majority of recent bars are bearish             |
//+------------------------------------------------------------------+
bool CheckBearishPriceAction(int lookback) {
    if (lookback < 2) lookback = 2;
    
    double closes[], opens[];
    ArraySetAsSeries(closes, true);
    ArraySetAsSeries(opens, true);
    
    if (CopyClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT, lookback, closes) < lookback ||
        CopyOpen(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT, lookback, opens) < lookback)
        return false;
    
    // Count bearish bars (close < open)
    int bearishBars = 0;
    for (int i = 0; i < lookback; i++) {
        if (closes[i] < opens[i]) bearishBars++;
    }
    
    // Require at least (n-1)/n bars bearish
    return bearishBars >= (lookback - 1);
}

//+------------------------------------------------------------------+
//| RSI Divergence Veto: Block entries when M3 RSI diverges against  |
//| trade direction. Bearish div blocks longs, bullish div blocks    |
//| shorts. Uses split-window peak/trough comparison.                |
//| Returns true if divergence detected (entry should be blocked).   |
//+------------------------------------------------------------------+
bool HasRSIDivergenceAgainstTrade(bool isLong, string entryLabel) {
    if (!ENABLE_RSI_DIVERGENCE_VETO) return false;
    
    int lookback = RSI_DIV_LOOKBACK;
    int halfLB = lookback / 2;
    if (halfLB < 2) return false;
    
    // Get M3 price data
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    if (CopyHigh(_Symbol, TF_ARRAY[TF1], ENTRY_SHIFT, lookback, highs) < lookback) return false;
    if (CopyLow(_Symbol, TF_ARRAY[TF1], ENTRY_SHIFT, lookback, lows) < lookback) return false;
    
    // Get M3 RSI(14) - reuse existing cached handle (index 1 = M3)
    if (rsiHandlesTF[1] == INVALID_HANDLE || rsiHandlePeriodTF[1] != 14) {
        if (rsiHandlesTF[1] != INVALID_HANDLE) IndicatorRelease(rsiHandlesTF[1]);
        rsiHandlesTF[1] = iRSI(_Symbol, TF_ARRAY[TF1], 14, PRICE_CLOSE);
        rsiHandlePeriodTF[1] = 14;
        if (rsiHandlesTF[1] == INVALID_HANDLE) return false;
    }
    double rsi[];
    ArraySetAsSeries(rsi, true);
    if (CopyBuffer(rsiHandlesTF[1], 0, ENTRY_SHIFT, lookback, rsi) < lookback) return false;
    
    if (isLong) {
        // Bearish divergence: price makes higher highs, RSI makes lower highs
        // Find highest high in recent window [0..halfLB-1]
        int recentBar = 0;
        for (int i = 1; i < halfLB; i++) {
            if (highs[i] > highs[recentBar]) recentBar = i;
        }
        // Find highest high in older window [halfLB..lookback-1]
        int olderBar = halfLB;
        for (int i = halfLB + 1; i < lookback; i++) {
            if (highs[i] > highs[olderBar]) olderBar = i;
        }
        
        double priceDiffPips = (highs[recentBar] - highs[olderBar]) / pipSize;
        double rsiDiff = rsi[olderBar] - rsi[recentBar];
        
        if (priceDiffPips >= RSI_DIV_MIN_PRICE_DIFF_PIPS && rsiDiff >= RSI_DIV_MIN_RSI_DIFF) {
            if (showDebug) Print("[", entryLabel, "] RSI DIV VETO: Bearish div - Price HH +",
                                 DoubleToString(priceDiffPips, 1), "p, RSI LH -",
                                 DoubleToString(rsiDiff, 1), " (recent:", DoubleToString(rsi[recentBar], 1),
                                 " older:", DoubleToString(rsi[olderBar], 1), ")");
            return true;
        }
    } else {
        // Bullish divergence: price makes lower lows, RSI makes higher lows
        // Find lowest low in recent window [0..halfLB-1]
        int recentBar = 0;
        for (int i = 1; i < halfLB; i++) {
            if (lows[i] < lows[recentBar]) recentBar = i;
        }
        // Find lowest low in older window [halfLB..lookback-1]
        int olderBar = halfLB;
        for (int i = halfLB + 1; i < lookback; i++) {
            if (lows[i] < lows[olderBar]) olderBar = i;
        }
        
        double priceDiffPips = (lows[olderBar] - lows[recentBar]) / pipSize;
        double rsiDiff = rsi[recentBar] - rsi[olderBar];
        
        if (priceDiffPips >= RSI_DIV_MIN_PRICE_DIFF_PIPS && rsiDiff >= RSI_DIV_MIN_RSI_DIFF) {
            if (showDebug) Print("[", entryLabel, "] RSI DIV VETO: Bullish div - Price LL -",
                                 DoubleToString(priceDiffPips, 1), "p, RSI HL +",
                                 DoubleToString(rsiDiff, 1), " (recent:", DoubleToString(rsi[recentBar], 1),
                                 " older:", DoubleToString(rsi[olderBar], 1), ")");
            return true;
        }
    }
    
    return false;
}

#endif // ENTRY_HELPERS_MQH
