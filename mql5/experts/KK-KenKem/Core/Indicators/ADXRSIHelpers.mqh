//+------------------------------------------------------------------+
//|                                            ADXRSIHelpers.mqh    |
//|              KenKem EA v1.7.51 - ADX & RSI Helper Functions     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// ADX & RSI INDICATOR HELPER FUNCTIONS
// ADX, DI+, DI-, RSI retrieval and analysis
//================================================================

// TimeFrame: Uses TF_ARRAY[] for configurable timeframes
double getADXValue(ENUM_TIMEFRAMES timeFrame, int shift = 0) {
    // Convert timeframe to array index using TF_ARRAY
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else {
        Print("Error: Unsupported timeframe ", timeFrame, " in getADXValue");
        return -1;
    }

    double adxBuffer[];
    ArraySetAsSeries(adxBuffer, true);
    if (CopyBuffer(adxHandles[arrayIndex], 0, shift, 1, adxBuffer) <= 0) {
        Print("Error getting ADX data for timeframe ", timeFrame, "!!");
        return -1;
    }
    return adxBuffer[0];
}

// Get +DI (Directional Index Plus) value for a timeframe
double getDIPlus(ENUM_TIMEFRAMES timeFrame, int shift = 0) {
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else {
        Print("Error: Unsupported timeframe ", timeFrame, " in getDIPlus");
        return -1;
    }
    double diPlusBuffer[];
    ArraySetAsSeries(diPlusBuffer, true);
    if (CopyBuffer(adxHandles[arrayIndex], 1, shift, 1, diPlusBuffer) <= 0) {
        Print("Error getting +DI data for timeframe ", timeFrame, "!!");
        return -1;
    }
    return diPlusBuffer[0];
}

// Get -DI (Directional Index Minus) value for a timeframe
double getDIMinus(ENUM_TIMEFRAMES timeFrame, int shift = 0) {
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else {
        Print("Error: Unsupported timeframe ", timeFrame, " in getDIMinus");
        return -1;
    }
    double diMinusBuffer[];
    ArraySetAsSeries(diMinusBuffer, true);
    if (CopyBuffer(adxHandles[arrayIndex], 2, shift, 1, diMinusBuffer) <= 0) {
        Print("Error getting -DI data for timeframe ", timeFrame, "!!");
        return -1;
    }
    return diMinusBuffer[0];
}

bool IsADXTrending(ENUM_TIMEFRAMES timeFrame, TREND_STATE trendState) {
    // Convert timeframe to array index using TF_ARRAY
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else {
        Print("Error: Unsupported timeframe ", timeFrame, " in IsADXTrending");
        return false;
    }

    double adxBuffer[];
    ArraySetAsSeries(adxBuffer, true);
    if (CopyBuffer(adxHandles[arrayIndex], 0, 0, 3, adxBuffer) <= 0) {
        Print("Error getting ADX data for timeframe ", timeFrame, " in trend check!!");
        return false;
    }

    bool isTrending;
    if (trendState == TREND_BULL) {
        isTrending = (adxBuffer[0] > adxBuffer[1]) && (adxBuffer[1] > adxBuffer[2]);
    } else {
        isTrending = (adxBuffer[0] < adxBuffer[1]) && (adxBuffer[1] < adxBuffer[2]);
    }
    return isTrending;
}

// Helper functions for specific timeframes
bool IsADXTrendingM1(TREND_STATE trendState) {
    return IsADXTrending(TF_ARRAY[TF0], trendState);
}

bool IsADXTrendingM3(TREND_STATE trendState) {
    return IsADXTrending(TF_ARRAY[TF1], trendState);
}

bool IsADXTrendingM5(TREND_STATE trendState) {
    return IsADXTrending(TF_ARRAY[TF2], trendState);
}

// Map timeframe enum to array index
int MapTimeframeToIndex(ENUM_TIMEFRAMES timeFrame) {
    if (timeFrame == TF_ARRAY[TF0])       return TF0;
    else if (timeFrame == TF_ARRAY[TF1])   return TF1;
    else if (timeFrame == TF_ARRAY[TF2])   return TF2;
    else if (timeFrame == TF_ARRAY[TF3])   return TF3;
    else return -1;
}

// Flexible RSI value retrieval for any timeframe and entry shift (cached handle)
double GetRSIValue(ENUM_TIMEFRAMES timeFrame, int period, int entryShift) {
    int tfIndex = MapTimeframeToIndex(timeFrame);
    if (tfIndex < 0) {
        PrintDebug("Invalid timeframe in GetRSIValue");
        return -1.0;
    }

    // Ensure cached handle exists and matches requested period
    if (rsiHandlesTF[tfIndex] == INVALID_HANDLE || rsiHandlePeriodTF[tfIndex] != period) {
        if (rsiHandlesTF[tfIndex] != INVALID_HANDLE) {
            IndicatorRelease(rsiHandlesTF[tfIndex]);
        }
        rsiHandlesTF[tfIndex] = iRSI(_Symbol, timeFrame, period, PRICE_CLOSE);
        rsiHandlePeriodTF[tfIndex] = period;
        if (rsiHandlesTF[tfIndex] == INVALID_HANDLE) {
            PrintDebug("Failed to create RSI handle for timeframe " + IntegerToString(timeFrame) + ", period " + IntegerToString(period));
            return -1.0;
        }
    }

    double buffer[];
    ArraySetAsSeries(buffer, true);
    if (CopyBuffer(rsiHandlesTF[tfIndex], 0, entryShift, 1, buffer) <= 0) {
        PrintDebug("Failed to copy RSI buffer for timeframe " + IntegerToString(timeFrame) + ", period " + IntegerToString(period));
        return -1.0;
    }
    return buffer[0];
}

// Flexible ADX/DI+/DI- values retrieval for any timeframe and entry shift
struct ADXValues {
    double adx;
    double diPlus;
    double diMinus;
    bool valid;
};

ADXValues GetADXValues(ENUM_TIMEFRAMES timeFrame, int entryShift) {
    ADXValues result;
    result.valid = false;

    // Convert timeframe to array index using TF_ARRAY
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else {
        PrintDebug("Error: Unsupported timeframe " + IntegerToString(timeFrame) + " in GetADXValues");
        return result;
    }

    // Use existing pre-initialized ADX handles
    double adxBuffer[], diPlusBuffer[], diMinusBuffer[];
    ArraySetAsSeries(adxBuffer, true);
    ArraySetAsSeries(diPlusBuffer, true);
    ArraySetAsSeries(diMinusBuffer, true);

    if (CopyBuffer(adxHandles[arrayIndex], 0, entryShift, 1, adxBuffer) <= 0 ||
        CopyBuffer(adxHandles[arrayIndex], 1, entryShift, 1, diPlusBuffer) <= 0 ||
        CopyBuffer(adxHandles[arrayIndex], 2, entryShift, 1, diMinusBuffer) <= 0) {
        PrintDebug("Failed to copy ADX buffers for timeframe " + IntegerToString(timeFrame) + " with entry shift " + IntegerToString(entryShift));
        return result;
    }

    result.adx = adxBuffer[0];
    result.diPlus = diPlusBuffer[0];
    result.diMinus = diMinusBuffer[0];
    result.valid = true;

    return result;
}

// RSI confluence validation function
bool HasRSIConfluence(TREND_STATE trendState, ENUM_TIMEFRAMES timeFrame, int rsiPeriod1, int rsiPeriod2, int rsiPeriod3, double threshold, int entryShift) {
    double rsi1 = GetRSIValue(timeFrame, rsiPeriod1, entryShift);
    double rsi2 = GetRSIValue(timeFrame, rsiPeriod2, entryShift);
    double rsi3 = GetRSIValue(timeFrame, rsiPeriod3, entryShift);

    if (rsi1 < 0 || rsi2 < 0 || rsi3 < 0) {
        return false; // Invalid RSI values
    }

    if (trendState == TREND_BULL) {
        // Bullish: RSI1 > RSI2 > RSI3 and RSI2 > threshold
        return (rsi1 > rsi2 && rsi2 > rsi3 && rsi2 > threshold);
    } else if (trendState == TREND_BEAR) {
        // Bearish: RSI1 < RSI2 < RSI3 and RSI2 < threshold
        return (rsi1 < rsi2 && rsi2 < rsi3 && rsi2 < threshold);
    }

    return false;
}

// Helper function: Get ADX average over lastBars
double GetADXAverage(ENUM_TIMEFRAMES timeFrame, int lastBars) {
    // Map timeframe to adxHandles array index
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else {
        PrintDebug("Invalid timeframe in GetADXAverage");
        return 0.0;
    }
    if (lastBars <= 0) return 0.0;
    double buf[];
    ArraySetAsSeries(buf, true);
    int copied = CopyBuffer(adxHandles[arrayIndex], 0, 0, lastBars, buf);
    if (copied <= 0) return 0.0;
    double sum = 0.0; int valid = 0;
    for (int i = 0; i < copied; i++) {
        double v = buf[i];
        if (v > 0) { sum += v; valid++; }
    }
    return valid > 0 ? sum / valid : 0.0;
}

// Helper function: Get RSI average over lastBars
double GetRSIAverage(ENUM_TIMEFRAMES timeFrame, int period, int lastBars) {
    int tfIndex = MapTimeframeToIndex(timeFrame);
    if (tfIndex < 0 || lastBars <= 0) return 0.0;
    // Ensure cached handle exists for requested period
    if (rsiHandlesTF[tfIndex] == INVALID_HANDLE || rsiHandlePeriodTF[tfIndex] != period) {
        if (rsiHandlesTF[tfIndex] != INVALID_HANDLE) {
            IndicatorRelease(rsiHandlesTF[tfIndex]);
        }
        rsiHandlesTF[tfIndex] = iRSI(_Symbol, timeFrame, period, PRICE_CLOSE);
        rsiHandlePeriodTF[tfIndex] = period;
        if (rsiHandlesTF[tfIndex] == INVALID_HANDLE) {
            PrintDebug("Failed to create RSI handle for timeframe " + IntegerToString(timeFrame) + ", period " + IntegerToString(period));
            return 0.0;
        }
    }
    double buf[];
    ArraySetAsSeries(buf, true);
    int copied = CopyBuffer(rsiHandlesTF[tfIndex], 0, 0, lastBars, buf);
    if (copied <= 0) return 0.0;
    double sum = 0.0; int valid = 0;
    for (int i = 0; i < copied; i++) {
        double v = buf[i];
        if (v > 0) { sum += v; valid++; }
    }
    return valid > 0 ? sum / valid : 0.0;
}


// Enhanced trend acceleration detection using DI spread dynamics
// Detects when directional momentum is not just present, but accelerating
// This is superior to IsADXTrending() which incorrectly assumes ADX direction = trend direction
// Supports both ADX(14) for standard detection and ADX(9) for faster panic exit
bool HasTrendAcceleration(ENUM_TIMEFRAMES timeFrame, TREND_STATE trendState, int lookbackBars = 3, int adxPeriod = 14) {
    // Select appropriate handle based on ADX period
    int handle;
    if (adxPeriod == 9) {
        handle = adxShortHandle;
    } else {
        // ADX(14) - use timeframe-specific handle from array
        int arrayIndex;
        if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
        else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
        else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
        else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
        else {
            Print("Error: Unsupported timeframe ", timeFrame, " in HasTrendAcceleration");
            return false;
        }
        handle = adxHandles[arrayIndex];
    }

    double adxBuffer[], diPlusBuffer[], diMinusBuffer[];
    ArraySetAsSeries(adxBuffer, true);
    ArraySetAsSeries(diPlusBuffer, true);
    ArraySetAsSeries(diMinusBuffer, true);

    int copied = CopyBuffer(handle, 0, 0, lookbackBars, adxBuffer);
    if (copied <= 0 ||
        CopyBuffer(handle, 1, 0, lookbackBars, diPlusBuffer) != copied ||
        CopyBuffer(handle, 2, 0, lookbackBars, diMinusBuffer) != copied) {
        return false;
    }

    // Use actual copied size to prevent array out of range
    int actualBars = MathMin(copied, lookbackBars);

    // Calculate DI spread for each bar (positive = correct direction, negative = wrong direction)
    double spread[];
    ArrayResize(spread, actualBars);
    for (int i = 0; i < actualBars; i++) {
        spread[i] = (trendState == TREND_BULL) ?
                    (diPlusBuffer[i] - diMinusBuffer[i]) :
                    (diMinusBuffer[i] - diPlusBuffer[i]);
    }

    // Need at least 3 bars for comparison
    if (actualBars < 3) {
        return false;
    }

    // Three conditions for trend acceleration:
    // 1. ADX rising (trend strength increasing)
    bool adxRising = (adxBuffer[0] > adxBuffer[1]) && (adxBuffer[1] > adxBuffer[2]);

    // 2. DI spread widening (directional momentum accelerating)
    bool spreadAccelerating = (spread[0] > spread[1]) && (spread[1] > spread[2]);

    // 3. Current spread positive and meaningful (>0.5 to filter noise)
    bool spreadPositive = (spread[0] > 0.5);

    return adxRising && spreadAccelerating && spreadPositive;
}

// Helper function: Get current RSI value for any period (optimized for CSV export)
double GetRSICurrent(ENUM_TIMEFRAMES timeFrame, int period) {
    int handle = iRSI(_Symbol, timeFrame, period, PRICE_CLOSE);
    if (handle == INVALID_HANDLE) return 0.0;
    double buf[1];
    int result = CopyBuffer(handle, 0, 0, 1, buf);
    IndicatorRelease(handle);
    if (result <= 0) return 0.0;
    return buf[0];
}
// Detect DI spread deceleration (reversal signal)
// For bullish reversal: DI+ increasing, DI- decreasing
// Mainly used for E3 for now
bool HasDISpreadDeceleration(ENUM_TIMEFRAMES timeFrame, TREND_STATE reversalDirection, int lookbackBars = 3) {
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else return false;

    double diPlusBuffer[], diMinusBuffer[];
    ArraySetAsSeries(diPlusBuffer, true);
    ArraySetAsSeries(diMinusBuffer, true);

    int copiedPlus = CopyBuffer(adxHandles[arrayIndex], 1, 0, lookbackBars, diPlusBuffer);
    int copiedMinus = CopyBuffer(adxHandles[arrayIndex], 2, 0, lookbackBars, diMinusBuffer);

    // Validate we have enough data for the requested lookback
    if (copiedPlus < lookbackBars || copiedMinus < lookbackBars) {
        return false;
    }

    // Additional safety: ensure array size matches what we need
    if (ArraySize(diPlusBuffer) < lookbackBars || ArraySize(diMinusBuffer) < lookbackBars) {
        return false;
    }

    if (reversalDirection == TREND_BULL) {
        // Bullish reversal: DI+ rising, DI- falling

        // 1. Current bar MUST show reversal (recent momentum)
        if (!(diPlusBuffer[0] > diPlusBuffer[1] && diMinusBuffer[0] < diMinusBuffer[1])) {
            return false;
        }

        // 2. Overall trend: DI spread must increase from furthest to current
        double spreadCurrent = diPlusBuffer[0] - diMinusBuffer[0];
        double spreadFurthest = diPlusBuffer[lookbackBars-1] - diMinusBuffer[lookbackBars-1];
        if (spreadCurrent <= spreadFurthest) {
            return false;  // No overall reversal trend
        }

        // 3. Majority check: at least 50% of bars show reversal
        int reversalCount = 0;
        for (int i = 0; i < lookbackBars - 1; i++) {
            if (i + 1 >= ArraySize(diPlusBuffer) || i + 1 >= ArraySize(diMinusBuffer)) {
                return false;
            }
            if (diPlusBuffer[i] > diPlusBuffer[i+1] && diMinusBuffer[i] < diMinusBuffer[i+1]) {
                reversalCount++;
            }
        }

        int minRequired = (lookbackBars - 1) / 2;  // 50% threshold (same as v1.7.66)
        return reversalCount > minRequired;

    } else {
        // Bearish reversal: DI- rising, DI+ falling

        // 1. Current bar MUST show reversal (recent momentum)
        if (!(diMinusBuffer[0] > diMinusBuffer[1] && diPlusBuffer[0] < diPlusBuffer[1])) {
            return false;
        }

        // 2. Overall trend: DI spread must increase from furthest to current
        double spreadCurrent = diMinusBuffer[0] - diPlusBuffer[0];
        double spreadFurthest = diMinusBuffer[lookbackBars-1] - diPlusBuffer[lookbackBars-1];
        if (spreadCurrent <= spreadFurthest) {
            return false;  // No overall reversal trend
        }

        // 3. Majority check: at least 50% of bars show reversal
        int reversalCount = 0;
        for (int i = 0; i < lookbackBars - 1; i++) {
            if (i + 1 >= ArraySize(diMinusBuffer) || i + 1 >= ArraySize(diPlusBuffer)) {
                return false;
            }
            if (diMinusBuffer[i] > diMinusBuffer[i+1] && diPlusBuffer[i] < diPlusBuffer[i+1]) {
                reversalCount++;
            }
        }

        int minRequired = (lookbackBars - 1) / 2;  // 50% threshold (same as v1.7.66)
        return reversalCount > minRequired;
    }
}


// Helper function: Get current ADX value (optimized for CSV export)
double GetADXCurrent(ENUM_TIMEFRAMES timeFrame) {
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else return 0.0;
    double buf[1];
    if (CopyBuffer(adxHandles[arrayIndex], 0, 0, 1, buf) <= 0) return 0.0;
    return buf[0];
}

// Helper function: Get current DI+ value
double GetDIPlusCurrent(ENUM_TIMEFRAMES timeFrame) {
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else return 0.0;
    double buf[1];
    if (CopyBuffer(adxHandles[arrayIndex], 1, 0, 1, buf) <= 0) return 0.0;
    return buf[0];
}

// Helper function: Get current DI- value
double GetDIMinusCurrent(ENUM_TIMEFRAMES timeFrame) {
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else return 0.0;
    double buf[1];
    if (CopyBuffer(adxHandles[arrayIndex], 2, 0, 1, buf) <= 0) return 0.0;
    return buf[0];
}

// Unified ADX helper: Get ADX value for any period (14 or 9)
// Uses appropriate handle based on period parameter
double getADXValueByPeriod(ENUM_TIMEFRAMES timeFrame, int period, int shift = 0) {
    int handle = (period == 9) ? adxShortHandle : adxHandles[0];  // Default to TF0 for period 14

    // For period 14, use timeframe-specific handle
    if (period == 14) {
        int arrayIndex;
        if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
        else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
        else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
        else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
        else return 0.0;
        handle = adxHandles[arrayIndex];
    }

    double buf[1];
    if (CopyBuffer(handle, 0, shift, 1, buf) <= 0) return 0.0;
    return buf[0];
}

// Unified DI+ helper: Get DI+ value for any period (14 or 9)
double getDIPlusByPeriod(ENUM_TIMEFRAMES timeFrame, int period, int shift = 0) {
    int handle = (period == 9) ? adxShortHandle : adxHandles[0];

    if (period == 14) {
        int arrayIndex;
        if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
        else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
        else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
        else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
        else return 0.0;
        handle = adxHandles[arrayIndex];
    }

    double buf[1];
    if (CopyBuffer(handle, 1, shift, 1, buf) <= 0) return 0.0;
    return buf[0];
}

// Unified DI- helper: Get DI- value for any period (14 or 9)
double getDIMinusByPeriod(ENUM_TIMEFRAMES timeFrame, int period, int shift = 0) {
    int handle = (period == 9) ? adxShortHandle : adxHandles[0];

    if (period == 14) {
        int arrayIndex;
        if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
        else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
        else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
        else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
        else return 0.0;
        handle = adxHandles[arrayIndex];
    }

    double buf[1];
    if (CopyBuffer(handle, 2, shift, 1, buf) <= 0) return 0.0;
    return buf[0];
}

// Backward compatibility wrappers (keep existing code working)
double getADXShortValue(int shift) {
    return getADXValueByPeriod(TF_ARRAY[TF0], 9, shift);
}

double getDIPlusShort(int shift) {
    return getDIPlusByPeriod(TF_ARRAY[TF0], 9, shift);
}

double getDIMinusShort(int shift) {
    return getDIMinusByPeriod(TF_ARRAY[TF0], 9, shift);
}

//| Helper: Check if values show consistent acceleration pattern     |
//| Uses 3-layer validation: current bar + overall trend + majority  |
//+------------------------------------------------------------------+
bool IsAccelerating(double &buffer[], int lookback) {
    if (lookback < 2 || ArraySize(buffer) < lookback) return false;

    // 1. Current bar must be rising
    if (buffer[0] <= buffer[1]) return false;

    // 2. Overall trend: current must be higher than furthest
    if (buffer[0] <= buffer[lookback-1]) return false;

    // 3. Majority check: 50%+ bars show rising pattern
    int risingCount = 0;
    for (int i = 0; i < lookback - 1; i++) {
        if (buffer[i] > buffer[i+1]) risingCount++;
    }
    return risingCount > (lookback - 1) / 2;
}


// 5. ADX confluence validation function
bool HasADXConfluence(TREND_STATE trendState, ENUM_TIMEFRAMES timeFrame, int lookbackBars, double adxThreshold, int entryShift) {
    if (lookbackBars < 2) lookbackBars = 2; // Minimum 2 bars needed

    // Convert timeframe to array index using TF_ARRAY
    int arrayIndex;
    if (timeFrame == TF_ARRAY[TF0])       arrayIndex = TF0;
    else if (timeFrame == TF_ARRAY[TF1])   arrayIndex = TF1;
    else if (timeFrame == TF_ARRAY[TF2])   arrayIndex = TF2;
    else if (timeFrame == TF_ARRAY[TF3])   arrayIndex = TF3;
    else {
        PrintDebug("Error: Unsupported timeframe " + IntegerToString(timeFrame) + " in HasADXConfluence");
        return false;
    }

    // Use existing pre-initialized ADX handles
    double adxBuffer[], diPlusBuffer[], diMinusBuffer[];
    ArraySetAsSeries(adxBuffer, true);
    ArraySetAsSeries(diPlusBuffer, true);
    ArraySetAsSeries(diMinusBuffer, true);

    if (CopyBuffer(adxHandles[arrayIndex], 0, entryShift, lookbackBars, adxBuffer) <= 0 ||
        CopyBuffer(adxHandles[arrayIndex], 1, entryShift, lookbackBars, diPlusBuffer) <= 0 ||
        CopyBuffer(adxHandles[arrayIndex], 2, entryShift, lookbackBars, diMinusBuffer) <= 0) {
        PrintDebug("Failed to copy ADX buffers for confluence check on timeframe " + IntegerToString(timeFrame));
        return false;
    }

    bool adxRising = true;
    bool diTrending = true;

    // Check ADX is rising over lookback period
    for (int i = 0; i < lookbackBars - 1; i++) {
        if (adxBuffer[i] <= adxBuffer[i+1]) {
            adxRising = false;
            break;
        }
    }

    // Check if current ADX is above threshold
    bool adxAboveThreshold = (adxBuffer[0] > adxThreshold);

    if (trendState == TREND_BULL) {
        // For bullish: DI+ should be rising and DI+ > DI-
        for (int i = 0; i < lookbackBars - 1; i++) {
            if (diPlusBuffer[i] <= diPlusBuffer[i+1] || diPlusBuffer[i] <= diMinusBuffer[i]) {
                diTrending = false;
                break;
            }
        }
    } else if (trendState == TREND_BEAR) {
        // For bearish: DI- should be rising and DI- > DI+
        for (int i = 0; i < lookbackBars - 1; i++) {
            if (diMinusBuffer[i] <= diMinusBuffer[i+1] || diMinusBuffer[i] <= diPlusBuffer[i]) {
                diTrending = false;
                break;
            }
        }
    }

    return adxRising && adxAboveThreshold && diTrending;
}
