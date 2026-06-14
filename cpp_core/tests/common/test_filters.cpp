// Unit tests for sessions + blocked hours + max-trades + ATR%/spread gates (filters.hpp).
#include "kk/common/filters.hpp"
#include "kk/common/test.hpp"

using kk::Params; using kk::Sessions; using kk::utc_parts;

static void test_session_windows() {
    Params p; Sessions s; s.init(p);   // defaults: Asia 00-06, Ldn 07-11, NY 12:30-16:30
    KK_CHECK(s.session_id(0) == 1);            // 00:00 Asia
    KK_CHECK(s.session_id(5 * 60 + 59) == 1);  // 05:59 Asia
    KK_CHECK(s.session_id(6 * 60) == 0);       // 06:00 gap
    KK_CHECK(s.session_id(7 * 60) == 2);       // 07:00 London
    KK_CHECK(s.session_id(10 * 60 + 59) == 2); // 10:59 London
    KK_CHECK(s.session_id(11 * 60) == 0);      // 11:00 gap
    KK_CHECK(s.session_id(12 * 60 + 30) == 3); // 12:30 NY
    KK_CHECK(s.session_id(16 * 60 + 29) == 3); // 16:29 NY
    KK_CHECK(s.session_id(16 * 60 + 30) == 0); // 16:30 end
    KK_CHECK(s.session_id(20 * 60) == 0);      // 20:00 none
}

static void test_blocked_hours() {
    Params p; Sessions s; s.init(p);   // default "8,10,11,16"
    KK_CHECK(s.is_blocked_hour(8));
    KK_CHECK(s.is_blocked_hour(10));
    KK_CHECK(s.is_blocked_hour(11));
    KK_CHECK(s.is_blocked_hour(16));
    KK_CHECK(!s.is_blocked_hour(9));
    KK_CHECK(!s.is_blocked_hour(12));
}

static void test_blocked_hours_range() {
    Params p; p.blocked_hours = "9-11,16"; Sessions s; s.init(p);
    KK_CHECK(s.is_blocked_hour(9) && s.is_blocked_hour(10) && s.is_blocked_hour(11));
    KK_CHECK(s.is_blocked_hour(16));
    KK_CHECK(!s.is_blocked_hour(8) && !s.is_blocked_hour(12));
}

static void test_max_trades_resets_on_session_change() {
    Params p; p.max_trades_per_session = 2; Sessions s; s.init(p);
    s.update(0);                  // Asia
    KK_CHECK(s.max_trades_ok()); s.on_fill();
    KK_CHECK(s.max_trades_ok()); s.on_fill();
    KK_CHECK(!s.max_trades_ok());            // 2 trades hit the cap
    s.update(7 * 60);             // London -> counter resets
    KK_CHECK(s.max_trades_ok());
    KK_CHECK(s.trades_this_session() == 0);
}

static void test_atr_and_spread_gates() {
    Params p; p.min_atr_pct = 0.0156; p.max_atr_pct = 0.158; p.pip_size = 0.01;
    p.max_spread_pips = 40.0; p.max_spread_tp1_frac = 0.25;
    // atr/price*100: 50/100000*100 = 0.05 -> in band.
    KK_CHECK(kk::atr_pct_ok(50.0, 100000.0, p));
    KK_CHECK(!kk::atr_pct_ok(5.0, 100000.0, p));      // 0.005 < floor
    KK_CHECK(!kk::atr_pct_ok(200.0, 100000.0, p));    // 0.2 > ceiling
    // spread 0.30 / pip 0.01 = 30 pips <= 40 ok; 0.50 -> 50 pips > 40 blocked.
    KK_CHECK(kk::spread_ok(100.0, 100.30, p));
    KK_CHECK(!kk::spread_ok(100.0, 100.50, p));
    // TP1 cost-clearance: tp1 dist = 20, frac 0.25 -> spread must be <= 5.
    KK_CHECK(kk::spread_vs_tp1_ok(100.0, 104.0, 120.0, 100.0, p));
    KK_CHECK(!kk::spread_vs_tp1_ok(100.0, 106.0, 120.0, 100.0, p));
}

static void test_utc_parts() {
    // 2025-08-11 00:06:00 UTC = 1754870760 s.
    const auto u = utc_parts(1754870760LL * 1000);
    KK_CHECK(u.year == 2025 && u.mon == 8 && u.day == 11);
    KK_CHECK(u.hour == 0 && u.min == 6);
    KK_CHECK(u.day_key == 20250811);
    KK_CHECK(u.min_of_day == 6);
}

void run_all() {
    KK_RUN(test_session_windows);
    KK_RUN(test_blocked_hours);
    KK_RUN(test_blocked_hours_range);
    KK_RUN(test_max_trades_resets_on_session_change);
    KK_RUN(test_atr_and_spread_gates);
    KK_RUN(test_utc_parts);
}

KK_TEST_MAIN()
