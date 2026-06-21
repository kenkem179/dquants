//+------------------------------------------------------------------+
//|                                              NewsCalendar.mqh   |
//|              KenKem EA v1.7.51 - News Filter Functions          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// NEWS CALENDAR FUNCTIONS
// Economic news filtering and avoidance
//================================================================

//+------------------------------------------------------------------+
//| Check if current time is near any important news event          |
//+------------------------------------------------------------------+
bool IsNearImportantNews() {
    if (!ENABLE_NEWS_FILTER) return false;
    
    // BACKTEST MODE: Use local CSV cache (API doesn't work in backtesting)
    if (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
        return IsNearLocalNews();
    }
    
    datetime currentTime = TimeCurrent();
    int bufferBefore = NEWS_MINUTES_BEFORE * 60;
    int bufferAfter = NEWS_MINUTES_AFTER * 60;
    
    for (int i = 0; i < ArraySize(upcomingNews); i++) {
        // Check if we're within the buffer period of this news event
        datetime newsTime = upcomingNews[i].time;
        int timeDiff = (int)(newsTime - currentTime);
        
        // Check if news is within our avoidance window
        if (timeDiff >= -bufferAfter && timeDiff <= bufferBefore) {
            int importance = upcomingNews[i].importance;
            
            // Check if we should avoid this news based on importance
            bool shouldAvoid = false;
            if (importance == 3 && AVOID_HIGH_IMPACT_NEWS) shouldAvoid = true;
            if (importance == 2 && AVOID_MEDIUM_IMPACT_NEWS) shouldAvoid = true;
            
            if (shouldAvoid) {
                if (showDebug) {
                    string impactStr = (importance == 3) ? "HIGH" : "MEDIUM";
                    int minutesUntil = timeDiff / 60;
                    Print("NEWS FILTER: Blocking trade - ", impactStr, " impact ", 
                          upcomingNews[i].currency, " news '", upcomingNews[i].event, 
                          "' in ", minutesUntil, " minutes");
                }
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Update News Events from MT5 Calendar                            |
//+------------------------------------------------------------------+
void UpdateNewsEvents() {
    datetime currentTime = TimeCurrent();
    
    // Only update if enough time has passed since last update
    if (currentTime - lastNewsUpdate < NEWS_UPDATE_INTERVAL) {
        return;
    }
    
    lastNewsUpdate = currentTime;
    ArrayResize(upcomingNews, 0);
    
    // Get news for next 24 hours
    datetime timeFrom = currentTime;
    datetime timeTo = currentTime + 86400; // 24 hours ahead
    
    MqlCalendarValue values[];
    
    string currencies[] = {"USD"};
    int newsCount = 0;
    
    // Get all countries
    MqlCalendarCountry countries[];
    if (CalendarCountries(countries)) {
        // For each relevant country
        for (int c = 0; c < ArraySize(countries); c++) {
            bool isRelevant = false;
            for (int curr = 0; curr < ArraySize(currencies); curr++) {
                if (countries[c].currency == currencies[curr]) {
                    isRelevant = true;
                    break;
                }
            }
            
            if (!isRelevant) continue;
            
            // Get events for this country
            MqlCalendarEvent events[];
            if (CalendarEventByCountry(countries[c].code, events)) {
                // For each event, check if it has upcoming values
                for (int e = 0; e < ArraySize(events); e++) {
                    // Only process medium and high impact events
                    ENUM_CALENDAR_EVENT_IMPORTANCE importance = events[e].importance;
                    int impactLevel = 0;
                    
                    if (importance == CALENDAR_IMPORTANCE_HIGH) impactLevel = 3;
                    else if (importance == CALENDAR_IMPORTANCE_MODERATE) impactLevel = 2;
                    else if (importance == CALENDAR_IMPORTANCE_LOW) impactLevel = 1;
                    
                    if (impactLevel < 2) continue; // Skip low impact
                    
                    // Get upcoming values for this event
                    MqlCalendarValue eventValues[];
                    if (CalendarValueHistoryByEvent(events[e].id, eventValues, timeFrom, timeTo)) {
                        for (int v = 0; v < ArraySize(eventValues); v++) {
                            // Only add future events
                            if (eventValues[v].time >= currentTime && eventValues[v].time <= timeTo) {
                                int newSize = ArraySize(upcomingNews) + 1;
                                ArrayResize(upcomingNews, newSize);
                                
                                upcomingNews[newSize - 1].time = eventValues[v].time;
                                upcomingNews[newSize - 1].currency = countries[c].currency;
                                upcomingNews[newSize - 1].event = events[e].name;
                                upcomingNews[newSize - 1].importance = impactLevel;
                                
                                newsCount++;
                            }
                        }
                    }
                }
            }
        }
        
        if (showDebug) {
            if (newsCount > 0) {
                Print("NEWS FILTER: Loaded ", newsCount, " upcoming high/medium impact news events");
                // Show next 3 upcoming news for verification
                int showCount = MathMin(3, newsCount);
                for (int i = 0; i < showCount; i++) {
                    int minutesUntil = (int)((upcomingNews[i].time - currentTime) / 60);
                    string impactStr = (upcomingNews[i].importance == 3) ? "HIGH" : "MEDIUM";
                    Print("  - ", impactStr, " ", upcomingNews[i].currency, " ", upcomingNews[i].event, " in ", minutesUntil, " minutes");
                }
            }
            // No log when there's no news - reduces noise
        }
    } else {
        if (showDebug) {
            Print("NEWS FILTER: Calendar data not available. Make sure 'News' is enabled in MT5 settings.");
            Print("NEWS FILTER: Go to Tools -> Options -> News and enable news feed.");
        }
    }
}

//+------------------------------------------------------------------+
//| Check and send news countdown alerts                            |
//| Returns the countdown message if sent, empty string otherwise   |
//+------------------------------------------------------------------+
string CheckAndSendNewsCountdown() {
    if (!ENABLE_NEWS_COUNTDOWN_IN_TELEGRAM) return "";
    if (!ENABLE_NEWS_FILTER) return "";
    if (ArraySize(upcomingNews) == 0) return "";
    
    datetime currentTime = TimeCurrent();
    
    // Only alert once per hour to avoid spam
    if (currentTime - lastNewsCountdownAlert < 3600) return "";
    
    // Find next high-impact news
    datetime nextHighImpactTime = 0;
    string nextNewsEvent = "";
    string nextNewsCurrency = "";
    
    for (int i = 0; i < ArraySize(upcomingNews); i++) {
        if (upcomingNews[i].importance == 3 && upcomingNews[i].time > currentTime) {
            if (nextHighImpactTime == 0 || upcomingNews[i].time < nextHighImpactTime) {
                nextHighImpactTime = upcomingNews[i].time;
                nextNewsEvent = upcomingNews[i].event;
                nextNewsCurrency = upcomingNews[i].currency;
            }
        }
    }
    
    if (nextHighImpactTime == 0) return "";
    
    int minutesUntil = (int)((nextHighImpactTime - currentTime) / 60);
    
    // Alert if news is within 60 minutes
    if (minutesUntil > 0 && minutesUntil <= 60) {
        string countdownMsg = "🚨 NEWS COUNTDOWN\n\n";
        countdownMsg += "- HIGH IMPACT: " + nextNewsCurrency + "\n";
        countdownMsg += "- Event: " + nextNewsEvent + "\n";
        countdownMsg += "- In " + IntegerToString(minutesUntil) + " minutes\n";
        countdownMsg += "\n- Trading will be paused " + IntegerToString(NEWS_MINUTES_BEFORE) + " min before";
        
        // Send to Telegram (Discord handled by unified wrapper in SystemAlerts.mqh)
        SendTelegramToUsersOnly(countdownMsg);
        lastNewsCountdownAlert = currentTime;
        
        PrintDebug("NEWS COUNTDOWN: Sent alert for " + nextNewsCurrency + " news in " + IntegerToString(minutesUntil) + " minutes");
        return countdownMsg;  // Return message for Discord to use
    }
    return "";
}

//+------------------------------------------------------------------+
//| Close all positions 10 minutes before high impact news          |
//+------------------------------------------------------------------+
void CloseAllPositionsBeforeHighImpactNews() {
    datetime currentTime = TimeCurrent();
    
    // For backtesting: Use AVOID_NEWS_TRADING flag (no real news calendar available)
    // Check this FIRST before ENABLE_NEWS_FILTER since backtesting doesn't use real news
    if (AVOID_NEWS_TRADING) {
        // Check if we're in US News window (1220-1245 UTC, was 21:20-21:45 JST)
        int currentTimeJST = GetCurrentTimeUTC_HHMM();
        
        // Only process once per 2 minutes to avoid excessive calls
        // Using global variable instead of static to ensure proper reset in backtesting
        if (currentTime - lastNewsAvoidanceCheck < 120) return;
        lastNewsAvoidanceCheck = currentTime;
        
        if (showDebug) {
            //PrintDebug("$$Location 1: NEWS AVOIDANCE CHECK: currentTimeJST=" + IntegerToString(currentTimeJST) + " (window: 2120-2145)");
        }
        
        if (currentTimeJST >= 1220 && currentTimeJST <= 1245) {
            // Prevent closing positions multiple times in the same window
            if (currentTime - lastNewsClosureTime < 300) return;
            
            int closedCount = CloseAllOpenPositions(
                "Closed before US news window (21:20-21:45 JST)",
                "CLOSED_NEWS_AVOIDANCE",
                false
            );
            
            if (closedCount > 0) {
                lastNewsClosureTime = currentTime;
                Print("NEWS AVOIDANCE: Closed ", closedCount, " positions during US News window (21:20-21:45 JST)");
            } else if (showDebug) {
                //PrintDebug("$$Location 3:NEWS AVOIDANCE: No positions to close (already flat or no open trades)");
            }
        }
    }
    
    // BACKTEST MODE: Also check local CSV for additional news events
    if (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) {
        if (!ENABLE_NEWS_FILTER) return;
        
        if (ShouldCloseForLocalNews(currentTime)) {
            if (currentTime - lastNewsClosureTime < 300) return;
            
            datetime newsTime;
            string newsEvent;
            GetNextHighImpactNews(currentTime, newsTime, newsEvent);
            
            string csvCloseReason = "Closed before news: " + newsEvent;
            
            int closedCount = CloseAllOpenPositions(
                csvCloseReason,
                "CLOSED_NEWS_AVOIDANCE",
                false
            );
            
            if (closedCount > 0) {
                lastNewsClosureTime = currentTime;
                int minutesUntil = (int)((newsTime - currentTime) / 60);
                Print("NEWS AVOIDANCE (CSV): Closed ", closedCount, " positions - '", newsEvent, "' in ", minutesUntil, " minutes");
            }
        }
        return;
    }
    
    // For live trading: Use real news calendar
    if (!ENABLE_NEWS_FILTER) return;
    if (!AVOID_HIGH_IMPACT_NEWS) return;
    if (ArraySize(upcomingNews) == 0) return;
    
    datetime nextHighImpactNewsTime = 0;
    string nextNewsEvent = "";
    string nextNewsCurrency = "";
    
    // upcomingNews should be sorted by time, so find first high impact news after current time
    for (int i = 0; i < ArraySize(upcomingNews); i++) {
        if (upcomingNews[i].importance == 3 && upcomingNews[i].time > currentTime) {
            nextHighImpactNewsTime = upcomingNews[i].time;
            nextNewsEvent = upcomingNews[i].event;
            nextNewsCurrency = upcomingNews[i].currency;
            break;  // Found the closest one, no need to continue
        }
    }
    
    // No high impact news found
    if (nextHighImpactNewsTime == 0) return;
    
    int secondsUntilNews = (int)(nextHighImpactNewsTime - currentTime);
    
    // Check if we're within NEWS_MINUTES_BEFORE of the news event
    if (secondsUntilNews > 0 && secondsUntilNews <= NEWS_MINUTES_BEFORE * 60) {
        // Prevent closing positions multiple times for the same news event
        if (currentTime - lastNewsClosureTime < 300) return;
        
        // Build user-friendly closure reason that includes news event name
        string newsCloseReason = "Closed before " + nextNewsCurrency + " news: " + nextNewsEvent;
        
        // Use reusable function to close all positions
        int closedCount = CloseAllOpenPositions(
            newsCloseReason,
            "CLOSED_NEWS_AVOIDANCE",
            false  // Don't send individual debug logs
        );
        
        if (closedCount > 0) {
            lastNewsClosureTime = currentTime;
            
            string alertMsg = "NEWS AVOIDANCE CLOSURE\n\n";
            alertMsg += "Closed " + IntegerToString(closedCount) + " position(s)\n";
            alertMsg += "- HIGH IMPACT: " + nextNewsCurrency + "\n";
            alertMsg += "- Event: " + nextNewsEvent + "\n";
            alertMsg += "- In " + IntegerToString(secondsUntilNews / 60) + " minutes";
            
            SendSystemMessage(alertMsg, true);  // Admin-only summary (per-trade EARLY_EXIT embeds handle user notification)
            
            if (showDebug) {
                Print("NEWS AVOIDANCE: Closed ", closedCount, " positions before ", 
                      nextNewsCurrency, " ", nextNewsEvent, " in ", 
                      (secondsUntilNews / 60), " minutes");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Send EMA Touch/Cross Alert with Momentum Details                 |
//+------------------------------------------------------------------+
// ===== SendEMATouchAlert moved to Alerts/TradeAlerts.mqh =====
