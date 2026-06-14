// Minimal dependency-free test harness (mirrors the discipline of pipeline/tests).
// Each test .cpp defines test functions + a run_all(), then KK_TEST_MAIN().
#pragma once
#include <cstdio>
#include <cmath>

namespace kk::test {
inline int g_checks = 0;
inline int g_failures = 0;
}

#define KK_CHECK(cond)                                                              \
    do {                                                                           \
        kk::test::g_checks++;                                                      \
        if (!(cond)) {                                                             \
            kk::test::g_failures++;                                                \
            std::printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);          \
        }                                                                          \
    } while (0)

#define KK_CHECK_NEAR(a, b, tol)                                                    \
    do {                                                                           \
        kk::test::g_checks++;                                                      \
        double _a = (double)(a), _b = (double)(b), _d = std::fabs(_a - _b);        \
        if (_d > (double)(tol)) {                                                  \
            kk::test::g_failures++;                                                \
            std::printf("  FAIL %s:%d: |%.10g - %.10g| = %.3g > %g\n",             \
                        __FILE__, __LINE__, _a, _b, _d, (double)(tol));            \
        }                                                                          \
    } while (0)

#define KK_RUN(fn)                                                                  \
    do { std::printf("[run] %s\n", #fn); fn(); } while (0)

#define KK_TEST_MAIN()                                                              \
    int main() {                                                                   \
        run_all();                                                                 \
        std::printf("%s: %d checks, %d failures\n",                                \
                    kk::test::g_failures ? "FAILED" : "OK",                        \
                    kk::test::g_checks, kk::test::g_failures);                     \
        return kk::test::g_failures ? 1 : 0;                                       \
    }
