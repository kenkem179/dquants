#include "kk/mastervp/strategy.hpp"
#include "kk/mastervp/fvg_sl.hpp"
#include "kk/common/test.hpp"
#include <cstring>
#include <vector>

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

// ---- FVG-anchored SL (feature #3) ----
static kk::Bar bar(double h, double l) { kk::Bar b; b.high = h; b.low = l; b.open = l; b.close = h; return b; }

static kk::Params fvg_base() {
    auto p = base();
    p.enable_fvg_sl = true; p.fvg_lookback = 30; p.fvg_min_atr = 0.3; p.fvg_buf_atr = 0.1;
    p.fvg_beyond_va = true; p.fvg_mode = 0;            // replace
    p.fvg_min_risk_atr = 0.5; p.fvg_max_risk_atr = 6.0; p.fvg_breakout_only = true;
    return p;
}

static void test_fvg_sl_short_replace() {
    auto p = fvg_base();
    auto m = mvp(/*vah*/110, /*val*/100, /*lo*/90, /*hi*/115);
    kk::SignalBar s{.o = 99.5, .h = 99.7, .l = 98.3, .c = 98.5, .atr2 = 2, .atr1 = 2, .entry_close = 99};
    kk::RegimeState r = trend_up(); r.plus = 10; r.minus = 30;
    auto sig = kk::detect_signal(p, m, m, kk::VPResult{}, r, s, NS, NS, NS);
    KK_CHECK(sig.valid && !sig.is_long);
    KK_CHECK_NEAR(sig.sl, 101.96, 1e-9);              // ATR stop before FVG
    // Bearish gap at k=4: high[4]=99.0 (bot), low[2]=99.9 (top); top in (entry99, val100].
    std::vector<kk::Bar> bars = { bar(105,104), bar(104,103), bar(102,99.9), bar(101,100), bar(99.0,98.0) };
    kk::apply_fvg_sl(p, sig, bars.data(), (int)bars.size(), /*sigBar*/4, /*atr*/2, /*vah*/110, /*val*/100);
    KK_CHECK_NEAR(sig.sl, 100.1, 1e-9);               // gap top 99.9 + 0.1*2 buffer
    KK_CHECK_NEAR(sig.risk, 1.1, 1e-9);
    KK_CHECK_NEAR(sig.tp1, 99 - 1.1 * 0.8, 1e-9);
    KK_CHECK_NEAR(sig.tp2, 99 - 1.1 * 1.8, 1e-9);
}

static void test_fvg_sl_long_replace() {
    auto p = fvg_base();
    auto m = mvp(/*vah*/99, /*val*/90, /*lo*/85, /*hi*/110);
    kk::SignalBar s{.o = 99.5, .h = 100.7, .l = 99.3, .c = 100.5, .atr2 = 2, .atr1 = 2, .entry_close = 100};
    auto sig = kk::detect_signal(p, m, m, kk::VPResult{}, trend_up(), s, NS, NS, NS);
    KK_CHECK(sig.valid && sig.is_long);
    KK_CHECK_NEAR(sig.sl, 97.04, 1e-9);
    // Bullish gap at k=4: low[4]=99.9 (top), high[2]=99.1 (bot); bot in [vah99, entry100).
    std::vector<kk::Bar> bars = { bar(95,94), bar(96,95), bar(99.1,98), bar(99.5,99.2), bar(100.5,99.9) };
    kk::apply_fvg_sl(p, sig, bars.data(), (int)bars.size(), /*sigBar*/4, /*atr*/2, /*vah*/99, /*val*/90);
    KK_CHECK_NEAR(sig.sl, 98.9, 1e-9);                // gap bottom 99.1 - 0.1*2 buffer
    KK_CHECK_NEAR(sig.risk, 1.1, 1e-9);
    KK_CHECK_NEAR(sig.tp1, 100 + 1.1 * 0.8, 1e-9);
    KK_CHECK_NEAR(sig.tp2, 100 + 1.1 * 1.8, 1e-9);
}

static void test_fvg_sl_default_off_and_mode_gate() {
    // (a) feature OFF -> byte-identical signal
    auto p = fvg_base(); p.enable_fvg_sl = false;
    auto m = mvp(110, 100, 90, 115);
    kk::SignalBar s{.o = 99.5, .h = 99.7, .l = 98.3, .c = 98.5, .atr2 = 2, .atr1 = 2, .entry_close = 99};
    kk::RegimeState r = trend_up(); r.plus = 10; r.minus = 30;
    auto sig = kk::detect_signal(p, m, m, kk::VPResult{}, r, s, NS, NS, NS);
    const double sl0 = sig.sl, risk0 = sig.risk;
    std::vector<kk::Bar> bars = { bar(105,104), bar(104,103), bar(102,99.9), bar(101,100), bar(99.0,98.0) };
    kk::apply_fvg_sl(p, sig, bars.data(), (int)bars.size(), 4, 2, 110, 100);
    KK_CHECK_NEAR(sig.sl, sl0, 1e-12);
    KK_CHECK_NEAR(sig.risk, risk0, 1e-12);
    // (b) widen-only mode rejects a TIGHTER gap (the short gap shrinks risk 2.96 -> 1.1)
    auto p2 = fvg_base(); p2.fvg_mode = 1;            // widen-only
    auto sig2 = kk::detect_signal(p2, m, m, kk::VPResult{}, r, s, NS, NS, NS);
    const double sl2 = sig2.sl;
    kk::apply_fvg_sl(p2, sig2, bars.data(), (int)bars.size(), 4, 2, 110, 100);
    KK_CHECK_NEAR(sig2.sl, sl2, 1e-12);              // unchanged (gap was tighter than ATR stop)
}

static void test_fvg_sl_require_gate() {
    // A short breakout with NO qualifying gap above entry. With fvg_require -> trade is dropped.
    auto p = fvg_base(); p.fvg_require = true; p.fvg_mode = 1;
    auto m = mvp(110, 100, 90, 115);
    kk::SignalBar s{.o = 99.5, .h = 99.7, .l = 98.3, .c = 98.5, .atr2 = 2, .atr1 = 2, .entry_close = 99};
    kk::RegimeState r = trend_up(); r.plus = 10; r.minus = 30;
    auto sig = kk::detect_signal(p, m, m, kk::VPResult{}, r, s, NS, NS, NS);
    KK_CHECK(sig.valid && !sig.is_long);
    std::vector<kk::Bar> flat = { bar(100,98), bar(100,98), bar(100,98), bar(100,98), bar(100,98) };
    kk::apply_fvg_sl(p, sig, flat.data(), (int)flat.size(), 4, 2, 110, 100);
    KK_CHECK(!sig.valid);                              // no structural gap -> breakout dropped
    // Same flat bars but require OFF -> trade survives with its ATR stop unchanged.
    auto p2 = fvg_base(); p2.fvg_require = false; p2.fvg_mode = 1;
    auto sig2 = kk::detect_signal(p2, m, m, kk::VPResult{}, r, s, NS, NS, NS);
    const double sl2 = sig2.sl;
    kk::apply_fvg_sl(p2, sig2, flat.data(), (int)flat.size(), 4, 2, 110, 100);
    KK_CHECK(sig2.valid);
    KK_CHECK_NEAR(sig2.sl, sl2, 1e-12);
}

static void run_all() {
    KK_RUN(test_breakout_long_economics);
    KK_RUN(test_breakout_short_economics);
    KK_RUN(test_anti_chase_ceiling_rejects);
    KK_RUN(test_no_breakout_when_balance_and_reversion_off);
    KK_RUN(test_reversion_long_when_enabled);
    KK_RUN(test_node_gate_blocks_long_when_selling);
    KK_RUN(test_fvg_sl_short_replace);
    KK_RUN(test_fvg_sl_long_replace);
    KK_RUN(test_fvg_sl_default_off_and_mode_gate);
    KK_RUN(test_fvg_sl_require_gate);
}

KK_TEST_MAIN()
