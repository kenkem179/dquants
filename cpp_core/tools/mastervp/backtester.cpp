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

int main(int argc, char** argv) {
    std::string bars_path, bars_m1_path, ticks_path, out_path = "tools/trades_cpp.csv", set_path;
    int64_t trade_from_ms = 0;
    int64_t trade_to_ms = 0;   // walk-forward fold cap: open no new positions at/after this ms (0=off)
    double extra_spread = 0.0; // cost-parity stress: extra spread (price units) added to bid/ask gap
    bool symbol_xau = false;
    bool set_all = false;   // apply ALL .set keys incl. MQL non-inputs (Pine-faithful mode)
    int    cli_use_vmc = -1;       // -1 = leave .set/default; 0/1 = force off/on
    double cli_vmc_confirm = -1;   // <0 = leave; else override |vmc| threshold
    double cli_vmc_dref = -1;      // <0 = leave; else override d_ref

    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&]() { return (i + 1 < argc) ? std::string(argv[++i]) : std::string(); };
        if      (a == "--bars")  bars_path  = next();
        else if (a == "--bars-m1") bars_m1_path = next();   // Monster: M1 series for impulse M1-net
        else if (a == "--ticks") ticks_path = next();
        else if (a == "--out")   out_path   = next();
        else if (a == "--set")   set_path   = next();
        else if (a == "--set-all") { set_path = next(); set_all = true; }
        else if (a == "--trade-from-ms") trade_from_ms = std::stoll(next());
        else if (a == "--trade-to-ms") trade_to_ms = std::stoll(next());
        else if (a == "--extra-spread") extra_spread = std::stod(next());
        else if (a == "--symbol-xau") symbol_xau = true;
        else if (a == "--symbol-btc") { /* default */ }
        else if (a == "--use-vmc")     cli_use_vmc = 1;
        else if (a == "--no-vmc")      cli_use_vmc = 0;
        else if (a == "--vmc-confirm") { cli_vmc_confirm = std::stod(next()); cli_use_vmc = 1; }
        else if (a == "--vmc-d-ref")   cli_vmc_dref = std::stod(next());
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
    // VMC support-factor overrides (CLI beats .set). Default off => exact baseline parity.
    if (cli_use_vmc >= 0)      p.use_vmc_confirm = (cli_use_vmc == 1);
    if (cli_vmc_confirm >= 0)  p.vmc_confirm = cli_vmc_confirm;
    if (cli_vmc_dref >= 0)     p.vmc_d_ref = cli_vmc_dref;
    if (p.use_vmc_confirm)
        std::fprintf(stderr, "[bt] VMC confirm ON: |vmc|>=%.4f d_ref=%.3f\n", p.vmc_confirm, p.vmc_d_ref);

    const auto bars = kk::load_bars_csv(bars_path);
    if (bars.empty()) { std::fprintf(stderr, "no bars from %s\n", bars_path.c_str()); return 1; }
    std::fprintf(stderr, "[bt] loaded %zu bars from %s\n", bars.size(), bars_path.c_str());

    kk::TickEngine eng(p);
    if (trade_to_ms > 0) eng.set_trade_to_ms(trade_to_ms);
    if (extra_spread > 0.0) {
        eng.set_extra_spread(extra_spread);
        std::fprintf(stderr, "[bt] extra spread = %.5f price added to bid/ask gap\n", extra_spread);
    }
    if (const char* df = std::getenv("KKVP_DBG_FROM")) {
        const char* dt = std::getenv("KKVP_DBG_TO");
        eng.set_debug_window(std::stoll(df), dt ? std::stoll(dt) : std::stoll(df) + 86400000LL);
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

    // Summary (net / win% / PF / maxDD) so baseline-vs-VMC A/B is one-glance comparable.
    {
        int wins = 0; double net = 0, gw = 0, gl = 0, bal = p.start_balance, peak = p.start_balance, maxdd = 0;
        for (const auto& t : trades) {
            net += t.realized_usd; bal += t.realized_usd;
            if (t.realized_usd > 0) { wins++; gw += t.realized_usd; } else gl += -t.realized_usd;
            if (bal > peak) peak = bal;
            double dd = peak - bal; if (dd > maxdd) maxdd = dd;
        }
        double pf = gl > 0 ? gw / gl : (gw > 0 ? 1e9 : 0.0);
        double wr = trades.empty() ? 0.0 : 100.0 * wins / (double)trades.size();
        std::fprintf(stderr, "[bt] SUMMARY %s%s: trades %zu  win%% %.1f  net %.2f  PF %.3f  maxDD %.2f\n",
                     symbol_xau ? "XAU" : "BTC", p.use_vmc_confirm ? " +VMC" : " baseline",
                     trades.size(), wr, net, pf, maxdd);
    }
    return 0;
}
