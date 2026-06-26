// Risk + capital management — port of TradeManagement/RiskManager.mqh. Pure + headless: owns the
// running balance, peak equity, day-start equity, loss streak, and cooldown clock. The engine feeds
// it live equity (balance + floating) per tick/bar and realized P&L on each close.
//
// Faithful formulas (all from RiskManager.mqh):
//   budget = balance * risk_acc_pct/100        (InpRiskUnit 0; 1=USD, 2=min, 3=max)
//   lot    = budget / (stopDist * valuePerPricePerLot) * peakDDLotMult, normalized to broker steps
//   dailyDD(proj) = (dayStartEquity - equity + nextRiskBudget)/dayStartEquity*100 >= max_daily_dd_pct
//   peakDD = (peakEquity - equity)/peakEquity*100 ; halt >= 22, soft-block (lot*0.55) >= 15
//   cooldown: arm 4h after `loss_streak_count` consecutive losses; 12h on a daily-DD hit; extend-only
#pragma once
#include <algorithm>
#include "kk/common/config.hpp"

namespace kk {

class RiskManager {
public:
    void reset(const Params& p) {
        p_ = &p;
        balance_ = p.start_balance;
        peak_equity_ = balance_;
        day_start_equity_ = balance_;
        day_peak_equity_ = balance_;
        last_day_key_ = -1;
        cooldown_until_ms_ = 0;
        consecutive_losses_ = 0;
    }

    double balance() const { return balance_; }
    double peak_equity() const { return peak_equity_; }

    // Per-tick: peak equity is monotonic in live equity (matches UpdatePeakEquity every tick).
    void update_peak(double equity) {
        if (equity > 0.0 && (peak_equity_ <= 0.0 || equity > peak_equity_)) peak_equity_ = equity;
        // H10c: day-peak resets each trading day (in seed_day_if_new) and trails within the day.
        if (equity > 0.0 && (day_peak_equity_ <= 0.0 || equity > day_peak_equity_)) day_peak_equity_ = equity;
    }

    // Per bar: reset day-start equity on a UTC calendar-date change (utc_day_key = yyyymmdd).
    void seed_day_if_new(int utc_day_key, double equity) {
        if (day_start_equity_ <= 0.0 || utc_day_key != last_day_key_) {
            day_start_equity_ = equity;
            day_peak_equity_ = equity;   // H10c: new trading day -> reset the giveback peak
            last_day_key_ = utc_day_key;
        }
    }

    double risk_budget_usd() const {
        const Params& p = *p_;
        const double pct = std::max(balance_ * p.risk_acc_pct / 100.0, 0.0);
        switch (p.risk_unit) {
            case 1:  return p.risk_usd;
            case 2:  return std::min(p.risk_usd, pct);
            case 3:  return std::max(p.risk_usd, pct);
            default: return pct;
        }
    }

    double peak_dd_pct(double equity) const {
        if (peak_equity_ <= 0.0) return 0.0;
        const double dd = (peak_equity_ - equity) / peak_equity_ * 100.0;
        return dd > 0.0 ? dd : 0.0;
    }
    bool is_peak_dd_halt(double equity) const {
        const Params& p = *p_;
        return p.max_peak_dd_pct > 0.0 && peak_dd_pct(equity) >= p.max_peak_dd_pct;
    }
    double peak_dd_lot_mult(double equity) const {
        const Params& p = *p_;
        if (p.soft_block_dd_pct <= 0.0) return 1.0;
        return peak_dd_pct(equity) >= p.soft_block_dd_pct ? p.soft_block_lot_mult : 1.0;
    }

    // Predictive daily-DD: adds the next trade's worst-case loss so one trade can't open through the cap.
    bool is_daily_dd_hit(double equity, double next_risk_budget) const {
        const Params& p = *p_;
        if (p.max_daily_dd_pct <= 0.0 || day_start_equity_ <= 0.0) return false;
        const double proj = std::max(0.0,
            (day_start_equity_ - equity + next_risk_budget) / day_start_equity_ * 100.0);
        return proj >= p.max_daily_dd_pct;
    }

    // H10c session-giveback halt: stand down for the rest of the day once the account has handed back
    // >= giveback_pct of the day's peak gain. Only arms on a green day (day_peak > day_start); flat at
    // the entry gate so `equity` is realized — never truncates the open runner. 0 = OFF.
    bool is_giveback_halt(double equity) const {
        const Params& p = *p_;
        if (p.giveback_pct <= 0.0 || day_start_equity_ <= 0.0) return false;
        const double gain = day_peak_equity_ - day_start_equity_;
        if (gain <= 0.0) return false;                       // day never went green -> nothing to give back
        const double givenback = day_peak_equity_ - equity;  // >= 0 once below the day peak
        return givenback >= p.giveback_pct / 100.0 * gain;
    }

    bool is_in_cooldown(int64_t ts_ms) const { return cooldown_until_ms_ > 0 && ts_ms < cooldown_until_ms_; }
    void arm_cooldown(int64_t ts_ms, double hours) {
        if (hours <= 0.0) return;
        const int64_t until = ts_ms + static_cast<int64_t>(hours * 3600.0 * 1000.0);
        if (until > cooldown_until_ms_) cooldown_until_ms_ = until;   // extend-only
    }
    // Per bar: arm the 12h daily-DD cooldown when the day's drop (no extra risk) already hit the cap.
    void maybe_arm_daily_dd_cooldown(int64_t ts_ms, double equity) {
        const Params& p = *p_;
        if (p.daily_dd_cooldown_hrs > 0.0 && is_daily_dd_hit(equity, 0.0))
            arm_cooldown(ts_ms, p.daily_dd_cooldown_hrs);
    }

    // Lot from stop distance (price units). Returns 0 if degenerate or the min-lot-over-risk guard trips.
    double compute_lot(double risk_price_dist, double equity) const {
        const Params& p = *p_;
        if (risk_price_dist <= 0.0) return 0.0;
        const double budget = risk_budget_usd();
        if (budget <= 0.0) return 0.0;
        const double vppl = p.value_per_price_per_lot();
        if (vppl <= 0.0) return 0.0;
        double raw = budget / (risk_price_dist * vppl);
        raw *= peak_dd_lot_mult(equity);
        if (raw <= 0.0) return 0.0;
        const double lot = p.normalize_lot(raw);
        // Min-lot over-risk skip-guard (RiskManager.mqh:114): skip ONLY when the broker's
        // VOLUME_MIN floored the raw lot UP (rawLot < minLot) AND the resulting min-lot risks
        // more than the budget. A normal lot rounded slightly over budget does NOT skip — the
        // flooredUp precondition is essential (without it, ordinary trades get dropped).
        if (p.skip_if_minlot_over_risk) {
            const bool floored_up = (raw < p.min_lot);
            const double actual_risk = lot * risk_price_dist * vppl;
            if (floored_up && actual_risk > budget * 1.001) return 0.0;
        }
        return lot;
    }

    // On a closed trade: bank P&L, update the loss streak, arm the streak cooldown at the threshold.
    void register_trade_close(double pnl, int64_t ts_ms) {
        const Params& p = *p_;
        balance_ += pnl;
        if (pnl < 0.0) ++consecutive_losses_; else consecutive_losses_ = 0;
        if (p.loss_streak_count > 0 && consecutive_losses_ >= p.loss_streak_count) {
            arm_cooldown(ts_ms, p.loss_streak_cooldown_hrs);
            consecutive_losses_ = 0;
        }
    }

    int consecutive_losses() const { return consecutive_losses_; }

private:
    const Params* p_ = nullptr;
    double  balance_ = 0.0, peak_equity_ = 0.0, day_start_equity_ = 0.0, day_peak_equity_ = 0.0;
    int     last_day_key_ = -1;
    int64_t cooldown_until_ms_ = 0;
    int     consecutive_losses_ = 0;
};

}  // namespace kk
