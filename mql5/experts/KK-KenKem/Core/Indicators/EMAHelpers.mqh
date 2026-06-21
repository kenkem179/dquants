//+------------------------------------------------------------------+
//|                                           IndicatorHelpers.mqh |
//|              KenKem EA v1.7.51 - Indicator Helper Functions     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// INDICATOR HELPER FUNCTIONS
// EMA retrieval and market status checks
//================================================================

//+------------------------------------------------------------------+
//| Get EMA values for all timeframes                                |
//+------------------------------------------------------------------+
bool GetEMAValues()
{
    // Get EMA values for all timeframes using 2D array structure
    int bufferSize = ENTRY_SHIFT + 3; // Ensure we have enough data for all array access
    
    // Loop through timeframes: TF0=M1, TF1=M3, TF2=M5, TF3=M15
    for(int tf = 0; tf < NUM_TF; tf++) {
        // Loop through EMA indices: EMA0=fast, EMA1=signal, EMA2=pullback, EMA3=bounce, EMA4=anchor
        for(int ema = 0; ema < NUM_EMA; ema++) {
            int bufferIndex = GetEMABufferIndex(tf, ema);
            double tempBuffer[];
            ArrayResize(tempBuffer, bufferSize);
            if(CopyBuffer(emaHandles[tf][ema], 0, 0, bufferSize, tempBuffer) <= 0) {
                if(showDebug) Print("Failed to copy EMA buffer for timeframe ", tf, " period ", ema);
                return false;
            }
            // Copy from temp buffer to our 2D array
            for(int i = 0; i < bufferSize; i++) {
                emaBuffers[bufferIndex][i] = tempBuffer[i];
            }
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Helper functions to access EMA values with readable syntax      |
//+------------------------------------------------------------------+
double GetEMA(int tfIdx, int emaIdx, int shift = 0)
{
    // Validate indices
    if(tfIdx < 0 || tfIdx >= NUM_TF) {
        Print("ERROR: Invalid timeframe index ", tfIdx);
        return 0.0;
    }
    if(emaIdx < 0 || emaIdx >= NUM_EMA) {
        Print("ERROR: Invalid EMA index ", emaIdx);
        return 0.0;
    }
    
    // Get the flattened buffer index
    int bufferIndex = GetEMABufferIndex(tfIdx, emaIdx);
    
    // Validate shift
    if(shift < 0 || shift >= ArrayRange(emaBuffers, 1)) {
        Print("ERROR: Invalid shift ", shift, " for tfIdx=", tfIdx, " emaIdx=", emaIdx);
        return 0.0;
    }
    
    return emaBuffers[bufferIndex][shift];
}

// Convenience functions for specific timeframes (emaIdx = EMA0..EMA4 constants)
double GetEMA_1m(int emaIdx, int shift = 0) { return GetEMA(TF0, emaIdx, shift); }
double GetEMA_3m(int emaIdx, int shift = 0) { return GetEMA(TF1, emaIdx, shift); }
double GetEMA_5m(int emaIdx, int shift = 0) { return GetEMA(TF2, emaIdx, shift); }
double GetEMA_15m(int emaIdx, int shift = 0) { return GetEMA(TF3, emaIdx, shift); }

//+------------------------------------------------------------------+
//| Check if market is open for trading                              |
//+------------------------------------------------------------------+
bool IsMarketOpen() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Check if symbol allows trading at current time
    datetime currentTime = TimeCurrent();
    
    // Get trading session info
    datetime sessionStart, sessionEnd;
    if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, 0, sessionStart, sessionEnd)) {
        // If can't get session info, assume market is closed
        return false;
    }
    
    // Check if current time is within trading session
    datetime currentTimeOfDay = currentTime % 86400; // Seconds since midnight
    
    // Handle sessions that cross midnight
    if(sessionEnd < sessionStart) {
        return (currentTimeOfDay >= sessionStart || currentTimeOfDay <= sessionEnd);
    } else {
        return (currentTimeOfDay >= sessionStart && currentTimeOfDay <= sessionEnd);
    }
}

// Helper function: Check if EMAs are flat (not trending)
bool IsEMAFlat(ENUM_TIMEFRAMES timeFrame, int lastBars) {
    // Convert ENUM_TIMEFRAMES to timeframe index
    int tfIndex = -1;
    if(timeFrame == TF_ARRAY[TF0])       tfIndex = TF0;
    else if(timeFrame == TF_ARRAY[TF1])  tfIndex = TF1;
    else if(timeFrame == TF_ARRAY[TF2])  tfIndex = TF2;
    else if(timeFrame == TF_ARRAY[TF3])  tfIndex = TF3;
    else return false;
    
    double ema25_start = GetEMA(tfIndex, EMA1, lastBars-1);
    double ema25_end = GetEMA(tfIndex, EMA1, 0);
    double ema100_start = GetEMA(tfIndex, EMA3, lastBars-1);
    double ema100_end = GetEMA(tfIndex, EMA3, 0);
    
    if(ema25_start <= 0 || ema25_end <= 0 || ema100_start <= 0 || ema100_end <= 0) return false;
    
    // Calculate EMA slope as percentage change
    double ema25_change = MathAbs((ema25_end - ema25_start) / ema25_start) * 100.0;
    double ema100_change = MathAbs((ema100_end - ema100_start) / ema100_start) * 100.0;
    
    // Flat if both EMAs changed less than 0.1%
    return (ema25_change < 0.1) && (ema100_change < 0.1);
}

//+------------------------------------------------------------------+
//| Initialize EMA Flags from Historical Data (Last 50 Bars)        |
//+------------------------------------------------------------------+
void InitializeEMAFlagsFromHistory() {
    int lookbackBars = 50;
    int totalBars = Bars(_Symbol, TF_ARRAY[TF0]);
    
    if (totalBars < lookbackBars + 5) {
        Print("[HISTORY INIT] WARNING: Not enough bars for historical scan (", totalBars, " bars available)");
        return;
    }
    
    Print("[HISTORY INIT] Scanning last ", lookbackBars, " bars for EMA crossings and touches...");
    
    // Prepare EMA buffers for historical scan (use CopyBuffer directly)
    double ema25[], ema75[], ema100[], ema200[];
    ArraySetAsSeries(ema25, true);
    ArraySetAsSeries(ema75, true);
    ArraySetAsSeries(ema100, true);
    ArraySetAsSeries(ema200, true);
    
    // Copy historical data
    int copied25 = CopyBuffer(emaHandles[TF0][EMA_25], 0, 0, lookbackBars + 2, ema25);
    int copied75 = CopyBuffer(emaHandles[TF0][EMA_75], 0, 0, lookbackBars + 2, ema75);
    int copied100 = CopyBuffer(emaHandles[TF0][EMA_100], 0, 0, lookbackBars + 2, ema100);
    int copied200 = CopyBuffer(emaHandles[TF0][EMA_200], 0, 0, lookbackBars + 2, ema200);
    
    if (copied25 < lookbackBars || copied75 < lookbackBars || copied100 < lookbackBars || copied200 < lookbackBars) {
        Print("[HISTORY INIT] WARNING: Failed to copy EMA buffers (25:", copied25, " 75:", copied75, " 100:", copied100, " 200:", copied200, ")");
        return;
    }
    
    // Scan from oldest to newest (reverse order) to find MOST RECENT events
    for (int i = lookbackBars; i >= 1; i--) {
        int barIndex = totalBars - 1 - i;
        
        // Check bullish alignment (EMA25 > EMA75 > EMA100 > EMA200)
        bool isBullishAligned = (ema25[i] > ema75[i] && ema75[i] > ema100[i] && ema100[i] > ema200[i]);
        bool wasBullishAligned = (ema25[i+1] > ema75[i+1] && ema75[i+1] > ema100[i+1] && ema100[i+1] > ema200[i+1]);
        
        // Check bearish alignment (EMA25 < EMA75 < EMA100 < EMA200)
        bool isBearishAligned = (ema25[i] < ema75[i] && ema75[i] < ema100[i] && ema100[i] < ema200[i]);
        bool wasBearishAligned = (ema25[i+1] < ema75[i+1] && ema75[i+1] < ema100[i+1] && ema100[i+1] < ema200[i+1]);
        
        // Check for EMA crossing UP (not aligned → bullish aligned)
        if (lastEMACrossingUp == -1 && !wasBullishAligned && isBullishAligned) {
            lastEMACrossingUp = barIndex;
            Print("[HISTORY INIT] Found EMA crossing UP at bar ", barIndex, " (", i, " bars ago)");
        }
        
        // Check for EMA crossing DOWN (not aligned → bearish aligned)
        if (lastEMACrossingDown == -1 && !wasBearishAligned && isBearishAligned) {
            lastEMACrossingDown = barIndex;
            Print("[HISTORY INIT] Found EMA crossing DOWN at bar ", barIndex, " (", i, " bars ago)");
        }
        
        // Check for EMA75 touch in bullish trend
        if (lastEma75TouchUp == -1 && isBullishAligned) {
            double high = iHigh(_Symbol, TF_ARRAY[TF0], i);
            double low = iLow(_Symbol, TF_ARRAY[TF0], i);

            if (low <= ema75[i] && high >= ema75[i]) {
                lastEma75TouchUp = barIndex;
                Print("[HISTORY INIT] Found EMA75 touch UP at bar ", barIndex, " (", i, " bars ago)");
            }
        }

        // Check for EMA75 touch in bearish trend
        if (lastEma75TouchDown == -1 && isBearishAligned) {
            double high = iHigh(_Symbol, TF_ARRAY[TF0], i);
            double low = iLow(_Symbol, TF_ARRAY[TF0], i);
            
            if (low <= ema75[i] && high >= ema75[i]) {
                lastEma75TouchDown = barIndex;
                Print("[HISTORY INIT] Found EMA75 touch DOWN at bar ", barIndex, " (", i, " bars ago)");
            }
        }
        
        // Early exit if all flags found
        if (lastEMACrossingUp != -1 && lastEMACrossingDown != -1 && 
            lastEma75TouchUp != -1 && lastEma75TouchDown != -1) {
            Print("[HISTORY INIT] All EMA events found, stopping scan early");
            break;
        }
    }
    
    // Summary
    Print("[HISTORY INIT] Initialization complete:");
    Print("   lastEMACrossingUp = ", lastEMACrossingUp);
    Print("   lastEMACrossingDown = ", lastEMACrossingDown);
    Print("   lastEma75TouchUp = ", lastEma75TouchUp);
    Print("   lastEma75TouchDown = ", lastEma75TouchDown);
}

// Update EMA touch status
void UpdateEmaTouches() {
    // Safety check: Ensure EMA arrays have sufficient data before accessing
    if (ArrayRange(emaBuffers, 1) < 3) {
        return; // Not enough data yet, skip EMA touch detection
    }

    bool m1JustCrossedUp = !isEMAsReadyForEntry(true, TF0, 2, true) && isEMAsReadyForEntry(true, TF0, 1, true);
    bool m3JustCrossedUp = !isEMAsReadyForEntry(true, TF1, 2, true) && isEMAsReadyForEntry(true, TF1, 1, true);
    bool m5JustCrossedUp = !isEMAsReadyForEntry(true, TF2, 2, false) && isEMAsReadyForEntry(true, TF2, 1, false);

    if (lastEMACrossingUp == -1 && 
        (m1JustCrossedUp || m3JustCrossedUp || m5JustCrossedUp) &&
        isEMAsReadyForEntry(true, TF0, 1, true) && 
        isEMAsReadyForEntry(true, TF1, 1, true)) {
        lastEMACrossingUp = currentBar;
        lastEMACrossingDown = -1;
        
        // Send proactive alert for potential setup
        CheckAndSendEMACrossAlert();
    }
    
    bool m1JustCrossedDown = !isEMAsReadyForEntry(false, TF0, 2, true) && isEMAsReadyForEntry(false, TF0, 1, true);
    bool m3JustCrossedDown = !isEMAsReadyForEntry(false, TF1, 2, true) && isEMAsReadyForEntry(false, TF1, 1, true);
    bool m5JustCrossedDown = !isEMAsReadyForEntry(false, TF2, 2, false) && isEMAsReadyForEntry(false, TF2, 1, false);

    if (lastEMACrossingDown == -1 && 
        (m1JustCrossedDown || m3JustCrossedDown || m5JustCrossedDown) &&
        isEMAsReadyForEntry(false, TF0, 1, true) && 
        isEMAsReadyForEntry(false, TF1, 1, true)) {
        lastEMACrossingDown = currentBar;
        lastEMACrossingUp = -1;
        
        // Send proactive alert for potential setup
        CheckAndSendEMACrossAlert();
    }
    
    // EMA200 touch trigger: When price touches EMA200 with all 4 EMAs aligned, set crossing flag
    // This provides additional E1 entry opportunities on pullbacks to EMA200 in strong trends
    double ema200 = GetEMA(TF0, EMA4, ENTRY_SHIFT);
    double barLow = iLow(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
    double barHigh = iHigh(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
    
    if (barLow <= ema200 && barHigh >= ema200) {
        // Price touched EMA200 - check if all 4 EMAs are strictly aligned
        if (lastEMACrossingUp == -1 && 
            isEMAsReadyForEntry(true, TF0, 1, true) &&
            isEMAsReadyForEntry(true, TF1, 1, true)) {
            // Bullish: All 4 EMAs aligned (25 > 75 > 100 > 200) + price touched EMA200
            lastEMACrossingUp = currentBar;
            lastEMACrossingDown = -1;
            if(showDebug) Print("[EMA200 Touch] Bullish trigger - all 4 EMAs aligned, price touched EMA200");
        }
        else if (lastEMACrossingDown == -1 &&
             isEMAsReadyForEntry(false, TF0, 1, true) &&
             isEMAsReadyForEntry(false, TF1, 1, true)) {
            // Bearish: All 4 EMAs aligned (25 < 75 < 100 < 200) + price touched EMA200
            lastEMACrossingDown = currentBar;
            lastEMACrossingUp = -1;
            if(showDebug) Print("[EMA200 Touch] Bearish trigger - all 4 EMAs aligned, price touched EMA200");
        }
    }
    
    double ema75 = GetEMA(TF0, EMA2, ENTRY_SHIFT);
    double barLow75 = iLow(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
    double barHigh75 = iHigh(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
    double barClose75 = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
    
    if (barLow75 <= ema75 && barHigh75 >= ema75) {
        // Price touched EMA75 - determine direction by close position relative to EMA75
        // (NOT by EMA alignment - alignment is checked at entry time in Entry2.mqh)
        if (barClose75 > ema75) {
            // Bullish touch: price closed above EMA75 after touching it
            int previousTouch = lastEma75TouchUp;
            lastEma75TouchUp = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
            lastEma75TouchDown = -1;
            
            // Send setup preparation alert only if this is a new touch (not same bar)
            if (previousTouch != lastEma75TouchUp) {
                SendEMA75TouchSetupAlert(true);
            }
        } else if (barClose75 < ema75) {
            // Bearish touch: price closed below EMA75 after touching it
            int previousTouch = lastEma75TouchDown;
            lastEma75TouchDown = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
            lastEma75TouchUp = -1;
            
            // Send setup preparation alert only if this is a new touch (not same bar)
            if (previousTouch != lastEma75TouchDown) {
                SendEMA75TouchSetupAlert(false);
            }
        }
    }
    
    // ===== E4: ICHIMOKU CLOUD CROSS DETECTION =====
    // E4 uses Ichimoku cloud color change as trigger instead of EMA crossing
    // Cloud green = SpanA > SpanB (bullish), Cloud red = SpanA < SpanB (bearish)
    // Requires BOTH M1 and M3 clouds to agree for confirmation
    if (ENABLE_E4_ENTRIES) {
        // Get current and previous Ichimoku cloud states from cache
        // Pine parity: Use CURRENT cloud (not future) for both M1 and M3
        bool m1CloudBullish_curr = (cache.ichimokuSpanA_M1_Current > cache.ichimokuSpanB_M1_Current);
        bool m3CloudBullish_curr = (cache.ichimokuSpanA_M3_Current > cache.ichimokuSpanB_M3_Current);
        
        // Get previous bar cloud states (both M1 and M3 use current cloud at previous bar)
        double tempBuffer[];
        ArrayResize(tempBuffer, 1);
        ArraySetAsSeries(tempBuffer, true);
        
        double spanA_M1_prev = 0, spanB_M1_prev = 0;
        double spanA_M3_prev = 0, spanB_M3_prev = 0;
        
        // M1 previous bar current cloud
        if (CopyBuffer(ichimokuHandles[0], 0, ENTRY_SHIFT + 1, 1, tempBuffer) > 0) spanA_M1_prev = tempBuffer[0];
        if (CopyBuffer(ichimokuHandles[0], 1, ENTRY_SHIFT + 1, 1, tempBuffer) > 0) spanB_M1_prev = tempBuffer[0];
        // M3 previous bar current cloud (Pine parity - NOT future cloud)
        if (CopyBuffer(ichimokuHandles[1], 0, ENTRY_SHIFT + 1, 1, tempBuffer) > 0) spanA_M3_prev = tempBuffer[0];
        if (CopyBuffer(ichimokuHandles[1], 1, ENTRY_SHIFT + 1, 1, tempBuffer) > 0) spanB_M3_prev = tempBuffer[0];
        
        bool m1CloudBullish_prev = (spanA_M1_prev > spanB_M1_prev);
        bool m3CloudBullish_prev = (spanA_M3_prev > spanB_M3_prev);
        
        // Both M1 and M3 must be bullish for bullish cross
        bool bothBullish_curr = m1CloudBullish_curr && m3CloudBullish_curr;
        bool bothBullish_prev = m1CloudBullish_prev && m3CloudBullish_prev;
        bool bothBearish_curr = !m1CloudBullish_curr && !m3CloudBullish_curr;
        bool bothBearish_prev = !m1CloudBullish_prev && !m3CloudBullish_prev;
        
        // Detect cloud cross (just turned green/red on both timeframes)
        bool ichiJustCrossedUp = bothBullish_curr && !bothBullish_prev;
        bool ichiJustCrossedDown = bothBearish_curr && !bothBearish_prev;
        
        // Set E4 trigger flags
        if (ichiJustCrossedUp && lastIchiCloudCrossUp == -1) {
            lastIchiCloudCrossUp = currentBar;
            lastIchiCloudCrossDown = -1;
            if(showDebug) Print("[E4] Ichimoku cloud crossed UP (M1+M3 green) at bar ", currentBar);
        }
        
        if (ichiJustCrossedDown && lastIchiCloudCrossDown == -1) {
            lastIchiCloudCrossDown = currentBar;
            lastIchiCloudCrossUp = -1;
            if(showDebug) Print("[E4] Ichimoku cloud crossed DOWN (M1+M3 red) at bar ", currentBar);
        }
    }

    // E1 ARM-STATE TRACE (parity): per-bar dump of the cross-arm DECISION inputs + resulting trigger ages,
    // so the C++ update_triggers can be diffed bar-for-bar vs this UpdateEmaTouches. Emits on any just-cross
    // OR while an E1 trigger is armed. Parse: ^KKE1ARM, -> ts,jcU(m1m3m5),jcD,rU(m1m3),rD(m1m3),armU,armD,e2U,e2D
    if (E1_ARM_TRACE) {
        bool jcUm1 = !isEMAsReadyForEntry(true, TF0, 2, true)  && isEMAsReadyForEntry(true, TF0, 1, true);
        bool jcUm3 = !isEMAsReadyForEntry(true, TF1, 2, true)  && isEMAsReadyForEntry(true, TF1, 1, true);
        bool jcUm5 = !isEMAsReadyForEntry(true, TF2, 2, false) && isEMAsReadyForEntry(true, TF2, 1, false);
        bool jcDm1 = !isEMAsReadyForEntry(false, TF0, 2, true)  && isEMAsReadyForEntry(false, TF0, 1, true);
        bool jcDm3 = !isEMAsReadyForEntry(false, TF1, 2, true)  && isEMAsReadyForEntry(false, TF1, 1, true);
        bool jcDm5 = !isEMAsReadyForEntry(false, TF2, 2, false) && isEMAsReadyForEntry(false, TF2, 1, false);
        int rUm1 = isEMAsReadyForEntry(true, TF0, 1, true)  ? 1 : 0;
        int rUm3 = isEMAsReadyForEntry(true, TF1, 1, true)  ? 1 : 0;
        int rDm1 = isEMAsReadyForEntry(false, TF0, 1, true) ? 1 : 0;
        int rDm3 = isEMAsReadyForEntry(false, TF1, 1, true) ? 1 : 0;
        int armU = (lastEMACrossingUp   == -1) ? -1 : (currentBar - lastEMACrossingUp);
        int armD = (lastEMACrossingDown == -1) ? -1 : (currentBar - lastEMACrossingDown);
        int e2U  = (lastEma75TouchUp    == -1) ? -1 : (currentBar - lastEma75TouchUp);
        int e2D  = (lastEma75TouchDown  == -1) ? -1 : (currentBar - lastEma75TouchDown);
        if (jcUm1||jcUm3||jcUm5||jcDm1||jcDm3||jcDm5 || armU>=0 || armD>=0) {
            string ts = TimeToString(iTime(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
            Print("KKE1ARM,", ts,
                  ",jcU=", (jcUm1?1:0), (jcUm3?1:0), (jcUm5?1:0),
                  ",jcD=", (jcDm1?1:0), (jcDm3?1:0), (jcDm5?1:0),
                  ",rU=", rUm1, rUm3, ",rD=", rDm1, rDm3,
                  ",armU=", armU, ",armD=", armD, ",e2U=", e2U, ",e2D=", e2D);
        }
    }
}

//+------------------------------------------------------------------+
//| EMA25 Leadership Check Across All Timeframes                     |
//+------------------------------------------------------------------+
bool isEMA25LeadingAllTimeFrames(bool isLong)
{
    if (isLong) {
        // For long: EMA25 should be above EMA75, EMA100, EMA200 on all timeframes
        bool leading1m = (GetEMA(TF0,EMA1,0) > GetEMA(TF0,EMA2,0) && GetEMA(TF0,EMA1,0) > GetEMA(TF0,EMA3,0) && GetEMA(TF0,EMA1,0) > GetEMA(TF0,EMA4,0));
        bool leading5m = (GetEMA(TF2,EMA1,0) > GetEMA(TF2,EMA2,0) && GetEMA(TF2,EMA1,0) > GetEMA(TF2,EMA3,0) && GetEMA(TF2,EMA1,0) > GetEMA(TF2,EMA4,0));
        bool leading15m = (GetEMA(TF3,EMA1,0) > GetEMA(TF3,EMA2,0) && GetEMA(TF3,EMA1,0) > GetEMA(TF3,EMA3,0) && GetEMA(TF3,EMA1,0) > GetEMA(TF3,EMA4,0));

        return (leading1m && leading5m && leading15m);
    } else {
        // For short: EMA25 should be below EMA75, EMA100, EMA200 on all timeframes
        bool leading1m = (GetEMA(TF0,EMA1,0) < GetEMA(TF0,EMA2,0) && GetEMA(TF0,EMA1,0) < GetEMA(TF0,EMA3,0) && GetEMA(TF0,EMA1,0) < GetEMA(TF0,EMA4,0));
        bool leading5m = (GetEMA(TF2,EMA1,0) < GetEMA(TF2,EMA2,0) && GetEMA(TF2,EMA1,0) < GetEMA(TF2,EMA3,0) && GetEMA(TF2,EMA1,0) < GetEMA(TF2,EMA4,0));
        bool leading15m = (GetEMA(TF3,EMA1,0) < GetEMA(TF3,EMA2,0) && GetEMA(TF3,EMA1,0) < GetEMA(TF3,EMA3,0) && GetEMA(TF3,EMA1,0) < GetEMA(TF3,EMA4,0));
        
        return (leading1m && leading5m && leading15m);
    }
}
