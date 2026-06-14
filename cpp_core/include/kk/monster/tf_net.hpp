// KK-MasterVP-Monster — multi-TF near-price net tick volume, faithful port of the EA's
// Core/NetVolume.mqh (TfNetNearAt / NetLastClosedShift / NetPrevAtTime / M1FlushAgainst).
//
// Pine request.security(tf, "f_tfNetPrev()", lookahead_off) on a confirmed chart bar returns the
// expression at the LAST CLOSED tf-bar at/before the chart close, and f_tfNetPrev is itself a [1]
// read — so the net is evaluated ONE tf-bar BEFORE that. Both steps are reproduced exactly. An
// off-by-one here silently poisons every net gate.
//
// In MQL the per-TF series is read via CopyRates with `shift` counting bars-ago from the newest.
// Here a TfSeries holds the bars oldest->newest (ts_ms = bar OPEN time) + a per-bar MT5-iATR(14);
// `shift` maps to array index N-1-shift. ATR uses MT5's iATR seeding (SMA seed then Wilder RMA).
#pragma once
#include "kk/common/types.hpp"
#include <vector>
#include <cmath>
#include <algorithm>

namespace kk::monster {

struct TfSeries {
    std::vector<kk::Bar> bars;   // oldest -> newest; ts_ms = bar open time (ms, UTC)
    std::vector<double>  atr;    // MT5 iATR(atr_len) at each bar (atr[i] uses bars[..i])
    int64_t tf_ms = 0;           // bar period in milliseconds

    int size() const { return (int)bars.size(); }
    // Array index for a shift (bars-ago from newest). shift 0 = newest. -1 if out of range.
    int idx_for_shift(int shift) const {
        int n = size(); int i = n - 1 - shift;
        return (i >= 0 && i < n) ? i : -1;
    }
};

// Build a TfSeries (compute MT5-iATR(atr_len) per bar). tf_seconds: M1=60, M5=300, M15=900.
inline TfSeries build_tf_series(std::vector<kk::Bar> bars, int atr_len, int tf_seconds) {
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
// the reference bar itself can't be read (MQL analog of request.security -> na). ATR<=0 -> 0 net but
// still valid (Pine: na/0 ATR -> zero net). Partial window when history is short.
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
// s0 = bar containing (T-1ms); barClose = open(s0) + tf; last-closed = (barClose<=T) ? s0 : s0+1.
inline int net_last_closed_shift(const TfSeries& s, int64_t decisionT_ms) {
    int n = s.size();
    if (n == 0) return -1;
    int64_t t = decisionT_ms - 1;
    // largest array index with open_time <= t
    int refIdx = -1;
    // bars are ascending in ts_ms; binary search
    int lo = 0, hi = n - 1;
    while (lo <= hi) {
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
// BEFORE the last closed tf bar (the [1] read).
inline double net_prev_at_time(const TfSeries& s, int64_t decisionT_ms, int look, double win_atr,
                               double mintick, bool& valid) {
    valid = false;
    int sClosed = net_last_closed_shift(s, decisionT_ms);
    if (sClosed < 0) return 0.0;
    return tf_net_near_at(s, sClosed + 1, look, win_atr, mintick, valid);
}

// M1 flush streak (M1FlushAgainst): true when M1 net has been at/over `thr` AGAINST `positionIsLong`
// for >= `need` consecutive completed M1 bars (counted M1-natively at sClosed+1+k). Unreadable bar
// breaks the streak.
inline bool m1_flush_against(const TfSeries& m1, bool positionIsLong, int64_t decisionT_ms,
                             double thr, int need, int look, double win_atr, double mintick) {
    if (need <= 0) return false;
    int sClosed = net_last_closed_shift(m1, decisionT_ms);
    if (sClosed < 0) return false;
    for (int k = 0; k < need; k++) {
        bool ok = false;
        double v = tf_net_near_at(m1, sClosed + 1 + k, look, win_atr, mintick, ok);
        if (!ok) return false;
        if (positionIsLong && !(v <= -thr)) return false;
        if (!positionIsLong && !(v >= thr)) return false;
    }
    return true;
}

}  // namespace kk::monster
