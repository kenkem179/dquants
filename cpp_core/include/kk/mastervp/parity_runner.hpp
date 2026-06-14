// Per-bar parity surface assembler. Drives the full front-half computation layer (VP +
// regime + indicators + node engine + DetectSignal) over a sequence of bid M3 bars and
// produces one ParityRow per bar -- byte-compatible with the MT5 ParityExport.mqh CSV
// (KK-MasterVP/Parity/ParityExport.mqh).
//
// SHIFT MAP (verified against the MQL5 source, OnTick + EntryVP.mqh + ParityExport.mqh):
// When we process bar index `i`, that bar plays MQL "shift 1" (the just-closed bar):
//   - barTimeUTC, master VP window end, regime (atr1/ema/adx/+di/-di) -> bar i (shift 1)
//   - node engine UPDATED with bar i BEFORE the signal is read (decay then add)
//   - DetectSignal signal-bar OHLC + atr2 -> bar i-1 (shift 2, InpUsePriorBarVP=false)
//   - DetectSignal entry_close + atr1     -> bar i   (shift 1)
//   - node reads: nsVah@masterCur.vah, nsVal@masterCur.val, nsPx@close[i-1] (signal close)
//   - sigValid..tp2 are the RAW DetectSignal output BEFORE quality gates / risk filters
#pragma once
#include <vector>
#include <string>
#include <cstdio>
#include <ctime>
#include "kk/common/types.hpp"
#include "kk/common/config.hpp"
#include "kk/mastervp/indicators.hpp"
#include "kk/mastervp/volume_profile.hpp"
#include "kk/mastervp/node_engine.hpp"
#include "kk/mastervp/regime.hpp"
#include "kk/mastervp/strategy.hpp"

namespace kk::parity {

struct ParityRow {
    int64_t ts_ms = 0;
    // local VP (lookback bars). NOTE: the MT5 reference leaves these ~0 -- not validated; emitted for completeness.
    double poc = 0, vah = 0, val = 0;
    // master VP (lookback*masterMult bars) -- the validated columns.
    double mpoc = 0, mvah = 0, mval = 0;
    int    trend = 0;
    double plus = 0, minus = 0, adx = 0, atr1 = 0;
    int    sigValid = 0, sigLong = 0, sigRev = 0;
    double entry = 0, sl = 0, tp1 = 0, tp2 = 0;
};

// Format ts_ms (epoch ms, UTC) as MT5 "YYYY.MM.DD HH:MM".
inline std::string fmt_bar_time(int64_t ts_ms) {
    const std::time_t t = static_cast<std::time_t>(ts_ms / 1000);
    std::tm tmv{};
#if defined(_WIN32)
    gmtime_s(&tmv, &t);
#else
    gmtime_r(&t, &tmv);
#endif
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%04d.%02d.%02d %02d:%02d",
                  tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday, tmv.tm_hour, tmv.tm_min);
    return std::string(buf);
}

// Run the per-bar parity surface over `bars` (oldest..newest). Emits a row for every bar
// at index >= master_len-1 (where the master VP window is full). Node engine is updated in
// strict bar order from the first valid master bar, exactly as the EA's OnTick does.
inline std::vector<ParityRow> run(const std::vector<Bar>& bars, const Params& p) {
    std::vector<ParityRow> out;
    const int N = static_cast<int>(bars.size());
    if (N == 0) return out;

    // Indicator arrays over the whole series (warmup converges long before the test window).
    std::vector<double> h(N), l(N), c(N);
    for (int i = 0; i < N; ++i) { h[i] = bars[i].high; l[i] = bars[i].low; c[i] = bars[i].close; }
    const auto atr   = kk::ind::atr(h, l, c, p.atr_len);
    const auto dmi   = kk::ind::dmi_adx_mt5(h, l, c, p.adx_len);   // MT5 iADX (EMA-smoothed), NOT Wilder
    const auto emaF  = kk::ind::ema(c, p.ema_fast);
    const auto emaS  = kk::ind::ema(c, p.ema_slow);

    const int master_len = p.master_len();
    const int local_len  = p.vp_lookback;

    NodeEngine node;
    node.init(p.vp_bins);

    for (int i = 0; i < N; ++i) {
        if (i < master_len - 1) continue;  // master VP window not yet full

        // master VP over [i-master_len+1 .. i] (shift-1 anchored window).
        const VPResult masterCur =
            kk::vp::compute_vp_bars(&bars[i - master_len + 1], master_len, p.vp_bins, p.va_pct);

        // Node engine: update with the just-closed bar (bar i) BEFORE reading the signal.
        node.update(masterCur, bars[i], atr[i], p);

        // local VP over [i-local_len+1 .. i] (emitted for completeness; not used by breakout).
        VPResult localCur;
        if (i >= local_len - 1)
            localCur = kk::vp::compute_vp_bars(&bars[i - local_len + 1], local_len, p.vp_bins, p.va_pct);

        const RegimeState regime =
            kk::compute_regime(atr[i], emaF[i], emaS[i], dmi.adx[i], dmi.plus_di[i], dmi.minus_di[i], p);

        ParityRow r;
        r.ts_ms = bars[i].ts_ms;
        r.poc = localCur.poc; r.vah = localCur.vah; r.val = localCur.val;
        r.mpoc = masterCur.poc; r.mvah = masterCur.vah; r.mval = masterCur.val;
        r.trend = regime.trend ? 1 : 0;
        r.plus = regime.plus; r.minus = regime.minus; r.adx = regime.adx; r.atr1 = regime.atr1;

        // DetectSignal needs a signal bar (shift 2 = bar i-1). Requires i>=1 (always true here).
        if (i >= 1) {
            SignalBar s;
            s.o = bars[i - 1].open; s.h = bars[i - 1].high; s.l = bars[i - 1].low; s.c = bars[i - 1].close;
            s.atr2 = atr[i - 1];          // ATR at shift 2
            s.atr1 = atr[i];              // ATR at shift 1
            s.entry_close = bars[i].close; // close at shift 1 (entry anchor)

            const VPResult& masterSig = masterCur;  // InpUsePriorBarVP=false -> sig VP == current
            const NodeState nsVah = node.state_at_price(masterCur.vah, p);
            const NodeState nsVal = node.state_at_price(masterCur.val, p);
            const NodeState nsPx  = node.state_at_price(s.c, p);   // signal-bar close

            const Signal sig = kk::detect_signal(p, masterCur, masterSig, localCur, regime,
                                                 s, nsVah, nsVal, nsPx, /*rr_scale=*/1.0);
            r.sigValid = sig.valid ? 1 : 0;
            r.sigLong  = sig.is_long ? 1 : 0;
            r.sigRev   = sig.is_rev ? 1 : 0;
            r.entry = sig.entry; r.sl = sig.sl; r.tp1 = sig.tp1; r.tp2 = sig.tp2;
        }
        out.push_back(r);
    }
    return out;
}

// MT5-compatible CSV (same column order + DoubleToString rounding the exporter uses).
inline std::string to_csv(const std::vector<ParityRow>& rows) {
    std::string s = "barTimeUTC,poc,vah,val,mpoc,mvah,mval,trend,plus,minus,adx,atr1,"
                    "sigValid,sigLong,sigRev,entry,sl,tp1,tp2\n";
    char buf[512];
    for (const auto& r : rows) {
        std::snprintf(buf, sizeof(buf),
            "%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%.2f,%.2f,%.2f,%.3f,%d,%d,%d,%.3f,%.3f,%.3f,%.3f\n",
            fmt_bar_time(r.ts_ms).c_str(), r.poc, r.vah, r.val, r.mpoc, r.mvah, r.mval,
            r.trend, r.plus, r.minus, r.adx, r.atr1,
            r.sigValid, r.sigLong, r.sigRev, r.entry, r.sl, r.tp1, r.tp2);
        s += buf;
    }
    return s;
}

}  // namespace kk::parity
