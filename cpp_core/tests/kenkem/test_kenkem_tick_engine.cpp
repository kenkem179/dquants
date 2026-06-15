// P7 (TICK): the tick-replay engine on the same synthetic down->up regime as the bar engine test.
// Verifies it (a) finds entries, (b) keeps coherent equity accounting, and (c) is DETERMINISTIC
// (same ticks -> same result). The economic *fidelity* vs MT5 is validated empirically against the
// tester deal stream (see research/optimization/MT5-GROUND-TRUTH.md), not in a unit test.
#include "kk/kenkem/tick_engine.hpp"
#include "kk/common/test.hpp"
#include <vector>
#include <cmath>

using std::vector;
using namespace kk::kenkem;

static kk::Bar mk(int64_t ts, double mid, double band, double spread) {
    kk::Bar b; b.ts_ms = ts; b.open = mid; b.close = mid; b.high = mid + band; b.low = mid - band;
    b.spread_mean = spread; b.spread_max = spread; b.tick_count = 20; return b;
}

// Build the synthetic bars + a tick stream that walks each bar open->high->low->close as mid prices,
// converted to bid/ask with a fixed spread.
static void build(vector<kk::Bar>& m1, vector<kk::Bar>& m3, vector<kk::Bar>& m5, vector<kk::Bar>& m15,
                  vector<kk::Tick>& ticks, double spread) {
    const int N = 1000;
    double price = 250.0;
    for (int i = 0; i < N; ++i) {
        if (i < 200) price -= 0.30; else price += 0.45;
        int64_t ts = (int64_t)i * 60000;
        kk::Bar bar = mk(ts, price, 0.20, spread);
        bar.close = price; bar.open = (i < 200) ? price + 0.10 : price - 0.10;
        m1.push_back(bar);
        if (i % 3 == 0)  m3.push_back(bar);
        if (i % 5 == 0)  m5.push_back(bar);
        if (i % 15 == 0) m15.push_back(bar);
        // four ticks per bar (O,H,L,C) as mids -> bid/ask
        const double half = 0.5 * spread;
        for (double mid : { bar.open, bar.high, bar.low, bar.close }) {
            kk::Tick t; t.ts_ms = ts + 1; t.bid = mid - half; t.ask = mid + half; ticks.push_back(t);
        }
    }
}

static BtResult run_once() {
    KenKemConfig cfg; cfg.apply_xauusd_specs();
    cfg.max_concurrent_pos = 2;
    // Disable the selectivity filters that need real multi-bar indicator history; this test exercises
    // tick-engine accounting/determinism on a synthetic trend (filters covered in test_kenkem_scoring).
    cfg.min_entry_atr_pctile = 0.0;
    cfg.min_tq_e1 = cfg.min_tq_e2 = cfg.min_tq_e4 = 0;
    cfg.use_conviction_e1 = cfg.use_conviction_e2 = cfg.use_conviction_e4 = false;
    cfg.enable_rsi_div_veto = false;
    cfg.enable_atr_high_block = false;
    cfg.max_consec_losses_type = 0;
    vector<kk::Bar> m1, m3, m5, m15; vector<kk::Tick> ticks;
    build(m1, m3, m5, m15, ticks, 0.02);
    TfBundle b = build_tf_bundle(m1, m3, m5, m15, cfg);
    TickEngine eng(b, cfg, /*warmup*/250);
    for (const kk::Tick& t : ticks) eng.on_tick(t);
    if (!ticks.empty()) eng.finish(ticks.back().bid, ticks.back().ask, ticks.back().ts_ms);
    return eng.result();
}

void test_tick_engine_trades_and_accounting() {
    BtResult R = run_once();
    KK_CHECK(R.trades > 0);
    KK_CHECK((int)R.equity.size() == R.trades);
    KK_CHECK(R.wins <= R.trades);
    KK_CHECK_NEAR(R.end_balance, R.list.empty() ? 10000.0 : (10000.0 + R.net), 1e-6);
    std::printf("  tick-engine: trades=%d wins=%d net=%.2f PF=%.3f\n", R.trades, R.wins, R.net, R.pf);
}

void test_tick_engine_deterministic() {
    BtResult a = run_once();
    BtResult b = run_once();
    KK_CHECK(a.trades == b.trades);
    KK_CHECK_NEAR(a.net, b.net, 1e-9);
    KK_CHECK_NEAR(a.end_balance, b.end_balance, 1e-9);
}

void run_all() {
    KK_RUN(test_tick_engine_trades_and_accounting);
    KK_RUN(test_tick_engine_deterministic);
}

KK_TEST_MAIN()
