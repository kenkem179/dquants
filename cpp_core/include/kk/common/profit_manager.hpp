// kk::common::ProfitManager — ONE shared, toggleable profit-management module any strategy includes.
//
// Distilled from the user's KenKemExpert TradeManagement/TradeManager.mqh (the proven-but-never-validated
// profit toolkit), refactored into a PURE, stateless function so each behaviour can be validated in
// isolation by the headless backtester. This is Layer 2 logic: NO broker calls, NO MT5 APIs — it takes a
// snapshot of one open trade (PMState) plus a config of independent ON/OFF toggles (PMConfig) and returns
// the actions an engine (or the thin MQL5 KK-Common/ProfitManager.mqh adapter) should apply: a (tighter)
// stop, a (further) take-profit, and/or a partial-close fraction.
//
// DESIGN — composition by tighten-only / extend-only merge:
//   * Every SL-moving toggle proposes a candidate stop; the engine keeps the TIGHTEST (long: highest;
//     short: lowest) of {current SL, all candidates}. A stop therefore never loosens, and multiple
//     SL toggles compose without ordering hazards.
//   * tp_extension proposes a candidate TP further from price; the engine keeps the FURTHER one.
//   * partial_tp requests a one-shot fractional close (the engine tracks "already done").
//   This makes the module STATELESS: recomputing from the live (price, MFE) each tick reproduces a
//   ratchet because the engine merges tighten-only. Hysteresis lives in the engine's state, not here.
//
// DEFAULT = ALL TOGGLES OFF => pm_evaluate returns the inputs unchanged (sl, tp, partial_frac=0), so an
// engine that merges the result is byte-for-byte identical to its pre-ProfitManager behaviour. Adopt a
// toggle into a locked .set ONLY if it improves net AND drawdown (risk-adjusted); otherwise leave inert.
#pragma once
#include <algorithm>
#include <cmath>

namespace kk::common {

// Independent ON/OFF profit-management toggles. Each block ports one KenKemExpert function.
struct PMConfig {
    // (1) be_protect — at >= trigger_r, move SL to entry + buffer_r * risk. (ApplyRMultipleSLProtection)
    bool   be_protect      = false;
    double be_trigger_r    = 1.0;   // R-multiple of CURRENT gain that arms breakeven
    double be_buffer_r     = 0.0;   // SL placed buffer_r * risk beyond entry (0 = exact entry)

    // (2) progressive_trail — R-milestone stepped SL tightening = accelerating trail.
    //     (ApplyConservativeTradeManagement phase-2 ladder)
    bool   prog_trail      = false;
    double prog_trigger_r  = 1.0;   // start ratcheting once CURRENT gain >= this R (SL -> entry here)
    double prog_increment_r= 0.5;   // every this much additional R of gain...
    double prog_step_r     = 0.10;  // ...advance the locked SL by step_r * risk (cumulative, in R)

    // (3) giveback_cap — once PEAK gain (MFE) >= arm_r, the stop may not give back more than cap_frac
    //     of the peak gain. The most direct fix for "ran to 3R, gave back 2R". (HasSignificantRetrace)
    bool   giveback        = false;
    double giveback_arm_r  = 2.0;   // arm only after MFE reaches this R
    double giveback_cap_frac = 0.30;// keep >= (1 - cap_frac) of peak gain locked as SL

    // (4) tp_extension — push the final TP further while the trend persists, capped. (ExtendTPAsNeeded)
    //     Needs trend_weakening from the engine (falling ADX / flat EMA-slope) to know when to stop.
    bool   tp_extension    = false;
    double tp_ext_progress = 0.90;  // only extend when price has covered >= this frac of entry->TP
    double tp_ext_atr_mult = 1.0;   // extend TP by this * atr per step
    int    tp_ext_max      = 5;     // cap on number of extensions

    // (5) pre_be_structure — before BE, tighten to a prior swing/BOS level. (ApplyPreBEStructureProtection)
    //     Needs structure_level from the engine (prior swing high/low); kept strictly below entry (long).
    bool   pre_be_structure= false;
    double pre_be_trigger_r= 0.5;   // arm once CURRENT gain >= this R
    double pre_be_buffer   = 0.0;   // place SL this far (price) inside the structure level

    // (6) partial_tp — one-shot R-triggered partial close. (TakePartialProfitAsNeeded)
    bool   partial_tp      = false;
    double partial_trigger_r = 1.0; // take the partial once CURRENT gain >= this R
    double partial_frac    = 0.5;   // fraction of INITIAL volume to close
};

// Snapshot of one open trade. All prices are absolute; risk/atr are price distances. cur_price is the
// EXIT-side price (long -> bid, short -> ask) so gains are realistic. best_price is the MFE high-water on
// that same exit side. The engine owns the hysteresis flags (partial_done / be_done / tp_extensions).
struct PMState {
    bool   is_long        = false;
    double entry          = 0.0;
    double sl             = 0.0;   // current stop
    double tp             = 0.0;   // current final take-profit
    double cur_price      = 0.0;   // current exit-side price
    double best_price     = 0.0;   // MFE exit-side price (high-water)
    double risk           = 0.0;   // original risk in price (|entry - initial sl|)
    double atr            = 0.0;   // live/entry ATR (price)
    int    tp_extensions  = 0;     // extensions taken so far
    bool   partial_done   = false; // PM partial already executed
    bool   be_done        = false; // breakeven already applied (by any source)
    double structure_level= 0.0;   // optional prior-swing level (0 = not supplied)
    bool   trend_weakening= false; // optional; gates tp_extension
};

// What the engine should apply. sl/tp are merged tighten-only/extend-only by the engine; partial_frac is a
// one-shot request (0 = none). With every toggle OFF this equals {state.sl, state.tp, 0}.
struct PMActions {
    double sl           = 0.0;
    double tp           = 0.0;
    double partial_frac = 0.0;
};

// True if any toggle is enabled. Engines guard the per-tick call with this so an all-OFF config is
// provably inert (and free): pm_evaluate is skipped entirely.
inline bool pm_any(const PMConfig& c) {
    return c.be_protect || c.prog_trail || c.giveback || c.tp_extension
        || c.pre_be_structure || c.partial_tp;
}

namespace detail {
// Tighten a stop toward price: long keeps the higher, short keeps the lower. Never loosens.
inline void tighten_sl(bool is_long, double& sl, double cand) {
    if (is_long) { if (cand > sl) sl = cand; }
    else         { if (cand < sl) sl = cand; }
}
}  // namespace detail

// PURE evaluation of all enabled toggles. Stateless: same (state, cfg) -> same actions.
inline PMActions pm_evaluate(const PMState& s, const PMConfig& c) {
    PMActions a;
    a.sl = s.sl;
    a.tp = s.tp;
    a.partial_frac = 0.0;
    if (s.risk <= 0.0) return a;

    const double dir      = s.is_long ? 1.0 : -1.0;
    const double cur_gain = (s.cur_price - s.entry) * dir;   // signed -> favourable when > 0
    const double peak_gain= (s.best_price - s.entry) * dir;
    const double cur_r    = cur_gain / s.risk;
    const double peak_r   = peak_gain / s.risk;

    // (1) be_protect
    if (c.be_protect && c.be_trigger_r > 0.0 && cur_r >= c.be_trigger_r) {
        const double cand = s.entry + dir * c.be_buffer_r * s.risk;
        detail::tighten_sl(s.is_long, a.sl, cand);
    }

    // (5) pre_be_structure (before BE; kept strictly inside entry so it never crosses to profit-lock)
    if (c.pre_be_structure && !s.be_done && s.structure_level > 0.0
        && c.pre_be_trigger_r > 0.0 && cur_r >= c.pre_be_trigger_r) {
        double cand = s.structure_level - dir * c.pre_be_buffer;
        // strictly pre-BE: do not let this stage reach or cross entry.
        const double margin = s.is_long ? (s.entry - 1e-9) : (s.entry + 1e-9);
        if (s.is_long)  cand = std::min(cand, margin);
        else            cand = std::max(cand, margin);
        // only an improvement, and only while still below entry on the locked side
        const bool below_entry = s.is_long ? (cand < s.entry) : (cand > s.entry);
        if (below_entry) detail::tighten_sl(s.is_long, a.sl, cand);
    }

    // (2) progressive_trail — SL -> entry at trigger, then advances step_r per increment_r of extra gain.
    if (c.prog_trail && c.prog_trigger_r >= 0.0 && c.prog_increment_r > 0.0 && cur_r >= c.prog_trigger_r) {
        const double over = cur_r - c.prog_trigger_r;
        const double steps = std::floor(over / c.prog_increment_r);
        const double shift_r = std::max(0.0, steps) * c.prog_step_r;  // SL = entry + shift_r*risk
        const double cand = s.entry + dir * shift_r * s.risk;
        detail::tighten_sl(s.is_long, a.sl, cand);
    }

    // (3) giveback_cap — lock >= (1 - cap_frac) of peak gain once MFE is armed.
    if (c.giveback && c.giveback_arm_r > 0.0 && peak_r >= c.giveback_arm_r && peak_gain > 0.0) {
        const double locked = (1.0 - c.giveback_cap_frac) * peak_gain;  // >= 0
        const double cand = s.entry + dir * locked;
        detail::tighten_sl(s.is_long, a.sl, cand);
    }

    // (4) tp_extension — extend the final TP while price nears it and the trend has NOT weakened.
    if (c.tp_extension && !s.trend_weakening && s.tp_extensions < c.tp_ext_max && s.atr > 0.0) {
        const double total     = (s.tp - s.entry) * dir;       // entry -> current TP (price)
        const double remaining = (s.tp - s.cur_price) * dir;   // price -> TP
        if (total > 0.0 && remaining > 0.0) {
            const double progress = (total - remaining) / total;  // [0,1)
            if (progress >= c.tp_ext_progress) {
                a.tp = s.tp + dir * c.tp_ext_atr_mult * s.atr;     // further only (engine merges extend-only)
            }
        }
    }

    // (6) partial_tp — one-shot fractional close at an R trigger.
    if (c.partial_tp && !s.partial_done && c.partial_trigger_r > 0.0
        && c.partial_frac > 0.0 && cur_r >= c.partial_trigger_r) {
        a.partial_frac = std::min(1.0, c.partial_frac);
    }

    return a;
}

}  // namespace kk::common
