//+------------------------------------------------------------------+
//|                                              CommonAlerts.mqh     |
//|                   Shared structs and functions for all alerts     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef COMMON_ALERTS_MQH
#define COMMON_ALERTS_MQH

//+------------------------------------------------------------------+
//| SHARED CONTENT STRUCTS - Used by both Telegram and Discord       |
//+------------------------------------------------------------------+
struct TradeAlertContent {
    string title;              // "BUY", "SELL", "WON", etc.
    string emoji;              // Emoji prefix for title
    int    colorCode;          // Discord embed color (green=65280, red=16711680, etc.)
    double slDistancePips;     // SL distance in pips (absolute)
    double tpDistancePips;     // TP distance in pips
    double rrRatio;            // Risk-reward ratio
    string slSign;             // "+" or "-" for SL
    string reason;             // Trade reason
    bool   isFollowUp;         // Is this a follow-up message (PARTIAL_TP, CLOSED, etc.)
    bool   isTradeAlert;       // Should go to users channel
    int    exitPnLPipsDisplay; // Exit P&L in pips for display
    double savedPips;          // Pips saved vs SL (for early exit)
};

//+------------------------------------------------------------------+
//| Helper functions for notification mode checking                   |
//+------------------------------------------------------------------+
bool IsTelegramEnabled() {
    return (NotificationMode == NOTIFY_TELEGRAM || NotificationMode == NOTIFY_BOTH);
}

bool IsDiscordEnabled() {
    bool enabled = (NotificationMode == NOTIFY_DISCORD || NotificationMode == NOTIFY_BOTH);
    if (showDebug) Print("[DISCORD] IsDiscordEnabled check: NotificationMode=", NotificationMode, " (NOTIFY_DISCORD=2, NOTIFY_BOTH=3), enabled=", enabled);
    return enabled;
}

//+------------------------------------------------------------------+
//| Get max trend quality score for entry type (for percentage calc)  |
//| E1/E2/E4: 13 with Ichimoku, 11 without                            |
//| E3: 12 (exhaustion score)                                         |
//+------------------------------------------------------------------+
int GetMaxTrendQualityScore(ENTRY_TYPE entryType) {
    int entryNum = 0;
    if (entryType == ENTRY_L_E1 || entryType == ENTRY_S_E1) entryNum = 1;
    else if (entryType == ENTRY_L_E2 || entryType == ENTRY_S_E2) entryNum = 2;
    else if (entryType == ENTRY_L_E3 || entryType == ENTRY_S_E3) return 12;  // E3 uses exhaustion score
    else if (entryType == ENTRY_L_E4 || entryType == ENTRY_S_E4) entryNum = 4;
    else return 11;  // Default
    
    bool useIchimoku = (entryNum == 1 && USE_ICHIMOKU_E1) || 
                       (entryNum == 2 && USE_ICHIMOKU_E2) ||
                       (entryNum == 4 && USE_ICHIMOKU_E4);
    return useIchimoku ? 13 : 11;
}

//+------------------------------------------------------------------+
//| Get trend quality as percentage string (e.g., "75%")              |
//+------------------------------------------------------------------+
string GetTrendQualityPercent(int score, ENTRY_TYPE entryType) {
    int maxScore = GetMaxTrendQualityScore(entryType);
    if (maxScore <= 0) return "0%";
    int percent = (int)MathRound((double)score / maxScore * 100);
    return IntegerToString(percent) + "%";
}
//+------------------------------------------------------------------+
//| Build shared trade alert content from trade data                  |
//| This is the SINGLE source of truth for trade alert calculations  |
//+------------------------------------------------------------------+
void BuildTradeAlertContent(Trade &dtrade, string messageType, string reasonText, 
                            double exitPrice, double exitPnLPips, TradeAlertContent &content) {
    // Initialize content
    content.reason = reasonText;
    content.colorCode = 3447003;  // Default blue
    
    // Determine title, emoji, and color based on message type
    if (messageType == "SKIP") {
        content.title = dtrade.isLong ? "SKIPPED BUY (" + GetTradeTag(dtrade) + ")" : "SKIPPED SELL (" + GetTradeTag(dtrade) + ")";
        content.emoji = "⏸️";
        content.colorCode = 9807270;  // Gray
    } else if (messageType == "PARTIAL_TP") {
        content.title = "PARTIAL TP (" + GetTradeTag(dtrade) + ")";
        content.emoji = "💰";
        content.colorCode = 16766720;  // Gold
    } else if (messageType == "CLOSED_WON") {
        content.title = "WON (" + GetTradeTag(dtrade) + ")";
        content.emoji = "🎯";
        content.colorCode = 65280;  // Green
    } else if (messageType == "CLOSED_LOST") {
        content.title = "LOST (" + GetTradeTag(dtrade) + ")";
        content.emoji = "☕️";
        content.colorCode = 16711680;  // Red
    } else if (messageType == "EARLY_EXIT") {
        if (exitPnLPips > 0) {
            content.title = "EARLY EXIT - WON (" + GetTradeTag(dtrade) + ")";
            content.colorCode = 65280;  // Green
        } else {
            content.title = "EARLY EXIT - LOST (" + GetTradeTag(dtrade) + ")";
            content.colorCode = 16711680;  // Red
        }
        content.emoji = "🚪";
    } else if (messageType == "SL_TO_BREAKEVEN") {
        content.title = "SL TO ENTRY (" + GetTradeTag(dtrade) + ")";
        content.emoji = "🛡️";
        content.colorCode = 3447003;  // Blue
    } else {
        // Default for ENTRY
        content.title = dtrade.isLong ? "BUY (" + GetTradeTag(dtrade) + ")" : "SELL (" + GetTradeTag(dtrade) + ")";
        content.emoji = dtrade.isLong ? "🟢" : "🔴";
        content.colorCode = dtrade.isLong ? 65280 : 16711680;
    }
    
    // Calculate SL distance in pips (use 0.1 pip for display)
    double slDist = (dtrade.entryPrice - dtrade.stopLoss) / (pipSize * 10);
    content.slDistancePips = MathAbs(slDist);
    
    // Determine SL sign (+ means moved favorably, - means against)
    if ((dtrade.isLong && slDist > 0) || (!dtrade.isLong && slDist < 0)) {
        content.slSign = "-";
    } else {
        content.slSign = "+";
    }
    
    // Calculate TP distance in pips
    content.tpDistancePips = MathAbs(dtrade.takeProfit - dtrade.entryPrice) / (pipSize * 10);
    
    // Calculate R:R ratio
    content.rrRatio = (content.slDistancePips > 0) ? (content.tpDistancePips / content.slDistancePips) : 0;
    
    // Determine if this is a follow-up message
    content.isFollowUp = (messageType == "PARTIAL_TP" || messageType == "CLOSED_WON" || 
                          messageType == "CLOSED_LOST" || messageType == "EARLY_EXIT" ||
                          messageType == "SL_TO_BREAKEVEN");
    
    // Determine if this is a trade alert (goes to users channel)
    content.isTradeAlert = (messageType == "ENTRY" || messageType == "CLOSED_WON" || 
                           messageType == "CLOSED_LOST" || messageType == "SKIP" || 
                           messageType == "PARTIAL_TP" || messageType == "EARLY_EXIT" ||
                           messageType == "SL_TO_BREAKEVEN");
    
    // Exit P&L for display (divide by 10 to convert from points to pips)
    content.exitPnLPipsDisplay = (int)MathRound(exitPnLPips / 10);
    
    // Calculate saved pips for early exit
    content.savedPips = 0;
    if (messageType == "EARLY_EXIT" && exitPrice > 0) {
        content.savedPips = dtrade.isLong ? 
            (exitPrice - dtrade.stopLoss) / (pipSize * 10) : 
            (dtrade.stopLoss - exitPrice) / (pipSize * 10);
    }
}

#endif // COMMON_ALERTS_MQH
