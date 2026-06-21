// Signal-journal CSV writer — the PRE-GATE counterpart to trade_journal.hpp.
//
// Emits one row per RAW DetectSignal (every valid signal the strategy arms, BEFORE the
// deterministic/quality/safety gates and one-position limiter remove most of them). This is
// the keystone of the "edge autopsy" middle layer: with the raw signal stream + its
// conditioning features, Python can measure the signal's conditional expectancy / IC, slice
// it by regime/session/ATR-percentile, gauge the cost margin (risk vs spread), and compare
// the signal set against the executed trades_*.csv to see whether the gates actually remove
// negative-expectancy signals (gate ablation / the selectivity funnel).
//
// Forward returns are intentionally NOT computed here — Python joins them from the bars on
// `tsMs`, keeping the engine change tiny and lookahead-free on the C++ side.
//
// tsMs/timeUTC anchor the DECISION bar (its close is the entry anchor `entry`); a realistic
// forward-return measure starts from the NEXT bar's open. Collection is opt-in
// (set_collect_signals) so default backtests carry zero overhead and stay byte-identical.
#pragma once
#include <string>
#include <vector>
#include <cstdio>
#include <cstdint>
#include "kk/common/trade_journal.hpp"   // reuse trade_time_utc()

namespace kk {

struct SignalRecord {
    int64_t ts_ms = 0;            // decision-bar timestamp (entry anchor = its close)
    bool    is_long = false;
    bool    is_rev = false, is_impulse = false, is_extreme_rev = false;
    const char* reason = "";
    double  entry = 0.0, sl = 0.0, risk = 0.0;
    // conditioning features carried straight off the Signal (no trading effect)
    double  brk_dist_atr = 0.0, body_pct = 0.0, adx = 0.0, di_spread = 0.0;
    double  runway_atr = 0.0, node_net = 0.0;
    double  atr = 0.0, close = 0.0;     // bar context for normalisation
    bool    regime_trend = false;
};

inline const char* signals_csv_header() {
    return "tsMs,timeUTC,dir,kind,isRev,isImpulse,isXRev,entry,sl,risk,"
           "brkDistAtr,bodyPct,adx,diSpread,runwayAtr,nodeNet,atr,close,regimeTrend\n";
}

inline std::string to_signals_csv(const std::vector<SignalRecord>& sigs) {
    std::string s = signals_csv_header();
    char buf[512];
    for (const auto& r : sigs) {
        std::snprintf(buf, sizeof(buf),
            "%lld,%s,%s,%s,%d,%d,%d,%.3f,%.3f,%.3f,%.2f,%.2f,%.1f,%.1f,%.2f,%.2f,%.5f,%.3f,%d\n",
            (long long)r.ts_ms, trade_time_utc(r.ts_ms).c_str(),
            r.is_long ? "L" : "S", r.reason,
            r.is_rev ? 1 : 0, r.is_impulse ? 1 : 0, r.is_extreme_rev ? 1 : 0,
            r.entry, r.sl, r.risk,
            r.brk_dist_atr, r.body_pct, r.adx, r.di_spread, r.runway_atr, r.node_net,
            r.atr, r.close, r.regime_trend ? 1 : 0);
        s += buf;
    }
    return s;
}

}  // namespace kk
