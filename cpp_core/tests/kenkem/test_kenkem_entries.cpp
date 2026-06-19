// P5: entry detection (dispatch, gates) + SL/TP geometry.
#include "kk/kenkem/entries.hpp"
#include "kk/common/test.hpp"
#include <vector>

using std::vector;
using namespace kk::kenkem;

static TfIndicators blank(int n, bool ichi = false) {
    TfIndicators s; s.bars.resize(n); s.tf_ms = 60000;
    for (int e = 0; e < 5; ++e) s.ema[e].assign(n, 0.0);
    if (ichi) { s.has_ichi = true; s.ichi.tenkan.assign(n,0); s.ichi.kijun.assign(n,0);
                s.ichi.span_a_cur.assign(n,0); s.ichi.span_b_cur.assign(n,0); }
    return s;
}
// Fill the EMA stack back a few bars so BOTH the trigger (reads align-1) and the faithful gates (read the
// GetEMA entry shift align-3 via emas_ready_entry) see a valid bull stack.
static void bull_emas(TfIndicators& s, int i) {
    for (int k=0;k<5 && i-k>=0;++k){ s.ema[1][i-k]=110; s.ema[2][i-k]=108; s.ema[3][i-k]=106; s.ema[4][i-k]=104; }
}

// These tests isolate trigger dispatch + SL/TP geometry. The full conviction / trend-quality / RSI-veto
// selectivity filters are exercised separately in test_kenkem_scoring.cpp; relax them here so the
// geometry fixtures (which don't populate multi-bar ADX/RSI history) aren't blocked by them.
static KenKemConfig geom_cfg() {
    KenKemConfig c; c.pip_size = 0.01;
    c.min_tq_e1 = c.min_tq_e2 = c.min_tq_e4 = 0;
    c.use_conviction_e1 = c.use_conviction_e2 = c.use_conviction_e4 = false;
    c.enable_rsi_div_veto = false;
    return c;
}

static Snapshot snap_bull() {
    Snapshot s; s.valid = true;
    for (int t=0;t<4;++t){ s.adx[t]=30; s.diP[t]=28; s.diM[t]=8; }
    // Full M1 EMA stack below price (faithful E4 STEP2/STEP3 + price-vs-EMA25 need emaM1[1..2] set).
    s.emaM1[1]=107; s.emaM1[2]=106.5; s.emaM1[3]=106; s.emaM1[4]=104; s.atrM1=1.0; s.atrM1_sl=1.0; s.rsiM1=60;
    s.sideways=0; s.atr_pctile=70; s.closeM1=109;
    s.senkouA_M3=120; s.senkouB_M3=118;   // cloud green (for E4)
    return s;
}

// Build a bundle with bullish-aligned EMAs at the decision shift-1 indices, low=100 across the range.
static TfBundle bundle_bull(int B, TfBundle::Align a) {
    TfBundle b;
    b.m1 = blank(B+1, true); b.m3 = blank(a.m3+1, true); b.m5 = blank(a.m5+1); b.m15 = blank(a.m15+1);
    for (int i=0;i<=B;++i){ b.m1.bars[i].high=101; b.m1.bars[i].low=100; b.m1.bars[i].close=109; }
    bull_emas(b.m1, a.m1-1); bull_emas(b.m3, a.m3-1);
    return b;
}

void test_e1_long_fires_with_geometry() {
    KenKemConfig c = geom_cfg();
    int B = 50; TfBundle::Align a{50,16,10,3};
    TfBundle b = bundle_bull(B, a);
    Snapshot s = snap_bull();
    TriggerState tg; tg.ema_up = B;     // fresh E1 up-cross

    EntrySignal r = detect_entry(b, c, B, a, s, tg);
    KK_CHECK(r.detected && r.is_long && r.kind == 1);
    KK_CHECK_NEAR(r.entry, 109.0, 1e-9);
    // custom level 104.5, baseSL min(100,104.5)=100, stop 99.73 -> ATR cap 4.0 -> sl=105.0, risk=4.0
    KK_CHECK_NEAR(r.sl, 105.0, 1e-6);
    KK_CHECK_NEAR(r.risk, 4.0, 1e-6);
    KK_CHECK_NEAR(r.tp, 109.0 + 1.9 * 4.0, 1e-6);   // E1 long RR 1.9
}

void test_stale_trigger_no_fire() {
    KenKemConfig c = geom_cfg();
    int B = 200; TfBundle::Align a{200,66,40,13};
    TfBundle b = bundle_bull(B, a);
    Snapshot s = snap_bull();
    TriggerState tg; tg.ema_up = 200 - (c.e1_max_cross_age + 5);   // older than max age
    EntrySignal r = detect_entry(b, c, B, a, s, tg);
    KK_CHECK(!r.detected);
}

void test_sideways_blocks() {
    KenKemConfig c = geom_cfg();
    int B = 50; TfBundle::Align a{50,16,10,3};
    TfBundle b = bundle_bull(B, a);
    Snapshot s = snap_bull(); s.sideways = 60;    // above block threshold
    TriggerState tg; tg.ema_up = B;
    KK_CHECK(!detect_entry(b, c, B, a, s, tg).detected);
}

void test_dispatch_e1_before_e4() {
    KenKemConfig c = geom_cfg();
    int B = 50; TfBundle::Align a{50,16,10,3};
    TfBundle b = bundle_bull(B, a);
    Snapshot s = snap_bull();
    TriggerState tg; tg.ema_up = B; tg.ichi_up = B;   // both E1 and E4 armed
    EntrySignal r = detect_entry(b, c, B, a, s, tg);
    KK_CHECK(r.detected && r.kind == 1);              // E1 wins (first match)
}

void test_e4_requires_green_cloud() {
    KenKemConfig c = geom_cfg(); c.enable_e1=false; c.enable_e2=false;
    int B = 50; TfBundle::Align a{50,16,10,3};
    TfBundle b = bundle_bull(B, a);
    Snapshot s = snap_bull(); s.senkouA_M3 = 118; s.senkouB_M3 = 120;   // cloud RED
    TriggerState tg; tg.ichi_up = B;                  // long trigger but cloud red
    KK_CHECK(!detect_entry(b, c, B, a, s, tg).detected);
    s.senkouA_M3 = 122; s.senkouB_M3 = 118;           // green + thick
    KK_CHECK(detect_entry(b, c, B, a, s, tg).detected);
}

void run_all() {
    KK_RUN(test_e1_long_fires_with_geometry);
    KK_RUN(test_stale_trigger_no_fire);
    KK_RUN(test_sideways_blocks);
    KK_RUN(test_dispatch_e1_before_e4);
    KK_RUN(test_e4_requires_green_cloud);
}

KK_TEST_MAIN()
