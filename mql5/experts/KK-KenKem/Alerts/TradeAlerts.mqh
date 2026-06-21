//+------------------------------------------------------------------+
//|                                               TradeAlerts.mqh    |
//|              KenKem EA v1.7.51 - Trade Alert Functions           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// TRADE ALERT FUNCTIONS
// Proactive setup alerts and trade lifecycle notifications
//================================================================

//+------------------------------------------------------------------+
//| Helper: Get Market Status Text                                   |
//+------------------------------------------------------------------+
string GetMarketStatusText() {
    // Leverage existing functions (no new calculations)
    if (IsInExtremeSidewayRange()) return "Extreme Sideway";
    
    // Use cached supertrend (already calculated in UpdateIndicatorCache)
    TREND_STATE trend = CalculateSuperTrendForEntry("E1");
    if (trend == TREND_BULL) return "Bullish";
    if (trend == TREND_BEAR) return "Bearish";
    return "Sideway";  // Fallback
}

//+------------------------------------------------------------------+
//| Helper: Get Momentum Status Text                                 |
//+------------------------------------------------------------------+
string GetMomentumStatusText() {
    // Use cached momentum (already calculated in UpdateIndicatorCache)
    if (cache.hasSufficientBullMomentum || cache.hasSufficientBearMomentum) {
        // Check if "strong" using existing HasStrongMomentum()
        if (HasStrongMomentum(TREND_BULL, PERIOD_M1, 5, ENTRY_SHIFT) || 
            HasStrongMomentum(TREND_BEAR, PERIOD_M1, 5, ENTRY_SHIFT)) {
            return "Strong";
        }
        return "Sufficient";
    }
    return "Insufficient";
}

//+------------------------------------------------------------------+
//| Helper: Get EA Block Reason Text                                 |
//+------------------------------------------------------------------+
string GetEABlockReasonText() {
    datetime currentTime = TimeCurrent();
    
    // Check news block
    if (IsNearImportantNews()) {
        return "Blocked by High Impact News";
    }
    
    // Check losing streak
    if (IsBlockedByLosingStreak()) {
        int remainingMin = (int)((losingStreakBlockUntil - currentTime) / 60);
        return "Consecutive losses (" + IntegerToString(consecutiveLosses) +
               " losses, waiting for " + IntegerToString(remainingMin) + " minutes)";
    }
    
    // Check drawdown
    if (IsDrawdownBlocked()) {
        int remainingMin = (int)((drawdownBlockedUntil - currentTime) / 60);
        return "Max drawdown cooldown (Remaining: " + IntegerToString(remainingMin) + " minutes)";
    }
    
    // Check session
    if (!IsNowInValidSession() && !IGNORE_VALID_SESSIONS) {
        return "Outside trading session";
    }
    
    return "Actively looking for entries";
}

//+------------------------------------------------------------------+
//| Proactive Alert: EMA Cross Detection                             |
//+------------------------------------------------------------------+
void CheckAndSendEMACrossAlert() {
    if (!ENABLE_EMA_TOUCH_ALERTS) return;
    
    // Track last alerted bar to avoid duplicate alerts
    int barIndex = Bars(_Symbol, PERIOD_M1) - 1;
    
    if (barIndex == lastAlertedCrossBar) return;
    
    double price = iClose(_Symbol, PERIOD_M1, 1);
    double ema25 = GetEMA_1m(EMA1, 1);
    
    bool bullishCross = (lastEMACrossingUp == barIndex - 1) && (price > ema25);
    bool bearishCross = (lastEMACrossingDown == barIndex - 1) && (price < ema25);
    
    if (bullishCross || bearishCross) {
        string alertMsg = "‼️ POTENTIAL SETUP FOUND\n\n";
        alertMsg += "EMAs M1 Crossed: " + (bullishCross ? "Bullish" : "Bearish") + "\n";
        alertMsg += "Market Status: " + GetMarketStatusText() + "\n";
        alertMsg += "Momentum: " + GetMomentumStatusText() + "\n";
        
        SendSystemMessage(alertMsg, false);  // Send to users channel
        lastAlertedCrossBar = barIndex;
    }
}

//+------------------------------------------------------------------+
//| Proactive Alert: EMA75 Touch with Setup Alignment                |
//+------------------------------------------------------------------+
void SendEMA75TouchSetupAlert(bool isBullish) {
    if (!ENABLE_EMA_TOUCH_ALERTS) return;
    
    // Check if EMAs are aligned for entry
    bool emasAligned = isEMAsReadyForEntry(isBullish, TF_1M, 1);
    
    if (emasAligned) {
        string alertMsg = "🌟 SETUP PREPARATION\n\n";
        alertMsg += "EMA 75 touched: " + (isBullish ? "Bullish" : "Bearish") + "\n";
        alertMsg += "Market Status: " + GetMarketStatusText() + "\n";
        alertMsg += "Momentum: " + GetMomentumStatusText() + "\n";
        
        SendSystemMessage(alertMsg, false);  // Send to users channel
    }
}

//+------------------------------------------------------------------+
//| Send EMA Touch/Cross Alert with Momentum Details                 |
//+------------------------------------------------------------------+
void SendEMATouchAlert(string touchType, int barIndex) {
    if (!ENABLE_EMA_TOUCH_ALERTS) return;
    if (!IsTelegramEnabled()) return;
    
    // Get current market data
    double currentPrice = iClose(_Symbol, PERIOD_M1, 0);
    double adx_1m = GetADXCurrent(PERIOD_M1);
    double adx_3m = GetADXCurrent(PERIOD_M3);
    double adx_5m = GetADXCurrent(PERIOD_M5);
    
    // Get RSI
    double rsi_1m = 0;
    double rsiBuf[1];
    if (CopyBuffer(rsiHandle, 0, 0, 1, rsiBuf) > 0) {
        rsi_1m = rsiBuf[0];
    }
    
    // Check EMA alignment
    bool emasAlignedBull = isEMAsReadyForEntry(true, TF_1M, 1);
    bool emasAlignedBear = isEMAsReadyForEntry(false, TF_1M, 1);
    string emaAlignment = emasAlignedBull ? "BULL" : (emasAlignedBear ? "BEAR" : "NOT ALIGNED");
    
    // Get session info
    string detectedSession = getCurrentTradingSession();
    datetime brokerTime = TimeCurrent();
    
    // Build alert message (compact format, one emoji)
    string alertMsg = "🎯 " + touchType + "\n";
    alertMsg += "- Price: " + DoubleToString(currentPrice, 2) + " | " + TimeToString(brokerTime, TIME_MINUTES) + " | " + detectedSession + "\n";
    alertMsg += "- ADX: 1m=" + DoubleToString(adx_1m, 1) + (adx_1m > 20 ? " OK" : " LOW");
    alertMsg += " 3m=" + DoubleToString(adx_3m, 1) + (adx_3m > 20 ? " OK" : " LOW");
    alertMsg += " 5m=" + DoubleToString(adx_5m, 1) + (adx_5m > 20 ? " OK" : " LOW") + "\n";
    alertMsg += "- RSI=" + DoubleToString(rsi_1m, 1) + " | EMAs: " + emaAlignment + "\n";
    
    SendSystemMessage(alertMsg, false);  // Send to users channel
    
    if(showDebug) Print("EMA TOUCH ALERT: ", touchType, " | ADX 1m:", DoubleToString(adx_1m, 1), " | EMAs:", emaAlignment);
}

//+------------------------------------------------------------------+
//| Helper: Calculate Entry Success Rate String                      |
//+------------------------------------------------------------------+
string GetEntrySuccessRate(int success, int attempts) {
    if (attempts == 0) return "N/A";
    int rate = (int)MathRound((double)success / attempts * 100);
    return IntegerToString(success) + "/" + IntegerToString(attempts) + " (" + IntegerToString(rate) + "%)";
}

//+------------------------------------------------------------------+
//| Helper: Get Most Common Failure Reason                           |
//+------------------------------------------------------------------+
string GetTopEntryFailure(int fail1, string name1, int fail2, string name2, int fail3, string name3) {
    if (fail1 == 0 && fail2 == 0 && fail3 == 0) return "";
    if (fail1 >= fail2 && fail1 >= fail3) return name1;
    if (fail2 >= fail1 && fail2 >= fail3) return name2;
    return name3;
}
