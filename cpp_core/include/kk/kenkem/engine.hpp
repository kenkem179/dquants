// KenKem P7 — bar-replay backtest engine. Ties trigger -> snapshot -> entry -> manager together over
// the aligned M1/M3/M5/M15 series and produces equity + trade stats with realistic costs.
//
// No-lookahead: at forming M1 bar B, detection uses only closed bars (<= B-1); entry fills at bar B's
// OPEN (+spread). Management walks each bar's OHLC with an adverse-first path (SL before TP on ties).
// Bars are on MID (project convention); a long pays +half-spread in / takes -half-spread out.
#pragma once
#include "kk/kenkem/entries.hpp"
#include "kk/kenkem/trade_manager.hpp"
#include "kk/kenkem/exits.hpp"
#include "kk/kenkem/snapshot.hpp"
#include "kk/kenkem/triggers.hpp"
#include "kk/kenkem/tf_cache.hpp"
#include <vector>
#include <cmath>
#include <cstdint>

namespace kk::kenkem {

struct Trade {
    int    kind = 0; bool is_long = false;
    int64_t t_in = 0, t_out = 0;
    double entry = 0, lot = 0, pnl = 0;     // pnl in account currency, net of costs
    // Parity fields (populated by the tick engine; default-inert for the bar engine).
    double risk = 0;                        // |entry - SL| at fill (price)
    double exit_price = 0;                  // price of the closing fill
    double mfe_r = 0;                       // max favorable excursion in R (from Position.best)
    double mae_r = 0;                       // max adverse excursion in R (from Position.worst)
    char   exit_tag = '?';                  // 'S' stop/trail/BE, 'T' take-profit, 'E' end-of-test
    // Diagnostic-only (KK_TRADE_DIAG): trail/HR state at close, for over-trail parity investigation.
    bool   is_high_risk = false;            // HandleHighRiskEntry routed this trade (TP×mult, 0.55 partial)
    int    tp_ext = 0;                      // final tpExtensions reached
    int    ladder_stage = 0;                // final ladder stage reached
    bool   partial_done = false;            // partial slice executed
    double orig_tp = 0, final_tp = 0, final_sl = 0, best = 0;
};

struct BtResult {
    double net = 0, pf = 0, end_balance = 0, max_dd = 0, win_rate = 0;
    int    trades = 0, wins = 0;
    std::vector<Trade> list;
    std::vector<double> equity;             // balance after each closed trade
};

namespace detail {
struct OpenPos { Position p; int64_t t_in; double entry_anchor; double pnl_acc; ExitState exit_st;
                 double exit_price = 0; char exit_tag = '?';
                 bool partial_taken = false; };  // a real partial slice filled (hasTakenPartialProfit)
}

// Valid-session check (SessionManager): the EA only enters during the Japan/London/NY windows.
// bar ts_ms is UTC and the windows are UTC (server_gmt_offset stays 0). Windows are HHMM; the end is
// INCLUSIVE to match the EA's `adjustedTime <= *_END` (e.g. ny_end 1500 admits exactly 15:00 UTC).
inline bool in_valid_session(int64_t ts_ms, const KenKemConfig& c) {
    if (c.ignore_valid_sessions) return true;
    int srv = (int)(((ts_ms / 60000) % 1440 + (int64_t)c.server_gmt_offset * 60) % 1440);
    if (srv < 0) srv += 1440;
    auto inw = [&](int s, int e){ return srv >= (s/100)*60 + s%100 && srv <= (e/100)*60 + e%100; };
    return inw(c.japan_start, c.japan_end) || inw(c.london_start, c.london_end) || inw(c.ny_start, c.ny_end);
}

inline BtResult run_backtest(const TfBundle& b, const KenKemConfig& cfg,
                             int warmup_bars = 250, int64_t start_ms = 0, int64_t end_ms = 0) {
    BtResult R;
    const double vppl = cfg.value_per_price_per_lot();
    double balance = cfg.start_balance;
    double peak = balance;
    double gross_win = 0, gross_loss = 0;
    R.end_balance = balance;

    TriggerState tg;
    std::vector<detail::OpenPos> open;
    const int N = b.m1.size();

    auto count_dir = [&](bool is_long) {
        int n = 0; for (auto& o : open) if (o.p.is_long == is_long) ++n; return n; };

    // Per-UTC-day entry cap (MAX_ENTRIES_PER_DAY): a robust backstop for the original EA's per-session
    // trade caps, which the distilled engine never enforced. 0 = off.
    int64_t cur_day = -1;
    int     entries_today = 0;

    // Stateful governors (previously parsed-but-ignored). Keyed by entry kind (1..5) and direction.
    // Consecutive-loss-per-entry-type block: after MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE losses on a
    // (kind,dir), that bucket is blocked for ENTRY_BLOCK_AFTER_CONSECUTIVE_LOSS_MINS. MIN_SECONDS_BETWEEN
    // throttles new entries. These suppress the post-loss over-trading bleed the EA avoids.
    auto bucket = [](int kind, bool is_long){ return (kind & 7) * 2 + (is_long ? 0 : 1); };
    int     consec_loss[16] = {0};
    int64_t blocked_until[16] = {0};
    int64_t last_entry_ms = -1;

    for (int B = 1; B < N; ++B) {
        const kk::Bar& bar = b.m1.bars[B];
        if (start_ms && bar.ts_ms < start_ms) continue;
        if (end_ms && bar.ts_ms >= end_ms) break;
        const TfBundle::Align align = b.align_at(bar.ts_ms);

        const int64_t day = bar.ts_ms / 86400000;   // UTC calendar day
        if (day != cur_day) { cur_day = day; entries_today = 0; }
        const bool day_cap_ok = (cfg.max_entries_per_day <= 0) || (entries_today < cfg.max_entries_per_day);

        // (1) Triggers from closed bars (<= B-1).
        update_triggers(b, cfg, B, align, tg);

        // Closed-bar snapshot for this bar — shared by entry selection and the adaptive early-exits.
        Snapshot snap = (B >= warmup_bars) ? build_snapshot(b, cfg, B, align) : Snapshot{};

        // (2) Entry decision (uses closed data); fill at this bar's open. Only during valid UTC sessions.
        const bool session_ok = in_valid_session(bar.ts_ms, cfg);
        if (B >= warmup_bars && day_cap_ok && session_ok && (int)open.size() < cfg.max_concurrent_pos) {
            if (snap.valid && snap.atrM1 > 0.0) {
                EntrySignal sig = detect_entry(b, cfg, B, align, snap, tg);
                if (sig.detected) {
                    bool block = cfg.block_opposite_dir && count_dir(!sig.is_long) > 0;
                    // MIN_SECONDS_BETWEEN_ENTRIES throttle.
                    if (cfg.min_seconds_between > 0 && last_entry_ms >= 0 &&
                        bar.ts_ms - last_entry_ms < (int64_t)cfg.min_seconds_between * 1000) block = true;
                    // Consecutive-loss-per-entry-type block (auto-expires).
                    {
                        int bk = bucket(sig.kind, sig.is_long);
                        if (blocked_until[bk] > 0 && bar.ts_ms < blocked_until[bk]) block = true;
                        else if (blocked_until[bk] > 0) { blocked_until[bk] = 0; consec_loss[bk] = 0; }
                    }
                    if (!block) {
                        double half = 0.5 * bar.spread_mean;
                        double fill = bar.open + (sig.is_long ? half : -half);
                        double risk = std::fabs(fill - sig.sl);
                        if (risk > 0.0) {
                            // Research-mode constant sizing: risk a FIXED fraction of the INITIAL
                            // balance (not the compounding balance) so the equity curve is additive and
                            // DD/net measure the edge, not the compounding. Deployment can re-enable
                            // compounding later.
                            double lot = position_size(cfg.start_balance, sig.kind, risk, cfg);
                            Position p = open_position(sig.is_long, sig.kind, fill, sig.sl, sig.tp, lot, cfg);
                            // seed pnl with entry commission; balance changes only when the trade closes
                            open.push_back({ p, bar.ts_ms, fill, -lot * cfg.commission_per_lot, ExitState{} });
                            ++entries_today;
                            last_entry_ms = bar.ts_ms;
                        }
                    }
                }
            }
        }

        // (3) Manage all open positions over bar B (adverse-first OHLC walk).
        const double half = 0.5 * bar.spread_mean;
        double path_up[4]   = { bar.open, bar.low, bar.high, bar.close };   // up bar
        double path_down[4] = { bar.open, bar.high, bar.low, bar.close };   // down bar
        const double* path = (bar.close >= bar.open) ? path_up : path_down;

        for (size_t k = 0; k < open.size(); ) {
            detail::OpenPos& o = open[k];
            std::vector<Fill> fills;
            // Session-end flat (CLOSE_ALL_TRADES_AT_SESSION_END): close anything still open once we are
            // outside the valid UTC sessions. Then adaptive early-exits (panic / score-drop): evaluated
            // once at bar open on the closed-bar snapshot, BEFORE the OHLC walk. Skip the open bar.
            if (cfg.close_at_session_end && !session_ok && o.p.open && o.t_in != bar.ts_ms) {
                fills.push_back({ bar.open, o.p.lot, 'E' }); o.p.lot = 0; o.p.open = false;
            }
            if (snap.valid && o.p.open && o.t_in != bar.ts_ms) {
                bool px = panic_exit_triggers(o.p.kind, o.p.is_long, o.p.entry, o.p.sl, bar.open,
                                              o.p.best, o.p.partial_done, b, align, cfg);
                bool sx = !px && score_drop_triggers(o.p.kind, o.p.is_long, o.p.entry, o.p.tp, bar.open,
                                                     o.p.partial_done, snap, cfg, o.exit_st);
                if (px || sx) { fills.push_back({ bar.open, o.p.lot, 'X' }); o.p.lot = 0; o.p.open = false; }
            }
            for (int s = 0; s < 4 && o.p.open; ++s) manage_tick(o.p, path[s], cfg, fills);
            for (const Fill& f : fills) {
                double exit_px = f.price - (o.p.is_long ? half : -half);     // pay spread on exit
                double pts = o.p.is_long ? (exit_px - o.p.entry) : (o.p.entry - exit_px);
                double pnl = f.lot * pts * vppl - f.lot * cfg.commission_per_lot;
                o.pnl_acc += pnl;
            }
            if (!o.p.open) {
                balance += o.pnl_acc;   // realize (entry commission seeded into pnl_acc)
                Trade t; t.kind = o.p.kind; t.is_long = o.p.is_long; t.t_in = o.t_in; t.t_out = bar.ts_ms;
                t.entry = o.entry_anchor; t.lot = o.p.init_lot; t.pnl = o.pnl_acc;
                R.list.push_back(t);
                if (o.pnl_acc >= 0) { gross_win += o.pnl_acc; ++R.wins; } else { gross_loss += -o.pnl_acc; }
                // Consecutive-loss-per-entry-type tracking: arm a timed block after N losses; a win resets.
                {
                    int bk = bucket(o.p.kind, o.p.is_long);
                    if (o.pnl_acc < 0) {
                        if (++consec_loss[bk] >= cfg.max_consec_losses_type && cfg.max_consec_losses_type > 0)
                            blocked_until[bk] = bar.ts_ms + (int64_t)cfg.consec_loss_block_mins * 60000;
                    } else { consec_loss[bk] = 0; }
                }
                ++R.trades;
                if (balance > peak) peak = balance;
                if (peak - balance > R.max_dd) R.max_dd = peak - balance;
                R.equity.push_back(balance);
                open.erase(open.begin() + k);
            } else { ++k; }
        }
    }

    R.end_balance = balance;
    R.net = balance - cfg.start_balance;
    R.pf = (gross_loss > 0) ? gross_win / gross_loss : (gross_win > 0 ? 1e9 : 0.0);
    R.win_rate = R.trades > 0 ? (double)R.wins / (double)R.trades : 0.0;
    return R;
}

}  // namespace kk::kenkem
