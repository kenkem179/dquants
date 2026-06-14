#include "kk/mastervp/node_engine.hpp"
#include "kk/common/test.hpp"

static kk::VPResult master(double lo, double hi) {
    kk::VPResult v; v.valid = true; v.lo = lo; v.hi = hi; return v;
}
static kk::Bar mk(double o, double h, double l, double c, long vol) {
    kk::Bar b; b.open = o; b.high = h; b.low = l; b.close = c; b.tick_count = vol; return b;
}

static void test_bull_bar_makes_buy_state() {
    kk::Params p;                       // bins 30, decay .94, neutral .15, sat 4
    kk::NodeEngine ne; ne.init(p.vp_bins);
    ne.update(master(100, 130), mk(110, 115, 109, 114, 100), /*atr=*/2.0, p);
    auto ns = ne.state_at_price(114.0, p);
    KK_CHECK(ns.net > 0.15);
    KK_CHECK(ns.state == 1);
    KK_CHECK(!ns.absorbed);             // single touch < saturation
}

static void test_bear_bar_makes_sell_state() {
    kk::Params p;
    kk::NodeEngine ne; ne.init(p.vp_bins);
    ne.update(master(100, 130), mk(114, 115, 109, 110, 100), 2.0, p);
    auto ns = ne.state_at_price(110.0, p);
    KK_CHECK(ns.net < -0.15);
    KK_CHECK(ns.state == -1);
}

static void test_balanced_repetition_becomes_absorbed() {
    kk::Params p;
    kk::NodeEngine ne; ne.init(p.vp_bins);
    // Alternate equal bull/bear at the same location -> buy≈sell (net~0), touch saturates -> absorbed.
    for (int i = 0; i < 60; ++i) {
        ne.update(master(100, 130), mk(110, 115, 109, 114, 100), 2.0, p);  // bull
        ne.update(master(100, 130), mk(114, 115, 109, 110, 100), 2.0, p);  // bear
    }
    auto ns = ne.state_at_price(112.0, p);
    KK_CHECK(ns.touch >= p.node_saturation);
    KK_CHECK(std::fabs(ns.net) <= p.node_neutral_band);
    KK_CHECK(ns.absorbed);
    KK_CHECK(ns.state == 0);            // absorbed -> flat
}

static void test_invalid_master_no_update() {
    kk::Params p;
    kk::NodeEngine ne; ne.init(p.vp_bins);
    kk::VPResult bad; bad.valid = false;
    ne.update(bad, mk(110, 115, 109, 114, 100), 2.0, p);
    auto ns = ne.state_at_price(112.0, p);
    KK_CHECK(ns.touch == 0.0);          // nothing accumulated
}

static void run_all() {
    KK_RUN(test_bull_bar_makes_buy_state);
    KK_RUN(test_bear_bar_makes_sell_state);
    KK_RUN(test_balanced_repetition_becomes_absorbed);
    KK_RUN(test_invalid_master_no_update);
}

KK_TEST_MAIN()
