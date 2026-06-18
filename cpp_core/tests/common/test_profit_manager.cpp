// Unit tests for kk::common::ProfitManager (profit_manager.hpp).
// Each toggle is exercised in isolation (the others OFF), both long and short, plus the all-OFF inert case.
#include "kk/common/profit_manager.hpp"
#include "kk/common/test.hpp"

using kk::common::PMConfig;
using kk::common::PMState;
using kk::common::PMActions;
using kk::common::pm_evaluate;

// A long trade: entry 100, initial SL 90 (risk 10), TP 130, ATR 5.
static PMState base_long() {
    PMState s;
    s.is_long = true; s.entry = 100.0; s.sl = 90.0; s.tp = 130.0;
    s.cur_price = 100.0; s.best_price = 100.0; s.risk = 10.0; s.atr = 5.0;
    return s;
}
// Mirror short: entry 100, SL 110 (risk 10), TP 70.
static PMState base_short() {
    PMState s;
    s.is_long = false; s.entry = 100.0; s.sl = 110.0; s.tp = 70.0;
    s.cur_price = 100.0; s.best_price = 100.0; s.risk = 10.0; s.atr = 5.0;
    return s;
}

static void test_all_off_is_inert() {
    PMConfig c;  // everything default OFF
    PMState s = base_long();
    s.cur_price = 125.0; s.best_price = 128.0;  // deep in profit
    PMActions a = pm_evaluate(s, c);
    KK_CHECK_NEAR(a.sl, s.sl, 1e-12);
    KK_CHECK_NEAR(a.tp, s.tp, 1e-12);
    KK_CHECK_NEAR(a.partial_frac, 0.0, 1e-12);
}

static void test_be_protect() {
    PMConfig c; c.be_protect = true; c.be_trigger_r = 1.0; c.be_buffer_r = 0.10;
    PMState s = base_long();
    // below trigger: no move (gain 0.5R)
    s.cur_price = 105.0; s.best_price = 105.0;
    KK_CHECK_NEAR(pm_evaluate(s, c).sl, 90.0, 1e-12);
    // at 1R (price 110): SL -> entry + 0.10*risk = 101
    s.cur_price = 110.0; s.best_price = 110.0;
    KK_CHECK_NEAR(pm_evaluate(s, c).sl, 101.0, 1e-12);
    // short mirror: at 1R (price 90) -> SL = entry - 1 = 99
    PMState ss = base_short(); ss.cur_price = 90.0; ss.best_price = 90.0;
    KK_CHECK_NEAR(pm_evaluate(ss, c).sl, 99.0, 1e-12);
}

static void test_progressive_trail() {
    PMConfig c; c.prog_trail = true; c.prog_trigger_r = 1.0; c.prog_increment_r = 0.5; c.prog_step_r = 0.10;
    PMState s = base_long();
    // at exactly 1R: shift 0 -> SL to entry (100)
    s.cur_price = 110.0; s.best_price = 110.0;
    KK_CHECK_NEAR(pm_evaluate(s, c).sl, 100.0, 1e-12);
    // at 2R (price 120): over=1.0, steps=floor(1.0/0.5)=2, shift=0.20*10=2 -> SL 102
    s.cur_price = 120.0; s.best_price = 120.0;
    KK_CHECK_NEAR(pm_evaluate(s, c).sl, 102.0, 1e-12);
    // below trigger: untouched
    s.cur_price = 104.0; s.best_price = 104.0;
    KK_CHECK_NEAR(pm_evaluate(s, c).sl, 90.0, 1e-12);
}

static void test_giveback_cap() {
    PMConfig c; c.giveback = true; c.giveback_arm_r = 2.0; c.giveback_cap_frac = 0.30;
    PMState s = base_long();
    // peak 3R (best 130) but armed: lock 70% of peak gain (30) -> 21 -> SL 121
    s.best_price = 130.0; s.cur_price = 124.0;
    KK_CHECK_NEAR(pm_evaluate(s, c).sl, 121.0, 1e-12);
    // not yet armed (peak 1.5R): no move
    PMState s2 = base_long(); s2.best_price = 115.0; s2.cur_price = 112.0;
    KK_CHECK_NEAR(pm_evaluate(s2, c).sl, 90.0, 1e-12);
    // short mirror: peak 3R (best 70), lock 70% -> SL = 100 - 21 = 79
    PMState ss = base_short(); ss.best_price = 70.0; ss.cur_price = 76.0;
    KK_CHECK_NEAR(pm_evaluate(ss, c).sl, 79.0, 1e-12);
}

static void test_tp_extension() {
    PMConfig c; c.tp_extension = true; c.tp_ext_progress = 0.90; c.tp_ext_atr_mult = 1.0; c.tp_ext_max = 5;
    PMState s = base_long();  // entry 100, tp 130, total 30; ATR 5
    // progress 95% (price 128.5 -> covered 28.5/30): extend by 1*ATR -> TP 135
    s.cur_price = 128.5;
    KK_CHECK_NEAR(pm_evaluate(s, c).tp, 135.0, 1e-12);
    // progress only 50% (price 115): no extension
    s.cur_price = 115.0;
    KK_CHECK_NEAR(pm_evaluate(s, c).tp, 130.0, 1e-12);
    // trend weakening: no extension even when near TP
    s.cur_price = 128.5; s.trend_weakening = true;
    KK_CHECK_NEAR(pm_evaluate(s, c).tp, 130.0, 1e-12);
    // at cap: no extension
    s.trend_weakening = false; s.tp_extensions = 5;
    KK_CHECK_NEAR(pm_evaluate(s, c).tp, 130.0, 1e-12);
}

static void test_partial_tp() {
    PMConfig c; c.partial_tp = true; c.partial_trigger_r = 1.0; c.partial_frac = 0.5;
    PMState s = base_long();
    // below trigger
    s.cur_price = 105.0;
    KK_CHECK_NEAR(pm_evaluate(s, c).partial_frac, 0.0, 1e-12);
    // at 1R: request half
    s.cur_price = 110.0;
    KK_CHECK_NEAR(pm_evaluate(s, c).partial_frac, 0.5, 1e-12);
    // already done: no repeat
    s.partial_done = true;
    KK_CHECK_NEAR(pm_evaluate(s, c).partial_frac, 0.0, 1e-12);
}

static void test_pre_be_structure() {
    PMConfig c; c.pre_be_structure = true; c.pre_be_trigger_r = 0.5; c.pre_be_buffer = 0.5;
    PMState s = base_long();  // entry 100, SL 90
    // armed at 0.5R (price 105), structure (prior swing low) at 96 -> SL = 96 - 0.5 = 95.5 (< entry)
    s.cur_price = 105.0; s.best_price = 105.0; s.structure_level = 96.0;
    KK_CHECK_NEAR(pm_evaluate(s, c).sl, 95.5, 1e-12);
    // structure above entry would be clamped strictly below entry (never crosses to profit-lock)
    s.structure_level = 102.0;
    PMActions a = pm_evaluate(s, c);
    KK_CHECK(a.sl < s.entry);
    // be already done: skip
    PMState s2 = base_long(); s2.cur_price = 105.0; s2.structure_level = 96.0; s2.be_done = true;
    KK_CHECK_NEAR(pm_evaluate(s2, c).sl, 90.0, 1e-12);
}

static void test_compose_tighten_only() {
    // be_protect + giveback both ON: result is the tightest candidate, never loosens.
    PMConfig c; c.be_protect = true; c.be_trigger_r = 1.0; c.be_buffer_r = 0.0;
    c.giveback = true; c.giveback_arm_r = 2.0; c.giveback_cap_frac = 0.30;
    PMState s = base_long();
    s.best_price = 130.0; s.cur_price = 124.0;  // be wants 100, giveback wants 121 -> keep 121
    KK_CHECK_NEAR(pm_evaluate(s, c).sl, 121.0, 1e-12);
}

void run_all() {
    KK_RUN(test_all_off_is_inert);
    KK_RUN(test_be_protect);
    KK_RUN(test_progressive_trail);
    KK_RUN(test_giveback_cap);
    KK_RUN(test_tp_extension);
    KK_RUN(test_partial_tp);
    KK_RUN(test_pre_be_structure);
    KK_RUN(test_compose_tighten_only);
}

KK_TEST_MAIN()
