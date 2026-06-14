#include "kk/common/config.hpp"
#include "kk/common/test.hpp"
#include <fstream>
#include <cstdio>

static const char* kSet =
    "; sample baseline\n"
    "InpNodeGateEnabled=false   ; non-input in MQL\n"
    "InpBreakBufAtr=0.50\n"
    "InpRrBrk=1.8\n"
    "InpSlAtrBrk=1.48\n"
    "InpRiskAccPct=1.6\n"
    "InpMaxDailyDDPct=5.0\n"
    "InpEnableReversion=false\n"
    "InpAsiaSess=00:00-06:00\n"
    "InpBlockedHoursStr=8,10,11,16\n";

static std::string write_tmp() {
    std::string path = "/tmp/kk_test_baseline.set";
    std::ofstream f(path);
    f << kSet;
    f.close();
    return path;
}

static void test_load_overrides_defaults() {
    kk::Params p;
    int n = kk::load_set(p, write_tmp());
    KK_CHECK(n >= 8);
    KK_CHECK_NEAR(p.break_buf_atr, 0.50, 1e-12);
    KK_CHECK_NEAR(p.rr_brk, 1.8, 1e-12);
    KK_CHECK_NEAR(p.sl_atr_brk, 1.48, 1e-12);
    KK_CHECK_NEAR(p.risk_acc_pct, 1.6, 1e-12);
    KK_CHECK_NEAR(p.max_daily_dd_pct, 5.0, 1e-12);
    KK_CHECK(!p.enable_reversion);
    KK_CHECK(p.asia_sess == "00:00-06:00");
    KK_CHECK(p.blocked_hours == "8,10,11,16");
}

static void test_comments_and_whitespace_stripped() {
    kk::Params p;
    kk::load_set(p, write_tmp());
    // node_gate parsed normally in default mode (comment after ; stripped, value=false)
    KK_CHECK(!p.node_gate_enabled);
}

static void test_mimic_mt5_skips_noninput() {
    // In MT5 the non-input InpNodeGateEnabled keeps its compile constant (true) — the .set line is
    // ignored. mimic_mt5_noninput=true must therefore leave node_gate_enabled at the struct default.
    kk::Params p;
    KK_CHECK(p.node_gate_enabled);                 // struct default = code constant true
    kk::load_set(p, write_tmp(), /*mimic_mt5_noninput=*/true);
    KK_CHECK(p.node_gate_enabled);                 // still true — .set false was skipped
    KK_CHECK_NEAR(p.rr_brk, 1.8, 1e-12);           // input keys still applied
}

static void test_master_len() {
    kk::Params p;   // 50 * 3
    KK_CHECK(p.master_len() == 150);
}

static void run_all() {
    KK_RUN(test_load_overrides_defaults);
    KK_RUN(test_comments_and_whitespace_stripped);
    KK_RUN(test_mimic_mt5_skips_noninput);
    KK_RUN(test_master_len);
}

KK_TEST_MAIN()
