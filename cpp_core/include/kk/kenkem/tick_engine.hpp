// KenKem P7 (TICK) — tick-replay backtest engine. Same signal/entry/SL-TP front-half as the bar
// engine (triggers -> snapshot -> detect_entry, all on CLOSED bars), but management is driven by the
// REAL bid/ask tick stream instead of a synthetic 4-point OHLC walk. This is the trustworthy path:
// the bar engine's OHLC walk flatters path-dependent exits (partial@0.2R -> breakeven -> chandelier
// trail) and disagrees wildly with MT5; replaying real ticks reproduces MT5's true execution.
//
// SHIFT MAP (identical to the bar engine): when the forming bar is F, detection uses closed bars <= F-1
// (update_triggers/build_snapshot/detect_entry with B=F). The signal armed on F-1 FILLS on the FIRST
// tick of bar F at the real ask (long) / bid (short). No synthetic half-spread is added — spread is
// already in the bid/ask path, exactly like MT5.
//
// Management per tick: feed the EXIT-side price (bid for a long, ask for a short) to the SAME
// manage_tick() the bar engine uses. Order per price is unchanged: full SL -> full TP -> partial+BE ->
// chandelier trail. Fills realize at the real tick price.
#pragma once
#include "kk/kenkem/engine.hpp"   // BtResult, Trade, detail::OpenPos, helpers
#include "kk/common/types.hpp"
#include <vector>
#include <cmath>
#include <cstdint>

namespace kk::kenkem {

class TickEngine {
public:
    explicit TickEngine(const TfBundle& bundle, const KenKemConfig& cfg,
                        int warmup_bars = 250, int64_t start_ms = 0, int64_t end_ms = 0)
        : b_(bundle), cfg_(cfg), warmup_(warmup_bars), start_ms_(start_ms), end_ms_(end_ms) {
        vppl_ = cfg_.value_per_price_per_lot();
        balance_ = cfg_.start_balance;
        peak_ = balance_;
        R_.end_balance = balance_;
        N_ = b_.m1.size();
        // Position the forming cursor at the last bar strictly before the test start, so the first
        // in-window tick fires exactly the boundary bar's signal (warmup bars never trade).
        cur_forming_ = 0;
        if (start_ms_ > 0) {
            for (int i = 0; i < N_; ++i) {
                if (b_.m1.bars[i].ts_ms < start_ms_) cur_forming_ = i;
                else break;
            }
        }
    }

    void on_tick(const kk::Tick& t) {
        // Advance the forming-bar index for this tick (largest bar whose open time <= ts).
        int forming = cur_forming_;
        while (forming + 1 < N_ && t.ts_ms >= b_.m1.bars[forming + 1].ts_ms) ++forming;

        // (1) Manage every open position with this tick (exit-side price), BEFORE any new entry so a
        //     position opened on this tick is not managed until the next tick (MT5 OnTick order).
        for (size_t k = 0; k < open_.size(); ) {
            detail::OpenPos& o = open_[k];
            const double px = o.p.is_long ? t.bid : t.ask;   // exit-side market price
            std::vector<Fill> fills;
            manage_tick(o.p, px, cfg_, fills);
            for (const Fill& f : fills) {
                const double pts = o.p.is_long ? (f.price - o.p.entry) : (o.p.entry - f.price);
                o.pnl_acc += f.lot * pts * vppl_ - f.lot * cfg_.commission_per_lot;
                if (f.reason != 'P') { o.exit_price = f.price; o.exit_tag = f.reason; }  // closing fill
            }
            if (!o.p.open) { realize_(o, t.ts_ms); open_.erase(open_.begin() + k); }
            else ++k;
        }

        // (2) New-bar handling per just-completed bar: bar-gated EXITS (session-end / panic / score-drop)
        //     first, then new-bar ENTRIES. Both use the closed-bar snapshot; fills at this tick's price.
        if (forming != cur_forming_) {
            for (int f = cur_forming_ + 1; f <= forming; ++f) { per_bar_exits_(f, t); on_bar_closed_(f, t); }
            cur_forming_ = forming;
        }
    }

    void finish(double last_bid, double last_ask, int64_t last_ts_ms) {
        for (size_t k = 0; k < open_.size(); ) {
            detail::OpenPos& o = open_[k];
            const double px = o.p.is_long ? last_bid : last_ask;
            const double pts = o.p.is_long ? (px - o.p.entry) : (o.p.entry - px);
            o.pnl_acc += o.p.lot * pts * vppl_ - o.p.lot * cfg_.commission_per_lot;
            o.p.open = false;
            o.exit_price = px; o.exit_tag = 'E';   // end-of-test forced close (no MT5 equivalent)
            realize_(o, last_ts_ms);
            open_.erase(open_.begin() + k);
        }
    }

    const BtResult& result() {
        R_.end_balance = balance_;
        R_.net = balance_ - cfg_.start_balance;
        R_.pf = (gross_loss_ > 0) ? gross_win_ / gross_loss_ : (gross_win_ > 0 ? 1e9 : 0.0);
        R_.win_rate = R_.trades > 0 ? (double)R_.wins / (double)R_.trades : 0.0;
        return R_;
    }

private:
    int count_dir_(bool is_long) const {
        int n = 0; for (auto& o : open_) if (o.p.is_long == is_long) ++n; return n; }

    // Bar-gated exits the EA evaluates on the first tick of a new bar using closed-bar values:
    // CLOSE_ALL_TRADES_AT_SESSION_END, fast-ADX panic, score-drop. Ports engine.hpp step (3) to ticks.
    // Closes at this tick's exit-side price. Tag 'E' = session-end, 'X' = panic/score-drop (both map to
    // the MT5 journal's DEAL_REASON_EXPERT = "EA"). Skips a position opened on this same bar.
    void per_bar_exits_(int f, const kk::Tick& t) {
        if (open_.empty()) return;
        const kk::Bar& bar = b_.m1.bars[f];
        const TfBundle::Align align = b_.align_at(bar.ts_ms);
        const bool session_ok = in_valid_session(bar.ts_ms, cfg_);
        Snapshot snap = build_snapshot(b_, cfg_, f, align);
        for (size_t k = 0; k < open_.size(); ) {
            detail::OpenPos& o = open_[k];
            if (o.t_in == bar.ts_ms) { ++k; continue; }     // never exit a just-opened position
            const double px = o.p.is_long ? t.bid : t.ask;  // exit-side market price
            bool close = false; char tag = 'E';
            if (cfg_.close_at_session_end && !session_ok) { close = true; tag = 'E'; }
            if (!close && snap.valid) {
                bool pe = panic_exit_triggers(o.p.kind, o.p.is_long, o.p.entry, o.p.sl, px,
                                              o.p.best, o.p.partial_done, b_, align, cfg_);
                bool se = !pe && score_drop_triggers(o.p.kind, o.p.is_long, o.p.entry, o.p.tp, px,
                                                     o.p.partial_done, snap, cfg_, o.exit_st);
                if (pe || se) { close = true; tag = 'X'; }
            }
            if (close) {
                const double pts = o.p.is_long ? (px - o.p.entry) : (o.p.entry - px);
                o.pnl_acc += o.p.lot * pts * vppl_ - o.p.lot * cfg_.commission_per_lot;
                o.p.open = false; o.exit_price = px; o.exit_tag = tag;
                realize_(o, t.ts_ms); open_.erase(open_.begin() + k);
            } else ++k;
        }
    }

    void on_bar_closed_(int f, const kk::Tick& t) {
        const kk::Bar& bar = b_.m1.bars[f];
        const TfBundle::Align align = b_.align_at(bar.ts_ms);

        // Trigger state machine must see EVERY bar in order (it accumulates cross/touch state).
        update_triggers(b_, cfg_, f, align, tg_);

        if (f < warmup_) return;
        if (start_ms_ && bar.ts_ms < start_ms_) return;
        if (end_ms_   && bar.ts_ms >= end_ms_)  return;

        const int64_t day = bar.ts_ms / 86400000;
        if (day != cur_day_) { cur_day_ = day; entries_today_ = 0; }
        const bool day_cap_ok = (cfg_.max_entries_per_day <= 0) || (entries_today_ < cfg_.max_entries_per_day);
        if (!day_cap_ok) return;
        if ((int)open_.size() >= cfg_.max_concurrent_pos) return;
        // Valid-session entry gate (the EA only ENTERS during the UTC Japan/London/NY windows). The bar
        // engine gates this; the tick engine was missing it -> entered off-session -> primary over-fire.
        if (!in_valid_session(bar.ts_ms, cfg_)) return;

        Snapshot snap = build_snapshot(b_, cfg_, f, align);
        if (!snap.valid || snap.atrM1 <= 0.0) return;
        // Occupancy: the EA blocks a new (kind,dir) entry while one is already open. Build the mask so
        // detect_entry blocks-without-consuming, matching CheckOpenPositions / checkOpen{L,S}E{n}==-1.
        bool occ[6][2] = {};
        for (const auto& o : open_) if (o.p.kind >= 1 && o.p.kind <= 5) occ[o.p.kind][o.p.is_long ? 0 : 1] = true;
        EntrySignal sig = detect_entry(b_, cfg_, f, align, snap, tg_, occ);
        if (!sig.detected) return;
        if (cfg_.block_opposite_dir && count_dir_(!sig.is_long) > 0) return;

        // Fill at THIS tick's real ask (long) / bid (short) — spread is in the price, no synthetic add.
        const double fill = sig.is_long ? t.ask : t.bid;
        const double risk = std::fabs(fill - sig.sl);
        if (risk <= 0.0) return;
        const double lot = position_size(cfg_.start_balance, sig.kind, risk, cfg_);
        Position p = open_position(sig.is_long, sig.kind, fill, sig.sl, sig.tp, lot, cfg_);
        open_.push_back({ p, bar.ts_ms, fill, -lot * cfg_.commission_per_lot });
        ++entries_today_;
    }

    void realize_(detail::OpenPos& o, int64_t t_out) {
        balance_ += o.pnl_acc;
        Trade tr; tr.kind = o.p.kind; tr.is_long = o.p.is_long; tr.t_in = o.t_in; tr.t_out = t_out;
        tr.entry = o.entry_anchor; tr.lot = o.p.init_lot; tr.pnl = o.pnl_acc;
        tr.risk = o.p.risk; tr.exit_price = o.exit_price; tr.exit_tag = o.exit_tag;
        tr.mfe_r = (o.p.risk > 0.0)
                 ? (o.p.is_long ? (o.p.best - o.p.entry) : (o.p.entry - o.p.best)) / o.p.risk : 0.0;
        R_.list.push_back(tr);
        if (o.pnl_acc >= 0) { gross_win_ += o.pnl_acc; ++R_.wins; } else { gross_loss_ += -o.pnl_acc; }
        ++R_.trades;
        if (balance_ > peak_) peak_ = balance_;
        if (peak_ - balance_ > R_.max_dd) R_.max_dd = peak_ - balance_;
        R_.equity.push_back(balance_);
    }

    const TfBundle& b_;
    KenKemConfig cfg_;
    int warmup_;
    int64_t start_ms_, end_ms_;
    double vppl_ = 0, balance_ = 0, peak_ = 0, gross_win_ = 0, gross_loss_ = 0;
    int N_ = 0, cur_forming_ = 0;
    int64_t cur_day_ = -1;
    int entries_today_ = 0;
    TriggerState tg_;
    std::vector<detail::OpenPos> open_;
    BtResult R_;
};

}  // namespace kk::kenkem
