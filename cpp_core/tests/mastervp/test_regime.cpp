#include "kk/mastervp/regime.hpp"
#include "kk/common/test.hpp"

static void test_trend_when_all_conditions_met() {
    kk::Params p;   // adxTrendMin 22, diSpreadMin 6, emaSepAtr 0.25
    // atr=2 -> ema sep threshold = 0.5; |120-100|=20 ok; adx 30>22; |30-10|=20>6
    auto r = kk::compute_regime(2.0, 120.0, 100.0, 30.0, 30.0, 10.0, p);
    KK_CHECK(r.valid);
    KK_CHECK(r.trend);
    KK_CHECK(!r.balance);
}

static void test_balance_when_adx_low() {
    kk::Params p;
    auto r = kk::compute_regime(2.0, 120.0, 100.0, 10.0, 30.0, 10.0, p);
    KK_CHECK(!r.trend);
    KK_CHECK(r.balance);
}

static void test_no_trend_when_ema_separation_tiny() {
    kk::Params p;
    // adx/di pass, but |emaF-emaS|=0.1 < 0.25*atr(=0.5) -> not trend
    auto r = kk::compute_regime(2.0, 100.1, 100.0, 30.0, 30.0, 10.0, p);
    KK_CHECK(!r.trend);
}

static void test_no_trend_when_di_spread_small() {
    kk::Params p;
    // |plus-minus| = 4 < 6 -> not trend even with high adx and ema sep
    auto r = kk::compute_regime(2.0, 120.0, 100.0, 30.0, 22.0, 18.0, p);
    KK_CHECK(!r.trend);
}

static void run_all() {
    KK_RUN(test_trend_when_all_conditions_met);
    KK_RUN(test_balance_when_adx_low);
    KK_RUN(test_no_trend_when_ema_separation_tiny);
    KK_RUN(test_no_trend_when_di_spread_small);
}

KK_TEST_MAIN()
