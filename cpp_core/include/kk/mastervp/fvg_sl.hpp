// FVG-anchored stop-loss (feature #3) — default OFF (inert / base byte-identical).
//
// User thesis (Desktop/testcases 1-6): a breakout stop placed just BEYOND the most recent
// significant Fair Value Gap (3-bar imbalance) sitting between entry and the value-area edge wins
// more often than a fixed-ATR stop, because the gap is untested price the move must reclaim to be
// invalidated — noise can't tag a stop parked past it. We re-anchor the SL to that gap and recompute
// risk + TP1/TP2 with the SAME RR multiples the detector used, so trade geometry stays self-consistent
// and position sizing (risk-based) auto-scales the lot down for the wider stop.
//
// Geometry:
//   LONG  (broke UP through VAH): the protective gap is BULLISH (gap up) — low[k] > high[k-2].
//         It is a support shelf BELOW entry. SL = high[k-2] (gap bottom) - buffer.
//         With fvg_beyond_va: the gap bottom must sit at/above VAH (breakout territory), so the
//         band is VAH <= gap < entry — exactly the imbalance the up-break left behind.
//   SHORT (broke DOWN through VAL): the gap is BEARISH (gap down) — high[k] < low[k-2].
//         Resistance shelf ABOVE entry. SL = low[k-2] (gap top) + buffer.
//         With fvg_beyond_va: gap top must sit at/below VAL, band entry < gap <= VAL.
//
// Only base breakout/reversion entries are touched (NOT Monster impulse, NOT XRev — those carry
// bespoke targets). Reversion is skipped too when fvg_breakout_only. No qualifying gap, or a guard
// rejects it (significance / side / beyond-VA / risk clamp / mode) => signal returned UNCHANGED.
#pragma once
#include <cmath>
#include <algorithm>
#include "kk/common/types.hpp"
#include "kk/common/config.hpp"

namespace kk {

// bars[] = full M-series; sigBar = the bar detect_signal read as the signal bar (engine i-1).
// atr = ATR at the entry bar (atr1) — matches the ATR the detector used to size its stop.
inline void apply_fvg_sl(const Params& p, Signal& sig,
                         const Bar* bars, int n, int sigBar,
                         double atr, double vah, double val,
                         double rr_scale = 1.0) {
    if (!p.enable_fvg_sl || !sig.valid || atr <= 0.0) return;
    if (sig.is_impulse || sig.is_extreme_rev) return;     // bespoke targets — leave alone
    if (sig.is_rev && p.fvg_breakout_only) return;        // breakout-only by default
    if (sigBar < 2 || sigBar >= n) return;

    const double minGap = p.fvg_min_atr * atr;
    const double buf    = p.fvg_buf_atr * atr;
    const double entry  = sig.entry;
    const int    kHi    = sigBar;
    const int    kLo    = std::max(2, sigBar - p.fvg_lookback + 1);

    double newSl = 0.0, newRisk = 0.0;
    bool found = false;                                   // a qualifying gap exists on the correct side
    if (sig.is_long) {
        double anchor = 0.0;                              // bottom of the bullish gap
        for (int k = kHi; k >= kLo; --k) {
            const double gtop = bars[k].low, gbot = bars[k - 2].high;   // gap [gbot, gtop]
            if (gtop - gbot < minGap) continue;          // significant only
            if (gbot >= entry) continue;                 // support must sit below entry
            if (p.fvg_beyond_va && vah > 0.0 && gbot < vah) continue;   // gap in breakout territory
            anchor = gbot; break;                        // nearest (most recent) qualifying
        }
        if (anchor > 0.0 && anchor - buf < entry) { found = true; newSl = anchor - buf; newRisk = entry - newSl; }
    } else {
        double anchor = 0.0;                              // top of the bearish gap
        for (int k = kHi; k >= kLo; --k) {
            const double gbot = bars[k].high, gtop = bars[k - 2].low;   // gap [gbot, gtop]
            if (gtop - gbot < minGap) continue;
            if (gtop <= entry) continue;                 // resistance must sit above entry
            if (p.fvg_beyond_va && val > 0.0 && gtop > val) continue;   // gap in breakdown territory
            anchor = gtop; break;
        }
        if (anchor > 0.0 && anchor + buf > entry) { found = true; newSl = anchor + buf; newRisk = newSl - entry; }
    }

    // Entry-gate: with fvg_require, a breakout with no qualifying structural gap to hide behind is
    // dropped entirely (the user's "ensure successful breakouts" framing — trade only protected setups).
    if (!found) { if (p.fvg_require) sig = Signal{}; return; }

    if (p.fvg_mode == 1 && newRisk <= sig.risk) return;  // widen-only
    if (p.fvg_mode == 2 && newRisk >= sig.risk) return;  // tighten-only
    if (newRisk < p.fvg_min_risk_atr * atr) return;      // too tight to be structural
    if (newRisk > p.fvg_max_risk_atr * atr) return;      // too far — keep the ATR stop

    // Re-anchor. Recompute TP1/TP2 off the new risk with the detector's RR (preserve the reversion
    // mPOC magnet if it was set, since that target is a price, not an R-multiple).
    const bool keep_mpoc_tp2 = sig.is_rev && p.rev_tp_mpoc;
    const double rr = (sig.is_rev ? p.rr_rev : p.rr_brk) * rr_scale;
    sig.sl   = newSl;
    sig.risk = newRisk;
    if (sig.is_long) {
        sig.tp1 = entry + newRisk * p.tp1_r;
        if (!keep_mpoc_tp2) sig.tp2 = entry + newRisk * rr;
    } else {
        sig.tp1 = entry - newRisk * p.tp1_r;
        if (!keep_mpoc_tp2) sig.tp2 = entry - newRisk * rr;
    }
}

}  // namespace kk
