// KenKem P6b — faithful port of the EA's adaptive early-exit suite that the distilled trade-manager
// dropped (and the config parsed-but-ignored): the fast-ADX PANIC exit and the SCORE-DROP exit. These
// cut losers early on momentum reversal / quality decay instead of riding them to the full stop — the
// main reason the distilled engine's E1 bled to full-SL losses.
//
// Bar-granularity model: the engine evaluates these once per M1 bar (at the bar's open, using the
// closed-bar snapshot) before walking the bar's OHLC. The EA evaluates the score-drop on each new M1
// bar and the panic per tick; once-per-bar is the deterministic no-lookahead analog.
//
// Source: TradeManager.mqh (panic :1351-1428, score-drop :969-1031), TrendIdentifier.mqh
// (GetActiveTradeMomentumScore :261-301), ADXRSIHelpers.mqh (HasTrendAcceleration).
#pragma once
#include "kk/kenkem/snapshot.hpp"
#include "kk/kenkem/scoring.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include <cmath>

namespace kk::kenkem {

// HasTrendAcceleration over explicit ADX/DI buffers (so M1 can use the ADX(9) "short" buffers and M3
// the ADX(14) buffers). idx = newest closed bar (series index 0).
inline bool kk_accel_buf(const std::vector<double>& adx, const std::vector<double>& diP,
                         const std::vector<double>& diM, int idx, bool is_long) {
    if (idx < 2) return false;
    auto A  = [&](int k){ return TfIndicators::get(adx, idx - k); };
    auto SP = [&](int k){ return is_long ? TfIndicators::get(diP, idx - k) - TfIndicators::get(diM, idx - k)
                                         : TfIndicators::get(diM, idx - k) - TfIndicators::get(diP, idx - k); };
    return (A(0) > A(1)) && (A(1) > A(2)) && (SP(0) > SP(1)) && (SP(1) > SP(2)) && (SP(0) > 0.5);
}

// GetActiveTradeMomentumScore (max 5; +1 for E4). All reads from the closed-bar snapshot.
inline int active_momentum_score(const Snapshot& s, bool is_long, int kind, const KenKemConfig& c) {
    int score = 0;
    double m1sp = is_long ? (s.diP[0] - s.diM[0]) : (s.diM[0] - s.diP[0]);
    if (m1sp >= 5.0) score += 2; else if (m1sp > 0.0) score += 1;
    if (s.adx[0] >= 15.0) score += 1;
    double m3sp = is_long ? (s.diP[1] - s.diM[1]) : (s.diM[1] - s.diP[1]);
    if (m3sp > 0.0) score += 1;
    double ema71 = s.emaM1[2];                          // EMA2 (the "75" label is stale)
    if (is_long ? (s.closeM1 > ema71) : (s.closeM1 < ema71)) score += 1;
    if (kind == 4) {                                    // E4: Ichimoku current cloud agreement
        double top = std::max(s.senkouA_M3, s.senkouB_M3), bot = std::min(s.senkouA_M3, s.senkouB_M3);
        if (is_long ? (s.closeM1 > top) : (s.closeM1 < bot)) score += 1;
    }
    (void)c;
    return score;
}

// Per-position adaptive-exit state the engine threads across bars.
struct ExitState {
    int  best_score = -1;
    int  drop_count = 0;
};

inline bool panic_exit_enabled(int kind, const KenKemConfig& c) {
    if (kind == 2) return c.panic_exit_e2;
    if (kind == 4) return c.panic_exit_e4;
    if (kind == 5) return c.panic_exit_e5;
    return c.panic_exit_e1;
}
inline bool score_drop_enabled(int kind, const KenKemConfig& c) {
    if (kind == 2) return c.score_drop_e2;
    if (kind == 4) return c.score_drop_e4;
    if (kind == 5) return c.score_drop_e5;
    return c.score_drop_e1;
}
inline int score_drop_threshold(int kind, const KenKemConfig& c) {
    if (kind == 2) return c.score_drop_thr_e2;
    if (kind == 4) return c.score_drop_thr_e4;
    if (kind == 5) return c.score_drop_thr_e5;
    return c.score_drop_thr_e1;
}

// Panic PRICE gate (TradeManager :1363-1393, Scenario A profit-giveback / B SL-used). Per-tick in the
// EA, so cur_price is the LIVE tick price. best = position high-water price. partial_done = partial taken.
inline bool panic_price_gate(bool is_long, double entry, double sl, double cur_price,
                             double best, bool partial_done, const KenKemConfig& c) {
    double floatingPnL = is_long ? (cur_price - entry) : (entry - cur_price);
    if (partial_done && floatingPnL > 0.0) {
        double mfe = is_long ? (best - entry) : (entry - best);
        if (mfe > 0.0 && (mfe - floatingPnL) / mfe >= c.panic_min_profit_giveback) return true;
    }
    if (floatingPnL < 0.0) {
        double slDist = std::fabs(sl - entry);
        if (slDist > 0.0 && ((-floatingPnL) / slDist) >= c.panic_min_sl_used) return true;
    }
    return false;
}

// Panic REVERSAL confirm (TradeManager :1402-1406): M1(ADX9)+M3(ADX14) both accelerate in the reversed
// direction. Bar-constant within a forming bar, so the tick engine caches it once per new bar.
inline bool panic_reversal(bool is_long, const TfBundle& b, const TfBundle::Align& align,
                           const KenKemConfig& c) {
    (void)c;
    bool reversed = !is_long;
    const int i1 = align.m1 - 1, j3 = align.m3 - 1;
    bool m1rev = b.m1.has_short && kk_accel_buf(b.m1.adxS, b.m1.diPS, b.m1.diMS, i1, reversed);
    bool m3rev = kk_accel_buf(b.m3.adx, b.m3.diP, b.m3.diM, j3, reversed);
    return m1rev && m3rev;
}

// Fast-ADX panic exit decision (bar-granular convenience: gate@cur_price + reversal). Retained for the
// bar engine; the tick engine evaluates the gate per-tick against the cached reversal flag.
inline bool panic_exit_triggers(int kind, bool is_long, double entry, double sl, double cur_price,
                                double best, bool partial_done, const TfBundle& b,
                                const TfBundle::Align& align, const KenKemConfig& c) {
    if (!panic_exit_enabled(kind, c)) return false;
    if (!panic_price_gate(is_long, entry, sl, cur_price, best, partial_done, c)) return false;
    return panic_reversal(is_long, b, align, c);
}

// Score-drop exit decision (updates st). tp_dist/profit gate per the EA: close only when a partial has
// been taken OR floating profit < 10% of TP distance. Returns true to close at market.
inline bool score_drop_triggers(int kind, bool is_long, double entry, double tp, double cur_price,
                                bool partial_done, const Snapshot& s, const KenKemConfig& c,
                                ExitState& st) {
    int cur = active_momentum_score(s, is_long, kind, c);
    if (cur > st.best_score) st.best_score = cur;
    if (!score_drop_enabled(kind, c) || st.best_score <= 0) { return false; }
    int drop = st.best_score - cur;
    if (drop >= score_drop_threshold(kind, c)) ++st.drop_count; else st.drop_count = 0;

    double tpDist = std::fabs(tp - entry);
    double signedProfit = is_long ? (cur_price - entry) : (entry - cur_price);
    double profitPct = tpDist > 0.0 ? (signedProfit / tpDist) * 100.0 : 0.0;
    bool profitGate = partial_done || (profitPct < 10.0);

    return st.drop_count >= c.score_drop_consec && profitGate;
}

}  // namespace kk::kenkem
