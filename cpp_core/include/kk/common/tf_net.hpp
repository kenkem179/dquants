// Multi-TF near-price net tick volume — salvaged from the (now-deprecated) kk::monster fork's
// tf_net.hpp; the only piece of that fork reused by the minimal Monster build. Faithful port of the
// EA's Core/NetVolume.mqh (TfNetNearAt / NetLastClosedShift / NetPrevAtTime).
//
// Net uses per-bar tick_count (== MT5 tick_volume), NOT broker real volume (which is ~0 on the
// Exness/MT5 feed). This is the parity-critical detail: the old Monster MQL5 keyed off real VOLUME
// and made ZERO trades while the engine traded — the EA port MUST read iVolume(...,VOLUME_TICK).
//
// Pine request.security(tf, "f_tfNetPrev()", lookahead_off) on a confirmed chart bar returns the
// expression at the LAST CLOSED tf-bar at/before the chart close, and f_tfNetPrev is itself a [1]
// read — so the net is evaluated ONE tf-bar BEFORE that. Both steps are reproduced exactly.
#pragma once
#include "kk/common/types.hpp"
#include <vector>
#include <cmath>
#include <algorithm>

namespace kk {

struct TfSeries {
    std::vector<Bar>    bars;   // oldest -> newest; ts_ms = bar open time (ms, UTC)
    std::vector<double> atr;    // MT5 iATR(atr_len) at each bar (atr[i] uses bars[..i])
    int64_t tf_ms = 0;          // bar period in milliseconds

    int size() const { return (int)bars.size(); }
    // Array index for a shift (bars-ago from newest). shift 0 = newest. -1 if out of range.
    int idx_for_shift(int shift) const {
        int n = size(); int i = n - 1 - shift;
        return (i >= 0 && i < n) ? i : -1;
    }
};

// Build a TfSeries (compute MT5-iATR(atr_len) per bar). tf_seconds: M1=60, M5=300, M15=900.
inline TfSeries build_tf_series(std::vector<Bar> bars, int atr_len, int tf_seconds) {
    TfSeries s;
    s.bars = std::move(bars);
    s.tf_ms = (int64_t)tf_seconds * 1000;
    int n = s.size();
    s.atr.assign(n, 0.0);
    if (n == 0 || atr_len < 1) return s;
    std::vector<double> tr(n, 0.0);
    for (int i = 0; i < n; i++) {
        double h = s.bars[i].high, l = s.bars[i].low;
        if (i == 0) { tr[i] = h - l; }
        else {
            double pc = s.bars[i - 1].close;
            tr[i] = std::max(h - l, std::max(std::fabs(h - pc), std::fabs(l - pc)));
        }
    }
    // MT5 iATR: ATR[atr_len-1] = SMA of TR[0..atr_len-1]; then Wilder RMA.
    if (n < atr_len) return s;   // not enough history -> all 0 (treated as unavailable)
    double seed = 0.0;
    for (int i = 0; i < atr_len; i++) seed += tr[i];
    seed /= atr_len;
    s.atr[atr_len - 1] = seed;
    for (int i = atr_len; i < n; i++)
        s.atr[i] = (s.atr[i - 1] * (atr_len - 1) + tr[i]) / atr_len;
    return s;
}

// TfNetNearAt: net buy/sell direction-proxy volume of the `look` bars ENDING at `shift`, restricted
// to bars whose hlc3 sits within win_atr x ATR(tf,shift) of that bar's close. valid=false only when
// the reference bar itself can't be read. ATR<=0 -> 0 net but still valid. Partial window if short.
inline double tf_net_near_at(const TfSeries& s, int shift, int look, double win_atr,
                             double mintick, bool& valid) {
    valid = false;
    if (shift < 0) return 0.0;
    int refIdx = s.idx_for_shift(shift);
    if (refIdx < 0) return 0.0;
    double px = s.bars[refIdx].close;
    if (px <= 0.0) return 0.0;
    valid = true;
    double a = s.atr[refIdx];
    if (a <= 0.0) return 0.0;
    double win = win_atr * a;
    int start = std::max(0, refIdx - look + 1);   // `look` bars ending at refIdx (partial if short)
    double tB = 0.0, tS = 0.0;
    for (int i = start; i <= refIdx; i++) {
        double hi = s.bars[i].high, lo = s.bars[i].low, op = s.bars[i].open, cl = s.bars[i].close;
        if (cl <= 0.0 || hi < lo) continue;
        double rng = std::max(hi - lo, mintick);
        double dp = (cl - op) / rng;
        double p = (hi + lo + cl) / 3.0;
        if (std::fabs(p - px) <= win) {
            double v = s.bars[i].tick_count > 0 ? (double)s.bars[i].tick_count : 0.0;
            tB += v * std::max(dp, 0.0);
            tS += v * std::max(-dp, 0.0);
        }
    }
    double tot = tB + tS;
    return (tot > 0.0) ? (tB - tS) / tot : 0.0;
}

// Shift of the LAST CLOSED bar of the series at decision time T (ms) — NetLastClosedShift.
inline int net_last_closed_shift(const TfSeries& s, int64_t decisionT_ms) {
    int n = s.size();
    if (n == 0) return -1;
    int64_t t = decisionT_ms - 1;
    int refIdx = -1, lo = 0, hi = n - 1;
    while (lo <= hi) {                          // largest index with open_time <= t
        int mid = (lo + hi) / 2;
        if (s.bars[mid].ts_ms <= t) { refIdx = mid; lo = mid + 1; }
        else hi = mid - 1;
    }
    if (refIdx < 0) return -1;
    int s0 = n - 1 - refIdx;
    int64_t barClose = s.bars[refIdx].ts_ms + s.tf_ms;
    return (barClose <= decisionT_ms) ? s0 : s0 + 1;
}

// Pine request.security(tf, f_tfNetPrev()) at the confirmed chart bar: net evaluated ONE tf-bar
// BEFORE the last closed tf bar (the [1] read). decisionT_ms = the entry-bar open (== signal close).
inline double net_prev_at_time(const TfSeries& s, int64_t decisionT_ms, int look, double win_atr,
                               double mintick, bool& valid) {
    valid = false;
    int sClosed = net_last_closed_shift(s, decisionT_ms);
    if (sClosed < 0) return 0.0;
    return tf_net_near_at(s, sClosed + 1, look, win_atr, mintick, valid);
}

}  // namespace kk
