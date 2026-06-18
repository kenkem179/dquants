// P4: snapshot build + distilled gates (trend hard-gate, sideways block, HTF filter).
#include "kk/kenkem/gates.hpp"
#include "kk/common/test.hpp"
#include <vector>

using std::vector;
using namespace kk::kenkem;

static Snapshot strong_bull() {
    Snapshot s; s.valid = true;
    for (int t = 0; t < 4; ++t) { s.adx[t] = 30; s.diP[t] = 28; s.diM[t] = 8; }  // strong + aligned
    s.rsiM1 = 60; s.atrM1 = 1.0;
    return s;
}

void test_trend_hard_gate() {
    KenKemConfig cfg;  // min_momentum_adx=19.7, adx_high=25
    Snapshot s = strong_bull();
    // ADX 30 (>=25 ->2), DI spread 20 (>=3 ->2), MTF 3/3 (->2) = 6.
    KK_CHECK(trend_core_score(s, true, cfg) == 6);
    // Short direction: DI spread negative -> diPts 0 -> hard gate -> 0.
    KK_CHECK(trend_core_score(s, false, cfg) == 0);

    // Weak ADX trips the hard gate even with good DI/MTF.
    Snapshot w = strong_bull();
    for (int t = 0; t < 4; ++t) w.adx[t] = 10;   // below min_momentum_adx
    KK_CHECK(trend_core_score(w, true, cfg) == 0);

    // DI agreement only 1/3 -> mtfPts 0 -> hard gate.
    Snapshot m = strong_bull();
    m.diP[1] = 8; m.diM[1] = 28;   // M3 flips
    m.diP[2] = 8; m.diM[2] = 28;   // M5 flips
    KK_CHECK(trend_core_score(m, true, cfg) == 0);
}

void test_sideways_block() {
    KenKemConfig cfg;  // sideways_block_thr = 53
    Snapshot s; s.sideways = 60;
    KK_CHECK(sideways_blocked(s, cfg));
    s.sideways = 40;
    KK_CHECK(!sideways_blocked(s, cfg));
}

void test_htf_filter() {
    Snapshot s = strong_bull();      // all TFs strong+bullish
    KK_CHECK(htf_filter_ok(s, true, HTF_M5_ONLY, 20.0, 4.0));
    KK_CHECK(htf_filter_ok(s, true, HTF_M15_ONLY, 20.0, 4.0));
    KK_CHECK(htf_filter_ok(s, true, HTF_M5_AND_M15, 20.0, 4.0));
    KK_CHECK(htf_filter_ok(s, true, HTF_DISABLED, 99.0, 99.0));   // disabled always ok
    // Long filter fails for a short trade (DI spread wrong sign).
    KK_CHECK(!htf_filter_ok(s, false, HTF_M5_ONLY, 20.0, 4.0));
    // M5 weak but M15 strong -> OR passes, AND fails.
    s.adx[2] = 5;
    KK_CHECK(htf_filter_ok(s, true, HTF_M5_OR_M15, 20.0, 4.0));
    KK_CHECK(!htf_filter_ok(s, true, HTF_M5_AND_M15, 20.0, 4.0));
}

void test_snapshot_build() {
    KenKemConfig cfg;
    const int N = 260;
    vector<kk::Bar> m1, m3, m5, m15;
    for (int i = 0; i < N; ++i) {
        double c = 1000.0 + i * 2.0;
        kk::Bar b; b.ts_ms = (int64_t)i * 60000; b.open = c; b.high = c + 1; b.low = c - 1; b.close = c; b.tick_count = 10;
        m1.push_back(b);
        if (i % 3 == 0)  m3.push_back(b);
        if (i % 5 == 0)  m5.push_back(b);
        if (i % 15 == 0) m15.push_back(b);
    }
    TfBundle bundle = build_tf_bundle(m1, m3, m5, m15, cfg);
    int B = 240;
    Snapshot s = build_snapshot(bundle, cfg, B, bundle.align_at((int64_t)B * 60000));
    KK_CHECK(s.valid);
    KK_CHECK(s.atrM1 > 0.0);
    KK_CHECK(s.emaM1[1] > 0.0 && s.emaM1[4] > 0.0);
    KK_CHECK(s.sideways >= 0 && s.sideways <= 100);
    KK_CHECK(s.atr_pctile >= 0.0 && s.atr_pctile <= 100.0);
}

void run_all() {
    KK_RUN(test_trend_hard_gate);
    KK_RUN(test_sideways_block);
    KK_RUN(test_htf_filter);
    KK_RUN(test_snapshot_build);
}

KK_TEST_MAIN()
