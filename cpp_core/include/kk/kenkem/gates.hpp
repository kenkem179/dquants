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

}  // namespace kk::kenkem
