// KenKem P4b — distilled entry gates. The essential selectivity filters, kept; score-inflation
// secondary components (acceleration, price-action, M3-accel, ichimoku bonus) dropped.
//
//   trend_core_score : the HARD GATE from GetTrendQualityScore — ADX strength + DI spread + multi-TF
//                      DI alignment, each must score >=1 or the trade is blocked (returns 0). This is
//                      what actually keeps KenKem out of weak/ambiguous trends.
//   sideways_blocked : chop filter (sideways score >= block threshold).
//   htf_filter_ok    : higher-timeframe agreement per entry (E1=M5, E2=M15, E4=M5-or-M15).
#pragma once
#include "kk/kenkem/snapshot.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include <cmath>

namespace kk::kenkem {

// Core trend-quality (0-6): ADX(0-2) + DI spread(0-2) + MTF DI alignment(0-2).
// Returns 0 if the hard gate trips (any of the three core components == 0).
inline int trend_core_score(const Snapshot& s, bool is_long, const KenKemConfig& cfg) {
    // ADX strength (M1).
    int adxPts = (s.adx[0] >= cfg.adx_high_threshold) ? 2 : (s.adx[0] >= cfg.min_momentum_adx) ? 1 : 0;
    // DI spread in trade direction (M1).
    double spread = is_long ? (s.diP[0] - s.diM[0]) : (s.diM[0] - s.diP[0]);
    int diPts = (spread >= 3.0) ? 2 : (spread >= 1.0) ? 1 : 0;
    // Multi-TF DI alignment (M1/M3/M5 agree on direction).
    auto agree = [&](int tf){ return is_long ? (s.diP[tf] > s.diM[tf]) : (s.diM[tf] > s.diP[tf]); };
    int aligned = (agree(0) ? 1 : 0) + (agree(1) ? 1 : 0) + (agree(2) ? 1 : 0);
    int mtfPts = (aligned == 3) ? 2 : (aligned >= 2) ? 1 : 0;
    // Hard gate.
    if (cfg.enable_tq_gates && (adxPts == 0 || diPts == 0 || mtfPts == 0)) return 0;
    return adxPts + diPts + mtfPts;
}

inline bool sideways_blocked(const Snapshot& s, const KenKemConfig& cfg) {
    return s.sideways >= cfg.sideways_block_thr;
}

// A higher TF (index: M3=1, M5=2, M15=3) is "valid & agreeing": ADX>=min, directional DI spread>=min.
inline bool htf_tf_ok(const Snapshot& s, int tf, bool is_long, double min_adx, double min_di) {
    if (s.adx[tf] < min_adx) return false;
    double spread = is_long ? (s.diP[tf] - s.diM[tf]) : (s.diM[tf] - s.diP[tf]);
    return spread >= min_di;
}

inline bool htf_filter_ok(const Snapshot& s, bool is_long, HtfMode mode, double min_adx, double min_di) {
    switch (mode) {
        case HTF_DISABLED:    return true;
        case HTF_M5_ONLY:     return htf_tf_ok(s, 2, is_long, min_adx, min_di);
        case HTF_M15_ONLY:    return htf_tf_ok(s, 3, is_long, min_adx, min_di);
        case HTF_M5_AND_M15:  return htf_tf_ok(s, 2, is_long, min_adx, min_di) && htf_tf_ok(s, 3, is_long, min_adx, min_di);
        case HTF_M5_OR_M15:   return htf_tf_ok(s, 2, is_long, min_adx, min_di) || htf_tf_ok(s, 3, is_long, min_adx, min_di);
    }
    return true;
}

// E1/E4-style HTF: block ONLY when a VALID higher TF is COUNTER-trend (require-aligned is wrong for E1).
// "valid" = adx>=min && |DI spread|>=min_di; counter = HTF DI opposes trade direction.
// Faithful port of CheckE1EntryConditions_Internal HTF block (Entry1.mqh:231-280).
inline bool htf_block_counter_ok(const Snapshot& s, bool is_long, HtfMode mode, double min_adx, double min_di) {
    auto valid = [&](int tf){ return s.adx[tf] >= min_adx && std::fabs(s.diP[tf] - s.diM[tf]) >= min_di; };
    auto bull  = [&](int tf){ return s.diP[tf] > s.diM[tf]; };
    bool blockL = false, blockS = false;
    switch (mode) {
        case HTF_DISABLED: return true;
        case HTF_M5_ONLY:  if (valid(2)) { blockL = !bull(2); blockS = bull(2); } break;
        case HTF_M15_ONLY: if (valid(3)) { blockL = !bull(3); blockS = bull(3); } break;
        case HTF_M5_AND_M15:
            if (valid(2) && valid(3)) { blockL = (!bull(2) && !bull(3)); blockS = (bull(2) && bull(3)); }
            break;
        case HTF_M5_OR_M15:
            blockL = (valid(2) && !bull(2)) || (valid(3) && !bull(3));
            blockS = (valid(2) &&  bull(2)) || (valid(3) &&  bull(3));
            break;
    }
    return is_long ? !blockL : !blockS;
}

// EMA-stack readiness at the EA's GetEMA(tf,ema,ENTRY_SHIFT=1) position. Due to the non-series CopyBuffer
// trap (EMAHelpers.mqh GetEMAValues), GetEMA(...,1) lands at cache index (align_tf - 3) — the SAME shift
// the Stage-1-validated snapshot uses. The trigger machine reads raw closed-bar shifts; the GATES must
// use this entry shift to match isEMAsReadyForEntry / isAllTimeframeEMAsReadyForEntry.
inline bool emas_ready_entry(const TfIndicators& s, int align_tf, bool is_long, bool strict, double tol) {
    return emas_ready(s, align_tf - 3, is_long, strict, tol);
}

// M5 directional check for E1 MTF bypass (isAllTimeframeEMAsReadyForEntry, KenKemExpert.mq5:1960-1965):
// LONG: e25>e75 && e75>e100 && e25>e200 (NOTE: e100>e200 NOT required; e25>e200 IS). Mirror for short.
inline bool m5_directional_ok(const TfIndicators& m5, int align_m5, bool is_long) {
    const int idx = align_m5 - 3;
    if (idx < 0 || idx >= m5.size()) return false;
    const double e25 = m5.ema[1][idx], e75 = m5.ema[2][idx], e100 = m5.ema[3][idx], e200 = m5.ema[4][idx];
    return is_long ? (e25 > e75 && e75 > e100 && e25 > e200)
                   : (e25 < e75 && e75 < e100 && e25 < e200);
}

// HasSufficientMomentum (E1 only) — CalculateMomentum (TrendIdentifier.mqh:721-737).
// REQUIRE_ADX_CONFLUENCE: adx[M1,M3,M5] all >= E2_MIN_MOMENTUM_ADX(20) AND DI in trade dir on all three
// (delta 0.1). When confluence off: only M1+M3.
inline bool has_sufficient_momentum(const Snapshot& s, bool is_long, const KenKemConfig& c) {
    const double thr = c.e2_min_momentum_adx;
    bool strength = c.require_adx_confluence
        ? (s.adx[0] >= thr && s.adx[1] >= thr && s.adx[2] >= thr)
        : (s.adx[0] >= thr && s.adx[1] >= thr);
    const double d = 0.1;
    auto dir = [&](int tf){ return is_long ? (s.diP[tf] - s.diM[tf] > d) : (s.diM[tf] - s.diP[tf] > d); };
    bool aligned = c.require_adx_confluence ? (dir(0) && dir(1) && dir(2)) : (dir(0) && dir(1));
    return strength && aligned;
}

}  // namespace kk::kenkem
