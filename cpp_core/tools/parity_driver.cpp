// C++ parity harness driver: bid M3 bars CSV -> per-bar computation surface -> parity_*.csv
// (byte-compatible with MT5 KK-MasterVP/Parity/ParityExport.mqh). This is the C++ side of the
// Level-1 parity check -- diff its output against the MT5 tester reference parity_*.csv.
//
// Usage:
//   parity_driver --bars <bars.csv> [--set <baseline.set>] [--out <parity_cpp.csv>]
//                 [--symbol-btc] [--mimic-mt5-noninput]
// Defaults: bars=tools/bars_btcusd_2026_m3.csv, out=tools/parity_cpp_btcusd_M3.csv,
//           symbol params = BTCUSD (pip/mintick 0.01), node-gate per code default (true).
#include <cstdio>
#include <cstring>
#include <string>
#include "kk/config.hpp"
#include "kk/bars_csv.hpp"
#include "kk/parity_runner.hpp"

int main(int argc, char** argv) {
    std::string bars_path = "tools/bars_btcusd_2026_m3.csv";
    std::string set_path;
    std::string out_path = "tools/parity_cpp_btcusd_M3.csv";
    bool mimic = false;

    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&]() { return (i + 1 < argc) ? std::string(argv[++i]) : std::string(); };
        if      (a == "--bars") bars_path = next();
        else if (a == "--set")  set_path  = next();
        else if (a == "--out")  out_path  = next();
        else if (a == "--mimic-mt5-noninput") mimic = true;
        else if (a == "--symbol-btc") { /* default */ }
        else { std::fprintf(stderr, "unknown arg: %s\n", a.c_str()); return 2; }
    }

    kk::Params p;
    p.apply_btcusd_specs();   // parity reference instrument; XAU via a future --symbol-xau
    if (!set_path.empty()) {
        const int n = kk::load_set(p, set_path, mimic);
        if (n < 0) { std::fprintf(stderr, "could not read .set: %s\n", set_path.c_str()); return 1; }
        std::fprintf(stderr, "[parity] applied %d keys from %s%s\n", n, set_path.c_str(),
                     mimic ? " (mimic MT5 non-input)" : "");
    }

    const auto bars = kk::load_bars_csv(bars_path);
    if (bars.empty()) { std::fprintf(stderr, "no bars loaded from %s\n", bars_path.c_str()); return 1; }
    std::fprintf(stderr, "[parity] loaded %zu bars from %s\n", bars.size(), bars_path.c_str());

    const auto rows = kk::parity::run(bars, p);
    const std::string csv = kk::parity::to_csv(rows);

    std::FILE* fo = std::fopen(out_path.c_str(), "wb");
    if (!fo) { std::fprintf(stderr, "could not open out: %s\n", out_path.c_str()); return 1; }
    std::fwrite(csv.data(), 1, csv.size(), fo);
    std::fclose(fo);
    std::fprintf(stderr, "[parity] wrote %zu rows -> %s\n", rows.size(), out_path.c_str());
    return 0;
}
