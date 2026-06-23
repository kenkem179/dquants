#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef BROKER_HELPERS_MQH
#define BROKER_HELPERS_MQH

//================================================================
// BROKER HELPERS
// Simple, reusable functions with no complex dependencies
//================================================================

//+------------------------------------------------------------------+
//| Modify position SL/TP by trade ID                               |
//+------------------------------------------------------------------+
// Direct ticket-based position modification (no comment search)
bool ModifyPositionSLTP(Trade &tradeObj, double newSL, double newTP, string actionDescription = "") {
    if(tradeObj.positionTicket <= 0) {
        if(showDebug) Print(actionDescription, " ERROR: Invalid position ticket for ", tradeObj.id);
        return false;
    }
    
    if(!PositionSelectByTicket(tradeObj.positionTicket)) {
        if(showDebug) Print(actionDescription, " ERROR: Position not found for ticket #", tradeObj.positionTicket, " (", tradeObj.id, ")");
        return false;
    }
    
    // Check if market is open before attempting modification
    if(!IsMarketOpen()) {
        // Silently skip modification when market is closed - no need to spam logs
        return false;
    }
                
    // Get current SL/TP to check if change is needed
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    
    // Only modify if there's a meaningful change (more than 1 point)
    if(MathAbs(currentSL - newSL) > _Point || MathAbs(currentTP - newTP) > _Point) {
        // Guard: skip modification if position is already frozen or new values violate broker
        // distance requirements. Frozen = existing SL/TP within stop/freeze level of market.
        // Any modification on a frozen position is rejected by the broker (including PositionClose).
        double stopLevel   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
        double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
        double spread      = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
        double effectiveMin = MathMax(MathMax(stopLevel, freezeLevel), spread);
        if(effectiveMin <= 0) effectiveMin = 10 * _Point;
        
        long posType = PositionGetInteger(POSITION_TYPE);
        bool posIsLong = (posType == POSITION_TYPE_BUY);
        double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        // Check 1: existing SL frozen (SL too close to market)
        if(currentSL > 0) {
            double slRef = posIsLong ? bidPrice : askPrice;
            if((posIsLong ? (slRef - currentSL) : (currentSL - slRef)) < effectiveMin) {
                if(showDebug) Print(actionDescription, " SKIP: position frozen by currentSL=", currentSL);
                return false;
            }
        }
        // Check 2: existing TP frozen (TP too close to market — price approaching TP)
        if(currentTP > 0) {
            double tpRef = posIsLong ? askPrice : bidPrice;
            if((posIsLong ? (currentTP - tpRef) : (tpRef - currentTP)) < effectiveMin) {
                if(showDebug) Print(actionDescription, " SKIP: position frozen by currentTP=", currentTP);
                return false;
            }
        }
        // Check 3: new SL would freeze position
        if(newSL > 0) {
            double slRef = posIsLong ? bidPrice : askPrice;
            if((posIsLong ? (slRef - newSL) : (newSL - slRef)) < effectiveMin) {
                if(showDebug) Print(actionDescription, " SKIP: newSL=", newSL, " within ", effectiveMin/_Point, " pts of market");
                return false;
            }
        }
        // Check 4: new TP too close to market
        if(newTP > 0) {
            double tpRef = posIsLong ? askPrice : bidPrice;
            if((posIsLong ? (newTP - tpRef) : (tpRef - newTP)) < effectiveMin) {
                if(showDebug) Print(actionDescription, " SKIP: newTP=", newTP, " within ", effectiveMin/_Point, " pts of market");
                return false;
            }
        }
        if(trade.PositionModify(tradeObj.positionTicket, newSL, newTP)) {
            if(showDebug) Print(actionDescription, " APPLIED: Ticket=", tradeObj.positionTicket, " SL=", newSL, " TP=", newTP);
            return true;
        } else {
            if(showDebug) Print(actionDescription, " FAILED: Ticket=", tradeObj.positionTicket, " Error=", trade.ResultRetcode(), " Description=", trade.ResultRetcodeDescription());
            return false;
        }
    }
    return true; // No change needed is considered success
}

// Returns true when the selected position is within the broker's freeze/stop level.
// Caller must have already called PositionSelectByTicket() successfully.
// Both PositionClose() and PositionClosePartial() are rejected while frozen.
bool IsPositionFrozen() {
    double stopLevel   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    double spread      = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
    double effectiveMin = MathMax(MathMax(stopLevel, freezeLevel), spread);
    if(effectiveMin <= 0) effectiveMin = 10 * _Point;
    bool posIsLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
    double bidPrice  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double askPrice  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    if(currentSL > 0) {
        double slRef = posIsLong ? bidPrice : askPrice;
        if((posIsLong ? (slRef - currentSL) : (currentSL - slRef)) < effectiveMin) return true;
    }
    if(currentTP > 0) {
        double tpRef = posIsLong ? askPrice : bidPrice;
        if((posIsLong ? (currentTP - tpRef) : (tpRef - currentTP)) < effectiveMin) return true;
    }
    return false;
}

// Close a position only when it is not broker-frozen (SL or TP within stop/freeze level).
// Frozen positions have PositionClose() rejected by the broker same as PositionModify().
// When frozen, skip — the position closes naturally at its SL/TP.
bool SafePositionClose(ulong ticket, string actionDescription = "") {
    if(!PositionSelectByTicket(ticket)) return false;
    if(IsPositionFrozen()) {
        if(showDebug) Print(actionDescription, " CLOSE SKIP: position frozen (SL/TP within broker stop/freeze level)");
        return false;
    }
    return trade.PositionClose(ticket);
}

//+------------------------------------------------------------------+
//| Process new entry signal (matching Pine Script exactly)         |
//+------------------------------------------------------------------+
void NormalizePriceToTickSize(double &price) {
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tickSize > 0) {
        price = MathRound(price/tickSize) * tickSize;
    }
}

// Normalize lot size to broker requirements
double NormalizeLotSize(double lotSize) {
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double volLimit= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT); // max TOTAL vol per symbol/dir (0=none)

    // Ceiling = broker per-order max AND the per-symbol/direction limit (prevents the
    // "Volume limit reached" reject when a large deposit sizes a big lot). Floor the
    // ceiling to a valid step so a later round can never push the lot back over it.
    double ceil = maxLot;
    if(volLimit > 0 && volLimit < ceil) ceil = volLimit;
    if(lotStep > 0) ceil = MathFloor(ceil / lotStep) * lotStep;

    if(lotSize > ceil) lotSize = ceil;
    if(lotStep > 0) lotSize = MathRound(lotSize / lotStep) * lotStep;  // existing rounding preserved
    if(lotSize > ceil) lotSize = ceil;                                 // re-cap if rounding stepped over

    // Final validation
    if(lotSize < minLot) lotSize = minLot;

    return lotSize;
}

// Validate SL/TP distances according to broker requirements
// Uses current market price (not entry price) and respects both stop level and freeze level.
bool ValidateSLTPDistances(double entryPrice, double &sl, double &tp, bool isLong) {
    double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double freezeLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    double spread       = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
    double effectiveMin = MathMax(MathMax(minStopLevel, freezeLevel), spread);
    if(effectiveMin == 0) effectiveMin = 10 * _Point; // Fallback: 1 pip minimum
    
    // SL must be at least effectiveMin away from current market price (BID for long, ASK for short)
    double slRefPrice = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if(sl > 0) {
        double slDistance = isLong ? (slRefPrice - sl) : (sl - slRefPrice);
        if(slDistance < effectiveMin) {
            sl = isLong ? slRefPrice - effectiveMin : slRefPrice + effectiveMin;
            NormalizePriceToTickSize(sl);
        }
    }
    
    // TP must be at least effectiveMin away from current market price (ASK for long, BID for short)
    double tpRefPrice = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(tp > 0) {
        double tpDistance = isLong ? (tp - tpRefPrice) : (tpRefPrice - tp);
        if(tpDistance < effectiveMin) {
            tp = isLong ? tpRefPrice + effectiveMin : tpRefPrice - effectiveMin;
            NormalizePriceToTickSize(tp);
        }
    }
    
    return true;
}

void CheckTradeStatusOnBrokerBeforeUpdating(Trade &dTrade) {
    // Use stored position ticket directly
    bool positionExists = (dTrade.positionTicket > 0 && PositionSelectByTicket(dTrade.positionTicket));

    // Check if position was found on chart
    if (!positionExists) {
        // Position not found - determine close reason using candle data and proximity
        // Check current bar (0) first, then previous bar (1) as fallback
        double closePrice = iClose(_Symbol, TF_ARRAY[TF0], 0);
        
        // Calculate proximity thresholds (use spread or small pip buffer)
        double proximityBuffer = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point, 15 * pipSize);
        
        bool hitSL = false;
        bool hitTP = false;
        
        // Check current bar (0) first - position close detected immediately
        double currentHigh = iHigh(_Symbol, TF_ARRAY[TF0], 0);
        double currentLow = iLow(_Symbol, TF_ARRAY[TF0], 0);
        double prevHigh = currentHigh;
        double prevLow = currentLow;
        
        if (dTrade.isLong) {
            // LONG: SL hit if low touched SL (exact), TP hit if high reached near TP (with buffer)
            hitSL = (currentLow <= dTrade.stopLoss);
            hitTP = (currentHigh >= dTrade.takeProfit - proximityBuffer);
        } else {
            // SHORT: SL hit if high touched SL (exact), TP hit if low reached near TP (with buffer)
            hitSL = (currentHigh >= dTrade.stopLoss);
            hitTP = (currentLow <= dTrade.takeProfit + proximityBuffer);
        }
        
        // Fallback: Check previous bar (1) if neither hit detected on current bar
        if (!hitTP && !hitSL) {
            prevHigh = iHigh(_Symbol, TF_ARRAY[TF0], 1);
            prevLow = iLow(_Symbol, TF_ARRAY[TF0], 1);
            closePrice = iClose(_Symbol, TF_ARRAY[TF0], 1);
            
            if (dTrade.isLong) {
                hitSL = (prevLow <= dTrade.stopLoss);
                hitTP = (prevHigh >= dTrade.takeProfit - proximityBuffer);
            } else {
                hitSL = (prevHigh >= dTrade.stopLoss);
                hitTP = (prevLow <= dTrade.takeProfit + proximityBuffer);
            }
        }
        
        // Determine close price and reason
        // Prioritize TP if price is closer to TP than SL (positive outcome bias)
        double distanceToSL = MathAbs(closePrice - dTrade.stopLoss);
        double distanceToTP = MathAbs(closePrice - dTrade.takeProfit);
        
        if (hitTP && hitSL) {
            // Both levels touched - use proximity to determine which was hit
            if (distanceToTP <= distanceToSL) {
                hitSL = false;  // Closer to TP, mark as TP hit
                closePrice = dTrade.takeProfit;
            } else {
                hitTP = false;  // Closer to SL, mark as SL hit
                closePrice = dTrade.stopLoss;
            }
        } else if (hitTP) {
            closePrice = dTrade.takeProfit;
        } else if (hitSL) {
            closePrice = dTrade.stopLoss;
        }
        // else: closePrice remains as iClose (early exit/session end)
        
        // Calculate PnL using estimated close price
        double closedPnL = dTrade.isLong ? 
            (closePrice - dTrade.entryPrice) * dTrade.lotSize * contractSize : 
            (dTrade.entryPrice - closePrice) * dTrade.lotSize * contractSize;
        dTrade.pnL = closedPnL;
        
        // Determine if this is a loss (original logic for alerts/logging)
        bool isLoss = hitSL ? (dTrade.pnL <= 0) : (dTrade.pnL < 0);
        
        // Categorize exit for session tracking (based on trade state, not just PnL):
        // 1. Real Loss: SL hit with negative PnL OR early exit with negative PnL
        // 2. Break-even: SL moved to entry AND SL hit AND no partial profit taken
        // 3. Win: Everything else (TP hit, partial taken, positive exit)
        bool isBreakEven = (dTrade.slMovedToBreakeven && hitSL && !dTrade.hasTakenPartialProfit);
        
        if (isLoss && !isBreakEven) {
            sessionLossCount++;
        } else if (isBreakEven) {
            sessionBreakEvenCount++;
        } else {
            sessionWinCount++;
        }
        tradeSLTPCountInSession++;  // Legacy counter (informational)
        if (isLoss) {
            dTrade.status = dTrade.isLong ? "BUY_LOST" : "SELL_LOST";
            PrintDebug("Position #" + IntegerToString(dTrade.positionTicket) + " " + dTrade.id + " closed by SL hit (prev candle high/low: " + DoubleToString(prevHigh, 5) + "/" + DoubleToString(prevLow, 5) + ", SL: " + DoubleToString(dTrade.stopLoss, 5) + ") PnL: " + DoubleToString(dTrade.pnL, 2));
            
            // FIX: Skip sending alert if early exit alert was already sent
            if (!dTrade.earlyExitAlertSent) {
                // Email alert for trade close (LOSS)
                string closeSubjL = EMAIL_SUBJECT_PREFIX + " - Trade CLOSED LOST";
                double pnlPips = dTrade.pnL / (contractSize * dTrade.lotSize * pipSize);
                string closeMsgL = StringFormat("%s | %s CLOSED LOST | Ticket: %s | PnL: %.1f pips",
                                               _Symbol,
                                               dTrade.id,
                                               IntegerToString(dTrade.positionTicket),
                                               pnlPips);
                SendAlertForTrade(closeSubjL, closeMsgL, dTrade, AlertTypeToString(ALERT_CLOSED_LOST), "SL Hit", closePrice, pnlPips);
            }
            
            // Track SL hit for adaptive learning
            EntryBase* entry = GetEntryForType(dTrade.entryType);
            if (entry != NULL) {
                // Get ATR if available (for SL tracking), but don't block adaptive learning if it fails
                double currentATR = 0;
                double atrBuffer[1];
                if (CopyBuffer(g_atrM1Handle, 0, 0, 1, atrBuffer) > 0) {
                    currentATR = atrBuffer[0];
                }
                
                // NOTE: SL capping removed - wasCapped always false
                double slDistance = MathAbs(dTrade.stopLoss - dTrade.entryPrice) / pipSize;
                
                // Only track SL details if ATR is available
                if (currentATR > 0) {
                    entry.TrackSLHit(slDistance, currentATR, false);
                }
                // NOTE: SL capping removed - no longer tracking cap outcomes
                
                // Track trailing SL hit if SL was trailed
                if (dTrade.slWasTrailed) {
                    bool wouldHaveHitTP = false; // TODO: Could analyze if price would have reached original TP
                    bool savedFromLoss = (dTrade.pnL > -100); // Rough heuristic: if loss is small, trailing may have saved from bigger loss
                    entry.TrackTrailingSL(dTrade.pnL, wouldHaveHitTP, savedFromLoss);
                }
                
                // Check if partial was taken
                if (dTrade.hasTakenPartialProfit) {
                    entry.TrackPartialOutcome(false, true, false); // hitTP=false, hitSL=true
                }
                
                // Update breakeven outcome if SL was moved to breakeven
                if (dTrade.slMovedToBreakeven) {
                    entry.TrackBreakeven(false, true);  // Lost after breakeven
                }
                
                // CRITICAL: Update entry-specific performance stats for adaptive learning
                // This MUST run regardless of ATR availability!
                double rrAchieved = 0; // Lost trade, RR = 0
                entry.UpdatePerformance(false, dTrade.pnL, rrAchieved);
            }
        } else {
            // Treat break even with partial profit as "WON"
            dTrade.status = dTrade.isLong ? "BUY_WON" : "SELL_WON";
            
            // Determine actual close reason for accurate reporting
            string closeReason = hitTP ? "TP Hit" : (hitSL ? "SL Hit (+)" : "Early Exit/Session End?");
            PrintDebug("Position #" + IntegerToString(dTrade.positionTicket) + " " + dTrade.id + " closed by " + closeReason + " (prev candle high/low: " + DoubleToString(prevHigh, 5) + "/" + DoubleToString(prevLow, 5) + ", TP: " + DoubleToString(dTrade.takeProfit, 5) + ") PnL: " + DoubleToString(dTrade.pnL, 2));
            
            // FIX: Skip sending alert if early exit alert was already sent
            if (!dTrade.earlyExitAlertSent) {
                // Email alert for trade close (WON)
                string closeSubjW = EMAIL_SUBJECT_PREFIX + " - Trade Closed WON";
                double pnlPips = dTrade.pnL / (contractSize * dTrade.lotSize * pipSize);
                string closeMsgW = StringFormat("%s | %s closed WON | Ticket: %s | PnL: %.1f pips",
                                               _Symbol,
                                               dTrade.id,
                                               IntegerToString(dTrade.positionTicket),
                                               pnlPips);
                SendAlertForTrade(closeSubjW, closeMsgW, dTrade, AlertTypeToString(ALERT_CLOSED_WON), closeReason, closePrice, pnlPips);
            }
            
            // Track TP hit for adaptive learning
            EntryBase* entry = GetEntryForType(dTrade.entryType);
            if (entry != NULL) {
                // Use ORIGINAL SL distance (buffered), not current SL (which may be at breakeven)
                double slDistance = dTrade.bufferedSLDistancePips;
                double tpDistance = MathAbs(dTrade.takeProfit - dTrade.entryPrice) / pipSize;
                double rrAchieved = (slDistance > 0.1) ? (tpDistance / slDistance) : 0;  // Safety: ignore if SL < 0.1 pips
                double rrBest = rrAchieved; // TODO: Track best price during trade
                double drawbackPct = 0; // TODO: Calculate drawback from best
                
                entry.TrackTPHit(tpDistance, rrAchieved, rrBest, drawbackPct);
                // NOTE: SL capping removed - no longer tracking cap outcomes
                
                // Check if partial was taken
                if (dTrade.hasTakenPartialProfit) {
                    entry.TrackPartialOutcome(true, false, false); // hitTP=true, hitSL=false
                }
                
                // Update breakeven outcome if SL was moved to breakeven
                if (dTrade.slMovedToBreakeven) {
                    entry.TrackBreakeven(true, false);  // Won after breakeven
                }
                
                // CRITICAL: Update entry-specific performance stats for adaptive learning
                entry.UpdatePerformance(true, dTrade.pnL, rrAchieved);
            }
        }
        UpdatePerformanceOnExit(dTrade);        
        PrintDebug("*** SESSION STATS *** " + getCurrentTradingSession() + " | W:" + IntegerToString(sessionWinCount) + " L:" + IntegerToString(sessionLossCount) + " BE:" + IntegerToString(sessionBreakEvenCount) + " | Total:" + IntegerToString(tradeSLTPCountInSession) + "/" + IntegerToString(MAX_SLTP_COUNT_PER_SESSION));
    }
}

#endif // BROKER_HELPERS_MQH