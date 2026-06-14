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
    return { c.e1_partial_tp_trigger, c.e1_partial_tp_ratio, c.e1_be_buffer, c.e1_trailing_factor };
}

struct Position {
    bool   is_long = false;
    int    kind = 0;
    double entry = 0, sl = 0, tp = 0, risk = 0;
    double init_lot = 0, lot = 0;          // lot = remaining
    double best = 0;                       // best favorable price (high-water mark)
    bool   partial_done = false;
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
                double q = p.init_lot * m.partial_ratio;
                if (q > 0 && q < p.lot) { fills.push_back({ price, q, 'P' }); p.lot -= q; }
                p.partial_done = true;
                double be = p.entry + m.be_buffer * p.risk;
                if (be > p.sl) p.sl = be;
            }
        }
        // Chandelier trail (raise-only) once partial taken.
        if (p.partial_done) {
            double trail = p.best - m.trailing_factor * p.risk;
            if (trail > p.sl) p.sl = trail;
        }
    } else {
        if (price < p.best) p.best = price;
        if (price >= p.sl) { fills.push_back({ p.sl, p.lot, 'S' }); p.lot = 0; p.open = false; return; }
        if (price <= p.tp) { fills.push_back({ p.tp, p.lot, 'T' }); p.lot = 0; p.open = false; return; }
        if (!p.partial_done) {
            double trig = p.entry - m.partial_trigger * (p.entry - p.tp);
            if (price <= trig && c.allow_partial_tp) {
                double q = p.init_lot * m.partial_ratio;
                if (q > 0 && q < p.lot) { fills.push_back({ price, q, 'P' }); p.lot -= q; }
                p.partial_done = true;
                double be = p.entry - m.be_buffer * p.risk;
                if (be < p.sl) p.sl = be;
            }
        }
        if (p.partial_done) {
            double trail = p.best + m.trailing_factor * p.risk;
            if (trail < p.sl) p.sl = trail;
        }
    }
}

// Signed price-points P&L of a fill for this position (engine multiplies by lot*vppl and subtracts costs).
inline double fill_points(const Position& p, const Fill& f) {
    return p.is_long ? (f.price - p.entry) : (p.entry - f.price);
}

}  // namespace kk::kenkem
