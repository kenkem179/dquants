// Unit tests for the Extreme Reversion (XRev) path (kk::detect_extreme_reversion). Pure function:
// crafted master VP + failed-breakout-sweep candle + precomputed lookback scalars -> assert fire /
// no-fire and the SL/TP/RR economics. Also proves the toggle gates the whole family OFF.
#include "kk/mastervp/extreme_reversion.hpp"
#include "kk/common/test.hpp"

static kk::Params base_params() {
    kk::Params p;
    p.apply_xauusd_specs();
    p.enable_extreme_reversion = true;
    p.xrev_hh_lookback = 5;
    p.xrev_fail_lookback = 14;
    p.xrev_min_closes_beyond = 2;
    p.xrev_max_closes_beyond = 0;
    p.xrev_min_age_bars = 40;
    p.xrev_big_candle_atr = 1.0;
    p.xrev_body_pct_min = 0.4;
    p.xrev_wick_frac = 1.0;
    p.xrev_net_delta_min = 0.6;
    p.xrev_use_node_gate = true;
    p.xrev_sl_atr = 0.7;
    p.xrev_rr_min = 2.0;
    p.tp1_r = 0.8;
    return p;
}

static kk::VPResult master() {
    kk::VPResult m; m.valid = true;
    m.poc = 100; m.vah = 110; m.val = 90; m.hi = 130; m.lo = 70;
    return m;
}

// SHORT rejection bar: swept above VAH(110), closed back below it on a big bearish candle with a
// large upper wick. range 10, body 4 (40%), upper wick 4 (>= body), lower wick 2.
static kk::SignalBar reject_short() {
    kk::SignalBar s;
    s.o = 113; s.c = 109; s.h = 117; s.l = 107;   // h sweeps >110; c<110 (failed back inside value)
    s.atr2 = 8; s.atr1 = 8; s.entry_close = 108;
    return s;
}

static kk::NodeState node(double net, bool absorbed = false) {
    kk::NodeState ns; ns.net = net; ns.touch = 5.0; ns.absorbed = absorbed;
    ns.state = absorbed ? 0 : (net > 0.15 ? 1 : (net < -0.15 ? -1 : 0));
    return ns;
}

static void test_xrev_short_fires() {
    auto p = base_params();
    auto sig = kk::detect_extreme_reversion(p, master(), reject_short(),
        /*sweep_hi=*/110, /*sweep_lo=*/90, /*closes_above=*/3, /*closes_below=*/0,
        /*aged_short=*/true, /*aged_long=*/false,
        node(-0.5), node(0.0), node(-0.7));
    KK_CHECK(sig.valid);
    KK_CHECK(!sig.is_long);
    KK_CHECK(sig.is_extreme_rev);
    KK_CHECK(sig.is_rev);
    KK_CHECK_NEAR(sig.sl, 110 + 0.7 * 8, 1e-9);     // sweep_hi + sl_atr*atr1
    KK_CHECK_NEAR(sig.risk, (110 + 5.6) - 108, 1e-9);
    KK_CHECK_NEAR(sig.tp2, 90.0, 1e-9);             // target = mVAL
    KK_CHECK_NEAR(sig.tp1, 108 - sig.risk * 0.8, 1e-9);
}

static void test_xrev_disabled_no_fire() {
    auto p = base_params(); p.enable_extreme_reversion = false;
    auto sig = kk::detect_extreme_reversion(p, master(), reject_short(),
        110, 90, 3, 0, true, false, node(-0.5), node(0.0), node(-0.7));
    KK_CHECK(!sig.valid);
}

static void test_xrev_rr_reject() {
    auto p = base_params(); p.xrev_rr_min = 3.0;   // runway/risk = 18/7.6 = 2.37 < 3
    auto sig = kk::detect_extreme_reversion(p, master(), reject_short(),
        110, 90, 3, 0, true, false, node(-0.5), node(0.0), node(-0.7));
    KK_CHECK(!sig.valid);
}

static void test_xrev_not_swept_no_fire() {
    auto p = base_params();
    auto sig = kk::detect_extreme_reversion(p, master(), reject_short(),
        /*sweep_hi=*/120, 90, 3, 0, true, false,   // s.h=117 < 120 -> not swept
        node(-0.5), node(0.0), node(-0.7));
    KK_CHECK(!sig.valid);
}

static void test_xrev_not_aged_no_fire() {
    auto p = base_params();
    auto sig = kk::detect_extreme_reversion(p, master(), reject_short(),
        110, 90, 3, 0, /*aged_short=*/false, false,
        node(-0.5), node(0.0), node(-0.7));
    KK_CHECK(!sig.valid);
}

static void test_xrev_weak_flow_no_fire() {
    auto p = base_params();
    auto sig = kk::detect_extreme_reversion(p, master(), reject_short(),
        110, 90, 3, 0, true, false,
        node(-0.5), node(0.0), node(-0.3));   // near-price net -0.3 > -0.6
    KK_CHECK(!sig.valid);
}

static void test_xrev_node_gate_blocks() {
    auto p = base_params();
    auto sig = kk::detect_extreme_reversion(p, master(), reject_short(),
        110, 90, 3, 0, true, false,
        node(+0.5), node(0.0), node(-0.7));   // VAH node BUYING (state +1) -> sell gate fails
    KK_CHECK(!sig.valid);
}

static void test_xrev_too_few_closes_no_fire() {
    auto p = base_params();
    auto sig = kk::detect_extreme_reversion(p, master(), reject_short(),
        110, 90, /*closes_above=*/1, 0, true, false,   // < min 2
        node(-0.5), node(0.0), node(-0.7));
    KK_CHECK(!sig.valid);
}

// LONG mirror: swept below VAL(90), closed back above it on a big bullish candle + lower wick.
static void test_xrev_long_fires() {
    auto p = base_params();
    kk::SignalBar s;
    s.o = 87; s.c = 91; s.h = 93; s.l = 83;   // l sweeps <90; c>90; body 4 (40%), lower wick 4
    s.atr2 = 8; s.atr1 = 8; s.entry_close = 92;
    auto sig = kk::detect_extreme_reversion(p, master(), s,
        /*sweep_hi=*/110, /*sweep_lo=*/90, /*closes_above=*/0, /*closes_below=*/3,
        /*aged_short=*/false, /*aged_long=*/true,
        node(0.0), node(+0.5), node(+0.7));
    KK_CHECK(sig.valid);
    KK_CHECK(sig.is_long);
    KK_CHECK(sig.is_extreme_rev);
    KK_CHECK_NEAR(sig.sl, 90 - 0.7 * 8, 1e-9);   // sweep_lo - sl_atr*atr1
    KK_CHECK_NEAR(sig.tp2, 110.0, 1e-9);         // target = mVAH
}

static void run_all() {
    KK_RUN(test_xrev_short_fires);
    KK_RUN(test_xrev_disabled_no_fire);
    KK_RUN(test_xrev_rr_reject);
    KK_RUN(test_xrev_not_swept_no_fire);
    KK_RUN(test_xrev_not_aged_no_fire);
    KK_RUN(test_xrev_weak_flow_no_fire);
    KK_RUN(test_xrev_node_gate_blocks);
    KK_RUN(test_xrev_too_few_closes_no_fire);
    KK_RUN(test_xrev_long_fires);
}

KK_TEST_MAIN()
