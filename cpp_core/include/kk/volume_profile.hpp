// Volume profile — exact port of KK-MasterVP/Core/VolumeProfile.mqh.
//   BuildVAFromHist: POC = max-volume bin; value area grown from POC outward, taking the
//   heavier neighbour, ties -> HIGH side, until vaPct% of total enclosed.
//   ComputeVP_Bar (Stage A): each bar drops its whole tick_count into the bin of its hlc3.
#pragma once
#include <vector>
#include <cmath>
#include "kk/types.hpp"

namespace kk::vp {

inline int clamp_i(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

// Mirrors BuildVAFromHist (VolumeProfile.mqh:15). lo/step define the bin grid.
inline VPResult build_va_from_hist(const std::vector<double>& hist, double lo, double step,
                                   double vaPct) {
    VPResult res;
    const int bins = static_cast<int>(hist.size());
    if (bins == 0) return res;

    double total = 0.0, pocVol = -1.0;
    int pocIdx = 0;
    for (int b = 0; b < bins; ++b) {
        total += hist[b];
        if (hist[b] > pocVol) { pocVol = hist[b]; pocIdx = b; }
    }
    const double target = total * (vaPct * 0.01);
    double acc = hist[pocIdx];
    int loIdx = pocIdx, hiIdx = pocIdx;
    while (acc < target && (loIdx > 0 || hiIdx < bins - 1)) {
        const double nextL = (loIdx > 0)        ? hist[loIdx - 1] : -1.0;
        const double nextH = (hiIdx < bins - 1) ? hist[hiIdx + 1] : -1.0;
        if (nextH >= nextL) { hiIdx += 1; acc += hist[hiIdx]; }   // ties -> high
        else                { loIdx -= 1; acc += hist[loIdx]; }
    }
    res.poc = lo + (pocIdx + 0.5) * step;
    res.vah = lo + (hiIdx + 1.0) * step;
    res.val = lo + loIdx * step;
    res.lo = lo;
    res.hi = lo + bins * step;
    res.valid = true;
    return res;
}

// Stage-A bar-feed VP over bars[start, start+len). Mirrors ComputeVP_Bar (VolumeProfile.mqh:42).
inline VPResult compute_vp_bars(const Bar* bars, int len, int bins, double vaPct) {
    VPResult res;
    if (len <= 0 || bins <= 0) return res;
    double lo = bars[0].low, hi = bars[0].high;
    for (int i = 1; i < len; ++i) {
        if (bars[i].low  < lo) lo = bars[i].low;
        if (bars[i].high > hi) hi = bars[i].high;
    }
    const double step = (hi - lo) / bins;
    if (step <= 0.0) { res.hi = hi; res.lo = lo; return res; }  // valid stays false

    std::vector<double> hist(bins, 0.0);
    for (int i = 0; i < len; ++i) {
        const double p = (bars[i].high + bars[i].low + bars[i].close) / 3.0;  // hlc3
        const int bi = clamp_i(static_cast<int>(std::floor((p - lo) / step)), 0, bins - 1);
        hist[bi] += static_cast<double>(bars[i].tick_count);
    }
    res = build_va_from_hist(hist, lo, step, vaPct);
    res.hi = hi;
    res.lo = lo;
    return res;
}

}  // namespace kk::vp
