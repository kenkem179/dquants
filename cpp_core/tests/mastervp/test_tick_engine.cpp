// Integration test for the TickEngine: replay a synthetic tick stream built from the
// known-good golden bar fixture (BTCUSD M3, the same bars the parity golden test uses) and
// assert the engine drives the full pipeline (front-half signal -> gates -> sizing -> fill
// -> per-tick management -> trade journal) into coherent, deterministic trades.
//
// The synthetic ticks visit each bar's O/H/L/C (both extremes, open first) with a fixed
// 2-pip spread, so the engine sees real intrabar excursions to manage positions against and
// fills entries on the first tick (open) of the bar after each signal bar.
#include "kk/mastervp/tick_engine.hpp"
#include "kk/common/bars_csv.hpp"
#include "kk/common/execution.hpp"
#include "kk/common/test.hpp"
#include <cmath>
#include <vector>

using kk::Params; using kk::Bar; using kk::Tick; using kk::TickEngine;
using kk::TradeRecord; using kk::ExitTag; using kk::ExecutionSimulator;

// Build a deterministic tick stream from a bar: open, then the two extremes (ordered by the
// bar's direction), then close. bid = price, ask = price + spread. Timestamps stay inside the
// 3-minute bar so the next bar's first tick is the open of that bar.
static void emit_bar_ticks(const Bar& b, double spread, std::vector<Tick>& out) {
    const int64_t offs[4] = {0, 45000, 90000, 135000};
    double seq[4];
    if (b.close >= b.open) { seq[0] = b.open; seq[1] = b.low;  seq[2] = b.high; seq[3] = b.close; }
    else                   { seq[0] = b.open; seq[1] = b.high; seq[2] = b.low;  seq[3] = b.close; }
    for (int k = 0; k < 4; ++k) {
        Tick t; t.ts_ms = b.ts_ms + offs[k]; t.bid = seq[k]; t.ask = seq[k] + spread;
        out.push_back(t);
    }
}

static std::vector<Tick> ticks_from_bars(const std::vector<Bar>& bars, double spread) {
    std::vector<Tick> ticks;
    ticks.reserve(bars.size() * 4);
    for (const auto& b : bars) emit_bar_ticks(b, spread, ticks);
    return ticks;
}

static std::vector<TradeRecord> run_engine(const std::vector<Bar>& bars, const Params& p) {
    TickEngine eng(p);
    eng.load_bars(bars);
    const double spread = 2.0 * p.pip_size;
    const auto ticks = ticks_from_bars(bars, spread);
    for (const auto& t : ticks) eng.on_tick(t);
    if (!ticks.empty()) {
        const auto& last = ticks.back();
        eng.finish(last.bid, last.ask, last.ts_ms);
    }
    return eng.trades();
}

static bool valid_exit(ExitTag t) {
    return t == ExitTag::SL_WIN || t == ExitTag::SL_LOSS || t == ExitTag::TP || t == ExitTag::EA_FORCE;
}

static bool finite(double x) { return !std::isnan(x) && !std::isinf(x); }

void test_execution_fill_model() {
    Tick t; t.bid = 100.0; t.ask = 100.30;
    KK_CHECK(ExecutionSimulator::fill_price(true, t)  == 100.30);  // long buys the ask
    KK_CHECK(ExecutionSimulator::fill_price(false, t) == 100.00);  // short sells the bid
    KK_CHECK(std::fabs(ExecutionSimulator::entry_spread(t) - 0.30) < 1e-9);
    // adverse slippage widens the fill against the trader either way.
    KK_CHECK(std::fabs(ExecutionSimulator::fill_price(true, t, 0.05) - 100.35) < 1e-9);
    KK_CHECK(std::fabs(ExecutionSimulator::fill_price(false, t, 0.05) - 99.95) < 1e-9);
}

void test_engine_produces_coherent_trades() {
    auto bars = kk::load_bars_csv("tests/mastervp/golden/bars_btcusd_M3_aprwindow.csv");
    if (bars.empty()) {
        std::printf("  (missing tests/mastervp/golden/bars_btcusd_M3_aprwindow.csv -- skipped)\n");
        return;
    }
    Params p;
    p.apply_btcusd_specs();   // pip/mintick 0.01, contract 1.0, vppl 1, $0 commission

    TickEngine eng(p);
    eng.load_bars(bars);
    const double spread = 2.0 * p.pip_size;
    const auto ticks = ticks_from_bars(bars, spread);
    for (const auto& t : ticks) eng.on_tick(t);
    const auto& last = ticks.back();
    eng.finish(last.bid, last.ask, last.ts_ms);

    const auto& trades = eng.trades();
    std::printf("  raw_signals=%d trades=%zu balance=%.2f peak=%.2f\n",
                eng.raw_signals(), trades.size(), eng.balance(), eng.peak_equity());

    // The front half must have fired on this fixture (the golden parity test sees ~74).
    KK_CHECK(eng.raw_signals() > 0);
    // Gates only ever REDUCE raw signals to trades; each fill consumes one signal bar.
    KK_CHECK(trades.size() <= static_cast<size_t>(eng.raw_signals()));
    // The gate stack (session/blocked-hours/MTF/RSI/ATR%) must let SOME trades through.
    KK_CHECK(!trades.empty());

    double sum_realized = 0.0;
    bool any_nonzero = false;
    for (const auto& tr : trades) {
        KK_CHECK(tr.entry > 0.0 && finite(tr.entry));
        KK_CHECK(tr.risk_price > 0.0 && finite(tr.risk_price));   // effRisk = |fill - SL| > 0
        KK_CHECK(finite(tr.mfe_r) && tr.mfe_r >= 0.0);            // excursions are non-negative
        KK_CHECK(finite(tr.mae_r) && tr.mae_r >= 0.0);
        KK_CHECK(valid_exit(tr.exit_tag));
        KK_CHECK(finite(tr.realized_usd));
        KK_CHECK(tr.session >= 1 && tr.session <= 3);            // entries only inside a session
        sum_realized += tr.realized_usd;
        if (tr.realized_usd != 0.0) any_nonzero = true;
    }
    KK_CHECK(any_nonzero);   // something actually resolved with P&L

    // Balance reconciliation: final balance == start + sum of every trade's realized P&L.
    KK_CHECK(std::fabs(eng.balance() - (p.start_balance + sum_realized)) < 1e-6);
    KK_CHECK(eng.peak_equity() >= p.start_balance - 1e-9);
}

void test_engine_is_deterministic() {
    auto bars = kk::load_bars_csv("tests/mastervp/golden/bars_btcusd_M3_aprwindow.csv");
    if (bars.empty()) { std::printf("  (fixture missing -- skipped)\n"); return; }
    Params p; p.apply_btcusd_specs();
    const auto a = run_engine(bars, p);
    const auto b = run_engine(bars, p);
    KK_CHECK(a.size() == b.size());
    for (size_t i = 0; i < a.size() && i < b.size(); ++i) {
        KK_CHECK(a[i].entry_ts_ms == b[i].entry_ts_ms);
        KK_CHECK(a[i].is_long == b[i].is_long);
        KK_CHECK(std::fabs(a[i].entry - b[i].entry) < 1e-12);
        KK_CHECK(std::fabs(a[i].realized_usd - b[i].realized_usd) < 1e-9);
        KK_CHECK(a[i].exit_tag == b[i].exit_tag);
    }
}

void run_all() {
    KK_RUN(test_execution_fill_model);
    KK_RUN(test_engine_produces_coherent_trades);
    KK_RUN(test_engine_is_deterministic);
}

KK_TEST_MAIN()
