// KenKem P6/A7 — risk-based sizing + EA-FAITHFUL per-tick trade manager.
//
// SIZING (risk-correct, not the EA's pip-value quirk): lot = (balance * riskRatio) / (riskPrice *
// value_per_price_per_lot), so a full-SL loss == balance*riskRatio exactly. Per-entry riskRatio =
// MAX_LOSS_RATIO_E{1,2,4}. normalize to broker lot step/min.
//
// MANAGEMENT — ports the canonical KenKemExpert.mq5 STANDARD-mode pipeline (TradeManager::ProcessAllTrades
// + CheckAndApplyLadderStages, see research/hypotheses/KENKEM-EXIT-PARITY-SPEC.md). Per OPEN trade, after
// the entry bar (barsSinceEntry>0), in this order:
//   B  broker SL/TP  (tick-accurate, runs even on the entry bar)
//   D  R-multiple SL->BE      : R=pnl/origRisk >= R_MULT_BE_TRIGGER -> SL=entry±origRisk*R_MULT_BE_BUFFER
//   F  smart partial (TP1)    : eligible at pnl>=trig*origTPDist; fill on retrace>=PARTIAL_TP_RETRACE_RATIO
//                               at the LIVE price; then BE=entry±origTPDist*breakevenBuffer
//   G  3-stage ladder trail   : only after partial; pnl_live>=StageN_mult*origTPDist -> SL=live-StageN_ratio*profit
//   T  CalculateTrailingSLForTrade : while eligible|partial, SL=best - origTPDist*trailF/(tpExt+1)*volMult
// All SL moves are improve-only and tick-normalized. Mechanisms needing indicators the engine doesn't yet
// compute (pre-BE structure, TP-extension, trend-weakening partial gate, early/panic/score-drop exits) are
// handled elsewhere (per_bar_exits_) or deferred (SPEC §6 P3/P4); IsTrendWeakening is treated as false here.
//
// PRICE RESOLUTION is load-bearing (SPEC §1): the EA refreshes cache.currentPrice/high/low ONCE per bar
// (at the new-bar event iClose(0)==iHigh(0)==iLow(0) = the bar's first-tick BID), so D/F/T/best read a
// BAR-FROZEN price (`bar_px`), while the ladder (G) and broker SL/TP read the LIVE tick price (`live_px`).
#pragma once
#include "kk/kenkem/kenkem_config.hpp"
#include <vector>
#include <cmath>
#include <cstdlib>
#include <cstdio>

namespace kk::kenkem {

inline double risk_ratio_for(int kind, const KenKemConfig& c) {
    if (kind == 2) return c.max_loss_ratio_e2;
    if (kind == 4) return c.max_loss_ratio_e4;
    if (kind == 5) return c.max_loss_ratio_e5;
    return c.max_loss_ratio_e1;
}

// Risk-correct lot for a stop distance of `risk_price` (|entry-sl|).
inline double position_size(double balance, int kind, double risk_price, const KenKemConfig& c) {
    double riskUSD = balance * risk_ratio_for(kind, c);
    double vppl = c.value_per_price_per_lot();
    if (risk_price <= 0.0 || vppl <= 0.0) return c.normalize_lot(c.min_lot);
    return c.normalize_lot(riskUSD / (risk_price * vppl));
}

// Per-entry management params (mirror EntryConfig getters; values from kenkem_config / .set).
struct MgmtParams {
    double partial_trigger, partial_ratio, be_buffer, trailing_factor;
    int    max_tp_ext;       // GetMaxTPExtensions (E1=40, E2/E4=30)
    bool   ladder_enabled;
    double s1m, s2m, s3m;    // ladder stage profit multipliers (× origTPDist)
    double s1t, s2t, s3t;    // ladder stage trail ratios
};
inline MgmtParams mgmt_for(int kind, const KenKemConfig& c) {
    if (kind == 2) return { c.e2_partial_tp_trigger, c.e2_partial_tp_ratio, c.e2_be_buffer, c.e2_trailing_factor,
                            c.e2_max_tp_ext, c.e2_ladder, c.e2_ladder_s1_mult, c.e2_ladder_s2_mult, c.e2_ladder_s3_mult,
                            c.e2_ladder_s1_trail, c.e2_ladder_s2_trail, c.e2_ladder_s3_trail };
    if (kind == 4) return { c.e4_partial_tp_trigger, c.e4_partial_tp_ratio, c.e4_be_buffer, c.e4_trailing_factor,
                            c.e4_max_tp_ext, c.e4_ladder, c.e4_ladder_s1_mult, c.e4_ladder_s2_mult, c.e4_ladder_s3_mult,
                            c.e4_ladder_s1_trail, c.e4_ladder_s2_trail, c.e4_ladder_s3_trail };
    if (kind == 5) return { c.e5_partial_tp_trigger, c.e5_partial_tp_ratio, c.e5_be_buffer, c.e5_trailing_factor,
                            30, false, 0,0,0, 0,0,0 };   // E5 ladder not configured (Pine parity path)
    return { c.e1_partial_tp_trigger, c.e1_partial_tp_ratio, c.e1_be_buffer, c.e1_trailing_factor,
             c.e1_max_tp_ext, c.e1_ladder, c.e1_ladder_s1_mult, c.e1_ladder_s2_mult, c.e1_ladder_s3_mult,
             c.e1_ladder_s1_trail, c.e1_ladder_s2_trail, c.e1_ladder_s3_trail };
}

struct Position {
    bool   is_long = false;
    int    kind = 0;
    double entry = 0, sl = 0, tp = 0, risk = 0;     // risk = origRisk = |entry-sl| at open (bufferedSLDist)
    double orig_tp = 0;                             // original TP (for origTPDist; survives TP-extension)
    double init_lot = 0, lot = 0;                   // lot = remaining
    double best = 0;                                // bestPrice — high-water of the BAR-FROZEN price
    int    entry_bar = 0;                           // forming-bar index at fill (entryBar; gates management)
    // smart-partial (F)
    bool   partial_eligible = false;               // partialTPEligible (latched at trigger)
    double best_since_eligible = 0;                 // bestPriceSinceEligible (for retrace)
    bool   partial_done = false;                    // hasTakenPartialProfit
    // BE / ladder state
    bool   sl_moved_to_be = false;                 // slMovedToBreakeven
    bool   rmult_be_applied = false;               // rMultipleBEApplied
    int    ladder_stage = 0;                        // ladderStageReached (0..3, advance-only)
    int    tp_ext = 0;                              // tpExtensions (trail distance divisor; 0 until E ported)
    bool   open = false;
};

inline Position open_position(bool is_long, int kind, double entry, double sl, double tp,
                              double lot, const KenKemConfig&) {
    Position p; p.is_long = is_long; p.kind = kind; p.entry = entry; p.sl = sl; p.tp = tp;
    p.risk = std::fabs(entry - sl); p.orig_tp = tp; p.init_lot = lot; p.lot = lot; p.best = entry; p.open = true;
    return p;
}

// One fill produced by management. reason: 'S'=stop, 'T'=take-profit, 'P'=partial.
struct Fill { double price; double lot; char reason; };

// Process one tick. `live_px` = this tick's exit-side market price (broker SL/TP fills + ladder, = EA
// iClose(0)). `bar_px` = the bar-frozen reference (= EA cache.currentPrice/high/low, the bar's first-tick
// bid) driving R-mult BE / smart-partial / trail / bestPrice. `manage_allowed` = barsSinceEntry>0 (the EA
// skips ALL management on the entry bar, but the broker still fills SL/TP). Mutates p; appends fills.
inline void manage_tick(Position& p, double live_px, double bar_px, const KenKemConfig& c,
                        std::vector<Fill>& fills, bool manage_allowed, double vol_mult) {
    if (!p.open) return;

    // (B) Broker SL/TP — tick-accurate at the live price, runs even on the entry bar.
    if (p.is_long) {
        if (live_px <= p.sl) { fills.push_back({ p.sl, p.lot, 'S' }); p.lot = 0; p.open = false; return; }
        if (live_px >= p.tp) { fills.push_back({ p.tp, p.lot, 'T' }); p.lot = 0; p.open = false; return; }
    } else {
        if (live_px >= p.sl) { fills.push_back({ p.sl, p.lot, 'S' }); p.lot = 0; p.open = false; return; }
        if (live_px <= p.tp) { fills.push_back({ p.tp, p.lot, 'T' }); p.lot = 0; p.open = false; return; }
    }
    if (!manage_allowed) return;   // EA: barsSinceEntry==0 -> no BE/partial/ladder/trail this bar

    const MgmtParams m = mgmt_for(p.kind, c);
    auto norm = [&](double px) { return c.tick_size > 0.0 ? std::round(px / c.tick_size) * c.tick_size : px; };
    // Broker min-stop-distance clamp on a SL move (BE/trail). Default 0 -> always allowed (Exness).
    auto sl_move_ok = [&](double cand) -> bool {
        if (c.stops_level_price <= 0.0) return true;
        return p.is_long ? (live_px - cand >= c.stops_level_price) : (cand - live_px >= c.stops_level_price);
    };
    // improve-only SL setter (long: raise; short: lower), tick-normalized + min-stop-clamped.
    auto raise_sl = [&](double cand) {
        cand = norm(cand);
        if (!sl_move_ok(cand)) return;
        if (p.is_long ? (cand > p.sl) : (cand < p.sl)) p.sl = cand;
    };

    const double sgn = p.is_long ? 1.0 : -1.0;
    const double origRisk   = p.risk;
    const double origTPDist = std::fabs(p.orig_tp - p.entry);
    const double pnl_bar    = sgn * (bar_px - p.entry);   // currentPnL from cache.currentPrice (bar-frozen)

    // bestPrice tracks the bar-frozen high-water (EA: MathMax(bestPrice, cache.high)).
    if (p.is_long ? (bar_px > p.best) : (bar_px < p.best)) p.best = bar_px;

    // (D) R-multiple SL -> BE (independent of partial). Improve-only; flags latch only on a real move.
    if (c.r_mult_be_trigger > 0.0 && !p.rmult_be_applied && !p.sl_moved_to_be && origRisk > 0.0) {
        if (pnl_bar / origRisk >= c.r_mult_be_trigger) {
            double be = p.entry + sgn * origRisk * c.r_mult_be_buffer;
            bool improves = p.is_long ? (be > p.sl) : (be < p.sl);
            if (improves) { raise_sl(be); p.rmult_be_applied = true; p.sl_moved_to_be = true; }
        }
    }

    // (E) TP extension (ExtendTPAsNeeded). When the bar-frozen price is within TP_EXT_TRIGGER_PIPS of TP
    // and progress >= MIN_TP_PROGRESS_FOR_EXTENSION, push TP out by TP_EXT_PIPS and bump tp_ext (which
    // shrinks the trail /(tp_ext+1)). IsTrendWeakening is unmodeled -> treated false (always extend).
    // NOTE: the EA's UpdateDynamicTPExtension() is DEFINED BUT NEVER CALLED (KenKemExpert.mq5:2400 comment
    // notwithstanding), so dynamicTPExtensionPips/Trigger keep their GlobalState.mqh defaults (6.0 / 25.0)
    // for the whole run — USE_DYNAMIC_TP_EXTENSION/ATR_TP_EXTENSION_MULTIPLIER are effectively dead. We
    // therefore use the static 6/25 pips, matching MT5. (Per-tick on a frozen bar_px it extends a few
    // times per bar until remaining > trigger, exactly as the EA does each OnTick.)
    {
        constexpr double TP_EXT_PIPS = 6.0;          // round(dynamicTPExtensionPips=6.0)
        constexpr double TP_EXT_TRIGGER_PIPS = 25.0; // dynamicTPExtensionTrigger=25.0
        if (c.allow_tp_extension && p.tp_ext < m.max_tp_ext && c.pip_size > 0.0) {
            double total = sgn * (p.tp - p.entry);
            if (total > 0.0) {
                double remaining_pips = sgn * (p.tp - bar_px) / c.pip_size;
                double total_pips = total / c.pip_size;
                double progress = (total_pips - remaining_pips) / total_pips;
                if (remaining_pips <= TP_EXT_TRIGGER_PIPS && remaining_pips > 0.0
                    && progress >= c.min_tp_progress_for_ext) {
                    p.tp = norm(p.tp + sgn * TP_EXT_PIPS * c.pip_size);
                    ++p.tp_ext;
                    // EA calls CalculateTrailingSLForTrade right after; the (T) block below (run every tick
                    // while eligible|partial) reproduces it with the updated tp_ext — no separate call needed.
                }
            }
        }
    }

    // (F) Smart partial TP. Eligible at the trigger; (non-E5) executes on a significant retrace from the
    // peak-since-eligible (IsTrendWeakening unmodeled -> false). Fills at the LIVE price; then SL -> BE.
    if (c.allow_partial_tp && origTPDist > 0.0) {
        if (!p.partial_eligible && pnl_bar >= m.partial_trigger * origTPDist) {
            p.partial_eligible = true; p.best_since_eligible = bar_px;
        }
        if (p.partial_eligible && !p.partial_done) {
            if (p.is_long ? (bar_px > p.best_since_eligible) : (bar_px < p.best_since_eligible))
                p.best_since_eligible = bar_px;
            double gained  = sgn * (p.best_since_eligible - p.entry);
            double retrace = sgn * (p.best_since_eligible - bar_px);
            bool sig_retrace = gained > 0.0 && (retrace / gained) >= c.partial_tp_retrace;
            if (sig_retrace) {
                // Partial slice: round(init*ratio) to the volume step, bumped up to min_lot, capped < lot
                // (EA ExecutePartialTakeProfit: NormalizeLotSize then clamp to SYMBOL_VOLUME_MIN).
                double q = p.init_lot * m.partial_ratio;
                if (c.lot_step > 0.0) q = std::round(q / c.lot_step) * c.lot_step;
                if (q < c.min_lot) q = c.min_lot;
                if (q < p.lot) { fills.push_back({ live_px, q, 'P' }); p.lot -= q; }
                double actual_pnl = sgn * (live_px - p.entry);
                if (actual_pnl > 0.0) {
                    double be = p.entry + sgn * origTPDist * m.be_buffer;
                    bool improves = p.is_long ? (be > p.sl) : (be < p.sl);
                    if (improves) { raise_sl(be); p.sl_moved_to_be = true; }
                }
                p.partial_done = true;
            }
        }
    }

    // (G) 3-stage ladder trail — LIVE price, advance-only, only after a partial (EA CheckAndApplyLadderStages).
    if (p.partial_done && m.ladder_enabled && origTPDist > 0.0) {
        double pnl_live = sgn * (live_px - p.entry);
        int stage = 0; double tr = 0.0;
        if (p.ladder_stage < 3 && pnl_live >= m.s3m * origTPDist)      { stage = 3; tr = m.s3t; }
        else if (p.ladder_stage < 2 && pnl_live >= m.s2m * origTPDist) { stage = 2; tr = m.s2t; }
        else if (p.ladder_stage < 1 && pnl_live >= m.s1m * origTPDist) { stage = 1; tr = m.s1t; }
        if (stage > 0) {
            p.ladder_stage = stage;                    // EA sets ladderStageReached unconditionally
            double profit = sgn * (live_px - p.entry);
            raise_sl(live_px - sgn * tr * profit);
        }
    }

    // (T) CalculateTrailingSLForTrade — bar-frozen best; runs while eligible OR after partial.
    // adaptiveTrailingDistance = origTPDist*trailF/(tpExt+1) * GetVolatilityMultiplier() (live, [0.7,1.5]).
    if (p.partial_eligible || p.partial_done) {
        double trail_dist = origTPDist * m.trailing_factor / (double)(p.tp_ext + 1) * vol_mult;
        raise_sl(p.best - sgn * trail_dist);
    }
}

// Back-compat single-price overload (bar engine + unit tests): live==bar, management always allowed,
// volatility multiplier 1.0 (neutral).
inline void manage_tick(Position& p, double px, const KenKemConfig& c, std::vector<Fill>& fills) {
    manage_tick(p, px, px, c, fills, true, 1.0);
}

// Signed price-points P&L of a fill for this position (engine multiplies by lot*vppl and subtracts costs).
inline double fill_points(const Position& p, const Fill& f) {
    return p.is_long ? (f.price - p.entry) : (p.entry - f.price);
}

}  // namespace kk::kenkem
