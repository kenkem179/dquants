#include "kk/mastervp/volume_profile.hpp"
#include "kk/common/test.hpp"
#include <vector>

static void test_build_va_from_hist_known() {
    // hist peak in the middle; lo=90, step=3 -> POC bin 2 (center 97.5), VA grows high-side first.
    std::vector<double> hist{1, 1, 50, 50, 50, 1, 1};
    auto r = kk::vp::build_va_from_hist(hist, 90.0, 3.0, 70.0);
    KK_CHECK(r.valid);
    KK_CHECK_NEAR(r.poc, 97.5, 1e-9);
    KK_CHECK_NEAR(r.val, 96.0, 1e-9);
    KK_CHECK_NEAR(r.vah, 105.0, 1e-9);
    KK_CHECK(r.val <= r.poc && r.poc <= r.vah);
}

static void test_build_va_ties_go_high() {
    // Symmetric around POC: equal neighbours -> high side taken first (nextH >= nextL).
    std::vector<double> hist{10, 10, 100, 10, 10};
    auto r = kk::vp::build_va_from_hist(hist, 0.0, 1.0, 60.0);
    KK_CHECK_NEAR(r.poc, 2.5, 1e-9);   // bin 2 center
    // total=140, target=84, acc=100 already >= target -> VA is just the POC bin.
    KK_CHECK_NEAR(r.vah, 3.0, 1e-9);
    KK_CHECK_NEAR(r.val, 2.0, 1e-9);
}

static void test_compute_vp_bars() {
    // Bars clustered so hlc3 concentrates near 100; check POC lands in-range and valid.
    std::vector<kk::Bar> bars;
    for (int i = 0; i < 50; ++i) {
        kk::Bar b;
        double base = (i % 5 == 0) ? 105.0 : 100.0;   // most mass at 100
        b.high = base + 0.5; b.low = base - 0.5; b.close = base;
        b.tick_count = (i % 5 == 0) ? 1 : 20;
        bars.push_back(b);
    }
    auto r = kk::vp::compute_vp_bars(bars.data(), (int)bars.size(), 30, 70.0);
    KK_CHECK(r.valid);
    KK_CHECK(r.lo <= r.poc && r.poc <= r.hi);
    KK_CHECK(r.val <= r.vah);
    KK_CHECK(r.poc > 99.0 && r.poc < 101.0);   // POC at the heavy 100 cluster
}

static void test_compute_vp_degenerate() {
    std::vector<kk::Bar> bars(3);
    for (auto& b : bars) { b.high = 100; b.low = 100; b.close = 100; b.tick_count = 5; }
    auto r = kk::vp::compute_vp_bars(bars.data(), 3, 30, 70.0);
    KK_CHECK(!r.valid);   // zero range -> invalid (matches MQL step<=0 guard)
}

static void run_all() {
    KK_RUN(test_build_va_from_hist_known);
    KK_RUN(test_build_va_ties_go_high);
    KK_RUN(test_compute_vp_bars);
    KK_RUN(test_compute_vp_degenerate);
}

KK_TEST_MAIN()
