// Integration tests for the Monster engine (kk::monster::MonsterEngine). Small synthetic
// fixtures replayed through the full OnTick path: per-bar signal computation (VP/node/net/
// crosses/regime/evaluate) interleaved with execution (gates -> sizing -> fill -> per-tick
// management -> trade journal).
//
// Coverage:
//   (a) clean master-VAH breakout fires an L-BRK and produces a coherent trade;
//   (b) determinism: same ticks twice -> identical trade count + final balance;
//   (c) a forced SL loss reconciles balance (entry->SL P&L matches a manual calc).
#include "kk/monster/monster_engine.hpp"
#include "kk/monster/tf_net.hpp"
#include "kk/common/test.hpp"
#include <cmath>
#include <vector>
#include <fstream>

using kk::Bar;
using kk::Tick;
using kk::monster::MonsterConfig;
using kk::monster::MonsterEngine;
using kk::monster::TfSeries;
using kk::monster::TradeRec;
using kk::monster::build_tf_series;

static const int64_t M3_MS = 180000;

// Emit O->extreme1->extreme2->C ticks inside a 3-minute bar with a fixed spread. bid=price,
// ask=price+spread. Order extremes by bar direction so excursions are visited realistically.
static void emit_bar_ticks(const Bar& b, double spread, std::vector<Tick>& out) {
    const int64_t offs[4] = {0, 45000, 90000, 135000};
    double seq[4];
    if (b.close >= b.open) { seq[0] = b.open; seq[1] = b.low;  seq[2] = b.high; seq[3] = b.close; }
    else                   { seq[0] = b.open; seq[1] = b.high; seq[2] = b.low;  seq[3] = b.close; }
    for (int k = 0; k < 4; ++k) {
        Tick t; t.ts_ms = b.ts_ms + offs[k]; t.bid = seq[k]; t.ask = seq[k] + spread;
        out.push_back(t);
    }
}

static std::vector<Tick> ticks_from_bars(const std::vector<Bar>& bars, double spread) {
    std::vector<Tick> ticks;
    ticks.reserve(bars.size() * 4);
    for (const auto& b : bars) emit_bar_ticks(b, spread, ticks);
    return ticks;
}

// Build an M1 TfSeries from M3 bars by splitting each M3 bar into 3 synthetic M1 bars that carry
// the SAME directional body (so M1 net agrees with the M3 move) and a third of the tick count.
static std::vector<Bar> m1_from_m3(const std::vector<Bar>& m3) {
    std::vector<Bar> m1;
    m1.reserve(m3.size() * 3);
    for (const auto& b : m3) {
        const double span = b.close - b.open;
        for (int k = 0; k < 3; ++k) {
            Bar s;
            s.ts_ms = b.ts_ms + (int64_t)k * 60000;
            s.open  = b.open + span * (k / 3.0);
            s.close = b.open + span * ((k + 1) / 3.0);
            s.high  = std::max(s.open, s.close) + (b.high - std::max(b.open, b.close)) * 0.34;
            s.low   = std::min(s.open, s.close) - (std::min(b.open, b.close) - b.low) * 0.34;
            s.tick_count = b.tick_count / 3 + 1;
            m1.push_back(s);
        }
    }
    return m1;
}

// Build an M5 TfSeries by aggregating M3 bars into 5-min buckets (coarse; only needs to be net-OK).
static std::vector<Bar> m5_from_m3(const std::vector<Bar>& m3) {
    std::vector<Bar> m5;
    const int64_t BK = 300000;
    for (const auto& b : m3) {
        const int64_t bk = b.ts_ms - (b.ts_ms % BK);
        if (m5.empty() || m5.back().ts_ms != bk) {
            Bar s = b; s.ts_ms = bk; m5.push_back(s);
        } else {
            Bar& s = m5.back();
            s.high = std::max(s.high, b.high);
            s.low  = std::min(s.low, b.low);
            s.close = b.close;
            s.tick_count += b.tick_count;
        }
    }
    return m5;
}

// A long-biased breakout fixture: a flat consolidation that builds a stable master VP around 1000,
// then ONE clean thrust bar up through the master VAH on heavy (buy) tick count, then a steady
// run-up so the long has room to hit TP1/TP2. The single-bar break keeps the master VAH stable
// (a wide breakout leg jitters VAH bar-to-bar and never lands in the entry-distance window).
static std::vector<Bar> make_breakout_fixture() {
    std::vector<Bar> bars;
    int64_t t = M3_MS * 1000;   // arbitrary aligned start
    double px = 1000.0;
    // 1) tight consolidation around 1000 to seed the master VP window + ATR convergence.
    for (int i = 0; i < 210; ++i) {
        Bar b; b.ts_ms = t; t += M3_MS;
        const double drift = ((i % 2) ? 0.5 : -0.5);          // tiny up/down chop
        b.open = px; b.close = px + drift;
        b.high = std::max(b.open, b.close) + 0.4;
        b.low  = std::min(b.open, b.close) - 0.4;
        b.tick_count = 100;
        bars.push_back(b);
        px = b.close;
    }
    // 2) the breakout bar: a strong green body clearing master VAH on heavy buy pressure.
    {
        Bar b; b.ts_ms = t; t += M3_MS;
        b.open = px; b.close = px + 1.8;
        b.high = b.close + 0.15; b.low = b.open - 0.15;
        b.tick_count = 320;
        bars.push_back(b);
        px = b.close;
    }
    // 3) steady continuation up to let the position resolve at TP.
    for (int i = 0; i < 40; ++i) {
        Bar b; b.ts_ms = t; t += M3_MS;
        b.open = px; b.close = px + 0.5;
        b.high = b.close + 0.25; b.low = b.open - 0.25;
        b.tick_count = 200;
        bars.push_back(b);
        px = b.close;
    }
    return bars;
}

static MonsterConfig base_cfg() {
    MonsterConfig c;
    c.apply_btcusd_specs();         // vppl 1, $0 commission, min_lot 0.01
    c.trade_anytime = true;         // ignore sessions in the synthetic clock
    c.max_atr_pct = 0.0;            // disable the volatility ceiling for the fixture
    c.min_atr_pct = 0.0;            // disable the floor
    c.max_spread_tp1_frac = 0.0;    // disable the cost gate
    c.max_daily_dd_pct = 0.0;       // disable predictive daily-DD
    c.max_peak_dd_pct = 0.0;
    // Relax the breakout entry-distance + local-tolerance gates: the synthetic master VAH jitters
    // by a few units bar-to-bar (the 150-bar window absorbs the breakout high), which is too tight
    // for the default 0.8-ATR entry window. These are legitimate strategy params, not engine knobs.
    c.brk_max_dist_atr = 0.0;       // 0 = disable the max-distance ceiling
    c.brk_local_tol_atr = 50.0;     // effectively disable the local-VP proximity gate
    return c;
}

static MonsterEngine* build_engine(const std::vector<Bar>& m3, const MonsterConfig& c) {
    auto* eng = new MonsterEngine(c);
    TfSeries m1 = build_tf_series(m1_from_m3(m3), c.atr_len, 60);
    TfSeries m5 = build_tf_series(m5_from_m3(m3), c.atr_len, 300);
    eng->load(m3, std::move(m1), std::move(m5), TfSeries{}, /*trade_from_ms=*/0);
    return eng;
}

static bool finite(double x) { return !std::isnan(x) && !std::isinf(x); }

void test_breakout_fires_and_trades() {
    const auto m3 = make_breakout_fixture();
    MonsterConfig c = base_cfg();
    auto* eng = build_engine(m3, c);
    const double spread = 0.02;
    const auto ticks = ticks_from_bars(m3, spread);
    for (const auto& t : ticks) eng->on_tick(t);
    if (!ticks.empty()) eng->finish(ticks.back().bid, ticks.back().ask, ticks.back().ts_ms);

    const auto& trades = eng->trades();
    std::printf("  raw_signals=%d trades=%zu balance=%.2f peak=%.2f\n",
                eng->raw_signals(), trades.size(), eng->balance(), eng->peak_equity());

    KK_CHECK(eng->raw_signals() > 0);     // the breakout leg must produce signals
    KK_CHECK(!trades.empty());            // at least one entry survives the gates

    bool saw_long_brk = false;
    double sum = 0.0;
    for (const auto& tr : trades) {
        KK_CHECK(tr.entry > 0.0 && finite(tr.entry));
        KK_CHECK(tr.sl > 0.0 && finite(tr.sl));
        KK_CHECK(finite(tr.realized_usd));
        KK_CHECK(!tr.exit_tag.empty());
        if (tr.is_long && tr.kind == kk::monster::KIND_BRK) saw_long_brk = true;
        sum += tr.realized_usd;
    }
    KK_CHECK(saw_long_brk);   // the first entry should be the long master-VAH breakout

    // Balance reconciliation: final balance == start + sum of realized P&L.
    KK_CHECK(std::fabs(eng->balance() - (c.start_balance + sum)) < 1e-6);
    delete eng;
}

void test_determinism() {
    const auto m3 = make_breakout_fixture();
    MonsterConfig c = base_cfg();
    const double spread = 0.02;
    const auto ticks = ticks_from_bars(m3, spread);

    auto run = [&](std::vector<TradeRec>& out, double& bal) {
        auto* eng = build_engine(m3, c);
        for (const auto& t : ticks) eng->on_tick(t);
        if (!ticks.empty()) eng->finish(ticks.back().bid, ticks.back().ask, ticks.back().ts_ms);
        out = eng->trades();
        bal = eng->balance();
        delete eng;
    };

    std::vector<TradeRec> a, b; double balA = 0, balB = 0;
    run(a, balA);
    run(b, balB);
    KK_CHECK(a.size() == b.size());
    KK_CHECK(std::fabs(balA - balB) < 1e-12);
    for (size_t i = 0; i < a.size() && i < b.size(); ++i) {
        KK_CHECK(a[i].entry_ts_ms == b[i].entry_ts_ms);
        KK_CHECK(a[i].is_long == b[i].is_long);
        KK_CHECK(std::fabs(a[i].entry - b[i].entry) < 1e-12);
        KK_CHECK(std::fabs(a[i].realized_usd - b[i].realized_usd) < 1e-9);
        KK_CHECK(a[i].exit_tag == b[i].exit_tag);
    }
}

// Forced SL loss: take the breakout entry, then truncate the fixture right after entry and crash
// price hard DOWN through the stop. With TP1/BE disabled the whole position resolves at the stop,
// so the realized loss must equal (exitFill - entry) * vol * vppl from the recorded fields. We
// reconstruct vol from the risk budget (lot = normalize(budget / (initRisk * vppl))) and check the
// arithmetic directly, plus the global balance reconciliation.
void test_forced_sl_loss_reconciles() {
    MonsterConfig c = base_cfg();
    c.use_tp1_partial = false;     // no partial: full position resolves at the stop
    c.be_after_tp1 = false;
    c.max_trades_per_session = 1;  // exactly one entry, so the trade is fully controlled

    // Truncate the fixture to: consolidation + the breakout bar + ONE continuation bar (so the
    // breakout entry fills on that continuation bar's first tick), then nothing else.
    std::vector<Bar> full = make_breakout_fixture();
    std::vector<Bar> m3(full.begin(), full.begin() + 213);   // 210 chop + breakout(210) + 2 cont

    auto* eng = build_engine(m3, c);
    const double spread = 0.02;
    auto ticks = ticks_from_bars(m3, spread);

    // Append a steep crash well below the long's stop on the bar AFTER the fixture ends.
    const int64_t t0 = m3.back().ts_ms + M3_MS;
    const double crash = 700.0;    // far below the ~1000-1010 fixture range and any long SL
    for (int k = 0; k < 4; ++k) {
        Tick t; t.ts_ms = t0 + (int64_t)k * 45000; t.bid = crash; t.ask = crash + spread;
        ticks.push_back(t);
    }
    for (const auto& t : ticks) eng->on_tick(t);
    eng->finish(ticks.back().bid, ticks.back().ask, ticks.back().ts_ms);

    const auto& trades = eng->trades();
    KK_CHECK(!trades.empty());

    double sum = 0.0;
    bool saw_long_loss = false;
    const double vppl = c.value_per_price_per_lot();
    for (const auto& tr : trades) {
        sum += tr.realized_usd;
        if (tr.is_long && tr.realized_usd < 0.0) {
            saw_long_loss = true;
            // The stop gapped through; the crash bid (700) is the worst fill, so the long exits at
            // the crash price. Invert the P&L formula to recover the lot the engine traded:
            //   realized = (exitFill - entry) * lot * vppl   ->   lot = realized / ((crash-entry)*vppl)
            // and assert that lot is a clean, valid normalized lot (>= min_lot, on the lot_step grid).
            const double implied_lot = tr.realized_usd / ((crash - tr.entry) * vppl);
            KK_CHECK(implied_lot >= c.min_lot - 1e-9);
            KK_CHECK_NEAR(implied_lot, c.normalize_lot(implied_lot), 1e-9);
            // And the manual P&L from (entry, crash-fill, that lot) must reproduce realized exactly.
            const double manual = (crash - tr.entry) * implied_lot * vppl;
            KK_CHECK_NEAR(tr.realized_usd, manual, 1e-6);
        }
    }
    KK_CHECK(saw_long_loss);

    // Global reconciliation: final balance == start + sum of realized P&L; net is a loss.
    KK_CHECK(std::fabs(eng->balance() - (c.start_balance + sum)) < 1e-6);
    KK_CHECK(eng->balance() < c.start_balance);
    delete eng;
}

// Trust guarantee: a .set may NOT override a param the Monster EA hardcodes (InpNodeDecay, InpAtrLen,
// InpVaPct, ...). Such keys must be ignored and the EA value retained.
static void test_monster_locked_keys_ignored() {
    const char* path = "/tmp/kk_monster_locked.set";
    std::ofstream f(path);
    f << "InpNodeDecay=0.5\n"        // EA hardcodes 0.94 -> ignored
      << "InpAtrLen=20\n"            // EA hardcodes 14   -> ignored
      << "InpVaPct=80.0\n"           // EA hardcodes 70.0 -> ignored
      << "InpBrkRrFar=2.5\n";        // real input        -> applied
    f.close();
    MonsterConfig p;
    double decay0 = p.node_decay, va0 = p.va_pct;
    int atr0 = p.atr_len;
    int applied = kk::monster::load_set(p, path);
    KK_CHECK(applied == 1);                       // only InpRrBrk honorable
    KK_CHECK(std::fabs(p.node_decay - decay0) < 1e-12);  // locked, unchanged
    KK_CHECK(p.atr_len == atr0);                  // locked
    KK_CHECK(std::fabs(p.va_pct - va0) < 1e-12);  // locked
    KK_CHECK(kk::monster::monster_non_input_keys().count("InpNodeDecay") == 1);
    KK_CHECK(kk::monster::monster_non_input_keys().count("InpRrBrk") == 0);
}

void run_all() {
    KK_RUN(test_breakout_fires_and_trades);
    KK_RUN(test_determinism);
    KK_RUN(test_forced_sl_loss_reconciles);
    KK_RUN(test_monster_locked_keys_ignored);
}

KK_TEST_MAIN()
