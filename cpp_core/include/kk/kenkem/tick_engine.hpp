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
#include "kk/kenkem/risk_exec.hpp" // execute-stage risk routing (high-risk path + ATR block)
#include "kk/common/types.hpp"
#include <vector>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <cstdio>
#include <cstdlib>

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

        // (0) Session-counter reset at the new-bar event, BEFORE managing closes — matches the EA, where
        //     OnTick's new-bar block (UpdateSessionTracking) runs before ProcessAllTrades/DetectNewEntry.
        //     So a position closing on a new session's first tick increments the NEW session's counters.
        if (forming != cur_forming_)
            for (int f = cur_forming_ + 1; f <= forming; ++f) update_session_(b_.m1.bars[f].ts_ms);

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
                if (f.reason == 'P') o.partial_taken = true;                            // real partial slice
                else { o.exit_price = f.price; o.exit_tag = f.reason; }                  // closing fill
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
            realize_(o, last_ts_ms, /*count_session=*/false);   // not a real EA close -> no counter bump
            open_.erase(open_.begin() + k);
        }
    }

    // DIAGNOSTIC ONLY: feed MT5's per-bar logged atr_pctile (from the bar trace) as an oracle, joined
    // by bar.ts_ms-60000 == mt5_ts. Isolates whether the ATR-percentile gate is the SOLE parity blocker:
    // run with ATR gates ON but the percentile taken from MT5. Never used in production.
    void set_pctile_oracle(const std::unordered_map<int64_t, double>* m) { pctile_oracle_ = m; }

    int arm_e1_count() const { return arm_e1_; }
    int arm_e2_count() const { return arm_e2_; }
    long arm_e1_cross() const { return tg_.arm_e1_cross; }
    long arm_e1_touch() const { return tg_.arm_e1_touch; }
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

    // Trading-session identity (SessionManager::GetCurrentSession): 1=ASIA/Japan, 2=EU/London, 3=US/NY,
    // 0=NONE. Uses the SAME UTC windows as in_valid_session, with if/else-if precedence (Japan, then
    // London, then NY) so it mirrors the EA's GetCurrentSession ladder. The session counters
    // (sessionLossCount, tradeSLTPCountInSession) reset whenever this id changes to a new non-zero value
    // (UpdateSessionTracking: `newSession != currentSession && newSession != "NONE"`).
    int session_id_(int64_t ts_ms) const {
        if (cfg_.ignore_valid_sessions) return 1;  // always "in session" -> single bucket, never resets
        int srv = (int)(((ts_ms / 60000) % 1440 + (int64_t)cfg_.server_gmt_offset * 60) % 1440);
        if (srv < 0) srv += 1440;
        auto inw = [&](int s, int e){ return srv >= (s/100)*60 + s%100 && srv <= (e/100)*60 + e%100; };
        if (inw(cfg_.japan_start, cfg_.japan_end))   return 1;
        if (inw(cfg_.london_start, cfg_.london_end)) return 2;
        if (inw(cfg_.ny_start,    cfg_.ny_end))      return 3;
        return 0;
    }
    // Reset the per-session caps when a new named session begins (mirrors UpdateSessionTracking, which
    // runs at the new-bar event BEFORE ProcessAllTrades/DetectNewEntry).
    void update_session_(int64_t ts_ms) {
        const int id = session_id_(ts_ms);
        if (id != 0 && id != cur_session_) {
            cur_session_ = id; session_losses_ = 0; session_sltp_ = 0; high_risk_count_ = 0;
        }
    }

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
        const int e1u0 = tg_.ema_up, e1d0 = tg_.ema_down, e2u0 = tg_.e75_up, e2d0 = tg_.e75_down;
        const long ac0 = tg_.arm_e1_cross, at0 = tg_.arm_e1_touch;
        update_triggers(b_, cfg_, f, align, tg_);
        if (start_ms_ == 0 || bar.ts_ms >= start_ms_) {  // count arms only in-window
            if (e1u0 == -1 && tg_.ema_up   != -1) ++arm_e1_;
            if (e1d0 == -1 && tg_.ema_down != -1) ++arm_e1_;
            if (e2u0 == -1 && tg_.e75_up   != -1) ++arm_e2_;
            if (e2d0 == -1 && tg_.e75_down != -1) ++arm_e2_;
            if (emit_arms_) {   // diagnostic: per-bar E1 arm event (consumption-aware) — src + dir
                const char* src = (tg_.arm_e1_cross > ac0) ? "cross"
                                : (tg_.arm_e1_touch > at0) ? "touch" : nullptr;
                if (src) {
                    const int tf = tg_.e1_cross_tf;  // only meaningful for cross arms
                    if (e1u0 == -1 && tg_.ema_up   != -1)
                        std::fprintf(stderr, "ARMFIRE,%lld,L,%s,%d\n", (long long)bar.ts_ms, src, tf);
                    if (e1d0 == -1 && tg_.ema_down != -1)
                        std::fprintf(stderr, "ARMFIRE,%lld,S,%s,%d\n", (long long)bar.ts_ms, src, tf);
                }
            }
        }

        if (emit_armstate_ && (start_ms_ == 0 || bar.ts_ms >= start_ms_)) {
            // Per-bar E1 latch age, mirroring the EA's KKE1ARM (armU/armD = currentBar - lastEMACross).
            // Emit only when a latch is armed (matches the EA trace's print condition). Diff bar-for-bar.
            const int au = (tg_.ema_up   != -1) ? (f - tg_.ema_up)   : -1;
            const int ad = (tg_.ema_down != -1) ? (f - tg_.ema_down) : -1;
            if (au != -1 || ad != -1)
                std::fprintf(stderr, "ESTATE,%lld,%d,%d\n", (long long)bar.ts_ms, au, ad);
        }

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
        // Per-session hard stops checked at the top of every Entry's Detect() (Entry1/2/4.mqh:81-90):
        //   sessionLossCount >= MAX_SESSION_LOSSES   -> block (>=, so the Nth loss blocks)
        //   tradeSLTPCountInSession > MAX_SLTP_COUNT  -> block (>, so up to N closes allowed)
        if (cfg_.max_session_losses > 0 && session_losses_ >= cfg_.max_session_losses) return;
        if (cfg_.max_sltp_per_session > 0 && session_sltp_ > cfg_.max_sltp_per_session) return;
        // Global losing-streak cooldown (IsBlockedByLosingStreak). In the EA this wraps the entire
        // DetectNewEntry block, so when blocked Detect() never runs and triggers are NOT consumed —
        // returning here (before detect_entry) preserves trigger state identically.
        if (cfg_.enable_loss_cooldowns && losing_streak_block_until_ > 0 &&
            t.ts_ms < losing_streak_block_until_) return;

        Snapshot snap = build_snapshot(b_, cfg_, f, align);
        if (!snap.valid || snap.atrM1 <= 0.0) return;
        if (pctile_oracle_) {   // diagnostic: replace engine percentile with MT5's logged value
            auto it = pctile_oracle_->find(bar.ts_ms);   // tick-engine bars share MT5 trace's ts grid
            if (it != pctile_oracle_->end()) snap.atr_pctile = it->second;
        }
        // Occupancy: the EA blocks a new (kind,dir) entry while one is already open. Build the mask so
        // detect_entry blocks-without-consuming, matching CheckOpenPositions / checkOpen{L,S}E{n}==-1.
        bool occ[6][2] = {};
        for (const auto& o : open_) if (o.p.kind >= 1 && o.p.kind <= 5) occ[o.p.kind][o.p.is_long ? 0 : 1] = true;
        EntrySignal sig = detect_entry(b_, cfg_, f, align, snap, tg_, occ);
        if (!sig.detected) return;

        // ---- EXECUTE STAGE (DetectNewEntry post-detection): faithful risk routing (risk_exec.hpp) ----
        // Lot + routing are computed from the detection ANCHOR (entry=close[1], sl) exactly as the EA;
        // the position then FILLS at the live tick. riskDist = |anchorEntry - sl| (EA |stopLoss-entryPrice|).
        const double anchorEntry = sig.entry;
        const double riskDist = sig.risk;
        if (riskDist <= 0.0) return;
        double lot = process_lot(sig.kind, balance_, riskDist, anchorEntry, cfg_);
        const double potentialLossUSD = riskDist * lot * cfg_.contract_size;
        const double entryMaxLoss = entry_max_loss_usd(sig.kind, balance_, cfg_);
        const bool min_sec_blocked = (last_entry_ms_ > 0) &&
            ((t.ts_ms - last_entry_ms_) < (int64_t)cfg_.min_seconds_between * 1000);
        double tp = sig.tp;

        if (potentialLossUSD >= entryMaxLoss) {
            // HandleHighRiskEntry. CanCreateNewEntry()==GetEntryBlockReason()=="" (ATR + min-seconds
            // subset ported), then opposing-dir, accept-flag, per-session cap, sideway warning, momentum.
            if (entry_blocked_by_atr(snap, cfg_)) return;
            if (min_sec_blocked) return;
            if (count_dir_(!sig.is_long) > 0) return;                  // HasOpposingDirectionPosition
            if (!accept_high_risk(sig.kind, cfg_)) return;
            if (high_risk_count_ >= cfg_.max_high_risk_per_session) return;
            if (snap.sideways >= cfg_.sideways_warning_thr &&
                snap.sideways <  cfg_.sideways_block_thr) return;      // IsInSidewayRange(10)
            const int level = hr_momentum_level(sig.kind, cfg_);
            if (!check_momentum_for_level(sig.kind, sig.is_long, level, b_, align, snap, cfg_)) return;
            lot = high_risk_lot(sig.kind, balance_, riskDist, cfg_);   // resize to ~maxLoss*0.98
            const double tpDist = std::fabs(sig.tp - anchorEntry);
            const double tpm = high_risk_tp_mult(session_id_(bar.ts_ms), cfg_);
            tp = sig.is_long ? anchorEntry + tpDist * tpm : anchorEntry - tpDist * tpm;
            ++high_risk_count_;
        } else {
            // Normal path: opposing-dir, then per-type consec-loss block, then GetEntryBlockReason.
            // (detect_entry already consumed the trigger — matches Entry::Detect resetting lastX before
            // DetectNewEntry checks IsEntryTypeBlocked, so a block here still costs the trigger.)
            if (count_dir_(!sig.is_long) > 0) return;                  // HasOpposingDirectionPosition
            if (cfg_.enable_loss_cooldowns && entry_type_blocked_(sig.kind, sig.is_long, t.ts_ms)) return;
            if (entry_blocked_by_atr(snap, cfg_)) return;
            if (min_sec_blocked) return;
        }

        // Fill at THIS tick's real ask (long) / bid (short) — spread is in the price, no synthetic add.
        const double fill = sig.is_long ? t.ask : t.bid;
        Position p = open_position(sig.is_long, sig.kind, fill, sig.sl, tp, lot, cfg_);
        open_.push_back({ p, bar.ts_ms, fill, -lot * cfg_.commission_per_lot });
        ++entries_today_;
        last_entry_ms_ = t.ts_ms;
        if (emit_age_) std::fprintf(stderr, "AGEFIRE,%lld,%c,E%d,%d\n",
                                    (long long)bar.ts_ms, sig.is_long ? 'L' : 'S', sig.kind, sig.age);
    }

    // UpdateLosingStreak (RiskManager.mqh:20-110). Global escalating block + per-(kind,dir) 60-min block
    // after N consecutive losses; a win decrements the global streak and RESETS the OPPOSITE direction's
    // per-type counters. consecutiveLosses persists for the whole run (reset only in OnInit). t_close =
    // the close time (== TimeCurrent() in the tester).
    void update_loss_streak_(bool is_loss, int kind, bool is_long, int64_t t_close) {
        const int d = is_long ? 0 : 1;
        if (is_loss) {
            ++consec_losses_;
            // Global block: blockUntil = now + floor(consecLosses * mult * MIN_SECONDS_BETWEEN) sec.
            double mult = (consec_losses_ >= cfg_.losing_streak_escalation_thr) ? 2.0 : 1.5;
            const double ddPct = (peak_ > 0.0) ? (peak_ - balance_) / peak_ : 0.0;
            if (ddPct >= cfg_.dd_ratio_slowdown) mult *= 1.2;   // !IsWithinDrawdownLimit()
            const int64_t block_s = (int64_t)std::floor(consec_losses_ * mult * cfg_.min_seconds_between);
            losing_streak_block_until_ = t_close + block_s * 1000;
            // Per-type block (E1/E2/E3 only; E4/E5 never counted by the EA).
            if (kind >= 1 && kind <= 3) {
                ++consec_loss_[kind][d];
                if (cfg_.max_consec_losses_type > 0 && consec_loss_[kind][d] >= cfg_.max_consec_losses_type)
                    blocked_until_[kind][d] = t_close + (int64_t)cfg_.consec_loss_block_mins * 60 * 1000;
            }
        } else {  // win
            if (consec_losses_ > 0) { --consec_losses_; losing_streak_block_until_ = 0; }
            const int od = is_long ? 1 : 0;   // a long win resets SHORT per-type; a short win resets LONG
            for (int k = 1; k <= 4; ++k) { consec_loss_[k][od] = 0; blocked_until_[k][od] = 0; }
        }
    }
    // IsEntryTypeBlocked (RiskManager.mqh:133): per-(kind,dir) block, auto-resetting on expiry. Only the
    // NORMAL-risk path consults this in the EA (high-risk entries bypass it).
    bool entry_type_blocked_(int kind, bool is_long, int64_t now) {
        const int d = is_long ? 0 : 1;
        if (kind < 1 || kind > 3) return false;
        if (blocked_until_[kind][d] > 0 && now >= blocked_until_[kind][d]) {
            consec_loss_[kind][d] = 0; blocked_until_[kind][d] = 0;
        }
        return (blocked_until_[kind][d] > 0 && now < blocked_until_[kind][d]);
    }

    void realize_(detail::OpenPos& o, int64_t t_out, bool count_session = true) {
        // Update the per-session caps exactly as BrokerHelpers::HandleClosedTrade does on every close:
        //   tradeSLTPCountInSession++ on EVERY close; sessionLossCount++ only on a real (non-breakeven)
        //   loss. isLoss = hitSL ? (pnl<=0) : (pnl<0); breakeven = SL-moved-to-BE && hitSL && no partial.
        //   (hitSL = exit tag 'S' = stop/trail/BE; 'T'=TP, 'E'/'X'=expert-close are not SL hits.)
        if (count_session) {
            ++session_sltp_;
            const bool hit_sl = (o.exit_tag == 'S');
            const bool is_loss = hit_sl ? (o.pnl_acc <= 0.0) : (o.pnl_acc < 0.0);
            const bool is_be   = o.p.partial_done && hit_sl && !o.partial_taken;
            if (is_loss && !is_be) ++session_losses_;
            // --- Loss cooldowns (UpdateLosingStreak, RiskManager.mqh:20). NOTE: the streak's loss test
            // is `is_loss` (status=="LOST" iff hitSL?pnl<=0:pnl<0) — it does NOT exclude break-even, so a
            // BE close DOES count as a streak loss (unlike session_losses_ above). Every close is win|loss.
            if (cfg_.enable_loss_cooldowns) update_loss_streak_(is_loss, o.p.kind, o.p.is_long, t_out);
        }
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
    const std::unordered_map<int64_t, double>* pctile_oracle_ = nullptr;  // diagnostic only
    const bool emit_age_ = std::getenv("KK_EMIT_AGE") != nullptr;         // diagnostic: per-fire age to stderr
    const bool emit_arms_ = std::getenv("KK_EMIT_ARMS") != nullptr;       // diagnostic: per-bar E1 arm events
    const bool emit_armstate_ = std::getenv("KK_EMIT_ARMSTATE") != nullptr; // diagnostic: per-bar E1 latch age (vs MT5 KKE1ARM)
    int cur_session_ = 0;       // last named trading session (0=NONE/1=ASIA/2=EU/3=US)
    int session_losses_ = 0;    // sessionLossCount  (real losses this session)
    int session_sltp_ = 0;      // tradeSLTPCountInSession (every close this session)
    int high_risk_count_ = 0;   // highRiskTradesInSession (reset per session)
    int64_t last_entry_ms_ = 0; // lastEntryTime (for MIN_SECONDS_BETWEEN_ENTRIES)
    int arm_e1_ = 0, arm_e2_ = 0;   // diagnostic: trigger ARM events in-window
    int consec_losses_ = 0;     // global consecutiveLosses (persists; OnInit-reset only)
    int64_t losing_streak_block_until_ = 0;     // losingStreakBlockUntil (ms; 0 = none)
    int consec_loss_[6][2] = {};                // [kind][dir 0=L/1=S] consecutiveLosses_{L,S}E{1..}
    int64_t blocked_until_[6][2] = {};          // [kind][dir] blockedUntil_{L,S}E{1..} (ms)
    TriggerState tg_;
    std::vector<detail::OpenPos> open_;
    BtResult R_;
};

}  // namespace kk::kenkem
