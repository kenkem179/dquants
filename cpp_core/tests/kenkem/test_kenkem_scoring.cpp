// P4c: the previously parsed-but-ignored selectivity filters — conviction, full trend-quality, RSI veto.
#include "kk/kenkem/scoring.hpp"
#include "kk/common/test.hpp"
#include <vector>

using namespace kk::kenkem;

// A TF with n bars and constant ADX/DI/RSI; bars trend up (close>open) by default.
static TfIndicators tf_const(int n, double adx, double dip, double dim, double rsi, bool up) {
    TfIndicators s; s.bars.resize(n); s.tf_ms = 60000;
    for (int e=0;e<5;++e) s.ema[e].assign(n, 0.0);
    s.adx.assign(n, adx); s.diP.assign(n, dip); s.diM.assign(n, dim);
    s.rsi.assign(n, rsi); s.has_rsi = true;
    for (int i=0;i<n;++i){ s.bars[i].open = up?100.0:101.0; s.bars[i].close = up?101.0:100.0;
                           s.bars[i].high = 101.5; s.bars[i].low = 99.5; }
    return s;
}

static TfBundle bundle(int n, double adx, double dip, double dim, double rsi, bool up) {
    TfBundle b;
    b.m1 = tf_const(n, adx, dip, dim, rsi, up);
    b.m3 = tf_const(n, adx, dip, dim, rsi, up);
    b.m5 = tf_const(n, adx, dip, dim, rsi, up);
    b.m15= tf_const(n, adx, dip, dim, rsi, up);
    return b;
}

static Snapshot snap(double adx, double dip, double dim, double rsi, double atr_pctile) {
    Snapshot s; s.valid = true;
    for (int t=0;t<4;++t){ s.adx[t]=adx; s.diP[t]=dip; s.diM[t]=dim; }
    s.emaM1[1]=110; s.emaM1[2]=108; s.emaM1[3]=106; s.emaM1[4]=104;   // bullish ordered stack
    s.atrM1=1.0; s.rsiM1=rsi; s.atr_pctile=atr_pctile; s.closeM1=109;
    return s;
}

// Strong, clean uptrend: high conviction + high trend-quality, no RSI divergence.
void test_strong_trend_passes_filters() {
    KenKemConfig c; c.pip_size = 0.01;
    TfBundle::Align a{60,60,60,60};
    TfBundle b = bundle(61, 30, 28, 8, 62, true);
    Snapshot s = snap(30, 28, 8, 62, 70);
    // E1 (min_tq 6, conviction 7) should pass.
    KK_CHECK(quality_filters_ok(1, true, b, s, a, c));
    int tq = trend_quality_score(b, a, s, true, 1, c);
    int cv = conviction_score(b, a, s, true, c);
    KK_CHECK(tq >= c.min_tq_e1);
    KK_CHECK(cv >= c.conviction_thr_e1);
}

// Hard gate: DI spread zero (diP==diM) must zero the trend-quality score and block all entries.
void test_hard_gate_zeroes_tq() {
    KenKemConfig c; c.pip_size = 0.01;
    TfBundle::Align a{60,60,60,60};
    TfBundle b = bundle(61, 30, 18, 18, 55, true);   // diP==diM -> spreadPts 0
    Snapshot s = snap(30, 18, 18, 55, 70);
    KK_CHECK(trend_quality_score(b, a, s, true, 1, c) == 0);
    KK_CHECK(!quality_filters_ok(1, true, b, s, a, c));
}

// E2 has a high conviction threshold (10). A merely-OK setup that clears E1 should fail E2's conviction.
void test_e2_conviction_is_stricter_than_e1() {
    KenKemConfig c; c.pip_size = 0.01;
    TfBundle::Align a{60,60,60,60};
    // Moderate trend: passes hard gate but not a 10/12 conviction.
    TfBundle b = bundle(61, 20, 21, 18, 51, true);
    Snapshot s = snap(20, 21, 18, 51, 40);
    int cv = conviction_score(b, a, s, true, c);
    KK_CHECK(cv < c.conviction_thr_e2);              // below 10
    KK_CHECK(!quality_filters_ok(2, true, b, s, a, c));
}

// RSI-divergence veto: a long into a bearish divergence (price HH, RSI LH) on M3 must be blocked,
// AND must veto an otherwise-strong setup that would pass on its own.
void test_rsi_divergence_blocks_long() {
    KenKemConfig c; c.pip_size = 0.01;
    TfBundle::Align a{40,40,40,40};
    TfBundle b = bundle(41, 30, 28, 8, 60, true);
    Snapshot s = snap(30, 28, 8, 60, 70);
    KK_CHECK(quality_filters_ok(1, true, b, s, a, c));     // strong setup passes WITHOUT divergence

    // Engineer M3: recent half has a higher HIGH but LOWER rsi than the older half (bearish divergence).
    const int j3 = a.m3 - 1;                     // newest closed M3 bar
    int LB = c.rsi_div_lookback, half = LB/2;    // 16, 8
    for (int k=0;k<LB;++k){ b.m3.bars[j3-k].high = 100.0; b.m3.rsi[j3-k] = 60.0; }
    b.m3.bars[j3-half].high = 200.0;  b.m3.rsi[j3-half] = 80.0;   // older peak, high RSI
    b.m3.bars[j3-1].high    = 260.0;  b.m3.rsi[j3-1]    = 60.0;   // recent higher peak, lower RSI
    // priceDiffPips = (260-200)/0.01 = 6000 >= 60 ; rsiDiff = 80-60 = 20 >= 6.5  -> veto
    KK_CHECK(rsi_divergence_veto(b, a, true, c));
    KK_CHECK(!quality_filters_ok(1, true, b, s, a, c));    // now blocked by the veto
}

void run_all() {
    KK_RUN(test_strong_trend_passes_filters);
    KK_RUN(test_hard_gate_zeroes_tq);
    KK_RUN(test_e2_conviction_is_stricter_than_e1);
    KK_RUN(test_rsi_divergence_blocks_long);
}

KK_TEST_MAIN()
