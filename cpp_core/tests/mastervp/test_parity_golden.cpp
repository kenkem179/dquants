// Golden parity regression guard. Freezes one day of the MT5 tester reference
// (parity_BTCUSD-Exnes-0406_PERIOD_M3.csv, BTCUSD M3 2026-04-09, 480 rows) plus the bid
// M3 bars that warm it up, and asserts the C++ per-bar computation surface still
// reproduces MT5 within the documented tolerances. If a future change breaks front-half
// faithfulness, THIS fails -- parity stops being a one-off check (SPEC §9d).
//
// Validated columns (must match): master VP (mpoc/mvah/mval), regime (trend/plus/minus/adx),
// raw signal (sigValid). atr1 and the sl/tp prices carry the ATR-from-CSV spike caveat and
// are NOT asserted here. The single 00:03 spike-bar signal miss is the known caveat boundary.
//
// Files are loaded relative to cpp_core/ (Makefile runs tests from there).
#include <cstdio>
#include <string>
#include <vector>
#include <unordered_map>
#include <fstream>
#include <sstream>
#include <cmath>
#include "kk/common/test.hpp"
#include "kk/common/config.hpp"
#include "kk/common/bars_csv.hpp"
#include "kk/mastervp/parity_runner.hpp"

static std::vector<std::string> split_csv(const std::string& line) {
    std::vector<std::string> out;
    std::stringstream ss(line);
    std::string cell;
    while (std::getline(ss, cell, ',')) out.push_back(cell);
    return out;
}

void test_parity_golden() {
    const std::string bars_path = "tests/mastervp/golden/bars_btcusd_M3_aprwindow.csv";
    const std::string ref_path  = "tests/mastervp/golden/parity_ref_btcusd_M3.csv";

    auto bars = kk::load_bars_csv(bars_path);
    KK_CHECK(!bars.empty());
    if (bars.empty()) { std::printf("  (missing %s -- run cpp_core/tools/export_bars.py)\n", bars_path.c_str()); return; }

    kk::Params p;                 // code defaults: node_gate_enabled=true (the MT5-effective value)
    p.pip_size = 0.01; p.mintick = 0.01; p.contract_size = 1.0;   // BTCUSD, 2 digits

    const auto rows = kk::parity::run(bars, p);
    std::unordered_map<std::string, const kk::parity::ParityRow*> by_time;
    for (const auto& r : rows) by_time[kk::parity::fmt_bar_time(r.ts_ms)] = &r;

    std::ifstream f(ref_path);
    KK_CHECK(f.good());
    if (!f.good()) { std::printf("  (missing %s)\n", ref_path.c_str()); return; }

    std::string line;
    std::getline(f, line);  // header
    int aligned = 0, trend_mismatch = 0, sig_mismatch = 0, ref_sig = 0, both_sig = 0;
    double max_dvp = 0.0, max_ddi = 0.0;
    while (std::getline(f, line)) {
        if (line.empty()) continue;
        const auto col = split_csv(line);
        if (col.size() < 13) continue;
        const auto it = by_time.find(col[0]);
        if (it == by_time.end()) continue;
        const kk::parity::ParityRow& r = *it->second;
        ++aligned;
        // master VP (cols 4,5,6), regime DI/ADX (cols 8,9,10), trend (7), sigValid (12).
        max_dvp = std::max(max_dvp, std::fabs(r.mpoc - std::stod(col[4])));
        max_dvp = std::max(max_dvp, std::fabs(r.mvah - std::stod(col[5])));
        max_dvp = std::max(max_dvp, std::fabs(r.mval - std::stod(col[6])));
        max_ddi = std::max(max_ddi, std::fabs(r.plus  - std::stod(col[8])));
        max_ddi = std::max(max_ddi, std::fabs(r.minus - std::stod(col[9])));
        max_ddi = std::max(max_ddi, std::fabs(r.adx   - std::stod(col[10])));
        if (r.trend != std::stoi(col[7])) ++trend_mismatch;
        const int rs = std::stoi(col[12]);
        if (r.sigValid != rs) ++sig_mismatch;
        if (rs == 1) { ++ref_sig; if (r.sigValid == 1) ++both_sig; }
    }
    std::printf("  aligned=%d  max|Δ|VP=%.4f  max|Δ|DI=%.4f  trendMiss=%d  "
                "sigMiss=%d  sig(both/ref)=%d/%d\n",
                aligned, max_dvp, max_ddi, trend_mismatch, sig_mismatch, both_sig, ref_sig);

    KK_CHECK(aligned == 480);            // all ref rows align to a computed bar
    KK_CHECK_NEAR(max_dvp, 0.0, 0.01);   // master VP matches to rounding
    KK_CHECK_NEAR(max_ddi, 0.0, 0.05);   // +DI/-DI/ADX match (MT5 iADX EMA-smoothed)
    KK_CHECK(trend_mismatch == 0);       // regime trend flag 100%
    KK_CHECK(sig_mismatch <= 1);         // raw signal: at most the one 00:03 ATR-spike boundary
    KK_CHECK(both_sig >= 74);            // reproduces >=74 of 75 MT5 raw signals
}

void run_all() {
    KK_RUN(test_parity_golden);
}

KK_TEST_MAIN()
