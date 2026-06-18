// P3: EMA alignment + trigger state machines (EMA cross, EMA75 touch, Ichimoku TK cross).
#include "kk/kenkem/triggers.hpp"
#include "kk/common/test.hpp"
#include <vector>

using std::vector;
using namespace kk::kenkem;

// Build a TF with n bars, all buffers zeroed; caller sets the indices it cares about.
static TfIndicators blank_tf(int n, bool ichi = false) {
    TfIndicators s; s.bars.resize(n); s.tf_ms = 60000;
    for (int e = 0; e < 5; ++e) s.ema[e].assign(n, 0.0);
    if (ichi) {
        s.has_ichi = true;
        s.ichi.tenkan.assign(n, 0.0); s.ichi.kijun.assign(n, 0.0);
        s.ichi.span_a_cur.assign(n, 0.0); s.ichi.span_b_cur.assign(n, 0.0);
    }
    return s;
}
static void set_emas(TfIndicators& s, int i, double e1, double e2, double e3, double e4) {
    s.ema[1][i] = e1; s.ema[2][i] = e2; s.ema[3][i] = e3; s.ema[4][i] = e4;
}

void test_emas_ready() {
    TfIndicators s = blank_tf(4);
    // bullish stack 25>71>97>192 with comfortable gaps
    set_emas(s, 1, 110, 108, 106, 104);
    KK_CHECK(emas_ready(s, 1, /*long*/true, /*strict*/true, 0.2));
    KK_CHECK(!emas_ready(s, 1, /*long*/false, true, 0.2));
    // bearish stack
    set_emas(s, 2, 104, 106, 108, 110);
    KK_CHECK(emas_ready(s, 2, false, true, 0.2));
    KK_CHECK(!emas_ready(s, 2, true, true, 0.2));
    // tolerance: e1 slightly below e2 but within tol counts as long-aligned
    set_emas(s, 3, 107.9, 108, 106, 104);
    KK_CHECK(emas_ready(s, 3, true, true, /*tol*/0.2));   // 107.9 > 108-0.2
    KK_CHECK(!emas_ready(s, 3, true, true, /*tol*/0.05)); // 107.9 < 108-0.05
}

void test_ema_cross_trigger() {
    KenKemConfig cfg; cfg.pip_size = 0.01;  // tol = 23*0.01 = 0.23
    const int B = 50;
    TfBundle bundle;
    bundle.m1 = blank_tf(B + 1); bundle.m3 = blank_tf(B + 1); bundle.m5 = blank_tf(B + 1);
    bundle.m15 = blank_tf(B + 1);
    // FAITHFUL EA buffer-inversion semantics (triggers.hpp): GetEMA(shift1)->B-2 (the "ready"/latch bar),
    // GetEMA(shift2)->B-1 (the "prev" bar). So the EA's "just crossed up" = !ready@(B-1) && ready@(B-2):
    // alignment PRESENT at the older bar (B-2) and ABSENT at the newer bar (B-1).
    set_emas(bundle.m1, B - 2, 110, 108, 106, 104);   // bullish at the ready bar (B-2)
    set_emas(bundle.m1, B - 1, 104, 106, 108, 110);   // bearish at the prev bar (B-1) -> alignment lost
    // M3 bullish at its ready bar (EA shift1 = align.m3-2). align.m3 = 20 -> ready = 18.
    set_emas(bundle.m3, 18, 110, 108, 106, 104);
    TfBundle::Align align{ B, 20, 12, 4 };

    TriggerState st;
    update_triggers(bundle, cfg, B, align, st);
    KK_CHECK(st.ema_up == B);       // fired this bar
    KK_CHECK(st.ema_down == -1);    // opposite cleared
}

void test_ema75_touch_trigger() {
    KenKemConfig cfg; cfg.pip_size = 0.01;
    const int B = 30;
    TfBundle bundle;
    bundle.m1 = blank_tf(B + 1); bundle.m3 = blank_tf(B + 1); bundle.m5 = blank_tf(B + 1);
    bundle.m15 = blank_tf(B + 1);
    // EMA75 (ema[2]) at B-1 = 100; bar straddles it and closes ABOVE -> touch up.
    bundle.m1.ema[2][B - 1] = 100.0;
    bundle.m1.bars[B - 1].low = 99.5; bundle.m1.bars[B - 1].high = 100.5; bundle.m1.bars[B - 1].close = 100.3;
    TfBundle::Align align{ B, 10, 6, 2 };

    TriggerState st;
    update_triggers(bundle, cfg, B, align, st);
    KK_CHECK(st.e75_up == B && st.e75_down == -1);

    // Close BELOW EMA75 -> touch down.
    bundle.m1.bars[B - 1].close = 99.7;
    TriggerState st2;
    update_triggers(bundle, cfg, B, align, st2);
    KK_CHECK(st2.e75_down == B && st2.e75_up == -1);
}

void test_ichi_tk_cross_trigger() {
    KenKemConfig cfg; cfg.pip_size = 0.01; cfg.enable_e4 = true;
    const int B = 40;
    TfBundle bundle;
    bundle.m1 = blank_tf(B + 1, /*ichi*/true); bundle.m3 = blank_tf(B + 1, true);
    bundle.m5 = blank_tf(B + 1); bundle.m15 = blank_tf(B + 1);
    TfBundle::Align align{ B, 14, 8, 3 };
    int m1s1 = B - 1, m1s2 = B - 2, m3s1 = 13, m3s2 = 12;
    // prev (shift2): both bearish (tenkan<kijun). curr (shift1): both bullish -> cross up.
    bundle.m1.ichi.tenkan[m1s2] = 5; bundle.m1.ichi.kijun[m1s2] = 9;   // bearish
    bundle.m3.ichi.tenkan[m3s2] = 5; bundle.m3.ichi.kijun[m3s2] = 9;
    bundle.m1.ichi.tenkan[m1s1] = 9; bundle.m1.ichi.kijun[m1s1] = 5;   // bullish
    bundle.m3.ichi.tenkan[m3s1] = 9; bundle.m3.ichi.kijun[m3s1] = 5;

    TriggerState st;
    update_triggers(bundle, cfg, B, align, st);
    KK_CHECK(st.ichi_up == B && st.ichi_down == -1);

    // If M3 doesn't agree at curr, no cross.
    bundle.m3.ichi.tenkan[m3s1] = 5; bundle.m3.ichi.kijun[m3s1] = 9;  // M3 still bearish
    TriggerState st2;
    update_triggers(bundle, cfg, B, align, st2);
    KK_CHECK(st2.ichi_up == -1);
}

void run_all() {
    KK_RUN(test_emas_ready);
    KK_RUN(test_ema_cross_trigger);
    KK_RUN(test_ema75_touch_trigger);
    KK_RUN(test_ichi_tk_cross_trigger);
}

KK_TEST_MAIN()
