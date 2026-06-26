// KK-MasterVP parameters — mirrors Config/InputParams.mqh. Struct defaults = MQL *code* defaults;
// load_set() overrides from a baseline .set file (the authoritative shipping config).
//
// PARITY HAZARD (non-input compile-constants): InpNodeGateEnabled, InpUsePriorBarVP,
// InpBrkRequireFlow, InpSfpFlowMin, InpUseAtrPctlGate, InpRsiLen, InpRsiMidline, InpVpFeedMode are
// declared WITHOUT `input` in InputParams.mqh, so the MT5 Strategy Tester IGNORES their .set lines and
// uses the compiled value. Most notably node_gate_enabled: code = true, baseline.set = false → MT5
// most likely ran with the gate ON. We keep these overridable and resolve the true effective value via
// the parity diff. `load_set(strict_inputs=true)` skips non-input keys to mimic MT5 exactly.
#pragma once
#include <string>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <cmath>
#include <unordered_set>
#include "kk/common/profit_manager.hpp"

namespace kk {

enum class Tf { M1, M3, M15 };   // entry TF is M1 or M3 (never M5); M15 only for the MTF gate

struct Params {
    // ---- VP core ----
    int    vp_lookback        = 50;
    int    vp_bins            = 30;
    double va_pct             = 70.0;
    double master_mult        = 3.0;   // float: master_len = round(vp_lookback * master_mult)
    double node_touch_atr     = 0.05;
    double node_decay         = 0.94;
    double node_neutral_band  = 0.15;
    double node_saturation    = 4.0;
    int    atr_len            = 14;
    bool   atr_mt5_mode       = false;   // false=textbook Wilder atr(); true=EMA k=2/(n+1) atr_mt5()
    // ---- regime ----
    int    ema_fast           = 24;
    int    ema_slow           = 194;
    int    adx_len            = 14;
    double adx_trend_min      = 22.0;
    double di_spread_min      = 6.0;
    double ema_sep_atr        = 0.25;
    // ---- entry shared (node_gate_enabled is a NON-INPUT in MQL: code=true) ----
    bool   node_gate_enabled  = true;
    bool   use_prior_bar_vp   = false;
    bool   brk_require_flow   = false;
    double sfp_flow_min       = 0.15;
    // ---- breakout ----
    bool   enable_breakout    = true;
    double break_buf_atr      = 0.65;
    double break_max_atr      = 9.0;
    double rr_brk             = 1.4;
    double sl_atr_brk         = 2.2;
    bool   brk_veto_sfp       = false;
    // ---- reversion ----
    bool   enable_reversion   = false;
    double retest_atr         = 0.5;
    double body_pct_min       = 0.4;
    double rr_rev             = 1.35;
    double sl_atr_rev         = 1.45;
    bool   rev_tp_mpoc        = false;   // reversion TP = master POC (full bank at the value magnet); OFF=rr_rev
    // Reversion is a TACTICAL fade in a balance regime. By default it triggers on, and targets, the
    // slow MASTER VP (480-bar). The user's standing hypothesis: a near-term fade should reference the
    // LOCAL (recent) value, not the slow master magnet. Both default OFF => base byte-identical.
    bool   rev_entry_local    = false;   // reversion touch trigger uses LOCAL VP edges instead of master
    bool   rev_tp_local       = false;   // rev_tp_mpoc target = LOCAL POC instead of master POC
    // ---- exit ----
    double tp1_r              = 0.8;
    double tp1_close_pct      = 20.0;
    bool   be_after_tp1       = true;
    double be_buf_atr         = 0.05;
    bool   trail_runner       = true;
    double runner_rr          = 10.0;
    double trail_atr_mult     = 3.6;
    // ---- per-entry-type trail override (tri-state: -1 inherit / 0 fixed-TP / 1 trail) ----
    // Lets each entry family override the GLOBAL trail_runner without touching it. -1 => inherit
    // trail_runner (default everywhere => base byte-identical). 0 => no trail (hold the fixed
    // sig.tp2 backstop, e.g. bank reversion/XRev at mPOC with rev_tp_mpoc/xrev_tp_mpoc). 1 => force
    // the chandelier trail. Resolved per-position at open in PositionManager (uses the Signal flags).
    int    trail_brk          = -1;   // breakout (impulse-less base path)
    int    trail_rev          = -1;   // base reversion
    int    trail_imp          = -1;   // Monster impulse-thrust
    int    trail_xrev         = -1;   // extreme reversion (XRev)
    // ---- Monster impulse-thrust path (kind 4) — default OFF = base byte-identical ----
    // The ONLY entry-model delta of KK-MasterVP-Monster over the faithful base: a single decisive
    // thrust candle that fires ONLY in the high-volatility band the normal ceiling (max_atr_pct)
    // vetoes. Confirmed by near-total one-sided M1 near-price net tick volume; trend-gated on the
    // master-POC slope + the predicted (aged-out) master profile. Reversion + all opt-in gates stay
    // OFF, so enabling impulse is the whole Monster delta. See [[monster-inherit-mastervp-base]].
    bool   enable_impulse        = false;  // master switch for the impulse path
    double impulse_candle_atr    = 1.7;    // min thrust-bar range (h-l) in ATR
    double impulse_entry_buf_atr = 0.4;    // min close beyond master VAH/VAL in ATR
    double impulse_net_min       = 0.95;   // min one-sided M1 near-price net (>= long / <= -this short)
    double impulse_max_dist_atr  = 2.5;    // anti-chase vs the PREDICTED edge in ATR; 0 = off
    double impulse_rr            = 3.0;    // impulse TP = close +/- this * stop distance
    int    impulse_trend_slope_bars = 10;  // master-POC slope lookback for the trend gate
    int    impulse_predict_bars  = 10;     // bars aged out of the master window for the predicted POC/VAH/VAL; 0 = use current
    int    tf_net_look           = 50;     // M1 net: bars summed for the near-price net
    double tf_net_win_atr        = 1.5;    // M1 net: near-price window half-width in ATR
    // ---- Extreme Reversion entry family (XRev) — default OFF = base byte-identical ----
    // A failed breakout above master VAH that SWEEPS the recent swing-high liquidity then snaps
    // back BELOW mVAH on a big sell-flow candle = trapped-breakout SHORT toward mVAL (long mirrors
    // at mVAL). Reuses the master VP + node order-flow + ATR + SL/TP bracket plumbing; the only new
    // logic is the sweep+rejection detector. See research/.../KK-MasterVP-ExtremeReversion.md.
    bool   enable_extreme_reversion = false; // master toggle (OFF)
    int    xrev_hh_lookback     = 5;     // N: swing-high/low sweep level lookback
    int    xrev_fail_lookback   = 14;    // M: window for the failed-acceptance count
    int    xrev_min_closes_beyond = 2;   // min closes beyond mVAH in M (trapped longs)
    int    xrev_max_closes_beyond = 0;   // cap to exclude a real sustained breakout; 0 = off
    int    xrev_min_age_bars    = 40;    // min bars since the opposite-edge cross (aged round-trip)
    double xrev_big_candle_atr  = 1.0;   // rejection-bar range >= x*ATR
    double xrev_body_pct_min    = 0.4;   // body fraction of range
    double xrev_wick_frac       = 1.0;   // sweep-tail wick >= x*body
    double xrev_net_delta_min   = 0.6;   // near-price net magnitude (sell-dominated flow)
    bool   xrev_use_node_gate   = true;  // require selling/absorption at mVAH
    double xrev_sl_atr          = 0.7;   // SL distance above the swept high
    double xrev_rr_min          = 2.0;   // min RR (entry->target vs SL) to take the trade
    bool   xrev_tp_mpoc         = false; // XRev TP = master POC (full bank, humble RR) instead of far edge; OFF=mVAL/mVAH
    // ---- multi-bar net volume (feature #1) — default OFF (inert) ----
    // Per-bar net flow = volume-weighted body ratio (c-o)/range * min(vol/avgVol, 3).
    // Persist: require last N closed bars all flow WITH the trade side beyond min before entry.
    // Flip-exit: close the open position if last N closed bars all flow AGAINST it beyond min.
    bool   enable_net_persist   = false;
    int    net_persist_bars     = 3;
    double net_persist_min      = 0.5;
    bool   enable_net_flip_exit = false;
    int    net_flip_bars        = 3;
    double net_flip_min         = 0.5;
    int    net_vol_avg_len      = 50;    // rolling tick-count window for the vol weight
    // ---- conviction-protect (TP1 redesign) — default OFF (inert) ----
    // Once a winner has run (MFE >= arm_r) AND the near-price VP node-net flips AGAINST the position
    // (long: net <= -net_min ; short: net >= +net_min — the panel's "Net ▼/over/under" verdict), bank a
    // one-shot partial AND ratchet the stop to lock lock_frac of the PEAK gain (giveback-style). This is
    // the "take TP1 with conviction, not blindly" exit: it fires only when flow confirms the retrace.
    bool   enable_conviction_protect = false;
    double conviction_arm_r       = 1.0;  // min MFE (in R) before the protect can arm
    double conviction_net_min     = 0.30; // near-price node-net magnitude against the trade to trigger
    double conviction_partial_frac= 0.50; // fraction of INITIAL volume to bank on trigger (one-shot)
    double conviction_lock_frac   = 0.50; // lock this fraction of PEAK gain as the new (tighter) stop
    // ---- node-structure TP (feature #2) — default OFF (inert) ----
    // Override the final/runner target with the next HVN shelf beyond TP1, clamped in R.
    bool   enable_struct_tp     = false;
    double stp_hvn_frac         = 0.66;  // node vol >= frac*maxVol counts as a shelf
    double stp_edge_off_atr     = 0.20;  // pull the target inside the shelf by this ATR
    double stp_min_rr           = 1.2;
    double stp_max_rr           = 3.0;
    // ---- FVG-anchored stop-loss (feature #3) — default OFF (inert / base byte-identical) ----
    // User thesis (testcases 1-6): anchor the SL just BEYOND the most recent significant Fair Value
    // Gap (3-bar imbalance) that sits between entry and the broken edge, instead of a fixed ATR stop.
    // The imbalance is untested price the move must reclaim to invalidate the trade, so a stop past it
    // is shielded from noise tags. For a LONG (broke up through VAH) the relevant FVG is BULLISH (gap
    // up: low[k] > high[k-2]); SL = bottom of that gap (high[k-2]) - buffer, i.e. BELOW entry. For a
    // SHORT (broke down through VAL) the FVG is BEARISH (gap down: high[k] < low[k-2]); SL = top of
    // that gap (low[k-2]) + buffer, i.e. ABOVE entry. We scan back fvg_lookback bars from the signal
    // bar, take the NEAREST qualifying gap, recompute risk + TP1/TP2 off the new stop. Guards keep it
    // sane: gap >= fvg_min_atr*ATR ("significant"); optionally the gap must lie beyond VAL/VAH
    // (fvg_beyond_va); resulting risk clamped to [fvg_min_risk_atr, fvg_max_risk_atr]*ATR. fvg_mode:
    // 0=replace (use the FVG stop whenever found), 1=widen-only (only if it is further than the ATR
    // stop — the user's "give it room" intent), 2=tighten-only. If no qualifying FVG: keep ATR stop.
    bool   enable_fvg_sl        = false;
    int    fvg_lookback         = 30;    // bars back from the signal bar to search for the gap
    double fvg_min_atr          = 0.30;  // min gap size (significance) in ATR
    double fvg_buf_atr          = 0.10;  // buffer placed beyond the gap edge, in ATR
    bool   fvg_beyond_va        = true;  // require the gap to sit beyond master VAL/VAH (outside value)
    int    fvg_mode             = 1;     // 0=replace, 1=widen-only, 2=tighten-only
    double fvg_min_risk_atr     = 0.50;  // clamp: floor on resulting risk in ATR
    double fvg_max_risk_atr     = 6.0;   // clamp: cap on resulting risk in ATR (else fall back to ATR SL)
    bool   fvg_breakout_only    = true;  // apply to breakout entries only (reversion keeps its own SL)
    bool   fvg_require          = false; // entry-gate: DROP a breakout with no qualifying structural FVG
    // ---- deferred / pullback-limit entry (shared module) — default OFF (inert) ----
    // Instead of a market fill on the signal bar, arm a virtual limit at a more favourable
    // price (entry pulled back by defer_pullback_atr*ATR) and fill within defer_bars if price
    // trades through it; cancel on expiry. SL/TP recompute off the limit price.
    bool   enable_defer_entry   = false;
    double defer_pullback_atr   = 0.5;
    int    defer_bars           = 3;
    // ---- shared ProfitManager toggles (kk::common, default OFF/inert) ----
    common::PMConfig pm;
    // ---- risk ----
    int    risk_unit          = 0;       // 0=%acct,1=USD,2=Min,3=Max
    double risk_usd           = 180.0;
    double risk_acc_pct       = 0.9;
    double max_daily_dd_pct   = 6.0;
    double max_peak_dd_pct    = 22.0;
    double soft_block_dd_pct  = 15.0;
    double soft_block_lot_mult = 0.55;
    int    loss_streak_count  = 3;
    double loss_streak_cooldown_hrs = 4.0;
    double daily_dd_cooldown_hrs    = 12.0;
    // H10c session-giveback stop: once the day has given back >= this % of its peak gain
    // (dayPeak - equity)/(dayPeak - dayStart), halt NEW entries for the rest of the day
    // (never truncates the open runner). 0 = OFF (byte-identical to the lock).
    double giveback_pct       = 0.0;
    double max_lot            = 0.0;
    int    deviation_points   = 200;
    bool   skip_if_minlot_over_risk = false;
    // ---- safety ----
    double min_atr_pct        = 0.0156;
    double max_atr_pct        = 0.158;
    double min_atr_ticks      = 0.0;     // Pine minAtrTicks floor (atr/mintick >= this); 0 = off
    int    max_trades_per_session = 4;
    double max_spread_pips    = 40.0;
    double max_spread_tp1_frac = 0.25;
    // ---- volatility RR (off) ----
    bool   enable_vol_rr      = false;
    double rr_asia_mul        = 0.85;
    double rr_london_mul      = 1.00;
    double rr_ny_mul          = 1.15;
    double atr_pctl_low       = 40.0;
    double atr_pctl_high      = 78.0;
    double rr_atr_low_mul     = 0.85;
    double rr_atr_high_mul    = 1.10;
    // ---- quality gates ----
    bool   use_mtf_agree      = true;
    Tf     htf_choice         = Tf::M15;
    bool   mtf_hard_veto      = true;
    bool   use_atr_pctl_gate  = false;
    bool   use_mom_veto       = true;
    int    rsi_len            = 14;
    double rsi_midline        = 50.0;
    // ---- sessions / news ----
    std::string asia_sess     = "00:00-06:00";
    std::string ldn_sess      = "07:00-11:00";
    std::string ny_sess       = "12:30-16:30";
    std::string blocked_hours = "8,10,11,16";
    bool   force_close_sess_news = true;
    int    day_reset_hour     = 0;       // UTC hour the trading day rolls (daily-DD reset); 0 = midnight
    bool   force_close_on_day_reset = false;  // flatten open positions at the day-reset hour (default OFF = parity)
    bool   avoid_news         = true;
    int    news_mins_before   = 15;
    int    news_mins_after    = 15;
    // ---- VP feed (NON-INPUT in MQL: 0=bar parity / 1=real tick) ----
    int    vp_feed_mode       = 0;
    // ---- symbol/runtime (set per instrument, not from .set) ----
    double pip_size           = 0.01;    // XAUUSD digits=2
    double mintick            = 0.01;
    double contract_size      = 100.0;
    // ---- broker specs (NOT in .set; supplied per instrument by the user for $ parity).
    // valuePerPricePerLot = tick_value/tick_size (falls back to contract_size if unset).
    // Placeholders below; the real Exness BTCUSD/XAUUSD values slot in here. ----
    double tick_value         = 0.0;     // USD per tick per lot (0 => use contract_size)
    double tick_size          = 0.0;     // price increment per tick
    double lot_step           = 0.01;    // broker volume step
    double min_lot            = 0.01;    // broker minimum volume
    double broker_max_lot     = 100.0;   // broker maximum volume (risk `max_lot` is the strategy cap)
    double commission_per_lot = 0.0;     // round-turn USD commission per lot
    double start_balance      = 10000.0; // tester starting balance

    // ---- broker spec presets (confirmed by the user from the Exness contract table) ----
    // Initial tester balance 10,000 USD, leverage 1:200, commission $0 on both symbols.
    void apply_xauusd_specs() {
        pip_size = 0.01; mintick = 0.01; contract_size = 100.0;   // 100 oz
        tick_value = 1.00; tick_size = 0.01;                      // vppl = 100
        lot_step = 0.01; min_lot = 0.01; commission_per_lot = 0.0; start_balance = 10000.0;
    }
    void apply_btcusd_specs() {
        pip_size = 0.01; mintick = 0.01; contract_size = 1.0;     // 1 BTC
        tick_value = 0.01; tick_size = 0.01;                      // vppl = 1
        lot_step = 0.01; min_lot = 0.01; commission_per_lot = 0.0; start_balance = 10000.0;
    }

    int master_len() const { return static_cast<int>(std::lround(vp_lookback * master_mult)); }
    // USD change per 1.0 price unit per 1.0 lot.
    double value_per_price_per_lot() const {
        return (tick_value > 0.0 && tick_size > 0.0) ? (tick_value / tick_size) : contract_size;
    }
    double normalize_lot(double lot) const {
        if (lot < min_lot) lot = min_lot;
        if (lot > broker_max_lot) lot = broker_max_lot;
        if (lot_step > 0.0) lot = std::round(lot / lot_step) * lot_step;
        if (lot < min_lot) lot = min_lot;
        return lot;
    }
};

namespace detail {
inline std::string trim(std::string s) {
    auto nb = s.find_first_not_of(" \t\r\n");
    auto ne = s.find_last_not_of(" \t\r\n");
    return nb == std::string::npos ? "" : s.substr(nb, ne - nb + 1);
}
inline bool to_bool(const std::string& v) { return v == "true" || v == "1"; }

// Keys that are non-input compile-constants in the KK-MasterVP EA's InputParams.mqh — MT5 SILENTLY
// IGNORES any .set value for them (they are not `input`s). Honoring them in C++ makes dquants diverge
// from MT5 on a parameter MT5 can't change. Verified 2026-06-16 against KK-MasterVP/Config/InputParams.mqh
// (full audit: research/kenkem_parity/PARAM_SURFACE_AUDIT.md). InpAtrLen was the missing one — it is
// "fixed at 14 for parity" in the EA yet leaked through (best_mastervp_*.set carried InpAtrLen=11/15).
inline const std::unordered_set<std::string>& non_input_keys() {
    static const std::unordered_set<std::string> s = {
        "InpNodeGateEnabled", "InpUsePriorBarVP", "InpBrkRequireFlow", "InpSfpFlowMin",
        "InpUseAtrPctlGate", "InpRsiLen", "InpRsiMidline", "InpVpFeedMode",
        "InpVpBins", "InpVaPct", "InpMasterMult", "InpAtrLen"};
    return s;
}
}  // namespace detail

// Apply one key=value. Returns true if the key was recognized.
inline bool apply_kv(Params& p, const std::string& key, const std::string& val) {
    using detail::to_bool;
    auto D = [&] { return std::stod(val); };
    auto I = [&] { return std::stoi(val); };
    if (key == "InpVpLookback") p.vp_lookback = I();
    else if (key == "InpVpBins") p.vp_bins = I();
    else if (key == "InpVaPct") p.va_pct = D();
    else if (key == "InpMasterMult") p.master_mult = D();
    else if (key == "InpNodeTouchAtr") p.node_touch_atr = D();
    else if (key == "InpNodeDecay") p.node_decay = D();
    else if (key == "InpNodeNeutralBand") p.node_neutral_band = D();
    else if (key == "InpNodeSaturation") p.node_saturation = D();
    else if (key == "InpAtrLen") p.atr_len = I();
    else if (key == "InpAtrMt5Mode") p.atr_mt5_mode = to_bool(val);
    else if (key == "InpEmaFast") p.ema_fast = I();
    else if (key == "InpEmaSlow") p.ema_slow = I();
    else if (key == "InpAdxLen") p.adx_len = I();
    else if (key == "InpAdxTrendMin") p.adx_trend_min = D();
    else if (key == "InpDiSpreadMin") p.di_spread_min = D();
    else if (key == "InpEmaSepAtr") p.ema_sep_atr = D();
    else if (key == "InpNodeGateEnabled") p.node_gate_enabled = to_bool(val);
    else if (key == "InpUsePriorBarVP") p.use_prior_bar_vp = to_bool(val);
    else if (key == "InpBrkRequireFlow") p.brk_require_flow = to_bool(val);
    else if (key == "InpSfpFlowMin") p.sfp_flow_min = D();
    else if (key == "InpEnableBreakout") p.enable_breakout = to_bool(val);
    else if (key == "InpBreakBufAtr") p.break_buf_atr = D();
    else if (key == "InpBreakMaxAtr") p.break_max_atr = D();
    else if (key == "InpRrBrk") p.rr_brk = D();
    else if (key == "InpSlAtrBrk") p.sl_atr_brk = D();
    else if (key == "InpBrkVetoSfp") p.brk_veto_sfp = to_bool(val);
    else if (key == "InpEnableReversion") p.enable_reversion = to_bool(val);
    else if (key == "InpRetestAtr") p.retest_atr = D();
    else if (key == "InpBodyPctMin") p.body_pct_min = D();
    else if (key == "InpRrRev") p.rr_rev = D();
    else if (key == "InpSlAtrRev") p.sl_atr_rev = D();
    else if (key == "InpRevTpMpoc") p.rev_tp_mpoc = to_bool(val);
    else if (key == "InpRevEntryLocal") p.rev_entry_local = to_bool(val);
    else if (key == "InpRevTpLocal") p.rev_tp_local = to_bool(val);
    else if (key == "InpTp1R") p.tp1_r = D();
    else if (key == "InpTp1ClosePct") p.tp1_close_pct = D();
    else if (key == "InpBeAfterTp1") p.be_after_tp1 = to_bool(val);
    else if (key == "InpBeBufAtr") p.be_buf_atr = D();
    else if (key == "InpTrailRunner") p.trail_runner = to_bool(val);
    else if (key == "InpRunnerRr") p.runner_rr = D();
    else if (key == "InpTrailAtrMult") p.trail_atr_mult = D();
    else if (key == "InpTrailBrk") p.trail_brk = I();
    else if (key == "InpTrailRev") p.trail_rev = I();
    else if (key == "InpTrailImp") p.trail_imp = I();
    else if (key == "InpTrailXRev") p.trail_xrev = I();
    else if (key == "InpEnableImpulse") p.enable_impulse = to_bool(val);
    else if (key == "InpImpulseCandleAtr") p.impulse_candle_atr = D();
    else if (key == "InpImpulseEntryBufAtr") p.impulse_entry_buf_atr = D();
    else if (key == "InpImpulseNetMin") p.impulse_net_min = D();
    else if (key == "InpImpulseMaxDistAtr") p.impulse_max_dist_atr = D();
    else if (key == "InpImpulseRr") p.impulse_rr = D();
    else if (key == "InpImpulseTrendSlopeBars") p.impulse_trend_slope_bars = I();
    else if (key == "InpImpulsePredictBars") p.impulse_predict_bars = I();
    else if (key == "InpTfNetLook") p.tf_net_look = I();
    else if (key == "InpTfNetWinAtr") p.tf_net_win_atr = D();
    else if (key == "InpEnableExtremeReversion") p.enable_extreme_reversion = to_bool(val);
    else if (key == "InpXRevHHLookback") p.xrev_hh_lookback = I();
    else if (key == "InpXRevFailLookback") p.xrev_fail_lookback = I();
    else if (key == "InpXRevMinClosesBeyond") p.xrev_min_closes_beyond = I();
    else if (key == "InpXRevMaxClosesBeyond") p.xrev_max_closes_beyond = I();
    else if (key == "InpXRevMinAgeBars") p.xrev_min_age_bars = I();
    else if (key == "InpXRevBigCandleAtr") p.xrev_big_candle_atr = D();
    else if (key == "InpXRevBodyPctMin") p.xrev_body_pct_min = D();
    else if (key == "InpXRevWickFrac") p.xrev_wick_frac = D();
    else if (key == "InpXRevNetDeltaMin") p.xrev_net_delta_min = D();
    else if (key == "InpXRevUseNodeGate") p.xrev_use_node_gate = to_bool(val);
    else if (key == "InpXRevSlAtr") p.xrev_sl_atr = D();
    else if (key == "InpXRevRrMin") p.xrev_rr_min = D();
    else if (key == "InpXRevTpMpoc") p.xrev_tp_mpoc = to_bool(val);
    else if (key == "InpEnableNetPersist") p.enable_net_persist = to_bool(val);
    else if (key == "InpNetPersistBars") p.net_persist_bars = I();
    else if (key == "InpNetPersistMin") p.net_persist_min = D();
    else if (key == "InpEnableNetFlipExit") p.enable_net_flip_exit = to_bool(val);
    else if (key == "InpNetFlipBars") p.net_flip_bars = I();
    else if (key == "InpNetFlipMin") p.net_flip_min = D();
    else if (key == "InpEnableConvictionProtect") p.enable_conviction_protect = to_bool(val);
    else if (key == "InpConvictionArmR") p.conviction_arm_r = D();
    else if (key == "InpConvictionNetMin") p.conviction_net_min = D();
    else if (key == "InpConvictionPartialFrac") p.conviction_partial_frac = D();
    else if (key == "InpConvictionLockFrac") p.conviction_lock_frac = D();
    else if (key == "InpNetVolAvgLen") p.net_vol_avg_len = I();
    else if (key == "InpEnableStructTp") p.enable_struct_tp = to_bool(val);
    else if (key == "InpStpHvnFrac") p.stp_hvn_frac = D();
    else if (key == "InpStpEdgeOffAtr") p.stp_edge_off_atr = D();
    else if (key == "InpStpMinRr") p.stp_min_rr = D();
    else if (key == "InpStpMaxRr") p.stp_max_rr = D();
    else if (key == "InpEnableFvgSl") p.enable_fvg_sl = to_bool(val);
    else if (key == "InpFvgLookback") p.fvg_lookback = I();
    else if (key == "InpFvgMinAtr") p.fvg_min_atr = D();
    else if (key == "InpFvgBufAtr") p.fvg_buf_atr = D();
    else if (key == "InpFvgBeyondVa") p.fvg_beyond_va = to_bool(val);
    else if (key == "InpFvgMode") p.fvg_mode = I();
    else if (key == "InpFvgMinRiskAtr") p.fvg_min_risk_atr = D();
    else if (key == "InpFvgMaxRiskAtr") p.fvg_max_risk_atr = D();
    else if (key == "InpFvgBreakoutOnly") p.fvg_breakout_only = to_bool(val);
    else if (key == "InpFvgRequire") p.fvg_require = to_bool(val);
    else if (key == "InpEnableDeferEntry") p.enable_defer_entry = to_bool(val);
    else if (key == "InpDeferPullbackAtr") p.defer_pullback_atr = D();
    else if (key == "InpDeferBars") p.defer_bars = I();
    // ---- shared ProfitManager toggles ----
    else if (key == "InpPmBeProtect") p.pm.be_protect = to_bool(val);
    else if (key == "InpPmBeTriggerR") p.pm.be_trigger_r = D();
    else if (key == "InpPmBeBufferR") p.pm.be_buffer_r = D();
    else if (key == "InpPmProgTrail") p.pm.prog_trail = to_bool(val);
    else if (key == "InpPmProgTriggerR") p.pm.prog_trigger_r = D();
    else if (key == "InpPmProgIncrementR") p.pm.prog_increment_r = D();
    else if (key == "InpPmProgStepR") p.pm.prog_step_r = D();
    else if (key == "InpPmGiveback") p.pm.giveback = to_bool(val);
    else if (key == "InpPmGivebackArmR") p.pm.giveback_arm_r = D();
    else if (key == "InpPmGivebackCapFrac") p.pm.giveback_cap_frac = D();
    else if (key == "InpPmTpExtension") p.pm.tp_extension = to_bool(val);
    else if (key == "InpPmTpExtProgress") p.pm.tp_ext_progress = D();
    else if (key == "InpPmTpExtAtrMult") p.pm.tp_ext_atr_mult = D();
    else if (key == "InpPmTpExtMax") p.pm.tp_ext_max = I();
    else if (key == "InpPmPreBeStructure") p.pm.pre_be_structure = to_bool(val);
    else if (key == "InpPmPreBeTriggerR") p.pm.pre_be_trigger_r = D();
    else if (key == "InpPmPreBeBuffer") p.pm.pre_be_buffer = D();
    else if (key == "InpPmPartialTp") p.pm.partial_tp = to_bool(val);
    else if (key == "InpPmPartialTriggerR") p.pm.partial_trigger_r = D();
    else if (key == "InpPmPartialFrac") p.pm.partial_frac = D();
    else if (key == "InpRiskUnit") p.risk_unit = I();
    else if (key == "InpRiskUsd") p.risk_usd = D();
    else if (key == "InpRiskAccPct") p.risk_acc_pct = D();
    else if (key == "InpMaxDailyDDPct") p.max_daily_dd_pct = D();
    else if (key == "InpMaxPeakDDPct") p.max_peak_dd_pct = D();
    else if (key == "InpSoftBlockDDPct") p.soft_block_dd_pct = D();
    else if (key == "InpSoftBlockLotMult") p.soft_block_lot_mult = D();
    else if (key == "InpLossStreakCount") p.loss_streak_count = I();
    else if (key == "InpLossStreakCooldownHrs") p.loss_streak_cooldown_hrs = D();
    else if (key == "InpDailyDDCooldownHrs") p.daily_dd_cooldown_hrs = D();
    else if (key == "InpGivebackPct") p.giveback_pct = D();
    else if (key == "InpMaxLot") p.max_lot = D();
    else if (key == "InpDeviationPoints") p.deviation_points = I();
    else if (key == "InpSkipIfMinLotOverRisk") p.skip_if_minlot_over_risk = to_bool(val);
    else if (key == "InpMinAtrPct") p.min_atr_pct = D();
    else if (key == "InpMaxAtrPct") p.max_atr_pct = D();
    else if (key == "InpMinAtrTicks") p.min_atr_ticks = D();
    else if (key == "InpMaxTradesPerSession") p.max_trades_per_session = I();
    else if (key == "InpMaxSpreadPips") p.max_spread_pips = D();
    else if (key == "InpMaxSpreadTp1Frac") p.max_spread_tp1_frac = D();
    else if (key == "InpEnableVolRR") p.enable_vol_rr = to_bool(val);
    else if (key == "InpAtrPctlLow") p.atr_pctl_low = D();
    else if (key == "InpAtrPctlHigh") p.atr_pctl_high = D();
    else if (key == "InpUseMtfAgree") p.use_mtf_agree = to_bool(val);
    else if (key == "InpMtfHardVeto") p.mtf_hard_veto = to_bool(val);
    else if (key == "InpUseAtrPctlGate") p.use_atr_pctl_gate = to_bool(val);
    else if (key == "InpUseMomVeto") p.use_mom_veto = to_bool(val);
    else if (key == "InpRsiLen") p.rsi_len = I();
    else if (key == "InpRsiMidline") p.rsi_midline = D();
    else if (key == "InpAsiaSess") p.asia_sess = val;
    else if (key == "InpLdnSess") p.ldn_sess = val;
    else if (key == "InpNySess") p.ny_sess = val;
    else if (key == "InpBlockedHoursStr") p.blocked_hours = val;
    else if (key == "InpForceCloseSessNews") p.force_close_sess_news = to_bool(val);
    else if (key == "InpDayResetHourUTC") p.day_reset_hour = I();
    else if (key == "InpForceCloseOnDayReset") p.force_close_on_day_reset = to_bool(val);
    else if (key == "InpAvoidNews") p.avoid_news = to_bool(val);
    else if (key == "InpNewsMinsBefore") p.news_mins_before = I();
    else if (key == "InpNewsMinsAfter") p.news_mins_after = I();
    else if (key == "InpVpFeedMode") p.vp_feed_mode = I();
    // Account economics (NOT an MQL `input`; MT5 sources commission from the account/symbol). The
    // engine needs it told so its $ P&L matches the tester. Importable so account type can be swapped.
    else if (key == "CommissionPerLot" || key == "InpCommissionPerLot") p.commission_per_lot = D();
    else return false;
    return true;
}

// Load a .set file into p. If mimic_mt5_noninput, skip the non-input compile-constants (so the loaded
// config matches what the Strategy Tester actually applied). Returns # of keys applied.
inline int load_set(Params& p, const std::string& path, bool mimic_mt5_noninput = false) {
    std::ifstream f(path);
    if (!f) return -1;
    int applied = 0;
    std::string line;
    while (std::getline(f, line)) {
        auto semic = line.find(';');
        if (semic != std::string::npos) line = line.substr(0, semic);
        line = detail::trim(line);
        if (line.empty()) continue;
        auto eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string key = detail::trim(line.substr(0, eq));
        std::string val = detail::trim(line.substr(eq + 1));
        if (mimic_mt5_noninput && detail::non_input_keys().count(key)) continue;
        if (apply_kv(p, key, val)) applied++;
    }
    return applied;
}

}  // namespace kk
