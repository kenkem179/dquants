//+------------------------------------------------------------------+
//|                                              SessionManager.mqh |
//|           KenKem EA v1.7.51 - Session & Time Management         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// SESSION & TIME MANAGEMENT FUNCTIONS
// Time conversion, session detection, and validation
//================================================================

// Session windows are defined in UTC (see Config/InputParams.mqh). TimeGMT() is UTC and is
// broker-agnostic, so we compare its HHMM directly against the UTC windows — no timezone offset.
// (Historically these windows were JST=UTC+9; they were converted to UTC so the dquants C++ engine
//  and this EA use one identical clock. JST 0900/1230/1400/1830/2100/2400 -> UTC 0000/0330/0500/0930/1200/1500.)
int GetCurrentTimeUTC_HHMM(){
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    return(dt.hour*100+dt.min);
}

// Identity pass-through: in UTC none of the KenKem sessions cross midnight (latest end is 1500 UTC),
// so the legacy after-midnight (+2400) remap is no longer needed. Kept as a named helper so the
// session-boundary call sites below read unchanged.
int IsTimeInValidSession(int t)
{
    return t;
}

//+------------------------------------------------------------------+
//| Check if current time is at session end                         |
//+------------------------------------------------------------------+
bool IsAtSessionEnd()
{
    int currentJST = GetCurrentTimeUTC_HHMM();
    int adjustedTime = IsTimeInValidSession(currentJST);
    int adjustedNyEnd = IsTimeInValidSession(NY_END);
    
    // Check if we're at US session end time (within 1 minute tolerance)
    return (MathAbs(adjustedTime - adjustedNyEnd) <= 1);
}


//+------------------------------------------------------------------+
//| Check if we're in the last 5 minutes of US session (block entries)|
//+------------------------------------------------------------------+
bool IsInLastFiveMinutesOfUSSession() {
    int currentJST = GetCurrentTimeUTC_HHMM();
    int adjustedTime = IsTimeInValidSession(currentJST);
    int adjustedNYEnd = IsTimeInValidSession(NY_END);
    return adjustedTime >= (adjustedNYEnd - 5);
}


// Get current trading session name
string GetCurrentSession() {
    int currentJST = GetCurrentTimeUTC_HHMM();
    int adjustedTime = IsTimeInValidSession(currentJST);
    
    if(adjustedTime >= JAPAN_START && adjustedTime <= JAPAN_END)
        return "ASIA";
    else if(adjustedTime >= LONDON_START && adjustedTime <= LONDON_END)
        return "EU";
    else if(adjustedTime >= NY_START && adjustedTime <= NY_END)
        return "US";
    
    return "NONE";
}

// Get session-aware TP multiplier for high-risk trades
double GetHighRiskTPMultiplier() {
    string session = GetCurrentSession();
    
    if (session == "ASIA") {
        return HIGH_RISK_TP_MULTIPLIER_ASIA;  // Conservative - low volatility
    }
    else if (session == "EU") {
        return HIGH_RISK_TP_MULTIPLIER_EU;    // Baseline - moderate volatility
    }
    else if (session == "US") {
        return HIGH_RISK_TP_MULTIPLIER_US;    // Aggressive - high volatility
    }
    
    return HIGH_RISK_TP_MULTIPLIER_EU;  // Default fallback to EU baseline
}

// Get dynamic RR multiplier based on ATR percentile and session
double GetDynamicRRMultiplier() {
    if (!USE_DYNAMIC_RR_SCALING) return 1.0;
    
    double sessionMult = 1.0;
    string session = GetCurrentSession();
    
    if (session == "ASIA") {
        sessionMult = 0.95;
    } else if (session == "US") {
        sessionMult = 1.15;
    }
    
    double atrMult = 1.0;
    if (cachedATRPercentile >= 75.0) {
        atrMult = 1.12;
    } else if (cachedATRPercentile <= 25.0) {
        atrMult = 0.88;
    }
    
    double finalMult = sessionMult * atrMult;
    
    return MathMax(0.70, MathMin(1.30, finalMult));
}

// Check if current time is in valid session with midnight conversion
bool IsNowInValidSession() {
    if (IGNORE_VALID_SESSIONS)
        return true;
        
    int currentUTC = GetCurrentTimeUTC_HHMM();

    // Legacy: Block trading during US news period (1220-1245 UTC, was 2120-2145 JST)
    if (AVOID_NEWS_TRADING && currentUTC >= 1220 && currentUTC <= 1245)
        return false;

    // New: Check economic calendar for important news
    if (IsNearImportantNews())
        return false;

    int adjustedTime = IsTimeInValidSession(currentUTC);

    // Check Japan session (0000-0330 UTC)
    if (adjustedTime >= JAPAN_START && adjustedTime <= JAPAN_END)
        return true;

    // Check London session (0500-0930 UTC)
    if (adjustedTime >= LONDON_START && adjustedTime <= LONDON_END)
        return true;

    // Check NY session (1200-1500 UTC)
    if (adjustedTime >= NY_START && adjustedTime <= NY_END)
        return true;
        
    return false;
}

//+------------------------------------------------------------------+
//| Check daily loss limit (P0 protection)                          |
//+------------------------------------------------------------------+
bool IsWithinDailyLossLimit() {
    datetime today = iTime(_Symbol, PERIOD_D1, 0);
    
    // Reset daily tracking on new day
    if(today != currentDate) {
        currentDate = today;
        dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        dailyLossLimitReached = false;
        
        // Note: peakAccountBalance is NOT reset daily - it tracks lifetime peak for drawdown protection
        // Drawdown uses cooldown (DRAWDOWN_COOLDOWN_MIN) instead of daily reset
        
        if(showDebug) {
            Print("NEW DAY RESET: Daily start balance = $", DoubleToString(dailyStartBalance, 2),
                  " | Peak balance: $", DoubleToString(peakAccountBalance, 2), " (lifetime tracking)");
        }
    }
    
    // Check if already hit limit today
    if(dailyLossLimitReached) {
        return false;
    }
    
    // Calculate daily loss
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dailyLoss = dailyStartBalance - currentBalance;
    double lossPercent = dailyLoss / dailyStartBalance;
    
    if(lossPercent >= MAX_DAILY_LOSS_RATIO) {
        dailyLossLimitReached = true;
        
        string alertMsg = "MAXIMUM DAILY LOSS LIMIT REACHED\n\n";
        alertMsg += "Daily Loss: " + DoubleToString(lossPercent * 100, 2) + "%\n";
        alertMsg += "Start Balance: $" + DoubleToString(dailyStartBalance, 2) + "\n";
        alertMsg += "Current Balance: $" + DoubleToString(currentBalance, 2) + "\n";
        alertMsg += "Loss Amount: $" + DoubleToString(dailyLoss, 2) + "\n";
        alertMsg += "Threshold: " + DoubleToString(MAX_DAILY_LOSS_RATIO * 100, 1) + "%\n\n";
        alertMsg += "NEW ENTRIES BLOCKED UNTIL TOMORROW\n";
        alertMsg += "Existing positions will run their course with SL/TP";
        
        Print(alertMsg);
        SendSystemMessage(alertMsg, true);  // Admin-only
        
        Print("MAX DAILY LOSS LIMIT: ", DoubleToString(lossPercent * 100, 2), "% daily loss | NEW ENTRIES BLOCKED UNTIL NEXT DAY");
        
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if we're in the weekend window where health checks pause   |
//| Window (UTC): from 1h after US session end on Friday             |
//|           until 1h before Japan session start on Monday          |
//+------------------------------------------------------------------+
bool IsInHealthCheckWeekendBlock() {
    // Work purely in UTC using TimeGMT() and the (now UTC) session inputs
    datetime utcNow = TimeGMT();
    MqlDateTime dt;
    TimeToStruct(utcNow, dt);
    int dow = dt.day_of_week;  // 0=Sunday, 1=Monday, ..., 5=Friday, 6=Saturday

    int currentJST = dt.hour * 100 + dt.min;
    int adjustedTime = IsTimeInValidSession(currentJST);
    int adjustedNyEndPlus1h = IsTimeInValidSession(NY_END + 100);
    int adjustedJapanStartMinus1h = IsTimeInValidSession(JAPAN_START - 100);

    // Friday -> Saturday: block after US session end + 1h (which falls on Sat early morning JST)
    if (dow == 5) {
        if (adjustedTime >= adjustedNyEndPlus1h) {
            return true;
        }
        return false;
    }

    // Other time on Saturday or Sunday: always block
    if (dow == 6 || dow == 0) {
        return true;
    }

    // Monday: block until 1h before Japan session start
    if (dow == 1) { // Monday
        if (adjustedTime <= adjustedJapanStartMinus1h) {
            return true;
        }
        return false;
    }

    // Other weekdays: never block
    return false;
}

//+------------------------------------------------------------------+
//| Check max positions limit (P0 protection)                       |
//+------------------------------------------------------------------+
bool IsWithinPositionLimit() {
    int openPositions = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(StringFind(PositionGetString(POSITION_COMMENT), "KenKemST") >= 0) {
                openPositions++;
            }
        }
    }
    
    if(openPositions >= MAX_CONCURRENT_POSITIONS_ALLOWED) {
        PrintDebug("Position limit reached: " + IntegerToString(openPositions) + "/" + IntegerToString(MAX_CONCURRENT_POSITIONS_ALLOWED));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if any open position opposes the proposed entry direction  |
//| Returns: true if opposing position exists, false if safe         |
//| CRITICAL: Prevents hedged positions that cancel profits          |
//+------------------------------------------------------------------+
bool HasOpposingDirectionPosition(bool proposedIsLong) {
    if (!BLOCK_OPPOSITE_DIRECTION_ENTRIES) return false;
    
    for (int i = 0; i < ArraySize(trades); i++) {
        if (trades[i].status != "OPEN") continue;
        if (trades[i].positionTicket == 0) continue;
        
        // Verify position still exists on broker
        if (!PositionSelectByTicket(trades[i].positionTicket)) continue;
        
        // Check if direction opposes the proposed entry
        if (trades[i].isLong != proposedIsLong) {
            if (showDebug) {
                Print("[DIRECTION BLOCK] Cannot enter ", (proposedIsLong ? "LONG" : "SHORT"),
                      " - opposing ", trades[i].type, " position active (ticket: ", trades[i].positionTicket, ")");
            }
            return true;  // Found opposing position
        }
    }
    
    return false;  // No opposing positions
}

//+------------------------------------------------------------------+
//| Get current position direction bias (for entry coordination)     |
//| Returns: 1 = LONG bias, -1 = SHORT bias, 0 = no positions        |
//+------------------------------------------------------------------+
int GetCurrentDirectionBias() {
    int longCount = 0;
    int shortCount = 0;
    
    for (int i = 0; i < ArraySize(trades); i++) {
        if (trades[i].status != "OPEN") continue;
        if (trades[i].positionTicket == 0) continue;
        if (!PositionSelectByTicket(trades[i].positionTicket)) continue;
        
        if (trades[i].isLong) longCount++;
        else shortCount++;
    }
    
    if (longCount > 0 && shortCount == 0) return 1;   // LONG bias
    if (shortCount > 0 && longCount == 0) return -1;  // SHORT bias
    return 0;  // No positions or mixed (shouldn't happen with blocking enabled)
}


void UpdateSessionTracking() {
    string newSession = getCurrentTradingSession();
    
    // Check if session has changed
    if (newSession != currentSession && newSession != "NONE") {
        // Flush CSV buffer at session end (before resetting counters)
        if (ENABLE_CSV_EXPORT && currentSession != "") {
            FlushCSVBuffer();
        }
        
        currentSession = newSession;
        
        // Reset all session counters at the beginning of each new session
        tradeSLTPCountInSession = 0;
        sessionLossCount = 0;
        sessionWinCount = 0;
        sessionBreakEvenCount = 0;
        highRiskTradesInSession = 0;
    }
}

//+------------------------------------------------------------------+
//| Close all open positions with specified reason                  |
//+------------------------------------------------------------------+
int CloseAllOpenPositions(string closureReason, string statusUpdate, bool sendDebugLog = true) {
    int closedCount = 0;
    
    for (int i = 0; i < ArraySize(trades); i++) {
        if (trades[i].status == "OPEN" && trades[i].positionTicket > 0) {
            if (PositionSelectByTicket(trades[i].positionTicket)) {
                // Capture exit price BEFORE close (current market price)
                double actualExitPrice = trades[i].isLong ? 
                    SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                double actualPnLPips = trades[i].isLong ? 
                    (actualExitPrice - trades[i].entryPrice) / pipSize :
                    (trades[i].entryPrice - actualExitPrice) / pipSize;
                
                if (SafePositionClose(trades[i].positionTicket, "SESSION CLOSE")) {
                    trades[i].status = statusUpdate;
                    trades[i].earlyExitAlertSent = true;
                    closedCount++;
                    
                    // Send EARLY_EXIT alert with actual P&L
                    SendAlertForTrade(
                        EMAIL_SUBJECT_PREFIX + " - " + closureReason,
                        closureReason,
                        trades[i],
                        "EARLY_EXIT",
                        closureReason,
                        actualExitPrice,
                        actualPnLPips);
                    
                    if (sendDebugLog && showDebug) {
                        Print(closureReason, ": Closed position ", trades[i].id, 
                              " (Ticket: ", trades[i].positionTicket, ") PnL: ", 
                              DoubleToString(actualPnLPips, 1), " pips");
                    }
                }
            }
        }
    }
    
    return closedCount;
}

//+------------------------------------------------------------------+
//| Close all open trades at session end                            |
//+------------------------------------------------------------------+
void CloseAllTradesAtSessionEnd() {
    if (!CLOSE_ALL_TRADES_AT_SESSION_END)
        return;

    if (!IsAtSessionEnd())
        return;
    
    int closedCount = CloseAllOpenPositions(
        "SESSION_END",
        "CLOSED_SESSION_END",
        true
    );
    
    if (closedCount > 0) {
        PrintDebug("All trades closed at session end at JST: " + IntegerToString(GetCurrentTimeUTC_HHMM()));
    }
}
