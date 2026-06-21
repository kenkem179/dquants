//+------------------------------------------------------------------+
//| EntryConditions.mqh - Reusable Entry Condition Checks           |
//| Phase 1.4: Organize messy Helpers into clean modular rules      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef ENTRYCONDITIONS_MQH
#define ENTRYCONDITIONS_MQH

#include "../Core/GlobalState.mqh"

//+------------------------------------------------------------------+
//| EntryConditions: Reusable building blocks for entry detection   |
//| Combines multiple atomic checks without JSON overhead           |
//+------------------------------------------------------------------+
class EntryConditions {
public:
    //--------------------------------------------------------------------
    // EMA ALIGNMENT CHECKS
    //--------------------------------------------------------------------
    bool CheckEMAStackAlignedUp(int tf) {
        // EMA25 > EMA75 > EMA100 > EMA200 (bullish stack)
        double e0 = emaBuffers[GetEMABufferIndex(tf, EMA1)][ENTRY_SHIFT];
        double e1 = emaBuffers[GetEMABufferIndex(tf, EMA2)][ENTRY_SHIFT];
        double e2 = emaBuffers[GetEMABufferIndex(tf, EMA3)][ENTRY_SHIFT];
        double e3 = emaBuffers[GetEMABufferIndex(tf, EMA4)][ENTRY_SHIFT];
        return (e0 > e1 && e1 > e2 && e2 >= e3);
    }
    
    bool CheckEMAStackAlignedDown(int tf) {
        // EMA25 < EMA75 < EMA100 < EMA200 (bearish stack)
        double e0 = emaBuffers[GetEMABufferIndex(tf, EMA1)][ENTRY_SHIFT];
        double e1 = emaBuffers[GetEMABufferIndex(tf, EMA2)][ENTRY_SHIFT];
        double e2 = emaBuffers[GetEMABufferIndex(tf, EMA3)][ENTRY_SHIFT];
        double e3 = emaBuffers[GetEMABufferIndex(tf, EMA4)][ENTRY_SHIFT];
        return (e0 < e1 && e1 < e2 && e2 <= e3);
    }
    
    bool CheckEMACross(int tf, int fastEMA, int slowEMA, bool bullish) {
        // Check if fast EMA crossed above/below slow EMA
        double fastNow = emaBuffers[GetEMABufferIndex(tf, fastEMA)][ENTRY_SHIFT];
        double slowNow = emaBuffers[GetEMABufferIndex(tf, slowEMA)][ENTRY_SHIFT];
        
        if(bullish) return (fastNow > slowNow);
        else return (fastNow < slowNow);
    }
    
    bool CheckPriceTouchingEMA(int tf, int emaPeriod, double tolerancePips) {
        // Check if price is near EMA (for E2 pullback entries)
        double emaValue = emaBuffers[GetEMABufferIndex(tf, emaPeriod)][ENTRY_SHIFT];
        double currentPrice = iClose(NULL, tf, ENTRY_SHIFT);
        double distance = MathAbs(currentPrice - emaValue) / _Point;
        return (distance <= tolerancePips);
    }
    
    //--------------------------------------------------------------------
    // MOMENTUM CHECKS
    //--------------------------------------------------------------------
    bool CheckADXAbove(int tf, double threshold) {
        // Simple ADX strength check
        double adx = GetADXValue(tf, 14, ENTRY_SHIFT);
        return (adx >= threshold);
    }
    
    bool CheckDISpreadAbove(int tf, double threshold) {
        // DI+/DI- spread check
        double diPlus = GetDIPlusValue(tf, 14, ENTRY_SHIFT);
        double diMinus = GetDIMinusValue(tf, 14, ENTRY_SHIFT);
        double spread = MathAbs(diPlus - diMinus);
        return (spread >= threshold);
    }
    
    bool CheckRSIInRange(int tf, int period, double minVal, double maxVal) {
        double rsi = GetRSIValue(tf, period, ENTRY_SHIFT);
        return (rsi >= minVal && rsi <= maxVal);
    }
    
    bool CheckRSIBullish(int tf, int period, double threshold) {
        // RSI momentum for longs
        double rsi = GetRSIValue(tf, period, ENTRY_SHIFT);
        return (rsi >= threshold);
    }
    
    bool CheckRSIBearish(int tf, int period, double threshold) {
        // RSI momentum for shorts
        double rsi = GetRSIValue(tf, period, ENTRY_SHIFT);
        return (rsi <= threshold);
    }
    
    //--------------------------------------------------------------------
    // HTF TREND CONFIRMATION
    //--------------------------------------------------------------------
    bool CheckHTFTrendAligned(int htf, bool isLong) {
        // Check if higher timeframe trend matches entry direction
        double conf_fast = emaBuffers[GetEMABufferIndex(htf, EMA2)][ENTRY_SHIFT];
        double conf_slow = emaBuffers[GetEMABufferIndex(htf, EMA3)][ENTRY_SHIFT];
        
        if(isLong) return (conf_fast > conf_slow);  // HTF uptrend
        else return (conf_fast < conf_slow);        // HTF downtrend
    }
    
    bool CheckHTFTrendAgainst(int htf, bool isLong) {
        // Returns true if HTF trend OPPOSES entry direction (veto signal)
        return !CheckHTFTrendAligned(htf, isLong);
    }
    
    //--------------------------------------------------------------------
    // COMPOSITE CONDITIONS (combine multiple rules)
    //--------------------------------------------------------------------
    bool CheckMomentumFilter(int tf, double minADX, double minDISpread) {
        // Combined momentum check (ADX OR DI spread)
        return CheckADXAbove(tf, minADX) || CheckDISpreadAbove(tf, minDISpread);
    }
    
    bool CheckStrongMomentum(int tf, double minADX, double minDISpread, double minRSI) {
        // All momentum indicators must align (AND logic)
        return CheckADXAbove(tf, minADX) && 
               CheckDISpreadAbove(tf, minDISpread) &&
               CheckRSIBullish(tf, 14, minRSI);
    }
    
    // Commented out for now - Clean up confusion with old conviction score 
    // bool CheckConvictionScore(bool isLong, int minScore) {
    //     // Combine EMA alignment + RSI + ADX into single score
    //     int score = 0;
        
    //     // Rule 1: EMA stack alignment (+1)
    //     if(isLong && CheckEMAStackAlignedUp(TF0)) score++;
    //     if(!isLong && CheckEMAStackAlignedDown(TF0)) score++;
        
    //     // Rule 2: RSI momentum (+1)
    //     if(isLong && CheckRSIBullish(TF_ARRAY[TF0], 14, 56.0)) score++;
    //     if(!isLong && CheckRSIBearish(TF_ARRAY[TF0], 14, 45.0)) score++;
        
    //     // Rule 3: ADX strength (+1, asymmetric)
    //     if(isLong && CheckADXAbove(TF_ARRAY[TF0], 18.0)) score++;
    //     if(!isLong && CheckADXAbove(TF_ARRAY[TF0], 21.0)) score++;
        
    //     if(showDebug) {
    //         Print("[EntryConditions] Conviction score: ", score, "/3 (required: ", minScore, ")");
    //     }
        
    //     return (score >= minScore);
    // }
    
    //--------------------------------------------------------------------
    // PRICE ACTION CHECKS
    //--------------------------------------------------------------------
    bool CheckPriceAboveEMA(int tf, int emaPeriod) {
        double emaValue = emaBuffers[GetEMABufferIndex(tf, emaPeriod)][ENTRY_SHIFT];
        double currentPrice = iClose(NULL, tf, ENTRY_SHIFT);
        return (currentPrice > emaValue);
    }
    
    bool CheckPriceBelowEMA(int tf, int emaPeriod) {
        double emaValue = emaBuffers[GetEMABufferIndex(tf, emaPeriod)][ENTRY_SHIFT];
        double currentPrice = iClose(NULL, tf, ENTRY_SHIFT);
        return (currentPrice < emaValue);
    }
    
    bool CheckCandleBullish(int tf, int shift) {
        double open = iOpen(NULL, tf, shift);
        double close = iClose(NULL, tf, shift);
        return (close > open);
    }
    
    bool CheckCandleBearish(int tf, int shift) {
        double open = iOpen(NULL, tf, shift);
        double close = iClose(NULL, tf, shift);
        return (close < open);
    }
};

#endif // ENTRYCONDITIONS_MQH
