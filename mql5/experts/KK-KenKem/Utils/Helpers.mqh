//+------------------------------------------------------------------+
//|                                                      Helpers.mqh |
//|                  KenKem EA v1.7.51 - Utility Helper Functions   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// UTILITY HELPER FUNCTIONS
// Simple, reusable functions with no complex dependencies
//================================================================

// Debug printing helper
void PrintDebug(string msg) {
    if (showDebug) Print(msg);
}

// ===== Session detection moved to Utils/SessionManager.mqh =====
// - GetCurrentSession()

// Helper function to convert string type to enum (replaces StringFind checks)
ENTRY_TYPE GetEntryTypeEnum(string type) {
    if (type == "L-E1") return ENTRY_L_E1;
    if (type == "S-E1") return ENTRY_S_E1;
    if (type == "L-E2") return ENTRY_L_E2;
    if (type == "S-E2") return ENTRY_S_E2;
    if (type == "L-E3") return ENTRY_L_E3;
    if (type == "S-E3") return ENTRY_S_E3;
    if (type == "L-E4") return ENTRY_L_E4;
    if (type == "S-E4") return ENTRY_S_E4;
    if (type == "L-E5") return ENTRY_L_E5;
    if (type == "S-E5") return ENTRY_S_E5;
    return ENTRY_UNKNOWN;
}

// PERFORMANCE: Fast entry type checking helpers (replaces StringFind)
bool IsE1Entry(ENTRY_TYPE type) { return (type == ENTRY_L_E1 || type == ENTRY_S_E1); }
bool IsE2Entry(ENTRY_TYPE type) { return (type == ENTRY_L_E2 || type == ENTRY_S_E2); }
bool IsE3Entry(ENTRY_TYPE type) { return (type == ENTRY_L_E3 || type == ENTRY_S_E3); }

//+------------------------------------------------------------------+
//| Per-Entry-Type Trade Management Parameter Getters                |
//| Returns entry-specific values based on entry type                |
//+------------------------------------------------------------------+
double GetPartialTPTrigger(ENTRY_TYPE type) {
    if(IsE1Entry(type)) return E1_PARTIAL_TP_TRIGGER;
    if(IsE2Entry(type)) return E2_PARTIAL_TP_TRIGGER;
    if(IsE3Entry(type)) return E3_PARTIAL_TP_TRIGGER;
    if(IsE5Entry(type)) return E5_PARTIAL_TP_TRIGGER;
    return E2_PARTIAL_TP_TRIGGER; // Default to E2
}

double GetPartialTPRatio(ENTRY_TYPE type) {
    if(IsE1Entry(type)) return E1_PARTIAL_TP_RATIO;
    if(IsE2Entry(type)) return E2_PARTIAL_TP_RATIO;
    if(IsE3Entry(type)) return E3_PARTIAL_TP_RATIO;
    if(IsE5Entry(type)) return E5_PARTIAL_TP_RATIO;
    return E2_PARTIAL_TP_RATIO; // Default to E2
}

double GetSLToBreakevenBuffer(ENTRY_TYPE type) {
    if(IsE1Entry(type)) return E1_SL_TO_BREAKEVEN_BUFFER;
    if(IsE2Entry(type)) return E2_SL_TO_BREAKEVEN_BUFFER;
    if(IsE3Entry(type)) return E3_SL_TO_BREAKEVEN_BUFFER;
    if(IsE5Entry(type)) return E5_SL_TO_BREAKEVEN_BUFFER;
    return E2_SL_TO_BREAKEVEN_BUFFER; // Default to E2
}

double GetTrailingSLFactor(ENTRY_TYPE type) {
    if(IsE1Entry(type)) return E1_TRAILING_SL_FACTOR;
    if(IsE2Entry(type)) return E2_TRAILING_SL_FACTOR;
    if(IsE3Entry(type)) return E3_TRAILING_SL_FACTOR;
    if(IsE5Entry(type)) return E5_TRAILING_SL_FACTOR;
    return E2_TRAILING_SL_FACTOR; // Default to E2
}

double GetTPExtensionTriggerPips(ENTRY_TYPE type) {
    // Always use dynamic value (per-entry static values removed for simplicity)
    return dynamicTPExtensionTrigger;
}

int GetTPExtensionPips(ENTRY_TYPE type) {
    // Always use dynamic value (per-entry static values removed for simplicity)
    return (int)MathRound(dynamicTPExtensionPips);
}

int GetMaxTPExtensions(ENTRY_TYPE type) {
    if(IsE1Entry(type)) return E1_MAX_TP_EXTENSIONS;
    if(IsE2Entry(type)) return E2_MAX_TP_EXTENSIONS;
    if(IsE3Entry(type)) return E3_MAX_TP_EXTENSIONS;
    if(IsE5Entry(type)) return E5_MAX_TP_EXTENSIONS;
    return E2_MAX_TP_EXTENSIONS; // Default to E2
}

double GetEarlyCutSLRatio(ENTRY_TYPE type) {
    if(IsE1Entry(type)) return E1_EARLY_CUT_SL_RATIO;
    if(IsE2Entry(type)) return E2_EARLY_CUT_SL_RATIO;
    if(IsE3Entry(type)) return E3_EARLY_CUT_SL_RATIO;
    if(IsE4Entry(type)) return E4_EARLY_CUT_SL_RATIO;
    if(IsE5Entry(type)) return E5_EARLY_CUT_SL_RATIO;
    return E2_EARLY_CUT_SL_RATIO; // Default to E2
}

// Calculate maximum lot size based on risk management principles
double GetMaxLotSize(double _price,              // current market price
                   double balance,              // account balance (equity) in USD
                   int leverage,                // e.g. 500
                   double feePercent,           // trading fee as % of notional
                   int marginLevelPercent      // broker liquidation threshold (30 % for Exness)
                   ) {
    // Margin per 1 lot
    double marginPerLot = contractSize * _price / leverage;

    // Pip/point value per 1 lot (XAUUSD: 0.01 move × 100 oz  = 1 USD)
    double pointValue = contractSize * pipSize;

    // $ risk budget per trade
    double riskBudget = getMaxLossUSD();

    // Adjust risk budget for fees (fee paid at entry + exit)
    double feeFactor = feePercent / 100.0;
    double maxLotsBasedOnRiskPercentage = riskBudget / pointValue;

    // Margin-based cap using the liquidation level
    double maxUsedMargin = balance / (marginLevelPercent / 100.0);
    double maxLotsMargin = maxUsedMargin / marginPerLot;

    // Safest lot size is the lesser of the two
    double maxLots = MathMin(maxLotsBasedOnRiskPercentage, maxLotsMargin);

    // Round down to broker lot step (auto-detected per broker)
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    if (lotStep <= 0) lotStep = minimumLotSize;
    return MathFloor(maxLots / lotStep) * lotStep;
}


// Function to generate unique trade ID using GMT timestamp with milliseconds
string GenerateTradeID(string entryType)
{
    // Get GMT time with milliseconds for uniqueness
    datetime gmtTime = TimeGMT();
    MqlDateTime dt;
    TimeToStruct(gmtTime, dt);
    
    // Get milliseconds from GetTickCount() for uniqueness within same second
    ulong tickCount = GetTickCount();
    int milliseconds = (int)(tickCount % 1000);
    
    // Format as yyyymmddhhmmss (14 digits) + milliseconds (3 digits)
    string yearStr = IntegerToString(dt.year);
    string monthStr = (dt.mon < 10) ? "0" + IntegerToString(dt.mon) : IntegerToString(dt.mon);
    string dayStr = (dt.day < 10) ? "0" + IntegerToString(dt.day) : IntegerToString(dt.day);
    string hourStr = (dt.hour < 10) ? "0" + IntegerToString(dt.hour) : IntegerToString(dt.hour);
    string minuteStr = (dt.min < 10) ? "0" + IntegerToString(dt.min) : IntegerToString(dt.min);
    string secondStr = (dt.sec < 10) ? "0" + IntegerToString(dt.sec) : IntegerToString(dt.sec);
    string msStr = StringFormat("%03d", milliseconds);
    
    string timestamp = yearStr + monthStr + dayStr + hourStr + minuteStr + secondStr + msStr;
    return entryType + " #" + timestamp;
}

// Function to get magic number for a specific trade (uses exact timestamp with milliseconds)
long GetTradeMagic(const string tradeID) {
    // Extract timestamp from tradeID (everything after " #")
    int hashPos = StringFind(tradeID, " #");
    if (hashPos >= 0 && StringLen(tradeID) > hashPos + 2) {
        string timestampStr = StringSubstr(tradeID, hashPos + 2);
        long magic = StringToInteger(timestampStr);
        
        // Validate magic number is reasonable (17 digits: yyyymmddhhmmssmmm)
        // Should be between 20250101000000000 and 20991231235959999
        if (magic >= 20250101000000000 && magic <= 20991231235959999) {
            return magic;
        }
        
        if (showDebug) {
            Print("WARNING: Invalid magic number extracted: ", magic, " from ID: ", tradeID);
            Print("  hashPos: ", hashPos, " timestampStr: '", timestampStr, "'");
        }
    }
    
    // Fallback: Generate magic from current time with milliseconds
    datetime gmtTime = TimeGMT();
    MqlDateTime dt;
    TimeToStruct(gmtTime, dt);
    ulong tickCount = GetTickCount();
    int milliseconds = (int)(tickCount % 1000);
    
    // SAFE CALCULATION: Use explicit long literals to prevent overflow
    // Max value: 20991231235959999 (17 digits) fits safely in long (19 digits max)
    long fallbackMagic = ((long)dt.year * 10000000000000LL) + 
                         ((long)dt.mon * 100000000000LL) + 
                         ((long)dt.day * 1000000000LL) + 
                         ((long)dt.hour * 10000000LL) + 
                         ((long)dt.min * 100000LL) + 
                         ((long)dt.sec * 1000LL) + 
                         (long)milliseconds;
    
    return fallbackMagic;
}


// Calculate market volatility multiplier for SL/TP adjustments
double GetVolatilityMultiplier() {
    // Calculate ATR-based volatility over last 14 bars
    double atr1m = 0;
    for(int i = 1; i <= 14; i++) {
        double high = iHigh(_Symbol, TF_ARRAY[TF0], i);
        double low = iLow(_Symbol, TF_ARRAY[TF0], i);
        double prevClose = iClose(_Symbol, TF_ARRAY[TF0], i + 1);
        
        double tr = MathMax(high - low, MathMax(MathAbs(high - prevClose), MathAbs(low - prevClose)));
        atr1m += tr;
    }
    atr1m /= 14.0;
    
    // Calculate current bar's range
    double currentRange = iHigh(_Symbol, TF_ARRAY[TF0], 0) - iLow(_Symbol, TF_ARRAY[TF0], 0);
    
    // Volatility multiplier: higher volatility = wider SL/TP
    double volatilityRatio = currentRange / atr1m;
    
    // Cap the multiplier between 0.7 and 1.5
    return MathMax(0.7, MathMin(1.5, volatilityRatio));
}