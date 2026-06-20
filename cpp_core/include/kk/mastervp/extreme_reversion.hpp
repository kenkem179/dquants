// Extreme Reversion (XRev) — failed-breakout liquidity-sweep reversal entry family for KK-MasterVP.
// Toggle OFF by default (enable_extreme_reversion); when OFF this header is never invoked and the base
// breakout/reversion economics are byte-identical. Modeled on impulse.hpp: a PURE function consuming the
// SAME shift map detect_signal() gets (SignalBar s = signal/rejection bar shift-2; entry anchor = shift-1
// close) plus a handful of caller-precomputed lookback scalars, so it inherits the base shift map exactly.
//
// Canonical case = SHORT at master VAH: price SWEEPS max(mVAH, recent swing-high) — running the buy-stops —
// then closes back BELOW mVAH on a big, sell-flow-dominated candle with a visible upper rejection wick,
// after an aged round-trip up from mVAL. Target = mVAL (full value rotation); SL above the swept high so a
// second probe doesn't stop us cheaply. LONG is the exact mirror at mVAL. See the build-plan md for the
// economic rationale and the §2 falsifiable rules.
//
// Order-flow delta uses the synthetic node engine's near-price net (ns_px.net, in [-1,+1], same unit as the
// base 80% flow gate) — self-contained, so XRev works on M3/M5 without an M1 feed.
#pragma once
#include <cmath>
#include <algorithm>
#include "kk/common/types.hpp"
#include "kk/common/config.hpp"
#include "kk/mastervp/strategy.hpp"   // SignalBar

namespace kk {

// Caller-precomputed lookbacks (all use CLOSED bars only — no lookahead):
//   sweep_hi = max(mVAH, highestHigh(N)) over the N bars preceding the rejection bar
//   sweep_lo = min(mVAL, lowestLow(N))   over the same N bars (LONG mirror)
//   closes_above / closes_below = # bars whose close >/< mVAH/mVAL over the last M closed bars
//   aged_short = no mVAL up-cross within the last min_age_bars bars (mature up-leg into the trap)
//   aged_long  = no mVAH down-cross within the last min_age_bars bars
// ns_vah/ns_val = node state at the master edge; ns_px = node state at the rejection-bar close.
inline Signal detect_extreme_reversion(const Params& p,
                                       const VPResult& master_cur,
                                       const SignalBar& s,
                                       double sweep_hi, double sweep_lo,
                                       int closes_above, int closes_below,
                                       bool aged_short, bool aged_long,
                                       const NodeState& ns_vah, const NodeState& ns_val,
                                       const NodeState& ns_px) {
    Signal out;
    if (!p.enable_extreme_reversion || !master_cur.valid) return out;
    if (s.c <= 0 || s.o <= 0 || s.h <= 0 || s.l <= 0 || s.h < s.l) return out;
    if (s.entry_close <= 0) return out;

    const double atr2 = s.atr2;   // signal-bar ATR (candle-size + wick tests)
    const double atr1 = s.atr1;   // entry-side ATR (SL distance)
    if (atr2 <= 0.0 || atr1 <= 0.0) return out;

    const double mVah = master_cur.vah, mVal = master_cur.val;
    if (mVah <= 0.0 || mVal <= 0.0 || mVah <= mVal) return out;

    const double rng     = std::max(s.h - s.l, p.mintick);
    const double bodyPct = std::fabs(s.c - s.o) / rng;
    const double bodyAbs = std::fabs(s.c - s.o);
    const double upWick  = s.h - std::max(s.o, s.c);
    const double dnWick  = std::min(s.o, s.c) - s.l;

    // ---- A. failed-acceptance count (trapped positioning built above/below value) ----
    auto count_ok = [&](int cnt) {
        if (cnt < p.xrev_min_closes_beyond) return false;
        if (p.xrev_max_closes_beyond > 0 && cnt > p.xrev_max_closes_beyond) return false;
        return true;
    };

    // ---- B/C/D evaluated per direction ----
    const bool bigRange = rng >= p.xrev_big_candle_atr * atr2;
    const bool wickShort = (upWick >= p.xrev_wick_frac * bodyAbs);   // upper sweep tail
    const bool wickLong  = (dnWick >= p.xrev_wick_frac * bodyAbs);   // lower sweep tail

    // SHORT: sweep above max(VAH, HH(N)), close back below VAH, big bearish candle + upper wick,
    // sell-dominated near-price net, optional node sell/absorb at VAH, aged up-leg.
    const bool sweptShort = (s.h > sweep_hi);
    const bool failBackShort = (s.c < mVah);
    const bool bearBody = (s.c < s.o) && (bodyPct >= p.xrev_body_pct_min);
    const bool netShort = (ns_px.net <= -p.xrev_net_delta_min);
    const bool nodeShortOk = !p.xrev_use_node_gate || (ns_vah.absorbed || ns_vah.state <= 0);
    const bool shortXR = count_ok(closes_above) && aged_short && sweptShort && failBackShort
                         && bearBody && bigRange && wickShort && netShort && nodeShortOk;

    // LONG mirror at mVAL.
    const bool sweptLong = (s.l < sweep_lo);
    const bool failBackLong = (s.c > mVal);
    const bool bullBody = (s.c > s.o) && (bodyPct >= p.xrev_body_pct_min);
    const bool netLong = (ns_px.net >= p.xrev_net_delta_min);
    const bool nodeLongOk = !p.xrev_use_node_gate || (ns_val.absorbed || ns_val.state >= 0);
    const bool longXR = count_ok(closes_below) && aged_long && sweptLong && failBackLong
                        && bullBody && bigRange && wickLong && netLong && nodeLongOk;

    if (longXR == shortXR) return out;   // need exactly one direction (mutually exclusive by construction)

    out.is_long = longXR;
    out.entry = s.entry_close;
    if (shortXR) {
        const double sl = sweep_hi + p.xrev_sl_atr * atr1;
        const double risk = sl - s.entry_close;
        if (risk <= 0.0) return out;
        const double runway = s.entry_close - mVal;          // target = mVAL
        if (runway <= 0.0) return out;
        if (runway / risk < p.xrev_rr_min) return out;       // RR filter
        out.sl = sl; out.risk = risk;
        out.tp1 = s.entry_close - risk * p.tp1_r;
        out.tp2 = mVal;
        out.reason = "S-XREV";
    } else {
        const double sl = sweep_lo - p.xrev_sl_atr * atr1;
        const double risk = s.entry_close - sl;
        if (risk <= 0.0) return out;
        const double runway = mVah - s.entry_close;          // target = mVAH
        if (runway <= 0.0) return out;
        if (runway / risk < p.xrev_rr_min) return out;
        out.sl = sl; out.risk = risk;
        out.tp1 = s.entry_close + risk * p.tp1_r;
        out.tp2 = mVah;
        out.reason = "L-XREV";
    }
    out.valid = true;
    out.is_rev = true;            // reversion economics (regime-balance complement of breakout)
    out.is_extreme_rev = true;

    // diagnostic features (no trading effect)
    const double atrF = (atr2 > 0.0) ? atr2 : 1.0;
    out.f_body_pct   = bodyPct;
    out.f_node_net   = ns_px.net;
    out.f_brk_dist_atr = longXR ? (mVal - s.c) / atrF : (s.c - mVah) / atrF;
    out.f_runway_atr   = longXR ? (mVah - s.entry_close) / atrF : (s.entry_close - mVal) / atrF;
    return out;
}

}  // namespace kk
