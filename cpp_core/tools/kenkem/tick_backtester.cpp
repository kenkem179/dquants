// kenkem_tick_backtester — headless TICK-replay backtest for the distilled KenKem engine.
//
// Loads M1 BID bars (for the bar-determined front-half: indicators, triggers, signals, SL/TP) AND a
// real bid/ask tick stream (ts_ms,bid,ask). Signals are detected on closed bars exactly as the bar
// engine; management (SL/TP/partial/BE/trail) is driven by the real tick path. This reproduces MT5
// execution far better than the bar engine's synthetic OHLC walk.
//
// Usage:
//   kenkem_tick_backtester --bars-m1 <m1.csv> --ticks <ticks.csv> [--symbol-btc|--symbol-xau]
//        [--set <file>] [--from-ms <e>] [--to-ms <e>] [--warmup <bars>] [--out <trades.csv>]
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>
#include <ctime>
#include "kk/common/bars_csv.hpp"
#include "kk/common/types.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include "kk/kenkem/tick_engine.hpp"

using namespace kk::kenkem;

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
    gmtime_r(&t, &tmv);
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%04d.%02d.%02d %02d:%02d", tmv.tm_year+1900, tmv.tm_mon+1, tmv.tm_mday, tmv.tm_hour, tmv.tm_min);
    return buf;
}

int main(int argc, char** argv) {
    std::string m1_path, ticks_path, set_path, out_path, oracle_path;
    bool xau = false;
    double spread = -1.0;
    int warmup = 250;
    int64_t from_ms = 0, to_ms = 0;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]{ return (i+1 < argc) ? std::string(argv[++i]) : std::string(); };
        if      (a == "--bars-m1")    m1_path = next();
        else if (a == "--ticks")      ticks_path = next();
        else if (a == "--set")        set_path = next();
        else if (a == "--out")        out_path = next();
        else if (a == "--symbol-xau") xau = true;
        else if (a == "--symbol-btc") xau = false;
        else if (a == "--spread")     spread = std::stod(next());
        else if (a == "--warmup")     warmup = std::stoi(next());
        else if (a == "--from-ms")    from_ms = std::stoll(next());
        else if (a == "--to-ms")      to_ms = std::stoll(next());
        else if (a == "--pctile-oracle") oracle_path = next();
    }
    if (m1_path.empty() || ticks_path.empty()) { std::fprintf(stderr, "need --bars-m1 AND --ticks\n"); return 2; }

    KenKemConfig cfg;
    if (xau) cfg.apply_xauusd_specs(); else cfg.apply_btcusd_specs();
    if (spread < 0) spread = xau ? 0.05 : 2.0;
    if (!set_path.empty()) {
        int n = load_set(cfg, set_path);
        std::fprintf(stderr, "[set] applied %d keys from %s\n", n, set_path.c_str());
    }
    if (const char* e = std::getenv("KK_E1_FAITHFUL")) cfg.e1_faithful_trigger = std::atoi(e) != 0;

    // Load ALL M1 bars (no from filter) so indicators warm up; the engine gates trading by from_ms.
    std::vector<kk::Bar> m1 = kk::load_bars_csv(m1_path, 0, to_ms);
    if (m1.empty()) { std::fprintf(stderr, "no M1 bars from %s\n", m1_path.c_str()); return 1; }
    for (kk::Bar& b : m1) b.spread_mean = spread;   // only used for indicator-side, not exits
    std::vector<kk::Bar> m3 = aggregate(m1, 3), m5 = aggregate(m1, 5), m15 = aggregate(m1, 15);
    TfBundle bundle = build_tf_bundle(m1, m3, m5, m15, cfg);

    TickEngine eng(bundle, cfg, warmup, from_ms, to_ms);

    // Optional diagnostic: load MT5's per-bar atr_pctile (ts_ms,atr_pctile CSV) and feed it as an oracle.
    std::unordered_map<int64_t, double> pctile_oracle;
    if (!oracle_path.empty()) {
        std::FILE* fo = std::fopen(oracle_path.c_str(), "rb");
        if (!fo) { std::fprintf(stderr, "cannot open oracle %s\n", oracle_path.c_str()); return 1; }
        char ln[256]; bool fst = true;
        while (std::fgets(ln, sizeof(ln), fo)) {
            if (fst) { fst = false; if (ln[0] < '0' || ln[0] > '9') continue; }
            long long ts; double pc;
            if (std::sscanf(ln, "%lld,%lf", &ts, &pc) == 2) pctile_oracle[(int64_t)ts] = pc;
        }
        std::fclose(fo);
        std::fprintf(stderr, "[oracle] loaded %zu atr_pctile rows from %s\n", pctile_oracle.size(), oracle_path.c_str());
        eng.set_pctile_oracle(&pctile_oracle);
    }

    // Stream ticks (ts_ms,bid,ask). Skip a header line if present.
    std::FILE* fi = std::fopen(ticks_path.c_str(), "rb");
    if (!fi) { std::fprintf(stderr, "cannot open ticks %s\n", ticks_path.c_str()); return 1; }
    char line[256];
    bool first = true;
    int64_t n_ticks = 0;
    kk::Tick last{};
    while (std::fgets(line, sizeof(line), fi)) {
        if (first) { first = false; if (line[0] < '0' || line[0] > '9') continue; }
        kk::Tick t;
        if (std::sscanf(line, "%lld,%lf,%lf", (long long*)&t.ts_ms, &t.bid, &t.ask) != 3) continue;
        if (to_ms && t.ts_ms >= to_ms) break;
        eng.on_tick(t);
        last = t;
        ++n_ticks;
    }
    std::fclose(fi);
    if (n_ticks > 0) eng.finish(last.bid, last.ask, last.ts_ms);

    const BtResult& R = eng.result();
    std::printf("=== KenKem TICK backtest (%s) ===\n", xau ? "XAUUSD" : "BTCUSD");
    std::printf("M1 bars: %d   ticks: %lld   warmup: %d\n", (int)m1.size(), (long long)n_ticks, warmup);
    std::printf("trades:   %d  (wins %d, win%% %.1f)\n", R.trades, R.wins, 100.0 * R.win_rate);
    std::printf("net:      %.2f USD   (end balance %.2f)\n", R.net, R.end_balance);
    std::printf("PF:       %.3f\n", R.pf);
    std::printf("max DD:   %.2f USD\n", R.max_dd);
    int ce[6] = {0,0,0,0,0,0}; double pe[6] = {0,0,0,0,0,0};
    for (const Trade& t : R.list) { if (t.kind>=1 && t.kind<=5) { ce[t.kind]++; pe[t.kind]+=t.pnl; } }
    std::printf("by entry: E1 %d (%.0f)  E2 %d (%.0f)  E4 %d (%.0f)  E5 %d (%.0f)\n",
                ce[1],pe[1], ce[2],pe[2], ce[4],pe[4], ce[5],pe[5]);
    std::printf("ARM events: E1 %d (cross %ld, touch %ld)  E2 %d\n",
                eng.arm_e1_count(), eng.arm_e1_cross(), eng.arm_e1_touch(), eng.arm_e2_count());

    if (!out_path.empty()) {
        FILE* f = std::fopen(out_path.c_str(), "w");
        if (f) {
            // Parity schema — column-aligned with KenKem EA Parity/TradeJournal.mqh so the two
            // ledgers diff 1:1 (entryTimeUTC is the join key). maeR is not tracked here (emit 0).
            std::fprintf(f, "entryTimeUTC,dir,kind,entry,riskPrice,exitPrice,realizedUsd,mfeR,maeR,exitTag\n");
            for (const Trade& t : R.list) {
                // 'E' session-end + 'X' panic/score-drop both close via DEAL_REASON_EXPERT in MT5 => "EA".
                const char* tag = (t.exit_tag == 'T') ? "TP"
                                : (t.exit_tag == 'E' || t.exit_tag == 'X') ? "EA"
                                : (t.exit_tag == 'S') ? (t.pnl > 0.0 ? "SL-WIN" : "SL-LOSS")
                                : "NA";
                std::fprintf(f, "%s,%s,E%d,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%s\n",
                             utc(t.t_in).c_str(), t.is_long?"L":"S", t.kind,
                             t.entry, t.risk, t.exit_price, t.pnl, t.mfe_r, 0.0, tag);
            }
            std::fclose(f);
            std::fprintf(stderr, "[out] %d trades -> %s\n", R.trades, out_path.c_str());
        }
    }
    return 0;
}
