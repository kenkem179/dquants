//+------------------------------------------------------------------+
//|                                            DiscordAlerts.mqh     |
//|                   Discord webhook alert functions                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef DISCORD_ALERTS_MQH
#define DISCORD_ALERTS_MQH

//+------------------------------------------------------------------+
//| Escape special characters for JSON string values                  |
//| Converts emojis and special chars to Unicode escape sequences     |
//| IMPORTANT: Always use this for any text containing emojis!        |
//| Direct emoji literals in JSON strings will cause HTTP 400 errors  |
//+------------------------------------------------------------------+
string EscapeJSONString(string text) {
    string result = "";
    int len = StringLen(text);
    
    for (int i = 0; i < len; i++) {
        ushort ch = StringGetCharacter(text, i);
        
        // Handle standard escape sequences
        if (ch == '\\') {
            result += "\\\\";
        } else if (ch == '"') {
            result += "\\\"";
        } else if (ch == '\n') {
            result += "\\n";
        } else if (ch == '\r') {
            result += "\\r";
        } else if (ch == '\t') {
            result += "\\t";
        } else if (ch == 0x08) {
            result += "\\b";
        } else if (ch == '\f') {
            result += "\\f";
        } else if (ch == 0) {
            // Skip null characters
            continue;
        } else if (ch >= 0x80) {
            // Escape all non-ASCII characters (including emojis) as \uXXXX
            result += StringFormat("\\u%04x", ch);
        } else {
            // Regular ASCII character
            result += ShortToString(ch);
        }
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Check if message type should be sent to public channel           |
//| Public: SKIP, PARTIAL_TP, CLOSED_WON, CLOSED_LOST, EARLY_EXIT    |
//+------------------------------------------------------------------+
bool IsPublicSignalType(string messageType) {
    return (messageType == "SKIP" || 
            messageType == "PARTIAL_TP" ||
            messageType == "CLOSED_WON" || 
            messageType == "CLOSED_LOST" || 
            messageType == "EARLY_EXIT");
}

//+------------------------------------------------------------------+
//| Get compact trade tag: "L-E1@15:30" for signal titles              |
//+------------------------------------------------------------------+
int FindTradeExtrasIndex(const Trade &dtrade) {
    for (int idx = 0; idx < ArraySize(trades); idx++) {
        if (trades[idx].id == dtrade.id) return idx;
    }
    return -1;
}

string GetTradeTag(const Trade &dtrade) {
    // Extract GMT HH:MM from trade ID (format: "TYPE #YYYYMMDDHHMMSSmmm" in GMT)
    int hashPos = StringFind(dtrade.id, " #");
    if (hashPos < 0 || (int)StringLen(dtrade.id) < hashPos + 14) return dtrade.type;
    
    string tsBlock = StringSubstr(dtrade.id, hashPos + 2);
    return dtrade.type + "@" + StringSubstr(tsBlock, 8, 2) + ":" + StringSubstr(tsBlock, 10, 2);
}

//+------------------------------------------------------------------+
//| Build Entry/SL/TP reference fields for embed JSON                 |
//| Returns comma-prefixed fields string for appending after others   |
//+------------------------------------------------------------------+
string AppendEntrySlTpFields(Trade &dtrade) {
    double slDist = dtrade.isLong ? (dtrade.stopLoss - dtrade.entryPrice) : (dtrade.entryPrice - dtrade.stopLoss);
    int slDistPips = (int)MathRound(slDist / (pipSize * 10));
    string slPipsText = (slDistPips >= 0 ? "+" : "") + IntegerToString(slDistPips) + " pips";
    
    double tpDist = dtrade.isLong ? (dtrade.takeProfit - dtrade.entryPrice) : (dtrade.entryPrice - dtrade.takeProfit);
    int tpDistPips = (int)MathRound(tpDist / (pipSize * 10));
    string tpPipsText = "+" + IntegerToString(tpDistPips) + " pips";
    
    string fields = "";
    fields += ",{\"name\":\"Executed Entry\",\"value\":\"" + EscapeJSONString(DoubleToString(dtrade.entryPrice, _Digits)) + "\",\"inline\":true}";
    fields += ",{\"name\":\"SL\",\"value\":\"" + EscapeJSONString(DoubleToString(dtrade.stopLoss, _Digits) + " (" + slPipsText + ")") + "\",\"inline\":true}";
    fields += ",{\"name\":\"TP\",\"value\":\"" + EscapeJSONString(DoubleToString(dtrade.takeProfit, _Digits) + " (" + tpPipsText + ")") + "\",\"inline\":true}";
    return fields;
}

//+------------------------------------------------------------------+
//| Create simplified message for public channel (no sensitive data)  |
//| Educational focus: what happened, not specific entry details      |
//+------------------------------------------------------------------+
string CreatePublicEmbed(Trade &dtrade, string messageType, string reason, double exitPnLPips) {
    string emoji = "";
    string title = "";
    int colorCode = 3447003;  // Blue default
    
    string tag = GetTradeTag(dtrade);
    
    if (messageType == "ENTRY") {
        emoji = dtrade.isLong ? "🟢" : "🔴";
        title = dtrade.isLong ? "BUY SIGNAL (" + tag + ")" : "SELL SIGNAL (" + tag + ")";
        colorCode = dtrade.isLong ? 65280 : 16711680;
    } else if (messageType == "SKIP") {
        emoji = "⏸️";
        title = "SKIPPED (" + tag + ")";
        colorCode = 9807270;  // Gray
    } else if (messageType == "CLOSED_WON") {
        emoji = "🎯";
        title = "WON (" + tag + ")";
        colorCode = 65280;  // Green
    } else if (messageType == "CLOSED_LOST") {
        emoji = "☕️";
        title = "LOST (" + tag + ")";
        colorCode = 16711680;  // Red
    } else if (messageType == "PARTIAL_TP") {
        emoji = "💰";
        title = "PARTIAL PROFIT TAKEN (" + tag + ")";
        colorCode = 16766720;  // Gold
    } else if (messageType == "EARLY_EXIT") {
        emoji = "🚪";
        title = exitPnLPips >= 0 ? "EARLY EXIT - Protected (" + tag + ")" : "EARLY EXIT - Cut Loss (" + tag + ")";
        colorCode = exitPnLPips >= 0 ? 16766720 : 16744256;  // Gold or Orange
    } else if (messageType == "PNL_UPDATE") {
        emoji = "📊";
        title = "TRADE UPDATE (" + tag + ")";
        colorCode = 3447003;  // Blue
    }
    
    string json = "{";
    
    // Thread follow-up signals to original public message when threading enabled
    bool isFollowUp = (messageType != "ENTRY" && messageType != "SKIP");
    int pubIdx = FindTradeExtrasIndex(dtrade);
    if (ENABLED_SIGNAL_THREADING && isFollowUp && pubIdx >= 0 && tradeExtras[pubIdx].discordPublicMsgId > 0) {
        json += "\"message_reference\":{\"message_id\":\"" + IntegerToString(tradeExtras[pubIdx].discordPublicMsgId) + "\"},";
    }
    
    json += "\"embeds\":[{";
    json += "\"title\":\"" + EscapeJSONString(emoji + " " + title + " - " + _Symbol) + "\",";
    json += "\"color\":" + IntegerToString(colorCode) + ",";
    json += "\"fields\":[";
    
    // Entry type category (E1/E2/E3/E4 as descriptive names)
    string entryDesc = "";
    if (dtrade.entryType == ENTRY_L_E1 || dtrade.entryType == ENTRY_S_E1) entryDesc = "New Trend";
    else if (dtrade.entryType == ENTRY_L_E2 || dtrade.entryType == ENTRY_S_E2) entryDesc = "Pull Back";
    else if (dtrade.entryType == ENTRY_L_E3 || dtrade.entryType == ENTRY_S_E3) entryDesc = "Reversal";
    else if (dtrade.entryType == ENTRY_L_E4 || dtrade.entryType == ENTRY_S_E4) entryDesc = "Early Trend";
    else entryDesc = "Signal";
    json += "{\"name\":\"Strategy\",\"value\":\"" + EscapeJSONString(entryDesc) + "\",\"inline\":true}";
    
    // For ENTRY: show risk/reward in pips (0.1 pip display)
    if (messageType == "ENTRY") {
        double slPips = MathAbs(dtrade.entryPrice - dtrade.stopLoss) / (pipSize * 10);
        double tpPips = MathAbs(dtrade.takeProfit - dtrade.entryPrice) / (pipSize * 10);
        json += ",{\"name\":\"Risk\",\"value\":\"" + IntegerToString((int)MathRound(slPips)) + " pips\",\"inline\":true}";
        json += ",{\"name\":\"Reward\",\"value\":\"" + IntegerToString((int)MathRound(tpPips)) + " pips\",\"inline\":true}";
        
        // Trend quality as percentage
        string tqPercent = GetTrendQualityPercent(dtrade.detectionTrendQualityScore, dtrade.entryType);
        json += ",{\"name\":\"Trend Quality\",\"value\":\"" + EscapeJSONString(tqPercent) + "\",\"inline\":true}";
    }
    
    // Result for closed trades (pips in 0.1 display - divide by 10)
    if (messageType == "CLOSED_WON" || messageType == "CLOSED_LOST" || messageType == "EARLY_EXIT") {
        int displayPips = (int)MathRound(exitPnLPips / 10);
        string pnlSign = displayPips >= 0 ? "+" : "";
        json += ",{\"name\":\"Result\",\"value\":\"" + EscapeJSONString(pnlSign + IntegerToString(displayPips) + " pips") + "\",\"inline\":true}";
    }
    
    // PARTIAL_TP: Show action
    if (messageType == "PARTIAL_TP") {
        json += ",{\"name\":\"Action\",\"value\":\"Partial profit locked, SL moved to entry\",\"inline\":false}";
    }
    
    // Reference Entry/SL/TP for all follow-up signals so each message is self-contained
    if (isFollowUp) {
        json += AppendEntrySlTpFields(dtrade);
    }
    
    // Reason (educational)
    if (reason != "" && messageType != "ENTRY") {
        json += ",{\"name\":\"Reason\",\"value\":\"" + EscapeJSONString(reason) + "\",\"inline\":false}";
    }
    
    json += "]";
    json += "}]";
    json += "}";
    
    return json;
}

//+------------------------------------------------------------------+
//| Create P&L zone update embed for premium channels (full info)     |
//+------------------------------------------------------------------+
string CreatePnLUpdateEmbed(Trade &dtrade, double floatingPnLPips, int currentTrendQuality) {
    string emoji = floatingPnLPips >= 0 ? "📈" : "📉";
    string title = "LIVE TRADE UPDATES (" + GetTradeTag(dtrade) + ")";
    int colorCode = floatingPnLPips >= 0 ? 65280 : 16744256;  // Green or Orange
    
    string json = "{";
    
    // Thread to original message when threading enabled
    if (ENABLED_SIGNAL_THREADING && dtrade.discordMsgId > 0) {
        json += "\"message_reference\":{\"message_id\":\"" + IntegerToString(dtrade.discordMsgId) + "\"},";
    }
    
    json += "\"embeds\":[{";
    json += "\"title\":\"" + EscapeJSONString(emoji + " " + title + " " + _Symbol) + "\",";
    json += "\"color\":" + IntegerToString(colorCode) + ",";
    json += "\"fields\":[";
    
    // Live P&L in pips (0.1 display) with TP distance
    int displayPips = (int)MathRound(floatingPnLPips / 10);
    int tpDistPips = (int)MathRound(MathAbs(dtrade.takeProfit - dtrade.entryPrice) / (pipSize * 10));
    int riskPips = (int)MathRound(MathAbs(dtrade.entryPrice - dtrade.stopLoss) / (pipSize * 10));  // 1R in pips
    string pnlSign = displayPips >= 0 ? "+" : "";
    string pnlText = pnlSign + IntegerToString(displayPips) + " pips / +" + IntegerToString(tpDistPips) + " pips TP";
    // Show suggestion when floating P&L reaches 95% ~ 105% of 1R (risk amount)
    if (riskPips > 0 && displayPips >= (int)(riskPips * 0.95) && displayPips <= (int)(riskPips * 1.05)) {
        pnlText += " - Close 1/2 position?";
    }
    json += "{\"name\":\"Live P&L\",\"value\":\"" + EscapeJSONString(pnlText) + "\",\"inline\":true}";
    
    // Trend quality as percentage
    string tqPercent = GetTrendQualityPercent(currentTrendQuality, dtrade.entryType);
    int tqPercentNum = (int)MathRound((double)currentTrendQuality / GetMaxTrendQualityScore(dtrade.entryType) * 100);
    string tqText = tqPercent;
    if (tqPercentNum < 50) {
        tqText += " - Trend is Weakening!!";
    }
    json += ",{\"name\":\"Trend Quality\",\"value\":\"" + EscapeJSONString(tqText) + "\",\"inline\":true}";
    
    // Spacer forces Entry/SL/TP onto their own row (P&L + TQ fill 2 of 3 inline columns)
    json += ",{\"name\":\"\\u200b\",\"value\":\"\\u200b\",\"inline\":false}";
    json += AppendEntrySlTpFields(dtrade);
    
    json += "]";
    json += "}]";
    json += "}";
    
    return json;
}

//+------------------------------------------------------------------+
//| Create P&L zone update embed for public channel (simplified)      |
//+------------------------------------------------------------------+
string CreatePublicPnLUpdateEmbed(Trade &dtrade, double floatingPnLPips, int currentTrendQuality) {
    string emoji = floatingPnLPips >= 0 ? "📈" : "📉";
    string title = "LIVE TRADE UPDATE (" + GetTradeTag(dtrade) + ")";
    int colorCode = floatingPnLPips >= 0 ? 65280 : 16744256;
    
    string json = "{";
    
    // Thread to original public message when threading enabled
    int pubIdx2 = FindTradeExtrasIndex(dtrade);
    if (ENABLED_SIGNAL_THREADING && pubIdx2 >= 0 && tradeExtras[pubIdx2].discordPublicMsgId > 0) {
        json += "\"message_reference\":{\"message_id\":\"" + IntegerToString(tradeExtras[pubIdx2].discordPublicMsgId) + "\"},";
    }
    
    json += "\"embeds\":[{";
    json += "\"title\":\"" + EscapeJSONString(emoji + " " + title + " " + _Symbol) + "\",";
    json += "\"color\":" + IntegerToString(colorCode) + ",";
    json += "\"fields\":[";
    
    // Live P&L in pips (0.1 display) with TP distance
    int displayPips = (int)MathRound(floatingPnLPips / 10);
    int tpDistPips = (int)MathRound(MathAbs(dtrade.takeProfit - dtrade.entryPrice) / (pipSize * 10));
    int riskPips = (int)MathRound(MathAbs(dtrade.entryPrice - dtrade.stopLoss) / (pipSize * 10));  // 1R in pips
    string pnlSign = displayPips >= 0 ? "+" : "";
    string pnlText = pnlSign + IntegerToString(displayPips) + " pips / +" + IntegerToString(tpDistPips) + " pips TP";
    // Show suggestion when floating P&L reaches 95% ~ 105% of 1R (risk amount)
    if (riskPips > 0 && displayPips >= (int)(riskPips * 0.95) && displayPips <= (int)(riskPips * 1.05)) {
        pnlText += " - Close 1/2 position?";
    }
    json += "{\"name\":\"Live P&L\",\"value\":\"" + EscapeJSONString(pnlText) + "\",\"inline\":true}";
    
    // Trend quality as percentage
    string tqPercent = GetTrendQualityPercent(currentTrendQuality, dtrade.entryType);
    int tqPercentNum = (int)MathRound((double)currentTrendQuality / GetMaxTrendQualityScore(dtrade.entryType) * 100);
    string tqText = tqPercent;
    if (tqPercentNum < 50) {
        tqText += " - Trend is Weakening!!";
    }
    json += ",{\"name\":\"Trend Quality\",\"value\":\"" + EscapeJSONString(tqText) + "\",\"inline\":true}";
    
    // Spacer forces Entry/SL/TP onto their own row (P&L + TQ fill 2 of 3 inline columns)
    json += ",{\"name\":\"\\u200b\",\"value\":\"\\u200b\",\"inline\":false}";
    json += AppendEntrySlTpFields(dtrade);
    
    json += "]";
    json += "}]";
    json += "}";
    
    return json;
}

//+------------------------------------------------------------------+
//| Send P&L zone update to premium Discord channels only             |
//+------------------------------------------------------------------+
void SendDiscordPnLUpdatePremium(Trade &dtrade, double floatingPnLPips, int currentTrendQuality) {
    if (!IsDiscordEnabled()) return;
    
    // Send to premium channels (full info)
    string premiumJson = CreatePnLUpdateEmbed(dtrade, floatingPnLPips, currentTrendQuality);
    SendDiscordMessage(premiumJson, true, dtrade.entryType);
}

//+------------------------------------------------------------------+
//| Send P&L zone update to public Discord channel only               |
//+------------------------------------------------------------------+
void SendDiscordPnLUpdatePublic(Trade &dtrade, double floatingPnLPips, int currentTrendQuality) {
    if (!IsDiscordEnabled()) return;
    if (DISCORD_WEBHOOK_URL_PUBLIC_USERS == "") return;
    
    string publicJson = CreatePublicPnLUpdateEmbed(dtrade, floatingPnLPips, currentTrendQuality);
    SendDiscordWebhook(DISCORD_WEBHOOK_URL_PUBLIC_USERS, publicJson);
}

//+------------------------------------------------------------------+
//| Parse Discord message ID from webhook response                    |
//| Discord returns: {"id": "1234567890123456789", ...}              |
//+------------------------------------------------------------------+
long ParseDiscordMessageId(string response) {
    int idPos = StringFind(response, "\"id\":");
    if (idPos == -1) return 0;
    
    int startQuote = StringFind(response, "\"", idPos + 5);
    if (startQuote == -1) return 0;
    
    int endQuote = StringFind(response, "\"", startQuote + 1);
    if (endQuote == -1) return 0;
    
    string msgIdStr = StringSubstr(response, startQuote + 1, endQuote - startQuote - 1);
    return StringToInteger(msgIdStr);
}

//+------------------------------------------------------------------+
//| Send Discord webhook message (low-level HTTP POST)                |
//| Returns message_id on success, 0 on failure                       |
//+------------------------------------------------------------------+
long SendDiscordWebhook(string webhookUrl, string jsonPayload) {
    if (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
        return 0;
    }
    
    if (webhookUrl == "") return 0;
    
    string url = webhookUrl + "?wait=true";
    int timeout = 3000;
    string headers = "Content-Type: application/json\r\n";
    
    char post[], result[];
    StringToCharArray(jsonPayload, post, 0, StringLen(jsonPayload), CP_UTF8);
    
    if (showDebug) Print("[DISCORD] JSON payload: ", jsonPayload);
    
    int res = WebRequest("POST", url, headers, timeout, post, result, headers);
    
    if (res == -1) {
        int errorCode = GetLastError();
        Print("[DISCORD] WebRequest error: ", errorCode, " | URL: ", webhookUrl);
        Print("[DISCORD] Error 4014 = URL not in allowed list. Check Tools->Options->Expert Advisors");
        Print("[DISCORD] Add this to allowed URLs: https://discord.com");
        return 0;
    }
    
    string response = CharArrayToString(result, 0, -1, CP_UTF8);
    
    if (res == 200 || res == 204) {
        long msgId = ParseDiscordMessageId(response);
        string channelType = (StringFind(webhookUrl, DISCORD_WEBHOOK_URL_PRO_USERS) >= 0) ? "PRO_USERS" : 
                             (StringFind(webhookUrl, DISCORD_WEBHOOK_URL_PREMIUM_USERS) >= 0) ? "PREMIUM_USERS" : "ADMINS";
        Print("[DISCORD] Sent to ", channelType, " successfully, msg_id=", msgId);
        return msgId;
    } else {
        string channelType = (StringFind(webhookUrl, DISCORD_WEBHOOK_URL_PRO_USERS) >= 0) ? "PRO_USERS" : 
                             (StringFind(webhookUrl, DISCORD_WEBHOOK_URL_PREMIUM_USERS) >= 0) ? "PREMIUM_USERS" : "ADMINS";
        Print("[DISCORD] Send to ", channelType, " failed - HTTP=", res, " body=", response);
        return 0;
    }
}

//+------------------------------------------------------------------+
//| Create Discord JSON for trade alerts                              |
//| ENTRY/SKIP: Plain text for visibility (larger font in Discord)   |
//| Follow-ups: Embeds with message_reference for reply threading     |
//+------------------------------------------------------------------+
string CreateTradeEmbed(Trade &dtrade, string messageType, string reason, double exitPrice, double exitPnLPips) {
    // Use shared content builder (single source of truth)
    TradeAlertContent content;
    BuildTradeAlertContent(dtrade, messageType, reason, exitPrice, exitPnLPips, content);
    
    string json = "{";
    
    // ENTRY/SKIP use plain text for better visibility; follow-ups use embeds
    bool useEmbed = DISCORD_USE_EMBEDS && content.isFollowUp;
    bool isEntryOrSkip = (messageType == "ENTRY" || messageType == "SKIP");
    
    if (useEmbed) {
        // Follow-up messages: Use message_reference for reply threading when enabled
        if (ENABLED_SIGNAL_THREADING && dtrade.discordMsgId > 0) {
            json += "\"message_reference\":{\"message_id\":\"" + IntegerToString(dtrade.discordMsgId) + "\"},";
        }
        
        json += "\"embeds\":[{";
        json += "\"title\":\"" + EscapeJSONString(content.emoji + " " + content.title + " - " + _Symbol) + "\",";
        json += "\"color\":" + IntegerToString(content.colorCode) + ",";
        json += "\"fields\":[";
        
        json += "{\"name\":\"Executed Entry\",\"value\":\"" + EscapeJSONString(DoubleToString(dtrade.entryPrice, _Digits)) + "\",\"inline\":true},";
        json += "{\"name\":\"SL\",\"value\":\"" + EscapeJSONString(DoubleToString(dtrade.stopLoss, _Digits) + 
                " (" + content.slSign + IntegerToString((int)MathRound(content.slDistancePips)) + " pips)") + "\",\"inline\":true},";
        json += "{\"name\":\"TP\",\"value\":\"" + EscapeJSONString(DoubleToString(dtrade.takeProfit, _Digits) + 
                " (+" + IntegerToString((int)MathRound(content.tpDistancePips)) + " pips)") + "\",\"inline\":true}";
        
        if (content.reason != "" && messageType != "PARTIAL_TP" && messageType != "SL_TO_BREAKEVEN") {
            json += ",{\"name\":\"Reason\",\"value\":\"" + EscapeJSONString(content.reason) + "\",\"inline\":false}";
        }
        
        if (messageType == "PARTIAL_TP") {
            json += ",{\"name\":\"Action\",\"value\":\"Partial TP taken, SL => Entry\",\"inline\":false}";
        }
        
        if (messageType == "SL_TO_BREAKEVEN") {
            string slAction = (content.reason != "") ? content.reason : "SL moved to Entry (Profit protection)";
            json += ",{\"name\":\"Action\",\"value\":\"" + EscapeJSONString(slAction) + "\",\"inline\":false}";
        }
        
        if (messageType == "EARLY_EXIT" && exitPrice > 0) {
            string pnlSign = content.exitPnLPipsDisplay >= 0 ? "+" : "";
            json += ",{\"name\":\"Exit Price\",\"value\":\"" + EscapeJSONString(DoubleToString(exitPrice, _Digits) + 
                    " (" + pnlSign + IntegerToString(content.exitPnLPipsDisplay) + " pips)") + "\",\"inline\":true}";
            
            if (content.savedPips > 0) {
                json += ",{\"name\":\"Saved\",\"value\":\"" + EscapeJSONString(IntegerToString((int)MathRound(content.savedPips)) + " pips vs SL") + "\",\"inline\":true}";
            }
        }
        
        if (dtrade.hasTakenPartialProfit) {
            json += ",{\"name\":\"Status\",\"value\":\"Partial TP was taken\",\"inline\":true}";
        }
        if (dtrade.tpExtensions > 0 && dtrade.tpExtensions < 1000) {
            json += ",{\"name\":\"Extensions\",\"value\":\"" + EscapeJSONString("TP extended " + IntegerToString(dtrade.tpExtensions) + " times") + "\",\"inline\":true}";
        }
        
        json += "]";
        json += "}]";
    } else {
        // ENTRY/SKIP: Plain text for larger, more visible display
        string plainText = "**" + content.emoji + " " + content.title + "** - " + _Symbol + "\n\n";
        plainText += "**ET**: " + DoubleToString(dtrade.entryPrice, _Digits) + "\n";
        plainText += "**SL**: " + DoubleToString(dtrade.stopLoss, _Digits) + " (" + content.slSign + IntegerToString((int)MathRound(content.slDistancePips)) + " pips)\n";
        plainText += "**TP**: " + DoubleToString(dtrade.takeProfit, _Digits) + " (+" + IntegerToString((int)MathRound(content.tpDistancePips)) + " pips)\n";
        if (messageType == "ENTRY" && content.rrRatio > 0) {
            plainText += "\nRR= 1:" + DoubleToString(content.rrRatio, 2) + "\n";
        }
        if (content.reason != "") {
            plainText += "Reason: " + content.reason + "\n";
        }
        json += "\"content\":\"" + EscapeJSONString(plainText) + "\"";
    }
    
    json += "}";
    return json;
}

//+------------------------------------------------------------------+
//| Create Discord embed JSON for health check messages               |
//+------------------------------------------------------------------+
string CreateHealthEmbed() {
    datetime brokerTime = TimeCurrent();
    datetime vpsLocalTime = TimeLocal();
    string detectedSession = getCurrentTradingSession();
    
    string json = "{";
    
    if (DISCORD_USE_EMBEDS) {
        json += "\"embeds\":[{";
        json += "\"title\":\"\\ud83d\\udc93 HEALTH CHECK\",";
        json += "\"color\":3447003,";
        json += "\"fields\":[";
        
        json += "{\"name\":\"Broker Time\",\"value\":\"" + EscapeJSONString(TimeToString(brokerTime, TIME_MINUTES)) + " GMT\",\"inline\":true},";
        json += "{\"name\":\"VPS Time\",\"value\":\"" + EscapeJSONString(TimeToString(vpsLocalTime, TIME_MINUTES)) + "\",\"inline\":true},";
        json += "{\"name\":\"KenKem 'Relative' Session\",\"value\":\"" + EscapeJSONString(detectedSession == "NONE" ? "NONE (No trading allowed)" : detectedSession) + "\",\"inline\":true}";
        
        if (MADE_FOR_PROP_TRADING) {
            double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            json += ",{\"name\":\"Balance\",\"value\":\"$" + DoubleToString(currentBalance, 2) + "\",\"inline\":true}";
            json += ",{\"name\":\"Equity\",\"value\":\"$" + DoubleToString(currentEquity, 2) + "\",\"inline\":true}";
        }
        
        json += ",{\"name\":\"Setups Found\",\"value\":\"" + IntegerToString(entryDetectedCount) + "\",\"inline\":true}";
        json += ",{\"name\":\"Session Stats\",\"value\":\"W:" + IntegerToString(sessionWinCount) + 
                " L:" + IntegerToString(sessionLossCount) + "/" + IntegerToString(MAX_SESSION_LOSSES) + 
                " BE:" + IntegerToString(sessionBreakEvenCount) + "\",\"inline\":true}";
        json += ",{\"name\":\"EA Status\",\"value\":\"" + EscapeJSONString(GetEABlockReasonText()) + "\",\"inline\":false}";
        json += ",{\"name\":\"Market Status\",\"value\":\"" + EscapeJSONString(GetMarketStatusText()) + "\",\"inline\":true}";
        json += ",{\"name\":\"Momentum\",\"value\":\"" + EscapeJSONString(GetMomentumStatusText()) + "\",\"inline\":true}";
        
        json += "],";
        json += "\"footer\":{\"text\":\"-- ver " + VERSION + " --\"}";
        json += "}]";
    } else {
        string plainText = "HEALTH CHECK\n";
        plainText += "Broker Time: " + TimeToString(brokerTime, TIME_MINUTES) + " GMT\n";
        plainText += "Relative Session: " + (detectedSession == "NONE" ? "NONE" : detectedSession) + "\n";
        plainText += "Setups Found: " + IntegerToString(entryDetectedCount) + "\n";
        plainText += "Session Stats: W:" + IntegerToString(sessionWinCount) + " L:" + IntegerToString(sessionLossCount) + "\n";
        plainText += "\n-- ver " + VERSION + " --\n";
        json += "\"content\":\"" + EscapeJSONString(plainText) + "\"";
    }
    
    json += "}";
    return json;
}

//+------------------------------------------------------------------+
//| Create Discord embed for prop trading mode (simplified alerts)    |
//+------------------------------------------------------------------+
string CreatePropTradeEmbed(Trade &dtrade, string messageType, double exitPnLPips) {
    string propTitle = "";
    int embedColor = 3447003;
    
    if (messageType == "PARTIAL_TP") {
        propTitle = "Partial Close";
        embedColor = 16766720;
    } else if (messageType == "CLOSED_WON") {
        propTitle = "Trade Closed +";
        embedColor = 65280;
    } else if (messageType == "CLOSED_LOST") {
        propTitle = "Trade Closed -";
        embedColor = 16711680;
    } else if (messageType == "EARLY_EXIT") {
        propTitle = exitPnLPips > 0 ? "Early Exit +" : "Early Exit -";
        embedColor = exitPnLPips > 0 ? 65280 : 16711680;
    } else {
        propTitle = "New Trade";
        embedColor = 3447003;
    }
    
    string json = "{";
    
    if (DISCORD_USE_EMBEDS) {
        json += "\"embeds\":[{";
        json += "\"title\":\"" + EscapeJSONString(_Symbol + " | " + propTitle + " (" + GetTradeTag(dtrade) + ")") + "\",";
        json += "\"color\":" + IntegerToString(embedColor) + ",";
        json += "\"fields\":[";
        json += "{\"name\":\"Type\",\"value\":\"" + EscapeJSONString(dtrade.type) + "\",\"inline\":true}";
        json += "]";
        json += "}]";
    } else {
        string plainText = _Symbol + " | " + propTitle + " (" + GetTradeTag(dtrade) + ")\n";
        plainText += "Type: " + dtrade.type + "\n";
        json += "\"content\":\"" + EscapeJSONString(plainText) + "\"";
    }
    
    json += "}";
    return json;
}

//+------------------------------------------------------------------+
//| High-level Discord message sender with routing                    |
//| isTradeAlert: true for trade signals, false for admin-only        |
//| entryType: E1/E2 go to PRO_USERS only, all entries to PREMIUM     |
//| Returns message_id from PREMIUM_USERS channel for reply threading |
//+------------------------------------------------------------------+
long SendDiscordMessage(string jsonPayload, bool isTradeAlert = false, int entryType = 0) {
    if (!IsDiscordEnabled()) return 0;
    
    long premiumMsgId = 0;
    
    if (isTradeAlert) {
        // Trade signals routing:
        // - E1/E2: Send to PRO_USERS only
        // - All entries (E1/E2/E3/E4): Send to PREMIUM_USERS
        bool isE1orE2 = (entryType == 1 || entryType == 2 || 
                         entryType == 3 || entryType == 4);
        
        if (isE1orE2) {
            if (showDebug) Print("[DISCORD] Sending E1/E2 trade signal to PRO_USERS...");
            SendDiscordWebhook(DISCORD_WEBHOOK_URL_PRO_USERS, jsonPayload);
        }
        
        // All entries go to PREMIUM_USERS
        if (showDebug) Print("[DISCORD] Sending trade signal to PREMIUM_USERS...");
        premiumMsgId = SendDiscordWebhook(DISCORD_WEBHOOK_URL_PREMIUM_USERS, jsonPayload);
        
    } else {
        if (showDebug) Print("[DISCORD] Sending to ADMINS channel...");
        SendDiscordWebhook(DISCORD_WEBHOOK_URL_ADMINS, jsonPayload);
    }
    
    return premiumMsgId;
}

//+------------------------------------------------------------------+
//| Send trade alert to Discord (called from TelegramAlerts.mqh)      |
//| Reuses trade data, formats for Discord, handles routing           |
//+------------------------------------------------------------------+
long SendDiscordTradeAlert(Trade &dtrade, string messageType, string reason, double exitPrice, double exitPnLPips) {
    if (!IsDiscordEnabled()) return 0;
    
    // Use shared content builder for isTradeAlert flag (single source of truth)
    TradeAlertContent content;
    BuildTradeAlertContent(dtrade, messageType, reason, exitPrice, exitPnLPips, content);
    
    string discordJson;
    
    if (MADE_FOR_PROP_TRADING) {
        if (messageType == "SKIP") return 0;
        discordJson = CreatePropTradeEmbed(dtrade, messageType, exitPnLPips);
    } else {
        discordJson = CreateTradeEmbed(dtrade, messageType, reason, exitPrice, exitPnLPips);
    }
    
    long discordMsgId = SendDiscordMessage(discordJson, content.isTradeAlert, dtrade.entryType);
    
    // Send to public channel for specific signal types (educational/transparency)
    // ENTRY signals also go to public now (with simplified info)
    bool sendToPublic = (IsPublicSignalType(messageType) || messageType == "ENTRY") && 
                        DISCORD_WEBHOOK_URL_PUBLIC_USERS != "";
    if (sendToPublic) {
        string publicJson = CreatePublicEmbed(dtrade, messageType, reason, exitPnLPips);
        if (publicJson != "") {
            if (showDebug) Print("[DISCORD] Sending ", messageType, " to PUBLIC_USERS channel...");
            long publicMsgId = SendDiscordWebhook(DISCORD_WEBHOOK_URL_PUBLIC_USERS, publicJson);
            // Store public message ID for ENTRY signals (for threading follow-ups)
            if (messageType == "ENTRY" && publicMsgId > 0) {
                int eIdx = FindTradeExtrasIndex(dtrade);
                if (eIdx >= 0) tradeExtras[eIdx].discordPublicMsgId = publicMsgId;
            }
        }
    }
    
    return discordMsgId;
}

//+------------------------------------------------------------------+
//| Send health check to Discord (called from TelegramAlerts.mqh)     |
//+------------------------------------------------------------------+
void SendDiscordHealthCheck() {
    if (!IsDiscordEnabled()) return;
    if (DISCORD_WEBHOOK_URL_PUBLIC_USERS == "") return;
    
    string discordJson = CreateHealthEmbed();
    if (showDebug) Print("[DISCORD] Sending health check to PUBLIC_USERS channel...");
    SendDiscordWebhook(DISCORD_WEBHOOK_URL_PUBLIC_USERS, discordJson);
}

#endif // DISCORD_ALERTS_MQH
