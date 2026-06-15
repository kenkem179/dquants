// P7: end-to-end engine on a synthetic down->up regime. A sustained uptrend after a bearish stretch
// should produce an E1 long cross that take-profits — i.e. trades > 0 and net > 0, with consistent stats.
#include "kk/kenkem/engine.hpp"
#include "kk/common/test.hpp"
#include <vector>
#include <cmath>

using std::vector;
using namespace kk::kenkem;

static kk::Bar mk(int64_t ts, double mid, double band, double spread) {
    kk::Bar b; b.ts_ms = ts; b.open = mid; b.close = mid; b.high = mid + band; b.low = mid - band;
    b.spread_mean = spread; b.spread_max = spread; b.tick_count = 20; return b;
}

// Relax the selectivity filters (conviction / trend-quality / RSI-veto / regime / governors) that need
// real multi-bar indicator history; these engine-mechanics tests use synthetic ramps. Filter behaviour
// is covered in test_kenkem_scoring.cpp.
static void relax_filters(KenKemConfig& cfg) {
    cfg.min_tq_e1 = cfg.min_tq_e2 = cfg.min_tq_e4 = 0;
    cfg.use_conviction_e1 = cfg.use_conviction_e2 = cfg.use_conviction_e4 = false;
    cfg.enable_rsi_div_veto = false;
    cfg.enable_atr_high_block = false;
    cfg.min_entry_atr_pctile = 0.0;
    cfg.max_consec_losses_type = 0;
}

void test_engine_uptrend_profits() {
    KenKemConfig cfg; cfg.apply_xauusd_specs();
    cfg.max_concurrent_pos = 2;
    relax_filters(cfg);
    const int N = 1000;
    vector<kk::Bar> m1, m3, m5, m15;
    double price = 250.0;
    for (int i = 0; i < N; ++i) {
        if (i < 200) price -= 0.30;          // downtrend (sets bearish stack)
        else         price += 0.45;          // sustained uptrend
        int64_t ts = (int64_t)i * 60000;
        kk::Bar bar = mk(ts, price, 0.20, 0.02);
        // make close lead in trend direction so OHLC walk is benign
        bar.close = price; bar.open = (i < 200) ? price + 0.10 : price - 0.10;
        m1.push_back(bar);
        if (i % 3 == 0)  m3.push_back(bar);
        if (i % 5 == 0)  m5.push_back(bar);
        if (i % 15 == 0) m15.push_back(bar);
    }
    TfBundle b = build_tf_bundle(m1, m3, m5, m15, cfg);
    BtResult R = run_backtest(b, cfg, /*warmup*/250);

    KK_CHECK(R.trades > 0);                                   // engine found entries
    KK_CHECK((int)R.equity.size() == R.trades);              // one equity point per closed trade
    KK_CHECK(R.wins <= R.trades);
    KK_CHECK_NEAR(R.end_balance, cfg.start_balance + R.net, 1e-6);
    KK_CHECK(R.net > 0.0);                                    // longs into a rising trend make money
    KK_CHECK(R.max_dd >= 0.0);
    // all trades should be long in this one-directional regime
    int longs = 0; for (auto& t : R.list) if (t.is_long) ++longs;
    KK_CHECK(longs == R.trades);
}

void test_engine_no_trades_when_disabled() {
    KenKemConfig cfg; cfg.apply_xauusd_specs();
    cfg.enable_e1 = cfg.enable_e2 = cfg.enable_e4 = false;
    const int N = 600;
    vector<kk::Bar> m1, m3, m5, m15;
    for (int i = 0; i < N; ++i) {
        double price = 250.0 + i * 0.4;
        kk::Bar bar = mk((int64_t)i * 60000, price, 0.2, 0.02);
        m1.push_back(bar);
        if (i % 3 == 0) m3.push_back(bar);
        if (i % 5 == 0) m5.push_back(bar);
        if (i % 15 == 0) m15.push_back(bar);
    }
    TfBundle b = build_tf_bundle(m1, m3, m5, m15, cfg);
    BtResult R = run_backtest(b, cfg, 250);
    KK_CHECK(R.trades == 0 && R.net == 0.0);
}

void run_all() {
    KK_RUN(test_engine_uptrend_profits);
    KK_RUN(test_engine_no_trades_when_disabled);
}

KK_TEST_MAIN()
