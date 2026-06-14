// MonsterEngine — the Layer-3 headless OnTick integrator for KK-MasterVP-Monster. Ports the EA's
// OnTick loop (Strategy_Monster.mqh) into a deterministic, headless tick replayer.
//
// UNLIKE the KK-MasterVP TickEngine (which precomputes ALL per-bar signals then replays ticks),
// the Monster engine INTERLEAVES per-bar signal computation with execution. This is forced by two
// stateful coupling points in the strategy:
//   * the fresh-cross registry (CrossRegistry) is CONSUMED on entry (consume_cross), so the set of
//     fresh crosses visible to bar j depends on whether bar j-k actually entered;
//   * the adaptive-RR recency stamps (lastLongEntryBar/lastShortEntryBar) are written on entry and
//     read back by evaluate_monster_signals to pick brk_rr_near vs brk_rr_far.
// Signal generation is therefore coupled to execution and cannot be fully precomputed.
//
// SHIFT MAP (mirrors the KK engine + the EA): when the forming M3 bar is F, the just-closed signal
// bar is j = F-1; the signal armed on bar j fills on the FIRST tick of bar F. M3 bar index from a
// tick = ts_ms / 180000. The chart ATR array is the SAME MT5-iATR(atr_len) seeding as build_tf_series.
//
// Per tick:  update equity/peak -> ManageOpenPosition (TP1 partial, BE, SL, TP2) at the price the
//            position can EXIT at (long->bid, short->ask).
// Per new M3 bar (first tick): NEW-BAR BLOCK for signal bar j (VP -> node -> net -> crosses ->
//            regime -> evaluate -> early exits -> entry arbitration -> fill at THIS tick).
//
// Determinism: same ticks -> same trades -> same balance. No Date.now / rand.
#pragma once
#include <vector>
#include <cstdint>
#include <string>
#include <cmath>
#include <algorithm>
#include "kk/common/types.hpp"
#include "kk/common/execution.hpp"
#include "kk/common/filters.hpp"            // kk::utc_parts (UTC decomposition only)
#include "kk/monster/monster_config.hpp"
#include "kk/monster/monster_signal.hpp"
#include "kk/monster/tf_net.hpp"

namespace kk::monster {

// One closed-trade record for the Monster journal.
struct TradeRec {
    int64_t     entry_ts_ms = 0;   // fill time (first tick of bar j+1), UTC
    bool        is_long = false;
    int         kind = KIND_NONE;  // BRK/MR1/MR2/IMP
    int         session = 0;       // 0 none / 1 Asia / 2 London / 3 NY (1 when trade_anytime)
    double      entry = 0.0;       // fill price
    double      sl = 0.0;
    double      tp2 = 0.0;
    double      realized_usd = 0.0;
    std::string exit_tag;          // SL / TP1+SL / TP2 / BE / FAILBRK / M1FLUSH / FORCE / OVH / EARLY / EOD
    // --- DIAGNOSTIC (temporary): sizing + banked-partial breakdown ---
    double      d_init_vol = 0.0;
    double      d_init_risk = 0.0;
    double      d_banked = 0.0;    // realized_accum_ (partial) at close
    double      d_final_pnl = 0.0; // pnl on the final remainder
    // diagnostic features (from the firing Signal; no trading effect)
    double      f_brk_dist_atr = 0.0;
    double      f_body_pct = 0.0;
    double      f_slope = 0.0;
    double      f_net_m1 = 0.0;
    double      f_net_m3 = 0.0;
    double      f_net_m5 = 0.0;
    double      f_atr_pct = 0.0;
};

inline const char* kind_str(int kind) {
    switch (kind) {
        case KIND_BRK:  return "BRK";
        case KIND_REV1: return "MR1";
        case KIND_REV2: return "MR2";
        case KIND_IMP:  return "IMP";
        default:        return "NONE";
    }
}

class MonsterEngine {
public:
    explicit MonsterEngine(const MonsterConfig& cfg) : cfg_(cfg) {
        node_.init(cfg_.vp_bins);
        mph_.init(cfg_.impulse_trend_slope_bars);
        ovh_.init(cfg_.brk_overhead_look);
        balance_ = cfg_.start_balance;
        peak_ = balance_;
    }

    // Load the bar series + the (already-built) HTF TfSeries. m15 may be empty (size 0) -> hasM15
    // is always false. The chart ATR over the M3 bars is built with the SAME MT5-iATR seeding as
    // build_tf_series (we reuse it directly on the m3 bars with tf=180s).
    void load(const std::vector<kk::Bar>& m3, TfSeries m1, TfSeries m5, TfSeries m15,
              int64_t trade_from_ms) {
        m3_ = m3;
        m1_ = std::move(m1);
        m5_ = std::move(m5);
        m15_ = std::move(m15);
        trade_from_ms_ = trade_from_ms;
        N_ = static_cast<int>(m3_.size());

        // chart ATR (MT5 iATR seeding) over the M3 bars.
        TfSeries chart = build_tf_series(m3_, cfg_.atr_len, 180);
        atr_ = std::move(chart.atr);

        warmup_bars_ = cfg_.master_len() + cfg_.atr_len + cfg_.impulse_predict_bars
                     + cfg_.impulse_trend_slope_bars + 5;

        // Position the forming-bar cursor at the last bar strictly before the test start, so the
        // first in-window tick fires exactly the boundary bar's signal (no warmup replays).
        cur_bar_idx_ = -1;
        if (trade_from_ms_ > 0) {
            int64_t boundary = trade_from_ms_ / 180000;
            // map index by bar-index == ts_ms/180000 < boundary
            for (int i = 0; i < N_; ++i) {
                if ((m3_[i].ts_ms / 180000) < boundary) cur_bar_idx_ = i;
                else break;
            }
        }
        equity_ = balance_;
        trades_.clear();
    }

    // Feed one tick (UTC epoch-ms order). Drives per-tick management + the new-bar block.
    void on_tick(const kk::Tick& t) {
        // Live equity = running balance + floating MtM of the open position.
        const double open_pnl = pos_.open ? open_pnl_(t.bid, t.ask) : 0.0;
        equity_ = balance_ + open_pnl;
        if (equity_ > peak_) peak_ = equity_;

        // ManageOpenPosition (broker-style TP1/BE/SL/TP2 against the exit-able price).
        if (pos_.open) manage_open_(t);

        // New M3 bar boundary from the tick timestamp.
        const int64_t this_idx = t.ts_ms / 180000;
        // Advance bars that have FULLY CLOSED before this tick. A bar j is "closed" only once a tick
        // from a LATER bar arrives (this_idx > bar-index of j) — STRICT inequality. Using <= here
        // would process bar j (with its complete OHLC) on the FIRST tick of bar j itself, i.e. a
        // one-bar lookahead: the signal armed on bar j must fill on the first tick of bar j+1.
        while (cur_bar_idx_ + 1 < N_ && (m3_[cur_bar_idx_ + 1].ts_ms / 180000) < this_idx) {
            ++cur_bar_idx_;
            on_bar_closed_(cur_bar_idx_, t);
        }
    }

    // End of data: force-close any open position at the last seen price, tagged EOD.
    void finish(double last_bid, double last_ask, int64_t /*last_ts_ms*/) {
        if (pos_.open) {
            const double px = pos_.is_long ? last_bid : last_ask;
            close_remainder_(px, "EOD");
        }
    }

    const std::vector<TradeRec>& trades() const { return trades_; }
    double balance() const { return balance_; }
    double peak_equity() const { return peak_; }
    int    raw_signals() const { return raw_signals_; }

private:
    // ---- open-position state (single netted position; v1 max_concurrent_per_dir=1) ----
    struct Position {
        bool   open = false;
        bool   is_long = false;
        int    kind = KIND_NONE;
        double entry = 0.0;        // fill price
        double init_risk = 0.0;    // |fill - sl| at entry
        double sl = 0.0;
        double tp1 = 0.0;
        double tp2 = 0.0;
        double signal_entry = 0.0; // sig.entry (close[j]); runner backstop anchor
        double edge = 0.0;         // master edge (mVah long / mVal short); 0 for reversion
        double initial_vol = 0.0;
        double cur_vol = 0.0;
        double open_balance = 0.0;
        int    open_bar_index = 0;
        double atr_at_entry = 0.0;
        int    session = 0;
        bool   tp1_done = false;
        bool   be_applied = false;
        bool   tp1_partial_taken = false;  // whether a TP1 partial was actually realized
        double best_price = 0.0;           // for chandelier trail (runner)
        // diagnostics carried to the journal
        double f_brk_dist_atr = 0.0, f_body_pct = 0.0, f_slope = 0.0;
        double f_net_m1 = 0.0, f_net_m3 = 0.0, f_net_m5 = 0.0, f_atr_pct = 0.0;
        int64_t entry_ts_ms = 0;
    };

    double value_per_price() const { return cfg_.value_per_price_per_lot(); }

    // Floating MtM of the open remainder at the current price (long->bid, short->ask).
    double open_pnl_(double bid, double ask) const {
        if (!pos_.open) return 0.0;
        const double px = pos_.is_long ? bid : ask;
        const double dir = pos_.is_long ? 1.0 : -1.0;
        return (px - pos_.entry) * pos_.cur_vol * value_per_price() * dir
             - cfg_.commission_per_lot * pos_.cur_vol;
    }

    // Realize P&L on `vol` lots exiting at `px`; bank it and (proportionally) the commission.
    double realize_(double px, double vol) {
        const double dir = pos_.is_long ? 1.0 : -1.0;
        const double pnl = (px - pos_.entry) * vol * value_per_price() * dir
                         - cfg_.commission_per_lot * vol;
        balance_ += pnl;
        return pnl;
    }

    // Close the whole remaining position at `px`, write the trade, reset state.
    void close_remainder_(double px, const std::string& tag) {
        const double pnl = realize_(px, pos_.cur_vol);
        TradeRec r;
        r.entry_ts_ms = pos_.entry_ts_ms;
        r.is_long = pos_.is_long;
        r.kind = pos_.kind;
        r.session = pos_.session;
        r.entry = pos_.entry;
        r.sl = pos_.sl;
        r.tp2 = pos_.tp2;
        r.realized_usd = realized_accum_ + pnl;
        r.exit_tag = tag;
        r.d_init_vol = pos_.initial_vol;
        r.d_init_risk = pos_.init_risk;
        r.d_banked = realized_accum_;
        r.d_final_pnl = pnl;
        r.f_brk_dist_atr = pos_.f_brk_dist_atr;
        r.f_body_pct = pos_.f_body_pct;
        r.f_slope = pos_.f_slope;
        r.f_net_m1 = pos_.f_net_m1;
        r.f_net_m3 = pos_.f_net_m3;
        r.f_net_m5 = pos_.f_net_m5;
        r.f_atr_pct = pos_.f_atr_pct;
        trades_.push_back(r);
        pos_ = Position{};
        realized_accum_ = 0.0;
    }

    // Per-tick broker-style management. Long exits on BID, short on ASK.
    void manage_open_(const kk::Tick& t) {
        const double exitPx = pos_.is_long ? t.bid : t.ask;

        // 1) TP1 partial. Fill no better than the live market (gap-aware, as with SL/TP2).
        if (cfg_.use_tp1_partial && !pos_.tp1_done) {
            const bool hit = pos_.is_long ? (exitPx >= pos_.tp1) : (exitPx <= pos_.tp1);
            if (hit) {
                const double tp1Fill = pos_.is_long ? std::min(pos_.tp1, exitPx)
                                                    : std::max(pos_.tp1, exitPx);
                const bool brkFam = (pos_.kind == KIND_BRK || pos_.kind == KIND_IMP);
                const double pct = brkFam ? cfg_.tp1_close_pct_brk : cfg_.tp1_close_pct_rev;
                double closeVol = pos_.initial_vol * pct / 100.0;
                // Partial is NOT normalized below min_lot. If the remainder would fall below
                // min_lot, close the whole position at TP1 instead (graceful min-lot handling).
                double remainder = pos_.cur_vol - closeVol;
                if (closeVol <= 0.0) {
                    pos_.tp1_done = true;
                } else if (remainder < cfg_.min_lot - 1e-12 || closeVol >= pos_.cur_vol) {
                    // close everything at TP1 (whole-position TP1 take).
                    close_remainder_(tp1Fill, "TP1");
                    return;
                } else {
                    realized_accum_ += realize_(tp1Fill, closeVol);
                    pos_.cur_vol = remainder;
                    pos_.tp1_done = true;
                    pos_.tp1_partial_taken = true;
                }
            }
        }

        // 2) BE after TP1.
        if (cfg_.be_after_tp1 && pos_.tp1_done && !pos_.be_applied) {
            const double newSL = pos_.is_long ? pos_.entry + cfg_.be_buf_atr * pos_.atr_at_entry
                                              : pos_.entry - cfg_.be_buf_atr * pos_.atr_at_entry;
            if (pos_.is_long) pos_.sl = std::max(pos_.sl, newSL);
            else              pos_.sl = std::min(pos_.sl, newSL);
            pos_.be_applied = true;
        }

        // 3) optional chandelier trail (runner; default OFF).
        if (cfg_.trail_runner) {
            if (pos_.is_long) {
                pos_.best_price = std::max(pos_.best_price, exitPx);
                const double trailSL = pos_.best_price - cfg_.trail_atr_mult * pos_.atr_at_entry;
                pos_.sl = std::max(pos_.sl, trailSL);
                const double backstop = pos_.signal_entry + cfg_.runner_rr * pos_.init_risk;
                pos_.tp2 = std::max(pos_.tp2, backstop);
            } else {
                pos_.best_price = (pos_.best_price <= 0.0) ? exitPx : std::min(pos_.best_price, exitPx);
                const double trailSL = pos_.best_price + cfg_.trail_atr_mult * pos_.atr_at_entry;
                pos_.sl = std::min(pos_.sl, trailSL);
                const double backstop = pos_.signal_entry - cfg_.runner_rr * pos_.init_risk;
                pos_.tp2 = std::min(pos_.tp2, backstop);
            }
        }

        // 4) SL. Fill at the SL price, but never BETTER than the live market — if price gapped
        // through the stop (e.g. the entry tick already sat past it), MT5 fills at the gapped
        // market, not the favourable stop. Long exits on bid: a gap below sl fills at the lower
        // bid; short exits on ask: a gap above sl fills at the higher ask.
        const bool slHit = pos_.is_long ? (exitPx <= pos_.sl) : (exitPx >= pos_.sl);
        if (slHit) {
            const double slFill = pos_.is_long ? std::min(pos_.sl, exitPx) : std::max(pos_.sl, exitPx);
            const char* tag = pos_.be_applied ? "BE" : (pos_.tp1_partial_taken ? "TP1+SL" : "SL");
            close_remainder_(slFill, tag);
            return;
        }
        // 5) TP2. Symmetric gap handling: a TP fills no better than the live market.
        const bool tp2Hit = pos_.is_long ? (exitPx >= pos_.tp2) : (exitPx <= pos_.tp2);
        if (tp2Hit) {
            const double tpFill = pos_.is_long ? std::min(pos_.tp2, exitPx) : std::max(pos_.tp2, exitPx);
            close_remainder_(tpFill, "TP2");
            return;
        }
    }

    // session id from a UTC minute-of-day (Asia 0-6 / London 7-11 / NY 12:30-16:30), with the
    // broker_gmt_offset shift. Returns 0 (out) / 1 / 2 / 3. trade_anytime -> always 1.
    int session_id_(const kk::UtcParts& u) const {
        if (cfg_.trade_anytime) return 1;
        int mod = u.min_of_day - cfg_.broker_gmt_offset * 60;
        // normalize into [0,1440)
        mod %= 1440; if (mod < 0) mod += 1440;
        if (cfg_.enable_asia   && mod >= 0     && mod < 6 * 60)   return 1;   // 00:00-06:00
        if (cfg_.enable_london && mod >= 7 * 60 && mod < 11 * 60) return 2;   // 07:00-11:00
        if (cfg_.enable_ny     && mod >= 750   && mod < 990)      return 3;   // 12:30-16:30
        return 0;
    }

    bool spread_ok_(const kk::Tick& t) const {
        if (cfg_.max_spread_pips <= 0.0) return true;
        const double sp = t.ask - t.bid;
        return (cfg_.pip_size > 0.0) && (sp / cfg_.pip_size) <= cfg_.max_spread_pips;
    }

    // Lot from a risk price-distance (mirrors RiskManager.compute_lot + min-lot guard).
    double compute_lot_(double risk_price_dist) const {
        if (risk_price_dist <= 0.0) return 0.0;
        const double budget = risk_budget_usd_();
        if (budget <= 0.0) return 0.0;
        const double vppl = value_per_price();
        if (vppl <= 0.0) return 0.0;
        double raw = budget / (risk_price_dist * vppl);
        // peak-DD soft-block multiplier.
        if (cfg_.soft_block_dd_pct > 0.0 && peak_ > 0.0) {
            const double dd = (peak_ - equity_) / peak_ * 100.0;
            if (dd >= cfg_.soft_block_dd_pct) raw *= cfg_.soft_block_lot_mult;
        }
        if (raw <= 0.0) return 0.0;
        const double lot = cfg_.normalize_lot(raw);
        if (cfg_.skip_if_minlot_over_risk) {
            const bool floored_up = (raw < cfg_.min_lot);
            const double actual_risk = lot * risk_price_dist * vppl;
            if (floored_up && actual_risk > budget * 1.001) return 0.0;
        }
        return lot;
    }

    double risk_budget_usd_() const {
        const double pct = std::max(balance_ * cfg_.risk_acc_pct / 100.0, 0.0);
        switch (cfg_.risk_unit) {
            case 1:  return cfg_.risk_usd;
            case 2:  return std::min(cfg_.risk_usd, pct);
            case 3:  return std::max(cfg_.risk_usd, pct);
            default: return pct;
        }
    }

    bool is_daily_dd_hit_(double next_budget) const {
        if (cfg_.max_daily_dd_pct <= 0.0 || day_start_equity_ <= 0.0) return false;
        const double proj = std::max(0.0,
            (day_start_equity_ - equity_ + next_budget) / day_start_equity_ * 100.0);
        return proj >= cfg_.max_daily_dd_pct;
    }
    bool is_peak_dd_halt_() const {
        if (cfg_.max_peak_dd_pct <= 0.0 || peak_ <= 0.0) return false;
        const double dd = (peak_ - equity_) / peak_ * 100.0;
        return dd >= cfg_.max_peak_dd_pct;
    }

    // The OnTick new-bar block for the just-closed signal bar j (first tick of bar j+1 = `t`).
    void on_bar_closed_(int j, const kk::Tick& t) {
        if (j < 0) return;
        const kk::UtcParts u = utc_parts(m3_[j].ts_ms);   // signal-bar UTC time

        // Per-UTC-day bookkeeping (trade count reset + day-start equity snapshot for daily-DD).
        if (u.day_key != last_day_key_) {
            last_day_key_ = u.day_key;
            trades_today_ = 0;
            day_start_equity_ = equity_;
        }

        const int sessionId = session_id_(u);

        // Below warmup: keep node/mpoc/cross empty (matches EA gating on requiredBars). Still do
        // out-of-session force-close so an open position is managed across the boundary.
        const bool warm = (j >= warmup_bars_);

        // --- NEW-BAR BLOCK (only when warm) ---
        Signal longSig, shortSig;
        NetContext net;
        bool haveSig = false;
        if (warm) {
            haveSig = compute_bar_signals_(j, longSig, shortSig, net);
        }

        // 8) EARLY EXITS on the open position (all default OFF; gated).
        if (warm && pos_.open) {
            const int64_t decisionT = m3_[j].ts_ms + 180000;
            const double closeJ = m3_[j].close;
            const double progressR = pos_.init_risk > 0.0
                ? ((pos_.is_long ? (closeJ - pos_.entry) : (pos_.entry - closeJ)) / pos_.init_risk)
                : 0.0;
            const int barsHeld = j - pos_.open_bar_index;
            const double curOpenPnl = open_pnl_(t.bid, t.ask);

            bool exited = false;
            // force-close on out-of-session / news.
            if (!exited && cfg_.force_close_sess_news && (sessionId == 0 || news_active_(u))) {
                const double px = pos_.is_long ? t.bid : t.ask;
                close_remainder_(px, "FORCE");
                exited = true;
            }
            // failed-break.
            if (!exited && cfg_.enable_failed_break_exit) {
                const int code = failed_break_check(pos_.is_long, pos_.edge, closeJ, net.netM3,
                                                    progressR, barsHeld, cfg_);
                if (code != 0) {
                    const double px = pos_.is_long ? t.bid : t.ask;
                    close_remainder_(px, "FAILBRK");
                    exited = true;
                }
            }
            // m1 flush.
            if (!exited && cfg_.enable_m1_flush_exit) {
                const bool flush = m1_flush_against(m1_, pos_.is_long, decisionT, cfg_.m1_flush_net_min,
                                                    cfg_.m1_flush_bars, cfg_.tf_net_look, cfg_.net_win_atr,
                                                    cfg_.mintick);
                if (flush && (!cfg_.m1_flush_underwater || curOpenPnl < 0.0)) {
                    const double px = pos_.is_long ? t.bid : t.ask;
                    close_remainder_(px, "M1FLUSH");
                    exited = true;
                }
            }
            // overhead exit (raw overhead against the position side + underwater gate).
            if (!exited && cfg_.enable_overhead_exit) {
                const bool ovhAgainst = pos_.is_long ? net.ovhRawLong : net.ovhRawShort;
                if (ovhAgainst && (!cfg_.overhead_exit_underwater || curOpenPnl < 0.0)) {
                    const double px = pos_.is_long ? t.bid : t.ask;
                    close_remainder_(px, "OVH");
                    exited = true;
                }
            }
            // legacy early-exit (net flush against the position on M3).
            if (!exited && cfg_.enable_early_exit) {
                const bool against = pos_.is_long ? (net.netM3 <= -cfg_.exit_net_min)
                                                  : (net.netM3 >=  cfg_.exit_net_min);
                if (against) {
                    const double px = pos_.is_long ? t.bid : t.ask;
                    close_remainder_(px, "EARLY");
                    exited = true;
                }
            }
        } else if (pos_.open && cfg_.force_close_sess_news && sessionId == 0) {
            // out-of-session force-close even below warmup (defensive; EA frees before entry).
            const double px = pos_.is_long ? t.bid : t.ask;
            close_remainder_(px, "FORCE");
        }

        if (!warm || !haveSig) return;

        // 9) ENTRY ARBITRATION (mirrors the EA OnTick).
        const bool haveLong = longSig.valid, haveShort = shortSig.valid;
        if (haveLong && haveShort) return;            // both -> single-position EA SKIP, log nothing
        if (!haveLong && !haveShort) return;
        const Signal& sig = haveLong ? longSig : shortSig;

        const bool flat = !pos_.open;
        // safety gate.
        const double atrSig = atr_[j];
        const double price = m3_[j].close;
        const double atrPct = (price > 0.0 && atrSig > 0.0) ? (atrSig / price) * 100.0 : 0.0;
        const bool atrFloorOk = (cfg_.min_atr_pct <= 0.0) || (atrPct >= cfg_.min_atr_pct);
        const bool inSession = (sessionId != 0);
        const bool spreadOk = spread_ok_(t);
        const bool maxTradesOk = trades_today_ < cfg_.max_trades_per_session;
        const bool newsBlock = news_active_(u);
        const bool dailyDdHit = is_daily_dd_hit_(risk_budget_usd_());
        const bool blockedHour = blocked_hour_(u.hour);
        const bool peakHalt = is_peak_dd_halt_();
        const bool cooldown = (cooldown_until_ms_ > 0 && t.ts_ms < cooldown_until_ms_);

        const bool safetyOk = cfg_.allow_trading && inSession && atrFloorOk && spreadOk
                            && maxTradesOk && !newsBlock && !dailyDdHit && !blockedHour
                            && !peakHalt && !cooldown;

        if (!flat || !safetyOk) return;   // skip, do NOT consume the cross

        // spread-vs-TP1 cost gate.
        const double liveSpread = t.ask - t.bid;
        const double tp1Dist = std::fabs(sig.tp1 - sig.entry);
        if (cfg_.max_spread_tp1_frac > 0.0 && tp1Dist > 0.0
            && liveSpread > cfg_.max_spread_tp1_frac * tp1Dist) return;

        // size + market fill.
        const double lot = compute_lot_(sig.risk);
        if (lot <= 0.0) return;   // min-lot-over-risk skip; do NOT consume the cross
        const double fill = ExecutionSimulator::fill_price(sig.is_long, t);

        Position np;
        np.open = true;
        np.is_long = sig.is_long;
        np.kind = sig.kind;
        np.entry = fill;
        np.init_risk = std::fabs(fill - sig.sl);
        if (np.init_risk <= 0.0) np.init_risk = sig.risk;
        np.sl = sig.sl;
        np.tp1 = sig.tp1;
        np.tp2 = sig.tp2;
        np.signal_entry = sig.entry;
        np.edge = sig.edge;
        np.initial_vol = np.cur_vol = lot;
        np.open_balance = balance_;
        np.open_bar_index = j;
        np.atr_at_entry = atrSig;
        np.session = sessionId;
        np.tp1_done = false;
        np.be_applied = false;
        np.best_price = sig.is_long ? fill : fill;
        np.entry_ts_ms = t.ts_ms;
        np.f_brk_dist_atr = sig.f_brk_dist_atr;
        np.f_body_pct = sig.f_body_pct;
        np.f_slope = sig.f_slope;
        np.f_net_m1 = sig.f_net_m1;
        np.f_net_m3 = sig.f_net_m3;
        np.f_net_m5 = sig.f_net_m5;
        np.f_atr_pct = sig.f_atr_pct;
        pos_ = np;
        realized_accum_ = 0.0;

        // consume the cross + stamp adaptive-RR recency + count the trade.
        cross_.consume_cross(sig.kind, sig.is_long);
        if (sig.is_long) cross_.lastLongEntryBar = j; else cross_.lastShortEntryBar = j;
        ++trades_today_;
    }

    // Run the full per-bar signal pipeline for signal bar j. Returns true if VP windows were valid
    // enough to attempt evaluation. Mutates node/mph/cross/ovh state (their order matters).
    bool compute_bar_signals_(int j, Signal& longSig, Signal& shortSig, NetContext& net) {
        const double o = m3_[j].open, h = m3_[j].high, l = m3_[j].low, c = m3_[j].close;
        const double atrSig = atr_[j];

        // 1) VP windows.
        const VPResult masterCur = compute_vp(m3_, j, cfg_.master_len(), cfg_.vp_bins,
                                              cfg_.va_pct, 0, cfg_.mintick);
        const VPResult localCur = compute_vp(m3_, j, cfg_.vp_lookback, cfg_.vp_bins,
                                             cfg_.va_pct, 0, cfg_.mintick);
        VPResult predCur;
        if (cfg_.impulse_predict_bars > 0)
            predCur = compute_vp(m3_, j, cfg_.master_len(), cfg_.vp_bins, cfg_.va_pct,
                                 cfg_.impulse_predict_bars, cfg_.mintick);

        // 2) node accumulate (tick_count of bar j, chart atr).
        node_.accumulate(o, h, l, c, (double)m3_[j].tick_count, atrSig, masterCur, cfg_);

        // 3) NetContext (M3 near-net + multi-TF prev-net + overhead raw).
        net.netM3 = node_.net_m3_weighted(c, atrSig, cfg_);
        const int64_t decisionT = m3_[j].ts_ms + 180000;
        net.netM1 = net_prev_at_time(m1_, decisionT, cfg_.tf_net_look, cfg_.net_win_atr,
                                     cfg_.mintick, net.hasM1);
        net.netM5 = net_prev_at_time(m5_, decisionT, cfg_.tf_net_look, cfg_.net_win_atr,
                                     cfg_.mintick, net.hasM5);
        if (m15_.size() > 0) {
            net.netM15 = net_prev_at_time(m15_, decisionT, cfg_.tf_net_look, cfg_.net_win_atr,
                                          cfg_.mintick, net.hasM15);
        } else {
            net.netM15 = 0.0; net.hasM15 = false;
        }
        // overhead raw reads.
        {
            double volL = 0.0, netL = 0.0, volS = 0.0, netS = 0.0;
            node_.band_node(c, c + cfg_.brk_proj_atr * atrSig, volL, netL);
            node_.band_node(c - cfg_.brk_proj_atr * atrSig, c, volS, netS);
            bool okL = false, okS = false;
            const double prL = ovh_.percentrank(ovh_.longHist, volL, cfg_.brk_overhead_look, okL);
            const double prS = ovh_.percentrank(ovh_.shortHist, volS, cfg_.brk_overhead_look, okS);
            net.ovhRawLong  = okL && (prL >= cfg_.brk_overhead_hvn_pct) && (netL <= -cfg_.brk_overhead_net_max);
            net.ovhRawShort = okS && (prS >= cfg_.brk_overhead_hvn_pct) && (netS >=  cfg_.brk_overhead_net_max);
            ovh_.push(volL, volS);
        }

        // 4) fresh crosses.
        cross_.update_fresh_crosses(c, masterCur, j);

        // 5) regime.
        MonsterRegime reg;
        const bool predValid = predCur.valid;
        mph_.compute_regime(atrSig, masterCur.poc, predValid, predCur.poc, cfg_, reg);

        // 6) evaluate.
        const double atrPct = (c > 0.0 && atrSig > 0.0) ? (atrSig / c) * 100.0 : 0.0;
        const bool atrCeilOk = (cfg_.max_atr_pct <= 0.0) || (atrPct <= cfg_.max_atr_pct);
        const bool inVolCeilBand = (cfg_.max_atr_pct > 0.0) && (atrPct > cfg_.max_atr_pct);
        evaluate_monster_signals(cfg_, o, h, l, c, masterCur, localCur, predCur, reg,
                                 atrSig, atrPct, atrCeilOk, inVolCeilBand, j,
                                 node_, cross_, net, longSig, shortSig);

        // 7) push master POC AFTER compute_regime.
        mph_.push(masterCur.poc);

        if (longSig.valid || shortSig.valid) ++raw_signals_;
        return masterCur.valid && localCur.valid;
    }

    // News window (avoid_news inert without a calendar; always false in v1).
    bool news_active_(const kk::UtcParts&) const { return false; }

    // Blocked hour veto (blocked_hours string; empty => never).
    bool blocked_hour_(int hour) const {
        if (cfg_.blocked_hours.empty() || hour < 0 || hour > 23) return false;
        // parse "8,10,11" or ranges "9-11" lazily each call (rare path; default off).
        const std::string& s = cfg_.blocked_hours;
        size_t i = 0;
        while (i < s.size()) {
            size_t comma = s.find(',', i);
            std::string tok = s.substr(i, comma == std::string::npos ? std::string::npos : comma - i);
            i = (comma == std::string::npos) ? s.size() : comma + 1;
            auto dash = tok.find('-');
            try {
                if (dash == std::string::npos) {
                    if (!tok.empty() && std::stoi(tok) == hour) return true;
                } else {
                    int lo = std::stoi(tok.substr(0, dash));
                    int hi = std::stoi(tok.substr(dash + 1));
                    if (hour >= lo && hour <= hi) return true;
                }
            } catch (...) { /* ignore malformed token */ }
        }
        return false;
    }

    MonsterConfig cfg_;
    std::vector<kk::Bar> m3_;
    std::vector<double>  atr_;
    TfSeries m1_, m5_, m15_;
    int N_ = 0;
    int warmup_bars_ = 0;
    int64_t trade_from_ms_ = 0;

    // stateful per-bar engines (consumed/mutated across bars).
    NodeEngine      node_;
    MPocHistory     mph_;
    OverheadHistory ovh_;
    CrossRegistry   cross_;

    // streaming state.
    Position pos_;
    double   realized_accum_ = 0.0;   // realized P&L banked on partials before full close
    double   balance_ = 0.0, peak_ = 0.0, equity_ = 0.0;
    double   day_start_equity_ = 0.0;
    int      last_day_key_ = -1;
    int      trades_today_ = 0;
    int      cur_bar_idx_ = -1;
    int      raw_signals_ = 0;
    int64_t  cooldown_until_ms_ = 0;
    std::vector<TradeRec> trades_;
};

}  // namespace kk::monster
