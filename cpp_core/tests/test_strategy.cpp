#include "kk/strategy.hpp"
#include "kk/test.hpp"
#include <cstring>

// Baseline-ish params for entry tests: node gate OFF (baseline .set), tight SL/high RR.
static kk::Params base() {
    kk::Params p;
    p.node_gate_enabled = false;
    p.break_buf_atr = 0.5; p.break_max_atr = 9.0;
    p.sl_atr_brk = 1.48; p.rr_brk = 1.8; p.tp1_r = 0.8;
    p.sl_atr_rev = 1.5; p.rr_rev = 1.2; p.body_pct_min = 0.6; p.retest_atr = 0.1;
    p.pip_size = 0.01; p.mintick = 0.01;
    return p;
}
static kk::VPResult mvp(double vah, double val, double lo, double hi) {
    kk::VPResult v; v.valid = true; v.vah = vah; v.val = val; v.lo = lo; v.hi = hi;
    v.poc = 0.5 * (vah + val); return v;
}
static kk::RegimeState trend_up() {
    kk::RegimeState r; r.valid = true; r.trend = true; r.balance = false;
    r.plus = 30; r.minus = 10; r.adx = 28; r.atr1 = 2; return r;
}
static kk::RegimeState balanced() {
    kk::RegimeState r; r.valid = true; r.trend = false; r.balance = true;
    r.plus = 15; r.minus = 12; r.adx = 12; r.atr1 = 2; return r;
}
static const kk::NodeState NS{};   // neutral node (ignored when gate off)

static void test_breakout_long_economics() {
    auto p = base();
    auto m = mvp(/*vah*/99, /*val*/90, /*lo*/85, /*hi*/110);
    kk::SignalBar s{.o = 99.5, .h = 100.7, .l = 99.3, .c = 100.5, .atr2 = 2, .atr1 = 2, .entry_close = 100};
    auto sig = kk::detect_signal(p, m, m, kk::VPResult{}, trend_up(), s, NS, NS, NS);
    KK_CHECK(sig.valid && sig.is_long && !sig.is_rev);
    KK_CHECK(std::strcmp(sig.reason, "L-BRK") == 0);
    KK_CHECK_NEAR(sig.sl, 97.04, 1e-9);            // 100 - max(1.48*2, 0.08)
    KK_CHECK_NEAR(sig.risk, 2.96, 1e-9);
    KK_CHECK_NEAR(sig.tp1, 102.368, 1e-9);         // 100 + 2.96*0.8
    KK_CHECK_NEAR(sig.tp2, 105.328, 1e-9);         // 100 + 2.96*1.8
}

static void test_breakout_short_economics() {
    auto p = base();
    auto m = mvp(/*vah*/110, /*val*/100, /*lo*/90, /*hi*/115);
    // short = close below VAL by > brkBuf(=1.0), within brkMax
    kk::SignalBar s{.o = 99.5, .h = 99.7, .l = 98.3, .c = 98.5, .atr2 = 2, .atr1 = 2, .entry_close = 99};
    kk::RegimeState r = trend_up(); r.plus = 10; r.minus = 30;   // -DI dominates
    auto sig = kk::detect_signal(p, m, m, kk::VPResult{}, r, s, NS, NS, NS);
    KK_CHECK(sig.valid && !sig.is_long);
    KK_CHECK(std::strcmp(sig.reason, "S-BRK") == 0);
    KK_CHECK_NEAR(sig.sl, 99 + 2.96, 1e-9);        // entry + max(1.48*2,...)
    KK_CHECK_NEAR(sig.tp2, 99 - 2.96 * 1.8, 1e-9);
    KK_CHECK(sig.tp1 < sig.entry && sig.tp2 < sig.entry && sig.sl > sig.entry);
}

static void test_anti_chase_ceiling_rejects() {
    auto p = base(); p.break_max_atr = 1.0;        // tighten ceiling so an extended break is rejected
    auto m = mvp(99, 90, 85, 130);
    kk::SignalBar s{.o = 99.5, .h = 102, .l = 99.3, .c = 101.5, .atr2 = 2, .atr1 = 2, .entry_close = 101};
    // sC=101.5 > vah+brkMax (99+2=101) -> breakout window exceeded -> no signal
    auto sig = kk::detect_signal(p, m, m, kk::VPResult{}, trend_up(), s, NS, NS, NS);
    KK_CHECK(!sig.valid);
}

static void test_no_breakout_when_balance_and_reversion_off() {
    auto p = base();   // reversion off by default
    auto m = mvp(99, 90, 85, 110);
    kk::SignalBar s{.o = 99.5, .h = 100.7, .l = 99.3, .c = 100.5, .atr2 = 2, .atr1 = 2, .entry_close = 100};
    auto sig = kk::detect_signal(p, m, m, kk::VPResult{}, balanced(), s, NS, NS, NS);
    KK_CHECK(!sig.valid);
}

static void test_reversion_long_when_enabled() {
    auto p = base(); p.enable_reversion = true;
    auto m = mvp(/*vah*/110, /*val*/98, /*lo*/95, /*hi*/115);
    // low touches VAL(98) within touch(=0.2); bull rejection body
    kk::SignalBar s{.o = 98.1, .h = 99.1, .l = 98.05, .c = 99.0, .atr2 = 2, .atr1 = 2, .entry_close = 99};
    auto sig = kk::detect_signal(p, m, m, kk::VPResult{}, balanced(), s, NS, NS, NS);
    KK_CHECK(sig.valid && sig.is_long && sig.is_rev);
    KK_CHECK(std::strcmp(sig.reason, "L-REV") == 0);
    KK_CHECK_NEAR(sig.sl, 99 - 1.5 * 2, 1e-9);     // sl_atr_rev * atr1 (local invalid -> no clamp)
}

static void test_node_gate_blocks_long_when_selling() {
    auto p = base(); p.node_gate_enabled = true;
    auto m = mvp(99, 90, 85, 110);
    kk::SignalBar s{.o = 99.5, .h = 100.7, .l = 99.3, .c = 100.5, .atr2 = 2, .atr1 = 2, .entry_close = 100};
    kk::NodeState sellVah; sellVah.state = -1; sellVah.absorbed = false;   // VAH shows selling
    auto sig = kk::detect_signal(p, m, m, kk::VPResult{}, trend_up(), s, sellVah, NS, NS);
    KK_CHECK(!sig.valid);                           // gate vetoes the long breakout
    // absorbed node would allow it:
    kk::NodeState absVah; absVah.absorbed = true;
    auto sig2 = kk::detect_signal(p, m, m, kk::VPResult{}, trend_up(), s, absVah, NS, NS);
    KK_CHECK(sig2.valid && sig2.is_long);
}

static void run_all() {
    KK_RUN(test_breakout_long_economics);
    KK_RUN(test_breakout_short_economics);
    KK_RUN(test_anti_chase_ceiling_rejects);
    KK_RUN(test_no_breakout_when_balance_and_reversion_off);
    KK_RUN(test_reversion_long_when_enabled);
    KK_RUN(test_node_gate_blocks_long_when_selling);
}

KK_TEST_MAIN()
