// KenKem-specific indicators that aren't already in kk::ind (EMA/ADX/DI/ATR/RSI live there).
// The only new primitive is Ichimoku — used by E4 (cloud-cross trigger) and the trend-quality
// cloud component. Computed to match MT5's iIchimoku buffer semantics so it parity-checks against
// the EA's cache.ichimoku* fields.
//
// Buffers (arrays oldest->newest, index i uses bars[..i]):
//   tenkan[i]   = (HH + LL)/2 over `tenkan` bars ending at i        (MT5 TENKANSEN_LINE)
//   kijun[i]    = (HH + LL)/2 over `kijun`  bars ending at i        (MT5 KIJUNSEN_LINE)
//   spanA_fut[i]= (tenkan[i] + kijun[i]) / 2                        (Span A *before* the +kijun plot shift)
//   spanB_fut[i]= (HH + LL)/2 over `senkouB` bars ending at i       (Span B before the plot shift)
// The Senkou spans are plotted `kijun` bars into the FUTURE, so the cloud overlapping bar i (what the
// EA reads as "current") is the span computed `kijun` bars earlier:
//   spanA_cur[i]= spanA_fut[i - kijun]      spanB_cur[i]= spanB_fut[i - kijun]
// MT5 CopyBuffer shift semantics then map to:
//   cache.ichimokuSpanA_*_Current = spanA_cur[idx(shift=1)]   (= CopyBuffer(SPANA, +1))
//   cache.ichimokuSpanA_*_Future  = spanA_fut[idx(shift=1)]   (= CopyBuffer(SPANA, -kijun))
//   cache.ichimokuTenkan_*        = tenkan[idx(shift=1)]      cache.ichimokuChikou_* = close[idx(shift=1)]
#pragma once
#include <vector>
#include <cmath>
#include <algorithm>

namespace kk::ind {

using std::vector;

struct IchimokuBuf {
    vector<double> tenkan, kijun, span_a_fut, span_b_fut, span_a_cur, span_b_cur;
    bool valid_at(int i) const {                 // cloud "current" needs i-kijun back-history
        return i >= 0 && i < (int)span_a_cur.size() && span_a_cur[i] != 0.0;
    }
};

// Highest-high / lowest-low midpoint over `period` bars ending at i (i.e. bars [i-period+1 .. i]).
inline double donchian_mid(const vector<double>& h, const vector<double>& l, int i, int period) {
    int start = i - period + 1;
    double hh = h[i], ll = l[i];
    for (int k = start; k < i; ++k) { hh = std::max(hh, h[k]); ll = std::min(ll, l[k]); }
    return 0.5 * (hh + ll);
}

inline IchimokuBuf ichimoku(const vector<double>& h, const vector<double>& l,
                            const vector<double>& c, int tenkan, int kijun, int senkou_b) {
    const int N = (int)h.size();
    IchimokuBuf b;
    b.tenkan.assign(N, 0.0); b.kijun.assign(N, 0.0);
    b.span_a_fut.assign(N, 0.0); b.span_b_fut.assign(N, 0.0);
    b.span_a_cur.assign(N, 0.0); b.span_b_cur.assign(N, 0.0);
    for (int i = 0; i < N; ++i) {
        if (i >= tenkan - 1)   b.tenkan[i] = donchian_mid(h, l, i, tenkan);
        if (i >= kijun - 1)    b.kijun[i]  = donchian_mid(h, l, i, kijun);
        if (i >= senkou_b - 1) b.span_b_fut[i] = donchian_mid(h, l, i, senkou_b);
        if (i >= kijun - 1)    b.span_a_fut[i] = 0.5 * (b.tenkan[i] + b.kijun[i]);
    }
    for (int i = 0; i < N; ++i) {
        int j = i - kijun;                       // span plotted +kijun ahead -> cloud at i is span from j
        if (j >= 0) { b.span_a_cur[i] = b.span_a_fut[j]; b.span_b_cur[i] = b.span_b_fut[j]; }
        (void)c;
    }
    return b;
}

}  // namespace kk::ind
