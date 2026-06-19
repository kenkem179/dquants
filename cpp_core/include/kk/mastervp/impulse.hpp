// Monster impulse-thrust (kind 4) — the ONE entry-model delta of KK-MasterVP-Monster over the
// faithful KK-MasterVP base. A single decisive thrust candle that fires ONLY in the high-volatility
// band the normal ceiling (max_atr_pct) vetoes, so impulse and the base breakout/reversion never
// compete on the same bar. Logic ported from the Monster spec (md §3) + the deprecated fork's
// monster_signal.hpp, but built to consume the SAME inputs detect_signal() gets (SignalBar +
// master VP) so it inherits the base shift map exactly.
//
// SL deliberately reuses the faithful BASE breakout SL (entry - sl_atr_brk*atr1), NOT the Pine
// VAH-anchored SL: the C++ base has no brk_sl_buf_atr term, and the user directive is to inherit
// the validated base economics. TP1 reuses tp1_r (breakout TP1; reversion is OFF in Monster).
//
// Shift map (caller mirrors detect_signal): s.c/o/h/l + s.atr2 = signal bar (shift-2); s.atr1 =
// shift-1 ATR (SL side); s.entry_close = entry anchor (shift-1 close). master_cur/master_pred are
// computed at the master window ending on the forming bar, exactly like detect_signal's master_sig.
#pragma once
#include <cmath>
#include <algorithm>
#include "kk/common/types.hpp"
#include "kk/common/config.hpp"
#include "kk/mastervp/strategy.hpp"   // SignalBar

namespace kk {

// slope_up/slope_dn: master-POC rising/falling over impulse_trend_slope_bars (caller-computed).
// net_m1 / has_m1: M1 near-price net tick volume at the decision time (caller-computed via tf_net).
inline Signal detect_impulse(const Params& p,
                             const VPResult& master_cur, const VPResult& master_pred,
                             const SignalBar& s,
                             bool slope_up, bool slope_dn,
                             double net_m1, bool has_m1) {
    Signal out;
    if (!p.enable_impulse || !master_cur.valid) return out;
    if (s.c <= 0 || s.o <= 0 || s.h <= 0 || s.l <= 0 || s.h < s.l) return out;
    if (s.entry_close <= 0) return out;

    const double atrE = s.atr2;    // entry-side ATR (matches detect_signal brkBuf)
    const double atrSL = s.atr1;   // SL-side ATR (matches detect_signal SL)
    if (atrE <= 0.0) return out;

    const double mVah = master_cur.vah, mVal = master_cur.val, mPoc = master_cur.poc;
    const double pPocRef = master_pred.valid ? master_pred.poc : mPoc;
    const double pVahRef = master_pred.valid ? master_pred.vah : mVah;
    const double pValRef = master_pred.valid ? master_pred.val : mVal;

    const double candleH = s.h - s.l;
    const bool thrustBull = (s.c > s.o) && (candleH >= p.impulse_candle_atr * atrE);
    const bool thrustBear = (s.c < s.o) && (candleH >= p.impulse_candle_atr * atrE);
    const bool netLongOk  = has_m1 && (net_m1 >=  p.impulse_net_min);
    const bool netShortOk = has_m1 && (net_m1 <= -p.impulse_net_min);
    const bool trendLong  = slope_up && (pPocRef >= mPoc);
    const bool trendShort = slope_dn && (pPocRef <= mPoc);
    const bool entryL = (s.c >= mVah + p.impulse_entry_buf_atr * atrE)
                     && (p.impulse_max_dist_atr <= 0.0 || s.c <= pVahRef + p.impulse_max_dist_atr * atrE);
    const bool entryS = (s.c <= mVal - p.impulse_entry_buf_atr * atrE)
                     && (p.impulse_max_dist_atr <= 0.0 || s.c >= pValRef - p.impulse_max_dist_atr * atrE);

    const bool longImp  = thrustBull && entryL && trendLong  && netLongOk;
    const bool shortImp = thrustBear && entryS && trendShort && netShortOk;
    if (longImp == shortImp) return out;   // need exactly one direction

    out.is_long = longImp;
    out.entry = s.entry_close;
    if (longImp) {
        const double sl = s.entry_close - std::max(p.sl_atr_brk * atrSL, 8.0 * p.pip_size);
        const double risk = s.entry_close - sl;
        if (risk <= 0.0) return out;
        out.sl = sl; out.risk = risk;
        out.tp1 = s.entry_close + risk * p.tp1_r;
        out.tp2 = s.entry_close + risk * p.impulse_rr;
        out.reason = "L-IMP";
    } else {
        const double sl = s.entry_close + std::max(p.sl_atr_brk * atrSL, 8.0 * p.pip_size);
        const double risk = sl - s.entry_close;
        if (risk <= 0.0) return out;
        out.sl = sl; out.risk = risk;
        out.tp1 = s.entry_close - risk * p.tp1_r;
        out.tp2 = s.entry_close - risk * p.impulse_rr;
        out.reason = "S-IMP";
    }
    out.valid = true;
    out.is_impulse = true;

    // diagnostic features (no trading effect)
    const double atrF = (atrE > 0.0) ? atrE : 1.0;
    out.f_brk_dist_atr = longImp ? (s.c - mVah) / atrF : (mVal - s.c) / atrF;
    out.f_runway_atr   = longImp ? (master_cur.hi - s.c) / atrF : (s.c - master_cur.lo) / atrF;
    out.f_body_pct     = std::fabs(s.c - s.o) / std::max(candleH, p.mintick);
    out.f_node_net     = net_m1;
    return out;
}

}  // namespace kk
