// monster_backtester — headless Layer-3 tick backtest driver for KK-MasterVP-Monster. Loads the
// M3 bars (warmup + test window) + the M1/M5(/M15) HTF bars, streams a tick CSV through the
// MonsterEngine, and emits a Monster trade journal CSV.
//
// Usage:
//   monster_backtester --bars-m3 <m3.csv> --bars-m1 <m1.csv> --bars-m5 <m5.csv>
//                      [--bars-m15 <m15.csv>] --ticks <ticks.csv> --out <trades.csv>
//                      [--trade-from-ms <epoch_ms>] [--set <file>] [--symbol-btc|--symbol-xau]
//
// bars-*.csv : ts_ms,open,high,low,close,tick_count   (tools/export_bars.py)
// ticks.csv  : ts_ms,bid,ask                          (tools/export_ticks.py)
//
// Symbol specs (apply_btcusd_specs/apply_xauusd_specs) are applied BEFORE load_set so the .set
// only overrides STRATEGY params, never the broker economics.
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>
#include <cmath>
#include "kk/common/bars_csv.hpp"
#include "kk/monster/monster_config.hpp"
#include "kk/monster/tf_net.hpp"
#include "kk/monster/monster_engine.hpp"

using kk::monster::MonsterConfig;
using kk::monster::MonsterEngine;
using kk::monster::TfSeries;
using kk::monster::TradeRec;
using kk::monster::build_tf_series;
using kk::monster::kind_str;

static std::string trade_time_utc(int64_t ts_ms) {
    const std::time_t t = static_cast<std::time_t>(ts_ms / 1000);
    std::tm tmv{};
#if defined(_WIN32)
    gmtime_s(&tmv, &t);
#else
    gmtime_r(&t, &tmv);
#endif
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%04d.%02d.%02d %02d:%02d:%02d",
                  tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday,
                  tmv.tm_hour, tmv.tm_min, tmv.tm_sec);
    return std::string(buf);
}

static const char* monster_trades_header() {
    return "entryTimeUTC,dir,kind,session,entry,sl,tp2,realizedUsd,exitTag,"
           "fBrkDistAtr,fBodyPct,fSlope,fNetM1,fNetM3,fNetM5,fAtrPct,"
           "dInitVol,dInitRisk,dBanked,dFinalPnl\n";
}

static std::string monster_trades_csv(const std::vector<TradeRec>& trades) {
    std::string s = monster_trades_header();
    char buf[640];
    for (const auto& r : trades) {
        std::snprintf(buf, sizeof(buf),
            "%s,%s,%s,%d,%.3f,%.3f,%.3f,%.2f,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%.4f,%.3f,%.2f,%.2f\n",
            trade_time_utc(r.entry_ts_ms).c_str(),
            r.is_long ? "L" : "S", kind_str(r.kind), r.session,
            r.entry, r.sl, r.tp2, r.realized_usd, r.exit_tag.c_str(),
            r.f_brk_dist_atr, r.f_body_pct, r.f_slope,
            r.f_net_m1, r.f_net_m3, r.f_net_m5, r.f_atr_pct,
            r.d_init_vol, r.d_init_risk, r.d_banked, r.d_final_pnl);
        s += buf;
    }
    return s;
}

int main(int argc, char** argv) {
    std::string m3_path, m1_path, m5_path, m15_path, ticks_path,
                out_path = "tools/trades_monster.csv", set_path;
    int64_t trade_from_ms = 0;
    bool symbol_xau = false;

    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&]() { return (i + 1 < argc) ? std::string(argv[++i]) : std::string(); };
        if      (a == "--bars-m3")  m3_path  = next();
        else if (a == "--bars-m1")  m1_path  = next();
        else if (a == "--bars-m5")  m5_path  = next();
        else if (a == "--bars-m15") m15_path = next();
        else if (a == "--ticks")    ticks_path = next();
        else if (a == "--out")      out_path = next();
        else if (a == "--set")      set_path = next();
        else if (a == "--trade-from-ms") trade_from_ms = std::stoll(next());
        else if (a == "--symbol-xau") symbol_xau = true;
        else if (a == "--symbol-btc") { /* default */ }
        else { std::fprintf(stderr, "unknown arg: %s\n", a.c_str()); return 2; }
    }
    if (m3_path.empty() || m1_path.empty() || m5_path.empty() || ticks_path.empty()) {
        std::fprintf(stderr, "usage: monster_backtester --bars-m3 <f> --bars-m1 <f> --bars-m5 <f> "
                             "[--bars-m15 <f>] --ticks <f> [--out <f>] [--trade-from-ms <ms>] "
                             "[--set <f>] [--symbol-btc|--symbol-xau]\n");
        return 2;
    }

    MonsterConfig cfg;
    // specs FIRST (economics), then .set (strategy) so the .set can't override broker specs.
    if (symbol_xau) cfg.apply_xauusd_specs(); else cfg.apply_btcusd_specs();
    if (!set_path.empty()) {
        const int n = kk::monster::load_set(cfg, set_path);
        if (n < 0) { std::fprintf(stderr, "could not read .set: %s\n", set_path.c_str()); return 1; }
        std::fprintf(stderr, "[mbt] applied %d keys from %s\n", n, set_path.c_str());
    }

    const auto m3 = kk::load_bars_csv(m3_path);
    if (m3.empty()) { std::fprintf(stderr, "no M3 bars from %s\n", m3_path.c_str()); return 1; }
    const auto m1b = kk::load_bars_csv(m1_path);
    const auto m5b = kk::load_bars_csv(m5_path);
    std::vector<kk::Bar> m15b;
    if (!m15_path.empty()) m15b = kk::load_bars_csv(m15_path);
    std::fprintf(stderr, "[mbt] bars: M3=%zu M1=%zu M5=%zu M15=%zu\n",
                 m3.size(), m1b.size(), m5b.size(), m15b.size());

    TfSeries m1 = build_tf_series(m1b, cfg.atr_len, 60);
    TfSeries m5 = build_tf_series(m5b, cfg.atr_len, 300);
    TfSeries m15;
    if (!m15b.empty()) m15 = build_tf_series(m15b, cfg.atr_len, 900);

    MonsterEngine eng(cfg);
    eng.load(m3, std::move(m1), std::move(m5), std::move(m15), trade_from_ms);

    std::FILE* fi = std::fopen(ticks_path.c_str(), "rb");
    if (!fi) { std::fprintf(stderr, "could not open ticks: %s\n", ticks_path.c_str()); return 1; }
    char line[256];
    bool first = true;
    int64_t n_ticks = 0;
    kk::Tick last{};
    while (std::fgets(line, sizeof(line), fi)) {
        if (first) { first = false; if (line[0] < '0' || line[0] > '9') continue; }  // skip header
        kk::Tick t;
        if (std::sscanf(line, "%lld,%lf,%lf", (long long*)&t.ts_ms, &t.bid, &t.ask) != 3) continue;
        eng.on_tick(t);
        last = t;
        ++n_ticks;
    }
    std::fclose(fi);
    if (n_ticks > 0) eng.finish(last.bid, last.ask, last.ts_ms);

    const auto& trades = eng.trades();
    const std::string csv = monster_trades_csv(trades);
    std::FILE* fo = std::fopen(out_path.c_str(), "wb");
    if (!fo) { std::fprintf(stderr, "could not open out: %s\n", out_path.c_str()); return 1; }
    std::fwrite(csv.data(), 1, csv.size(), fo);
    std::fclose(fo);

    // profit factor (gross win / gross loss) for the summary line.
    double gw = 0.0, gl = 0.0;
    for (const auto& r : trades) { if (r.realized_usd >= 0.0) gw += r.realized_usd; else gl += -r.realized_usd; }
    const double pf = (gl > 0.0) ? gw / gl : (gw > 0.0 ? 1e9 : 0.0);

    std::fprintf(stderr,
        "[mbt] bars(M3)=%zu ticks=%lld trades=%zu final_balance=%.2f peak=%.2f raw_signals=%d PF=%.3f -> %s\n",
        m3.size(), (long long)n_ticks, trades.size(),
        eng.balance(), eng.peak_equity(), eng.raw_signals(), pf, out_path.c_str());
    return 0;
}
