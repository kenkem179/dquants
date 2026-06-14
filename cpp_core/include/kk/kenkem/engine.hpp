// KenKem P7 — bar-replay backtest engine. Ties trigger -> snapshot -> entry -> manager together over
// the aligned M1/M3/M5/M15 series and produces equity + trade stats with realistic costs.
//
// No-lookahead: at forming M1 bar B, detection uses only closed bars (<= B-1); entry fills at bar B's
// OPEN (+spread). Management walks each bar's OHLC with an adverse-first path (SL before TP on ties).
// Bars are on MID (project convention); a long pays +half-spread in / takes -half-spread out.
#pragma once
#include "kk/kenkem/entries.hpp"
#include "kk/kenkem/trade_manager.hpp"
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
};

struct BtResult {
    double net = 0, pf = 0, end_balance = 0, max_dd = 0, win_rate = 0;
    int    trades = 0, wins = 0;
    std::vector<Trade> list;
    std::vector<double> equity;             // balance after each closed trade
};

namespace detail {
struct OpenPos { Position p; int64_t t_in; double entry_anchor; double pnl_acc; };
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

    for (int B = 1; B < N; ++B) {
        const kk::Bar& bar = b.m1.bars[B];
        if (start_ms && bar.ts_ms < start_ms) continue;
        if (end_ms && bar.ts_ms >= end_ms) break;
        const TfBundle::Align align = b.align_at(bar.ts_ms);

        // (1) Triggers from closed bars (<= B-1).
        update_triggers(b, cfg, B, align, tg);

        // (2) Entry decision (uses closed data); fill at this bar's open.
        if (B >= warmup_bars && (int)open.size() < cfg.max_concurrent_pos) {
            Snapshot snap = build_snapshot(b, cfg, B, align);
            if (snap.valid && snap.atrM1 > 0.0) {
                EntrySignal sig = detect_entry(b, cfg, B, align, snap, tg);
                if (sig.detected) {
                    bool block = cfg.block_opposite_dir && count_dir(!sig.is_long) > 0;
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
                            open.push_back({ p, bar.ts_ms, fill, -lot * cfg.commission_per_lot });
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
