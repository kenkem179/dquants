// KenKem P6 — risk-based sizing + distilled trade manager.
//
// SIZING (risk-correct, not the EA's pip-value quirk): lot = (balance * riskRatio) / (riskPrice *
// value_per_price_per_lot), so a full-SL loss == balance*riskRatio exactly. Per-entry riskRatio =
// MAX_LOSS_RATIO_E{1,2,4}. normalize to broker lot step/min.
//
// MANAGEMENT (essential core only — laddered extensions / TP-extension / panic / score-drop / DI-flip
// all dropped): partial TP -> breakeven -> chandelier trail. manage_tick processes ONE price; the engine
// feeds it the intra-bar price path (tick or OHLC walk). Deterministic order per price: full SL, full
// TP, then partial+BE, then trail (raise-only / lower-only).
#pragma once
#include "kk/kenkem/kenkem_config.hpp"
#include <vector>
#include <cmath>

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

struct MgmtParams { double partial_trigger, partial_ratio, be_buffer, trailing_factor; };
inline MgmtParams mgmt_for(int kind, const KenKemConfig& c) {
    if (kind == 2) return { c.e2_partial_tp_trigger, c.e2_partial_tp_ratio, c.e2_be_buffer, c.e2_trailing_factor };
    if (kind == 4) return { c.e4_partial_tp_trigger, c.e4_partial_tp_ratio, c.e4_be_buffer, c.e4_trailing_factor };
    if (kind == 5) return { c.e5_partial_tp_trigger, c.e5_partial_tp_ratio, c.e5_be_buffer, c.e5_trailing_factor };
    return { c.e1_partial_tp_trigger, c.e1_partial_tp_ratio, c.e1_be_buffer, c.e1_trailing_factor };
}

struct Position {
    bool   is_long = false;
    int    kind = 0;
    double entry = 0, sl = 0, tp = 0, risk = 0;
    double init_lot = 0, lot = 0;          // lot = remaining
    double best = 0;                       // best favorable price (high-water mark)
    bool   partial_done = false;
    bool   pm_partial_done = false;        // shared ProfitManager one-shot partial
    int    pm_tp_ext = 0;
    bool   open = false;
};

inline Position open_position(bool is_long, int kind, double entry, double sl, double tp,
                              double lot, const KenKemConfig&) {
    Position p; p.is_long = is_long; p.kind = kind; p.entry = entry; p.sl = sl; p.tp = tp;
    p.risk = std::fabs(entry - sl); p.init_lot = lot; p.lot = lot; p.best = entry; p.open = true;
    return p;
}

// One fill produced by management. reason: 'S'=stop, 'T'=take-profit, 'P'=partial.
struct Fill { double price; double lot; char reason; };

// Process one price update. Mutates p (sl/best/lot/open) and appends fills.
inline void manage_tick(Position& p, double price, const KenKemConfig& c, std::vector<Fill>& fills) {
    if (!p.open) return;
    const MgmtParams m = mgmt_for(p.kind, c);

    // Broker partial-close slice: floor to the volume step and require >= min_lot, EXACTLY as the EA
    // does (Engine.mqh:337-338 `q=vol*ratio; MathFloor(q/step)*step; if(q>=mn && q<vol)`). Without this
    // the engine closed a fractional slice the broker can never fill -> a different runner size and a
    // silent per-trade P&L drift. `partial_done` still latches on the trigger even if the slice is
    // sub-min (EA sets g_posTp1Done regardless), so BE/trail engage on the full runner just like MT5.
    auto partial_slice = [&]() -> double {
        double q = p.init_lot * m.partial_ratio;
        if (c.lot_step > 0.0) q = std::floor(q / c.lot_step) * c.lot_step;
        return q;
    };
    // Broker min-stop-distance clamp on a SL move (BE/trail): the EA refuses a modify within
    // stops_level_price of the market (Engine.mqh okDist). Default 0 -> always allowed (Exness).
    auto sl_move_ok = [&](double cand) -> bool {
        if (c.stops_level_price <= 0.0) return true;
        return p.is_long ? (price - cand >= c.stops_level_price) : (cand - price >= c.stops_level_price);
    };

    if (p.is_long) {
        if (price > p.best) p.best = price;
        // Full SL.
        if (price <= p.sl) { fills.push_back({ p.sl, p.lot, 'S' }); p.lot = 0; p.open = false; return; }
        // Full TP.
        if (price >= p.tp) { fills.push_back({ p.tp, p.lot, 'T' }); p.lot = 0; p.open = false; return; }
        // Partial TP -> breakeven.
        if (!p.partial_done) {
            double trig = p.entry + m.partial_trigger * (p.tp - p.entry);
            if (price >= trig && c.allow_partial_tp) {
                double q = partial_slice();
                if (q >= c.min_lot && q < p.lot) { fills.push_back({ price, q, 'P' }); p.lot -= q; }
                p.partial_done = true;
                double be = p.entry + m.be_buffer * p.risk;
                if (be > p.sl && sl_move_ok(be)) p.sl = be;
            }
        }
        // Chandelier trail (raise-only) once partial taken.
        if (p.partial_done) {
            double trail = p.best - m.trailing_factor * p.risk;
            if (trail > p.sl && sl_move_ok(trail)) p.sl = trail;
        }
    } else {
        if (price < p.best) p.best = price;
        if (price >= p.sl) { fills.push_back({ p.sl, p.lot, 'S' }); p.lot = 0; p.open = false; return; }
        if (price <= p.tp) { fills.push_back({ p.tp, p.lot, 'T' }); p.lot = 0; p.open = false; return; }
        if (!p.partial_done) {
            double trig = p.entry - m.partial_trigger * (p.entry - p.tp);
            if (price <= trig && c.allow_partial_tp) {
                double q = partial_slice();
                if (q >= c.min_lot && q < p.lot) { fills.push_back({ price, q, 'P' }); p.lot -= q; }
                p.partial_done = true;
                double be = p.entry - m.be_buffer * p.risk;
                if (be < p.sl && sl_move_ok(be)) p.sl = be;
            }
        }
        if (p.partial_done) {
            double trail = p.best + m.trailing_factor * p.risk;
            if (trail < p.sl && sl_move_ok(trail)) p.sl = trail;
        }
    }

    // Shared ProfitManager (kk::common). All toggles default OFF => skipped (inert). Applied after the
    // distilled partial/trail; a tightened SL is honoured on the NEXT price (as the chandelier trail is).
    // atr is not tracked per-position here, so tp_extension stays inert; the R-based SL toggles work.
    if (kk::common::pm_any(c.pm)) {
        kk::common::PMState st;
        st.is_long = p.is_long; st.entry = p.entry; st.sl = p.sl; st.tp = p.tp;
        st.cur_price = price; st.best_price = p.best;
        st.risk = p.risk; st.atr = 0.0;
        st.tp_extensions = p.pm_tp_ext;
        st.partial_done = p.pm_partial_done; st.be_done = p.partial_done;
        st.structure_level = 0.0; st.trend_weakening = false;
        const kk::common::PMActions act = kk::common::pm_evaluate(st, c.pm);
        if (p.is_long ? (act.sl > p.sl) : (act.sl < p.sl)) p.sl = act.sl;
        if (p.is_long ? (act.tp > p.tp) : (act.tp < p.tp)) { p.tp = act.tp; ++p.pm_tp_ext; }
        if (act.partial_frac > 0.0 && !p.pm_partial_done) {
            double q = p.init_lot * act.partial_frac;
            if (q > 0 && q < p.lot) { fills.push_back({ price, q, 'P' }); p.lot -= q; }
            p.pm_partial_done = true;
        }
    }
}

// Signed price-points P&L of a fill for this position (engine multiplies by lot*vppl and subtracts costs).
inline double fill_points(const Position& p, const Fill& f) {
    return p.is_long ? (f.price - p.entry) : (p.entry - f.price);
}

}  // namespace kk::kenkem
