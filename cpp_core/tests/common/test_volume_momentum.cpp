// Unit tests for kk::VolumeMomentum (VMC). Dependency-free; see kk/common/test.hpp.
#include "kk/common/volume_momentum.hpp"
#include "kk/common/test.hpp"
#include <vector>

using namespace kk;

static Bar mkbar(double spread_mean, int64_t tick_count) {
    Bar b; b.spread_mean = spread_mean; b.tick_count = tick_count; return b;
}

// Feed a run of ticks that step mid up by `steps` points each, point=0.01.
static void up_ticks(VolumeMomentum& v, int n, const VmcParams& p, double start = 2000.00) {
    double mid = start;
    for (int i = 0; i < n; ++i) { mid += 0.01; v.on_tick(mid - 0.005, mid + 0.005, 0.01, p); }
}
static void dn_ticks(VolumeMomentum& v, int n, const VmcParams& p, double start = 2000.00) {
    double mid = start;
    for (int i = 0; i < n; ++i) { mid -= 0.01; v.on_tick(mid - 0.005, mid + 0.005, 0.01, p); }
}

// ---- 1. tick rule: dead-band, up/dn counting, carry across the seed tick ----
void test_sign_counting() {
    VmcParams p; p.epsilon_pts = 1; p.warmup_bars = 1;
    VolumeMomentum v; v.init(p);
    // 1 seed tick + 5 up steps => up=5, dn=0 => r = +1
    up_ticks(v, 6, p);                       // first tick seeds, next 5 are +1
    auto o = v.on_bar_close(mkbar(0.01, 6), false, p);
    KK_CHECK_NEAR(o.r, 1.0, 1e-9);
    KK_CHECK_NEAR(o.cvd, 5.0, 1e-9);
}

void test_deadband_excludes_flat() {
    VmcParams p; p.epsilon_pts = 2; p.warmup_bars = 1;   // require >= 2 points to count
    VolumeMomentum v; v.init(p);
    // seed, then steps of exactly 1 point each — all below the 2-pt dead-band => flat => r=0
    up_ticks(v, 6, p);
    auto o = v.on_bar_close(mkbar(0.01, 6), false, p);
    KK_CHECK_NEAR(o.r, 0.0, 1e-9);
}

// ---- 2. prev_mid carries across bar boundaries (no reset) ----
void test_carry_across_bars() {
    VmcParams p; p.epsilon_pts = 1; p.warmup_bars = 1;
    VolumeMomentum v; v.init(p);
    up_ticks(v, 4, p, 2000.00);              // seed @2000.01 then 3 up => up=3
    v.on_bar_close(mkbar(0.01, 4), false, p);
    // next bar continues from last mid (2000.04). One more up tick should count as +1 (carry, not reseed).
    double mid = 2000.05; v.on_tick(mid - 0.005, mid + 0.005, 0.01, p);
    auto o = v.on_bar_close(mkbar(0.01, 1), false, p);
    KK_CHECK_NEAR(o.r, 1.0, 1e-9);           // would be 0 if prev_mid had been reset (first tick = seed)
}

// ---- 3. INDEPENDENCE: a green bar with majority down-ticks yields negative r (the whole point) ----
void test_independent_of_close() {
    VmcParams p; p.epsilon_pts = 1; p.warmup_bars = 1;
    VolumeMomentum v; v.init(p);
    // path: 2 up then 5 down then settle up so the bar's net price move is up, but down-ticks dominate.
    up_ticks(v, 3, p, 2000.00);              // seed + 2 up
    dn_ticks(v, 5, p, 2000.03);              // 5 down  -> up=2, dn=5
    auto o = v.on_bar_close(mkbar(0.01, 8), false, p);
    KK_CHECK(o.r < 0.0);                     // flow is bearish even if you'd have called the bar "green"
}

// ---- 4. warmup invalidity + gating ----
void test_warmup_and_gate() {
    VmcParams p; p.warmup_bars = 5; p.epsilon_pts = 1;
    VolumeMomentum v; v.init(p);
    VmcOut o{};
    for (int i = 0; i < 4; ++i) { up_ticks(v, 4, p); o = v.on_bar_close(mkbar(0.01, 4), false, p); }
    KK_CHECK(!o.valid);                      // 4 bars < warmup 5
    KK_CHECK_NEAR(o.vmc, 0.0, 1e-9);         // invalid => vmc forced 0
    up_ticks(v, 4, p); o = v.on_bar_close(mkbar(0.01, 4), false, p);
    KK_CHECK(o.valid);                       // 5th bar => valid
    // ext_block forces gate regardless of signal
    up_ticks(v, 4, p); o = v.on_bar_close(mkbar(0.01, 4), true, p);
    KK_CHECK(o.gated);
    KK_CHECK_NEAR(o.vmc, 0.0, 1e-9);
}

// ---- 5. persistence + confirms(): a sustained one-sided run confirms long, not short ----
void test_persistence_and_confirms() {
    VmcParams p; p.warmup_bars = 3; p.epsilon_pts = 1; p.persist_len = 5; p.retention_len = 5;
    VolumeMomentum v; v.init(p);
    VmcOut o{};
    for (int i = 0; i < 8; ++i) { up_ticks(v, 6, p); o = v.on_bar_close(mkbar(0.01, 6), false, p); }
    KK_CHECK(o.valid && !o.gated);
    KK_CHECK_NEAR(o.persist, 1.0, 1e-9);     // all recent bars agree (up)
    KK_CHECK(o.vmc > 0.0);
    KK_CHECK(v.confirms(+1, 0.1));           // confirms a long
    KK_CHECK(!v.confirms(-1, 0.1));          // does NOT confirm a short
}

// ---- 6. determinism: identical input => identical output ----
void test_determinism() {
    VmcParams p; p.warmup_bars = 2;
    auto run = [&]() {
        VolumeMomentum v; v.init(p); VmcOut o{};
        for (int i = 0; i < 6; ++i) { up_ticks(v, 5, p); o = v.on_bar_close(mkbar(0.01, 5), false, p); }
        return o.vmc;
    };
    KK_CHECK_NEAR(run(), run(), 0.0);
}

// ---- 7. peek_forming does not mutate committed state ----
void test_peek_no_mutate() {
    VmcParams p; p.warmup_bars = 2;
    VolumeMomentum v; v.init(p);
    for (int i = 0; i < 5; ++i) { up_ticks(v, 5, p); v.on_bar_close(mkbar(0.01, 5), false, p); }
    const double committed = v.out().vmc;
    up_ticks(v, 3, p);                        // partial forming bar
    VmcOut pk = v.peek_forming(mkbar(0.01, 3), false, p);
    (void)pk;
    KK_CHECK_NEAR(v.out().vmc, committed, 0.0);   // committed reading untouched by peek
}

void run_all() {
    KK_RUN(test_sign_counting);
    KK_RUN(test_deadband_excludes_flat);
    KK_RUN(test_carry_across_bars);
    KK_RUN(test_independent_of_close);
    KK_RUN(test_warmup_and_gate);
    KK_RUN(test_persistence_and_confirms);
    KK_RUN(test_determinism);
    KK_RUN(test_peek_no_mutate);
}

KK_TEST_MAIN()
