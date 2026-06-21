//+------------------------------------------------------------------+
//| Entry5.mqh - E5 SuperBros EMA Alignment (Pine Script parity)    |
//| M1-only 4-EMA alignment, no momentum, sideway block only        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef ENTRY5_MQH
#define ENTRY5_MQH

#include "EntryBase.mqh"

//+------------------------------------------------------------------+
//| Entry5: SuperBros EMA Alignment (ported from Pine SuperBros v1)  |
//| - M1 4-EMA strict alignment (25>75>100>200)                     |
//| - No momentum/ADX/trend quality checks                           |
//| - Sideway blocking only                                          |
//| - SL at EMA200 +/- spread, TP1 at 0.8R (54% of full TP)        |
//+------------------------------------------------------------------+
class Entry5 : public EntryBase {
private:
    // Fresh signal tracking (self-contained, matches Pine SuperBros logic)
    int m_lastBullishSignal;    // bar_index when bullish fresh signal occurred
    int m_lastBearishSignal;    // bar_index when bearish fresh signal occurred
    int m_lastProcessedBar;     // avoid re-processing signals on same bar
    bool m_prevBullishAligned;  // previous bar alignment state
    bool m_prevBearishAligned;
    // Pine v1-stable consumed lock: prevents alignment-onset from re-arming a signal
    // that an open trade already consumed. Released only when alignment breaks AND
    // no position is active in that direction.
    bool m_bullishSignalConsumed;
    bool m_bearishSignalConsumed;
    // Deferred entry tracking (Pine SuperBros parity)
    bool m_deferredBySideway;   // true when valid signal was blocked by multi-TF sideway
    bool m_deferredIsLong;      // direction of deferred signal
    bool m_adxBlockLogged;      // suppress repeated ADX block debug messages
    bool m_tqBlockLogged;       // suppress repeated trend quality block debug messages
    // --- Per-bar trace state (PARITY/diagnostics only; INDEPENDENT of the live Detect()
    //     trigger so the read-only TraceBar() observer never perturbs real trading) ---
    int  m_tr_lastBull;         // bar of last bullish alignment onset (-1 = none)
    int  m_tr_lastBear;
    int  m_tr_lastProcBar;      // once-per-bar onset-tracking guard
    bool m_tr_prevBull;         // previous-bar alignment state
    bool m_tr_prevBear;
    bool m_tr_bullConsumed;     // consumed lock (released when alignment breaks)
    bool m_tr_bearConsumed;
    // --- REAL-PATH trace snapshot (PARITY/diagnostics only). Filled FROM the live
    //     Detect() execution (real onset/adx/gate), read by the EA via GetRealTrace().
    //     Read-only: never mutates the live trigger. ---
    E5RealRow m_rt;

public:
    Entry5() : EntryBase("E5", ENTRY_L_E5, ENABLE_E5_ENTRIES) {
        m_lastBullishSignal = -1;
        m_lastBearishSignal = -1;
        m_lastProcessedBar = -1;
        m_prevBullishAligned = false;
        m_prevBearishAligned = false;
        m_bullishSignalConsumed = false;
        m_bearishSignalConsumed = false;
        m_deferredBySideway = false;
        m_deferredIsLong = false;
        m_adxBlockLogged = false;
        m_tqBlockLogged = false;
        m_tr_lastBull = -1;
        m_tr_lastBear = -1;
        m_tr_lastProcBar = -1;
        m_tr_prevBull = false;
        m_tr_prevBear = false;
        m_tr_bullConsumed = false;
        m_tr_bearConsumed = false;
        InitializeDefaults();
        SaveBaselines();
    }

protected:
    virtual void InitializeDefaults() override {
        m_config.isActive = ENABLE_ADAPTIVE_E5;

        m_config.adaptiveMinTradesFirst = ADAPTIVE_MIN_TRADES_FIRST;
        m_config.adaptiveCheckInterval = ADAPTIVE_CHECK_EVERY_N_TRADES;
        m_config.adaptiveMaxDaysBetween = ADAPTIVE_MAX_DAYS_BETWEEN_ADJUSTMENTS;

        // E5 does NOT use momentum/ADX filters
        m_config.minADX = 0.0;
        m_config.minDISpread = 0.0;
        m_config.highRiskMinADX = 0.0;
        m_config.highRiskMinDISpread = 0.0;

        // Stop Loss (EMA200-based, matching Pine SuperBros)
        m_config.emaDistancePips = SL_EMA_DISTANCE;
        m_config.atrMultiplier = E5_ATR_SL_CAP_MULTIPLIER;
        m_config.useATRBased = E5_USE_ATR_SL_ARBITRATION;
        m_config.minSLSpreadMultiplier = MIN_SL_SPREAD_MULT;

        // Take Profit (RR 1.5, TP1 at 0.8R = 54% of full TP)
        m_config.rewardRatio = E5_RR;
        m_config.rewardRatioSideway = E5_RR_SIDEWAY;
        m_config.partialTPTrigger = E5_PARTIAL_TP_TRIGGER;
        m_config.partialTPRatio = E5_PARTIAL_TP_RATIO;

        // TP Extension
        m_config.maxTPExtensions = E5_MAX_TP_EXTENSIONS;

        // Trailing SL
        m_config.trailingFactor = E5_TRAILING_SL_FACTOR;
        m_config.breakevenBuffer = E5_SL_TO_BREAKEVEN_BUFFER;
        m_config.useADXFilter = false;

        // Early Exit
        m_config.earlyCutSLRatio = E5_EARLY_CUT_SL_RATIO;
        m_config.adxPeriodForExit = 14;
        m_config.minADXToHold = 18.0;

        // Laddered Extensions
        m_config.enableLadderedExtensions = E5_ENABLE_LADDERED_EXTENSIONS;
        m_config.ladderStage1Multiplier = E5_LADDER_STAGE1_MULTIPLIER;
        m_config.ladderStage2Multiplier = E5_LADDER_STAGE2_MULTIPLIER;
        m_config.ladderStage3Multiplier = E5_LADDER_STAGE3_MULTIPLIER;
        m_config.ladderStage1TrailRatio = E5_LADDER_STAGE1_TRAIL_RATIO;
        m_config.ladderStage2TrailRatio = E5_LADDER_STAGE2_TRAIL_RATIO;
        m_config.ladderStage3TrailRatio = E5_LADDER_STAGE3_TRAIL_RATIO;

        ValidateAndClampParams();
    }

public:
    virtual DetectionResult Detect() override {
        DetectionResult result;
        result.detected = false;
        result.rawSLDistancePips = 0.0;
        result.bufferedSLDistancePips = 0.0;

        // PARITY: reset the real-path trace snapshot for this bar (read-only diagnostics).
        RTReset();

        // Session loss limit check
        if (sessionLossCount >= MAX_SESSION_LOSSES) {
            if(showDebug) Print("[E5] Session loss limit reached: ", sessionLossCount, "/", MAX_SESSION_LOSSES);
            RTArmedFromState(); m_rt.gate = "session_limit"; return result;
        }
        if (tradeSLTPCountInSession > MAX_SLTP_COUNT_PER_SESSION) {
            if(showDebug) Print("[E5] Session trade limit reached: ", tradeSLTPCountInSession);
            RTArmedFromState(); m_rt.gate = "session_limit"; return result;
        }

        // ADX momentum gate: reject entries in weak/choppy markets
        if (E5_MIN_MOMENTUM_ADX > 0 && cache.adx[0] < E5_MIN_MOMENTUM_ADX) {
            if(showDebug && !m_adxBlockLogged) {
                Print("[E5] Blocked: M1 ADX ", DoubleToString(cache.adx[0], 1),
                      " < ", DoubleToString(E5_MIN_MOMENTUM_ADX, 1));
                m_adxBlockLogged = true;
            }
            RTArmedFromState();
            m_rt.adx_m1 = cache.adx[0]; m_rt.min_adx = E5_MIN_MOMENTUM_ADX; m_rt.adx_pass = 0;
            m_rt.atr_m1 = cache.atrM1; m_rt.gate = "adx_gate";
            return result;
        }
        m_rt.adx_m1 = cache.adx[0]; m_rt.min_adx = E5_MIN_MOMENTUM_ADX; m_rt.adx_pass = 1;
        m_adxBlockLogged = false;  // Reset when ADX passes — log again on next block

        double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);

        // Check open positions - prevent duplicate E5
        int checkOpenLE1, checkOpenSE1, checkOpenLE2, checkOpenSE2, checkOpenLE3, checkOpenSE3;
        int checkOpenLE4, checkOpenSE4, checkOpenLE5, checkOpenSE5;
        CheckOpenPositions(checkOpenLE1, checkOpenSE1, checkOpenLE2, checkOpenSE2,
                           checkOpenLE3, checkOpenSE3, checkOpenLE4, checkOpenSE4,
                           checkOpenLE5, checkOpenSE5);

        // --- M1 4-EMA strict alignment (no tolerance, matches Pine SuperBros) ---
        double ema25  = GetEMA(TF0, EMA1, ENTRY_SHIFT);
        double ema75  = GetEMA(TF0, EMA2, ENTRY_SHIFT);
        double ema100 = GetEMA(TF0, EMA3, ENTRY_SHIFT);
        double ema200 = GetEMA(TF0, EMA4, ENTRY_SHIFT);

        bool isBullishAligned = (ema25 > ema75) && (ema75 > ema100) && (ema100 > ema200);
        bool isBearishAligned = (ema25 < ema75) && (ema75 < ema100) && (ema100 < ema200);

        // --- Update fresh signal tracking (once per bar, Pine v1-stable parity) ---
        // Pine v1-stable: ONLY alignment onset resets the timer. The consumed lock
        // prevents calc_on_every_tick / mid-trade alignment flickers from re-arming
        // a signal an open trade has already consumed.
        int thisBar = currentBar;
        if (thisBar != m_lastProcessedBar) {
            m_lastProcessedBar = thisBar;

            // Alignment onset (EMAs just aligned this bar)
            bool bullishOnset = isBullishAligned && !m_prevBullishAligned;
            bool bearishOnset = isBearishAligned && !m_prevBearishAligned;

            if (bullishOnset && !m_bullishSignalConsumed)
                m_lastBullishSignal = thisBar;
            if (bearishOnset && !m_bearishSignalConsumed)
                m_lastBearishSignal = thisBar;

            // Invalidate when alignment breaks. Release the consumed lock only when
            // no position is active in that direction — otherwise a mid-trade
            // alignment flicker would re-arm the consumed signal the moment the
            // open trade closes.
            if (!isBullishAligned) {
                m_lastBullishSignal = -1;
                if (checkOpenLE5 == -1)
                    m_bullishSignalConsumed = false;
            }
            if (!isBearishAligned) {
                m_lastBearishSignal = -1;
                if (checkOpenSE5 == -1)
                    m_bearishSignalConsumed = false;
            }

            // Save state for next bar
            m_prevBullishAligned = isBullishAligned;
            m_prevBearishAligned = isBearishAligned;
        }

        // --- Entry triggers (alignment + price on right side of EMA25 + within maxCrossAge) ---
        bool bullishTrigger = isBullishAligned && m_lastBullishSignal != -1
                              && (thisBar - m_lastBullishSignal) <= E5_MAX_EMA_CROSS_AGE
                              && currentPrice > ema25;

        bool bearishTrigger = isBearishAligned && m_lastBearishSignal != -1
                              && (thisBar - m_lastBearishSignal) <= E5_MAX_EMA_CROSS_AGE
                              && currentPrice < ema25;

        // PARITY: snapshot the REAL trigger state (onset ages captured BEFORE any consume).
        m_rt.armed_dir    = (m_lastBullishSignal != -1) ? 1 : ((m_lastBearishSignal != -1) ? -1 : 0);
        m_rt.up_age       = (m_lastBullishSignal != -1) ? (thisBar - m_lastBullishSignal) : -1;
        m_rt.dn_age       = (m_lastBearishSignal != -1) ? (thisBar - m_lastBearishSignal) : -1;
        m_rt.aligned_bull = isBullishAligned ? 1 : 0;
        m_rt.aligned_bear = isBearishAligned ? 1 : 0;
        m_rt.price        = currentPrice;
        m_rt.ema25        = ema25;
        m_rt.ema200       = ema200;
        m_rt.atr_m1       = cache.atrM1;
        // PARITY value-diff: full M1 4-EMA stack + M1 DI + M5/M15 HTF ADX/DI (the exact
        // inputs the alignment-onset / trend-core / HTF gates read), for engine value-diff.
        m_rt.ema75        = ema75;
        m_rt.ema100       = ema100;
        m_rt.m1_diplus    = cache.diPlus[0];
        m_rt.m1_diminus   = cache.diMinus[0];
        m_rt.m5_adx       = cache.adx[2];
        m_rt.m5_diplus    = cache.diPlus[2];
        m_rt.m5_diminus   = cache.diMinus[2];
        m_rt.m15_adx      = cache.adx[3];
        m_rt.m15_diplus   = cache.diPlus[3];
        m_rt.m15_diminus  = cache.diMinus[3];
        m_rt.price_ok     = ((m_rt.armed_dir >= 0 && currentPrice > ema25) ||
                             (m_rt.armed_dir <  0 && currentPrice < ema25)) ? 1 : 0;

        // --- Trend Quality Score gate (parity with E1/E2/E4) ---
        // Reuses GetTrendQualityScore (Core/TrendIdentifier.mqh:125). entryNum=5 excludes
        // the Ichimoku component AND skips the per-component hard gate, so score range
        // matches Pine v1-stable's 0-11 with pure-sum semantics.
        // MIN_TREND_QUALITY_E5=0 disables (Pine "0 disables" semantics).
        int trendQualityE5 = 0;
        if (bullishTrigger || bearishTrigger) {
            TREND_STATE tqState = bullishTrigger ? TREND_BULL : TREND_BEAR;
            trendQualityE5 = GetTrendQualityScore(tqState, 5);
            if (MIN_TREND_QUALITY_E5 > 0 && trendQualityE5 < MIN_TREND_QUALITY_E5) {
                if(showDebug && !m_tqBlockLogged) {
                    Print("[E5] Blocked: trend quality ", trendQualityE5,
                          "/11 < ", MIN_TREND_QUALITY_E5);
                    m_tqBlockLogged = true;
                }
                TrackEntryAttempt(bullishTrigger ? "L-E5" : "S-E5", false, "trend_quality");
                bullishTrigger = false;
                bearishTrigger = false;
            } else {
                m_tqBlockLogged = false;  // gate passed — re-arm log on next block
            }
        }
        // PARITY: record trend-quality outcome (real path).
        m_rt.trend_quality = trendQualityE5;
        m_rt.tq_pass = (MIN_TREND_QUALITY_E5 <= 0 || trendQualityE5 >= MIN_TREND_QUALITY_E5) ? 1 : 0;

        // --- HTF trend direction filter (block entries against higher timeframe trend) ---
        bool htfBlockLong = false, htfBlockShort = false;
        if (E5_HTF_TREND_FILTER != HTF_DISABLED) {
            bool m5Valid = false, m5Bullish = false;
            bool m15Valid = false, m15Bullish = false;

            if (E5_HTF_TREND_FILTER == HTF_M5_ONLY || E5_HTF_TREND_FILTER == HTF_M5_AND_M15 || E5_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                double m5ADX = cache.adx[2];
                double m5DISpread = MathAbs(cache.diPlus[2] - cache.diMinus[2]);
                if (m5ADX >= E5_HTF_MIN_ADX && m5DISpread >= E5_HTF_MIN_DI_SPREAD) {
                    m5Valid = true;
                    m5Bullish = (cache.diPlus[2] > cache.diMinus[2]);
                }
            }
            if (E5_HTF_TREND_FILTER == HTF_M15_ONLY || E5_HTF_TREND_FILTER == HTF_M5_AND_M15 || E5_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                double m15ADX = cache.adx[3];
                double m15DISpread = MathAbs(cache.diPlus[3] - cache.diMinus[3]);
                if (m15ADX >= E5_HTF_MIN_ADX && m15DISpread >= E5_HTF_MIN_DI_SPREAD) {
                    m15Valid = true;
                    m15Bullish = (cache.diPlus[3] > cache.diMinus[3]);
                }
            }

            if (E5_HTF_TREND_FILTER == HTF_M5_ONLY && m5Valid) {
                htfBlockLong = !m5Bullish;
                htfBlockShort = m5Bullish;
            } else if (E5_HTF_TREND_FILTER == HTF_M15_ONLY && m15Valid) {
                htfBlockLong = !m15Bullish;
                htfBlockShort = m15Bullish;
            } else if (E5_HTF_TREND_FILTER == HTF_M5_AND_M15 && m5Valid && m15Valid) {
                htfBlockLong = (!m5Bullish && !m15Bullish);
                htfBlockShort = (m5Bullish && m15Bullish);
            } else if (E5_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                htfBlockLong = (m5Valid && !m5Bullish) || (m15Valid && !m15Bullish);
                htfBlockShort = (m5Valid && m5Bullish) || (m15Valid && m15Bullish);
            }

            if (htfBlockLong && bullishTrigger) TrackEntryAttempt("L-E5", false, "htf_trend");
            if (htfBlockShort && bearishTrigger) TrackEntryAttempt("S-E5", false, "htf_trend");
        }
        // PARITY: record HTF block flags (real path).
        m_rt.htf_block_long  = htfBlockLong ? 1 : 0;
        m_rt.htf_block_short = htfBlockShort ? 1 : 0;

        // --- Full entry conditions (Pine longAllConditions / shortAllConditions) ---
        bool inSession = IsNowInValidSession() || IGNORE_VALID_SESSIONS;
        m_rt.in_session = inSession ? 1 : 0;
        // Pine v1-stable: block long if bar[1] EMAs are bearish-aligned (and vice versa).
        // Uses bar[1] alignment booleans (not bar[0] zones) — matches Pine longAllConditions.
        bool longAllConditions  = bullishTrigger && checkOpenLE5 == -1 && inSession && !isBearishAligned && !htfBlockLong;
        bool shortAllConditions = bearishTrigger && checkOpenSE5 == -1 && inSession && !isBullishAligned && !htfBlockShort;

        // --- Multi-TF Sideways block (2/3 of M1/M3/M5 >= threshold, Pine parity) ---
        bool sidewayBlocksEntry = E5_ENABLE_SIDEWAY_ENTRY_BLOCK && IsMultiTfSideway(E5_SIDEWAYS_BLOCK_THRESHOLD);
        m_rt.sideway_block = sidewayBlocksEntry ? 1 : 0;

        // --- Deferred entry tracking: save direction when sideway blocks valid signal ---
        if (sidewayBlocksEntry && longAllConditions && !m_deferredBySideway) {
            m_deferredBySideway = true;
            m_deferredIsLong = true;
            if(showDebug) Print("[E5] Deferred: long signal saved during sideway block");
        }
        if (sidewayBlocksEntry && shortAllConditions && !m_deferredBySideway) {
            m_deferredBySideway = true;
            m_deferredIsLong = false;
            if(showDebug) Print("[E5] Deferred: short signal saved during sideway block");
        }

        // Clear deferred when alignment breaks
        if (m_deferredBySideway) {
            if (m_deferredIsLong && !isBullishAligned)
                m_deferredBySideway = false;
            if (!m_deferredIsLong && !isBearishAligned)
                m_deferredBySideway = false;
        }

        // Deferred entry ATR proximity gate: after sideway clears, require close[1] within ATR of EMA25
        bool longDeferredBlock  = m_deferredBySideway && m_deferredIsLong && !sidewayBlocksEntry
                                  && MathAbs(currentPrice - ema25) > E5_DEFERRED_ENTRY_MAX_ATR * cache.atrM1;
        bool shortDeferredBlock = m_deferredBySideway && !m_deferredIsLong && !sidewayBlocksEntry
                                  && MathAbs(currentPrice - ema25) > E5_DEFERRED_ENTRY_MAX_ATR * cache.atrM1;

        // Block entry during sideway (does NOT consume signal - retries once sideway clears)
        if (sidewayBlocksEntry) {
            if(showDebug) Print("[E5] Blocked: multi-TF sideway (2/3 >= ", E5_SIDEWAYS_BLOCK_THRESHOLD, ")");
            if (longAllConditions) TrackEntryAttempt("L-E5", false, "sideway");
            if (shortAllConditions) TrackEntryAttempt("S-E5", false, "sideway");
            m_rt.gate = "sideway"; RTDeriveInterest();
            return result;
        }

        // === LONG E5 Detection ===
        if (longAllConditions && !longDeferredBlock) {
            result.detected = true;
            result.isLong = true;
            m_rt.detected = 1; m_rt.det_long = 1;   // PARITY: capture before signal consume
            result.entryPrice = currentPrice;

            // SL: EMA200[1] - 2*spread (matching Pine SuperBros exactly)
            double spreadPrice = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
            double rawSL = ema200 - 2.0 * spreadPrice;
            double minSLPrice = E5_MIN_SL_PIPS * pipSize;
            double slDist = MathMax(currentPrice - rawSL, minSLPrice);

            // ATR SL cap (Pine SuperBros parity, line 1487-1491). Floored at minSLPrice
            // so spread/noise can't trigger a too-tight SL. Without this cap, EMA200
            // anchor in strong trends produces 1000+ pip SLs that wreck avg_loss.
            if (E5_USE_ATR_SL_ARBITRATION && cache.atrM1 > 0) {
                double atrCap = E5_ATR_SL_CAP_MULTIPLIER * cache.atrM1;
                if (atrCap >= minSLPrice && slDist > atrCap)
                    slDist = atrCap;
            }

            result.stopLoss = currentPrice - slDist;
            result.rawSLDistancePips = MathAbs(currentPrice - rawSL) / pipSize;
            result.bufferedSLDistancePips = slDist / pipSize;

            // TP based on RR ratio
            result.takeProfit = currentPrice + (slDist * CFG.rrLongE5);

            result.entryType = ENTRY_L_E5;
            result.isLowConfidence = false;
            result.lowConfidenceReason = "";
            result.trendQualityScore = trendQualityE5;

            // Consume signal (Pine parity): re-entry requires a new alignment onset
            // AND the consumed lock to be released (which only happens after alignment
            // breaks while no E5 long position is active).
            m_lastBullishSignal = -1;
            m_bullishSignalConsumed = true;
            m_deferredBySideway = false;
        }

        // === SHORT E5 Detection (only if LONG didn't trigger) ===
        if (!result.detected && shortAllConditions && !shortDeferredBlock) {
            result.detected = true;
            result.isLong = false;
            m_rt.detected = 1; m_rt.det_long = 0;   // PARITY: capture before signal consume
            result.entryPrice = currentPrice;

            double spreadPrice = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
            double rawSL = ema200 + 2.0 * spreadPrice;
            double minSLPrice = E5_MIN_SL_PIPS * pipSize;
            double slDist = MathMax(rawSL - currentPrice, minSLPrice);

            if (E5_USE_ATR_SL_ARBITRATION && cache.atrM1 > 0) {
                double atrCap = E5_ATR_SL_CAP_MULTIPLIER * cache.atrM1;
                if (atrCap >= minSLPrice && slDist > atrCap)
                    slDist = atrCap;
            }

            result.stopLoss = currentPrice + slDist;
            result.rawSLDistancePips = MathAbs(rawSL - currentPrice) / pipSize;
            result.bufferedSLDistancePips = slDist / pipSize;

            result.takeProfit = currentPrice - (slDist * CFG.rrShortE5);

            result.entryType = ENTRY_S_E5;
            result.isLowConfidence = false;
            result.lowConfidenceReason = "";
            result.trendQualityScore = trendQualityE5;

            m_lastBearishSignal = -1;
            m_bearishSignalConsumed = true;
            m_deferredBySideway = false;
        }

        // PARITY: derive the real-path gate label + write-gate for the main (non-early-return) path.
        RTDeriveGate(longDeferredBlock, shortDeferredBlock);
        RTDeriveInterest();
        return result;
    }

    //+--------------------------------------------------------------+
    //| Real-path trace helpers (PARITY/diagnostics only).           |
    //| RTReset/RTArmedFromState/RTDeriveGate/RTDeriveInterest fill   |
    //| m_rt from the LIVE Detect() state without perturbing the      |
    //| trigger; the EA reads it via GetRealTrace() after Detect().   |
    //+--------------------------------------------------------------+
    void GetRealTrace(E5RealRow &r) {
        // Stamp identity from the decision bar (UTC clock, matching TradeJournal/BarTrace).
        datetime srvOpen = iTime(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
        datetime utc     = srvOpen - (TimeCurrent() - TimeGMT());
        m_rt.ts_ms = (long)utc * 1000;
        m_rt.dt    = TimeToString(utc, TIME_DATE | TIME_MINUTES);
        m_rt.bar   = currentBar;
        r = m_rt;
    }

private:
    void RTReset() {
        m_rt.ts_ms = 0; m_rt.dt = ""; m_rt.bar = -1; m_rt.interesting = 0;
        m_rt.armed_dir = 0; m_rt.up_age = -1; m_rt.dn_age = -1;
        m_rt.aligned_bull = 0; m_rt.aligned_bear = 0;
        m_rt.price = 0; m_rt.ema25 = 0; m_rt.ema200 = 0; m_rt.atr_m1 = 0;
        m_rt.adx_m1 = 0; m_rt.min_adx = 0; m_rt.adx_pass = 1;
        m_rt.trend_quality = 0; m_rt.tq_pass = 1;
        m_rt.htf_block_long = 0; m_rt.htf_block_short = 0; m_rt.sideway_block = 0;
        m_rt.price_ok = 0; m_rt.in_session = 0; m_rt.detected = 0; m_rt.det_long = 0;
        m_rt.gate = "none";
        // execution-side defaults (EA overwrites when relevant)
        m_rt.atr_pctile = 0; m_rt.min_entry_pctile = 0; m_rt.atr_pctile_low = 0; m_rt.atr_pctile_high = 0;
        m_rt.min_entry_block = 0; m_rt.is_high_risk = 0;
        m_rt.potential_loss_usd = 0; m_rt.entry_max_loss = 0;
        m_rt.opposing_pos = 0; m_rt.entrytype_blocked = 0; m_rt.final_decision = "";
        // value-diff columns
        m_rt.ema75 = 0; m_rt.ema100 = 0; m_rt.m1_diplus = 0; m_rt.m1_diminus = 0;
        m_rt.m5_adx = 0; m_rt.m5_diplus = 0; m_rt.m5_diminus = 0;
        m_rt.m15_adx = 0; m_rt.m15_diplus = 0; m_rt.m15_diminus = 0;
    }
    // Capture armed dir/ages from live state at an early return (alignment not yet computed).
    void RTArmedFromState() {
        m_rt.armed_dir = (m_lastBullishSignal != -1) ? 1 : ((m_lastBearishSignal != -1) ? -1 : 0);
        m_rt.up_age    = (m_lastBullishSignal != -1) ? (currentBar - m_lastBullishSignal) : -1;
        m_rt.dn_age    = (m_lastBearishSignal != -1) ? (currentBar - m_lastBearishSignal) : -1;
    }
    // Derive which gate short-circuited the entry on the main path, in Detect()'s own order.
    void RTDeriveGate(bool longDeferredBlock, bool shortDeferredBlock) {
        if (m_rt.detected) { m_rt.gate = "fired"; return; }
        if (m_rt.armed_dir == 0) { m_rt.gate = "no_trigger"; return; }
        bool isLong = (m_rt.armed_dir > 0);
        int  age    = isLong ? m_rt.up_age : m_rt.dn_age;
        bool aligned = isLong ? (m_rt.aligned_bull == 1) : (m_rt.aligned_bear == 1);
        bool oppAligned = isLong ? (m_rt.aligned_bear == 1) : (m_rt.aligned_bull == 1);
        if (!aligned)                                   { m_rt.gate = "align_break"; return; }
        if (age < 0 || age > E5_MAX_EMA_CROSS_AGE)      { m_rt.gate = "age_expired"; return; }
        if (m_rt.price_ok == 0)                         { m_rt.gate = "price";       return; }
        if (m_rt.tq_pass == 0)                          { m_rt.gate = "tq";          return; }
        if (isLong ? m_rt.htf_block_long==1 : m_rt.htf_block_short==1) { m_rt.gate = "htf"; return; }
        if (m_rt.in_session == 0)                       { m_rt.gate = "session";     return; }
        if (oppAligned)                                 { m_rt.gate = "align_flip";  return; }
        if (isLong ? longDeferredBlock : shortDeferredBlock) { m_rt.gate = "deferred"; return; }
        m_rt.gate = "other";
    }
    void RTDeriveInterest() {
        m_rt.interesting = (m_rt.armed_dir != 0 || m_rt.detected == 1) ? 1 : 0;
    }

public:

    virtual double GetTargetWinrate() override {
        return 0.60;  // 60% target for E5 (simpler entry)
    }

    // Lightweight direction peek for conflict detection
    bool PeekDirection() {
        if (m_lastBullishSignal != -1 && m_lastBearishSignal == -1)
            return true;   // Long trigger active
        if (m_lastBearishSignal != -1 && m_lastBullishSignal == -1)
            return false;  // Short trigger active
        // Fallback: price vs EMA75
        double ema75 = GetEMA(TF0, EMA2, ENTRY_SHIFT);
        double currentPrice = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
        return (currentPrice > ema75);
    }

    // Entry-specific config overrides
    virtual double GetRRBoostMultiplier() const { return 1.05; }
    virtual bool GetUseConvictionScoring() const { return false; }     // E5: No conviction scoring
    virtual bool GetUseHTFVeto() const { return false; }              // E5: No HTF veto
    virtual int GetConvictionThreshold() const { return 0; }
    virtual bool GetAcceptHighRisk() const { return ACCEPT_HIGH_RISK_E5_ENTRIES; }
    virtual int GetHighRiskMomentumCheck() const { return (int)NONE; } // E5: No momentum
    virtual double GetMaxLossRatio() const { return MAX_LOSS_RATIO_E5; }
    virtual bool GetVolLotAdjEnabled() const { return VOL_LOT_ADJ_E5; }
    virtual bool GetRecoveryLadderEnabled() const { return E5_USE_RECOVERY_LADDER; }
    virtual int GetRecoveryBoostThreshold() const { return 0; }
    virtual bool GetEnableScoreDropExit() const { return ENABLE_SCORE_DROP_EXIT_E5; }
    virtual int GetScoreDropThreshold() const { return SCORE_DROP_THRESHOLD_E5; }
    virtual bool GetEnableDIFlipExit() const { return ENABLE_DI_FLIP_FAST_EXIT_E5; }
    virtual bool GetExitInIchiCloud() const { return false; }         // E5: No Ichimoku
    virtual bool GetEnablePanicADXExit() const { return ENABLE_FAST_ADX_PANIC_EXIT_E5; }

    //+--------------------------------------------------------------+
    //| TraceBar — READ-ONLY per-bar E5 decision dump (PARITY).       |
    //| Mirrors Detect()'s gate field-by-field with NO early-return  |
    //| and NO trade/state side effect on the live trigger. Fills an |
    //| E5TraceRow whose columns match the C++ trace_dumper exactly.  |
    //| Call once per CLOSED M1 bar (after UpdateIndicatorCache).     |
    //+--------------------------------------------------------------+
    void TraceBar(int barIndex, E5TraceRow &r) {
        // --- EMAs at the decision shift (matches Detect lines 145-148) ---
        double ema10  = GetEMA(TF0, EMA0, ENTRY_SHIFT);
        double ema25  = GetEMA(TF0, EMA1, ENTRY_SHIFT);
        double ema75  = GetEMA(TF0, EMA2, ENTRY_SHIFT);
        double ema100 = GetEMA(TF0, EMA3, ENTRY_SHIFT);
        double ema200 = GetEMA(TF0, EMA4, ENTRY_SHIFT);
        double px     = iClose(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);

        bool bull = (ema25 > ema75) && (ema75 > ema100) && (ema100 > ema200);
        bool bear = (ema25 < ema75) && (ema75 < ema100) && (ema100 < ema200);

        // --- Onset tracking, once per bar (mirror Detect 153-188; "no position" so the
        //     consumed lock releases whenever alignment breaks — matches trace_dumper). ---
        if (barIndex != m_tr_lastProcBar) {
            m_tr_lastProcBar = barIndex;
            bool bullOnset = bull && !m_tr_prevBull;
            bool bearOnset = bear && !m_tr_prevBear;
            if (bullOnset && !m_tr_bullConsumed) m_tr_lastBull = barIndex;
            if (bearOnset && !m_tr_bearConsumed) m_tr_lastBear = barIndex;
            if (!bull) { m_tr_lastBull = -1; m_tr_bullConsumed = false; }
            if (!bear) { m_tr_lastBear = -1; m_tr_bearConsumed = false; }
            m_tr_prevBull = bull;
            m_tr_prevBear = bear;
        }

        int upAge = (m_tr_lastBull != -1) ? (barIndex - m_tr_lastBull) : -1;
        int dnAge = (m_tr_lastBear != -1) ? (barIndex - m_tr_lastBear) : -1;

        // --- Gate sub-decisions (recorded, never short-circuited) ---
        bool L_inage = (m_tr_lastBull != -1) && (upAge <= E5_MAX_EMA_CROSS_AGE);
        bool S_inage = (m_tr_lastBear != -1) && (dnAge <= E5_MAX_EMA_CROSS_AGE);

        bool swblk = E5_ENABLE_SIDEWAY_ENTRY_BLOCK && IsMultiTfSideway(E5_SIDEWAYS_BLOCK_THRESHOLD);
        bool atrlo = (ATR_PERCENTILE_LOW > 0 && cachedATRPercentile < ATR_PERCENTILE_LOW);
        bool atrhi = (ENABLE_ATR_HIGH_BLOCK && ATR_PERCENTILE_HIGH > 0 && cachedATRPercentile > ATR_PERCENTILE_HIGH);
        bool L_price = (px > ema25);
        bool S_price = (px < ema25);
        int  L_tq = GetTrendQualityScore(TREND_BULL, 5);
        int  S_tq = GetTrendQualityScore(TREND_BEAR, 5);
        bool L_tqok = (MIN_TREND_QUALITY_E5 <= 0) || (L_tq >= MIN_TREND_QUALITY_E5);
        bool S_tqok = (MIN_TREND_QUALITY_E5 <= 0) || (S_tq >= MIN_TREND_QUALITY_E5);
        bool adxok  = (E5_MIN_MOMENTUM_ADX <= 0) || (cache.adx[0] >= E5_MIN_MOMENTUM_ADX);

        // E5 has no separate trend-core score: EMA alignment IS the directional hard gate.
        int  L_tcore = (bull && !bear) ? 1 : 0;
        int  S_tcore = (bear && !bull) ? 1 : 0;

        // --- HTF trend filter (mirror Detect 223-261) ---
        bool htfBlockLong = false, htfBlockShort = false;
        if (E5_HTF_TREND_FILTER != HTF_DISABLED) {
            bool m5Valid = false, m5Bullish = false, m15Valid = false, m15Bullish = false;
            if (E5_HTF_TREND_FILTER == HTF_M5_ONLY || E5_HTF_TREND_FILTER == HTF_M5_AND_M15 || E5_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                double m5ADX = cache.adx[2];
                double m5DISpread = MathAbs(cache.diPlus[2] - cache.diMinus[2]);
                if (m5ADX >= E5_HTF_MIN_ADX && m5DISpread >= E5_HTF_MIN_DI_SPREAD) {
                    m5Valid = true; m5Bullish = (cache.diPlus[2] > cache.diMinus[2]);
                }
            }
            if (E5_HTF_TREND_FILTER == HTF_M15_ONLY || E5_HTF_TREND_FILTER == HTF_M5_AND_M15 || E5_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                double m15ADX = cache.adx[3];
                double m15DISpread = MathAbs(cache.diPlus[3] - cache.diMinus[3]);
                if (m15ADX >= E5_HTF_MIN_ADX && m15DISpread >= E5_HTF_MIN_DI_SPREAD) {
                    m15Valid = true; m15Bullish = (cache.diPlus[3] > cache.diMinus[3]);
                }
            }
            if (E5_HTF_TREND_FILTER == HTF_M5_ONLY && m5Valid) {
                htfBlockLong = !m5Bullish; htfBlockShort = m5Bullish;
            } else if (E5_HTF_TREND_FILTER == HTF_M15_ONLY && m15Valid) {
                htfBlockLong = !m15Bullish; htfBlockShort = m15Bullish;
            } else if (E5_HTF_TREND_FILTER == HTF_M5_AND_M15 && m5Valid && m15Valid) {
                htfBlockLong = (!m5Bullish && !m15Bullish); htfBlockShort = (m5Bullish && m15Bullish);
            } else if (E5_HTF_TREND_FILTER == HTF_M5_OR_M15) {
                htfBlockLong = (m5Valid && !m5Bullish) || (m15Valid && !m15Bullish);
                htfBlockShort = (m5Valid && m5Bullish) || (m15Valid && m15Bullish);
            }
        }
        bool L_htf = !htfBlockLong;
        bool S_htf = !htfBlockShort;

        bool inSession = IsNowInValidSession() || IGNORE_VALID_SESSIONS;

        bool L_pass = !swblk && !atrlo && !atrhi && L_price && (L_tcore != 0) && L_tqok && adxok && L_htf;
        bool S_pass = !swblk && !atrlo && !atrhi && S_price && (S_tcore != 0) && S_tqok && adxok && S_htf;
        bool L_fire = L_inage && L_pass;
        bool S_fire = S_inage && S_pass;

        // Session-gated fire (long priority), consuming this direction's trigger — mirrors
        // detect_entry's one-shot semantics so the trace's fire count tracks real entries.
        int fire_dir = 0;
        if (inSession && L_fire)      { fire_dir =  1; m_tr_lastBull = -1; m_tr_bullConsumed = true; }
        else if (inSession && S_fire) { fire_dir = -1; m_tr_lastBear = -1; m_tr_bearConsumed = true; }

        // --- Fill the row (UTC clock, matching TradeJournal + the C++ trace) ---
        datetime srvOpen = iTime(_Symbol, TF_ARRAY[TF0], ENTRY_SHIFT);
        datetime utc     = srvOpen - (TimeCurrent() - TimeGMT());
        r.ts_ms = (long)utc * 1000;
        r.dt    = TimeToString(utc, TIME_DATE | TIME_MINUTES);
        r.ema0 = ema10; r.ema1 = ema25; r.ema2 = ema75; r.ema3 = ema100; r.ema4 = ema200;
        r.adx_m1 = cache.adx[0]; r.adx_m3 = cache.adx[1]; r.adx_m5 = cache.adx[2]; r.adx_m15 = cache.adx[3];
        r.diP_m1 = cache.diPlus[0]; r.diP_m3 = cache.diPlus[1]; r.diP_m5 = cache.diPlus[2]; r.diP_m15 = cache.diPlus[3];
        r.diM_m1 = cache.diMinus[0]; r.diM_m3 = cache.diMinus[1]; r.diM_m5 = cache.diMinus[2]; r.diM_m15 = cache.diMinus[3];
        r.adxS = cache.adx[0]; r.diPS = cache.diPlus[0]; r.diMS = cache.diMinus[0];
        r.atr = cache.atrM1; r.rsi = GetRSIAverage(TF_ARRAY[TF0], RSI_LEN, 5);
        r.close = px; r.high = cache.high; r.low = cache.low;
        r.tenkan = 0.0; r.kijun = 0.0;                                  // E5 has no M1 Ichimoku
        r.senkouA_m3 = cache.ichimokuSpanA_M3_Current; r.senkouB_m3 = cache.ichimokuSpanB_M3_Current;
        r.sideways = GetSidewaysScoreForTF(TF0, 1);
        r.atr_pctile = cachedATRPercentile;
        r.e5up_age = upAge; r.e5dn_age = dnAge;
        r.L_inage = L_inage; r.L_swblk = swblk; r.L_atrlo = atrlo; r.L_atrhi = atrhi; r.L_price = L_price;
        r.L_tcore = L_tcore; r.L_tq = L_tq; r.L_tqok = L_tqok; r.L_adx = adxok; r.L_htf = L_htf; r.L_pass = L_pass; r.L_fire = L_fire;
        r.S_inage = S_inage; r.S_swblk = swblk; r.S_atrlo = atrlo; r.S_atrhi = atrhi; r.S_price = S_price;
        r.S_tcore = S_tcore; r.S_tq = S_tq; r.S_tqok = S_tqok; r.S_adx = adxok; r.S_htf = S_htf; r.S_pass = S_pass; r.S_fire = S_fire;
        r.session = inSession ? 1 : 0; r.fire_dir = fire_dir;
    }
};

#endif // ENTRY5_MQH
