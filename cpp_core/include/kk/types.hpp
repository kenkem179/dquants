// Shared value types for the KK-MasterVP engine. Mirrors GlobalState.mqh structs.
#pragma once
#include <cstdint>

namespace kk {

// One market tick. ts_ms = epoch milliseconds (UTC), matching the imported Parquet.
struct Tick {
    int64_t ts_ms = 0;
    double  bid   = 0.0;
    double  ask   = 0.0;
    double mid() const { return 0.5 * (bid + ask); }
    double spread() const { return ask - bid; }
};

// One OHLC bar (M1/M3). Built on mid; spread + tick_count tracked separately
// (see docs/KENKEM_QUANT_OS.md §3 and pipeline/build_bars.py).
struct Bar {
    int64_t ts_ms      = 0;
    double  open       = 0.0;
    double  high       = 0.0;
    double  low        = 0.0;
    double  close      = 0.0;
    double  spread_mean = 0.0;
    double  spread_max  = 0.0;
    int64_t tick_count  = 0;   // == MT5 tick_volume (Stage-A VP weight)
};

// Volume-profile result for one window (GlobalState.mqh VPResult).
struct VPResult {
    bool   valid = false;
    double poc   = 0.0;
    double vah   = 0.0;
    double val   = 0.0;
    double hi    = 0.0;
    double lo    = 0.0;
};

// Node-state read at one master bin (GlobalState.mqh NodeState).
struct NodeState {
    int    state    = 0;       // +1 buy, -1 sell, 0 flat/absorbed
    double net      = 0.0;     // (buy-sell)/(buy+sell)
    double touch    = 0.0;     // decayed touch count
    bool   absorbed = false;   // saturated + two-sided
};

// Trend vs balance regime (Regime.mqh RegimeState).
struct RegimeState {
    bool   valid   = false;
    bool   trend   = false;
    bool   balance = false;
    double plus    = 0.0;
    double minus   = 0.0;
    double adx     = 0.0;
    double atr1    = 0.0;
};

}  // namespace kk
