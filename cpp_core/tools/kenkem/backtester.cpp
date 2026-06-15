// kenkem_backtester — headless Layer-3 backtest for the distilled KenKem engine.
//
// Loads M1 BID bars (ts_ms,open,high,low,close,tick_count), aggregates M3/M5/M15 in-process (so the
// TFs are always aligned to the same data), applies a fixed spread cost, runs the bar-replay engine,
// and prints net / PF / trades / win-rate / maxDD. Optionally writes a trades CSV.
//
// Usage:
//   kenkem_backtester --bars-m1 <m1.csv> [--symbol-btc|--symbol-xau] [--spread <price>]
//                     [--set <file>] [--from-ms <e>] [--to-ms <e>] [--warmup <bars>] [--out <trades.csv>]
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>
#include <ctime>
#include "kk/common/bars_csv.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include "kk/kenkem/engine.hpp"

using namespace kk::kenkem;

// Aggregate M1 bars into a higher TF by flooring ts_ms to tf-minute buckets.
static std::vector<kk::Bar> aggregate(const std::vector<kk::Bar>& m1, int tf_minutes) {
    const int64_t w = (int64_t)tf_minutes * 60000;
    std::vector<kk::Bar> out;
    for (const kk::Bar& b : m1) {
        int64_t bucket = (b.ts_ms / w) * w;
        if (out.empty() || out.back().ts_ms != bucket) {
            kk::Bar nb = b; nb.ts_ms = bucket; out.push_back(nb);
        } else {
            kk::Bar& cur = out.back();
            if (b.high > cur.high) cur.high = b.high;
            if (b.low  < cur.low)  cur.low  = b.low;
            cur.close = b.close;
            cur.tick_count += b.tick_count;
        }
    }
    return out;
}

static std::string utc(int64_t ts_ms) {
    std::time_t t = (std::time_t)(ts_ms / 1000); std::tm tmv{};
#if defined(_WIN32)
    gmtime_s(&tmv, &t);
#else
    gmtime_r(&t, &tmv);
#endif
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%04d.%02d.%02d %02d:%02d", tmv.tm_year+1900, tmv.tm_mon+1, tmv.tm_mday, tmv.tm_hour, tmv.tm_min);
    return buf;
}

int main(int argc, char** argv) {
    std::string m1_path, set_path, out_path;
    bool xau = false;
    double spread = -1.0;            // -1 => symbol default
    int warmup = 250;
    int64_t from_ms = 0, to_ms = 0;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]{ return (i+1 < argc) ? std::string(argv[++i]) : std::string(); };
        if      (a == "--bars-m1")    m1_path = next();
        else if (a == "--set")        set_path = next();
        else if (a == "--out")        out_path = next();
        else if (a == "--symbol-xau") xau = true;
        else if (a == "--symbol-btc") xau = false;
        else if (a == "--spread")     spread = std::stod(next());
        else if (a == "--warmup")     warmup = std::stoi(next());
        else if (a == "--from-ms")    from_ms = std::stoll(next());
        else if (a == "--to-ms")      to_ms = std::stoll(next());
    }
    if (m1_path.empty()) { std::fprintf(stderr, "need --bars-m1\n"); return 2; }

    KenKemConfig cfg;
    if (xau) cfg.apply_xauusd_specs(); else cfg.apply_btcusd_specs();
    if (spread < 0) spread = xau ? 0.05 : 2.0;     // sensible default spread (price units)
    if (!set_path.empty()) {
        int n = load_set(cfg, set_path);
        std::fprintf(stderr, "[set] applied %d keys from %s\n", n, set_path.c_str());
    }

    std::vector<kk::Bar> m1 = kk::load_bars_csv(m1_path, from_ms, to_ms);
    if (m1.empty()) { std::fprintf(stderr, "no M1 bars loaded from %s\n", m1_path.c_str()); return 1; }
    for (kk::Bar& b : m1) b.spread_mean = spread;

    std::vector<kk::Bar> m3 = aggregate(m1, 3), m5 = aggregate(m1, 5), m15 = aggregate(m1, 15);
    TfBundle bundle = build_tf_bundle(m1, m3, m5, m15, cfg);

    BtResult R = run_backtest(bundle, cfg, warmup, from_ms, to_ms);

    // The bar engine's synthetic 4-point OHLC walk mis-resolves path-dependent exits and SL-vs-TP
    // ordering; it DISAGREES WITH MT5 on the sign of P&L (measured: bar PF 0.89 vs tick PF 1.12 on the
    // same KenKem config/window; tick win% matched the MT5 ground truth, bar did not). Use the tick
    // backtester for any MT5-faithful conclusion. This path is for fast research signal-shape checks only.
    std::fprintf(stderr,
        "\n  !!! BAR ENGINE — NOT MT5-FAITHFUL. Validate on kenkem_tick_backtester (real bid/ask). !!!\n\n");

    std::printf("=== KenKem BAR-engine backtest [research-only, NOT MT5-faithful] (%s) ===\n", xau ? "XAUUSD" : "BTCUSD");
    std::printf("M1 bars: %d   spread: %.3f   warmup: %d\n", (int)m1.size(), spread, warmup);
    std::printf("trades:   %d  (wins %d, win%% %.1f)\n", R.trades, R.wins, 100.0 * R.win_rate);
    std::printf("net:      %.2f USD   (end balance %.2f)\n", R.net, R.end_balance);
    std::printf("PF:       %.3f\n", R.pf);
    std::printf("max DD:   %.2f USD\n", R.max_dd);
    // by-entry breakdown
    int ce[6] = {0,0,0,0,0,0}; double pe[6] = {0,0,0,0,0,0};
    for (const Trade& t : R.list) { if (t.kind>=1 && t.kind<=5) { ce[t.kind]++; pe[t.kind]+=t.pnl; } }
    std::printf("by entry: E1 %d (%.0f)  E2 %d (%.0f)  E4 %d (%.0f)  E5 %d (%.0f)\n",
                ce[1],pe[1], ce[2],pe[2], ce[4],pe[4], ce[5],pe[5]);

    if (!out_path.empty()) {
        FILE* f = std::fopen(out_path.c_str(), "w");
        if (f) {
            std::fprintf(f, "ts_ms,entryTimeUTC,dir,kind,entry,lot,pnlUsd\n");
            for (const Trade& t : R.list)
                std::fprintf(f, "%lld,%s,%s,E%d,%.3f,%.2f,%.2f\n", (long long)t.t_in, utc(t.t_in).c_str(), t.is_long?"L":"S", t.kind, t.entry, t.lot, t.pnl);
            std::fclose(f);
            std::fprintf(stderr, "[out] %d trades -> %s\n", R.trades, out_path.c_str());
        }
    }
    return 0;
}
