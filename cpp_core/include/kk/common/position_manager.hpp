// Per-tick position management — port of TradeManagement/TradeManager.mqh (ManageOpenPosition +
// OpenTrade). Pure + headless: fed a stream of (bid, ask, live atr1) it reproduces the EA's TP1
// partial / BE-after-TP1 / runner chandelier trail exactly, and tracks R-multiple excursions.
//
// Faithful ordering per tick (matches the MT5 tester: broker SL/TP first, then EA management):
//   1. update MFE/MAE excursion (exit-side price: long->bid, short->ask)
//   2. broker SL / backstop-TP fills on the just-updated price
//   3. EA: TP1 partial (close tp1_close_pct% of INITIAL vol), then BE-after-TP1, then chandelier
//      trail (only ever tightens, anti-churn step = max(2*pip, 0.10*trailDist))
//
// $ realized is computed via Params::value_per_price_per_lot() (broker specs) minus commission;
// dir/entry/sl/exitTag and mfeR/maeR are broker-spec-INDEPENDENT (validated first).
#pragma once
#include <vector>
#include <cmath>
#include <algorithm>
#include "kk/common/types.hpp"
#include "kk/common/config.hpp"
#include "kk/common/profit_manager.hpp"

namespace kk {

enum class ExitTag { NONE, SL_WIN, SL_LOSS, TP, EA_FORCE };

inline const char* exit_tag_str(ExitTag t) {
    switch (t) {
        case ExitTag::SL_WIN:   return "SL-WIN";
        case ExitTag::SL_LOSS:  return "SL-LOSS";
        case ExitTag::TP:       return "TP";
        case ExitTag::EA_FORCE: return "EA";
        default:                return "NA";
    }
}

// A finished position's parity record (mirrors the TradeJournal trades_*.csv row, $-fields included).
struct TradeRecord {
    int64_t entry_ts_ms = 0;
    bool    is_long = false;
    bool    is_rev  = false;
    bool    regime_trend = false;
    int     session = 0;
    double  entry = 0.0;       // actual fill price
    double  risk_price = 0.0;  // |entry - initial sl|
    double  mfe_r = 0.0;       // max favorable excursion / risk
    double  mae_r = 0.0;       // max adverse excursion / risk
    double  realized_usd = 0.0;
    const char* reason = "";
    ExitTag exit_tag = ExitTag::NONE;
    // entry-context diagnostics (carried from the signal; no effect on management)
    double  brk_dist_atr = 0.0, body_pct = 0.0, adx = 0.0, di_spread = 0.0, runway_atr = 0.0, node_net = 0.0;
    double  spread_pips = 0.0, spread_atr = 0.0;
};

class PositionManager {
public:
    bool open() const { return open_; }
    bool is_long() const { return is_long_; }
    const TradeRecord& record() const { return rec_; }

    // Trade's contribution to account equity beyond the running balance: realized-so-far
    // (TP1 partial already booked to balance in MT5) + floating MtM of the remaining volume
    // on the exit side (long->bid, short->ask). Used by the engine for peak/daily-DD tracking.
    double open_pnl(double bid, double ask) const {
        if (!open_) return 0.0;
        const double exit_px = is_long_ ? bid : ask;
        const double dir = is_long_ ? 1.0 : -1.0;
        const double floating = (exit_px - entry_) * dir * cur_vol_ * p_->value_per_price_per_lot();
        return realized_usd_ + floating;
    }

    // Open at an actual fill price + sized lot. entry_atr1 = the shift-1 ATR at entry (used only if
    // a value is needed before the first managed tick supplies a live atr). Returns false if degenerate.
    bool open_position(const Params& p, const Signal& sig, double fill_price, double lot,
                       int64_t entry_ts_ms, int session, double entry_spread, double entry_atr1,
                       bool regime_trend = false) {
        if (lot <= 0.0 || sig.risk <= 0.0) return false;
        p_ = &p;
        open_ = true; is_long_ = sig.is_long;
        entry_ = fill_price; initial_vol_ = lot; cur_vol_ = lot;
        // Effective risk = |actual fill - SL| (TradeManager.mqh:99 effRisk), NOT the anchor
        // sig.risk. The journal's riskPrice/mfeR/maeR all measure against this true R so a
        // fill away from the anchor is scored fairly. Fall back to sig.risk if degenerate.
        risk_ = std::fabs(fill_price - sig.sl);
        if (risk_ <= 0.0) risk_ = sig.risk;
        sl_ = sig.sl;
        // Runner: open with a far InpRunnerRr backstop TP (not the fixed rrBrk cap) so a real
        // breakout can run; the chandelier trail normally exits first. The backstop is anchored
        // to sig.entry + sig.risk*RunnerRr (TradeManager.mqh:61-64) — the SIGNAL anchor/risk,
        // not the fill — so it is a fixed absolute price the broker holds as TP.
        // Feature #2: when node-structure TP is on, the final/runner target IS the structural
        // level (already baked into sig.tp2 by the engine); the chandelier trail still rides and
        // may exit earlier. Otherwise the usual runner backstop (or fixed rrBrk cap).
        tp_backstop_ = (p.enable_struct_tp && sig.tp2 > 0.0)
            ? sig.tp2
            : ((p.trail_runner && sig.risk > 0.0)
                ? (is_long_ ? sig.entry + sig.risk * p.runner_rr : sig.entry - sig.risk * p.runner_rr)
                : sig.tp2);
        tp1_ = sig.tp1;
        tp1_done_ = false; be_applied_ = false;
        pm_partial_done_ = false; pm_tp_ext_count_ = 0;
        mfe_ = 0.0; mae_ = 0.0;
        last_atr_ = entry_atr1;

        rec_ = TradeRecord{};
        rec_.entry_ts_ms = entry_ts_ms; rec_.is_long = is_long_; rec_.is_rev = sig.is_rev;
        rec_.regime_trend = regime_trend;
        rec_.session = session; rec_.entry = entry_; rec_.risk_price = risk_; rec_.reason = sig.reason;
        rec_.brk_dist_atr = sig.f_brk_dist_atr; rec_.body_pct = sig.f_body_pct; rec_.adx = sig.f_adx;
        rec_.di_spread = sig.f_di_spread; rec_.runway_atr = sig.f_runway_atr; rec_.node_net = sig.f_node_net;
        rec_.spread_pips = (p.pip_size > 0.0) ? entry_spread / p.pip_size : 0.0;
        rec_.spread_atr  = (entry_atr1 > 0.0) ? entry_spread / entry_atr1 : 0.0;
        realized_usd_ = 0.0;
        return true;
    }

    // Process one tick. atr1 = current shift-1 ATR (live; the EA reads AtrAt(1) every tick).
    // Returns true if the position closed on this tick.
    bool on_tick(double bid, double ask, double atr1) {
        if (!open_) return false;
        const Params& p = *p_;
        if (atr1 > 0.0) last_atr_ = atr1;

        // 1) excursion (exit-side price).
        const double exit_px = is_long_ ? bid : ask;
        const double favor = is_long_ ? (exit_px - entry_) : (entry_ - exit_px);
        const double adverse = is_long_ ? (entry_ - exit_px) : (exit_px - entry_);
        if (favor > mfe_) mfe_ = favor;
        if (adverse > mae_) mae_ = adverse;

        // 2) broker SL / backstop-TP (checked on the exit-side price).
        if (is_long_) {
            if (bid <= sl_)          return close_all(sl_, ExitTag::SL_LOSS);  // sign-disambiguated below
            if (bid >= tp_backstop_) return close_all(tp_backstop_, ExitTag::TP);
        } else {
            if (ask >= sl_)          return close_all(sl_, ExitTag::SL_LOSS);
            if (ask <= tp_backstop_) return close_all(tp_backstop_, ExitTag::TP);
        }

        // 3) EA management.
        const bool tp1_hit = is_long_ ? (bid >= tp1_) : (ask <= tp1_);
        if (!tp1_done_ && tp1_hit) {
            const double close_vol = p.normalize_lot(initial_vol_ * p.tp1_close_pct / 100.0);
            if (close_vol >= p.min_lot && (cur_vol_ - close_vol) >= p.min_lot) {
                book_pnl(tp1_, close_vol);     // partial close at TP1 (EA deal)
                cur_vol_ -= close_vol;
            }
            tp1_done_ = true;                  // mark done even if unsplittable (runner rides on)
        }

        if (tp1_done_ && p.be_after_tp1 && !be_applied_) {
            const double be = is_long_ ? entry_ + p.be_buf_atr * last_atr_
                                       : entry_ - p.be_buf_atr * last_atr_;
            // BE only ever tightens (never loosens the stop).
            if (is_long_ ? (be > sl_) : (be < sl_)) sl_ = be;
            be_applied_ = true;
        }

        if (tp1_done_ && p.trail_runner && last_atr_ > 0.0) {
            const double trail_dist = p.trail_atr_mult * last_atr_;
            const double step = std::max(2.0 * p.pip_size, 0.10 * trail_dist);
            if (is_long_) {
                const double cand = bid - trail_dist;
                if (cand > 0.0 && cand >= sl_ + step) sl_ = cand;
            } else {
                const double cand = ask + trail_dist;
                if (cand > 0.0 && cand <= sl_ - step) sl_ = cand;
            }
        }

        // 4) Shared ProfitManager (kk::common). All toggles default OFF => skipped (provably inert).
        //    Composes with the above: SL merged tighten-only, TP extended-only, partial one-shot.
        //    structure_level/trend_weakening are not yet fed by this engine (pre_be_structure /
        //    tp_extension stay inert until wired); the SL-only toggles are fully functional here.
        if (common::pm_any(p.pm)) {
            common::PMState st;
            st.is_long = is_long_; st.entry = entry_; st.sl = sl_; st.tp = tp_backstop_;
            st.cur_price = exit_px; st.best_price = is_long_ ? (entry_ + mfe_) : (entry_ - mfe_);
            st.risk = risk_; st.atr = last_atr_;
            st.tp_extensions = pm_tp_ext_count_;
            st.partial_done = pm_partial_done_; st.be_done = be_applied_;
            st.structure_level = 0.0; st.trend_weakening = false;
            const common::PMActions act = common::pm_evaluate(st, p.pm);
            if (is_long_ ? (act.sl > sl_) : (act.sl < sl_)) sl_ = act.sl;
            if (is_long_ ? (act.tp > tp_backstop_) : (act.tp < tp_backstop_)) {
                tp_backstop_ = act.tp; ++pm_tp_ext_count_;
            }
            if (act.partial_frac > 0.0 && !pm_partial_done_) {
                const double close_vol = p.normalize_lot(initial_vol_ * act.partial_frac);
                if (close_vol >= p.min_lot && (cur_vol_ - close_vol) >= p.min_lot) {
                    book_pnl(exit_px, close_vol);
                    cur_vol_ -= close_vol;
                }
                pm_partial_done_ = true;
            }
        }
        return false;
    }

    // Force-close (out of session / news / end of data) at the exit-side price, tagged EA.
    bool force_close(double bid, double ask) {
        if (!open_) return false;
        return close_all(is_long_ ? bid : ask, ExitTag::EA_FORCE);
    }

private:
    void book_pnl(double exit_px, double vol) {
        const double dir = is_long_ ? 1.0 : -1.0;
        const double gross = (exit_px - entry_) * dir * vol * p_->value_per_price_per_lot();
        const double comm  = p_->commission_per_lot * vol;   // round-turn commission per closed lot
        realized_usd_ += gross - comm;
    }

    bool close_all(double exit_px, ExitTag forced_tag) {
        // Book the remaining volume, then finalize the win/loss disambiguation for SL.
        book_pnl(exit_px, cur_vol_);
        cur_vol_ = 0.0;
        ExitTag tag = forced_tag;
        if (forced_tag == ExitTag::SL_WIN || forced_tag == ExitTag::SL_LOSS)
            tag = (realized_usd_ > 0.0) ? ExitTag::SL_WIN : ExitTag::SL_LOSS;
        rec_.exit_tag = tag;
        rec_.realized_usd = realized_usd_;
        rec_.mfe_r = (risk_ > 0.0) ? mfe_ / risk_ : 0.0;
        rec_.mae_r = (risk_ > 0.0) ? mae_ / risk_ : 0.0;
        open_ = false;
        return true;
    }

    const Params* p_ = nullptr;
    bool   open_ = false, is_long_ = false, tp1_done_ = false, be_applied_ = false;
    bool   pm_partial_done_ = false;
    int    pm_tp_ext_count_ = 0;
    double entry_ = 0.0, sl_ = 0.0, tp1_ = 0.0, tp_backstop_ = 0.0, risk_ = 0.0;
    double initial_vol_ = 0.0, cur_vol_ = 0.0, realized_usd_ = 0.0;
    double mfe_ = 0.0, mae_ = 0.0, last_atr_ = 0.0;
    TradeRecord rec_;
};

}  // namespace kk
