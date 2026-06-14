// P2: Ichimoku primitive correctness (Tenkan/Kijun/Span A/B + the +kijun plot shift for "current").
#include "kk/kenkem/indicators.hpp"
#include "kk/common/test.hpp"
#include <vector>

using std::vector;
using namespace kk::ind;

// On a strictly rising series with high=close, low=close, the Donchian midpoint over `p` bars ending
// at i is (close[i] + close[i-p+1]) / 2 — a clean closed form to check Tenkan/Kijun against.
void test_ichimoku_rising() {
    const int N = 120;
    vector<double> h(N), l(N), c(N);
    for (int i = 0; i < N; ++i) { c[i] = 100.0 + i; h[i] = c[i]; l[i] = c[i]; }
    IchimokuBuf b = ichimoku(h, l, c, 9, 26, 52);

    int i = 100;
    // Tenkan(9): (c[i] + c[i-8]) / 2
    KK_CHECK_NEAR(b.tenkan[i], 0.5 * (c[i] + c[i - 8]), 1e-9);
    // Kijun(26): (c[i] + c[i-25]) / 2
    KK_CHECK_NEAR(b.kijun[i], 0.5 * (c[i] + c[i - 25]), 1e-9);
    // SpanB future(52): (c[i] + c[i-51]) / 2
    KK_CHECK_NEAR(b.span_b_fut[i], 0.5 * (c[i] + c[i - 51]), 1e-9);
    // SpanA future = (Tenkan+Kijun)/2
    KK_CHECK_NEAR(b.span_a_fut[i], 0.5 * (b.tenkan[i] + b.kijun[i]), 1e-9);
    // "current" cloud at i is the future-span computed kijun(26) bars earlier
    KK_CHECK_NEAR(b.span_a_cur[i], b.span_a_fut[i - 26], 1e-9);
    KK_CHECK_NEAR(b.span_b_cur[i], b.span_b_fut[i - 26], 1e-9);
    KK_CHECK(b.valid_at(i));
}

// Warmup region: values undefined (0) until enough history; current-cloud needs i >= kijun+ (period-1).
void test_ichimoku_warmup() {
    const int N = 60;
    vector<double> h(N), l(N), c(N);
    for (int i = 0; i < N; ++i) { c[i] = 50.0 + 0.1 * i; h[i] = c[i] + 0.5; l[i] = c[i] - 0.5; }
    IchimokuBuf b = ichimoku(h, l, c, 9, 26, 52);
    KK_CHECK(b.tenkan[7] == 0.0);     // < tenkan-1
    KK_CHECK(b.tenkan[8] != 0.0);     // first valid Tenkan
    KK_CHECK(b.span_b_fut[50] == 0.0);// < senkou_b-1
    KK_CHECK(b.span_b_fut[51] != 0.0);// first valid SpanB
    KK_CHECK(!b.valid_at(30));        // current cloud needs i-kijun >= span warmup
}

void run_all() {
    KK_RUN(test_ichimoku_rising);
    KK_RUN(test_ichimoku_warmup);
}

KK_TEST_MAIN()
