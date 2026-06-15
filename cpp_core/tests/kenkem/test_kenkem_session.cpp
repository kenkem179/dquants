// Locks the UTC valid-session windows. After the JST->UTC conversion the EA and this engine share one
// clock: Japan 0000-0330, London 0500-0930, NY 1200-1500 (UTC), end-INCLUSIVE to match the EA's `<=`.
#include "kk/kenkem/kenkem_config.hpp"
#include "kk/kenkem/engine.hpp"
#include "kk/common/test.hpp"

using namespace kk::kenkem;

// time-of-day -> epoch ms (day component is irrelevant: in_valid_session uses minutes % 1440).
static int64_t ms(int hh, int mm) { return (int64_t)(hh * 60 + mm) * 60000; }

void test_window_defaults() {
    KenKemConfig p;   // defaults are UTC now, offset 0
    KK_CHECK(p.japan_start == 0   && p.japan_end == 330);
    KK_CHECK(p.london_start == 500 && p.london_end == 930);
    KK_CHECK(p.ny_start == 1200   && p.ny_end == 1500);
    KK_CHECK(p.server_gmt_offset == 0);
}

void test_in_valid_session() {
    KenKemConfig p;

    // Japan (was 0900-1230 JST)
    KK_CHECK( in_valid_session(ms(0, 0),  p));   // start, inclusive
    KK_CHECK( in_valid_session(ms(3, 30), p));   // end, inclusive (EA uses <=)
    KK_CHECK(!in_valid_session(ms(3, 31), p));
    KK_CHECK(!in_valid_session(ms(4, 59), p));   // gap before London

    // London (was 1400-1830 JST)
    KK_CHECK( in_valid_session(ms(5, 0),  p));
    KK_CHECK( in_valid_session(ms(9, 30), p));   // end inclusive
    KK_CHECK(!in_valid_session(ms(9, 31), p));
    KK_CHECK(!in_valid_session(ms(11, 59), p));  // gap before NY

    // NY (was 2100-2400 JST)
    KK_CHECK( in_valid_session(ms(12, 0),  p));
    KK_CHECK( in_valid_session(ms(15, 0),  p));  // end inclusive (== old 2400 JST boundary)
    KK_CHECK(!in_valid_session(ms(15, 1),  p));
    KK_CHECK(!in_valid_session(ms(23, 0),  p));  // dead overnight

    // ignore flag forces always-valid
    p.ignore_valid_sessions = true;
    KK_CHECK(in_valid_session(ms(23, 0), p));
}

void run_all() {
    KK_RUN(test_window_defaults);
    KK_RUN(test_in_valid_session);
}

KK_TEST_MAIN()
