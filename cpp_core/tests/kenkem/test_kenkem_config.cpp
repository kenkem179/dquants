// P1 smoke test: KenKemConfig defaults match InputParams.mqh + .set loader applies real input names.
#include "kk/kenkem/kenkem_config.hpp"
#include "kk/common/test.hpp"
#include <cstdio>
#include <string>

using namespace kk::kenkem;

void test_defaults() {
    KenKemConfig p;
    // entry enables (E1/E2/E4 on; E3/E5 not in schema)
    KK_CHECK(p.enable_e1 && p.enable_e2 && p.enable_e4);
    // RR defaults (authoritative InputParams.mqh values)
    KK_CHECK_NEAR(p.e1_rr, 1.9, 1e-9);
    KK_CHECK_NEAR(p.e2_rr, 1.575, 1e-9);
    KK_CHECK_NEAR(p.e4_rr, 2.4, 1e-9);
    // trend-quality mins
    KK_CHECK(p.min_tq_e1 == 6 && p.min_tq_e2 == 9 && p.min_tq_e4 == 9);
    // HTF filter modes
    KK_CHECK(p.e1_htf_filter == HTF_M5_ONLY);
    KK_CHECK(p.e2_htf_filter == HTF_M15_ONLY);
    KK_CHECK(p.e4_htf_filter == HTF_M5_OR_M15);
    // gates / guards
    KK_CHECK(p.sideways_block_thr == 53);
    KK_CHECK(p.max_session_losses == 4);
    KK_CHECK_NEAR(p.r_mult_be_trigger, 0.87, 1e-9);
    KK_CHECK_NEAR(p.max_daily_loss_ratio, 0.072, 1e-9);
    KK_CHECK(p.sl_ema_distance == 27);
    KK_CHECK_NEAR(p.e1_atr_sl_cap, 4.0, 1e-9);
    // per-entry risk ratios derive from COMMON_MAX_RISK_PER_TRADE
    KK_CHECK_NEAR(p.max_loss_ratio_e1, 0.021, 1e-9);
    // LIVE EMA periods are 10/25/71/97/192 (NOT the round 75/100/200 the enum labels imply)
    KK_CHECK(p.ema0_period == 10 && p.ema1_period == 25 && p.ema2_period == 71);
    KK_CHECK(p.ema3_period == 97 && p.ema4_period == 192);
    KK_CHECK(p.rsi_len == 14 && p.adx_len == 14);
}

void test_set_loader() {
    const std::string path = "/tmp/kenkem_test.set";
    FILE* f = std::fopen(path.c_str(), "w");
    std::fprintf(f, "; KenKem test set\n");
    std::fprintf(f, "E1_RR=2.10\n");
    std::fprintf(f, "MIN_TREND_QUALITY_E2=8\n");
    std::fprintf(f, "E4_HTF_TREND_FILTER=1\n");           // -> HTF_M5_ONLY
    std::fprintf(f, "ENABLE_E2_ENTRIES=false\n");
    std::fprintf(f, "SIDEWAYS_BLOCK_THRESHOLD=50 ; trailing comment\n");
    std::fprintf(f, "UNKNOWN_KEY=123\n");                 // ignored gracefully
    std::fclose(f);

    KenKemConfig p;
    int applied = load_set(p, path);
    KK_CHECK(applied == 5);                                // 5 known keys, unknown ignored
    KK_CHECK_NEAR(p.e1_rr, 2.10, 1e-9);
    KK_CHECK(p.min_tq_e2 == 8);
    KK_CHECK(p.e4_htf_filter == HTF_M5_ONLY);
    KK_CHECK(!p.enable_e2);
    KK_CHECK(p.sideways_block_thr == 50);

    KenKemConfig q;
    KK_CHECK(load_set(q, "/tmp/does_not_exist_kenkem.set") == -1);
}

void test_specs() {
    KenKemConfig p; p.apply_btcusd_specs();
    KK_CHECK_NEAR(p.contract_size, 1.0, 1e-9);
    KK_CHECK_NEAR(p.value_per_price_per_lot(), 1.0, 1e-9);   // tick_value/tick_size = 0.01/0.01
    KK_CHECK_NEAR(p.pip_size, 1.0, 1e-9);                    // BTC pip = 1 (EA :159)
    KK_CHECK_NEAR(p.std_lot, 0.30, 1e-9);                    // 0.15 * 2 BTC override (EA :161)
    KenKemConfig x; x.apply_xauusd_specs();
    KK_CHECK_NEAR(x.value_per_price_per_lot(), 100.0, 1e-9); // 1.00/0.01
    KK_CHECK_NEAR(x.pip_size, 0.01, 1e-9);                   // gold pip = 0.01 (2-digit)
    KK_CHECK_NEAR(x.std_lot, 0.15, 1e-9);                    // gold: no multiplier
    KK_CHECK_NEAR(x.normalize_lot(0.153), 0.15, 1e-9);
}

void run_all() {
    KK_RUN(test_defaults);
    KK_RUN(test_set_loader);
    KK_RUN(test_specs);
}

KK_TEST_MAIN()
