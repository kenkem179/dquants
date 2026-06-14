// Trend vs balance regime — exact port of Core/Regime.mqh. Read on the just-closed bar (shift 1).
#pragma once
#include <cmath>
#include "kk/common/types.hpp"
#include "kk/common/config.hpp"

namespace kk {

inline RegimeState compute_regime(double atr, double ema_fast, double ema_slow,
                                  double adx, double plus, double minus, const Params& p) {
    RegimeState r;
    r.atr1 = atr; r.plus = plus; r.minus = minus; r.adx = adx;
    r.valid = (atr > 0.0 && ema_slow != 0.0);
    r.trend = (adx > p.adx_trend_min)
              && (std::fabs(plus - minus) > p.di_spread_min)
              && (std::fabs(ema_fast - ema_slow) > p.ema_sep_atr * atr);
    r.balance = !r.trend;
    return r;
}

}  // namespace kk
