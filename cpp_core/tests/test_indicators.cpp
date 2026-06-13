#include "kk/indicators.hpp"
#include "kk/test.hpp"
#include <vector>

using kk::ind::vector;

static void test_ema_recursive() {
    std::vector<double> x{1, 2, 3, 4};
    auto o = kk::ind::ema(x, 2);            // alpha = 2/3
    const double a = 2.0 / 3.0;
    std::vector<double> e{1};
    for (size_t i = 1; i < x.size(); ++i) e.push_back(a * x[i] + (1 - a) * e[i - 1]);
    for (size_t i = 0; i < x.size(); ++i) KK_CHECK_NEAR(o[i], e[i], 1e-12);
}

static void test_wilder_rma() {
    std::vector<double> x{10, 11, 12, 13};
    auto o = kk::ind::wilder_rma(x, 4);     // alpha = 0.25
    KK_CHECK_NEAR(o[3], 11.265625, 1e-9);
}

static void test_true_range() {
    std::vector<double> h{10, 12}, l{8, 9}, c{9, 11};
    auto tr = kk::ind::true_range(h, l, c);
    KK_CHECK_NEAR(tr[0], 2.0, 1e-12);        // high-low
    KK_CHECK_NEAR(tr[1], 3.0, 1e-12);        // max(3, |12-9|, |9-9|)
}

static void test_rsi_all_gains_is_100() {
    std::vector<double> c;
    for (int i = 0; i < 300; ++i) c.push_back(100.0 + i * (100.0 / 299.0));
    auto r = kk::ind::rsi(c, 14);
    KK_CHECK(r.back() > 99.9);
    for (double v : r) KK_CHECK(v >= 0.0 && v <= 100.0);
}

static void test_atr_positive() {
    std::vector<double> h, l, c;
    for (int i = 0; i < 100; ++i) { double p = 100 + i; h.push_back(p + 1); l.push_back(p - 1); c.push_back(p); }
    auto a = kk::ind::atr(h, l, c, 14);
    for (size_t i = 14; i < a.size(); ++i) KK_CHECK(a[i] > 0.0);
}

static void test_dmi_uptrend_plus_dominates() {
    std::vector<double> h, l, c;
    for (int i = 0; i < 200; ++i) { double p = 100 + i * 0.5; h.push_back(p + 1); l.push_back(p - 1); c.push_back(p); }
    auto d = kk::ind::dmi_adx(h, l, c, 14);
    double pd = 0, md = 0;
    for (size_t i = 150; i < h.size(); ++i) { pd += d.plus_di[i]; md += d.minus_di[i]; }
    KK_CHECK(pd > md);
    for (size_t i = 30; i < h.size(); ++i) {
        KK_CHECK(d.adx[i] >= 0 && d.adx[i] <= 100);
        KK_CHECK(d.plus_di[i] >= 0 && d.plus_di[i] <= 100);
    }
}

static void run_all() {
    KK_RUN(test_ema_recursive);
    KK_RUN(test_wilder_rma);
    KK_RUN(test_true_range);
    KK_RUN(test_rsi_all_gains_is_100);
    KK_RUN(test_atr_positive);
    KK_RUN(test_dmi_uptrend_plus_dominates);
}

KK_TEST_MAIN()
