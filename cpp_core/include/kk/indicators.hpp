// Causal indicators — C++ port matching pipeline/indicators.py (which matches MT5/Wilder).
// EMA: adjust=False recursion. RSI/ATR/ADX: Wilder RMA (alpha=1/n). Warmup is discarded
// downstream, so the ewm-vs-SMA seed difference vs MT5's iATR/iADX is immaterial post-warmup
// (tracked as a parity risk in research/hypotheses/KK-MasterVP-SPEC.md §9).
#pragma once
#include <vector>
#include <cmath>
#include <algorithm>

namespace kk::ind {

using std::vector;

inline vector<double> ema(const vector<double>& x, int n) {
    vector<double> o(x.size());
    if (x.empty()) return o;
    const double a = 2.0 / (n + 1.0);
    o[0] = x[0];
    for (size_t i = 1; i < x.size(); ++i) o[i] = a * x[i] + (1.0 - a) * o[i - 1];
    return o;
}

// Wilder running moving average (RMA / SMMA): alpha = 1/n.
inline vector<double> wilder_rma(const vector<double>& x, int n) {
    vector<double> o(x.size());
    if (x.empty()) return o;
    const double a = 1.0 / n;
    o[0] = x[0];
    for (size_t i = 1; i < x.size(); ++i) o[i] = a * x[i] + (1.0 - a) * o[i - 1];
    return o;
}

inline vector<double> true_range(const vector<double>& h, const vector<double>& l,
                                 const vector<double>& c) {
    const size_t N = h.size();
    vector<double> tr(N);
    if (N == 0) return tr;
    tr[0] = h[0] - l[0];
    for (size_t i = 1; i < N; ++i) {
        const double pc = c[i - 1];
        tr[i] = std::max({h[i] - l[i], std::fabs(h[i] - pc), std::fabs(l[i] - pc)});
    }
    return tr;
}

inline vector<double> atr(const vector<double>& h, const vector<double>& l,
                          const vector<double>& c, int n) {
    return wilder_rma(true_range(h, l, c), n);
}

inline vector<double> rsi(const vector<double>& c, int n) {
    const size_t N = c.size();
    vector<double> gain(N, 0.0), loss(N, 0.0);
    for (size_t i = 1; i < N; ++i) {
        const double d = c[i] - c[i - 1];
        gain[i] = d > 0 ? d : 0.0;
        loss[i] = d < 0 ? -d : 0.0;
    }
    const vector<double> ag = wilder_rma(gain, n);
    const vector<double> al = wilder_rma(loss, n);
    vector<double> out(N, 50.0);
    for (size_t i = 0; i < N; ++i) {
        if (al[i] == 0.0 && ag[i] == 0.0) out[i] = 50.0;
        else if (al[i] == 0.0)            out[i] = 100.0;
        else {
            const double rs = ag[i] / al[i];
            out[i] = 100.0 - 100.0 / (1.0 + rs);
        }
    }
    return out;
}

// Returns adx, +di, -di (all Wilder-smoothed, [0,100]).
struct DMI { vector<double> adx, plus_di, minus_di; };

inline DMI dmi_adx(const vector<double>& h, const vector<double>& l,
                   const vector<double>& c, int n) {
    const size_t N = h.size();
    vector<double> plus_dm(N, 0.0), minus_dm(N, 0.0);
    for (size_t i = 1; i < N; ++i) {
        const double up = h[i] - h[i - 1];
        const double dn = l[i - 1] - l[i];
        plus_dm[i]  = (up > dn && up > 0) ? up : 0.0;
        minus_dm[i] = (dn > up && dn > 0) ? dn : 0.0;
    }
    const vector<double> atr_n = wilder_rma(true_range(h, l, c), n);
    const vector<double> pdm = wilder_rma(plus_dm, n);
    const vector<double> mdm = wilder_rma(minus_dm, n);
    DMI r;
    r.plus_di.resize(N); r.minus_di.resize(N);
    vector<double> dx(N, 0.0);
    for (size_t i = 0; i < N; ++i) {
        const double a = atr_n[i] > 0 ? atr_n[i] : 1e-12;
        r.plus_di[i]  = 100.0 * pdm[i] / a;
        r.minus_di[i] = 100.0 * mdm[i] / a;
        const double s = r.plus_di[i] + r.minus_di[i];
        dx[i] = s > 0 ? 100.0 * std::fabs(r.plus_di[i] - r.minus_di[i]) / s : 0.0;
    }
    r.adx = wilder_rma(dx, n);
    return r;
}

}  // namespace kk::ind
