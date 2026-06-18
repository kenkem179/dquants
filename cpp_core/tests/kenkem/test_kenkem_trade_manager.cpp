// P6/A7: risk-based sizing + EA-FAITHFUL management (broker SL/TP, R-mult BE, smart-partial-on-retrace,
// origTPDist trail, 3-stage ladder). Mirrors canonical KenKemExpert.mq5 (KENKEM-EXIT-PARITY-SPEC.md).
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
    double lossUSD = lot * 4.0 * c.value_per_price_per_lot();
    KK_CHECK(lossUSD > 200.0 && lossUSD < 220.0);   // ~210
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

void test_short_sl() {
    KenKemConfig c;
    vector<Fill> fills;
    Position p = open_position(false, 1, 100.0, 104.0, 92.0, 1.0, c);  // short
    manage_tick(p, 105.0, c, fills);
    KK_CHECK(!p.open && fills[0].reason == 'S');
    KK_CHECK_NEAR(fills[0].price, 104.0, 1e-9);
}

// (D) R-multiple SL->BE fires at R>=R_MULT_BE_TRIGGER (0.87) INDEPENDENT of any partial. origRisk=4,
// trigger pnl=3.48; at 103.5 -> R=0.875 -> SL=entry+origRisk*R_MULT_BE_BUFFER = 100 + 4*0.055 = 100.22.
void test_rmultiple_be() {
    KenKemConfig c;
    vector<Fill> fills;
    Position p = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c);
    manage_tick(p, 103.5, c, fills);
    KK_CHECK(p.open && fills.empty());
    KK_CHECK(p.rmult_be_applied && p.sl_moved_to_be);
    KK_CHECK_NEAR(p.sl, 100.22, 1e-9);
    // Below trigger -> no BE move.
    vector<Fill> f2; Position q = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c);
    manage_tick(q, 103.0, c, f2);        // R=0.75 < 0.87
    KK_CHECK(!q.rmult_be_applied && q.sl == 96.0);
}

// (F) Smart partial: eligible at >=0.90*origTPDist (=7.2 -> price 107.2), but DOES NOT fire until a
// retrace >= PARTIAL_TP_RETRACE_RATIO (0.15) from the peak-since-eligible. Single touch never fills.
void test_smart_partial_waits_for_retrace() {
    KenKemConfig c;
    vector<Fill> fills;
    Position p = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c);  // origTPDist 8
    manage_tick(p, 107.5, c, fills);     // eligible, peak=107.5, retrace 0 -> NO partial
    KK_CHECK(p.open && p.partial_eligible && !p.partial_done && fills.empty());
    manage_tick(p, 107.0, c, fills);     // retrace 0.5/7.5 = 0.067 < 0.15 -> still no
    KK_CHECK(!p.partial_done && fills.empty());
    manage_tick(p, 106.3, c, fills);     // retrace 1.2/7.5 = 0.16 >= 0.15 -> partial fills @106.3
    KK_CHECK(p.partial_done && fills.size() == 1 && fills[0].reason == 'P');
    KK_CHECK_NEAR(fills[0].price, 106.3, 1e-9);
    KK_CHECK_NEAR(fills[0].lot, 0.20, 1e-9);          // 1.0 * E1 ratio 0.20
    KK_CHECK_NEAR(p.lot, 0.80, 1e-9);
    // SL is the higher of BE (100+8*0.07=100.56) and the origTPDist trail (best 107.5 - 8*0.40 = 104.3).
    KK_CHECK_NEAR(p.sl, 104.3, 1e-6);
}

// (T) The origTPDist trail engages as soon as ELIGIBLE (even before a partial fills): best - origTPDist*0.40.
void test_trail_engages_on_eligible() {
    KenKemConfig c;
    vector<Fill> fills;
    Position p = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c);
    manage_tick(p, 107.5, c, fills);     // eligible -> trail to 107.5 - 8*0.40 = 104.3
    KK_CHECK(p.open && !p.partial_done);
    KK_CHECK_NEAR(p.sl, 104.3, 1e-6);
}

// (G) 3-stage ladder — only after a partial, and only once profit exceeds StageN*origTPDist (>=1.05x), i.e.
// ABOVE the original TP. In the live engine this needs a prior TP-extension (P3); here we simulate the
// extended TP (p.tp pushed out, orig_tp held). Stage 3 at +17.4: SL = live - StageN_trail*profit.
void test_ladder_engages_above_orig_tp() {
    KenKemConfig c; c.e1_trailing_factor = 2.0;   // loosen the origTPDist trail so the ladder dominates
    vector<Fill> fills;
    Position p = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c);  // origTPDist 8
    p.tp = 130.0;                       // simulate an extended TP; orig_tp stays 108 (origTPDist 8)
    p.partial_eligible = true; p.partial_done = true;   // ladder requires a taken partial
    manage_tick(p, 117.4, c, fills);    // pnl_live 17.4 >= stage3 1.17*8=9.36 -> stage 3 (trail ratio 0.65)
    KK_CHECK(p.open && p.ladder_stage == 3);
    // ladder SL = 117.4 - 0.65*17.4 = 106.09 ; loose trail = 117.4 - 16 = 101.4 -> ladder wins
    KK_CHECK_NEAR(p.sl, 106.09, 1e-6);
}

// Partial slice rounds to the broker volume step (EA NormalizeLotSize): 0.13*0.20=0.026 -> 0.03.
void test_partial_slice_rounds_to_step() {
    KenKemConfig c;
    vector<Fill> fills;
    Position p = open_position(true, 1, 100.0, 96.0, 108.0, 0.13, c);
    manage_tick(p, 107.5, c, fills);     // eligible
    manage_tick(p, 106.0, c, fills);     // retrace 1.5/7.5 = 0.20 -> partial
    KK_CHECK(p.partial_done && fills.size() == 1 && fills[0].reason == 'P');
    KK_CHECK_NEAR(fills[0].lot, 0.03, 1e-9);
    KK_CHECK_NEAR(p.lot, 0.10, 1e-9);
}

// A sub-step slice is bumped UP to min_lot and still closes (EA clamps volToClose to SYMBOL_VOLUME_MIN):
// 0.02*0.20=0.004 -> round 0 -> bumped to 0.01 -> closes 0.01, runner 0.01.
void test_partial_sub_min_bumps_to_min() {
    KenKemConfig c;
    vector<Fill> fills;
    Position p = open_position(true, 1, 100.0, 96.0, 108.0, 0.02, c);
    manage_tick(p, 107.5, c, fills);
    manage_tick(p, 106.0, c, fills);     // retrace 0.20 -> partial
    KK_CHECK(p.partial_done && fills.size() == 1);
    KK_CHECK_NEAR(fills[0].lot, 0.01, 1e-9);
    KK_CHECK_NEAR(p.lot, 0.01, 1e-9);
}

// (C2) A SL move within the broker min-stop-distance is refused (EA okDist). With stops_level_price=10,
// both BE and the trail are too close to price, so SL stays at 96 while the partial still fills.
void test_stops_level_blocks_sl_move() {
    KenKemConfig c; c.stops_level_price = 10.0;
    vector<Fill> fills;
    Position p = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c);
    manage_tick(p, 107.5, c, fills);     // eligible; trail move (Δ3.2) blocked
    manage_tick(p, 106.0, c, fills);     // partial fires (unaffected); BE/trail moves blocked
    KK_CHECK(p.partial_done && fills.size() == 1 && fills[0].reason == 'P');
    KK_CHECK_NEAR(p.sl, 96.0, 1e-9);
    // Sanity: with stops_level 0 the trail DOES move.
    KenKemConfig c0; vector<Fill> f0;
    Position q = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c0);
    manage_tick(q, 107.5, c0, f0);
    KK_CHECK_NEAR(q.sl, 104.3, 1e-6);
}

// Entry-bar gate: with manage_allowed=false the EA skips ALL management (no BE/partial/trail), but the
// broker still fills SL/TP. (barsSinceEntry==0 rule.)
void test_entry_bar_skips_management_not_sltp() {
    KenKemConfig c;
    vector<Fill> fills;
    Position p = open_position(true, 1, 100.0, 96.0, 108.0, 1.0, c);
    manage_tick(p, 107.5, 107.5, c, fills, /*manage_allowed=*/false);  // no partial/trail on entry bar
    KK_CHECK(p.open && !p.partial_eligible && !p.partial_done && fills.empty() && p.sl == 96.0);
    // But SL still fills even on the entry bar.
    manage_tick(p, 95.0, 95.0, c, fills, /*manage_allowed=*/false);
    KK_CHECK(!p.open && fills.size() == 1 && fills[0].reason == 'S');
}

void run_all() {
    KK_RUN(test_sizing_is_risk_correct);
    KK_RUN(test_full_sl_and_tp);
    KK_RUN(test_short_sl);
    KK_RUN(test_rmultiple_be);
    KK_RUN(test_smart_partial_waits_for_retrace);
    KK_RUN(test_trail_engages_on_eligible);
    KK_RUN(test_ladder_engages_above_orig_tp);
    KK_RUN(test_partial_slice_rounds_to_step);
    KK_RUN(test_partial_sub_min_bumps_to_min);
    KK_RUN(test_stops_level_blocks_sl_move);
    KK_RUN(test_entry_bar_skips_management_not_sltp);
}

KK_TEST_MAIN()
