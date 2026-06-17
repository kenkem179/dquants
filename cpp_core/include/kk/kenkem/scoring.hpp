// KenKem P4c — faithful port of the EA's entry-selectivity scoring that the distilled engine PARSED
// from the .set but never applied (the "config lie"): conviction scoring, full 0-11 trend-quality, and
// the RSI-divergence veto. Wiring these back in is what restores the EA's selectivity (E2 conviction
// threshold 10, trend-quality min 9, etc.) and stops the distilled engine from over-trading chop.
//
// PORT CONVENTION: the EA reads acceleration helpers at shift 0 (forming bar) and everything else at
// ENTRY_SHIFT=1. The dquants engine is strictly no-lookahead and decides on forming bar B using only
// CLOSED bars, so "shift 0 forming" maps to dquants i1 (= align.m1-1, the last closed bar) and the
// acceleration windows read the closed bars ending at i1. This is the no-lookahead analog of the EA's
// intent; it is NOT MT5 buffer-parity (the snapshot header already documents that trade-off).
//
// Source: ../kenkem EntryHelpers.mqh (conviction, RSI-div), TrendIdentifier.mqh (trend-quality),
// ADXRSIHelpers.mqh (IsAccelerating / HasTrendAcceleration).
#pragma once
#include "kk/kenkem/tf_cache.hpp"
#include "kk/kenkem/snapshot.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include <algorithm>
#include <cmath>

namespace kk::kenkem {

// HasTrendAcceleration(tf, trend, lookback): adx rising over 3 bars AND directional DI spread
// accelerating over 3 bars AND spread[0] > 0.5. idx = newest CLOSED bar (series shift 1).
//
// PARITY NOTE: the EA reads the iADX buffer at shift 0 (the forming bar, ArraySetAsSeries) so its window
// is {forming, closed, closed-1}; this reads {closed, closed-1, closed-2}. Modeling the forming bar's
// shift-0 ADX as a first-tick step is correct ONLY for M1 (bar just opened) — for M3/M5 the "forming"
// bar is partially built at an arbitrary M1 decision time and the first-tick model is WRONG, which
// empirically *hurt* trade parity (matched 4→1). So we keep the closed-bar window as the best available
// approximation; the residual ±1 trend-quality/conviction point is a documented tick-fidelity gap.
inline bool kk_trend_accel(const TfIndicators& tf, int idx, bool is_long, int min_bars) {
    if (idx < min_bars - 1 || idx < 2) return false;
    auto A  = [&](int k){ return TfIndicators::get(tf.adx, idx - k); };
    auto SP = [&](int k){ double p = TfIndicators::get(tf.diP, idx - k),
                                 m = TfIndicators::get(tf.diM, idx - k); return is_long ? p - m : m - p; };
    bool adxRising = (A(0) > A(1)) && (A(1) > A(2));
    bool spAccel   = (SP(0) > SP(1)) && (SP(1) > SP(2));
    return adxRising && spAccel && (SP(0) > 0.5);
}

// IsAccelerating(adx, n): adx[0]>adx[1] && adx[0]>adx[n-1] && (#rising over i=0..n-2) > (n-1)/2.
inline bool kk_adx_accel(const TfIndicators& tf, int idx, int n) {
    if (idx < n - 1) return false;
    auto A = [&](int k){ return TfIndicators::get(tf.adx, idx - k); };
    if (!(A(0) > A(1) && A(0) > A(n - 1))) return false;
    int rising = 0;
    for (int i = 0; i < n - 1; ++i) if (A(i) > A(i + 1)) ++rising;
    return rising > (n - 1) / 2;
}

// Count of close>open over the last `n` closed M1 bars ending at idx (for bullish/bearish price action).
inline int kk_dir_bar_count(const TfIndicators& m1, int idx, int n, bool bullish) {
    int cnt = 0, start = std::max(0, idx - n + 1);
    for (int i = start; i <= idx; ++i)
        if (bullish ? (m1.bars[i].close > m1.bars[i].open) : (m1.bars[i].close < m1.bars[i].open)) ++cnt;
    return cnt;
}

// Simple engulfing detector over the window (matches HasStrongTrendingPriceActions' OR condition).
inline bool kk_has_engulf(const TfIndicators& m1, int idx, int n, bool bullish) {
    int start = std::max(1, idx - n + 1);
    for (int i = start; i <= idx; ++i) {
        const kk::Bar& cu = m1.bars[i]; const kk::Bar& pr = m1.bars[i - 1];
        if (bullish) { if (cu.close > cu.open && pr.close < pr.open && cu.close > pr.open && cu.open < pr.close) return true; }
        else         { if (cu.close < cu.open && pr.close > pr.open && cu.close < pr.open && cu.open > pr.close) return true; }
    }
    return false;
}

// EMA stack separation in pips/30, clamped to 1.0; 0 if the 25/71/97/192 stack is not correctly ordered.
inline double kk_ema_stack_sep(const Snapshot& s, bool is_long, const KenKemConfig& c) {
    const double e25 = s.emaM1[1], e71 = s.emaM1[2], e97 = s.emaM1[3], e192 = s.emaM1[4];
    bool ordered = is_long ? (e25 > e71 && e71 > e97 && e97 >= e192)
                           : (e25 < e71 && e71 < e97 && e97 <= e192);
    if (!ordered) return 0.0;
    double avgGap = (std::fabs(e25 - e71) + std::fabs(e71 - e97) + std::fabs(e97 - e192)) / c.pip_size / 3.0;
    return std::min(1.0, avgGap / 30.0);
}

// ---- Conviction score (0-12). EntryHelpers.mqh CalculateConvictionScore. ----
// USE_HTF_VETO_E1/E2/E4 default false, so the -999 HTF veto is omitted (matches the .set).
inline int conviction_score(const TfBundle& b, const TfBundle::Align& align, const Snapshot& s,
                            bool is_long, const KenKemConfig& c) {
    const int i1 = align.m1 - 1, j3 = align.m3 - 1;
    int score = 0;

    // 1. M1 DI spread (0-2).
    double m1sp = is_long ? (s.diP[0] - s.diM[0]) : (s.diM[0] - s.diP[0]);
    score += (m1sp >= 3.0) ? 2 : (m1sp >= 1.0) ? 1 : 0;

    // 2. EMA stack separation (0-2).
    double sep = kk_ema_stack_sep(s, is_long, c);
    score += (sep >= 0.8) ? 2 : (sep >= 0.5) ? 1 : 0;

    // 3. RSI momentum (0-2, clamped). M1 level+velocity (shift1 vs shift+2) and M3 level (shift1).
    {
        double rsi_m1 = s.rsiM1;
        double rsi_m1_prev = (i1 >= 2 && b.m1.has_rsi) ? TfIndicators::get(b.m1.rsi, i1 - 2) : rsi_m1;
        double rsi_m3 = (j3 >= 0 && b.m3.has_rsi) ? TfIndicators::get(b.m3.rsi, j3) : 50.0;
        int rp = 0;
        if (is_long) {
            bool m1Above = rsi_m1 > 50.0, m3Above = rsi_m3 > 50.0;
            double vel = (rsi_m1 - rsi_m1_prev) / 2.0;
            if (m1Above && m3Above) rp += 2; else if (m1Above || m3Above) rp += 1;
            if (vel > 1.5 && m1Above) rp += 1;
        } else {
            bool m1Below = rsi_m1 < 50.0, m3Below = rsi_m3 < 50.0;
            double vel = (rsi_m1_prev - rsi_m1) / 2.0;
            if (m1Below && m3Below) rp += 2; else if (m1Below || m3Below) rp += 1;
            if (vel > 1.5 && m1Below) rp += 1;
        }
        score += std::max(0, std::min(2, rp));
    }

    // 4. ADX strength + acceleration (0-2, clamped).
    {
        int ap = 0;
        if (s.adx[0] >= 23.0) ap += 1; else if (s.adx[0] < 15.0) ap -= 1;
        if (kk_adx_accel(b.m1, i1, 3)) ap += 1;
        score += std::max(0, std::min(2, ap));
    }

    // 5. M3 + M5 MTF confirmation (0-2).
    {
        double sp3 = is_long ? (s.diP[1] - s.diM[1]) : (s.diM[1] - s.diP[1]);
        double sp5 = is_long ? (s.diP[2] - s.diM[2]) : (s.diM[2] - s.diP[2]);
        bool m3Strong = (s.adx[1] >= 22.0 && sp3 >= 2.0), m3Support = (s.adx[1] >= 16.0 && sp3 > 0.5);
        bool m5Strong = (s.adx[2] >= 22.0 && sp5 >= 2.0), m5Support = (s.adx[2] >= 16.0 && sp5 > 0.5);
        if (m3Strong && m5Strong) score += 2;
        else if (m3Strong || m5Strong) score += 1;
        else if (m3Support && m5Support) score += 1;
    }

    // 6. Price action structure (0-2).
    {
        bool bull = kk_dir_bar_count(b.m1, i1, 3, true)  >= 2;   // CheckBullishPriceAction(3): >= n-1
        bool bear = kk_dir_bar_count(b.m1, i1, 3, false) >= 2;
        if (is_long && bull) score += 2;
        else if (!is_long && bear) score += 2;
        else if (is_long && !bear) score += 1;
        else if (!is_long && !bull) score += 1;
    }
    return score;   // 0..12
}

// Ichimoku cloud alignment (0-2): +1 M1 future-cloud color matches trend AND price beyond current cloud;
// +1 M3 future-cloud color matches trend. Only counts when USE_ICHIMOKU_E{entry} is on.
inline int kk_ichimoku_points(const TfBundle& b, const TfBundle::Align& align, const Snapshot& s,
                              bool is_long, int entryNum, const KenKemConfig& c) {
    bool use = (entryNum == 1) ? c.use_ichimoku_e1 : (entryNum == 2) ? c.use_ichimoku_e2
             : (entryNum == 4) ? c.use_ichimoku_e4 : false;
    if (!use) return 0;
    int pts = 0;
    const int i1 = align.m1 - 1, j3 = align.m3 - 1;
    if (b.m1.has_ichi && i1 >= 0 && b.m1.ichi.valid_at(i1)) {
        double fa = TfIndicators::get(b.m1.ichi.span_a_fut, i1), fb = TfIndicators::get(b.m1.ichi.span_b_fut, i1);
        double ca = TfIndicators::get(b.m1.ichi.span_a_cur, i1), cb = TfIndicators::get(b.m1.ichi.span_b_cur, i1);
        bool colorOk = is_long ? (fa > fb) : (fa < fb);
        bool priceOk = is_long ? (s.closeM1 > std::max(ca, cb)) : (s.closeM1 < std::min(ca, cb));
        if (colorOk && priceOk) pts += 1;
    }
    if (b.m3.has_ichi && j3 >= 0 && b.m3.ichi.valid_at(j3)) {
        double fa = TfIndicators::get(b.m3.ichi.span_a_fut, j3), fb = TfIndicators::get(b.m3.ichi.span_b_fut, j3);
        bool colorOk = is_long ? (fa > fb) : (fa < fb);
        if (colorOk) pts += 1;
    }
    return pts;
}

// ---- Trend-quality score (0-11, +2 Ichimoku, +1 ATR). TrendIdentifier.mqh GetTrendQualityScore. ----
// Returns 0 if the hard gate trips (ADX/DI/MTF component == 0 and gates enabled, entryNum != 5).
inline int trend_quality_score(const TfBundle& b, const TfBundle::Align& align, const Snapshot& s,
                               bool is_long, int entryNum, const KenKemConfig& c) {
    const int i1 = align.m1 - 1, j3 = align.m3 - 1;

    // 1. ADX strength (0-2).
    int adxPts = (s.adx[0] >= c.adx_high_threshold) ? 2 : (s.adx[0] >= c.min_momentum_adx) ? 1 : 0;
    // 2. DI spread (0-2).
    double sp = is_long ? (s.diP[0] - s.diM[0]) : (s.diM[0] - s.diP[0]);
    int spreadPts = (sp >= 3.0) ? 2 : (sp >= 1.0) ? 1 : 0;
    // 3. M1 acceleration (0-2).
    int accelPts = 0;
    if (c.use_acceleration_bonus) {
        if (kk_trend_accel(b.m1, i1, is_long, 5)) accelPts = 2;
        else if (kk_trend_accel(b.m1, i1, is_long, 3)) accelPts = 1;
    }
    // 4. MTF alignment (0-2): M1/M3/M5 DI direction agreement.
    auto agree = [&](int tf){ return is_long ? (s.diP[tf] > s.diM[tf]) : (s.diM[tf] > s.diP[tf]); };
    int aligned = (agree(0) ? 1 : 0) + (agree(1) ? 1 : 0) + (agree(2) ? 1 : 0);
    int mtfPts = (aligned == 3) ? 2 : (aligned >= 2) ? 1 : 0;

    // Hard gate (entryNum != 5).
    if (entryNum != 5 && c.enable_tq_gates && (adxPts == 0 || spreadPts == 0 || mtfPts == 0)) return 0;

    int score = adxPts + spreadPts + accelPts + mtfPts;
    // 5. Price action (0-1).
    bool bull = entryNum != 5 ? is_long : is_long;   // direction = trade direction
    int dirCnt = kk_dir_bar_count(b.m1, i1, 5, is_long);
    if (dirCnt >= 4 || kk_has_engulf(b.m1, i1, 5, is_long)) score += 1;
    (void)bull;
    // 6. M3 acceleration (0-1).
    if (j3 >= 0 && kk_trend_accel(b.m3, j3, is_long, 3)) score += 1;
    // 7. Ichimoku cloud (0-2, only if enabled for the entry).
    score += kk_ichimoku_points(b, align, s, is_long, entryNum, c);
    // 8. ATR health (0-1).
    if (s.atr_pctile >= c.atr_percentile_low) score += 1;
    return score;
}

// ---- RSI divergence veto. EntryHelpers.mqh:298-372. Reads M3 highs/lows + M3 RSI(14). ----
// Long  -> bearish divergence (price higher-high, RSI lower-high).
// Short -> bullish divergence (price lower-low,  RSI higher-low).
inline bool rsi_divergence_veto(const TfBundle& b, const TfBundle::Align& align, bool is_long,
                                const KenKemConfig& c) {
    if (!c.enable_rsi_div_veto) return false;
    const int j3 = align.m3 - 1;
    const int LB = c.rsi_div_lookback, half = LB / 2;
    if (half < 2 || j3 < LB || !b.m3.has_rsi) return false;
    auto H  = [&](int k){ return b.m3.bars[j3 - k].high; };
    auto L  = [&](int k){ return b.m3.bars[j3 - k].low; };
    auto RS = [&](int k){ return TfIndicators::get(b.m3.rsi, j3 - k); };

    double priceDiffPips, rsiDiff;
    if (is_long) {
        int rb = 0, ob = half;                                  // first (most recent) extreme wins ties
        for (int k = 1; k < half; ++k)      if (H(k) > H(rb)) rb = k;
        for (int k = half + 1; k < LB; ++k) if (H(k) > H(ob)) ob = k;
        priceDiffPips = (H(rb) - H(ob)) / c.pip_size;
        rsiDiff       = RS(ob) - RS(rb);
    } else {
        int rb = 0, ob = half;
        for (int k = 1; k < half; ++k)      if (L(k) < L(rb)) rb = k;
        for (int k = half + 1; k < LB; ++k) if (L(k) < L(ob)) ob = k;
        priceDiffPips = (L(ob) - L(rb)) / c.pip_size;
        rsiDiff       = RS(rb) - RS(ob);
    }
    return (priceDiffPips >= c.rsi_div_min_price_pips) && (rsiDiff >= c.rsi_div_min_rsi_diff);
}

// Combined entry-selectivity gate for E1/E2/E4 (the previously-ignored filters). true = trade allowed.
inline bool quality_filters_ok(int kind, bool is_long, const TfBundle& b, const Snapshot& s,
                               const TfBundle::Align& align, const KenKemConfig& c) {
    int min_tq      = (kind == 2) ? c.min_tq_e2 : (kind == 4) ? c.min_tq_e4 : c.min_tq_e1;
    bool use_conv   = (kind == 2) ? c.use_conviction_e2 : (kind == 4) ? c.use_conviction_e4 : c.use_conviction_e1;
    int  conv_thr   = (kind == 2) ? c.conviction_thr_e2 : (kind == 4) ? c.conviction_thr_e4 : c.conviction_thr_e1;

    // Trend-quality minimum (hard gate already folded into the score == 0 path).
    if (trend_quality_score(b, align, s, is_long, kind, c) < min_tq) return false;
    // Conviction threshold.
    if (use_conv && conviction_score(b, align, s, is_long, c) < conv_thr) return false;
    // RSI-divergence veto.
    if (rsi_divergence_veto(b, align, is_long, c)) return false;
    return true;
}

}  // namespace kk::kenkem
