// Trade-journal CSV writer — byte-compatible with MT5 Parity/TradeJournal.mqh output
// (MQL5/Files/KK-MasterVP/trades_<sym>_<tf>.csv). Emits one row per closed TradeRecord so
// the C++ trade stream can be diffed directly against the MT5 tester reference.
//
// Column order + per-field rounding match TradeJournal.mqh FileWrite exactly:
//   entryTimeUTC,dir,rev,retest,regimeTrend,session,entry,riskPrice,mfeR,maeR,realizedUsd,
//   entryReason,brkDistAtr,bodyPct,adx,diSpread,runwayAtr,nodeNet,spreadPips,spreadAtr,exitTag
// retest is always 0 in the v1 parity config (InpUseRetestFill=false).
#pragma once
#include <string>
#include <vector>
#include <cstdio>
#include <ctime>
#include "kk/position_manager.hpp"

namespace kk {

// "YYYY.MM.DD HH:MM" in UTC, matching MT5 TimeToString(TIME_DATE|TIME_MINUTES) on a UTC time.
inline std::string trade_time_utc(int64_t ts_ms) {
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

inline const char* trades_csv_header() {
    return "entryTimeUTC,dir,rev,retest,regimeTrend,session,entry,riskPrice,mfeR,maeR,"
           "realizedUsd,entryReason,brkDistAtr,bodyPct,adx,diSpread,runwayAtr,nodeNet,"
           "spreadPips,spreadAtr,exitTag\n";
}

inline std::string to_trades_csv(const std::vector<TradeRecord>& trades) {
    std::string s = trades_csv_header();
    char buf[512];
    for (const auto& r : trades) {
        std::snprintf(buf, sizeof(buf),
            "%s,%s,%d,%d,%d,%d,%.3f,%.3f,%.2f,%.2f,%.2f,%s,%.2f,%.2f,%.1f,%.1f,%.2f,%.2f,%.1f,%.3f,%s\n",
            trade_time_utc(r.entry_ts_ms).c_str(),
            r.is_long ? "L" : "S", r.is_rev ? 1 : 0, /*retest=*/0, r.regime_trend ? 1 : 0, r.session,
            r.entry, r.risk_price, r.mfe_r, r.mae_r, r.realized_usd, r.reason,
            r.brk_dist_atr, r.body_pct, r.adx, r.di_spread, r.runway_atr, r.node_net,
            r.spread_pips, r.spread_atr, exit_tag_str(r.exit_tag));
        s += buf;
    }
    return s;
}

}  // namespace kk
