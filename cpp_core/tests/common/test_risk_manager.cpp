// Unit tests for RiskManager: budget, lot sizing (+ peak-DD soft block + min-lot guard),
// predictive daily-DD breaker, day reset, peak-DD halt, and cooldown arming/extension.
#include "kk/common/risk_manager.hpp"
#include "kk/common/test.hpp"

using kk::Params; using kk::RiskManager;

static Params specs() {
    Params p;
    p.start_balance = 10000.0;
    p.risk_unit = 0; p.risk_acc_pct = 0.9;          // 0.9% of balance = $90 budget
    p.contract_size = 1.0; p.tick_value = 0.0; p.tick_size = 0.0;  // vppl = 1.0
    p.lot_step = 0.01; p.min_lot = 0.01; p.broker_max_lot = 100.0;
    p.max_daily_dd_pct = 6.0; p.daily_dd_cooldown_hrs = 12.0;
    p.max_peak_dd_pct = 22.0; p.soft_block_dd_pct = 15.0; p.soft_block_lot_mult = 0.55;
    p.loss_streak_count = 3; p.loss_streak_cooldown_hrs = 4.0;
    p.skip_if_minlot_over_risk = false;
    return p;
}

static void test_budget_and_lot() {
    Params p = specs();
    RiskManager rm; rm.reset(p);
    KK_CHECK_NEAR(rm.risk_budget_usd(), 90.0, 1e-9);
    // stopDist = 50 price units, vppl = 1 -> raw lot = 90/50 = 1.8, normalized to 1.80.
    KK_CHECK_NEAR(rm.compute_lot(50.0, 10000.0), 1.80, 1e-9);
    KK_CHECK_NEAR(rm.compute_lot(0.0, 10000.0), 0.0, 1e-9);   // degenerate stop
}

static void test_soft_block_scales_lot() {
    Params p = specs();
    RiskManager rm; rm.reset(p);
    rm.update_peak(10000.0);
    // equity at 16% drawdown (>=15 soft block, <22 halt) -> lot * 0.55.
    const double eq = 8400.0;  // (10000-8400)/10000 = 16%
    KK_CHECK(!rm.is_peak_dd_halt(eq));
    KK_CHECK_NEAR(rm.peak_dd_lot_mult(eq), 0.55, 1e-9);
    KK_CHECK_NEAR(rm.compute_lot(50.0, eq), p.normalize_lot(1.8 * 0.55), 1e-9);  // 0.99
}

static void test_peak_dd_halt() {
    Params p = specs();
    RiskManager rm; rm.reset(p);
    rm.update_peak(10000.0);
    KK_CHECK(rm.is_peak_dd_halt(7700.0));    // 23% > 22% -> halt
    KK_CHECK(!rm.is_peak_dd_halt(8000.0));   // 20% < 22%
}

static void test_min_lot_over_risk_guard() {
    Params p = specs();
    p.skip_if_minlot_over_risk = true;
    p.min_lot = 1.0;                          // big min lot forces over-risk on a tiny budget
    RiskManager rm; rm.reset(p);
    // budget=90, stop=50, vppl=1 -> raw 1.8 lot; min 1.0 ok here (actual risk 90 == budget) -> allowed.
    KK_CHECK(rm.compute_lot(50.0, 10000.0) > 0.0);
    // stop=200 -> raw 0.45 lot, min floors to 1.0 -> actual risk = 1.0*200 = 200 > 90 -> skip.
    KK_CHECK_NEAR(rm.compute_lot(200.0, 10000.0), 0.0, 1e-9);
}

static void test_daily_dd_predictive_and_reset() {
    Params p = specs();
    RiskManager rm; rm.reset(p);
    rm.seed_day_if_new(20260409, 10000.0);
    // (10000 - 9500 + 100)/10000*100 = 6.0 >= 6 -> hit.
    KK_CHECK(rm.is_daily_dd_hit(9500.0, 100.0));
    KK_CHECK(!rm.is_daily_dd_hit(9600.0, 100.0));   // 5.0% < 6%
    // New UTC day reseeds day-start equity, clearing the prior drop.
    rm.seed_day_if_new(20260410, 9500.0);
    KK_CHECK(!rm.is_daily_dd_hit(9500.0, 100.0));    // day-start now 9500
}

static void test_loss_streak_cooldown() {
    Params p = specs();
    RiskManager rm; rm.reset(p);
    const int64_t t0 = 1000000;
    rm.register_trade_close(-10.0, t0);
    rm.register_trade_close(-10.0, t0);
    KK_CHECK(!rm.is_in_cooldown(t0 + 1));            // 2 losses, no cooldown yet
    rm.register_trade_close(-10.0, t0);              // 3rd loss -> arm 4h
    KK_CHECK(rm.is_in_cooldown(t0 + 1));
    KK_CHECK(rm.is_in_cooldown(t0 + 3 * 3600 * 1000));
    KK_CHECK(!rm.is_in_cooldown(t0 + 5 * 3600 * 1000));   // expired after 4h
    KK_CHECK_NEAR(rm.balance(), p.start_balance - 30.0, 1e-9);
    // a win resets the streak counter.
    rm.register_trade_close(20.0, t0);
    KK_CHECK(rm.consecutive_losses() == 0);
}

static void test_cooldown_extend_only() {
    Params p = specs();
    RiskManager rm; rm.reset(p);
    rm.arm_cooldown(0, 4.0);                          // until 4h
    rm.arm_cooldown(0, 1.0);                          // shorter -> ignored
    KK_CHECK(rm.is_in_cooldown(3 * 3600 * 1000));     // still in the 4h window
}

void run_all() {
    KK_RUN(test_budget_and_lot);
    KK_RUN(test_soft_block_scales_lot);
    KK_RUN(test_peak_dd_halt);
    KK_RUN(test_min_lot_over_risk_guard);
    KK_RUN(test_daily_dd_predictive_and_reset);
    KK_RUN(test_loss_streak_cooldown);
    KK_RUN(test_cooldown_extend_only);
}

KK_TEST_MAIN()
