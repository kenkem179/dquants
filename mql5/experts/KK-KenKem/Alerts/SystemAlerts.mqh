//+------------------------------------------------------------------+
//|                                             SystemAlerts.mqh    |
//|              KenKem EA v1.7.51 - System Alert Functions          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// SYSTEM ALERT & NOTIFICATION FUNCTIONS
// Base alert system, system health monitoring, and connection warnings
//================================================================

//+------------------------------------------------------------------+
//| Base Alert Function - Optimized for Performance                  |
//+------------------------------------------------------------------+
// PERFORMANCE: Optimized alert function - minimal overhead
void SendAlert(string subject = "", string msg = "") {
    // PERFORMANCE: Only print if debug enabled
    if (showDebug) {
        Print(msg);
    }
    
    // PERFORMANCE: Email is slow, only send if explicitly enabled
    if (ENABLE_EMAIL_ALERTS) {
        SendMail(subject, msg);
    }
}

//+------------------------------------------------------------------+
//| Unified System Message - Sends to both Telegram and Discord      |
//| Use this for all non-trade alerts (startup, risk, news, etc.)    |
//+------------------------------------------------------------------+
void SendSystemMessage(string message, bool isAdminOnly = false) {
    // Send to Telegram if enabled
    if (IsTelegramEnabled()) {
        SendTelegramMessage(message, !isAdminOnly);  // isTradeAlert = !isAdminOnly
    }
    
    // Send to Discord if enabled
    if (IsDiscordEnabled()) {
        // Create simple Discord message (plain text, not embed)
        string discordJson = "{\"content\":\"" + EscapeJSONString(message) + "\"}";
        
        if (isAdminOnly) {
            // Admin-only messages go to ADMINS channel only
            SendDiscordMessage(discordJson, false, 0);  // isTradeAlert = false, entryType = 0 (not a trade)
        } else {
            // Non-admin system messages (like News Countdown) go to both PRO and PREMIUM
            if (showDebug) Print("[DISCORD] Sending system message to PRO_USERS and PREMIUM_USERS...");
            SendDiscordWebhook(DISCORD_WEBHOOK_URL_PRO_USERS, discordJson);
            SendDiscordWebhook(DISCORD_WEBHOOK_URL_PREMIUM_USERS, discordJson);
        }
    }
}

//+------------------------------------------------------------------+
//| Check Broker Connection and Trading Permissions                  |
//+------------------------------------------------------------------+
void CheckSystemHealth() {
    // P1 CHECK: Connection loss detection (with startup grace period)
    datetime currentTime = TimeCurrent();
    bool startupGracePeriod = (currentTime - eaStartTime) < 30;  // 30 second grace period
    
    if(!TerminalInfoInteger(TERMINAL_CONNECTED)) {
        if(!startupGracePeriod && currentTime - lastConnectionAlert > 300) {  // Alert every 5 min
            Print("WARNING: DISCONNECTED FROM BROKER!");
            lastConnectionAlert = currentTime;
        }
        return;
    }
    
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
        if(!startupGracePeriod && currentTime - lastConnectionAlert > 300) {
            Print("WARNING: TRADING NOT ALLOWED! Enable AutoTrading button (toolbar) or check EA settings.");
            lastConnectionAlert = currentTime;
        }
        return;  // Don't process any trading logic if trading is disabled
    }
}

//+------------------------------------------------------------------+
//| Unified Health Check - Sends to both Telegram and Discord        |
//| Called from main EA to avoid circular dependency issues          |
//+------------------------------------------------------------------+
void SendUnifiedHealthCheck() {
    // Send Telegram health check (handles timing/interval logic, returns true if sent)
    bool healthCheckSent = SendHealthCheckMessage();
    
    // Send Discord health check only if Telegram health check was actually sent
    if (healthCheckSent && IsDiscordEnabled()) {
        SendDiscordHealthCheck();
    }
}

//+------------------------------------------------------------------+
//| Unified News Countdown - Sends to both Telegram and Discord      |
//| Called from main EA to avoid circular dependency issues          |
//+------------------------------------------------------------------+
void SendUnifiedNewsCountdown() {
    // Send Telegram news countdown (returns message if sent, empty if not)
    string newsMsg = CheckAndSendNewsCountdown();
    
    // Send to Discord if message was sent and Discord is enabled
    if (newsMsg != "" && IsDiscordEnabled()) {
        string discordJson = "{\"content\":\"" + EscapeJSONString(newsMsg) + "\"}";
        // News countdown goes to all user channels (PUBLIC, PRO, PREMIUM)
        if (DISCORD_WEBHOOK_URL_PUBLIC_USERS != "")
            SendDiscordWebhook(DISCORD_WEBHOOK_URL_PUBLIC_USERS, discordJson);
        SendDiscordWebhook(DISCORD_WEBHOOK_URL_PRO_USERS, discordJson);
        SendDiscordWebhook(DISCORD_WEBHOOK_URL_PREMIUM_USERS, discordJson);
    }
}
