// backtester — headless Layer-3 tick backtest driver for KK-MasterVP. Loads the validated
// bid M3 bars (warmup + test window) and streams a tick CSV through the TickEngine, emitting
// a byte-compatible trades_*.csv to diff against the MT5 tester reference (Level-2 parity).
//
// Usage:
//   backtester --bars <bars.csv> --ticks <ticks.csv> --out <trades_cpp.csv>
//              [--trade-from-ms <epoch_ms>] [--set <baseline.set>] [--symbol-xau]
// bars.csv  : ts_ms,open,high,low,close,tick_count  (tools/export_bars.py)
// ticks.csv : ts_ms,bid,ask                          (tools/export_ticks.py)
// trade-from-ms: test-period start; bars before it are warmup only (no trading). The tick
//                stream should itself begin at/after this instant.
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include "kk/common/config.hpp"
#include "kk/common/bars_csv.hpp"
#include "kk/mastervp/tick_engine.hpp"
#include "kk/common/trade_journal.hpp"
#include "kk/common/signal_journal.hpp"

int main(int argc, char** argv) {
    std::string bars_path, bars_m1_path, bars_m5_path, ticks_path, out_path = "tools/trades_cpp.csv", set_path;
    std::string signals_path;   // edge-autopsy: pre-gate raw signal stream (empty = off)
    std::string flow_path;      // Step-0: per-bar flow path while a position is open (empty = off)
    int64_t trade_from_ms = 0;
    int64_t trade_to_ms = 0;   // walk-forward fold cap: open no new positions at/after this ms (0=off)
    double extra_spread = 0.0; // cost-parity stress: extra spread (price units) added to bid/ask gap
    bool symbol_xau = false;
    bool set_all = false;   // apply ALL .set keys incl. MQL non-inputs (Pine-faithful mode)

    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&]() { return (i + 1 < argc) ? std::string(argv[++i]) : std::string(); };
        if      (a == "--bars")  bars_path  = next();
        else if (a == "--bars-m1") bars_m1_path = next();   // Monster: M1 series for impulse M1-net
        else if (a == "--bars-m5") bars_m5_path = next();   // MTF: M5 overlay series (confluence gate)
        else if (a == "--ticks") ticks_path = next();
        else if (a == "--out")   out_path   = next();
        else if (a == "--signals-out") signals_path = next();   // pre-gate signal CSV (edge autopsy)
        else if (a == "--flow-path-out") flow_path = next();     // Step-0 per-bar flow path CSV
        else if (a == "--set")   set_path   = next();
        else if (a == "--set-all") { set_path = next(); set_all = true; }
        else if (a == "--trade-from-ms") trade_from_ms = std::stoll(next());
        else if (a == "--trade-to-ms") trade_to_ms = std::stoll(next());
        else if (a == "--extra-spread") extra_spread = std::stod(next());
        else if (a == "--symbol-xau") symbol_xau = true;
        else if (a == "--symbol-btc") { /* default */ }
        else { std::fprintf(stderr, "unknown arg: %s\n", a.c_str()); return 2; }
    }
    if (bars_path.empty() || ticks_path.empty()) {
        std::fprintf(stderr, "usage: backtester --bars <f> --ticks <f> [--out <f>] "
                             "[--trade-from-ms <ms>] [--set <f>] [--symbol-xau]\n");
        return 2;
    }

    kk::Params p;
    if (symbol_xau) p.apply_xauusd_specs(); else p.apply_btcusd_specs();
    if (!set_path.empty()) {
        const int n = kk::load_set(p, set_path, /*mimic_mt5_noninput=*/!set_all);
        if (n < 0) { std::fprintf(stderr, "could not read .set: %s\n", set_path.c_str()); return 1; }
        std::fprintf(stderr, "[bt] applied %d keys from %s (%s)\n", n, set_path.c_str(),
                     set_all ? "ALL keys, Pine-faithful" : "mimic MT5 non-input");
    }

    const auto bars = kk::load_bars_csv(bars_path);
    if (bars.empty()) { std::fprintf(stderr, "no bars from %s\n", bars_path.c_str()); return 1; }
    std::fprintf(stderr, "[bt] loaded %zu bars from %s\n", bars.size(), bars_path.c_str());

    kk::TickEngine eng(p);
    if (!signals_path.empty()) eng.set_collect_signals(true);
    if (!flow_path.empty()) eng.set_flow_path(flow_path);
    if (trade_to_ms > 0) eng.set_trade_to_ms(trade_to_ms);
    if (extra_spread > 0.0) {
        eng.set_extra_spread(extra_spread);
        std::fprintf(stderr, "[bt] extra spread = %.5f price added to bid/ask gap\n", extra_spread);
    }
    if (const char* df = std::getenv("KKVP_DBG_FROM")) {
        const char* dt = std::getenv("KKVP_DBG_TO");
        eng.set_debug_window(std::stoll(df), dt ? std::stoll(dt) : std::stoll(df) + 86400000LL);
    }
    if (!bars_m5_path.empty()) {
        const auto m5 = kk::load_bars_csv(bars_m5_path);
        std::fprintf(stderr, "[bt] loaded %zu M5 bars from %s (MTF overlay)\n",
                     m5.size(), bars_m5_path.c_str());
        eng.set_m5_bars(m5);   // must precede load_bars (precompute_ reads it)
    }
    if (!bars_m1_path.empty()) {
        const auto m1 = kk::load_bars_csv(bars_m1_path);
        std::fprintf(stderr, "[bt] loaded %zu M1 bars from %s (impulse M1-net)\n",
                     m1.size(), bars_m1_path.c_str());
        eng.load_bars(bars, m1, trade_from_ms);
    } else {
        eng.load_bars(bars, trade_from_ms);
    }

    // Stream the tick CSV (ts_ms,bid,ask). Skip the header line. fscanf keeps memory flat
    // over the ~50M-row window; the engine holds only bars + precomputed arrays.
    std::FILE* fi = std::fopen(ticks_path.c_str(), "rb");
    if (!fi) { std::fprintf(stderr, "could not open ticks: %s\n", ticks_path.c_str()); return 1; }
    char line[256];
    bool first = true;
    int64_t n_ticks = 0;
    kk::Tick last{};
    while (std::fgets(line, sizeof(line), fi)) {
        if (first) { first = false; if (line[0] < '0' || line[0] > '9') continue; }  // skip header
        kk::Tick t;
        // robust parse: ts_ms,bid,ask
        if (std::sscanf(line, "%lld,%lf,%lf", (long long*)&t.ts_ms, &t.bid, &t.ask) != 3) continue;
        eng.on_tick(t);
        last = t;
        ++n_ticks;
    }
    std::fclose(fi);
    if (n_ticks > 0) eng.finish(last.bid, last.ask, last.ts_ms);
    std::fprintf(stderr, "[bt] streamed %lld ticks\n", (long long)n_ticks);

    const auto& trades = eng.trades();
    const std::string csv = kk::to_trades_csv(trades);
    std::FILE* fo = std::fopen(out_path.c_str(), "wb");
    if (!fo) { std::fprintf(stderr, "could not open out: %s\n", out_path.c_str()); return 1; }
    std::fwrite(csv.data(), 1, csv.size(), fo);
    std::fclose(fo);

    std::fprintf(stderr, "[bt] %zu trades -> %s | final balance %.2f, peak %.2f, raw signals %d\n",
                 trades.size(), out_path.c_str(), eng.balance(), eng.peak_equity(), eng.raw_signals());

    // Edge-autopsy: dump the pre-gate raw signal stream for the Python conditional-expectancy layer.
    if (!signals_path.empty()) {
        const std::string scsv = kk::to_signals_csv(eng.signals());
        std::FILE* fs = std::fopen(signals_path.c_str(), "wb");
        if (!fs) { std::fprintf(stderr, "could not open signals-out: %s\n", signals_path.c_str()); return 1; }
        std::fwrite(scsv.data(), 1, scsv.size(), fs);
        std::fclose(fs);
        std::fprintf(stderr, "[bt] %zu raw signals -> %s\n", eng.signals().size(), signals_path.c_str());
    }
    return 0;
}
