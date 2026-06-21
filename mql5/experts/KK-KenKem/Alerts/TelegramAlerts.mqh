//+------------------------------------------------------------------+
//|                                           TelegramAlerts.mqh      |
//|                   Telegram & Email alert functions                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef TELEGRAM_ALERTS_MQH
#define TELEGRAM_ALERTS_MQH

// NOTE: This file is included AFTER all variable declarations in the main script,
// so all global variables and functions are visible here.

//+------------------------------------------------------------------+
//| TELEGRAM & EMAIL ALERT FUNCTIONS                                 |
//+------------------------------------------------------------------+

// ===== SendAlert() function is in Alerts/SystemAlerts.mqh =====

//+------------------------------------------------------------------+
//| Escape HTML entities for Telegram HTML parse mode                |
//+------------------------------------------------------------------+
string EscapeHTMLEntities(string text) {
    string result = text;
    // Escape in specific order to avoid double-escaping
    StringReplace(result, "&", "&amp;");
    StringReplace(result, "<", "&lt;");
    StringReplace(result, ">", "&gt;");
    StringReplace(result, "\"", "&quot;");
    return result;
}

//+------------------------------------------------------------------+
//| URL-encode a string for Telegram API (UTF-8 byte-level encoding)|
//| Properly handles emojis and all UTF-8 multi-byte characters      |
//+------------------------------------------------------------------+
string URLEncode(string text) {
    // Convert string to UTF-8 byte array
    uchar utf8[];
    int bytesWritten = StringToCharArray(text, utf8, 0, WHOLE_ARRAY, CP_UTF8);
    if(bytesWritten <= 0) return "";
    
    // URL encode at byte level (proper UTF-8 handling)
    string result = "";
    for(int i = 0; i < bytesWritten - 1; i++) {  // -1 to skip null terminator
        uchar byte = utf8[i];
        
        // Safe unreserved characters (RFC 3986): A-Z a-z 0-9 - _ . ~
        if((byte >= 'A' && byte <= 'Z') ||
           (byte >= 'a' && byte <= 'z') ||
           (byte >= '0' && byte <= '9') ||
           byte == '-' || byte == '_' || byte == '.' || byte == '~') {
            result += CharToString(byte);
        }
        // Also allow some safe punctuation for readability: : / ? @ ! $ ' ( ) * , ;
        else if(byte == ':' || byte == '/' || byte == '?' || byte == '@' ||
                byte == '!' || byte == '$' || byte == '\'' || byte == '(' ||
                byte == ')' || byte == '*' || byte == ',' || byte == ';') {
            result += CharToString(byte);
        }
        // Percent-encode everything else (including spaces, newlines, and all non-ASCII bytes)
        else {
            result += StringFormat("%%%02X", byte);
        }
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Parse message_id from Telegram API response                       |
//+------------------------------------------------------------------+
long ParseMessageIdFromResponse(string response) {
    // Look for "message_id": in the response
    int msgIdPos = StringFind(response, "\"message_id\":");
    if (msgIdPos == -1) return 0;
    
    // Find the number after "message_id":
    int startPos = msgIdPos + 13;  // Length of "message_id":
    int endPos = startPos;
    
    // Skip whitespace
    while (endPos < StringLen(response) && (StringGetCharacter(response, endPos) == ' ')) endPos++;
    startPos = endPos;
    
    // Find end of number
    while (endPos < StringLen(response)) {
        ushort ch = StringGetCharacter(response, endPos);
        if (ch < '0' || ch > '9') break;
        endPos++;
    }
    
    if (endPos > startPos) {
        string msgIdStr = StringSubstr(response, startPos, endPos - startPos);
        return StringToInteger(msgIdStr);
    }
    return 0;
}

// Helper function to send to a specific chat (returns message_id or 0 on failure)
long SendToChat(string chatId, string chatLabel, string encodedMessage, long replyToMsgId = 0) {
    // CRITICAL: Skip entirely in backtest/optimization mode (performance)
    if (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
        return 0;
    }
    
    // PERFORMANCE: Pre-build URL to minimize string operations
    string url = "https://api.telegram.org/bot" + TELEGRAM_BOT_TOKEN + "/sendMessage";    
    int timeout = 2000;
    string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

    if (chatId == "") return 0;  // Skip if not configured
    
    string postData = "chat_id=" + chatId + "&text=" + encodedMessage + "&parse_mode=HTML";
    
    // Add reply_to_message_id if provided
    if (replyToMsgId > 0) {
        postData += "&reply_to_message_id=" + IntegerToString(replyToMsgId);
    }
    
    char post[], result[];
    StringToCharArray(postData, post, 0, StringLen(postData), CP_UTF8);
    
    int res = WebRequest("POST", url, headers, timeout, post, result, headers);
    
    if(res == -1) {
        int errorCode = GetLastError();
        if(showDebug) {
            Print("[TELEGRAM] WebRequest error (", chatLabel, "): Error=", errorCode);
        }
        return 0;
    }
    
    string response = CharArrayToString(result, 0, -1, CP_UTF8);
    bool ok = (StringFind(response, "\"ok\":true") != -1 || StringFind(response, "\"ok\": true") != -1);
    
    if(res == 200 && ok) {
        long msgId = ParseMessageIdFromResponse(response);
        if(showDebug) Print("[TELEGRAM] Sent to ", chatLabel, " successfully, msg_id=", msgId);
        return msgId;
    } else {
        if(showDebug) {
            Print("[TELEGRAM] ", chatLabel, " send failed - HTTP=", res, " body=", response);
        }
        return 0;
    }
}

//+------------------------------------------------------------------+
//| Send Telegram Message (ASYNC - non-blocking)                     |
//| isTradeAlert: true for BUY/SELL/WON/LOST/SKIP (sends to both)   |
//|               false for admin-only messages (startup, health)    |
//| replyToMsgId: if > 0, reply to this message instead of new msg   |
//| Returns: message_id from USERS channel (for reply threading)     |
//+------------------------------------------------------------------+
long SendTelegramMessage(string message, bool isTradeAlert = false, long replyToMsgId = 0) {
    if (!IsTelegramEnabled()) {
        return 0;
    }
    
    if (TELEGRAM_BOT_TOKEN == "") {
        if(showDebug) Print("[TELEGRAM] NOT CONFIGURED - Missing BOT_TOKEN");
        return 0;
    }
    
    // Validate message is not empty
    string trimmedMessage = message;
    StringTrimLeft(trimmedMessage);
    StringTrimRight(trimmedMessage);
    if (StringLen(trimmedMessage) == 0) {
        if(showDebug) Print("[TELEGRAM] ERROR - Message is empty, skipping send");
        return 0;
    }
    
    // In tester mode, always log to help diagnose issues
    bool isTesterMode = (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION));
    if (isTesterMode && showDebug) {
        //Print("[TELEGRAM TESTER] Original message:\n", message);
    }
    
    // Sanitize HTML entities first (since we use parse_mode=HTML)
    string sanitizedMessage = EscapeHTMLEntities(message);
    
    // URL-encode the sanitized message
    string encodedMessage = URLEncode(sanitizedMessage);
    
    // Debug: Show encoded message if needed
    if (showDebug && isTesterMode) {
        // Print("[TELEGRAM TESTER] After HTML escape: ", sanitizedMessage);
        // Print("[TELEGRAM TESTER] After URL encode: ", encodedMessage);
    }
    
    // Send to appropriate channels based on message type
    long usersMsgId = 0;
    
    if (isTradeAlert) {
        // Trade alerts: Send to USERS channel only (admins are in users group too)
        usersMsgId = SendToChat(TELEGRAM_CHAT_ID_USERS, "USERS", encodedMessage, replyToMsgId);
    } else {
        // Non-trade alerts (health checks, summaries, etc.): Send to ADMINS only
        SendToChat(TELEGRAM_CHAT_ID_ADMINS, "ADMINS", encodedMessage, replyToMsgId);
    }
    
    return usersMsgId;
}

//+------------------------------------------------------------------+
//| Send Telegram Message to USERS channel only (e.g., news alerts)  |
//+------------------------------------------------------------------+
void SendTelegramToUsersOnly(string message) {
    if (!IsTelegramEnabled() || TELEGRAM_BOT_TOKEN == "") return;
    
    string trimmedMessage = message;
    StringTrimLeft(trimmedMessage);
    StringTrimRight(trimmedMessage);
    if (StringLen(trimmedMessage) == 0) return;
    
    string sanitizedMessage = EscapeHTMLEntities(message);
    string encodedMessage = URLEncode(sanitizedMessage);
    
    SendToChat(TELEGRAM_CHAT_ID_USERS, "USERS", encodedMessage, 0);
}

//+------------------------------------------------------------------+
//| Unified Alert Function - Sends to Telegram + CSV + Email         |
//| exitPrice/exitPnLPips: Optional params for EARLY_EXIT to show    |
//|                        actual exit price and P&L                 |
//+------------------------------------------------------------------+
void SendAlertForTrade(string subject, string fullMessage, Trade &dtrade, string messageType = "ENTRY", string reason = "", double exitPrice = 0, double exitPnLPips = 0) {    
    // Generate Telegram signal message (allow SKIP even if type is empty)
    if (IsTelegramEnabled()) {
        // PROP TRADING MODE: Simplified alerts without trade details (FundedNext compliance)
        if (MADE_FOR_PROP_TRADING) {
            // Skip sending alerts for skipped trades in prop mode
            if (messageType == "SKIP") {
                SendAlert(subject, fullMessage);
                ExportTradeEventToCSV(dtrade, messageType, reason);
                return;
            }
            
            string propTitle = "";
            if (messageType == "PARTIAL_TP") propTitle = "Partial Close";
            else if (messageType == "CLOSED_WON") propTitle = "Trade Closed +";
            else if (messageType == "CLOSED_LOST") propTitle = "Trade Closed -";
            else if (messageType == "EARLY_EXIT") propTitle = exitPnLPips > 0 ? "Early Exit +" : "Early Exit -";
            else propTitle = "New Trade";
            
            string propMsg = _Symbol + " | " + propTitle + "\n";
            propMsg += "Type: " + dtrade.type + "\n";
            propMsg += "---\nKenKem " + VERSION + " | Acc: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
            propMsg += "\nBalance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2);
            
            bool isTradeAlert = (messageType == "ENTRY" || messageType == "CLOSED_WON" || 
                                messageType == "CLOSED_LOST" || messageType == "SKIP" || 
                                messageType == "PARTIAL_TP" || messageType == "EARLY_EXIT");
            SendTelegramMessage(propMsg, isTradeAlert, 0);
            SendAlert(subject, fullMessage);
            ExportTradeEventToCSV(dtrade, messageType, reason);
            return;
        }
        
        // Build shared content (single source of truth for all calculations)
        TradeAlertContent content;
        BuildTradeAlertContent(dtrade, messageType, reason, exitPrice, exitPnLPips, content);
        
        string signalMessage = _Symbol + " SIGNAL\n";
        signalMessage += content.emoji + " " + content.title + "\n";

        if (messageType == "PARTIAL_TP") {
            signalMessage += "- Action: Partial TP taken, SL => Entry!!\n";
        } else if (messageType == "SL_TO_BREAKEVEN") {
            // Use custom reason if provided, otherwise fallback to generic
            if (content.reason != "") {
                signalMessage += "- Action: " + content.reason + "\n";
            } else {
                signalMessage += "- Action: SL moved to Entry (Profit protection)\n";
            }
        } else if (content.reason != "") {
            signalMessage += "- Reason: " + content.reason + "\n";
        }
        
        // Entry details - show "Executed Entry" for follow-up signals to clarify it's the actual fill price
        string entryLabel = content.isFollowUp ? "Executed Entry" : "Entry";
        signalMessage += "- " + entryLabel + ": " + DoubleToString(dtrade.entryPrice, _Digits) + "\n";
        
        // SL line - show original -> current if trailed
        if (dtrade.slWasTrailed && dtrade.bufferedSLDistancePips > 0) {
            double originalSL = dtrade.isLong 
                ? dtrade.entryPrice - (dtrade.bufferedSLDistancePips * pipSize)
                : dtrade.entryPrice + (dtrade.bufferedSLDistancePips * pipSize);
            signalMessage += "- SL: " + DoubleToString(originalSL, _Digits) + " -> " + DoubleToString(dtrade.stopLoss, _Digits);
        } else {
            signalMessage += "- SL: " + DoubleToString(dtrade.stopLoss, _Digits);
        }
        signalMessage += " (" + content.slSign + IntegerToString((int)MathRound(content.slDistancePips)) + " pips)\n";
        
        signalMessage += "- TP: " + DoubleToString(dtrade.takeProfit, _Digits);
        signalMessage += " (+" + IntegerToString((int)MathRound(content.tpDistancePips)) + " pips)\n";
        
        // For EARLY_EXIT, show actual exit price, P&L, and saved pips
        if (messageType == "EARLY_EXIT" && exitPrice > 0) {
            string pnlSign = content.exitPnLPipsDisplay >= 0 ? "+" : "";
            signalMessage += "- Exit Price: " + DoubleToString(exitPrice, _Digits) + 
                            " (" + pnlSign + IntegerToString(content.exitPnLPipsDisplay) + " pips)\n";
            if (content.savedPips > 0) {
                signalMessage += "- Saved: " + IntegerToString((int)MathRound(content.savedPips)) + " pips vs SL\n";
            }
        }
        
        // Risk-Reward ratio - Display only for entry signal
        if (content.rrRatio > 0 && messageType == "ENTRY") {
            signalMessage += "- R:R = 1:" + DoubleToString(content.rrRatio, 2) + "\n";
        } else {
            signalMessage += "\n";
        }
        
        // Only show trade progress info for follow-up messages
        if (content.isFollowUp) {
            // Partial TP info if available
            if (dtrade.hasTakenPartialProfit) {
                signalMessage += "- Partial TP was taken\n";
            }
            
            // TP extensions info (only if initialized and > 0)
            if (dtrade.tpExtensions > 0 && dtrade.tpExtensions < 1000) {
                signalMessage += "- TP extended " + IntegerToString(dtrade.tpExtensions) + " times\n";
            }
            
            
            // // Show current P&L if available and valid
            // if (dtrade.pnL != 0 && dtrade.lotSize > 0 && contractSize > 0 && pipSize > 0) {
            //     double pnlPips = dtrade.pnL / (contractSize * dtrade.lotSize * pipSize);
            //     string pnlSign = pnlPips > 0 ? "+" : "";
            //     signalMessage += "- PnL: " + pnlSign + DoubleToString(pnlPips, 1) + " pips\n";
            // }
        }
        
        // Magic number
        // if (dtrade.magicNumber > 0) {
        //     signalMessage += "\n- Unique Number: " + IntegerToString(dtrade.magicNumber) + "\n";
        // }
        // Add footer with version and account info
        signalMessage += "---\nKenKem " + VERSION + " | Acc: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
        
        // Calculate and show ROI
        // double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        // double roi = ((currentBalance - INITIAL_ACCOUNT_BALANCE) / INITIAL_ACCOUNT_BALANCE) * 100.0;
        // string roiSign = roi >= 0 ? "+" : "";
        // signalMessage += "\n- ROI: " + roiSign + DoubleToString(roi, 2) + "%";
        
        // Determine if we should reply to an existing message (for trade updates)
        long replyToMsgId = 0;
        if (content.isFollowUp && dtrade.telegramMsgId > 0) {
            replyToMsgId = dtrade.telegramMsgId;
        }
        
        // Send message and capture returned message ID
        long sentMsgId = SendTelegramMessage(signalMessage, content.isTradeAlert, replyToMsgId);
        
        // Fallback: If reply failed (msg_id=0) and we tried to reply, retry as new message
        if (sentMsgId == 0 && replyToMsgId > 0) {
            if(showDebug) Print("[TELEGRAM] Reply failed, retrying as new message");
            sentMsgId = SendTelegramMessage(signalMessage, content.isTradeAlert, 0);
        }
        
        // On ENTRY, store the message ID for future replies (not for SKIP)
        if (messageType == "ENTRY" && sentMsgId > 0) {
            dtrade.telegramMsgId = sentMsgId;
        }
    }
    
    // Send to Discord if enabled (reuses same trade data, different format)
    if (IsDiscordEnabled()) {
        long discordMsgId = SendDiscordTradeAlert(dtrade, messageType, reason, exitPrice, exitPnLPips);
        
        // On ENTRY, store the Discord message ID for future replies
        if (messageType == "ENTRY" && discordMsgId > 0) {
            dtrade.discordMsgId = discordMsgId;
        }
    }

    // Send regular alert/email - Prioritize Telegram instead of Email
    SendAlert(subject, fullMessage);

    // Export to CSV
    ExportTradeEventToCSV(dtrade, messageType, reason);   
}

//+------------------------------------------------------------------+
//| Enhanced Health Check Message with Time Details                  |
//+------------------------------------------------------------------+
bool SendHealthCheckMessage() {
    if (!ENABLE_HEALTH_CHECK_MESSAGES) return false;
    if (IsInHealthCheckWeekendBlock()) return false;
    
    datetime currentTime = TimeCurrent();
    int intervalSeconds = HEALTH_CHECK_INTERVAL_MINUTES * 60;
    
    // Check if it's time for health check
    if (lastHealthCheckTime == 0) {
        lastHealthCheckTime = currentTime;
        return false; // Skip first check
    }
    
    if (currentTime - lastHealthCheckTime < intervalSeconds) return false;
    
    lastHealthCheckTime = currentTime;
    datetime brokerTime = TimeCurrent();
    datetime vpsLocalTime = TimeLocal();
    
    string detectedSession = getCurrentTradingSession();
    string healthMsg = "HEALTH CHECK\n";
    
    healthMsg += "Broker Time: " + TimeToString(brokerTime, TIME_MINUTES) + " GMT | ";
    healthMsg += "VPS local time: " + TimeToString(vpsLocalTime, TIME_MINUTES) + "\n";
    if (detectedSession == "NONE") {
        healthMsg += "Current session: NONE (Outside valid trading sessions)\n";
    } else {
        healthMsg += "Current session: " + detectedSession + "\n";
    }
    
    // Show balance/equity in prop mode only (for monitoring drawdown limits)
    if (MADE_FOR_PROP_TRADING) {
        double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        healthMsg += "Balance: $" + DoubleToString(currentBalance, 2) + " | ";
        healthMsg += "Equity: $" + DoubleToString(currentEquity, 2) + "\n";
    }
    healthMsg += "Entries found before risk gating= " + IntegerToString(entryDetectedCount) + "\n";
    healthMsg += "Session: W:" + IntegerToString(sessionWinCount) + " L:" + IntegerToString(sessionLossCount) + 
                 "/" + IntegerToString(MAX_SESSION_LOSSES) + " BE:" + IntegerToString(sessionBreakEvenCount) + "\n";
    healthMsg += "EA Status: " + GetEABlockReasonText() + "\n";
    healthMsg += "Market Status: " + GetMarketStatusText() + "\n";
    healthMsg += "Momentum: " + GetMomentumStatusText() + "\n";
    healthMsg += "\nKenKem v" + VERSION + " | Acc ID: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
    
    // Send to Telegram if enabled
    if (IsTelegramEnabled()) {
        SendTelegramMessage(healthMsg, false);  // Health check to admins only (isTradeAlert=false)
    }
    
    // NOTE: Discord health check is called from SystemAlerts.mqh::SendUnifiedHealthCheck()
    // to avoid circular dependency (TelegramAlerts included before DiscordAlerts)
    return true;  // Indicate that health check was sent
}



void SendEntryFailureSummary() {
    datetime currentTime = TimeCurrent();
    
    // Only log once per day, and only if we have any failure reasons
    datetime today = iTime(_Symbol, PERIOD_D1, 0);
    int totalReasons = entryStats.le1_no_cross + entryStats.le1_mtf_fail + entryStats.le1_momentum_fail +
                       entryStats.se1_no_cross + entryStats.se1_mtf_fail + entryStats.se1_momentum_fail +
                       entryStats.le2_no_touch + entryStats.le2_mtf_fail + entryStats.le2_volume_fail +
                       entryStats.se2_no_touch + entryStats.se2_mtf_fail + entryStats.se2_volume_fail;
    if (totalReasons == 0) return;
    if (today == lastEntryStatsLogDate) return;

    lastEntryStatsLogDate = today;

    // Build a compact one-line summary using only failure reason counters (no attempts/success counts)
    string summary = "E1_L(no_cross=" + IntegerToString(entryStats.le1_no_cross) +
                     ",mtf=" + IntegerToString(entryStats.le1_mtf_fail) +
                     ",mom=" + IntegerToString(entryStats.le1_momentum_fail) + ")" +
                     " E1_S(no_cross=" + IntegerToString(entryStats.se1_no_cross) +
                     ",mtf=" + IntegerToString(entryStats.se1_mtf_fail) +
                     ",mom=" + IntegerToString(entryStats.se1_momentum_fail) + ")" +
                     " E2_L(no_touch=" + IntegerToString(entryStats.le2_no_touch) +
                     ",mtf=" + IntegerToString(entryStats.le2_mtf_fail) +
                     ",vol=" + IntegerToString(entryStats.le2_volume_fail) + ")" +
                     " E2_S(no_touch=" + IntegerToString(entryStats.se2_no_touch) +
                     ",mtf=" + IntegerToString(entryStats.se2_mtf_fail) +
                     ",vol=" + IntegerToString(entryStats.se2_volume_fail) + ")";

    AppendEntryStatsToStateFile(summary);

    // Reset statistics after logging
    ZeroMemory(entryStats);
}



#endif // TELEGRAM_ALERTS_MQH
