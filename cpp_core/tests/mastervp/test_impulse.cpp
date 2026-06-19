// Unit tests for the Monster impulse-thrust path (kk::detect_impulse). Pure function: crafted
// master VP + thrust candle + slope/net inputs -> assert fire / no-fire and the SL/TP economics.
#include "kk/mastervp/impulse.hpp"
#include "kk/common/test.hpp"

static kk::Params base_params() {
    kk::Params p;
    p.apply_btcusd_specs();
    p.enable_impulse = true;
    p.impulse_candle_atr = 1.7;
    p.impulse_entry_buf_atr = 0.4;
    p.impulse_net_min = 0.95;
    p.impulse_max_dist_atr = 2.5;
    p.impulse_rr = 3.0;
    p.sl_atr_brk = 2.2;
    p.tp1_r = 1.05;
    return p;
}

static kk::VPResult master() {
    kk::VPResult m; m.valid = true;
    m.poc = 100; m.vah = 110; m.val = 90; m.hi = 130; m.lo = 70;
    return m;
}

// long thrust bar clearing master VAH on near-total M1 net + rising POC -> fires long impulse.
static kk::SignalBar thrust_long() {
    kk::SignalBar s;
    s.o = 110; s.c = 130; s.h = 131; s.l = 109;   // body up, range 22 >= 1.7*10
    s.atr2 = 10; s.atr1 = 10; s.entry_close = 130;
    return s;
}

static void test_impulse_long_fires() {
    auto p = base_params();
    kk::VPResult m = master(), pred = master(); pred.poc = 101;   // predicted POC >= master (trend up)
    auto sig = kk::detect_impulse(p, m, pred, thrust_long(), /*up*/true, /*dn*/false, 0.96, true);
    KK_CHECK(sig.valid);
    KK_CHECK(sig.is_long);
    KK_CHECK(sig.is_impulse);
    KK_CHECK_NEAR(sig.sl, 130 - 2.2 * 10, 1e-9);            // base breakout SL
    KK_CHECK_NEAR(sig.risk, 22.0, 1e-9);
    KK_CHECK_NEAR(sig.tp2, 130 + 22.0 * 3.0, 1e-9);         // impulse_rr
    KK_CHECK_NEAR(sig.tp1, 130 + 22.0 * 1.05, 1e-9);        // tp1_r
}

static void test_impulse_blocked_by_low_net() {
    auto p = base_params();
    kk::VPResult m = master(), pred = master(); pred.poc = 101;
    auto sig = kk::detect_impulse(p, m, pred, thrust_long(), true, false, 0.50, true);  // net < 0.95
    KK_CHECK(!sig.valid);
}

static void test_impulse_blocked_by_slope() {
    auto p = base_params();
    kk::VPResult m = master(), pred = master(); pred.poc = 101;
    auto sig = kk::detect_impulse(p, m, pred, thrust_long(), false, false, 0.96, true);  // no slope
    KK_CHECK(!sig.valid);
}

static void test_impulse_blocked_when_disabled() {
    auto p = base_params(); p.enable_impulse = false;
    kk::VPResult m = master(), pred = master(); pred.poc = 101;
    auto sig = kk::detect_impulse(p, m, pred, thrust_long(), true, false, 0.96, true);
    KK_CHECK(!sig.valid);
}

static void test_impulse_blocked_no_m1() {
    auto p = base_params();
    kk::VPResult m = master(), pred = master(); pred.poc = 101;
    auto sig = kk::detect_impulse(p, m, pred, thrust_long(), true, false, 0.96, false);  // has_m1=false
    KK_CHECK(!sig.valid);
}

static void test_impulse_short_fires() {
    auto p = base_params();
    kk::VPResult m = master(), pred = master(); pred.poc = 99;   // predicted POC <= master (trend dn)
    kk::SignalBar s;
    s.o = 90; s.c = 70; s.h = 91; s.l = 69;   // body down, range 22
    s.atr2 = 10; s.atr1 = 10; s.entry_close = 70;
    auto sig = kk::detect_impulse(p, m, pred, s, /*up*/false, /*dn*/true, -0.96, true);
    KK_CHECK(sig.valid);
    KK_CHECK(!sig.is_long);
    KK_CHECK(sig.is_impulse);
    KK_CHECK_NEAR(sig.sl, 70 + 2.2 * 10, 1e-9);
    KK_CHECK_NEAR(sig.tp2, 70 - 22.0 * 3.0, 1e-9);
}

static void run_all() {
    KK_RUN(test_impulse_long_fires);
    KK_RUN(test_impulse_blocked_by_low_net);
    KK_RUN(test_impulse_blocked_by_slope);
    KK_RUN(test_impulse_blocked_when_disabled);
    KK_RUN(test_impulse_blocked_no_m1);
    KK_RUN(test_impulse_short_fires);
}

KK_TEST_MAIN()
