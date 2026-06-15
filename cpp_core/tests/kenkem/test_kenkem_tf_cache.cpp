// P2: per-TF indicator buffers + multi-TF OPEN-time alignment (shift semantics).
#include "kk/kenkem/tf_cache.hpp"
#include "kk/common/test.hpp"
#include <vector>

using std::vector;
using namespace kk::kenkem;

static kk::Bar mk(int64_t ts, double o, double h, double l, double c) {
    kk::Bar b; b.ts_ms = ts; b.open = o; b.high = h; b.low = l; b.close = c; b.tick_count = 10; return b;
}

// Builder populates every buffer the M1 TF needs; HTFs carry only what their handle set has.
void test_buffers_built() {
    KenKemConfig cfg;  // default EMA periods 10/25/71/97/192
    const int N = 260;
    vector<kk::Bar> m1, m3, m5, m15;
    for (int i = 0; i < N; ++i) {
        double c = 1000.0 + i;                 // strictly rising
        m1.push_back(mk((int64_t)i * 60000, c, c + 0.5, c - 0.5, c));
        if (i % 3 == 0)  m3.push_back(mk((int64_t)i * 60000, c, c + 0.5, c - 0.5, c));
        if (i % 5 == 0)  m5.push_back(mk((int64_t)i * 60000, c, c + 0.5, c - 0.5, c));
        if (i % 15 == 0) m15.push_back(mk((int64_t)i * 60000, c, c + 0.5, c - 0.5, c));
    }
    TfBundle b = build_tf_bundle(m1, m3, m5, m15, cfg);

    // M1 carries short ADX + RSI + Ichimoku; M3 carries RSI (conviction/RSI-veto) + Ichimoku; HTFs differ.
    KK_CHECK(b.m1.has_short && b.m1.has_rsi && b.m1.has_ichi);
    KK_CHECK(b.m3.has_ichi && b.m3.has_rsi && !b.m3.has_short);
    KK_CHECK(!b.m5.has_short && !b.m5.has_rsi && !b.m5.has_ichi);
    KK_CHECK(!b.m15.has_ichi);

    // All five EMA buffers sized to the series; last EMA value is finite & below last close (rising series).
    for (int e = 0; e < 5; ++e) KK_CHECK((int)b.m1.ema[e].size() == N);
    KK_CHECK(b.m1.ema[0][N - 1] > 0.0 && b.m1.ema[0][N - 1] < b.m1.bars[N - 1].close);
    // Faster EMA (period 10) tracks closer to price than the slow anchor (period 192).
    KK_CHECK(b.m1.ema[0][N - 1] > b.m1.ema[4][N - 1]);

    // ADX/ATR/RSI populated on M1.
    KK_CHECK((int)b.m1.adx.size() == N && (int)b.m1.atr.size() == N && (int)b.m1.rsi.size() == N);
    KK_CHECK(b.m1.atr[N - 1] > 0.0);              // true range ~1.0 each bar
    KK_CHECK(b.m1.adxS.size() == b.m1.adx.size()); // short handle present
}

// forming_index_at returns the newest bar with OPEN <= t; shift 1 = last closed bar.
void test_alignment() {
    KenKemConfig cfg;
    vector<kk::Bar> m1, m3, m5, m15;
    const int N = 90;
    for (int i = 0; i < N; ++i) {
        double c = 100.0 + i;
        m1.push_back(mk((int64_t)i * 60000, c, c, c, c));
        if (i % 3 == 0)  m3.push_back(mk((int64_t)i * 60000, c, c, c, c));
        if (i % 5 == 0)  m5.push_back(mk((int64_t)i * 60000, c, c, c, c));
        if (i % 15 == 0) m15.push_back(mk((int64_t)i * 60000, c, c, c, c));
    }
    TfBundle b = build_tf_bundle(m1, m3, m5, m15, cfg);

    // Decision at the open of M1 bar 60 (t = 60*60000).
    int64_t t = (int64_t)60 * 60000;
    TfBundle::Align a = b.align_at(t);
    KK_CHECK(a.m1 == 60);                 // forming M1 bar = 60
    // M3 bars exist at i=0,3,...,60 -> index 20 has open 60*60000; forming = 20, shift1 = 19.
    KK_CHECK(b.m3.bars[a.m3].ts_ms <= t && a.m3 == 20);
    // M5 bars at 0,5,...,60 -> index 12 (open 60*60000). M15 at 0,15,30,45,60 -> index 4.
    KK_CHECK(a.m5 == 12 && a.m15 == 4);

    // shift 1 = last closed bar on each TF.
    KK_CHECK(a.m1 - 1 == 59);
    KK_CHECK(b.m3.bars[a.m3 - 1].ts_ms == (int64_t)57 * 60000);   // previous M3 bar opened at i=57

    // A decision instant BETWEEN M3 opens still maps to the in-progress M3 bar.
    int64_t t2 = (int64_t)61 * 60000;     // M3 bar 20 still forming (next opens at i=63)
    KK_CHECK(b.m3.forming_index_at(t2) == 20);
}

void run_all() {
    KK_RUN(test_buffers_built);
    KK_RUN(test_alignment);
}

KK_TEST_MAIN()
