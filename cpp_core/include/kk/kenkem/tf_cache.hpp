// KenKem P2 — per-timeframe indicator series + multi-TF alignment.
//
// The EA holds one iMA/iADX/iATR/iRSI/iIchimoku handle per (TF, indicator) and reads them via
// CopyBuffer(handle, buffer, shift, ...). This header precomputes the equivalent per-bar buffers for
// one timeframe (oldest->newest; array index i uses bars[..i]) and exposes shift-based reads anchored
// to a "forming bar" found by OPEN-time alignment — the byte-faithful analog of MT5's per-TF shift.
//
// Faithful-to-source choices (see research/hypotheses/kenkem-portnotes/02-indicator-cache.md):
//   - EMA periods come from cfg (10/25/71/97/192 by default — NOT the round enum labels).
//   - ADX/DI = MT5 iADX  -> kk::ind::dmi_adx_mt5 (NOT textbook Wilder).
//   - Cache ATR uses period 14 (hardcoded literal in the EA), independent of ATR_PERIOD_FOR_SL.
//   - ADX(9) "short", RSI(14), Ichimoku(9/26/52) are built only on the TFs that need them
//     (short+RSI: M1 only; Ichimoku: M1 + M3) to mirror the EA's handle set exactly.
//
// SHIFT SEMANTICS: forming_index_at(t) returns the newest bar whose OPEN time <= t (the bar that is
// "forming" at instant t). A shift-`k` read is that index minus k. So with the decision instant set to
// the forming M1 bar's open time, shift 1 = last CLOSED bar on every TF, matching ENTRY_SHIFT=1.
// Shift 0 (the forming bar itself) is intentionally NOT served from closed-bar arrays here — the
// engine models the forming bar explicitly (its shift-0 ATR/price evolve intra-bar). See P7.
#pragma once
#include "kk/common/types.hpp"
#include "kk/mastervp/indicators.hpp"   // kk::ind::ema / atr / rsi / dmi_adx_mt5
#include "kk/kenkem/indicators.hpp"     // kk::ind::ichimoku
#include "kk/kenkem/kenkem_config.hpp"
#include <vector>
#include <cstdint>

namespace kk::kenkem {

// Cache ATR period is a hardcoded 14 in KenKemExpert.mq5 (:315/321/327), distinct from the
// ATR_PERIOD_FOR_SL input used by SL arbitration. Keep it literal for parity.
inline constexpr int KENKEM_CACHE_ATR_PERIOD = 14;
inline constexpr int KENKEM_ADX_SHORT_PERIOD = 9;   // M1 ADX(9) micro-trend handle (:302)

struct TfIndicators {
    std::vector<kk::Bar> bars;       // oldest -> newest; ts_ms = bar OPEN time (ms, UTC)
    int64_t tf_ms = 0;

    std::vector<double> ema[5];      // EMA0..4 (periods from cfg)
    std::vector<double> adx, diP, diM;        // dmi_adx_mt5(adx_len)
    std::vector<double> adxS, diPS, diMS;     // dmi_adx_mt5(9), built iff has_short
    std::vector<double> atr;                  // atr(14)
    std::vector<double> rsi;                  // rsi(rsi_len), built iff has_rsi (MT5-faithful Wilder)
    std::vector<double> rsi_ag, rsi_al;       // Wilder avg-gain/avg-loss series (for forming shift-0 step)
    kk::ind::IchimokuBuf ichi;                // built iff has_ichi
    bool has_short = false, has_rsi = false, has_ichi = false;

    int size() const { return (int)bars.size(); }

    // Newest bar whose OPEN time <= t_ms (the bar "forming" at instant t). -1 if t precedes all bars.
    int forming_index_at(int64_t t_ms) const {
        int n = size(); if (n == 0) return -1;
        int lo = 0, hi = n - 1, ref = -1;
        while (lo <= hi) {
            int m = (lo + hi) / 2;
            if (bars[m].ts_ms <= t_ms) { ref = m; lo = m + 1; }
            else hi = m - 1;
        }
        return ref;
    }

    // Bounds-checked buffer read at absolute index. Returns 0.0 (MT5 "no data") when out of range.
    static double get(const std::vector<double>& v, int idx) {
        return (idx >= 0 && idx < (int)v.size()) ? v[idx] : 0.0;
    }
};

// Build one TF's indicator buffers. tf_seconds: M1=60, M3=180, M5=300, M15=900.
inline TfIndicators build_tf_indicators(std::vector<kk::Bar> bars, const KenKemConfig& cfg,
                                        int tf_seconds, bool want_short, bool want_rsi,
                                        bool want_ichi) {
    TfIndicators s;
    s.bars = std::move(bars);
    s.tf_ms = (int64_t)tf_seconds * 1000;
    const int n = s.size();
    if (n == 0) return s;

    std::vector<double> H(n), L(n), C(n);
    for (int i = 0; i < n; ++i) { H[i] = s.bars[i].high; L[i] = s.bars[i].low; C[i] = s.bars[i].close; }

    const int per[5] = { cfg.ema0_period, cfg.ema1_period, cfg.ema2_period, cfg.ema3_period, cfg.ema4_period };
    for (int e = 0; e < 5; ++e) s.ema[e] = kk::ind::ema(C, per[e]);

    const kk::ind::DMI d = kk::ind::dmi_adx_mt5(H, L, C, cfg.adx_len);
    s.adx = d.adx; s.diP = d.plus_di; s.diM = d.minus_di;

    s.atr = kk::ind::atr(H, L, C, KENKEM_CACHE_ATR_PERIOD);

    if (want_short) {
        const kk::ind::DMI d9 = kk::ind::dmi_adx_mt5(H, L, C, KENKEM_ADX_SHORT_PERIOD);
        s.adxS = d9.adx; s.diPS = d9.plus_di; s.diMS = d9.minus_di; s.has_short = true;
    }
    if (want_rsi) {
        const kk::ind::RSIWilder rw = kk::ind::rsi_wilder_mt5(C, cfg.rsi_len);
        s.rsi = rw.rsi; s.rsi_ag = rw.ag; s.rsi_al = rw.al; s.has_rsi = true;
    }
    if (want_ichi) {
        s.ichi = kk::ind::ichimoku(H, L, C, cfg.ichimoku_tenkan, cfg.ichimoku_kijun, cfg.ichimoku_senkou);
        s.has_ichi = true;
    }
    return s;
}

// The four active KenKem timeframes (TF4=H1 reserved/inactive). M1 carries short+RSI+Ichimoku;
// M3 carries Ichimoku; M5/M15 carry only EMA/ADX/ATR — exactly the EA's handle set.
struct TfBundle {
    TfIndicators m1, m3, m5, m15;

    // Decision instant = the forming M1 bar's open time. Returns each TF's forming index at that
    // instant; shift 1 on each = the last closed bar (ENTRY_SHIFT). -1 components mean "no data".
    struct Align { int m1, m3, m5, m15; };
    Align align_at(int64_t t_ms) const {
        return { m1.forming_index_at(t_ms), m3.forming_index_at(t_ms),
                 m5.forming_index_at(t_ms), m15.forming_index_at(t_ms) };
    }
};

inline TfBundle build_tf_bundle(std::vector<kk::Bar> m1, std::vector<kk::Bar> m3,
                                std::vector<kk::Bar> m5, std::vector<kk::Bar> m15,
                                const KenKemConfig& cfg) {
    TfBundle b;
    b.m1  = build_tf_indicators(std::move(m1),  cfg,  60, /*short*/true,  /*rsi*/true,  /*ichi*/true);
    // M3 carries RSI too: the conviction RSI-momentum component and the RSI-divergence veto both read
    // M3 RSI(14). The EA builds rsiHandlesTF[1]=iRSI(_Symbol,M3,14) (KenKemExpert.mq5:785).
    b.m3  = build_tf_indicators(std::move(m3),  cfg, 180, false, /*rsi*/true, /*ichi*/true);
    b.m5  = build_tf_indicators(std::move(m5),  cfg, 300, false, false, false);
    b.m15 = build_tf_indicators(std::move(m15), cfg, 900, false, false, false);
    return b;
}

}  // namespace kk::kenkem
