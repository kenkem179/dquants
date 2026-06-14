// Unit tests for PositionManager (TP1 partial / BE-after-TP1 / chandelier trail / SL / TP).
// Synthetic tick streams exercise each exit path; assertions are broker-spec-independent where
// possible (exitTag, mfeR/maeR) plus a $ check with explicit specs.
#include "kk/common/position_manager.hpp"
#include "kk/common/test.hpp"

using kk::Params; using kk::Signal; using kk::PositionManager; using kk::ExitTag;

static Params make_params() {
    Params p;
    p.pip_size = 0.01; p.mintick = 0.01;
    p.contract_size = 1.0;            // BTCUSD: 1 lot = 1 unit (value_per_price_per_lot = 1)
    p.lot_step = 0.01; p.min_lot = 0.01; p.broker_max_lot = 100.0;
    p.commission_per_lot = 0.0;
    p.tp1_close_pct = 20.0; p.tp1_r = 0.8;
    p.be_after_tp1 = true; p.be_buf_atr = 0.05;
    p.trail_runner = true; p.runner_rr = 10.0; p.trail_atr_mult = 3.6;
    return p;
}

// A long that immediately runs against us and hits the initial SL -> SL-LOSS.
static void test_long_sl_loss() {
    Params p = make_params();
    Signal sig; sig.valid = true; sig.is_long = true; sig.entry = 100.0;
    sig.sl = 90.0; sig.risk = 10.0; sig.tp1 = 108.0; sig.tp2 = 114.0; sig.reason = "L-BRK";

    PositionManager pm;
    KK_CHECK(pm.open_position(p, sig, /*fill*/100.0, /*lot*/1.0, /*ts*/0, /*sess*/2, /*spread*/0.5, /*atr1*/4.0));
    // price drifts down to the stop.
    bool closed = false;
    for (double px = 99.0; px >= 88.0 && !closed; px -= 1.0) closed = pm.on_tick(px, px, 4.0);
    KK_CHECK(closed);
    KK_CHECK(pm.record().exit_tag == ExitTag::SL_LOSS);
    KK_CHECK_NEAR(pm.record().realized_usd, -10.0, 1e-9);      // (90-100)*1*1
    KK_CHECK_NEAR(pm.record().mae_r, 1.0, 1e-6);               // hit exactly -1R
    KK_CHECK(pm.record().mfe_r <= 0.0 + 1e-9);
}

// A long that reaches TP1 (partial), arms BE+trail, then the trail stop catches it in profit -> SL-WIN.
static void test_long_tp1_then_trail_win() {
    Params p = make_params();
    Signal sig; sig.valid = true; sig.is_long = true; sig.entry = 100.0;
    sig.sl = 90.0; sig.risk = 10.0; sig.tp1 = 108.0; sig.tp2 = 114.0; sig.reason = "L-BRK";

    PositionManager pm;
    KK_CHECK(pm.open_position(p, sig, 100.0, 1.0, 0, 2, 0.5, 4.0));
    // Rally well past TP1 (108) up to 130 with atr=4 -> trail_dist = 14.4.
    bool closed = false;
    for (double px = 101.0; px <= 130.0 && !closed; px += 1.0) closed = pm.on_tick(px, px, 4.0);
    KK_CHECK(!closed);                          // backstop TP is 100+10*10=200, not hit; trail active
    // Now pull back: from 130, trail sat near 130-14.4=115.6; a drop through that closes in profit.
    for (double px = 129.0; px >= 110.0 && !closed; px -= 1.0) closed = pm.on_tick(px, px, 4.0);
    KK_CHECK(closed);
    KK_CHECK(pm.record().exit_tag == ExitTag::SL_WIN);
    KK_CHECK(pm.record().realized_usd > 0.0);   // 20% booked at 108 + 80% trailed out >100
    KK_CHECK_NEAR(pm.record().mfe_r, 3.0, 1e-6); // peaked at 130 => +30 favorable = 3R
}

// A short whose backstop TP (entry - risk*runnerRr) is reached -> TP.
static void test_short_backstop_tp() {
    Params p = make_params();
    p.runner_rr = 2.0;                           // small backstop so the test reaches it
    Signal sig; sig.valid = true; sig.is_long = false; sig.entry = 100.0;
    sig.sl = 110.0; sig.risk = 10.0; sig.tp1 = 92.0; sig.tp2 = 86.0; sig.reason = "S-BRK";

    PositionManager pm;
    KK_CHECK(pm.open_position(p, sig, 100.0, 1.0, 0, 1, 0.5, 4.0));
    // backstop TP = 100 - 10*2 = 80.
    bool closed = false;
    for (double px = 99.0; px >= 78.0 && !closed; px -= 1.0) closed = pm.on_tick(px, px, 4.0);
    KK_CHECK(closed);
    KK_CHECK(pm.record().exit_tag == ExitTag::TP);
    KK_CHECK_NEAR(pm.record().mfe_r, 2.0, 1e-6); // reached 80 => +20 favorable = 2R for a short
}

// Trail only ever tightens: a deeper pullback after a higher peak must not loosen the stop.
static void test_trail_only_tightens() {
    Params p = make_params();
    Signal sig; sig.valid = true; sig.is_long = true; sig.entry = 100.0;
    sig.sl = 90.0; sig.risk = 10.0; sig.tp1 = 108.0; sig.tp2 = 114.0; sig.reason = "L-BRK";

    PositionManager pm;
    KK_CHECK(pm.open_position(p, sig, 100.0, 1.0, 0, 2, 0.5, 4.0));
    bool closed = false;
    for (double px = 101.0; px <= 140.0 && !closed; px += 1.0) closed = pm.on_tick(px, px, 4.0); // peak 140
    KK_CHECK(!closed);
    // small dip that should NOT trigger (stop sat ~140-14.4=125.6); 128 stays above stop.
    closed = pm.on_tick(128.0, 128.0, 4.0);
    KK_CHECK(!closed);
    // drop through the ratcheted stop closes in solid profit.
    for (double px = 126.0; px >= 120.0 && !closed; px -= 1.0) closed = pm.on_tick(px, px, 4.0);
    KK_CHECK(closed);
    KK_CHECK(pm.record().exit_tag == ExitTag::SL_WIN);
    KK_CHECK_NEAR(pm.record().mfe_r, 4.0, 1e-6); // peaked at 140 = +40 = 4R
}

void run_all() {
    KK_RUN(test_long_sl_loss);
    KK_RUN(test_long_tp1_then_trail_win);
    KK_RUN(test_short_backstop_tp);
    KK_RUN(test_trail_only_tightens);
}

KK_TEST_MAIN()
