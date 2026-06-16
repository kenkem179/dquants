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

// The trust guarantee: a .set may NOT override a param the EA hardcodes (ADX_LEN, RSI_LEN, etc.).
// Such a key must be ignored and the EA value retained, regardless of what the .set says.
void test_ea_locked_keys_ignored() {
    const std::string path = "/tmp/kenkem_locked_test.set";
    FILE* f = std::fopen(path.c_str(), "w");
    std::fprintf(f, "ADX_LEN=9\n");                    // EA hardcodes 14 -> must stay 14
    std::fprintf(f, "RSI_LEN=20\n");                   // EA hardcodes 14 -> must stay 14
    std::fprintf(f, "USE_CONVICTION_SCORING_E1=false\n"); // EA hardcodes true -> stays true
    std::fprintf(f, "ICHIMOKU_TENKAN=5\n");            // EA hardcodes 9 -> stays 9
    std::fprintf(f, "JAPAN_START=100\n");              // EA hardcodes 0 -> stays 0
    std::fprintf(f, "E1_RR=2.22\n");                   // real input -> applies
    std::fclose(f);

    KenKemConfig p;
    int applied = load_set(p, path);
    KK_CHECK(applied == 1);                            // only E1_RR is honorable
    KK_CHECK(p.adx_len == 14);                         // locked
    KK_CHECK(p.rsi_len == 14);                         // locked
    KK_CHECK(p.use_conviction_e1 == true);             // locked
    KK_CHECK(p.ichimoku_tenkan == 9);                  // locked
    KK_CHECK(p.japan_start == 0);                      // locked
    KK_CHECK_NEAR(p.e1_rr, 2.22, 1e-9);                // honorable input applied
    KK_CHECK(is_ea_locked_key("ADX_LEN") && is_ea_locked_key("RSI_LEN"));
    KK_CHECK(!is_ea_locked_key("E1_RR") && !is_ea_locked_key("MIN_TREND_QUALITY_E1"));
}

// Ledger G1: the engine must also load the DEPLOY-VEHICLE schema (Inp* keys, MT5 ||-delimited values),
// so ONE .set drives both the engine and the KK-KenKem EA — the precondition for any parity_diff.
void test_inp_deploy_schema_loader() {
    const std::string path = "/tmp/kenkem_inp_test.set";
    FILE* f = std::fopen(path.c_str(), "w");
    std::fprintf(f, "InpRiskPerTrade=0.02||0.02||0.002||0.2||N\n");   // MT5 ||-format -> stod stops at |
    std::fprintf(f, "InpE1On=false||false||0||true||N\n");
    std::fprintf(f, "InpE1Rr=1.9||1.9||0.19||19.0||N\n");
    std::fprintf(f, "InpMinMomentumAdx=13.9663\n");
    std::fprintf(f, "InpSidewaysBlock=48\n");
    std::fprintf(f, "InpE4HtfMode=4\n");                              // -> HTF_M5_OR_M15
    std::fprintf(f, "InpAdxLen=15\n");                                // KK-KenKem UN-LOCKS this (genuine input)
    std::fprintf(f, "InpEma4=192\n");
    std::fprintf(f, "InpRrSidewayAll=1.2\n");                         // sets all four e*_rr_sideway
    std::fprintf(f, "InpUseSessionFilter=true\n");                    // -> ignore_valid_sessions=false
    std::fprintf(f, "InpNyEnd=1500\n");
    std::fclose(f);

    KenKemConfig p;
    int applied = load_set(p, path);
    KK_CHECK(applied == 11);
    // single-risk EA model -> every per-entry ratio takes InpRiskPerTrade
    KK_CHECK_NEAR(p.max_loss_ratio_e1, 0.02, 1e-9);
    KK_CHECK_NEAR(p.max_loss_ratio_e5, 0.02, 1e-9);
    KK_CHECK(!p.enable_e1);
    KK_CHECK_NEAR(p.e1_rr, 1.9, 1e-9);
    KK_CHECK_NEAR(p.min_momentum_adx, 13.9663, 1e-9);
    KK_CHECK(p.sideways_block_thr == 48);
    KK_CHECK(p.e4_htf_filter == HTF_M5_OR_M15);
    KK_CHECK(p.adx_len == 15);                       // honored on the Inp* path (un-locked for KK-KenKem)
    KK_CHECK(p.ema4_period == 192);
    KK_CHECK_NEAR(p.e1_rr_sideway, 1.2, 1e-9);       // RrSidewayAll fans out to every entry
    KK_CHECK_NEAR(p.e4_rr_sideway, 1.2, 1e-9);
    KK_CHECK(!p.ignore_valid_sessions);              // session filter ON => engine enforces sessions
    KK_CHECK(p.ny_end == 1500);
    // OFF must restore 24h trading (ignore sessions) — the all-OFF == today's-EA guarantee.
    KenKemConfig q;
    apply_kv(q, "InpUseSessionFilter", "false");
    KK_CHECK(q.ignore_valid_sessions);
    // The ORIGINAL-name lock is unaffected: ADX_LEN (original schema) still refused.
    KenKemConfig r;
    KK_CHECK(!apply_kv(r, "ADX_LEN", "9") && r.adx_len == 14);
}

// Ledger G1: MT5 EXPORTS .set as UTF-16 LE (BOM + CRLF). The loader must decode it, else every key is
// mangled -> 0 keys applied -> engine silently runs on DEFAULTS (the silent parity trap).
void test_utf16_set_loader() {
    const std::string path = "/tmp/kenkem_utf16_test.set";
    FILE* f = std::fopen(path.c_str(), "wb");
    auto put16 = [&](const std::string& s) {                 // write ASCII as UTF-16 LE
        for (char ch : s) { unsigned char lo = (unsigned char)ch, hi = 0; std::fwrite(&lo,1,1,f); std::fwrite(&hi,1,1,f); }
    };
    unsigned char bom[2] = {0xFF, 0xFE}; std::fwrite(bom, 1, 2, f);   // UTF-16 LE BOM
    put16("InpE1Rr=2.5||2.5||0.25||25||N\r\n");               // MT5 ||-format + CRLF
    put16("InpSidewaysBlock=48\r\n");
    put16("InpUseSessionFilter=true\r\n");
    std::fclose(f);

    KenKemConfig p;
    int applied = load_set(p, path);
    KK_CHECK(applied == 3);                                   // decoded, not 0
    KK_CHECK_NEAR(p.e1_rr, 2.5, 1e-9);
    KK_CHECK(p.sideways_block_thr == 48);
    KK_CHECK(!p.ignore_valid_sessions);
}

void run_all() {
    KK_RUN(test_defaults);
    KK_RUN(test_set_loader);
    KK_RUN(test_specs);
    KK_RUN(test_ea_locked_keys_ignored);
    KK_RUN(test_inp_deploy_schema_loader);
    KK_RUN(test_utf16_set_loader);
}

KK_TEST_MAIN()
