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

// Entry signal from DetectSignal (GlobalState.mqh Signal). reason = L/S-BRK or L/S-REV.
struct Signal {
    bool   valid   = false;
    bool   is_long = false;
    bool   is_rev  = false;       // reversion vs breakout economics
    bool   is_impulse = false;    // Monster kind-4 impulse-thrust (fired above the vol ceiling)
    double entry   = 0.0;         // anchor = shift-1 close
    double sl      = 0.0;
    double tp1     = 0.0;
    double tp2     = 0.0;
    double risk    = 0.0;         // |entry - sl|
    double lot     = 0.0;
    const char* reason = "";
    // diagnostic features (selectivity study; no trading effect)
    double f_brk_dist_atr = 0.0;
    double f_body_pct     = 0.0;
    double f_adx          = 0.0;
    double f_di_spread    = 0.0;
    double f_runway_atr   = 0.0;
    double f_node_net     = 0.0;
};

}  // namespace kk
