// TickEngine — the Layer-3 headless integrator. Ties the validated front-half (VP +
// regime + indicators + node engine + DetectSignal, all per-bar) to the execution half
// (gates -> risk sizing -> PositionManager -> trade journal) by replaying a tick stream
// over a precomputed bar series. It reproduces the MT5 KK-MasterVP OnTick loop:
//
//   per tick:  UpdatePeakEquity -> ManageOpenPosition (broker SL/TP, then EA TP1/BE/trail)
//   per new bar (first tick of the next bar):  session/day context -> force-close out of
//      session -> DetectSignal (shift-1) -> quality gate (MTF/RSI) -> safety gate + flat
//      check -> spread-vs-TP1 -> market fill at this tick's ask/bid -> open position.
//
// SHIFT MAP (identical to parity_runner.hpp, verified against the MQL5 source): when the
// forming bar is F, the just-closed signal bar is shift-1 = F-1; DetectSignal's signal bar
// is shift-2 = F-2; entry anchor = close[F-1]; AtrAt(1) = atr[F-1]. The signal armed on
// bar F-1 fills on the FIRST tick of bar F (no pending/retest in the v1 parity config).
//
// Design: bars[] (validated bid M3 bars, already matched to MT5) are the source of truth
// for all bar-determined computation; the tick stream drives ONLY fill timing/price,
// per-tick management (SL/TP/trail/MFE/MAE), and equity for the DD/peak/cooldown breakers.
// The front-half is precomputed once over the whole bar array (the proven array path), so
// the engine never re-derives indicators incrementally.
//
// Parity config (v1): InpUseRetestFill = false, InpAvoidNews = false (news calendar inert),
// InpEnableVolRR = false (rrScale = 1). These match the reference tester run.
#pragma once
#include <vector>
#include <cstdint>
#include <cstdio>
#include <string>
#include <cmath>
#include <algorithm>
#include "kk/common/types.hpp"
#include "kk/common/config.hpp"
#include "kk/mastervp/indicators.hpp"
#include "kk/mastervp/volume_profile.hpp"
#include "kk/mastervp/node_engine.hpp"
#include "kk/mastervp/regime.hpp"
#include "kk/mastervp/strategy.hpp"
#include "kk/common/filters.hpp"
#include "kk/common/risk_manager.hpp"
#include "kk/common/position_manager.hpp"
#include "kk/common/execution.hpp"

namespace kk {

class TickEngine {
public:
    explicit TickEngine(const Params& p) : p_(p) {}

    // Precompute the front-half over the full bar series, then ready the streaming state.
    // Call once before feeding ticks. Bars must be oldest..newest, contiguous in series
    // order (gaps in TIME are fine — empty M3 buckets simply aren't bars, exactly as MT5).
    //
    // trade_from_ts_ms = the test-period start (epoch ms, UTC). Bars before it are WARMUP
    // only (precomputed for indicator convergence, never bar-closed/traded) — exactly the
    // MT5 tester's preloaded history. The stream must then begin at the first tick >=
    // trade_from_ts_ms. 0 (default) trades from the first bar (used by the unit test).
    void load_bars(const std::vector<Bar>& bars, int64_t trade_from_ts_ms = 0) {
        bars_ = bars;
        precompute_();
        rm_.reset(p_);
        sess_.init(p_);
        // Position the forming-bar cursor at the last warmup bar strictly before the test
        // start, so the first in-window tick fires exactly the boundary bar's signal (and
        // never replays warmup bars into spurious fills).
        cur_forming_ = -1;
        if (trade_from_ts_ms > 0) {
            for (int i = 0; i < N_; ++i) {
                if (bars_[i].ts_ms < trade_from_ts_ms) cur_forming_ = i;
                else break;
            }
        }
        equity_ = rm_.balance();
        trades_.clear();
    }

    // Feed one tick (UTC epoch-ms order). Drives management + new-bar entry.
    void on_tick(const Tick& t) {
        // Determine the forming-bar index for this tick: the largest bar whose start <= ts.
        int forming = cur_forming_;
        while (forming + 1 < N_ && t.ts_ms >= bars_[forming + 1].ts_ms) ++forming;
        const int shift1 = forming - 1;   // last completed bar (AtrAt(1) source)

        // Live equity = running balance + the open trade's realized-so-far + floating MtM.
        const double open_pnl = pos_.open() ? pos_.open_pnl(t.bid, t.ask) : 0.0;
        equity_ = rm_.balance() + open_pnl;
        rm_.update_peak(equity_);   // peak equity is tracked every tick (UpdatePeakEquity)

        // ManageOpenPosition: broker SL/TP first, then EA TP1/BE/trail (AtrAt(1) = atr[shift1]).
        if (pos_.open()) {
            const double atr1 = (shift1 >= 0) ? atr_[shift1] : 0.0;
            if (pos_.on_tick(t.bid, t.ask, atr1)) finalize_trade_(t.ts_ms);
        }

        // New-bar gate: every bar that just completed fires its signal/entry block, with the
        // current tick as the fill candidate. Normally advances by exactly one bar.
        if (forming != cur_forming_) {
            for (int f = cur_forming_ + 1; f <= forming; ++f)
                on_bar_closed_(/*sig_bar=*/f - 1, t);
            cur_forming_ = forming;
        }
    }

    // End of data: force-close any open position at the last seen price, tagged EA.
    void finish(double last_bid, double last_ask, int64_t last_ts_ms) {
        if (pos_.open()) { pos_.force_close(last_bid, last_ask); finalize_trade_(last_ts_ms); }
    }

    // Debug: print the gate decision for every valid signal whose shift-1 bar time is in
    // [from_ms, to_ms]. 0,0 disables. Used to trace Level-2 trade divergences.
    void set_debug_window(int64_t from_ms, int64_t to_ms) { dbg_from_ = from_ms; dbg_to_ = to_ms; }

    const std::vector<TradeRecord>& trades() const { return trades_; }
    double balance() const { return rm_.balance(); }
    double peak_equity() const { return rm_.peak_equity(); }
    int    raw_signals() const { return raw_signals_; }   // bars with a valid DetectSignal

private:
    // ---- per-bar precomputed front-half + gate inputs ----
    struct BarEval {
        bool   valid = false;     // master VP window full AND a signal bar exists
        Signal sig;               // raw DetectSignal output (pre-gate)
        double atr1 = 0.0;        // atr at this (shift-1) bar
        double price = 0.0;       // close at this bar (ATR%-gate denominator = iClose(1))
        bool   regime_trend = false;  // regime.trend at this bar (trade-journal context)
    };

    void precompute_() {
        N_ = static_cast<int>(bars_.size());
        evals_.assign(N_, BarEval{});
        if (N_ == 0) return;

        std::vector<double> h(N_), l(N_), c(N_);
        for (int i = 0; i < N_; ++i) { h[i] = bars_[i].high; l[i] = bars_[i].low; c[i] = bars_[i].close; }
        atr_  = kk::ind::atr(h, l, c, p_.atr_len);
        rsi_  = kk::ind::rsi(c, p_.rsi_len);
        const auto dmi  = kk::ind::dmi_adx_mt5(h, l, c, p_.adx_len);
        const auto emaF = kk::ind::ema(c, p_.ema_fast);
        const auto emaS = kk::ind::ema(c, p_.ema_slow);

        build_htf_m15_();   // M15 EMA fast/slow for the MTF-agree gate

        const int master_len = p_.master_len();
        const int local_len  = p_.vp_lookback;
        NodeEngine node;
        node.init(p_.vp_bins);

        for (int i = 0; i < N_; ++i) {
            if (i < master_len - 1) continue;
            const VPResult masterCur =
                kk::vp::compute_vp_bars(&bars_[i - master_len + 1], master_len, p_.vp_bins, p_.va_pct);
            node.update(masterCur, bars_[i], atr_[i], p_);   // update BEFORE the signal read

            VPResult localCur;
            if (i >= local_len - 1)
                localCur = kk::vp::compute_vp_bars(&bars_[i - local_len + 1], local_len, p_.vp_bins, p_.va_pct);

            const RegimeState regime =
                kk::compute_regime(atr_[i], emaF[i], emaS[i], dmi.adx[i], dmi.plus_di[i], dmi.minus_di[i], p_);

            BarEval& ev = evals_[i];
            ev.atr1 = atr_[i];
            ev.price = bars_[i].close;
            ev.regime_trend = regime.trend;
            if (i >= 1) {
                SignalBar s;
                s.o = bars_[i - 1].open; s.h = bars_[i - 1].high; s.l = bars_[i - 1].low; s.c = bars_[i - 1].close;
                s.atr2 = atr_[i - 1]; s.atr1 = atr_[i]; s.entry_close = bars_[i].close;
                const NodeState nsVah = node.state_at_price(masterCur.vah, p_);
                const NodeState nsVal = node.state_at_price(masterCur.val, p_);
                const NodeState nsPx  = node.state_at_price(s.c, p_);
                ev.sig = kk::detect_signal(p_, masterCur, masterCur, localCur, regime,
                                           s, nsVah, nsVal, nsPx, /*rr_scale=*/1.0);
                ev.valid = true;
                if (ev.sig.valid) ++raw_signals_;
            }
        }
    }

    // Build M15 bars by aggregating the M3 series into 15-min buckets, then EMA fast/slow on
    // M15 closes. M15 boundaries align with M3 (15 % 3 == 0). Stored sorted by bucket start.
    void build_htf_m15_() {
        m15_start_.clear(); m15_close_.clear();
        const int64_t BK = 15 * 60 * 1000;
        for (int i = 0; i < N_; ++i) {
            const int64_t bk = bars_[i].ts_ms - (bars_[i].ts_ms % BK);
            if (m15_start_.empty() || m15_start_.back() != bk) {
                m15_start_.push_back(bk);
                m15_close_.push_back(bars_[i].close);
            } else {
                m15_close_.back() = bars_[i].close;   // last M3 close in the bucket
            }
        }
        m15_emaF_ = kk::ind::ema(m15_close_, p_.ema_fast);
        m15_emaS_ = kk::ind::ema(m15_close_, p_.ema_slow);
    }

    // MTF shift-1 HTF EMA at wall-clock `now_ms`: the M15 bar immediately preceding the
    // bucket that contains now_ms (shift-0 = forming bucket, shift-1 = the one before it).
    // Returns {0,0} if no prior M15 bar exists (gate skips silently, as the EA does).
    std::pair<double, double> htf_emas_(int64_t now_ms) const {
        const int64_t BK = 15 * 60 * 1000;
        const int64_t shift0 = now_ms - (now_ms % BK);
        // largest index j with m15_start_[j] < shift0
        int lo = 0, hi = static_cast<int>(m15_start_.size()) - 1, j = -1;
        while (lo <= hi) {
            const int mid = (lo + hi) / 2;
            if (m15_start_[mid] < shift0) { j = mid; lo = mid + 1; } else hi = mid - 1;
        }
        if (j < 0) return {0.0, 0.0};
        return {m15_emaF_[j], m15_emaS_[j]};
    }

    // QualityGateOk (EntryVP.mqh:33): MTF-agree (M15 EMA) + RSI veto. ATR-pctl gate is off.
    bool quality_ok_(bool is_long, int sig_bar, int64_t now_ms) const {
        if (p_.use_mtf_agree) {
            const auto [hf, hs] = htf_emas_(now_ms);
            if (hf > 0.0 && hs > 0.0) {
                const bool htf_bull = hf > hs, htf_bear = hf < hs;
                if (p_.mtf_hard_veto) {
                    if (is_long && !htf_bull) return false;
                    if (!is_long && !htf_bear) return false;
                } else {
                    if (is_long && htf_bear) return false;
                    if (!is_long && htf_bull) return false;
                }
            }
        }
        if (p_.use_mom_veto) {
            const double r = rsi_[sig_bar];
            if (r > 0.0) {
                if (is_long && r < p_.rsi_midline) return false;
                if (!is_long && r > p_.rsi_midline) return false;
            }
        }
        return true;
    }

    // First tick of bar (sig_bar+1): the OnTick new-bar block for shift-1 == sig_bar.
    void on_bar_closed_(int sig_bar, const Tick& t) {
        if (sig_bar < 0) return;
        const BarEval& ev = evals_[sig_bar];
        const UtcParts u = utc_parts(bars_[sig_bar].ts_ms);   // SignalBarUtc = shift-1 bar time

        // Session/day context (counter resets on session change inside update()).
        const int sessionId = sess_.update(u.min_of_day);
        rm_.seed_day_if_new(u.day_key, equity_);
        // Latch the 12h daily-DD cooldown the moment realized daily DD breaches the cap.
        rm_.maybe_arm_daily_dd_cooldown(t.ts_ms, equity_);

        // Force-close out of session (news is inert in v1). Frees the position before entry.
        if (p_.force_close_sess_news && pos_.open() && sessionId == 0) {
            pos_.force_close(t.bid, t.ask);
            finalize_trade_(t.ts_ms);
        }

        if (!ev.valid || !ev.sig.valid) return;
        const Signal& sig = ev.sig;
        const bool dbg = dbg_from_ && bars_[sig_bar].ts_ms >= dbg_from_ && bars_[sig_bar].ts_ms <= dbg_to_;
        auto blk = [&](const char* why) { if (dbg) std::fprintf(stderr, "[gate] %s %s -> BLOCK: %s\n",
                       trade_dbg_time_(sig_bar).c_str(), sig.is_long ? "L" : "S", why); };

        // Supplementary quality gate (before the main safety gate, as in OnTick).
        if (!quality_ok_(sig.is_long, sig_bar, t.ts_ms)) { blk("quality (MTF/RSI)"); return; }

        // Flat check + main safety gate (order mirrors OnTick / SafetyBlockReason).
        if (pos_.open()) { blk("position already open"); return; }
        const double risk_budget = rm_.risk_budget_usd();
        if (sessionId == 0) { blk("out of session"); return; }
        if (!atr_pct_ok(ev.atr1, ev.price, p_)) { blk("ATR% band"); return; }
        if (!spread_ok(t.bid, t.ask, p_)) { blk("spread"); return; }
        if (!sess_.max_trades_ok()) { blk("max trades/session"); return; }
        if (rm_.is_daily_dd_hit(equity_, risk_budget)) { blk("daily DD"); return; }
        if (sess_.is_blocked_hour(u.hour)) { blk("blocked hour"); return; }
        if (rm_.is_peak_dd_halt(equity_)) { blk("peak DD halt"); return; }
        if (rm_.is_in_cooldown(t.ts_ms)) { blk("cooldown"); return; }

        // Cost-clearance: live spread must not eat the TP1 partial.
        if (!spread_vs_tp1_ok(t.bid, t.ask, sig.tp1, sig.entry, p_)) { blk("spread vs TP1"); return; }

        // Size + market fill at this tick (long->ask, short->bid).
        const double lot = rm_.compute_lot(sig.risk, equity_);
        if (lot <= 0.0) { blk("lot<=0 (min-lot-over-risk)"); return; }   // no fill, no counter
        const double fill = ExecutionSimulator::fill_price(sig.is_long, t);
        const double entry_spread = ExecutionSimulator::entry_spread(t);
        if (pos_.open_position(p_, sig, fill, lot, bars_[sig_bar].ts_ms, sessionId, entry_spread,
                               ev.atr1, ev.regime_trend)) {
            sess_.on_fill();   // g_tradesThisSession++
            if (dbg) std::fprintf(stderr, "[gate] %s %s -> FILL entry=%.3f sl=%.3f lot=%.2f\n",
                                  trade_dbg_time_(sig_bar).c_str(), sig.is_long ? "L" : "S",
                                  fill, sig.sl, lot);
        }
    }

    std::string trade_dbg_time_(int sig_bar) const {
        const UtcParts u = utc_parts(bars_[sig_bar].ts_ms);
        char b[24]; std::snprintf(b, sizeof(b), "%04d.%02d.%02d %02d:%02d",
                                  u.year, u.mon, u.day, u.hour, u.min);
        return std::string(b);
    }

    void finalize_trade_(int64_t ts_ms) {
        const TradeRecord& rec = pos_.record();
        trades_.push_back(rec);
        rm_.register_trade_close(rec.realized_usd, ts_ms);   // bank P&L + loss-streak cooldown
    }

    Params p_;
    std::vector<Bar> bars_;
    int N_ = 0;

    // precomputed arrays
    std::vector<BarEval> evals_;
    std::vector<double>  atr_, rsi_;
    std::vector<int64_t> m15_start_;
    std::vector<double>  m15_close_, m15_emaF_, m15_emaS_;

    // streaming state
    RiskManager     rm_;
    Sessions        sess_;
    PositionManager pos_;
    int     cur_forming_ = -1;
    double  equity_ = 0.0;
    int     raw_signals_ = 0;
    int64_t dbg_from_ = 0, dbg_to_ = 0;
    std::vector<TradeRecord> trades_;
};

}  // namespace kk
