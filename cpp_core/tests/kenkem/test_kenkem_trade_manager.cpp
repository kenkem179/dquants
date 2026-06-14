// P6: risk-based sizing + management (SL / TP / partial->BE->trail).
#include "kk/kenkem/trade_manager.hpp"
#include "kk/common/test.hpp"
#include <vector>

using std::vector;
using namespace kk::kenkem;

void test_sizing_is_risk_correct() {
    KenKemConfig c; c.apply_xauusd_specs();   // vppl = 100
    double bal = 10000.0;
    // E1 ratio 0.021, risk 4.0 price -> lot = 10000*0.021/(4*100) = 0.525 -> 0.53 (step 0.01)
    double lot = position_size(bal, 1, 4.0, c);
    KK_CHECK_NEAR(lot, 0.53, 1e-9);
    // Loss at full SL ~= balance * ratio.
    double lossUSD = lot * 4.0 * c.value_per_price_per_lot();
    KK_CHECK(lossUSD > 200.0 && lossUSD < 220.0);   // ~210
    // Wider stop -> smaller lot (fixed-fractional risk).
    KK_CHECK(position_size(bal, 1, 8.0, c) < lot);
}

void test_full_sl_and_tp() {
    KenKemConfig c;
    vector<Fill> fills;
    Position p = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c);
    manage_tick(p, 95.0, c, fills);      // gap below SL
    KK_CHECK(!p.open && fills.size() == 1 && fills[0].reason == 'S');
    KK_CHECK_NEAR(fills[0].price, 96.0, 1e-9);

    fills.clear();
    Position q = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c);
    manage_tick(q, 109.0, c, fills);     // through TP
    KK_CHECK(!q.open && fills.size() == 1 && fills[0].reason == 'T');
    KK_CHECK_NEAR(fills[0].price, 108.0, 1e-9);
}

void test_partial_be_trail_sequence() {
    KenKemConfig c; c.pip_size = 0.01;   // E1: trigger 0.90, ratio 0.20, be 0.07, trail 0.40
    vector<Fill> fills;
    Position p = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c);  // risk 4
    // price reaches 107.5 (>= 90% trigger 107.2): partial 0.2 @107.5, BE+, trail to 107.5-1.6=105.9
    manage_tick(p, 107.5, c, fills);
    KK_CHECK(p.open && p.partial_done);
    KK_CHECK(fills.size() == 1 && fills[0].reason == 'P');
    KK_CHECK_NEAR(fills[0].lot, 0.20, 1e-9);
    KK_CHECK_NEAR(p.lot, 0.80, 1e-9);
    KK_CHECK_NEAR(p.sl, 105.9, 1e-6);    // trail locked above breakeven
    // Pullback to 105.8 stops out the runner at the trailed SL (in profit).
    manage_tick(p, 105.8, c, fills);
    KK_CHECK(!p.open && fills.size() == 2 && fills[1].reason == 'S');
    KK_CHECK_NEAR(fills[1].price, 105.9, 1e-6);
    KK_CHECK_NEAR(fills[1].lot, 0.80, 1e-9);
    // Both fills are net profitable vs entry 100.
    KK_CHECK(fill_points(p, fills[0]) > 0 && fill_points(p, fills[1]) > 0);
}

void test_short_sl() {
    KenKemConfig c;
    vector<Fill> fills;
    Position p = open_position(false, 1, 100.0, 104.0, 92.0, 1.0, c);  // short
    manage_tick(p, 105.0, c, fills);
    KK_CHECK(!p.open && fills[0].reason == 'S');
    KK_CHECK_NEAR(fills[0].price, 104.0, 1e-9);
}

void run_all() {
    KK_RUN(test_sizing_is_risk_correct);
    KK_RUN(test_full_sl_and_tp);
    KK_RUN(test_partial_be_trail_sequence);
    KK_RUN(test_short_sl);
}

KK_TEST_MAIN()
