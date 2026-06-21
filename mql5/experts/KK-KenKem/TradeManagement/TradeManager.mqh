//+------------------------------------------------------------------+
//| TradeManager.mqh - Centralized Trade Management                  |
//| Phase 1.2: OOP Foundation - Trade Operations                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef TRADEMANAGER_MQH
#define TRADEMANAGER_MQH

#include "../Core/GlobalState.mqh"
#include "../Utils/Helpers.mqh"
#include "../Entries/EntryBase.mqh"
#include "../Entries/EntryHelpers.mqh"
#include "../Utils/BrokerHelpers.mqh"
#include "RiskManager.mqh"

//+------------------------------------------------------------------+
//| TradeManager: Centralized trade lifecycle management            |
//| Replaces ProcessExistingTrades() with modular methods            |
//+------------------------------------------------------------------+
class TradeManager {
private:
    // State variables (was function-local statics - now reset properly on EA init)
    datetime m_lastQualityCheckBarTime;
    int m_brokerCheckCounter;
    datetime m_lastDebugTime;
    
    // Helper: Check if trade has retraced significantly from peak (for Smart Partial TP)
    bool HasSignificantRetrace(Trade &t, double retraceRatio) {
        double peak = t.bestPriceSinceEligible;
        double current = cache.currentPrice;
        double gained = t.isLong ? (peak - t.entryPrice) : (t.entryPrice - peak);
        double retrace = t.isLong ? (peak - current) : (current - peak);
        return (gained > 0) && (retrace / gained >= retraceRatio);
    }
    
    // Helper to close trade by ticket
    void CloseTradeByTicket(ulong positionTicket, string tradeID) {
        if(positionTicket <= 0) {
            if(showDebug) Print("CloseTradeByTicket ERROR: Invalid ticket for ", tradeID);
            return;
        }
        
        if (PositionSelectByTicket(positionTicket)) {
            // Use PositionClose instead of creating opposite positions
            if (SafePositionClose(positionTicket, "CloseTradeByTicket")) {
                //PrintDebug("Successfully closed position: " + IntegerToString(positionTicket) + " for trade " + tradeID);
            } else {
                Print("ERROR: Failed to close position ", positionTicket, " - Error: ", trade.ResultRetcode());
            }
        } else {
            if(showDebug) Print("CloseTradeByTicket ERROR: Position not found for ticket #", positionTicket);
        }
    }

public:
    //--------------------------------------------------------------------
    // Constructor / Destructor
    //--------------------------------------------------------------------
    TradeManager() {
        // Reset all state variables to ensure clean start for each backtest run
        m_lastQualityCheckBarTime = 0;
        m_brokerCheckCounter = 0;
        m_lastDebugTime = 0;
        if(showDebug) Print("[TradeManager] Initialized with clean state");
    }
    
    ~TradeManager() {
        if(showDebug) Print("[TradeManager] Destroyed");
    }
    
    //--------------------------------------------------------------------
    // MAIN PROCESSING (replaces ProcessExistingTrades)
    //--------------------------------------------------------------------
    void ProcessAllTrades() {
        // PERFORMANCE: Early exit if no trades to process
        int tradeCount = ArraySize(trades);
        if (tradeCount == 0) return;
        
        // PERFORMANCE: Quick scan for any OPEN trades (not SKIPPED)
        // If all trades are SKIPPED, skip the expensive Phase 1 processing
        bool hasOpenTrades = false;
        for (int i = tradeCount - 1; i >= 0; i--) {
            if (trades[i].status == "OPEN") {
                hasOpenTrades = true;
                break;  // Found one, no need to continue
            }
        }
        
        // If no open trades, skip all Phase 1 processing (huge speedup in backtest)
        if (!hasOpenTrades) return;
        
        // STEP 4: No need to call UpdateIndicatorCache() here - already called once in OnTick()
        // All functions use cached values from the single call at OnTick() start
        double currentPrice = cache.currentPrice;
        double high = cache.high;
        double low = cache.low;
        
        // Bar-based gate for quality-drop exit (count checks per M1 bar, not per tick)
        datetime currentBarTimeForQuality = iTime(_Symbol, TF_ARRAY[TF0], 0);
        bool allowQualityDropCheck = false;
        if (currentBarTimeForQuality != m_lastQualityCheckBarTime) {
            m_lastQualityCheckBarTime = currentBarTimeForQuality;
            allowQualityDropCheck = true;
        }
        
        // ========================================
        // PHASE 1: REAL TRADES ONLY (CRITICAL PATH - HIGHEST PRIORITY)
        // ========================================
        // First pass: Remove closed real trades and skip virtual trades
        for (int i = ArraySize(trades) - 1; i >= 0; i--) {
            // SAFETY: Validate index at loop start
            if (i >= ArraySize(trades)) continue;
            
            // Skip virtual trades in Phase 1 - they'll be processed in Phase 2
            string currentStatus = trades[i].status;
            if(StringFind(currentStatus, "SKIPPED") >= 0) continue;  // Skip all SKIPPED* statuses
            
            // skip early‑exit on entry bar (TV rule)
            int barsSinceEntry = (Bars(_Symbol, TF_ARRAY[TF0]) - 1) - trades[i].entryBar;
            if(barsSinceEntry==0) continue;

            string newStatus = currentStatus;
            
            // CLEANUP: Remove trades that are already closed to prevent repeated processing
            if (newStatus != "OPEN") {
                ArrayRemove(trades, i, 1);
                ArrayRemove(tradeExtras, i, 1);
                continue;
            }
        }
        
        // Continue with main trade processing loop
        for (int i = ArraySize(trades) - 1; i >= 0; i--) {
            // SAFETY: Validate index at loop start (first loop may have removed items)
            if (i >= ArraySize(trades)) continue;
            
            // Skip all SKIPPED* trades - they're handled in Phase 2
            string currentStatus = trades[i].status;
            if(StringFind(currentStatus, "SKIPPED") >= 0) continue;
            
            // skip early‑exit on entry bar (TV rule)
            int barsSinceEntry = (Bars(_Symbol, TF_ARRAY[TF0]) - 1) - trades[i].entryBar;
            if(barsSinceEntry==0)
                continue;
            
            // Phase 2A: Time-based exit for high-risk trades
            if (trades[i].isHighRiskTrade && barsSinceEntry >= HIGH_RISK_MAX_BARS) {
                string timeExitReason = "Time limit (" + IntegerToString(HIGH_RISK_MAX_BARS) + " mins) to keep a risky trade reached. Exit Early?";
                ulong hrTicket = trades[i].positionTicket;
                if (hrTicket > 0 && PositionSelectByTicket(hrTicket)) {
                    // Capture exit price BEFORE close (current market price)
                    double actualExitPrice = trades[i].isLong ? 
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    double actualPnLPips = trades[i].isLong ? 
                        (actualExitPrice - trades[i].entryPrice) / pipSize :
                        (trades[i].entryPrice - actualExitPrice) / pipSize;
                    
                    if (SafePositionClose(hrTicket, "HIGH-RISK TIME EXIT")) {
                        
                        trades[i].status = "EARLY_EXIT";
                        SendAlertForTrade(
                            EMAIL_SUBJECT_PREFIX + " - High-Risk time-based Exit",
                            timeExitReason,
                            trades[i],
                            "EARLY_EXIT",
                            timeExitReason,
                            actualExitPrice,
                            actualPnLPips
                        );
                    }
                }
                continue;  // Skip further processing for this trade
            }

            bool isLong = trades[i].isLong;
            string newStatus = currentStatus;
            
            // CLEANUP: Remove trades that are already closed to prevent repeated processing
            if (newStatus != "OPEN") {
                ArrayRemove(trades, i, 1);
                ArrayRemove(tradeExtras, i, 1);
                continue;
            }
            
            // PERFORMANCE: Smart broker check - only when needed (hybrid event-driven approach)
            bool brokerCheckWasCalled = false;  // Track if we already called CheckTradeStatusOnBrokerBeforeUpdating
            
            if (newStatus == "OPEN") {
                bool needsBrokerCheck = false;
                
                // 1. CRITICAL: Always check if price hit SL/TP (trade likely closed by broker)
                if (isLong) {
                    needsBrokerCheck = (low <= trades[i].stopLoss || high >= trades[i].takeProfit);
                } else {
                    needsBrokerCheck = (high >= trades[i].stopLoss || low <= trades[i].takeProfit);
                }
                
                // 2. Check before MODIFYING position (avoid failed modification attempts)
                if (!needsBrokerCheck) {
                    bool aboutToModify = false;
                    if (ENABLE_CONSERVATIVE_TRADE_MGMT) {
                        aboutToModify = !trades[i].hasTakenPartialProfit;
                    } else {
                        EntryBase* entryPtrForModify = GetEntryForType(trades[i].entryType);
                        int maxExtForModify = (entryPtrForModify != NULL) ? entryPtrForModify.GetMaxTPExtensions() : 30;
                        aboutToModify = (ALLOW_TP_EXTENSION && trades[i].tpExtensions < maxExtForModify) ||
                                        (ALLOW_PARTIAL_TP && !trades[i].hasTakenPartialProfit) ||
                                        ENABLE_EARLY_CUT_NEAR_SL;
                    }
                    needsBrokerCheck = aboutToModify;
                }
                
                // 3. Periodic safety check for edge cases (manual close, broker-side events, etc.)
                m_brokerCheckCounter++;
                if (!needsBrokerCheck && (m_brokerCheckCounter % 20 == 0)) {
                    needsBrokerCheck = true;  // Every 20th tick (~1-2 seconds)
                }
                
                // Only call broker when truly needed (reduces API calls by ~75%)
                if (needsBrokerCheck) {
                    CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
                    newStatus = trades[i].status;
                    brokerCheckWasCalled = true;
                }
            }
            
            if (newStatus == "OPEN") {
                // Update best price achieved
                double bestPrice = trades[i].bestPrice;
                bestPrice = isLong ? MathMax(bestPrice, high) : MathMin(bestPrice, low);
                trades[i].bestPrice = bestPrice;
                
                // Win/Loss detection
                bool hitWin = (isLong && high >= trades[i].takeProfit) || (!isLong && low <= trades[i].takeProfit);
                bool hitLoss = (isLong && low <= trades[i].stopLoss) || (!isLong && high >= trades[i].stopLoss);
                
                if (!hitWin && !hitLoss && barsSinceEntry > 0) {
                    double currentPnL = isLong ? (currentPrice - trades[i].entryPrice) : (trades[i].entryPrice - currentPrice);

                    // Pre-BE structure protection: tighten SL on favorable structure breach before BE logic
                    ApplyPreBEStructureProtection(i, currentPnL, currentPrice);

                    if (ENABLE_CONSERVATIVE_TRADE_MGMT) {
                        // Conservative mode: R-based partial + progressive trailing
                        ApplyConservativeTradeManagement(i, currentPnL, currentPrice);
                    } else {
                        // Standard mode: existing behavior preserved
                        ApplyRMultipleSLProtection(i, currentPnL);
                        ExtendTPAsNeeded(i, currentPrice, currentPnL);
                        TakePartialProfitAsNeeded(i, currentPnL, currentPrice);
                    }

                    // Early exit conditions
                    ExitEarlyAsNeeded(i, currentPrice, currentPnL, allowQualityDropCheck, newStatus, brokerCheckWasCalled);
                    
                    // P&L Zone Update: Send signal when floating P&L enters a new 10% zone
                    CheckAndSendPnLZoneUpdate(i, currentPnL);
                }
            }
            
            // SAFETY: Final validation before updating status
            if (i >= ArraySize(trades)) continue;
            
            // Update trade status anyways if earlyWin / early Loss was detected.
            if (newStatus != "OPEN") {
                // CRITICAL: If CheckTradeStatusOnBrokerBeforeUpdating wasn't called yet,
                // we must call it now to ensure UpdatePerformance is triggered for adaptive learning!
                if (!brokerCheckWasCalled) {
                    CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
                }
                
                trades[i].status = newStatus;
                UpdateLosingStreak(newStatus, trades[i].type);
            }
        }
    }
    
    //--------------------------------------------------------------------
    // PRE-BE STRUCTURE PROTECTION
    // Tighten SL before breakeven when price makes a meaningful structure breach
    //--------------------------------------------------------------------
    void ApplyPreBEStructureProtection(int i, double currentPnL, double currentPrice) {
        if (!ENABLE_PRE_BE_STRUCTURE_PROTECTION) return;
        if (PRE_BE_TRIGGER_R <= 0) return;
        if (trades[i].slMovedToBreakeven) return;
        if (trades[i].partialTPEligible || trades[i].hasTakenPartialProfit) return;

        double originalRisk = trades[i].bufferedSLDistancePips * pipSize;
        if (originalRisk <= 0) return;
        if (currentPnL <= 0) return;

        double rMultiple = currentPnL / originalRisk;
        if (rMultiple < PRE_BE_TRIGGER_R) return;

        TREND_STATE trendState = trades[i].isLong ? TREND_BULL : TREND_BEAR;
        if (PRE_BE_REQUIRE_M3_ACCEL_CONFIRM && !HasTrendAcceleration(TF_ARRAY[TF1], trendState, 3)) {
            return;
        }

        int lookbackBars = MathMax(3, PRE_BE_BOS_LOOKBACK_BARS);
        int priorStructureShift = -1;
        if (trades[i].isLong) {
            priorStructureShift = iHighest(_Symbol, TF_ARRAY[TF0], MODE_HIGH, lookbackBars, 1);
        } else {
            priorStructureShift = iLowest(_Symbol, TF_ARRAY[TF0], MODE_LOW, lookbackBars, 1);
        }
        if (priorStructureShift < 0) return;

        double priorStructure = 0.0;
        if (trades[i].isLong) {
            priorStructure = iHigh(_Symbol, TF_ARRAY[TF0], priorStructureShift);
        } else {
            priorStructure = iLow(_Symbol, TF_ARRAY[TF0], priorStructureShift);
        }
        if (priorStructure <= 0) return;

        double breachBuffer = PRE_BE_BOS_BREACH_BUFFER_PIPS * pipSize;
        bool structureBreached = false;
        if (trades[i].isLong) {
            structureBreached = (currentPrice > (priorStructure + breachBuffer));
        } else {
            structureBreached = (currentPrice < (priorStructure - breachBuffer));
        }
        if (!structureBreached) return;

        double swingBuffer = PRE_BE_SWING_BUFFER_PIPS * pipSize;
        double breakoutExtreme = 0.0;
        if (trades[i].isLong) {
            breakoutExtreme = iLow(_Symbol, TF_ARRAY[TF0], 0);
        } else {
            breakoutExtreme = iHigh(_Symbol, TF_ARRAY[TF0], 0);
        }
        if (breakoutExtreme <= 0) return;

        double newSL = 0.0;
        if (trades[i].isLong) {
            newSL = breakoutExtreme - swingBuffer;
        } else {
            newSL = breakoutExtreme + swingBuffer;
        }

        // Keep this strictly pre-BE: do not let this stage cross entry.
        double preBEMargin = 0.5 * pipSize;
        if (trades[i].isLong) {
            newSL = MathMin(newSL, trades[i].entryPrice - preBEMargin);
        } else {
            newSL = MathMax(newSL, trades[i].entryPrice + preBEMargin);
        }

        double brokerMinStop = MathMax(
            MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point,
                    SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point),
            SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point);
        if (brokerMinStop <= 0) brokerMinStop = 10 * _Point;
        double marketPrice = trades[i].isLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        if (trades[i].isLong) {
            if ((marketPrice - newSL) < brokerMinStop) newSL = marketPrice - brokerMinStop;
        } else {
            if ((newSL - marketPrice) < brokerMinStop) newSL = marketPrice + brokerMinStop;
        }

        bool isImprovement = trades[i].isLong ? (newSL > trades[i].stopLoss) : (newSL < trades[i].stopLoss);
        if (!isImprovement) return;

        double minImprovement = PRE_BE_MIN_SL_IMPROVEMENT_PIPS * pipSize;
        if (MathAbs(newSL - trades[i].stopLoss) < minImprovement) return;

        // Final pre-BE guard after broker distance adjustment
        if (trades[i].isLong && newSL >= trades[i].entryPrice) return;
        if (!trades[i].isLong && newSL <= trades[i].entryPrice) return;

        datetime currentTime = TimeCurrent();
        if (trades[i].lastSLModificationAttempt != 0 && (currentTime - trades[i].lastSLModificationAttempt) < 2) {
            return;
        }

        double oldSL = trades[i].stopLoss;
        NormalizePriceToTickSize(newSL);
        trades[i].lastSLModificationAttempt = currentTime;
        if (ModifyPositionSLTP(trades[i], newSL, trades[i].takeProfit, "PRE-BE STRUCTURE")) {
            trades[i].stopLoss = newSL;
            trades[i].lastSLModificationAttempt = 0;
            if (showDebug) {
                double oldSLDistancePips = MathAbs(trades[i].entryPrice - oldSL) / pipSize;
                double newSLDistancePips = MathAbs(trades[i].entryPrice - newSL) / pipSize;
                Print("[PRE-BE STRUCTURE] ", trades[i].id,
                      " r=", DoubleToString(rMultiple, 2),
                      " prior=", DoubleToString(priorStructure, 5),
                      " newSL=", DoubleToString(newSL, 5),
                      " distToEntry=", DoubleToString(oldSLDistancePips, 1), "->", DoubleToString(newSLDistancePips, 1), " pips");
            }
        }
    }

    //--------------------------------------------------------------------
    // R-MULTIPLE SL PROTECTION (World-class early breakeven protection)
    // Moves SL to entry+buffer when profit reaches R_MULT_BE_TRIGGER × original risk
    // This is INDEPENDENT of partial TP - protects capital earlier
    //--------------------------------------------------------------------
    void ApplyRMultipleSLProtection(int i, double currentPnL) {
        if (R_MULT_BE_TRIGGER <= 0) return;  // Feature disabled
        if (trades[i].rMultipleBEApplied) return;  // Already applied
        if (trades[i].slMovedToBreakeven) return;  // Already at BE from partial TP
        
        // Calculate original risk from buffered SL distance (stored at trade creation)
        double originalRisk = trades[i].bufferedSLDistancePips * pipSize;
        if (originalRisk <= 0) return;  // Safety check
        
        // Calculate current R-multiple (profit / risk)
        double rMultiple = currentPnL / originalRisk;
        
        // Check if we've reached the BE trigger threshold
        if (rMultiple >= R_MULT_BE_TRIGGER) {
            // Calculate new SL: entry + buffer (buffer = % of original risk)
            double buffer = originalRisk * R_MULT_BE_BUFFER;
            double newSL = trades[i].isLong ? 
                          (trades[i].entryPrice + buffer) : 
                          (trades[i].entryPrice - buffer);
            
            // Only move SL if it's an improvement (more protective)
            bool isImprovement = trades[i].isLong ? 
                                (newSL > trades[i].stopLoss) : 
                                (newSL < trades[i].stopLoss);
            
            if (isImprovement) {
                NormalizePriceToTickSize(newSL);
                bool modifyResult = ModifyPositionSLTP(trades[i], newSL, trades[i].takeProfit, "R-MULT BE");
                if (modifyResult) {
                    trades[i].stopLoss = newSL;
                    trades[i].rMultipleBEApplied = true;
                    trades[i].slMovedToBreakeven = true;
                    
                    if(showDebug) {
                        Print("[R-MULT BE] ", trades[i].id, " reached ", DoubleToString(rMultiple, 2), 
                              "R | SL moved to ", DoubleToString(newSL, 5), 
                              " (entry=", DoubleToString(trades[i].entryPrice, 5), 
                              ", buffer=", DoubleToString(buffer / pipSize, 1), " pips)");
                    }
                    
                    // Send Telegram alert for SL moved to breakeven
                    string beSubject = EMAIL_SUBJECT_PREFIX + " - SL Moved to Entry";
                    string beReason = StringFormat("Reached %.1fR, SL protected at entry + %.1f pips", rMultiple, buffer / pipSize);
                    SendAlertForTrade(beSubject, beReason, trades[i], AlertTypeToString(ALERT_SL_TO_BREAKEVEN), beReason);
                    
                    // Track for adaptive learning
                    EntryBase* entry = GetEntryForType(trades[i].entryType);
                    if (entry != NULL) {
                        entry.TrackBreakeven(false, false);
                    }
                }
            }
        }
    }
    
    //--------------------------------------------------------------------
    // CONSERVATIVE TRADE MANAGEMENT: R-based partial + progressive trailing
    //--------------------------------------------------------------------
    double GetConsInitialPartialR(int n) {
        switch(n) { case 1: return CONS_INITIAL_PARTIAL_R_E1; case 2: return CONS_INITIAL_PARTIAL_R_E2;
                    case 3: return CONS_INITIAL_PARTIAL_R_E3; case 4: return CONS_INITIAL_PARTIAL_R_E4;
                    case 5: return CONS_INITIAL_PARTIAL_R_E5; default: return 0.30; }
    }
    double GetConsInitialPartialRatio(int n) {
        switch(n) { case 1: return CONS_INITIAL_PARTIAL_RATIO_E1; case 2: return CONS_INITIAL_PARTIAL_RATIO_E2;
                    case 3: return CONS_INITIAL_PARTIAL_RATIO_E3; case 4: return CONS_INITIAL_PARTIAL_RATIO_E4;
                    case 5: return CONS_INITIAL_PARTIAL_RATIO_E5; default: return 0.10; }
    }
    double GetConsPostPartialSLR(int n) {
        switch(n) { case 1: return CONS_POST_PARTIAL_SL_R_E1; case 2: return CONS_POST_PARTIAL_SL_R_E2;
                    case 3: return CONS_POST_PARTIAL_SL_R_E3; case 4: return CONS_POST_PARTIAL_SL_R_E4;
                    case 5: return CONS_POST_PARTIAL_SL_R_E5; default: return 0.15; }
    }
    double GetConsTrailRIncrement(int n) {
        switch(n) { case 1: return CONS_TRAIL_R_INCREMENT_E1; case 2: return CONS_TRAIL_R_INCREMENT_E2;
                    case 3: return CONS_TRAIL_R_INCREMENT_E3; case 4: return CONS_TRAIL_R_INCREMENT_E4;
                    case 5: return CONS_TRAIL_R_INCREMENT_E5; default: return 0.10; }
    }
    double GetConsTrailSLStepR(int n) {
        switch(n) { case 1: return CONS_TRAIL_SL_STEP_R_E1; case 2: return CONS_TRAIL_SL_STEP_R_E2;
                    case 3: return CONS_TRAIL_SL_STEP_R_E3; case 4: return CONS_TRAIL_SL_STEP_R_E4;
                    case 5: return CONS_TRAIL_SL_STEP_R_E5; default: return 0.025; }
    }

    void ApplyConservativeTradeManagement(int i, double currentPnL, double currentPrice) {
        if (trades[i].status != "OPEN") return;

        double originalRisk = trades[i].bufferedSLDistancePips * pipSize;
        if (originalRisk <= 0) return;

        double currentR = currentPnL / originalRisk;
        if (currentR <= 0) return;

        int entryNum = GetEntryNumber(trades[i].entryType);
        double initialPartialR = GetConsInitialPartialR(entryNum);
        double partialRatio = GetConsInitialPartialRatio(entryNum);
        double postPartialSLR = GetConsPostPartialSLR(entryNum);
        double trailRIncrement = GetConsTrailRIncrement(entryNum);
        double trailSLStepR = GetConsTrailSLStepR(entryNum);

        if (initialPartialR <= 0 || partialRatio <= 0 || trailRIncrement <= 0) return;

        // PHASE 1: Initial partial profit + SL to entry+buffer (fires once)
        if (!tradeExtras[i].consInitialPartialTaken && currentR >= initialPartialR) {
            double executionPrice = 0;
            bool partialSuccess = ExecutePartialTakeProfit(i, partialRatio, executionPrice);
            if (i >= ArraySize(trades)) return;

            if (partialSuccess) {
                tradeExtras[i].consInitialPartialTaken = true;
                trades[i].hasTakenPartialProfit = true;

                double slBuffer = postPartialSLR * originalRisk;
                double newSL = trades[i].isLong ?
                    (trades[i].entryPrice + slBuffer) :
                    (trades[i].entryPrice - slBuffer);
                NormalizePriceToTickSize(newSL);

                bool isImprovement = trades[i].isLong ? (newSL > trades[i].stopLoss) : (newSL < trades[i].stopLoss);
                if (isImprovement) {
                    if (ModifyPositionSLTP(trades[i], newSL, trades[i].takeProfit, "CONS INITIAL BE")) {
                        trades[i].stopLoss = newSL;
                        trades[i].slMovedToBreakeven = true;
                        trades[i].rMultipleBEApplied = true;
                        tradeExtras[i].consLastActionedRLevel = initialPartialR;
                        tradeExtras[i].consCumulativeSLShift = postPartialSLR;

                        string beReason = StringFormat("CONS: Partial %.0f%% at %.2fR, SL to entry + %.2fR",
                            partialRatio * 100, currentR, postPartialSLR);
                        SendAlertForTrade(EMAIL_SUBJECT_PREFIX + " - Conservative Partial + BE",
                            beReason, trades[i], AlertTypeToString(ALERT_SL_TO_BREAKEVEN), beReason);

                        if (showDebug) Print("[CONS PARTIAL] ", trades[i].id, " R=", DoubleToString(currentR, 3),
                            " | Partial ", DoubleToString(partialRatio * 100, 0), "% | SL=", DoubleToString(newSL, 5));

                        EntryBase* entry = GetEntryForType(trades[i].entryType);
                        if (entry != NULL) entry.TrackBreakeven(false, false);
                    }
                }
            }
            return;  // Don't trail on same tick as partial
        }

        // PHASE 2: Progressive R-based trailing (after initial partial)
        if (!tradeExtras[i].consInitialPartialTaken) return;

        double rSinceLastAction = currentR - tradeExtras[i].consLastActionedRLevel;
        if (rSinceLastAction < trailRIncrement) return;

        int newIncrements = (int)MathFloor(rSinceLastAction / trailRIncrement);
        if (newIncrements <= 0) return;

        double additionalSLShift = newIncrements * trailSLStepR;
        double newCumulativeSLShift = tradeExtras[i].consCumulativeSLShift + additionalSLShift;
        double newSL = trades[i].isLong ?
            (trades[i].entryPrice + newCumulativeSLShift * originalRisk) :
            (trades[i].entryPrice - newCumulativeSLShift * originalRisk);
        NormalizePriceToTickSize(newSL);

        bool isImprovement = trades[i].isLong ? (newSL > trades[i].stopLoss) : (newSL < trades[i].stopLoss);
        if (!isImprovement) return;

        // Broker min stop distance check
        double marketPrice = trades[i].isLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double minStopLevel = MathMax(
            MathMax((double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point,
                    (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point),
            (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point);
        if (minStopLevel <= 0) minStopLevel = 10 * _Point;

        double slDistFromMarket = trades[i].isLong ? (marketPrice - newSL) : (newSL - marketPrice);
        if (slDistFromMarket < minStopLevel) {
            newSL = trades[i].isLong ? (marketPrice - minStopLevel) : (marketPrice + minStopLevel);
            NormalizePriceToTickSize(newSL);
        }

        isImprovement = trades[i].isLong ? (newSL > trades[i].stopLoss) : (newSL < trades[i].stopLoss);
        if (!isImprovement) return;

        double slDifference = MathAbs(newSL - trades[i].stopLoss);
        if (slDifference < _Point * 10) return;  // Min 1 pip change

        datetime currentTime = TimeCurrent();
        if (trades[i].lastSLModificationAttempt != 0 && (currentTime - trades[i].lastSLModificationAttempt) < 2) return;

        if (!IsMarketOpen()) return;

        trades[i].lastSLModificationAttempt = currentTime;
        if (ModifyPositionSLTP(trades[i], newSL, trades[i].takeProfit, "CONS TRAIL")) {
            trades[i].stopLoss = newSL;
            trades[i].lastSLModificationAttempt = 0;
            trades[i].slWasTrailed = true;
            tradeExtras[i].consLastActionedRLevel += (newIncrements * trailRIncrement);
            tradeExtras[i].consCumulativeSLShift = newCumulativeSLShift;

            if (showDebug) Print("[CONS TRAIL] ", trades[i].id, " R=", DoubleToString(currentR, 3),
                " | +", newIncrements, " incr | cumSL=", DoubleToString(newCumulativeSLShift, 4),
                "R | newSL=", DoubleToString(newSL, 5));
        }
    }

    //--------------------------------------------------------------------
    // TP EXTENSION
    //--------------------------------------------------------------------
    void ExtendTPAsNeeded(int i, double currentPrice, double currentPnL) {
        ENTRY_TYPE entryType = GetEntryTypeEnum(trades[i].type);
        EntryBase* entryPtr = GetEntryForType(trades[i].entryType);
        int maxExt = (entryPtr != NULL) ? entryPtr.GetMaxTPExtensions() : 30;

        if (ALLOW_TP_EXTENSION && trades[i].tpExtensions < maxExt){
            // Simple progress calculation from entry to current TP
            double totalDistance = trades[i].isLong ? (trades[i].takeProfit - trades[i].entryPrice) : (trades[i].entryPrice - trades[i].takeProfit);
            
            // Safety check for division by zero
            if(totalDistance > 0) {
                // Calculate remaining distance to TP and current progress
                double remainingDistanceToTP = trades[i].isLong ? (trades[i].takeProfit - currentPrice) : (currentPrice - trades[i].takeProfit);
                double remainingDistancePips = remainingDistanceToTP / pipSize;
                double totalDistancePips = totalDistance / pipSize;
                double progressPercent = ((totalDistancePips - remainingDistancePips) / totalDistancePips) * 100.0;
                
                double triggerPips = GetTPExtensionTriggerPips(entryType);
                
                // TP Extension: Trigger when close to TP AND sufficient progress made
                if(remainingDistancePips <= triggerPips && remainingDistancePips > 0) {
                    // Require minimum progress (e.g., 91%) to prevent premature extensions
                    double progressRatio = progressPercent / 100.0;
                    if(progressRatio < MIN_TP_PROGRESS_FOR_EXTENSION) {
                        return; // Not enough progress yet
                    }
                    
                    // v1.7.92: Only extend if trend is not weakening (let dying trends hit TP)
                    if(IsTrendWeakening(trades[i].isLong)) {
                        if(showDebug) Print("TP EXTENSION SKIPPED: Trend weakening for ", trades[i].id);
                        return;
                    }

                    int extPips = GetTPExtensionPips(entryType);
                    double extension = extPips * pipSize;
                    double oldTP = trades[i].takeProfit;
                    double newTP = trades[i].takeProfit + (trades[i].isLong ? extension : -extension);
                    NormalizePriceToTickSize(newTP);
                    
                    PrintDebug("TP EXTENSION TRIGGERED for " + trades[i].id + " ext #" + IntegerToString(trades[i].tpExtensions) + " | oldTP=" + DoubleToString(oldTP, 5) + " | newTP=" + DoubleToString(newTP, 5));
                    
                    bool modifyResult = ModifyPositionSLTP(trades[i], trades[i].stopLoss, newTP, "TP EXTENSION");
                    if (modifyResult) {
                        trades[i].takeProfit = newTP;
                        trades[i].tpExtensions++;
                        
                        // Track for adaptive learning
                        if (entryPtr != NULL) {
                            double pipsGained = MathAbs(newTP - oldTP) / pipSize;
                            bool hitMax = (trades[i].tpExtensions >= maxExt);
                            entryPtr.TrackTPExtension(true, pipsGained, hitMax);
                        }
                        
                        PrintDebug("TP EXTENSION SUCCESS: #" + IntegerToString(trades[i].positionTicket) + " " + trades[i].id + " | Extension #" + IntegerToString(trades[i].tpExtensions) + " | New TP=" + DoubleToString(newTP, 5));
                        
                        // Trail the stop loss after successful TP extension
                        CalculateTrailingSLForTrade(trades[i]);
                    } else {
                        PrintDebug("TP EXTENSION FAILED: #" + IntegerToString(trades[i].positionTicket) + " " + trades[i].id + " | ModifyPositionSLTP returned false");
                    }
                }
            }
        }
    }
    
    //--------------------------------------------------------------------
    // PARTIAL TP
    //--------------------------------------------------------------------
    void TakePartialProfitAsNeeded(int i, double currentPnL, double currentPrice) {
        double origTPDist = MathAbs(trades[i].originalTP - trades[i].entryPrice); 
        
        if (ALLOW_PARTIAL_TP) {
            // Phase 2C: Use per-entry-type thresholds (or high-risk override)
            EntryBase* entryForPartial = GetEntryForType(trades[i].entryType);
            bool useHighRiskOverride = trades[i].isHighRiskTrade && ALLOW_HIGH_RISK_PARTIAL_TP_OVERRIDE;
            double partialTrigger = useHighRiskOverride ?
                                   HIGH_RISK_PARTIAL_TP_TRIGGER : ((entryForPartial != NULL) ? entryForPartial.GetPartialTPTrigger() : 0.65);
            double partialRatio = useHighRiskOverride ?
                                 HIGH_RISK_PARTIAL_TP_RATIO : ((entryForPartial != NULL) ? entryForPartial.GetPartialTPRatio() : 0.5);
            
            // v1.7.92: Smart Partial TP - mark eligible when trigger reached, wait for weakness/retrace
            if (currentPnL >= partialTrigger * origTPDist && !trades[i].partialTPEligible) {
                trades[i].partialTPEligible = true;
                trades[i].bestPriceSinceEligible = currentPrice;
                if(showDebug) Print("PARTIAL TP ELIGIBLE: ", trades[i].id, " at ", currentPrice,
                    " trigger=", partialTrigger, " ratio=", partialRatio,
                    (useHighRiskOverride ? " [HIGH-RISK OVERRIDE]" : ""), " - waiting for weakness/retrace");
            }

            // E5 Pine parity: execute partial TP immediately at level (no weakness/retrace gate)
            bool isE5Trade = (trades[i].entryType == ENTRY_L_E5 || trades[i].entryType == ENTRY_S_E5);
            if (isE5Trade && trades[i].partialTPEligible && !trades[i].hasTakenPartialProfit) {
                double executionPrice = 0;
                bool partialSuccess = ExecutePartialTakeProfit(i, partialRatio, executionPrice);

                if (i >= ArraySize(trades)) return;

                if (partialSuccess) {
                    double actualPnL = trades[i].isLong ?
                        (executionPrice - trades[i].entryPrice) :
                        (trades[i].entryPrice - executionPrice);

                    if (actualPnL > 0) {
                        // E5 breakeven: entry + 2*spread (Pine SuperBros parity)
                        double spreadPrice = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
                        double breakevenBuffer = 2.0 * spreadPrice;
                        double breakevenSL = trades[i].isLong ? trades[i].entryPrice + breakevenBuffer : trades[i].entryPrice - breakevenBuffer;

                        NormalizePriceToTickSize(breakevenSL);
                        bool modifyResult = ModifyPositionSLTP(trades[i], breakevenSL, trades[i].takeProfit, "SL TO BREAKEVEN");
                        if (modifyResult) {
                            trades[i].stopLoss = breakevenSL;
                            if(showDebug) Print("E5 SL MOVED TO BREAKEVEN: ", trades[i].id, " newSL=", breakevenSL, " entry=", trades[i].entryPrice, " buffer=", breakevenBuffer/pipSize, " pips");
                            trades[i].slMovedToBreakeven = true;

                            string beSubject = EMAIL_SUBJECT_PREFIX + " - SL Moved to Entry";
                            string beReason = StringFormat("E5 TP1 hit, SL at entry + %.1f pips (2*spread)", breakevenBuffer / pipSize);
                            SendAlertForTrade(beSubject, beReason, trades[i], AlertTypeToString(ALERT_SL_TO_BREAKEVEN), beReason);

                            EntryBase* entry = GetEntryForType(trades[i].entryType);
                            if (entry != NULL) {
                                entry.TrackBreakeven(false, false);
                            }
                        }
                    } else {
                        Print("WARNING: E5 Partial close at LOSS for ", trades[i].id, " | execPrice=", executionPrice,
                              " entry=", trades[i].entryPrice, " | SL NOT moved to breakeven");
                    }

                    trades[i].hasTakenPartialProfit = true;
                    if(showDebug) Print("E5 IMMEDIATE PARTIAL TP: ", trades[i].id, " at ", executionPrice,
                                       " (ratio=", partialRatio, ")");
                }
            }

            // Non-E5: Track best price while eligible (for retrace calculation)
            if (!isE5Trade && trades[i].partialTPEligible && !trades[i].hasTakenPartialProfit) {
                if (trades[i].isLong && currentPrice > trades[i].bestPriceSinceEligible)
                    trades[i].bestPriceSinceEligible = currentPrice;
                else if (!trades[i].isLong && currentPrice < trades[i].bestPriceSinceEligible)
                    trades[i].bestPriceSinceEligible = currentPrice;
            }

            // Non-E5: Take partial when eligible AND (trend weakening OR significant retrace)
            if (!isE5Trade && trades[i].partialTPEligible && !trades[i].hasTakenPartialProfit) {
                bool trendWeakening = IsTrendWeakening(trades[i].isLong);
                bool significantRetrace = HasSignificantRetrace(trades[i], PARTIAL_TP_RETRACE_RATIO);

                if (trendWeakening || significantRetrace) {
                    // v1.7.94: Execute partial TP FIRST, verify profit, THEN move SL
                    double executionPrice = 0;
                    bool partialSuccess = ExecutePartialTakeProfit(i, partialRatio, executionPrice);

                    if (i >= ArraySize(trades)) return;

                    if (partialSuccess) {
                        // Check if partial close was actually profitable
                        double actualPnL = trades[i].isLong ?
                            (executionPrice - trades[i].entryPrice) :
                            (trades[i].entryPrice - executionPrice);

                        if (actualPnL > 0) {
                            // Partial TP was profitable - now move SL to breakeven
                            double originalTpDist = MathAbs(trades[i].originalTP - trades[i].entryPrice);
                            double breakevenBuffer = originalTpDist * ((entryForPartial != NULL) ? entryForPartial.GetBreakevenBuffer() : 0.02);
                            double breakevenSL = trades[i].isLong ? trades[i].entryPrice + breakevenBuffer : trades[i].entryPrice - breakevenBuffer;

                            NormalizePriceToTickSize(breakevenSL);
                            bool modifyResult = ModifyPositionSLTP(trades[i], breakevenSL, trades[i].takeProfit, "SL TO BREAKEVEN");
                            if (modifyResult) {
                                trades[i].stopLoss = breakevenSL;
                                if(showDebug) Print("SL MOVED TO BREAKEVEN: ", trades[i].id, " newSL=", breakevenSL, " entry=", trades[i].entryPrice, " buffer=", breakevenBuffer);
                                trades[i].slMovedToBreakeven = true;

                                // Send alert for SL moved to breakeven after partial TP
                                string beSubject = EMAIL_SUBJECT_PREFIX + " - SL Moved to Entry";
                                string beReason = StringFormat("Partial TP taken, SL protected at entry + %.1f pips", breakevenBuffer / pipSize);
                                SendAlertForTrade(beSubject, beReason, trades[i], AlertTypeToString(ALERT_SL_TO_BREAKEVEN), beReason);

                                EntryBase* entry = GetEntryForType(trades[i].entryType);
                                if (entry != NULL) {
                                    entry.TrackBreakeven(false, false);
                                }
                            }
                        } else {
                            // Partial close at loss - keep original SL, don't move to entry
                            Print("WARNING: Partial close at LOSS for ", trades[i].id, " | execPrice=", executionPrice,
                                  " entry=", trades[i].entryPrice, " | SL NOT moved to breakeven");
                        }

                        trades[i].hasTakenPartialProfit = true;
                        string reason = trendWeakening ? "trend weakening" : "retrace";
                        if(showDebug) Print("SMART PARTIAL TP: ", trades[i].id, " at ", executionPrice,
                                           " (ratio=", partialRatio, ", reason=", reason, trades[i].isHighRiskTrade ? ", HIGH-RISK)" : ")");
                    }
                }
            }
            
            // Phase 2: Check ladder stages FIRST (more aggressive trailing)
            if (trades[i].hasTakenPartialProfit) {
                CheckAndApplyLadderStages(i);
            }
            
            // Trail SL when partial TP trigger is passed (even if partial TP not taken yet)
            // This protects profits when price reaches target zone but hasn't retraced/weakened
            if (trades[i].partialTPEligible || trades[i].hasTakenPartialProfit) {
                CalculateTrailingSLForTrade(trades[i]);
            }
        }
    }
    
    //--------------------------------------------------------------------
    // P&L ZONE UPDATE: Send signal when floating P&L enters a new zone
    // Premium: 20% zones with +/-10% tolerance (0=entry, 1=20%, 2=40%, etc.)
    // Public: 35% zones with +/-17.5% tolerance (0=entry, 1=35%, 2=70%, etc.)
    // Cooldown: PNL_UPDATE_COOLDOWN_MINUTES between updates per trade
    //--------------------------------------------------------------------
    void CheckAndSendPnLZoneUpdate(int i, double currentPnL) {
        // Calculate TP distance for zone calculation
        double tpDistance = MathAbs(trades[i].takeProfit - trades[i].entryPrice);
        if (tpDistance <= 0) return;
        
        // Cooldown: skip if last update was too recent
        datetime currentTime = TimeCurrent();
        if (tradeExtras[i].lastPnLUpdateTime > 0 && 
            (currentTime - tradeExtras[i].lastPnLUpdateTime) < PNL_UPDATE_COOLDOWN_MINUTES * 60) {
            return;
        }
        
        // Calculate current P&L as percentage of TP distance
        double pnlPercent = (currentPnL / tpDistance) * 100;
        
        // Get current trend quality (shared for both channels)
        int entryNum = GetEntryNumber(trades[i].entryType);
        TREND_STATE trendForScore = trades[i].isLong ? TREND_BULL : TREND_BEAR;
        int currentTrendQuality = GetTrendQualityScore(trendForScore, entryNum);
        
        // Convert currentPnL to pips for display (points to pips)
        double floatingPnLPips = currentPnL / pipSize;
        
        bool updateSent = false;
        
        // PREMIUM: 20% zones with +/-10% tolerance
        int premiumZone = 0;
        if (pnlPercent >= 10) {
            premiumZone = (int)MathFloor((pnlPercent + 10) / 20);
        } else if (pnlPercent <= -10) {
            premiumZone = (int)MathFloor((pnlPercent - 10) / 20);  // Negative zones
        }
        
        if (premiumZone != tradeExtras[i].lastPnLZone) {
            SendDiscordPnLUpdatePremium(trades[i], floatingPnLPips, currentTrendQuality);
            tradeExtras[i].lastPnLZone = premiumZone;
            updateSent = true;
            if (showDebug) Print("[PNL ZONE PREMIUM] ", trades[i].id, " zone ", premiumZone, 
                                " (", DoubleToString(pnlPercent, 1), "% of TP)");
        }
        
        // PUBLIC: 35% zones with +/-17.5% tolerance
        int publicZone = 0;
        if (pnlPercent >= 17.5) {
            publicZone = (int)MathFloor((pnlPercent + 17.5) / 35);
        } else if (pnlPercent <= -17.5) {
            publicZone = (int)MathFloor((pnlPercent - 17.5) / 35);  // Negative zones
        }
        
        if (publicZone != tradeExtras[i].lastPublicPnLZone) {
            SendDiscordPnLUpdatePublic(trades[i], floatingPnLPips, currentTrendQuality);
            tradeExtras[i].lastPublicPnLZone = publicZone;
            updateSent = true;
            if (showDebug) Print("[PNL ZONE PUBLIC] ", trades[i].id, " zone ", publicZone, 
                                " (", DoubleToString(pnlPercent, 1), "% of TP)");
        }
        
        if (updateSent) tradeExtras[i].lastPnLUpdateTime = currentTime;
    }
    
    //--------------------------------------------------------------------
    // TRAILING SL
    //--------------------------------------------------------------------
    void CalculateTrailingSLForTrade(Trade &dTrade) {
        double originalTpDist = MathAbs(dTrade.originalTP - dTrade.entryPrice);
        double newSL = dTrade.stopLoss; // Start with current SL
        
        // Calculate trailing stop based on best price achieved (per-entry adaptive factor)
        EntryBase* entryForTrail = GetEntryForType(dTrade.entryType);
        double trailingFactor = (entryForTrail != NULL) ? entryForTrail.GetTrailingFactor() : 0.35;
        double baseTrailingDistance = originalTpDist * trailingFactor / (dTrade.tpExtensions+1);
        double adaptiveTrailingDistance = baseTrailingDistance * GetVolatilityMultiplier();
        double trailingSL = dTrade.isLong ? dTrade.bestPrice - adaptiveTrailingDistance : dTrade.bestPrice + adaptiveTrailingDistance;
        newSL = dTrade.isLong ? MathMax(newSL, trailingSL) : MathMin(newSL, trailingSL);

        bool shouldMoveSL = dTrade.isLong ? (newSL > dTrade.stopLoss) : (newSL < dTrade.stopLoss);
        if (shouldMoveSL) {
            // Validate new SL against current market price BEFORE applying
            double currentPrice = dTrade.isLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double minStopLevel = MathMax(
                MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point,
                        SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point),
                SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point);
            if(minStopLevel == 0) minStopLevel = 10 * _Point; // Default minimum
            
            // Check if new SL meets broker requirements
            double slDistanceFromMarket = dTrade.isLong ? (currentPrice - newSL) : (newSL - currentPrice);
            if (slDistanceFromMarket < minStopLevel) {
                // Adjust SL to meet minimum distance requirement
                newSL = dTrade.isLong ? (currentPrice - minStopLevel) : (currentPrice + minStopLevel);
            }
            
            // Final validation: only proceed if new SL is still better than current SL
            bool stillBetterSL = dTrade.isLong ? (newSL > dTrade.stopLoss) : (newSL < dTrade.stopLoss);
            
            // Check if the change is meaningful (at least 1 pip difference)
            double slDifference = MathAbs(newSL - dTrade.stopLoss);
            double minChange = _Point * 10; // 1 pip minimum change
            
            if (stillBetterSL && slDifference >= minChange) {
                // Skip trailing when market is closed (avoid log spam during daily close)
                if (!IsMarketOpen()) return;
                
                // Prevent spam: Only attempt modification after 2 seconds cooldown
                datetime currentTime = TimeCurrent();
                if (dTrade.lastSLModificationAttempt == 0 || (currentTime - dTrade.lastSLModificationAttempt) >= 2) {
                    NormalizePriceToTickSize(newSL);
                    ValidateSLTPDistances(dTrade.entryPrice, newSL, dTrade.takeProfit, dTrade.isLong);
                    
                    dTrade.lastSLModificationAttempt = currentTime; // Mark attempt timestamp
                    
                    string reason = "TRAILING SL";
                    if (ModifyPositionSLTP(dTrade, newSL, dTrade.takeProfit, reason)) {
                        // Check if SL just crossed breakeven (before updating stopLoss)
                        bool wasBelowBE = dTrade.isLong ? (dTrade.stopLoss < dTrade.entryPrice) : (dTrade.stopLoss > dTrade.entryPrice);
                        bool nowAboveBE = dTrade.isLong ? (newSL >= dTrade.entryPrice) : (newSL <= dTrade.entryPrice);
                        bool justCrossedBE = wasBelowBE && nowAboveBE && !dTrade.slMovedToBreakeven;
                        
                        dTrade.stopLoss = newSL;
                        dTrade.lastSLModificationAttempt = 0; // Reset on success
                        dTrade.slWasTrailed = true; // Mark that SL was trailed for adaptive learning
                        int distanceToTPpips = (int)MathFloor((dTrade.takeProfit-dTrade.stopLoss)/pipSize);
                        PrintDebug(reason + " ID:" + dTrade.id + " Ext #" + IntegerToString(dTrade.tpExtensions) + " | Distance: " + IntegerToString(distanceToTPpips) + " TP=" + DoubleToString(dTrade.takeProfit,5)+ " newSL=" + DoubleToString(newSL, 5) + " bestPrice=" + DoubleToString(dTrade.bestPrice, 5) + " marketPrice=" + DoubleToString(currentPrice, 5));
                        
                        // Send alert when trailing SL first crosses breakeven
                        if (justCrossedBE) {
                            dTrade.slMovedToBreakeven = true;
                            double bufferPips = MathAbs(newSL - dTrade.entryPrice) / pipSize;
                            string beSubject = EMAIL_SUBJECT_PREFIX + " - SL Moved to Entry";
                            string beReason = StringFormat("Trailing SL crossed entry + %.1f pips", bufferPips);
                            SendAlertForTrade(beSubject, beReason, dTrade, AlertTypeToString(ALERT_SL_TO_BREAKEVEN), beReason);
                        }
                    } else {
                        // Only log on first failure (avoid spam), reset on success above
                        if (dTrade.lastSLModificationAttempt == currentTime) {
                            PrintDebug("TRAILING SL FAILED: ticket #" + IntegerToString(dTrade.positionTicket) + " " + dTrade.id + " | newSL=" + DoubleToString(newSL, 5) + " currentSL=" + DoubleToString(dTrade.stopLoss, 5));
                        }
                    }
                }
            }
        }
    }
    
    //--------------------------------------------------------------------
    // EARLY EXIT
    //--------------------------------------------------------------------
    void ExitEarlyAsNeeded(int i, double currentPrice, double currentPnL, bool allowQualityDropCheck, string &newStatus, bool &brokerCheckWasCalled) {
        // QUALITY DROP EXIT: Exit if momentum score dropped significantly from BEST score during trade
        // Uses GetActiveTradeMomentumScore (0-5) instead of GetTrendQualityScore (0-13)
        // Momentum score focuses on DI direction, ADX alive, M3 confirmation, price vs EMA75
        if (allowQualityDropCheck && newStatus == "OPEN") {
            int entryNum = GetEntryNumber(trades[i].entryType);
            TREND_STATE trendForScore = trades[i].isLong ? TREND_BULL : TREND_BEAR;
            int currentQuality = GetActiveTradeMomentumScore(trendForScore, entryNum);
            
            // Update best quality score if current is higher
            if (currentQuality > trades[i].bestQualityScore) {
                trades[i].bestQualityScore = currentQuality;
            }
            
            EntryBase* entryForDrop = GetEntryForType(trades[i].entryType);
            bool enableScoreDrop = (entryForDrop != NULL) ? entryForDrop.GetEnableScoreDropExit() : false;
            int threshold = (entryForDrop != NULL) ? entryForDrop.GetScoreDropThreshold() : 3;
            
            if (enableScoreDrop && trades[i].bestQualityScore > 0) {
                int qualityDrop = trades[i].bestQualityScore - currentQuality;
                
                // Track consecutive checks where quality dropped below threshold
                if (qualityDrop >= threshold) {
                    trades[i].qualityDropCount++;
                } else {
                    trades[i].qualityDropCount = 0;  // Reset if quality recovers
                }
                
                // Check conditions: partial profit taken OR floating profit < 10% of TP
                double currentPriceChk = iClose(_Symbol, TF_ARRAY[TF0], 0);
                double floatingProfitPct = 0;
                double tpDistance = MathAbs(trades[i].takeProfit - trades[i].entryPrice);
                if (tpDistance > 0) {
                    double currentProfit = trades[i].isLong ? 
                        (currentPriceChk - trades[i].entryPrice) : 
                        (trades[i].entryPrice - currentPriceChk);
                    floatingProfitPct = (currentProfit / tpDistance) * 100.0;
                }
                // FIX: Trigger if partial taken OR floating profit is small/negative (< 10% of TP)
                bool shouldApplyExit = trades[i].hasTakenPartialProfit || (floatingProfitPct < 10.0);
                
                // Only exit after N consecutive checks showing quality drop AND conditions met
                if (trades[i].qualityDropCount >= SCORE_DROP_CONSECUTIVE_CHECKS && shouldApplyExit) {
                    ulong scoreDropTicket = trades[i].positionTicket;
                    if (scoreDropTicket > 0 && PositionSelectByTicket(scoreDropTicket)) {
                        string scoreDropReason = StringFormat("E%d Quality dropped %d pts (best %d→%d) for %d candles", 
                            entryNum, qualityDrop, trades[i].bestQualityScore, currentQuality, trades[i].qualityDropCount);
                        // Capture exit price BEFORE close (current market price)
                        double actualExitPrice = trades[i].isLong ? 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                        double actualPnLPips = trades[i].isLong ? 
                            (actualExitPrice - trades[i].entryPrice) / pipSize :
                            (trades[i].entryPrice - actualExitPrice) / pipSize;
                        
                        if (SafePositionClose(scoreDropTicket, "QUALITY DROP EXIT")) {
                            trades[i].earlyExitAlertSent = true;
                            SendAlertForTrade(
                                EMAIL_SUBJECT_PREFIX + " - Quality Drop Exit",
                                scoreDropReason,
                                trades[i],
                                "EARLY_EXIT",
                                scoreDropReason,
                                actualExitPrice,
                                actualPnLPips);
                            
                            if(showDebug) Print("[QUALITY DROP EXIT] ", trades[i].id, " ", scoreDropReason, 
                                               " PnL=", DoubleToString(actualPnLPips, 1), " pips");
                            CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
                            newStatus = trades[i].status;
                        }
                    }
                }
            }
        }

        // ADX DROP EXIT: Exit if ADX declines N consecutive bars AND falls below entry's min ADX threshold
        if (ENABLE_ADX_DROP_BASED_EXIT && allowQualityDropCheck && newStatus == "OPEN") {
            double currentAdx = cache.adx[TF0];
            int entryNumAdx = GetEntryNumber(trades[i].entryType);
            EntryBase* entryForAdx = GetEntryForType(trades[i].entryType);
            double minAdxForEntry = (entryForAdx != NULL) ? entryForAdx.GetMinADX() : 20.0;
            
            if (trades[i].lastAdxValue > 0.0) {
                if (currentAdx < trades[i].lastAdxValue) {
                    trades[i].adxDropCount++;
                } else {
                    trades[i].adxDropCount = 0;
                }
            }
            trades[i].lastAdxValue = currentAdx;
            
            if (trades[i].adxDropCount >= ADX_DROP_EXIT_BARS && currentAdx < minAdxForEntry) {
                ulong adxDropTicket = trades[i].positionTicket;
                if (adxDropTicket > 0 && PositionSelectByTicket(adxDropTicket)) {
                    string adxDropReason = StringFormat("E%d ADX dropped %d bars in a row (%.1f < min %.1f)",
                        entryNumAdx, trades[i].adxDropCount, currentAdx, minAdxForEntry);
                    double adxExitPrice = trades[i].isLong ?
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    double adxExitPnL = trades[i].isLong ?
                        (adxExitPrice - trades[i].entryPrice) / pipSize :
                        (trades[i].entryPrice - adxExitPrice) / pipSize;
                    
                    if (SafePositionClose(adxDropTicket, "ADX DROP EXIT")) {
                        trades[i].earlyExitAlertSent = true;
                        SendAlertForTrade(
                            EMAIL_SUBJECT_PREFIX + " - ADX Drop Exit",
                            adxDropReason,
                            trades[i],
                            "EARLY_EXIT",
                            adxDropReason,
                            adxExitPrice,
                            adxExitPnL);
                        
                        if(showDebug) Print("[ADX DROP EXIT] ", trades[i].id, " ", adxDropReason,
                                           " PnL=", DoubleToString(adxExitPnL, 1), " pips");
                        CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
                        newStatus = trades[i].status;
                    }
                }
            }
        }
        
        // DI FLIP FAST EXIT: Exit if opposing DI crosses with sufficient spread on M1
        // Gap filler: Panic Exit requires M3 confirmation (min 9 min). This fires on M1 alone,
        // covering fast reversals (<5 min) that complete before M3 has enough bars to confirm.
        if (allowQualityDropCheck && newStatus == "OPEN") {
            int diFlipEntryNum = GetEntryNumber(trades[i].entryType);
            EntryBase* entryForDiFlip = GetEntryForType(trades[i].entryType);
            bool enableDiFlip = (entryForDiFlip != NULL) ? entryForDiFlip.GetEnableDIFlipExit() : false;

            if (enableDiFlip) {
                double diPlus  = cache.diPlus[TF0];
                double diMinus = cache.diMinus[TF0];
                double diAdx   = cache.adx[TF0];

                // Opposing DI has crossed and opened a spread of at least the minimum threshold
                bool diFlipped = trades[i].isLong ?
                    (diMinus > diPlus && (diMinus - diPlus) >= DI_FLIP_MIN_SPREAD_M1) :
                    (diPlus > diMinus && (diPlus  - diMinus) >= DI_FLIP_MIN_SPREAD_M1);

                // ADX must still be elevated - cross without energy is noise
                bool adxSufficient = (diAdx >= DI_FLIP_MIN_ADX_M1);

                // Track consecutive bars of confirmed flip (count regardless of SL gate)
                if (diFlipped && adxSufficient) {
                    tradeExtras[i].diFlipCount++;
                } else {
                    tradeExtras[i].diFlipCount = 0;
                }

                // Gate: only fire when a meaningful portion of SL has been consumed
                double totalSLDist = trades[i].isLong ?
                    (trades[i].entryPrice - trades[i].stopLoss) :
                    (trades[i].stopLoss  - trades[i].entryPrice);
                double slUsedRatio = 0.0;
                if (totalSLDist > 0) {
                    double priceMoved = trades[i].isLong ?
                        (trades[i].entryPrice - currentPrice) :
                        (currentPrice - trades[i].entryPrice);
                    slUsedRatio = MathMax(0.0, priceMoved / totalSLDist);
                }

                if (tradeExtras[i].diFlipCount >= DI_FLIP_CONSECUTIVE_M1_BARS &&
                    slUsedRatio >= DI_FLIP_MIN_SL_USED_RATIO) {

                    ulong diFlipTicket = trades[i].positionTicket;
                    if (diFlipTicket > 0 && PositionSelectByTicket(diFlipTicket)) {
                        double oppSpread = trades[i].isLong ? (diMinus - diPlus) : (diPlus - diMinus);
                        string diFlipReason = StringFormat(
                            "E%d DI flip %d bars: %s=%.1f > %s=%.1f (spread %.1f, ADX %.1f, SL used %.0f%%)",
                            diFlipEntryNum,
                            tradeExtras[i].diFlipCount,
                            trades[i].isLong ? "DI-" : "DI+",
                            trades[i].isLong ? diMinus : diPlus,
                            trades[i].isLong ? "DI+" : "DI-",
                            trades[i].isLong ? diPlus  : diMinus,
                            oppSpread,
                            diAdx,
                            slUsedRatio * 100);

                        double diFlipExitPrice = trades[i].isLong ?
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                        double diFlipExitPnL = trades[i].isLong ?
                            (diFlipExitPrice - trades[i].entryPrice) / pipSize :
                            (trades[i].entryPrice - diFlipExitPrice) / pipSize;

                        if (SafePositionClose(diFlipTicket, "DI FLIP EXIT")) {
                            trades[i].earlyExitAlertSent = true;
                            SendAlertForTrade(
                                EMAIL_SUBJECT_PREFIX + " - DI Flip Fast Exit",
                                diFlipReason,
                                trades[i],
                                "EARLY_EXIT",
                                diFlipReason,
                                diFlipExitPrice,
                                diFlipExitPnL);

                            if (showDebug) Print("[DI FLIP EXIT] ", trades[i].id, " ", diFlipReason,
                                                 " PnL=", DoubleToString(diFlipExitPnL, 1), " pips");
                            CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
                            newStatus = trades[i].status;
                            brokerCheckWasCalled = true;
                        }
                    }
                }
            }
        }

        // E5 MULTI-TF SIDEWAY EARLY EXIT: Immediate close when 2/3 TFs confirm sideway (Pine SuperBros parity)
        bool isE5ForExit = (trades[i].entryType == ENTRY_L_E5 || trades[i].entryType == ENTRY_S_E5);
        if (isE5ForExit && E5_ALLOW_SIDEWAY_EARLY_EXIT && newStatus == "OPEN"
            && currentBar > trades[i].entryBar + 1) {
            if (IsMultiTfSideway(E5_SIDEWAYS_BLOCK_THRESHOLD)) {
                ulong e5SwTicket = trades[i].positionTicket;
                if (e5SwTicket > 0 && PositionSelectByTicket(e5SwTicket)) {
                    string e5SwReason = "E5 Multi-TF Sideway: 2/3 TFs >= " + IntegerToString(E5_SIDEWAYS_BLOCK_THRESHOLD);
                    double e5SwExitPrice = trades[i].isLong ?
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    double e5SwPnLPips = trades[i].isLong ?
                        (e5SwExitPrice - trades[i].entryPrice) / pipSize :
                        (trades[i].entryPrice - e5SwExitPrice) / pipSize;

                    if (SafePositionClose(e5SwTicket, "E5 SIDEWAY EXIT")) {
                        trades[i].earlyExitAlertSent = true;
                        SendAlertForTrade(
                            EMAIL_SUBJECT_PREFIX + " - E5 Sideway Exit",
                            e5SwReason,
                            trades[i],
                            "EARLY_EXIT",
                            e5SwReason,
                            e5SwExitPrice,
                            e5SwPnLPips);

                        if(showDebug) Print("[E5 SIDEWAY EXIT] ", trades[i].id, " ", e5SwReason,
                                           " PnL=", DoubleToString(e5SwPnLPips, 1), " pips");
                        CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
                        newStatus = trades[i].status;
                        brokerCheckWasCalled = true;
                    }
                }
            }
        }

        // SIDEWAY EARLY EXIT (non-E5): Exit if market turns sideway while price fails to make new highs/lows
        if (!isE5ForExit && ENABLE_SIDEWAY_EARLY_EXIT && newStatus == "OPEN") {
            int currentSidewayScore = GetCachedSidewaysScore();
            
            // Get highest high / lowest low of last N candles
            int lookback = SIDEWAY_EXIT_CONSECUTIVE_BARS;
            double recentExtreme = trades[i].isLong ?
                iHigh(_Symbol, TF_ARRAY[TF0], iHighest(_Symbol, TF_ARRAY[TF0], MODE_HIGH, lookback, 0)) :
                iLow(_Symbol, TF_ARRAY[TF0], iLowest(_Symbol, TF_ARRAY[TF0], MODE_LOW, lookback, 0));
            
            // Check if price failed to exceed best price (stagnating)
            bool priceStagnating = trades[i].isLong ? 
                (recentExtreme <= trades[i].bestPrice) :  // LONG: highest high didn't exceed best
                (recentExtreme >= trades[i].bestPrice);   // SHORT: lowest low didn't go below best
            
            bool sidewayScoreRising = (trades[i].lastSidewayScore > 0) && (currentSidewayScore > trades[i].lastSidewayScore);
            
            if (priceStagnating && sidewayScoreRising) {
                trades[i].sidewayDriftCount++;
            } else {
                trades[i].sidewayDriftCount = 0;  // Reset if conditions not met
            }
            
            // Update tracking for next bar
            trades[i].lastSidewayScore = currentSidewayScore;
            
            // Exit if consecutive bars threshold reached
            if (trades[i].sidewayDriftCount >= SIDEWAY_EXIT_CONSECUTIVE_BARS) {
                ulong sidewayTicket = trades[i].positionTicket;
                if (sidewayTicket > 0 && PositionSelectByTicket(sidewayTicket)) {
                    string sidewayReason = StringFormat("Sideway: %d bars no new %s, sideway score rising to %d", 
                        trades[i].sidewayDriftCount, trades[i].isLong ? "high" : "low", currentSidewayScore);
                    double actualExitPrice = trades[i].isLong ? 
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    double actualPnLPips = trades[i].isLong ? 
                        (actualExitPrice - trades[i].entryPrice) / pipSize :
                        (trades[i].entryPrice - actualExitPrice) / pipSize;
                    
                    if (SafePositionClose(sidewayTicket, "SIDEWAY EXIT")) {
                        trades[i].earlyExitAlertSent = true;
                        SendAlertForTrade(
                            EMAIL_SUBJECT_PREFIX + " - Sideway Exit",
                            sidewayReason,
                            trades[i],
                            "EARLY_EXIT",
                            sidewayReason,
                            actualExitPrice,
                            actualPnLPips);
                        
                        if(showDebug) Print("[SIDEWAY EXIT] ", trades[i].id, " ", sidewayReason, 
                                           " PnL=", DoubleToString(actualPnLPips, 1), " pips");
                        CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
                        newStatus = trades[i].status;
                    }
                }
            }
        }

        // ICHIMOKU CLOUD EARLY EXIT: Exit if price closes inside cloud for N consecutive bars
        if (allowQualityDropCheck && newStatus == "OPEN") {
            int cloudEntryNum = GetEntryNumber(trades[i].entryType);
            EntryBase* entryForCloud = GetEntryForType(trades[i].entryType);
            bool enableCloudExit = (entryForCloud != NULL) ? entryForCloud.GetExitInIchiCloud() : false;
            
            if (enableCloudExit) {
                // Get CURRENT bar (bar 0) cloud values - not cached values which use ENTRY_SHIFT
                // For exit logic, we need to check if the LAST CLOSED bar is inside cloud
                double tempBuffer[];
                ArrayResize(tempBuffer, 1);
                ArraySetAsSeries(tempBuffer, true);
                
                // MQL5 iIchimoku buffer indices:
                // 0 = Tenkan-sen, 1 = Kijun-sen, 2 = Senkou Span A, 3 = Senkou Span B, 4 = Chikou
                double spanA = 0, spanB = 0;
                if (CopyBuffer(ichimokuHandles[0], 2, 0, 1, tempBuffer) > 0) spanA = tempBuffer[0];  // Senkou Span A
                if (CopyBuffer(ichimokuHandles[0], 3, 0, 1, tempBuffer) > 0) spanB = tempBuffer[0];  // Senkou Span B
                
                double cloudTop = MathMax(spanA, spanB);
                double cloudBottom = MathMin(spanA, spanB);
                double closePrice = iClose(_Symbol, TF_ARRAY[TF0], 0);  // Current bar close
                
                // Directional cloud exit check:
                // - Long: price closes BELOW cloud top (lost bullish momentum)
                // - Short: price closes ABOVE cloud bottom (lost bearish momentum)
                bool cloudExitCondition = trades[i].isLong ? 
                    (closePrice < cloudTop) :   // Long: below cloud top = bearish
                    (closePrice > cloudBottom); // Short: above cloud bottom = bullish
                
                if (cloudExitCondition) {
                    trades[i].insideCloudCount++;
                    if(showDebug) Print("[CLOUD CHECK] ", trades[i].id, 
                                       trades[i].isLong ? " LONG below cloudTop" : " SHORT above cloudBottom",
                                       " count=", trades[i].insideCloudCount,
                                       " close=", DoubleToString(closePrice, 5), 
                                       " cloudTop=", DoubleToString(cloudTop, 5),
                                       " cloudBottom=", DoubleToString(cloudBottom, 5));
                } else {
                    if (trades[i].insideCloudCount > 0 && showDebug) 
                        Print("[CLOUD CHECK] ", trades[i].id, " back in favorable zone, reset count");
                    trades[i].insideCloudCount = 0;  // Reset if price recovers
                }
                
                // Exit if consecutive bars threshold reached
                if (trades[i].insideCloudCount >= ICHI_CLOUD_EXIT_BARS) {
                    ulong cloudTicket = trades[i].positionTicket;
                    if (cloudTicket > 0 && PositionSelectByTicket(cloudTicket)) {
                        string cloudReason = StringFormat("E%d: Price %s cloud %s for %d bars - alignment lost", 
                            cloudEntryNum, 
                            trades[i].isLong ? "below" : "above",
                            trades[i].isLong ? "top" : "bottom",
                            trades[i].insideCloudCount);
                        double actualExitPrice = trades[i].isLong ? 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                        double actualPnLPips = trades[i].isLong ? 
                            (actualExitPrice - trades[i].entryPrice) / pipSize :
                            (trades[i].entryPrice - actualExitPrice) / pipSize;
                        
                        if (SafePositionClose(cloudTicket, "CLOUD EXIT")) {
                            trades[i].earlyExitAlertSent = true;
                            SendAlertForTrade(
                                EMAIL_SUBJECT_PREFIX + " - Cloud Exit",
                                cloudReason,
                                trades[i],
                                "EARLY_EXIT",
                                cloudReason,
                                actualExitPrice,
                                actualPnLPips);
                            
                            if(showDebug) Print("[CLOUD EXIT] ", trades[i].id, " ", cloudReason, 
                                               " PnL=", DoubleToString(actualPnLPips, 1), " pips");
                            CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
                            newStatus = trades[i].status;
                        }
                    }
                }
            }
        }

        bool panicExitHandled = false;
        bool fastPanicExit = false;
        int panicEntryNum = GetEntryNumber(trades[i].entryType);
        EntryBase* entryForPanic = GetEntryForType(trades[i].entryType);
        bool enablePanicExit = (entryForPanic != NULL) ? entryForPanic.GetEnablePanicADXExit() : true;
        if (enablePanicExit) {
            // Calculate current floating PnL
            double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], 0);
            double floatingPnL = trades[i].isLong ?
                (currentPrice - trades[i].entryPrice) :
                (trades[i].entryPrice - currentPrice);
            
            // Check if loss/giveback is SIGNIFICANT enough to warrant panic
            bool shouldCheckReversal = false;
            string panicReason = "";
            
            // Scenario A: Profit protection - only if giving back significant profit
            if (trades[i].hasTakenPartialProfit && floatingPnL > 0) {
                double mfe = trades[i].isLong ? 
                            (trades[i].bestPrice - trades[i].entryPrice) : 
                            (trades[i].entryPrice - trades[i].bestPrice);
                if (mfe > 0) {
                    double givebackRatio = (mfe - floatingPnL) / mfe;
                    if (givebackRatio >= PANIC_MIN_PROFIT_GIVEBACK) {
                        shouldCheckReversal = true;
                        panicReason = StringFormat("Profit giveback %.1f%%", givebackRatio * 100);
                    }
                }
            }
            
            // Scenario B: Loss prevention - only if used significant portion of SL
            // E3 uses lower threshold (counter-trend needs faster exit)
            if (!shouldCheckReversal && floatingPnL < 0) {
                double slDistance = MathAbs(trades[i].stopLoss - trades[i].entryPrice);
                if (slDistance > 0) {
                    double usedSLRatio = (-floatingPnL) / slDistance;
                    double panicThreshold = (entryForPanic != NULL) ? entryForPanic.GetPanicMinSLUsedRatio() : PANIC_MIN_SL_USED_RATIO;
                    if (usedSLRatio >= panicThreshold) {
                        shouldCheckReversal = true;
                        panicReason = StringFormat("Used %.1f%% of SL", usedSLRatio * 100);
                    }
                }
            }
            
            if (shouldCheckReversal) {
                TREND_STATE reversedDirection = trades[i].isLong ? TREND_BEAR : TREND_BULL;
                
                // Multi-timeframe cascade detection:
                // LEVEL 1: M1 early warning (2-3 bars, 2-3 min) - catches reversal early
                // LEVEL 2: M3 conviction (at least 2 bars, 6 min) - confirms it's real
                // Both must agree to filter M1 noise while maintaining detection speed
                bool m1ReversalDetected = HasTrendAcceleration(TF_ARRAY[TF0], reversedDirection, 4, 9);
                bool m3ReversalConfirmed = HasTrendAcceleration(TF_ARRAY[TF1], reversedDirection, 3, 14);
                
                // Panic exit only if BOTH M1 detects AND M3 confirms (multi-timeframe agreement)
                if (m1ReversalDetected && m3ReversalConfirmed) {
                    fastPanicExit = true;
                    if(showDebug) {
                        Print("[PANIC EXIT] Trade #", trades[i].id, " - ", panicReason, ": ",
                              "M1(3-bar) + M3(2-bar) both confirm sustained reversal, FloatingPnL=", 
                              DoubleToString(floatingPnL / pipSize, 1), " pips");
                    }
                }
            }
        }

        if (fastPanicExit) {
            ulong panicTicket = trades[i].positionTicket;
            if (panicTicket > 0 && PositionSelectByTicket(panicTicket)) {
                string panicReason = "Fast trend reversal early exit";
                // Capture exit price BEFORE close (current market price)
                double actualExitPrice = trades[i].isLong ? 
                    SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                double actualPnLPips = trades[i].isLong ? 
                    (actualExitPrice - trades[i].entryPrice) / pipSize :
                    (trades[i].entryPrice - actualExitPrice) / pipSize;
                
                if (SafePositionClose(panicTicket, "PANIC EXIT")) {
                    trades[i].earlyExitAlertSent = true;
                    SendAlertForTrade(
                        EMAIL_SUBJECT_PREFIX + " - Trend Reversal Early Exit",
                        panicReason,
                        trades[i],
                        "EARLY_EXIT",
                        panicReason,
                        actualExitPrice,
                        actualPnLPips);
                    
                    if(showDebug) Print("Fast trend reversal early exit: Closed #", panicTicket, " ", trades[i].id);
                    CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
                    newStatus = trades[i].status;
                    brokerCheckWasCalled = true;
                    panicExitHandled = true;
                }
            }
        }

        // Early-cut failsafe when price nears SL and momentum is not supportive
        if (!panicExitHandled && ENABLE_EARLY_CUT_NEAR_SL && newStatus == "OPEN") {
            bool shouldExitEarly = false;
            TREND_STATE reversedDirection = trades[i].isLong ? TREND_BEAR : TREND_BULL;
            
            // RULE 1: Always exit if super strong opposing momentum (regardless of entry type)
            shouldExitEarly = HasTrendAcceleration(TF_ARRAY[TF1], reversedDirection, 3);

            if (!shouldExitEarly) {
                double totalSLDist = trades[i].isLong ? (trades[i].entryPrice - trades[i].stopLoss) : (trades[i].stopLoss - trades[i].entryPrice);
                if (totalSLDist > 0) {
                    double reached = trades[i].isLong ? (trades[i].entryPrice - currentPrice) / totalSLDist
                                            : (currentPrice - trades[i].entryPrice) / totalSLDist;
                    
                    // Get appropriate early cut ratio based on entry type
                    EntryBase* entryForCut = GetEntryForType(trades[i].entryType);
                    double earlyCutRatio = (entryForCut != NULL) ? entryForCut.GetEarlyCutRatio() : 0.88;
                    
                    if (reached >= earlyCutRatio) {
                        // Check both momentum state AND trend direction
                        bool momentumInsufficient = !HasSufficientMomentum(trades[i].isLong ? TREND_BULL : TREND_BEAR);
                        bool trendWeakening = IsTrendWeakening(trades[i].isLong);
                        
                        // Exit if momentum insufficient OR trend is weakening (v1.7.92 enhancement)
                        shouldExitEarly = momentumInsufficient || trendWeakening;
                        
                        if(showDebug && shouldExitEarly) {
                            string reason = momentumInsufficient ? "momentum insufficient" : "trend weakening";
                            Print("[EARLY CUT] ", trades[i].type, " at ", DoubleToString(reached*100,1), "% to SL - ", reason);
                        }
                    }
                }
            }

            if (shouldExitEarly) {
                ulong tkt = trades[i].positionTicket;
                if (tkt > 0 && PositionSelectByTicket(tkt)) {
                    string earlyExitReason = "Early Exit when price moves strongly to SL";
                    // Capture exit price BEFORE close (current market price)
                    double actualExitPrice = trades[i].isLong ? 
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                    double actualPnLPips = trades[i].isLong ? 
                        (actualExitPrice - trades[i].entryPrice) / pipSize :
                        (trades[i].entryPrice - actualExitPrice) / pipSize;

                    bool closed = SafePositionClose(tkt, "EARLY EXIT");
                    if (closed) {
                        trades[i].earlyExitAlertSent = true;
                        SendAlertForTrade(
                            EMAIL_SUBJECT_PREFIX + " - Early Exit",
                            earlyExitReason,
                            trades[i],
                            "EARLY_EXIT",
                            earlyExitReason,
                            actualExitPrice,
                            actualPnLPips
                        );
                        
                        PrintDebug("EARLY CUT NEAR SL: Closed #" + IntegerToString(tkt) + " " + trades[i].id);                                
                        // SAFETY: Validate index before status update
                        if (i >= ArraySize(trades)) return;
                        
                        // Update trade status immediately
                        CheckTradeStatusOnBrokerBeforeUpdating(trades[i]);
                        newStatus = trades[i].status;
                    } else {
                        PrintDebug("EARLY CUT FAILED: #" + IntegerToString(tkt) + " ret=" + IntegerToString((int)trade.ResultRetcode()));
                    }
                }
            }
        
        }
    }
    
    //--------------------------------------------------------------------
    // HELPER METHODS
    //--------------------------------------------------------------------
    // v1.7.94: Returns actual execution price via reference for profit validation
    bool ExecutePartialTakeProfit(int tradeIndex, double ratio, double &executionPrice) {
        executionPrice = 0;
        if(ratio <= 0 || ratio >= 1) return false;
        
        ulong ticket = trades[tradeIndex].positionTicket;
        if(ticket <= 0) {
            if(showDebug) Print("ExecutePartialTakeProfit ERROR: Invalid ticket for ", trades[tradeIndex].id);
            return false;
        }
        
        if(!PositionSelectByTicket(ticket)) {
            if(showDebug) Print("ExecutePartialTakeProfit ERROR: Position not found for ticket #", ticket);
            return false;
        }
        
        if(IsPositionFrozen()) return false;
        
        double vol = PositionGetDouble(POSITION_VOLUME);
        double volToClose = NormalizeLotSize(vol * ratio);
        double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        if(volToClose < minVol) volToClose = minVol;
        
        if(!trade.PositionClosePartial(ticket, volToClose)) {
            Print("ERROR: Partial TP failed retcode=", trade.ResultRetcode());
            return false;
        }
        
        // v1.7.94: Get ACTUAL execution price from broker (not iClose!)
        executionPrice = trade.ResultPrice();
        if(executionPrice <= 0) {
            // Fallback: use current market price if ResultPrice not available
            executionPrice = trades[tradeIndex].isLong ? 
                SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        }
        
        if(showDebug) Print("PARTIAL TP executed: closed ", volToClose, " lots for ", trades[tradeIndex].id, " at ", executionPrice);
        trades[tradeIndex].lotSize = vol - volToClose;
        
        // Update PnL using actual execution price
        trades[tradeIndex].pnL = trades[tradeIndex].isLong ? 
            (executionPrice - trades[tradeIndex].entryPrice) * volToClose * contractSize : 
            (trades[tradeIndex].entryPrice - executionPrice) * volToClose * contractSize;
        
        // Alert for partial take profit
        string ptpSubject = EMAIL_SUBJECT_PREFIX + " - Partial TP";
        string ptpMsg = StringFormat("PARTIAL TP: %s | %s | Closed %.2f lots, Remaining %.2f | ExecPrice: %.2f, Entry: %.2f, TP: %.2f",
                                    _Symbol,
                                    trades[tradeIndex].id,
                                    volToClose,
                                    trades[tradeIndex].lotSize,
                                    executionPrice,
                                    trades[tradeIndex].entryPrice,
                                    trades[tradeIndex].takeProfit);
        SendAlertForTrade(ptpSubject, ptpMsg, trades[tradeIndex], AlertTypeToString(ALERT_PARTIAL_TP), "Partial TP taken");
        
        // Track partial TP for adaptive learning
        EntryBase* entry = GetEntryForType(trades[tradeIndex].entryType);
        if (entry != NULL) {
            double closedPips = MathAbs(executionPrice - trades[tradeIndex].entryPrice) / pipSize;
            double partialPnL = closedPips * contractSize * volToClose;
            double simulatedFullPnL = closedPips * contractSize * vol;
            entry.TrackPartialTP(partialPnL, simulatedFullPnL);
        }
        
        return true;
    }

    // Update dynamic TP extension parameters based on ATR M1
    void UpdateDynamicTPExtension() {
        // BUG FIX: Always set fallback to input param minimum (not hardcoded 6.0)
        if (!USE_DYNAMIC_TP_EXTENSION || !cache.valid || cache.atrM1 <= 0) {
            dynamicTPExtensionPips = TP_EXTENSION_MIN_PIPS;
            dynamicTPExtensionTrigger = dynamicTPExtensionPips * 2.0;
            return;
        }
        
        // ATR-based calculation: extension = ATR × multiplier (0.15 = survive 9 sec move)
        double atrPips = cache.atrM1 / pipSize;
        
        // Calculate extension amount, clamped to safety bounds
        dynamicTPExtensionPips = atrPips * ATR_TP_EXTENSION_MULTIPLIER;
        dynamicTPExtensionPips = MathMax(TP_EXTENSION_MIN_PIPS, MathMin(TP_EXTENSION_MAX_PIPS, dynamicTPExtensionPips));
        
        // Trigger = 2x extension distance
        dynamicTPExtensionTrigger = dynamicTPExtensionPips * 2.0;
    }
};

#endif // TRADEMANAGER_MQH
