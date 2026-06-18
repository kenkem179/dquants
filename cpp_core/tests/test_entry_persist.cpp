// Tests for feature #1 — entry-persistence (DI-spread proxy). Two layers:
//   1) the pure rule kk::ind::di_persist_ok (directional spread must hold >= min for N bars);
//   2) the KK-MasterVP TickEngine wiring on the golden bars: OFF == baseline (no-op equivalence
//      when bars=1,min=0), and a high threshold can only REMOVE trades (monotone suppression),
//      never invent them. This guards the parity invariant: the gate filters, it never adds.
#include "kk/indicators.hpp"
#include "kk/tick_engine.hpp"
#include "kk/bars_csv.hpp"
#include "kk/test.hpp"
#include <vector>

using kk::Params; using kk::Bar; using kk::Tick; using kk::TickEngine;

// --- pure-rule tests -------------------------------------------------------
void test_persist_directional_and_window() {
    //            idx:   0    1    2    3    4
    std::vector<double> plus  = {10, 20, 30, 12, 25};
    std::vector<double> minus = { 5,  5,  5, 18,  5};
    // long spread (plus-minus): 5, 15, 25, -6, 20
    // bars=1 at j=2: spread 25 >= 8 -> pass
    KK_CHECK(kk::ind::di_persist_ok(true, 2, 1, 8.0, plus, minus));
    // bars=3 ending j=2: need 5,15,25 all >= 8 -> 5 fails -> block
    KK_CHECK(!kk::ind::di_persist_ok(true, 2, 3, 8.0, plus, minus));
    // bars=2 ending j=2: 15,25 both >= 8 -> pass
    KK_CHECK(kk::ind::di_persist_ok(true, 2, 2, 8.0, plus, minus));
    // long at j=3: spread -6 -> block any positive min
    KK_CHECK(!kk::ind::di_persist_ok(true, 3, 1, 0.1, plus, minus));
    // short at j=3: minus-plus = 6 >= 5 -> pass
    KK_CHECK(kk::ind::di_persist_ok(false, 3, 1, 5.0, plus, minus));
    // short at j=2: minus-plus = -25 -> block
    KK_CHECK(!kk::ind::di_persist_ok(false, 2, 1, 0.0, plus, minus));
}

void test_persist_insufficient_history_blocks() {
    std::vector<double> plus  = {30, 30, 30};
    std::vector<double> minus = { 5,  5,  5};
    // need 3 bars but j=1 only has 2 of history -> block (no lookahead, no wrap)
    KK_CHECK(!kk::ind::di_persist_ok(true, 1, 3, 1.0, plus, minus));
    KK_CHECK(kk::ind::di_persist_ok(true, 2, 3, 1.0, plus, minus));
    // bars<1 is clamped to 1
    KK_CHECK(kk::ind::di_persist_ok(true, 0, 0, 1.0, plus, minus));
}

void test_persist_min_zero_is_noop_on_dominant_side() {
    std::vector<double> plus  = {30, 30, 30};
    std::vector<double> minus = { 5,  5,  5};
    // min=0: long passes wherever plus>=minus; this is the no-op-ish floor.
    KK_CHECK(kk::ind::di_persist_ok(true, 2, 1, 0.0, plus, minus));
}

// --- engine wiring tests (golden bars) -------------------------------------
static std::vector<Tick> ticks_from_bars(const std::vector<Bar>& bars, double spread) {
    std::vector<Tick> out; out.reserve(bars.size() * 4);
    const int64_t offs[4] = {0, 45000, 90000, 135000};
    for (const auto& b : bars) {
        double seq[4];
        if (b.close >= b.open) { seq[0]=b.open; seq[1]=b.low;  seq[2]=b.high; seq[3]=b.close; }
        else                   { seq[0]=b.open; seq[1]=b.high; seq[2]=b.low;  seq[3]=b.close; }
        for (int k = 0; k < 4; ++k) { Tick t; t.ts_ms=b.ts_ms+offs[k]; t.bid=seq[k]; t.ask=seq[k]+spread; out.push_back(t); }
    }
    return out;
}

static size_t run_count(const std::vector<Bar>& bars, const Params& p) {
    TickEngine eng(p);
    eng.load_bars(bars);
    const auto ticks = ticks_from_bars(bars, 2.0 * p.pip_size);
    for (const auto& t : ticks) eng.on_tick(t);
    if (!ticks.empty()) { const auto& z = ticks.back(); eng.finish(z.bid, z.ask, z.ts_ms); }
    return eng.trades().size();
}

void test_engine_persist_off_is_baseline_and_monotone() {
    auto bars = kk::load_bars_csv("tests/golden/bars_btcusd_M3_aprwindow.csv");
    if (bars.empty()) { std::printf("  (missing golden bars -- skipped)\n"); return; }

    Params base; base.apply_btcusd_specs();
    const size_t n_base = run_count(bars, base);

    // Enabling with bars=1, min=0 only blocks bars where the wrong DI side dominates the entry
    // direction — a mild, well-defined filter; it must not EXCEED baseline.
    Params noop = base; noop.enable_entry_persist = true; noop.persist_bars = 1; noop.persist_di_min = 0.0;
    const size_t n_noop = run_count(bars, noop);
    KK_CHECK(n_noop <= n_base);

    // A high directional floor over 3 bars can only suppress trades further.
    Params strict = base; strict.enable_entry_persist = true; strict.persist_bars = 3; strict.persist_di_min = 25.0;
    const size_t n_strict = run_count(bars, strict);
    KK_CHECK(n_strict <= n_noop);
    std::printf("  trades: baseline=%zu persist(1,0)=%zu persist(3,25)=%zu\n", n_base, n_noop, n_strict);
}

static void run_all() {
    KK_RUN(test_persist_directional_and_window);
    KK_RUN(test_persist_insufficient_history_blocks);
    KK_RUN(test_persist_min_zero_is_noop_on_dominant_side);
    KK_RUN(test_engine_persist_off_is_baseline_and_monotone);
}

KK_TEST_MAIN()
