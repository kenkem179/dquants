// Entry detection — exact port of Entries/EntryVP.mqh::DetectSignal. Fully bidirectional
// (breakout L/S + reversion L/S). Node states are supplied by the caller (NodeEngine read on the
// CURRENT master VAH/VAL and on the signal close). master_sig = signal-VP (== master_cur unless
// use_prior_bar_vp, in which case the caller recomputes it at shift 2).
//
// Shift map (caller's responsibility): signal-bar OHLC + atr2 = shift 2; entry_close + atr1 = shift 1.
#pragma once
#include <cmath>
#include <algorithm>
#include "kk/common/types.hpp"
#include "kk/common/config.hpp"

namespace kk {

struct SignalBar {
    double o = 0, h = 0, l = 0, c = 0;   // signal-bar OHLC (shift 2)
    double atr2 = 0;                     // ATR at shift 2 (Pine atr[1])
    double atr1 = 0;                     // ATR at shift 1 (Pine atr[0])
    double entry_close = 0;              // close at shift 1 (entry anchor)
};

inline Signal detect_signal(const Params& p,
                            const VPResult& master_cur, const VPResult& master_sig,
                            const VPResult& local_cur, const RegimeState& regime,
                            const SignalBar& s,
                            const NodeState& ns_vah, const NodeState& ns_val,
                            const NodeState& ns_px, double rr_scale = 1.0) {
    Signal out;
    if (!master_cur.valid || !regime.valid) return out;
    if (s.c <= 0 || s.o <= 0 || s.h <= 0 || s.l <= 0 || s.h < s.l) return out;

    const double sVah = master_sig.valid ? master_sig.vah : 0.0;
    const double sVal = master_sig.valid ? master_sig.val : 0.0;
    const bool   haveSig = master_sig.valid;

    const double brkBuf = p.break_buf_atr * s.atr2;
    const double brkMax = p.break_max_atr * s.atr2;
    const double touch  = std::max(p.retest_atr * s.atr2, 3.0 * p.pip_size);

    const double rng     = std::max(s.h - s.l, p.mintick);
    const double bodyPct = std::fabs(s.c - s.o) / rng;
    const bool   bullBody = (s.c > s.o) && (bodyPct >= p.body_pct_min);
    const bool   bearBody = (s.c < s.o) && (bodyPct >= p.body_pct_min);
    const double upWick   = s.h - std::max(s.o, s.c);
    const double dnWick   = std::min(s.o, s.c) - s.l;
    const double bodyAbs  = std::fabs(s.c - s.o);

    // breakout raw triggers (windowed: clear brkBuf, not beyond brkMax = anti-chase)
    const bool brkLong  = haveSig && (s.c > sVah + brkBuf) && (s.c <= sVah + brkMax);
    const bool brkShort = haveSig && (s.c < sVal - brkBuf) && (s.c >= sVal - brkMax);

    const bool brkLongOk  = !p.node_gate_enabled || (ns_vah.absorbed || ns_vah.state >= 0);
    const bool brkShortOk = !p.node_gate_enabled || (ns_val.absorbed || ns_val.state <= 0);

    const bool buyFlowVahOk  = (ns_vah.net >=  p.sfp_flow_min) && (ns_px.net >=  p.sfp_flow_min);
    const bool sellFlowValOk = (ns_val.net <= -p.sfp_flow_min) && (ns_px.net <= -p.sfp_flow_min);
    const bool brkFlowLongOk  = !p.brk_require_flow || buyFlowVahOk;
    const bool brkFlowShortOk = !p.brk_require_flow || sellFlowValOk;

    const bool brkVetoLongOk  = !p.brk_veto_sfp || !(upWick > dnWick && upWick > bodyAbs);
    const bool brkVetoShortOk = !p.brk_veto_sfp || !(dnWick > upWick && dnWick > bodyAbs);

    const bool longBrk  = p.enable_breakout && regime.trend && brkLong
                          && (regime.plus > regime.minus) && brkLongOk && brkFlowLongOk && brkVetoLongOk;
    const bool shortBrk = p.enable_breakout && regime.trend && brkShort
                          && (regime.minus > regime.plus) && brkShortOk && brkFlowShortOk && brkVetoShortOk;

    // reversion (fades the opposite edge; FORBIDS absorbed nodes).
    // Edge source: master VP by default; LOCAL VP when rev_entry_local (the user's near-term-fade idea).
    // With the flag off, revVal/revVah/haveRev collapse to the master values => byte-identical.
    const double revVal  = (p.rev_entry_local && local_cur.valid) ? local_cur.val : sVal;
    const double revVah  = (p.rev_entry_local && local_cur.valid) ? local_cur.vah : sVah;
    const bool   haveRev = p.rev_entry_local ? local_cur.valid : haveSig;
    const bool nearVal = haveRev && (std::fabs(s.l - revVal) <= touch);
    const bool nearVah = haveRev && (std::fabs(s.h - revVah) <= touch);
    const bool revLongOk  = !p.node_gate_enabled || (!ns_val.absorbed && ns_val.state >= 0);
    const bool revShortOk = !p.node_gate_enabled || (!ns_vah.absorbed && ns_vah.state <= 0);
    const bool longRev  = p.enable_reversion && regime.balance && nearVal && bullBody && revLongOk;
    const bool shortRev = p.enable_reversion && regime.balance && nearVah && bearBody && revShortOk;

    const bool enterLong  = longRev || longBrk;
    const bool enterShort = shortRev || shortBrk;
    if (!enterLong && !enterShort) return out;
    if (enterLong && enterShort)   return out;   // never both (defensive)

    if (s.entry_close <= 0) return out;

    out.valid = true;
    out.is_long = enterLong;
    out.entry = s.entry_close;

    if (enterLong) {
        const bool isRev = longRev;
        const double slAtrUse = isRev ? p.sl_atr_rev : p.sl_atr_brk;
        double sl = s.entry_close - std::max(slAtrUse * s.atr1, 8.0 * p.pip_size);
        if (isRev && local_cur.valid) sl = std::min(sl, local_cur.lo - 4.0 * p.pip_size);
        const double risk = s.entry_close - sl;
        const double rr = (isRev ? p.rr_rev : p.rr_brk) * rr_scale;
        out.is_rev = isRev; out.sl = sl; out.risk = risk;
        out.tp1 = s.entry_close + risk * p.tp1_r;
        out.tp2 = s.entry_close + risk * rr;
        // Full-bank-at-mPOC option (reversion only): target the value magnet (humble RR) instead
        // of the fixed rr_rev multiple. Run with trail_runner OFF + tp1_close_pct 0 to bank it whole.
        {
            const double revPoc = (p.rev_tp_local && local_cur.valid) ? local_cur.poc : master_cur.poc;
            if (isRev && p.rev_tp_mpoc && revPoc > s.entry_close) out.tp2 = revPoc;
        }
        out.reason = isRev ? "L-REV" : "L-BRK";
    } else {
        const bool isRev = shortRev;
        const double slAtrUse = isRev ? p.sl_atr_rev : p.sl_atr_brk;
        double sl = s.entry_close + std::max(slAtrUse * s.atr1, 8.0 * p.pip_size);
        if (isRev && local_cur.valid) sl = std::max(sl, local_cur.hi + 4.0 * p.pip_size);
        const double risk = sl - s.entry_close;
        const double rr = (isRev ? p.rr_rev : p.rr_brk) * rr_scale;
        out.is_rev = isRev; out.sl = sl; out.risk = risk;
        out.tp1 = s.entry_close - risk * p.tp1_r;
        out.tp2 = s.entry_close - risk * rr;
        {
            const double revPoc = (p.rev_tp_local && local_cur.valid) ? local_cur.poc : master_cur.poc;
            if (isRev && p.rev_tp_mpoc && revPoc > 0.0 && revPoc < s.entry_close) out.tp2 = revPoc;
        }
        out.reason = isRev ? "S-REV" : "S-BRK";
    }

    if (out.risk <= 0.0) { out = Signal{}; return out; }

    // diagnostic features (no trading effect)
    const double atrF = (s.atr2 > 0.0) ? s.atr2 : 1.0;
    if (enterLong) {
        out.f_brk_dist_atr = (sVah > 0.0) ? (s.c - sVah) / atrF : 0.0;
        out.f_runway_atr   = (master_cur.hi - s.c) / atrF;
        out.f_node_net     = ns_vah.net;
    } else {
        out.f_brk_dist_atr = (sVal > 0.0) ? (sVal - s.c) / atrF : 0.0;
        out.f_runway_atr   = (s.c - master_cur.lo) / atrF;
        out.f_node_net     = ns_val.net;
    }
    out.f_body_pct  = bodyPct;
    out.f_adx       = regime.adx;
    out.f_di_spread = std::fabs(regime.plus - regime.minus);
    return out;
}

}  // namespace kk
