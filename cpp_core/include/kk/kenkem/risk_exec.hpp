// KenKem — execute-stage risk routing (the back-half DetectNewEntry never had in the distilled engine).
//
// The EA splits entry into DETECT (triggers+gates -> detectedTrade.type) and EXECUTE (DetectNewEntry's
// post-detection block). EXECUTE is where the over-fire is actually controlled, and the distilled engine
// skipped it entirely — it opened every detected+ATR-passing trade. This header ports the pure decision
// logic of that block so the tick engine can route faithfully:
//
//   potentialLossUSD = riskDist * lot * contractSize;   entryMaxLoss = getMaxLossUSD(type)
//   if (potentialLossUSD >= entryMaxLoss) -> HandleHighRiskEntry (accept flag, per-session cap,
//        IsInSidewayRange warning veto, CheckMomentumForLevel, lot resize, TP shrink)
//   else                                 -> normal path (opposing-dir, GetEntryBlockReason = ATR gate)
//
// Both paths run GetEntryBlockReason (CanCreateNewEntry == GetEntryBlockReason==""), whose load-bearing
// subset here is the ATR-percentile regime filter (B1: the gate that used to live wrongly inside
// per-candidate detection) + min-seconds-between-entries (handled by the engine via last-entry time).
//
// DEFERRED (documented, non-binding on the clean Feb-2026 anchor; see CPP_VS_MQL_FAITHFULNESS_AUDIT.md):
//   getMaxLossUSD daily-room / drawdown-room caps (D8/D7); getScaledLotSize state multipliers
//   (recovery / soft-block / profit-protection / win-streak); MAX_AGGREGATE_RISK_RATIO (D5);
//   per-type consecutive-loss timed block IsEntryTypeBlocked (D3); black-swan cooldown + spread blocks
//   (D9). These need running daily/peak balances or loss-streak state and do not bite at the deposit on
//   a profitable short window — add them when extending past the anchor.
#pragma once
#include "kk/kenkem/snapshot.hpp"
#include "kk/kenkem/scoring.hpp"        // kk_adx_accel, TfIndicators::get
#include "kk/kenkem/trade_manager.hpp"  // risk_ratio_for
#include "kk/kenkem/kenkem_config.hpp"
#include <algorithm>
#include <cmath>

namespace kk::kenkem {

// getMaxLossUSD(type) — entry-specific max $ loss (base branch only; DD/daily caps deferred).
// balance = the RUNNING account balance; start_balance doubles as INITIAL_ACCOUNT_BALANCE (the deposit).
inline double entry_max_loss_usd(int kind, double balance, const KenKemConfig& c) {
    const double rr = risk_ratio_for(kind, c);
    double base;
    if (balance > c.start_balance && c.increase_lot_on_profit) {       // consecutiveLosses<=0 assumed
        const double scaled = balance * c.profit_scale_w_cur + c.start_balance * c.profit_scale_w_init;
        base = scaled * rr;
    } else {
        base = std::min(balance * rr, c.start_balance * rr);
    }
    return std::max(base, balance * c.min_risk_floor_ratio);           // MIN_RISK_FLOOR_RATIO
}

// getScaledLotSize(type) — base std-lot with profit-growth scaling. The anchor has volLotAdj OFF for
// E1/E2/E4 and no per-entry lot multiplier (only E3=0.65, out of scope); state multipliers deferred.
inline double scaled_lot_size(double balance, const KenKemConfig& c) {
    double base = c.std_lot;
    if (balance > c.start_balance && c.increase_lot_on_profit) {       // consecutiveLosses<=0 assumed
        const double growth = balance / c.start_balance;
        const double sf = std::min(2.0, 1.0 + (growth - 1.0) * 0.5);
        base = c.std_lot * sf;
    }
    return base;
}

// ProcessEntryConvictionAndConfidence lot: min(maxLotsBasedOnRisk, maxLotsMargin, getScaledLotSize),
// normalized to the broker step. entry_price = the detection anchor (close[1]).
inline double process_lot(int kind, double balance, double risk_price, double entry_price,
                          const KenKemConfig& c) {
    const double maxLoss = entry_max_loss_usd(kind, balance, c);
    const double pointValue = c.contract_size * c.pip_size;
    const double maxLotsRisk = (pointValue > 0.0) ? maxLoss / pointValue : 1e18;
    const double marginPerLot = (c.leverage > 0) ? c.contract_size * entry_price / c.leverage : 0.0;
    const double maxUsedMargin = balance / (c.margin_level_percent / 100.0);
    const double maxLotsMargin = (marginPerLot > 0.0) ? maxUsedMargin / marginPerLot : 1e18;
    double lot = std::min(maxLotsRisk, maxLotsMargin);
    lot = std::min(lot, scaled_lot_size(balance, c));
    return c.normalize_lot(lot);
}

// HandleHighRiskEntry lot: target ~maxLoss*0.98 at the actual SL distance, capped by getScaledLotSize.
inline double high_risk_lot(int kind, double balance, double risk_price, const KenKemConfig& c) {
    const double target = entry_max_loss_usd(kind, balance, c) * 0.98;
    double adj = std::max(target / (risk_price * c.contract_size), c.min_lot);
    adj = std::min(adj, scaled_lot_size(balance, c));
    return c.normalize_lot(adj);
}

// GetEntryBlockReason ATR subset — true == BLOCKED. P0 0c (black-swan ATR low/high) + 0d (vol regime).
inline bool entry_blocked_by_atr(const Snapshot& s, const KenKemConfig& c) {
    if (c.enable_black_swan) {
        if (c.atr_percentile_low > 0.0 && s.atr_pctile < c.atr_percentile_low) return true;
        if (c.enable_atr_high_block && c.atr_percentile_high > 0.0 && s.atr_pctile > c.atr_percentile_high)
            return true;
    }
    if (c.min_entry_atr_pctile > 0.0 && s.atr_pctile < c.min_entry_atr_pctile) return true;
    return false;
}

// High-risk variant: empirically MT5's HandleHighRiskEntry fires E5 trades at low ATR-percentile that the
// normal MIN_ENTRY_ATR_PERCENTILE volatility-regime gate would block (engine w/65-block=75, no-block=218,
// MT5=108 over 2026 => intermediate = HR bypasses MIN_ENTRY). Keeps ONLY the black-swan low/high guard.
inline bool high_risk_blocked_by_atr(const Snapshot& s, const KenKemConfig& c) {
    if (c.enable_black_swan) {
        if (c.atr_percentile_low > 0.0 && s.atr_pctile < c.atr_percentile_low) return true;
        if (c.enable_atr_high_block && c.atr_percentile_high > 0.0 && s.atr_pctile > c.atr_percentile_high)
            return true;
    }
    return false;
}

inline bool accept_high_risk(int kind, const KenKemConfig& c) {
    if (kind == 1) return c.accept_high_risk_e1;
    if (kind == 2) return c.accept_high_risk_e2;
    if (kind == 4) return c.accept_high_risk_e4;
    if (kind == 5) return c.accept_high_risk_e5;
    return false;
}
inline int hr_momentum_level(int kind, const KenKemConfig& c) {
    if (kind == 2) return c.hr_momentum_e2;
    if (kind == 4) return c.hr_momentum_e4;
    return c.hr_momentum_e1;   // E1 (E5 has no level here; out of scope)
}

// HasMomentumForTrend(checkAccel=false): closed-bar ADX>=minADX AND directional DI spread>=minDISpread.
inline bool has_momentum_strict(const Snapshot& s, int tf, bool is_long, double min_adx, double min_di) {
    if (s.adx[tf] < min_adx) return false;
    const double sp = is_long ? (s.diP[tf] - s.diM[tf]) : (s.diM[tf] - s.diP[tf]);
    return sp >= min_di;
}

// HasEarlyTrendMomentumForE1: ADX>=E1_MIN_MOMENTUM_ADX, ADX accelerating, DI spread>=1.75 AND widening.
// lookback M1=5 / M3=3 / M5=2. Acceleration windows read the closed bars ending at align.tf-1 (the
// codebase convention for the EA's shift-0 forming read; see scoring.hpp).
inline bool has_early_trend_momentum(const TfBundle& b, const TfBundle::Align& align, const Snapshot& s,
                                     int tf, bool is_long, const KenKemConfig& c) {
    // HasMomentumForTrend(checkAccel=true): Check1 ADX>=min (CLOSED cache); Check2 ADX accelerating
    // (FORMING window, shift 0); Check3 DI spread>=1.75 (CLOSED cache); Check4 DI spread widening (FORMING
    // window). lookback M1=5/M3=3/M5=2.
    if (s.adx[tf] < c.e1_min_momentum_adx) return false;                          // Check1 (closed)
    const TfIndicators& ind = (tf == 1) ? b.m3 : (tf == 2) ? b.m5 : (tf == 3) ? b.m15 : b.m1;
    const int an = (tf == 1) ? align.m3 : (tf == 2) ? align.m5 : (tf == 3) ? align.m15 : align.m1;
    const int idx = an - 1;
    const int lookback = (tf == 0) ? 5 : (tf == 1) ? 3 : 2;
    // Check2 (ADX accelerating) + Check4 (DI spread widening): forming-bar window when enabled, else the
    // older closed {shift1,2,..} window. Check1/Check3 thresholds always read the closed cache.
    const bool fm = c.use_forming_accel;
    if (!(fm ? kk_adx_accel_f(s.adxF[tf], ind, idx, lookback) : kk_adx_accel(ind, idx, lookback)))
        return false;                                                            // Check2
    const double sp0 = is_long ? (s.diP[tf] - s.diM[tf]) : (s.diM[tf] - s.diP[tf]);
    if (sp0 < 1.75) return false;                                                // Check3 (closed)
    // Check4: IsAccelerating on the directional DI-spread window.
    const double fSP = is_long ? (s.diPF[tf] - s.diMF[tf]) : (s.diMF[tf] - s.diPF[tf]);
    auto SP = [&](int k){ int sh = fm ? (k - 1) : k; if (fm && k == 0) return fSP;
        double p = TfIndicators::get(ind.diP, idx - sh), m = TfIndicators::get(ind.diM, idx - sh);
        return is_long ? p - m : m - p; };
    if (idx < lookback - 1) return false;
    if (!(SP(0) > SP(1) && SP(0) > SP(lookback - 1))) return false;
    int rising = 0;
    for (int i = 0; i < lookback - 1; ++i) if (SP(i) > SP(i + 1)) ++rising;
    return rising > (lookback - 1) / 2;
}

// CheckMomentumForLevel — non-E3 branch (E3 counter-trend out of scope). `level` = HIGH_RISK_MOMENTUM_LEVEL
// integer value (NONE=-1, M1_ONLY=0, M3_ONLY=1, M1_OR_M3=2, M1_AND_M3=3, M1_AND_M5=4, M5_ONLY=5,
// M3_AND_M5=6, M5_AND_M15=7, E1_ACCEL_M1=8, _M3=9, _M1_OR_M3=10, _M1_AND_M3=11, _M3_OR_M5=12-but-&&).
inline bool check_momentum_for_level(int kind, bool is_long, int level, const TfBundle& b,
                                     const TfBundle::Align& align, const Snapshot& s,
                                     const KenKemConfig& c) {
    double minADX, minDI;
    if (kind == 2) { minADX = c.e2_hr_min_adx; minDI = c.e2_hr_min_di_spread; }
    else           { minADX = c.e1_hr_min_adx; minDI = c.e1_hr_min_di_spread; }  // E1 & E4 (EA Entry4 cfg)
    auto strict = [&](int tf){ return has_momentum_strict(s, tf, is_long, minADX, minDI); };
    auto accel  = [&](int tf){ return has_early_trend_momentum(b, align, s, tf, is_long, c); };
    switch (level) {
        case -1: return true;
        case 0:  return strict(0);
        case 1:  return strict(1);
        case 2:  return strict(0) || strict(1);
        case 3:  return strict(0) && strict(1);
        case 4:  return strict(0) && strict(2);
        case 5:  return strict(2);
        case 6:  return strict(1) && strict(2);
        case 7:  return strict(2) && strict(3);
        case 8:  return accel(0);
        case 9:  return accel(1);
        case 10: return accel(0) || accel(1);
        case 11: return accel(0) && accel(1);
        case 12: return accel(1) && accel(2);   // EA uses && despite the "_OR_" name
        default: return false;
    }
}

// GetHighRiskTPMultiplier — session-keyed TP shrink for high-risk trades. session: 1=ASIA,2=EU,3=US.
inline double high_risk_tp_mult(int session, const KenKemConfig& c) {
    if (session == 1) return c.hr_tp_mult_asia;
    if (session == 3) return c.hr_tp_mult_us;
    return c.hr_tp_mult_eu;   // EU + fallback
}

}  // namespace kk::kenkem
