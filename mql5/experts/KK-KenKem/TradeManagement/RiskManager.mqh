#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

// Ensure types and globals are available when this file is parsed
#include "../Core/GlobalState.mqh"
#include "../Utils/Helpers.mqh"
#include "../Entries/EntryBase.mqh"

//================================================================
// RISK MANAGEMENT FUNCTIONS
// Losing streak tracking, entry type blocking, drawdown limits
//================================================================

//+------------------------------------------------------------------+
//| Update Losing Streak Tracking (Global and Per-Entry-Type)       |
//+------------------------------------------------------------------+
void UpdateLosingStreak(string tradeStatus, string tradeType) {
    datetime currentTime = TimeCurrent();
    bool isLoss = (StringFind(tradeStatus, "LOST") >= 0 || StringFind(tradeStatus, "LOSS") >= 0);
    bool isWin = (StringFind(tradeStatus, "WON") >= 0 || StringFind(tradeStatus, "WIN") >= 0);
    
    if (isLoss) {
        // Global consecutive losses (existing logic)
        consecutiveLosses++;
        lastLossTime = currentTime;
        
        if (consecutiveLosses >= 1) {
            double multiplier = (consecutiveLosses >= LOSING_STREAK_ESCALATION_THRESHOLD) ? 2 : 1.5;
            if (!IsWithinDrawdownLimit()) multiplier = multiplier * 1.2;
            losingStreakBlockUntil = currentTime + (datetime)MathFloor(((consecutiveLosses * multiplier) * MIN_SECONDS_BETWEEN_ENTRIES));
        }
        
        // Per-entry-type consecutive losses (NEW)
        if (tradeType == "L-E1") consecutiveLosses_LE1++;
        else if (tradeType == "L-E2") consecutiveLosses_LE2++;
        else if (tradeType == "L-E3") consecutiveLosses_LE3++;
        else if (tradeType == "S-E1") consecutiveLosses_SE1++;
        else if (tradeType == "S-E2") consecutiveLosses_SE2++;
        else if (tradeType == "S-E3") consecutiveLosses_SE3++;
        
        // Block entry type if max consecutive losses reached
        int blockDurationSec = ENTRY_BLOCK_AFTER_CONSECUTIVE_LOSS_MINS * 60;  // Convert minutes to seconds
        if (tradeType == "L-E1" && consecutiveLosses_LE1 >= MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE) 
            blockedUntil_LE1 = currentTime + blockDurationSec;
        else if (tradeType == "L-E2" && consecutiveLosses_LE2 >= MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE) 
            blockedUntil_LE2 = currentTime + blockDurationSec;
        else if (tradeType == "L-E3" && consecutiveLosses_LE3 >= MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE) 
            blockedUntil_LE3 = currentTime + blockDurationSec;
        else if (tradeType == "S-E1" && consecutiveLosses_SE1 >= MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE) 
            blockedUntil_SE1 = currentTime + blockDurationSec;
        else if (tradeType == "S-E2" && consecutiveLosses_SE2 >= MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE) 
            blockedUntil_SE2 = currentTime + blockDurationSec;
        else if (tradeType == "S-E3" && consecutiveLosses_SE3 >= MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE) 
            blockedUntil_SE3 = currentTime + blockDurationSec;
    }
    else if (isWin) {
        // Global consecutive losses reset (existing logic)
        if (consecutiveLosses > 0) {
            consecutiveLosses = consecutiveLosses - 1;
            losingStreakBlockUntil = 0;
        }
        
        // Per-entry-type reset: Win resets OPPOSITE direction types (NEW)
        bool isLong = (StringFind(tradeType, "L-") == 0);
        if (isLong) {
            // Long win resets all SHORT consecutive losses
            consecutiveLosses_SE1 = 0; consecutiveLosses_SE2 = 0; consecutiveLosses_SE3 = 0; consecutiveLosses_SE4 = 0;
            blockedUntil_SE1 = 0; blockedUntil_SE2 = 0; blockedUntil_SE3 = 0; blockedUntil_SE4 = 0;
        } else {
            // Short win resets all LONG consecutive losses
            consecutiveLosses_LE1 = 0; consecutiveLosses_LE2 = 0; consecutiveLosses_LE3 = 0; consecutiveLosses_LE4 = 0;
            blockedUntil_LE1 = 0; blockedUntil_LE2 = 0; blockedUntil_LE3 = 0; blockedUntil_LE4 = 0;
        }
        
        // Winning streak cooldown tracking
        if (ENABLE_WIN_STREAK_COOLDOWN) {
            consecutiveWins++;
            
            // Trigger cooldown after N consecutive wins
            if (consecutiveWins >= WIN_STREAK_COOLDOWN_TRIGGER && !inWinStreakCooldown) {
                inWinStreakCooldown = true;
                winStreakCooldownRemaining = WIN_STREAK_COOLDOWN_TRADES;
                Print("[WIN STREAK COOLDOWN] Triggered after ", consecutiveWins, " wins | Lot reduced to ",
                      DoubleToString(WIN_STREAK_COOLDOWN_LOT_MULT * 100, 0), "% for next ", WIN_STREAK_COOLDOWN_TRADES, " trades");
            }
            
            // Decrement cooldown counter if in cooldown
            if (inWinStreakCooldown) {
                winStreakCooldownRemaining--;
                if (winStreakCooldownRemaining <= 0) {
                    inWinStreakCooldown = false;
                    consecutiveWins = 0;  // Reset streak after cooldown
                    Print("[WIN STREAK COOLDOWN] Ended - normal lot sizing resumed");
                }
            }
        }
    }
    
    // Loss resets consecutive wins
    if (isLoss) {
        consecutiveWins = 0;
        if (inWinStreakCooldown) {
            inWinStreakCooldown = false;
            winStreakCooldownRemaining = 0;
            Print("[WIN STREAK COOLDOWN] Cancelled by loss");
        }
    }
    
    // Recovery Lot Ladder: Update per-entry multiplier on win/loss
    ENTRY_TYPE entryTypeForLadder = GetEntryTypeEnum(tradeType);
    UpdateRecoveryLadder(entryTypeForLadder, isWin);
}

//+------------------------------------------------------------------+
//| Check if Blocked by Global Losing Streak                         |
//+------------------------------------------------------------------+
bool IsBlockedByLosingStreak() {
    datetime currentTime = TimeCurrent();
    
    if (losingStreakBlockUntil > 0 && currentTime < losingStreakBlockUntil) {
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Specific Entry Type is Blocked                          |
//+------------------------------------------------------------------+
bool IsEntryTypeBlocked(string tradeType) {
    datetime currentTime = TimeCurrent();
    
    if (tradeType == "L-E1") {
        if (blockedUntil_LE1 > 0 && currentTime >= blockedUntil_LE1) { consecutiveLosses_LE1 = 0; blockedUntil_LE1 = 0; }
        return (blockedUntil_LE1 > 0 && currentTime < blockedUntil_LE1);
    }
    if (tradeType == "L-E2") {
        if (blockedUntil_LE2 > 0 && currentTime >= blockedUntil_LE2) { consecutiveLosses_LE2 = 0; blockedUntil_LE2 = 0; }
        return (blockedUntil_LE2 > 0 && currentTime < blockedUntil_LE2);
    }
    if (tradeType == "L-E3") {
        if (blockedUntil_LE3 > 0 && currentTime >= blockedUntil_LE3) { consecutiveLosses_LE3 = 0; blockedUntil_LE3 = 0; }
        return (blockedUntil_LE3 > 0 && currentTime < blockedUntil_LE3);
    }
    if (tradeType == "S-E1") {
        if (blockedUntil_SE1 > 0 && currentTime >= blockedUntil_SE1) { consecutiveLosses_SE1 = 0; blockedUntil_SE1 = 0; }
        return (blockedUntil_SE1 > 0 && currentTime < blockedUntil_SE1);
    }
    if (tradeType == "S-E2") {
        if (blockedUntil_SE2 > 0 && currentTime >= blockedUntil_SE2) { consecutiveLosses_SE2 = 0; blockedUntil_SE2 = 0; }
        return (blockedUntil_SE2 > 0 && currentTime < blockedUntil_SE2);
    }
    if (tradeType == "S-E3") {
        if (blockedUntil_SE3 > 0 && currentTime >= blockedUntil_SE3) { consecutiveLosses_SE3 = 0; blockedUntil_SE3 = 0; }
        return (blockedUntil_SE3 > 0 && currentTime < blockedUntil_SE3);
    }
    return false;
}

// Functions ExecutePartialTakeProfit, CalculateTrailingSLForTrade, and UpdateDynamicTPExtension 
// have been moved to TradeManagement/TradeManager.mqh


//+------------------------------------------------------------------+
//| Calculate total risk exposure from all open positions            |
//| Returns: Total risk as a ratio of account balance (0.0 - 1.0)   |
//| Uses STOP LOSS distance, not floating PnL                        |
//+------------------------------------------------------------------+
double CalculateTotalRiskExposure() {
    double totalRiskUSD = 0.0;
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if (currentBalance <= 0) return 0.0;
    
    // Loop through trades array (reliable after partial TP, unlike comment-based search)
    for(int i = 0; i < ArraySize(trades); i++) {
        // Skip if not an active position
        if(trades[i].status != "OPEN") continue;
        if(trades[i].positionTicket == 0) continue;
        
        // Verify position still exists in broker
        if(!PositionSelectByTicket(trades[i].positionTicket)) continue;
        
        // Get current lot size (may have changed after partial TP)
        double currentLots = PositionGetDouble(POSITION_VOLUME);
        
        // Calculate risk based on STOP LOSS distance (not floating PnL)
        // Risk = Distance from entry to SL * Lot Size * Contract Size
        double riskDistance = MathAbs(trades[i].entryPrice - trades[i].stopLoss);
        double positionRiskUSD = riskDistance * currentLots * CONTRACT_SIZE;
        
        totalRiskUSD += positionRiskUSD;
    }

    // Include pending limit order risk in aggregate (risk-budget stacking)
    if (ENABLE_LIMIT_ORDERS) {
        for(int j = 0; j < ArraySize(pendingOrders); j++) {
            if(!pendingOrders[j].isActive) continue;
            double pendingRiskDist = MathAbs(pendingOrders[j].limitPrice - pendingOrders[j].stopLoss);
            totalRiskUSD += pendingRiskDist * pendingOrders[j].lotSize * CONTRACT_SIZE;
        }
    }

    // Return risk as ratio of balance
    return totalRiskUSD / currentBalance;
}

//+------------------------------------------------------------------+
//| Calculate ATR percentile (where current ATR stands vs history)  |
//| Reuses existing g_atrM1Handle for efficiency                    |
//+------------------------------------------------------------------+
double CalculateATRPercentile(double currentATR, int lookback) {
    if (lookback <= 0 || currentATR <= 0) return 50.0;  // Default to middle
    if (g_atrM1Handle == INVALID_HANDLE) return 50.0;   // Handle not ready
    
    double atrValues[];
    ArraySetAsSeries(atrValues, true);
    
    // Reuse existing ATR handle to get historical values
    if (CopyBuffer(g_atrM1Handle, 0, 1, lookback, atrValues) <= 0) {
        return 50.0;  // Failed to copy, default to middle
    }
    
    // Count how many values are below current ATR
    int countBelow = 0;
    int copied = ArraySize(atrValues);
    for (int i = 0; i < copied; i++) {
        if (atrValues[i] < currentATR) countBelow++;
    }
    
    return (double)countBelow / (double)copied * 100.0;
}

//+------------------------------------------------------------------+
//| Check if we can create a new entry (enhanced with P0 checks)    |
//| Returns empty string if allowed, otherwise returns block reason |
//+------------------------------------------------------------------+
string GetEntryBlockReason() {
    datetime currentTime = TimeCurrent();
    
    if (ENABLE_BLACK_SWAN_PROTECTION && BLACKSWAN_BLOCK_COOLDOWN_MINS > 0 && blackSwanBlockedUntil > currentTime) {
        if (showDebug) {
            Print("[BLACK SWAN COOLDOWN] Blocked until: ", TimeToString(blackSwanBlockedUntil, TIME_DATE|TIME_MINUTES));
        }
        return "Black swan cooldown active";
    }
    
    // P0 Check 0: Spread safety (block during news spikes with excessive spread)
    // Uses consecutive bar check to avoid blocking on single-tick spikes
    if (MAX_SPREAD_PIPS > 0 && highSpreadBarCount >= SPREAD_BLOCK_CONSECUTIVE_BARS) {
        if (ENABLE_BLACK_SWAN_PROTECTION && BLACKSWAN_BLOCK_COOLDOWN_MINS > 0 && blackSwanBlockedUntil <= currentTime) {
            blackSwanBlockedUntil = currentTime + (datetime)(BLACKSWAN_BLOCK_COOLDOWN_MINS * 60);
        }
        if(showDebug) {
            Print("[SPREAD BLOCK] High spread for ", highSpreadBarCount, " consecutive bars. ",
                  "Last spread: ", DoubleToString(lastSpreadPips, 1), " pips > max ", 
                  DoubleToString(MAX_SPREAD_PIPS, 1), " pips");
        }
        return "High spread";
    }
    
    // P0 Check 0b: Spread vs ATR ratio (contextual spread check)
    if (MAX_SPREAD_ATR_RATIO > 0 && cache.atrM1 > 0) {
        double atrPips = cache.atrM1 / pipSize;
        double spreadRatio = lastSpreadPips / atrPips;
        if (spreadRatio > MAX_SPREAD_ATR_RATIO) {
            if (ENABLE_BLACK_SWAN_PROTECTION && BLACKSWAN_BLOCK_COOLDOWN_MINS > 0 && blackSwanBlockedUntil <= currentTime) {
                blackSwanBlockedUntil = currentTime + (datetime)(BLACKSWAN_BLOCK_COOLDOWN_MINS * 60);
            }
            if(showDebug) {
                Print("[SPREAD/ATR BLOCK] Spread ", DoubleToString(lastSpreadPips, 1), " pips = ",
                      DoubleToString(spreadRatio * 100, 1), "% of ATR (", DoubleToString(atrPips, 1), 
                      " pips). Max allowed: ", DoubleToString(MAX_SPREAD_ATR_RATIO * 100, 0), "%");
            }
            return "High spread";
        }
    }
    
    // P0 Check 0c: ATR percentile filter (avoid dead or extreme markets)
    // Uses cachedATRPercentile from UpdateIndicatorCache() for performance
    if (ENABLE_BLACK_SWAN_PROTECTION && (ATR_PERCENTILE_LOW > 0 || ATR_PERCENTILE_HIGH > 0)) {
        if (ATR_PERCENTILE_LOW > 0 && cachedATRPercentile < ATR_PERCENTILE_LOW) {
            if(showDebug) {
                Print("[ATR LOW BLOCK] ATR at ", DoubleToString(cachedATRPercentile, 1), 
                      " percentile (min: ", DoubleToString(ATR_PERCENTILE_LOW, 0), "). Market too quiet.");
            }
            return "Market volatility is too low";
        }
        if (ENABLE_ATR_HIGH_BLOCK && ATR_PERCENTILE_HIGH > 0 && cachedATRPercentile > ATR_PERCENTILE_HIGH) {
            if (BLACKSWAN_BLOCK_COOLDOWN_MINS > 0 && blackSwanBlockedUntil <= currentTime) {
                blackSwanBlockedUntil = currentTime + (datetime)(BLACKSWAN_BLOCK_COOLDOWN_MINS * 60);
            }
            if(showDebug) {
                Print("[ATR HIGH BLOCK] ATR at ", DoubleToString(cachedATRPercentile, 1), 
                      " percentile (max: ", DoubleToString(ATR_PERCENTILE_HIGH, 0), "). Market too volatile.");
            }
            return "Market volatility is too high";
        }
    }
    
    // P0 Check 0d: Volatility regime filter - only trade when market is statistically active
    if (MIN_ENTRY_ATR_PERCENTILE > 0 && cachedATRPercentile < MIN_ENTRY_ATR_PERCENTILE) {
        if(showDebug) {
            Print("[VOL REGIME BLOCK] ATR at ", DoubleToString(cachedATRPercentile, 1),
                  " percentile (min: ", DoubleToString(MIN_ENTRY_ATR_PERCENTILE, 0), "). Low volatility regime.");
        }
        return "Low volatility regime";
    }
    
    // P0 Check 1: Daily loss limit
    if(!IsWithinDailyLossLimit()) {
        return "Daily loss limit reached";
    }
    
    // P0 Check 2: Max positions limit
    if(!IsWithinPositionLimit()) {
        return "Max positions limit reached";
    }
    
    // P0 Check 3: Aggregate risk limit
    double currentRiskExposure = CalculateTotalRiskExposure();
    if(currentRiskExposure >= MAX_AGGREGATE_RISK_RATIO) {
        if(showDebug) {
            Print("NEW ENTRY BLOCKED: Total risk exposure ", DoubleToString(currentRiskExposure * 100, 2), 
                  "% exceeds maximum ", DoubleToString(MAX_AGGREGATE_RISK_RATIO * 100, 1), "%");
        }
        return StringFormat("Total risk of open trades are too big %.1f%% >= %.1f%% max", currentRiskExposure * 100, MAX_AGGREGATE_RISK_RATIO * 100);
    }
    
    // Check 4: Time-based prevention (minimum seconds between entries)
    if (lastEntryTime > 0 && (currentTime - lastEntryTime) < MIN_SECONDS_BETWEEN_ENTRIES) {
        return StringFormat("Too soon after last entry (%ds cooldown)", MIN_SECONDS_BETWEEN_ENTRIES);
    }
    
    return "";  // Empty = allowed
}

// Backward compatible wrapper
bool CanCreateNewEntry() {
    return GetEntryBlockReason() == "";
}

// Account-DD reference value. The account-level trailing-DD guard (peak, ddPct,
// hard/soft-block, recovery, profit-floor) measures against THIS. Default = account
// BALANCE (unchanged behavior). When USE_EQUITY_DD_BASIS is ON it switches to
// account EQUITY (includes open positions) so KenKem's prop DD matches the MasterVP
// leg and the shared joint HWM. Per-trade RISK sizing (CalculateTotalRiskExposure)
// is deliberately NOT re-based -- that stays balance-relative.
double AccountDDValue() {
    return USE_EQUITY_DD_BASIS ? AccountInfoDouble(ACCOUNT_EQUITY)
                               : AccountInfoDouble(ACCOUNT_BALANCE);
}

// Profit Protection (High Water Mark) - Protect gains by reducing risk when giving back profits
void CheckProfitProtection() {
    if (!ENABLE_PROFIT_PROTECTION) return;

    double currentBalance = AccountDDValue();   // equity-based when USE_EQUITY_DD_BASIS
    double profitFromInitial = peakAccountBalance - INITIAL_ACCOUNT_BALANCE;
    double minProfitToProtect = INITIAL_ACCOUNT_BALANCE * MIN_PROFIT_TO_PROTECT_RATIO;
    
    // Only activate protection if we have meaningful profit to protect
    if (profitFromInitial < minProfitToProtect) {
        if (inProfitProtectionMode) {
            inProfitProtectionMode = false;
            profitFloor = 0;
            Print("[PROFIT PROTECTION] Deactivated - profit below minimum threshold");
        }
        return;
    }
    
    // Update profit floor when we hit new peak (protect 50% of gains by default)
    if (currentBalance >= peakAccountBalance) {
        double protectedProfit = profitFromInitial * (1.0 - PROFIT_PROTECTION_TRIGGER_RATIO);
        profitFloor = INITIAL_ACCOUNT_BALANCE + protectedProfit;
        
        // Exit protection mode on new peak
        if (inProfitProtectionMode) {
            inProfitProtectionMode = false;
            Print("[PROFIT PROTECTION] Exited - new peak reached at $", DoubleToString(currentBalance, 2));
        }
    }
    
    // Check if we've dropped below profit floor
    if (profitFloor > 0 && currentBalance < profitFloor && !inProfitProtectionMode) {
        inProfitProtectionMode = true;
        
        string msg = "[PROFIT PROTECTION] ACTIVATED\n";
        msg += "Peak: $" + DoubleToString(peakAccountBalance, 2) + "\n";
        msg += "Current: $" + DoubleToString(currentBalance, 2) + "\n";
        msg += "Floor: $" + DoubleToString(profitFloor, 2) + "\n";
        msg += "Lot multiplier: " + DoubleToString(PROFIT_PROTECTION_LOT_MULTIPLIER * 100, 0) + "%\n";
        
        Print(msg);
        SendSystemMessage(msg, true);  // Admin-only
    }
}

// Peak Balance Decay: gradually lower peak toward current balance during recovery mode
// Called once per tick from IsWithinDrawdownLimit(), guarded by time checks internally
void ApplyPeakBalanceDecay(double currentBalance) {
    if (!ENABLE_PEAK_BALANCE_DECAY || !inRecoveryMode) return;
    if (peakAccountBalance <= currentBalance) return;  // No gap to decay
    if (originalPeakAtRecovery <= 0) return;            // Decay not initialized
    
    datetime now = TimeCurrent();
    
    // Grace period: let natural recovery attempt first
    long hoursSincePeakSet = (long)(now - peakBalanceSetTime) / 3600;
    if (hoursSincePeakSet < PEAK_DECAY_GRACE_HOURS) return;
    
    // Interval guard: only decay once per PEAK_DECAY_INTERVAL_HOURS
    if (lastPeakDecayTime > 0) {
        long hoursSinceLastDecay = (long)(now - lastPeakDecayTime) / 3600;
        if (hoursSinceLastDecay < PEAK_DECAY_INTERVAL_HOURS) return;
    }
    
    // Max cap: don't decay more than PEAK_DECAY_MAX_TOTAL of the original gap
    double originalGap = originalPeakAtRecovery - currentBalance;
    if (originalGap <= 0) return;  // Balance recovered past original peak snapshot
    double maxDecayAllowed = originalGap * PEAK_DECAY_MAX_TOTAL;
    double alreadyDecayed = originalPeakAtRecovery - peakAccountBalance;
    if (alreadyDecayed >= maxDecayAllowed) return;  // Cap reached
    
    // Exponential decay: close PEAK_DECAY_RATE of the remaining gap
    double currentGap = peakAccountBalance - currentBalance;
    double decayAmount = currentGap * PEAK_DECAY_RATE;
    
    // Respect max cap
    decayAmount = MathMin(decayAmount, maxDecayAllowed - alreadyDecayed);
    if (decayAmount < 0.01) return;  // Skip negligible amounts
    
    double oldPeak = peakAccountBalance;
    peakAccountBalance -= decayAmount;
    lastPeakDecayTime = now;
    
    double newDDPct = (peakAccountBalance - currentBalance) / peakAccountBalance * 100;
    double totalDecayed = originalPeakAtRecovery - peakAccountBalance;
    double capPct = (maxDecayAllowed > 0) ? (totalDecayed / maxDecayAllowed * 100) : 0;
    
    Print(StringFormat("[PEAK DECAY] $%.2f -> $%.2f (decayed $%.2f) | DD now: %.2f%% | Decay used: %.0f%% of cap",
          oldPeak, peakAccountBalance, decayAmount, newDDPct, capPct));
    SendSystemMessage(StringFormat("PEAK DECAY: $%.0f -> $%.0f | DD: %.1f%% | Cap: %.0f%%",
          oldPeak, peakAccountBalance, newDDPct, capPct), true);
}

// Emergency drawdown protection - Track from account peak balance
bool IsWithinDrawdownLimit() {
    // --- Joint account-level equity HWM (shared with the MasterVP leg) ----------
    // Maintain the account EQUITY high-water mark in the shared COMMON file
    // (KK_PropState_<account>.txt) so it survives restarts and BOTH legs contribute
    // to / read the same joint HWM. KKPropStateSave MAX-merges (never regresses);
    // file I/O is Tester-skipped. See KK-Common/PropState.mqh.
    double eqNow = AccountInfoDouble(ACCOUNT_EQUITY);
    KKPropState ps;
    double sharedPeak = (KKPropStateLoad(ps) ? ps.peakEquity : 0.0);
    // Prop contract-baseline floor (LIVE only): anchor the overall-DD peak at the
    // contract size (e.g. 100000) so a fresh attach on a drawn-down account measures
    // DD from the baseline, not from current equity. Tester-skipped so backtests are
    // unchanged. The HWM still trails UP from here as new peaks print.
    double baselineFloor = (!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION)
                            && PROP_BASELINE_EQUITY > 0.0) ? PROP_BASELINE_EQUITY : 0.0;
    double jointEquityPeak = MathMax(MathMax(sharedPeak, eqNow), baselineFloor);
    if (baselineFloor > 0.0) peakAccountBalance = MathMax(peakAccountBalance, baselineFloor);
    if (USE_EQUITY_DD_BASIS) {
        // Equity basis ON: KenKem's DD anchor IS the joint equity HWM (adopt the
        // higher of the shared HWM and KenKem's own tracked peak). Everything below
        // (ddPct, hard/soft-block, recovery, decay, profit-floor) then runs on
        // equity automatically because they derive from peakAccountBalance + the
        // AccountDDValue() reference.
        peakAccountBalance = MathMax(peakAccountBalance, jointEquityPeak);
        jointEquityPeak = peakAccountBalance;
    }
    // Write the joint HWM back (both legs maintain it; MAX-merged in Save).
    KKPropState w;
    w.peakEquity = jointEquityPeak; w.dayStartEquity = eqNow; w.dayPeakEquity = eqNow; w.dayKey = -1;
    KKPropStateSave(w);

    // DD reference value: BALANCE (default) or EQUITY (when USE_EQUITY_DD_BASIS).
    double currentBalance = AccountDDValue();

    // Check profit protection (runs every tick, lightweight)
    CheckProfitProtection();
    
    // Update peak balance ONLY if we've reached a new HIGH (never reset downwards)
    if (currentBalance > peakAccountBalance) {
        peakAccountBalance = currentBalance;
        
        // Check if we've recovered from drawdown (new peak means ddPct = 0, always exits)
        if (inRecoveryMode) {
            inRecoveryMode = false;
            ExitRecoveryLadders();  // Reset to full lots
            Print("RECOVERY MODE ENDED: Balance recovered to $", DoubleToString(currentBalance, 2), 
                  " (new peak). Normal lot sizing resumed.");
            SendSystemMessage("RECOVERY MODE ENDED - Balance recovered. Normal trading resumed.", true);  // Admin-only
        }
    }
    
    // Initialize peak on first run
    if (peakAccountBalance <= 0.0) {
        peakAccountBalance = currentBalance;
        return true;
    }
    
    // Apply gradual peak decay during recovery (time-guarded internally)
    ApplyPeakBalanceDecay(currentBalance);
    
    // Calculate drawdown from peak balance (may have been decayed above)
    double loss = peakAccountBalance - currentBalance;
    double ddPct = loss / peakAccountBalance;
    
    // PROP HARD BLOCK: When trading prop accounts, halt ALL trading at soft block threshold
    // Prop firms terminate accounts that keep trading during extreme DD
    if (MADE_FOR_PROP_TRADING && ddPct >= ACCOUNT_DD_RATIO_TO_SOFT_BLOCK) {
        if (!inPropHardBlock) {
            inPropHardBlock = true;
            string alertMsg = "PROP HARD BLOCK: ALL TRADING HALTED\n\n";
            alertMsg += "Drawdown: " + DoubleToString(ddPct * 100, 2) + "%\n";
            alertMsg += "Threshold: " + DoubleToString(ACCOUNT_DD_RATIO_TO_SOFT_BLOCK * 100, 1) + "%\n";
            alertMsg += "ALL TRADING STOPPED to protect prop account.";
            Print(alertMsg);
            SendSystemMessage(alertMsg, true);
            Print("[PROP HARD BLOCK] Drawdown ", DoubleToString(ddPct * 100, 2), "% >= ",
                  DoubleToString(ACCOUNT_DD_RATIO_TO_SOFT_BLOCK * 100, 1), "% - ZERO TRADING");
        }
        return false;  // Block ALL entries
    }
    // Exit prop hard block if DD recovered below threshold
    if (inPropHardBlock && ddPct < ACCOUNT_DD_RATIO_TO_SOFT_BLOCK) {
        inPropHardBlock = false;
        Print("[PROP HARD BLOCK] Exited - Drawdown recovered to ", DoubleToString(ddPct * 100, 2), "%");
    }

    // SOFT BLOCK: If DD exceeds threshold, allow micro-lot trading to recover
    // (Hard block kills the bot forever - soft block gives recovery chance)
    if (ddPct >= ACCOUNT_DD_RATIO_TO_SOFT_BLOCK) {
        if (!inSoftBlockMode) {
            double softBlockMult = SOFT_BLOCK_LOT_MULTIPLIER;  // Use dedicated soft block multiplier
            string alertMsg = "SOFT BLOCK: EXTREME DRAWDOWN REACHED\n\n";
            alertMsg += "Drawdown: " + DoubleToString(ddPct * 100, 2) + "%\n";
            alertMsg += "Threshold: " + DoubleToString(ACCOUNT_DD_RATIO_TO_SOFT_BLOCK * 100, 1) + "%\n";
            alertMsg += "Trading continues with MICRO LOTS (" + DoubleToString(softBlockMult * 100, 0) + "%)";
            Print(alertMsg);
            SendSystemMessage(alertMsg, true);  // Admin-only
            Print("[SOFT BLOCK] Drawdown ", DoubleToString(ddPct * 100, 2), "% >= ", 
                  DoubleToString(ACCOUNT_DD_RATIO_TO_SOFT_BLOCK * 100, 1), "% - MICRO LOT MODE");
            inSoftBlockMode = true;
            inRecoveryMode = true;  // Also ensure recovery mode is on
            ResetRecoveryLadders();
            // Snapshot for peak decay (only if not already set by earlier recovery entry)
            if (originalPeakAtRecovery <= 0) {
                originalPeakAtRecovery = peakAccountBalance;
                peakBalanceSetTime = TimeCurrent();
            }
        }
        return true;  // Allow trading with micro lots (applied in GetRecoveryModeLotMultiplier)
    }
    
    // Exit soft block mode if DD recovered below threshold
    if (inSoftBlockMode && ddPct < ACCOUNT_DD_RATIO_TO_SOFT_BLOCK) {
        inSoftBlockMode = false;
        Print("[SOFT BLOCK] Exited - Drawdown recovered to ", DoubleToString(ddPct * 100, 2), "%");
    }
    
    // Check if we should exit recovery mode (balance improved significantly)
    // Exit when drawdown drops to EXIT_RATIO of the trigger threshold (exit earlier than entry)
    double recoveryTriggerThreshold = ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN * RECOVERY_MODE_TRIGGER_RATIO;
    double recoveryExitThreshold = recoveryTriggerThreshold * RECOVERY_MODE_EXIT_RATIO;
    if (inRecoveryMode && ddPct < recoveryExitThreshold) {
        inRecoveryMode = false;
        ExitRecoveryLadders();  // Reset to full lots
        Print("RECOVERY MODE ENDED: Drawdown reduced to ", DoubleToString(ddPct * 100, 2), 
              "% (exit threshold: ", DoubleToString(recoveryExitThreshold * 100, 1), "%)");
        SendSystemMessage("RECOVERY MODE ENDED - Drawdown: " + DoubleToString(ddPct * 100, 2) + "% - Normal trading resumed.", true);  // Admin-only
    }
    
    // If already blocked for today, stay blocked
    if (drawdownTriggered) {
        return false;
    }
    
    // Calculate early warning threshold (e.g., 85% of 9% = 7.65%)
    // Note: recoveryTriggerThreshold already calculated above for exit check
    
    // STAGE 1: Early warning - activate recovery mode (reduced lots) but keep trading
    if (!inRecoveryMode && ddPct >= recoveryTriggerThreshold && ddPct < ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN) {
        inRecoveryMode = true;
        ResetRecoveryLadders();  // Start at minimum lot multiplier
        // Snapshot for peak decay
        originalPeakAtRecovery = peakAccountBalance;
        peakBalanceSetTime = TimeCurrent();
        
        string warningMsg = "DRAWDOWN WARNING - RECOVERY MODE ACTIVATED\n\n";
        warningMsg += "Drawdown: " + DoubleToString(ddPct * 100, 2) + "%\n";
        warningMsg += "Warning Threshold: " + DoubleToString(recoveryTriggerThreshold * 100, 1) + "%\n";
        warningMsg += "Block Threshold: " + DoubleToString(ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN * 100, 1) + "%\n\n";
        warningMsg += "Lot size reduced to " + DoubleToString(RECOVERY_MODE_LOT_MULTIPLIER * 100, 0) + "%\n";
        warningMsg += "Trading continues with reduced risk";
        
        Print(warningMsg);
        SendSystemMessage(warningMsg, true);  // Admin-only
        
        Print("DRAWDOWN WARNING: ", DoubleToString(ddPct * 100, 2), "% (trigger: ", 
              DoubleToString(recoveryTriggerThreshold * 100, 1), "%) | RECOVERY MODE ON | Trading continues");
    }
    
    // STAGE 2: Max drawdown - block entries until end of day
    // CRITICAL: Only block on FIRST breach, NOT on subsequent days while in recovery mode
    // After the initial block, recovery mode allows trading with reduced lots to recover
    if (ddPct > ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN && !inRecoveryMode) {
        // Calculate end of current trading day (23:59:59)
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        dt.hour = 23;
        dt.min = 59;
        dt.sec = 59;
        drawdownBlockedUntil = StructToTime(dt);
        
        drawdownTriggered = true;
        inRecoveryMode = true;  // Enter recovery mode
        ResetRecoveryLadders();  // Start at minimum lot multiplier
        // Snapshot for peak decay (only if not already set by STAGE 1)
        if (originalPeakAtRecovery <= 0) {
            originalPeakAtRecovery = peakAccountBalance;
            peakBalanceSetTime = TimeCurrent();
        }
        
        // Peak balance preserved (no instant reset) to prevent cascading drawdowns
        // Peak decay (if enabled) will gradually ease it over time
        
        string alertMsg = "MAXIMUM DRAWDOWN LIMIT REACHED\n\n";
        alertMsg += "Drawdown: " + DoubleToString(ddPct * 100, 2) + "% from peak\n";
        alertMsg += "Peak: $" + DoubleToString(peakAccountBalance, 2) + "\n";
        alertMsg += "Current: $" + DoubleToString(currentBalance, 2) + "\n";
        alertMsg += "Threshold: " + DoubleToString(ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN * 100, 1) + "%\n\n";
        alertMsg += "PEAK NOT RESET - must recover to $" + DoubleToString(peakAccountBalance, 2) + "\n";
        alertMsg += "NEW ENTRIES BLOCKED UNTIL END OF DAY\n";
        alertMsg += "RECOVERY MODE ACTIVE (" + DoubleToString(RECOVERY_MODE_LOT_MULTIPLIER * 100, 0) + "% lot size)\n";
        alertMsg += "Tomorrow: Trading resumes with reduced lot size until recovery";
        
        Print(alertMsg);
        SendSystemMessage(alertMsg, true);  // Admin-only
        
        Print("MAX DRAWDOWN LIMIT: ", DoubleToString(ddPct * 100, 2), "% from peak $",
              DoubleToString(peakAccountBalance, 2), " | Current: $", DoubleToString(currentBalance, 2),
              " | BLOCKED UNTIL END OF DAY | RECOVERY MODE ON");
        
        return false;
    }
    
    // If already in recovery mode and DD still above threshold, ALLOW TRADING with reduced lots
    // This is the key fix - don't re-block, let the bot trade to recover
    return true;
}

// Returns true if entries should be blocked due to drawdown protection
// Blocks until end of day, NEVER resets peak balance
bool IsDrawdownBlocked() {
    if (!drawdownTriggered)
        return false;
    
    datetime currentTime = TimeCurrent();
    
    // Check if we've passed end of day (new trading day)
    if (currentTime > drawdownBlockedUntil) {
        // New day - allow trading again but STAY IN RECOVERY MODE
        // Peak balance is NEVER reset - must earn way back
        drawdownTriggered = false;
        drawdownBlockedUntil = 0;
        
        // Note: No alerts here - just silently lift the block
        // If DD is still above threshold, IsWithinDrawdownLimit() will re-block
        // with a quiet log message (no spam alerts)
        
        return false;  // Allow trading (with reduced lots if in recovery)
    }
    
    // Still blocked for today
    return true;
}

// Get lot size multiplier based on recovery mode, profit protection, and win streak cooldown
// Returns the most conservative (lowest) multiplier
double GetRecoveryModeLotMultiplier() {
    double multiplier = 1.0;
    
    // PROP HARD BLOCK: Zero trading (return 0 to block lot calculation upstream)
    if (inPropHardBlock) {
        return 0.0;
    }
    
    // SOFT BLOCK: Extreme DD - micro lot mode (most aggressive, takes priority)
    if (inSoftBlockMode) {
        double softBlockMult = SOFT_BLOCK_LOT_MULTIPLIER;  // 1/5 of normal (20%)
        return softBlockMult;  // Override all other multipliers
    }
    
    // Profit protection multiplier (if active)
    if (inProfitProtectionMode) {
        multiplier = MathMin(multiplier, PROFIT_PROTECTION_LOT_MULTIPLIER);
    }
    
    // Recovery mode multiplier (if active)
    if (inRecoveryMode) {
        multiplier = MathMin(multiplier, RECOVERY_MODE_LOT_MULTIPLIER);
    }
    
    // Win streak cooldown multiplier (if active)
    if (inWinStreakCooldown) {
        multiplier = MathMin(multiplier, WIN_STREAK_COOLDOWN_LOT_MULT);
    }
    
    return multiplier;
}

// Check if currently in recovery mode
bool IsInRecoveryMode() {
    return inRecoveryMode;
}

// Check if currently in profit protection mode
bool IsInProfitProtectionMode() {
    return inProfitProtectionMode;
}

// Check if currently in soft block mode
bool IsInSoftBlockMode() {
    return inSoftBlockMode;
}

// Check if in any protection mode (for signal-only behavior)
// Returns true if: Max Daily Drawdown blocked, Recovery mode, or Soft block
bool IsInProtectionMode() {
    return inRecoveryMode || inSoftBlockMode || inPropHardBlock || IsDrawdownBlocked();
}

// Get protection mode reason string for alerts
string GetProtectionModeReason() {
    if (inPropHardBlock) return "Prop Hard Block (Trading Halted)";
    if (IsDrawdownBlocked()) return "Max Daily Drawdown";
    if (inSoftBlockMode) return "Soft Block (Extreme DD)";
    if (inRecoveryMode) return "Recovery Mode";
    return "";
}
#endif // RISK_MANAGER_MQH
