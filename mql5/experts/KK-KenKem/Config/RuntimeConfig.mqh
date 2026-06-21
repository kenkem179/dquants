//+------------------------------------------------------------------+
//|                                               RuntimeConfig.mqh |
//|                    KenKem EA v1.7.51 - Runtime Configuration    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// RUNTIME CONFIGURATION STRUCT - Centralized configuration that adapts at runtime
// NOTE: 
// - This is meant to handle super fast scalping on 30 second chart, but NOT ALL of Ken's ideas have been implemented!
// - We will come back to make this config really flexible to deal with any strategies with any entry timeframes (not only M1)
//================================================================

struct RuntimeConfig {
    // Entry settings (prepares for S30/M1 switching)
    bool useS30;  // false for now (M1 only), true when S30 implemented
    int emaFast, emaMid, emaSlow, emaLong;
    int rsiPeriod, adxPeriod;
    
    // Confirmation timeframe for conviction scoring (adaptive based on entry TF)
    ENUM_TIMEFRAMES confirmationTF;  // M5 for M1 entries, M3 for S30 entries
    int confirmationTFIndex;   // Array index for buffer access (TF2=M5 or TF1=M3)
    
    // Asymmetric RR per direction (long vs short)
    double rrLongE1, rrShortE1;
    double rrLongE2, rrShortE2;
    double rrLongE3, rrShortE3;
    double rrLongE4, rrShortE4;
    double rrLongE5, rrShortE5;
    
    // Session type (0=Asia, 1=London, 2=US)
    int sessionType;
} CFG;

void InitializeConfig() {
    // Start with M1 configuration (S30 support added later in Phase 4)
    CFG.useS30 = false;
    CFG.emaFast = 25;
    CFG.emaMid = 75;
    CFG.emaSlow = 100;
    CFG.emaLong = 200;
    CFG.rsiPeriod = 14;
    CFG.adxPeriod = 14;
    
    // Set confirmation timeframe adaptively (3x-5x ratio from entry TF)
    if (CFG.useS30) {
        CFG.confirmationTF = TF_ARRAY[TF1];  // S30 → M3 (6x ratio)
        CFG.confirmationTFIndex = TF1;
    } else {
        CFG.confirmationTF = TF_ARRAY[TF2];  // M1 → M5 (5x ratio)
        CFG.confirmationTFIndex = TF2;
    }
    
    // Asymmetric RR: XAUUSD shorts are harder, need tighter targets
    CFG.rrLongE1 = E1_RR;  // 1.6 (from input)
    CFG.rrShortE1 = E1_RR * 0.875;  // 1.4 (12.5% lower for shorts)
    
    CFG.rrLongE2 = E2_RR;  // 1.5 (from input)
    CFG.rrShortE2 = E2_RR * 0.867;  // 1.3 (13.3% lower)
    
    CFG.rrLongE3 = E3_RR;  // 1.8 (from input)
    CFG.rrShortE3 = E3_RR * 0.778;  // 1.4 (22.2% lower)
    
    CFG.rrLongE4 = E4_RR;  // 2.4 (from input)
    CFG.rrShortE4 = E4_RR_SHORT * 0.875;  // 12.5% lower for shorts

    CFG.rrLongE5 = E5_RR;  // 1.5 (from input, matches Pine SuperBros)
    CFG.rrShortE5 = E5_RR;  // Same as long (Pine SuperBros parity)
    
    // Session detection (0=Asia 9-15, 1=London 15-22, 2=US 22-6)
    CFG.sessionType = 1;  // Default London (most active)
    
    if(showDebug) {
        Print("[CONFIG INITIALIZED] S30=", CFG.useS30, " EMAs=[", CFG.emaFast, ",", CFG.emaMid, ",", CFG.emaSlow, ",", CFG.emaLong, "]");
        Print("[CONFIG] RR Long E1=", CFG.rrLongE1, " Short E1=", CFG.rrShortE1);
        Print("[CONFIG] RR Long E2=", CFG.rrLongE2, " Short E2=", CFG.rrShortE2);
    }
}
