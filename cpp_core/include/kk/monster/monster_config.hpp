// KK-MasterVP-Monster parameters — mirrors the EA's Config/InputParams.mqh (147 inputs).
// Struct defaults = the Monster Pine defaults EXACTLY (out-of-the-box behavior matches the Pine
// strategy: Breakout + Impulse ON, Reversion OFF, all gates/edge-candidates OFF). load_set()
// overrides from a .set file using the real InpXxx names so an MT5 .set drops straight in.
//
// This engine is SEPARATE from the KK-MasterVP engine (kk::Params / config.hpp). It inherits only
// the reusable value types (kk::Bar/Tick/VPResult) and the broker-spec economics pattern.
#pragma once
#include <string>
#include <fstream>
#include <algorithm>
#include <cmath>
#include "kk/common/profit_manager.hpp"

namespace kk::monster {

struct MonsterConfig {
    // ---- general / safety ----
    bool   allow_trading        = true;
    bool   allow_any_timeframe  = false;
    double max_spread_pips      = 0.0;     // 0 = off (Pine parity)
    double max_spread_tp1_frac  = 0.0;     // 0 = off

    // ---- risk / sizing ----
    int    risk_unit            = 0;       // 0=%Acc 1=USD 2=Min 3=Max
    double risk_usd             = 180.0;
    double risk_acc_pct         = 1.6;
    double max_daily_dd_pct     = 5.0;
    bool   use_tp1_partial      = true;
    double tp1_rr_brk           = 1.05;    // TP1 distance (R) — breakout & impulse
    double tp1_rr_rev           = 1.0;     // TP1 distance (R) — mean-reversion
    double tp1_close_pct_brk    = 10.0;    // % closed at TP1 — brk/imp
    double tp1_close_pct_rev    = 15.0;    // % closed at TP1 — reversion
    bool   be_after_tp1         = true;
    double be_buf_atr           = 0.05;
    bool   trail_runner         = false;   // Pine locks OFF
    double runner_rr            = 10.0;
    double trail_atr_mult       = 3.6;
    double min_atr_pct          = 0.04;    // vol floor (all kinds)
    double max_atr_pct          = 0.2;     // vol ceiling: normal kinds <=, impulse fires ONLY above
    bool   skip_if_minlot_over_risk = false;
    double max_lot              = 0.0;
    int    deviation_points     = 200;

    // ---- drawdown protection extras (EA-only; all OFF = Pine parity) ----
    double max_peak_dd_pct      = 0.0;
    double soft_block_dd_pct    = 0.0;
    double soft_block_lot_mult  = 0.55;
    double daily_dd_cooldown_hrs = 0.0;
    int    loss_streak_count    = 0;
    double loss_streak_cooldown_hrs = 4.0;

    // ---- master VP core ----
    int    vp_lookback          = 50;
    int    vp_bins              = 40;
    double va_pct               = 70.0;    // hidden const
    int    master_mult          = 3;       // hidden const -> 150-bar master
    double node_touch_atr       = 0.05;    // hidden const
    double node_decay           = 0.94;    // hidden const
    double node_neutral_band    = 0.15;    // hidden const
    double node_saturation      = 4.0;     // hidden const
    int    atr_len              = 14;      // hidden const
    int    vp_feed_mode         = 0;       // 0 = bar tick_volume (Pine parity)

    // ---- net tick volume ----
    bool   use_weighted_net     = true;
    bool   net_confirm_m1_or_m3 = false;
    bool   net_confirm_m5       = true;
    int    tf_net_look          = 50;      // hidden const
    double net_win_atr          = 1.5;     // hidden const
    double w_hvn                = 1.5;     // hidden const
    double w_mvn                = 1.0;     // hidden const
    double w_lvn                = 0.5;     // hidden const

    // ---- strategy: breakout ----
    bool   enable_breakout      = true;
    int    brk_fresh_bars       = 7;
    double brk_local_tol_atr    = 0.1;
    double brk_entry_buf_atr    = 1.0;
    double brk_max_dist_atr     = 1.8;
    double brk_net_min          = 0.80;
    double brk_net_min_m3       = 0.80;
    double brk_opp_max          = 0.80;
    double brk_sl_buf_atr       = 0.25;
    double brk_sl_atr_mult      = 2.0;
    double brk_rr_far           = 3.0;
    double brk_rr_near          = 2.0;
    int    brk_rr_lookback_bars = 25;      // hidden const
    bool   brk_overhead_veto    = false;
    double brk_proj_atr         = 1.5;
    int    brk_overhead_look    = 200;
    double brk_overhead_hvn_pct = 70.0;
    double brk_overhead_net_max = 0.5;

    // ---- strategy: impulse-thrust ----
    bool   enable_impulse       = true;
    double impulse_candle_atr   = 1.7;
    double impulse_entry_buf_atr = 0.4;
    double impulse_net_min      = 0.95;
    double impulse_max_dist_atr = 2.5;
    double impulse_rr           = 3.0;
    int    impulse_trend_slope_bars = 10;
    int    impulse_predict_bars = 10;      // aged-out master window age

    // ---- regime gate (opt-in) ----
    bool   enable_regime_gate   = false;
    double regime_tau_high      = 0.5;
    double regime_tau_low       = 0.25;

    // ---- master-POC stability gate (opt-in) ----
    double poc_stable_max_atr   = 0.2;
    bool   brk_require_poc_stable = false;
    bool   rev_require_poc_stable = false;

    // ---- strategy: mean-reversion ----
    bool   enable_reversion     = false;
    int    rev_fresh_bars       = 6;
    double rev_entry_dist_atr   = 1.0;
    double rev_max_dist_atr     = 2.0;
    double rev_net_min          = 0.80;
    double rev_opp_max          = 0.80;
    double rev_sl_buf_atr       = 0.2;
    double rev_sl_atr_mult      = 2.0;
    double rev_min_rr           = 1.5;
    double rev_anchor_off_atr   = 0.06;    // hidden const
    double rev_poc_sl_off_atr   = 0.1;     // hidden const

    // ---- HTF net-volume bias gate (opt-in) ----
    bool   enable_htf_bias      = false;
    double htf_bias_min         = 0.5;
    bool   htf_require_align    = false;

    // ---- stacking / early-exit ----
    int    max_concurrent_per_dir = 1;     // v1: single netted position
    bool   enable_early_exit    = false;   // legacy M1+M3/M3+M5 flush
    double exit_net_min         = 0.80;
    // multi-bar net volume (feature #1): persistence-on-entry + N-bar flip-exit
    bool   enable_net_persist   = false;
    int    net_persist_bars     = 3;
    double net_persist_min      = 0.5;
    bool   enable_net_flip_exit = false;
    int    net_flip_bars        = 3;
    double net_flip_min         = 0.5;
    bool   enable_m1_flush_exit = false;
    double m1_flush_net_min     = 0.80;
    int    m1_flush_bars        = 2;
    bool   m1_flush_underwater  = true;
    bool   enable_overhead_exit = false;
    bool   overhead_exit_underwater = true;

    // ---- edge candidates (Phase 4 — all OFF = baseline) ----
    bool   enable_failed_break_exit = false;
    int    fail_break_bars      = 6;
    double fail_break_net_flip  = 0.5;
    double fail_break_r_gate    = 0.5;
    bool   enable_structural_tp2 = false;
    double stp2_hvn_frac        = 0.66;
    double stp2_edge_off_atr    = 0.2;
    double stp2_min_rr          = 1.2;
    double stp2_max_rr          = 3.0;
    bool   enable_hvn_shelf_sl  = false;
    double shelf_near_atr       = 0.5;
    double shelf_far_atr        = 2.5;
    double shelf_buf_atr        = 0.25;

    // ---- shared ProfitManager toggles (kk::common, default OFF/inert) ----
    kk::common::PMConfig pm;

    // ---- sessions (UTC) ----
    bool   trade_anytime        = true;
    bool   enable_asia          = false;
    bool   enable_london        = false;
    bool   enable_ny            = false;
    bool   force_close_sess_news = false;
    int    broker_gmt_offset    = 0;
    std::string asia_sess       = "00:00-06:00";
    std::string ldn_sess        = "07:00-11:00";
    std::string ny_sess         = "12:30-16:30";
    std::string blocked_hours   = "";
    int    max_trades_per_session = 50;    // hidden const

    // ---- news ----
    bool   avoid_news           = false;
    int    news_mins_before     = 15;
    int    news_mins_after      = 15;

    // ---- symbol/runtime + broker specs (set per instrument, not from .set) ----
    double pip_size             = 0.01;
    double mintick              = 0.01;
    double contract_size        = 100.0;
    double tick_value           = 0.0;
    double tick_size            = 0.0;
    double lot_step             = 0.01;
    double min_lot              = 0.01;
    double broker_max_lot       = 100.0;
    double commission_per_lot   = 0.0;
    double start_balance        = 10000.0;

    void apply_xauusd_specs() {
        pip_size = 0.01; mintick = 0.01; contract_size = 100.0;
        tick_value = 1.00; tick_size = 0.01;            // vppl = 100
        lot_step = 0.01; min_lot = 0.01; commission_per_lot = 0.0; start_balance = 10000.0;
    }
    void apply_btcusd_specs() {
        pip_size = 0.01; mintick = 0.01; contract_size = 1.0;
        tick_value = 0.01; tick_size = 0.01;            // vppl = 1
        lot_step = 0.01; min_lot = 0.01; commission_per_lot = 0.0; start_balance = 10000.0;
    }

    int master_len() const { return vp_lookback * master_mult; }
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
inline std::string mtrim(std::string s) {
    auto nb = s.find_first_not_of(" \t\r\n");
    auto ne = s.find_last_not_of(" \t\r\n");
    return nb == std::string::npos ? "" : s.substr(nb, ne - nb + 1);
}
inline bool mbool(const std::string& v) { return v == "true" || v == "1"; }
}  // namespace detail

// Apply one InpXxx=value. Returns true if recognized (unknown/inert keys are ignored gracefully).
inline bool apply_kv(MonsterConfig& p, const std::string& key, const std::string& val) {
    using detail::mbool;
    auto D = [&] { return std::stod(val); };
    auto I = [&] { return std::stoi(val); };
    // general
    if (key == "InpAllowTrading") p.allow_trading = mbool(val);
    else if (key == "InpAllowAnyTimeframe") p.allow_any_timeframe = mbool(val);
    else if (key == "InpMaxSpreadPips") p.max_spread_pips = D();
    else if (key == "InpMaxSpreadTp1Frac") p.max_spread_tp1_frac = D();
    // risk
    else if (key == "InpRiskUnit") p.risk_unit = I();
    else if (key == "InpRiskUsd") p.risk_usd = D();
    else if (key == "InpRiskAccPct") p.risk_acc_pct = D();
    else if (key == "InpMaxDailyDDPct") p.max_daily_dd_pct = D();
    else if (key == "InpUseTp1Partial") p.use_tp1_partial = mbool(val);
    else if (key == "InpTp1RrBrk") p.tp1_rr_brk = D();
    else if (key == "InpTp1RrRev") p.tp1_rr_rev = D();
    else if (key == "InpTp1ClosePctBrk") p.tp1_close_pct_brk = D();
    else if (key == "InpTp1ClosePctRev") p.tp1_close_pct_rev = D();
    else if (key == "InpBeAfterTp1") p.be_after_tp1 = mbool(val);
    else if (key == "InpBeBufAtr") p.be_buf_atr = D();
    else if (key == "InpTrailRunner") p.trail_runner = mbool(val);
    else if (key == "InpRunnerRr") p.runner_rr = D();
    else if (key == "InpTrailAtrMult") p.trail_atr_mult = D();
    else if (key == "InpMinAtrPct") p.min_atr_pct = D();
    else if (key == "InpMaxAtrPct") p.max_atr_pct = D();
    else if (key == "InpSkipIfMinLotOverRisk") p.skip_if_minlot_over_risk = mbool(val);
    else if (key == "InpMaxLot") p.max_lot = D();
    else if (key == "InpDeviationPoints") p.deviation_points = I();
    // dd extras
    else if (key == "InpMaxPeakDDPct") p.max_peak_dd_pct = D();
    else if (key == "InpSoftBlockDDPct") p.soft_block_dd_pct = D();
    else if (key == "InpSoftBlockLotMult") p.soft_block_lot_mult = D();
    else if (key == "InpDailyDDCooldownHrs") p.daily_dd_cooldown_hrs = D();
    else if (key == "InpLossStreakCount") p.loss_streak_count = I();
    else if (key == "InpLossStreakCooldownHrs") p.loss_streak_cooldown_hrs = D();
    // vp core
    else if (key == "InpVpLookback") p.vp_lookback = I();
    else if (key == "InpVpBins") p.vp_bins = I();
    else if (key == "InpVaPct") p.va_pct = D();
    else if (key == "InpMasterMult") p.master_mult = I();
    else if (key == "InpNodeTouchAtr") p.node_touch_atr = D();
    else if (key == "InpNodeDecay") p.node_decay = D();
    else if (key == "InpNodeNeutralBand") p.node_neutral_band = D();
    else if (key == "InpNodeSaturation") p.node_saturation = D();
    else if (key == "InpAtrLen") p.atr_len = I();
    else if (key == "InpVpFeedMode") p.vp_feed_mode = I();
    // net
    else if (key == "InpUseWeightedNet") p.use_weighted_net = mbool(val);
    else if (key == "InpNetConfirmM1orM3") p.net_confirm_m1_or_m3 = mbool(val);
    else if (key == "InpNetConfirmM5") p.net_confirm_m5 = mbool(val);
    else if (key == "InpTfNetLook") p.tf_net_look = I();
    else if (key == "InpNetWinAtr") p.net_win_atr = D();
    else if (key == "InpWHvn") p.w_hvn = D();
    else if (key == "InpWMvn") p.w_mvn = D();
    else if (key == "InpWLvn") p.w_lvn = D();
    // breakout
    else if (key == "InpEnableBreakout") p.enable_breakout = mbool(val);
    else if (key == "InpBrkFreshBars") p.brk_fresh_bars = I();
    else if (key == "InpBrkLocalTolAtr") p.brk_local_tol_atr = D();
    else if (key == "InpBrkEntryBufAtr") p.brk_entry_buf_atr = D();
    else if (key == "InpBrkMaxDistAtr") p.brk_max_dist_atr = D();
    else if (key == "InpBrkNetMin") p.brk_net_min = D();
    else if (key == "InpBrkNetMinM3") p.brk_net_min_m3 = D();
    else if (key == "InpBrkOppMax") p.brk_opp_max = D();
    else if (key == "InpBrkSlBufAtr") p.brk_sl_buf_atr = D();
    else if (key == "InpBrkSlAtrMult") p.brk_sl_atr_mult = D();
    else if (key == "InpBrkRrFar") p.brk_rr_far = D();
    else if (key == "InpBrkRrNear") p.brk_rr_near = D();
    else if (key == "InpBrkRrLookbackBars") p.brk_rr_lookback_bars = I();
    else if (key == "InpBrkOverheadVeto") p.brk_overhead_veto = mbool(val);
    else if (key == "InpBrkProjAtr") p.brk_proj_atr = D();
    else if (key == "InpBrkOverheadLook") p.brk_overhead_look = I();
    else if (key == "InpBrkOverheadHvnPct") p.brk_overhead_hvn_pct = D();
    else if (key == "InpBrkOverheadNetMax") p.brk_overhead_net_max = D();
    // impulse
    else if (key == "InpEnableImpulse") p.enable_impulse = mbool(val);
    else if (key == "InpImpulseCandleAtr") p.impulse_candle_atr = D();
    else if (key == "InpImpulseEntryBufAtr") p.impulse_entry_buf_atr = D();
    else if (key == "InpImpulseNetMin") p.impulse_net_min = D();
    else if (key == "InpImpulseMaxDistAtr") p.impulse_max_dist_atr = D();
    else if (key == "InpImpulseRr") p.impulse_rr = D();
    else if (key == "InpImpulseTrendSlopeBars") p.impulse_trend_slope_bars = I();
    else if (key == "InpImpulsePredictBars") p.impulse_predict_bars = I();
    // regime gate
    else if (key == "InpEnableRegimeGate") p.enable_regime_gate = mbool(val);
    else if (key == "InpRegimeTauHigh") p.regime_tau_high = D();
    else if (key == "InpRegimeTauLow") p.regime_tau_low = D();
    // poc stability
    else if (key == "InpPocStableMaxAtr") p.poc_stable_max_atr = D();
    else if (key == "InpBrkRequirePocStable") p.brk_require_poc_stable = mbool(val);
    else if (key == "InpRevRequirePocStable") p.rev_require_poc_stable = mbool(val);
    // reversion
    else if (key == "InpEnableReversion") p.enable_reversion = mbool(val);
    else if (key == "InpRevFreshBars") p.rev_fresh_bars = I();
    else if (key == "InpRevEntryDistAtr") p.rev_entry_dist_atr = D();
    else if (key == "InpRevMaxDistAtr") p.rev_max_dist_atr = D();
    else if (key == "InpRevNetMin") p.rev_net_min = D();
    else if (key == "InpRevOppMax") p.rev_opp_max = D();
    else if (key == "InpRevSlBufAtr") p.rev_sl_buf_atr = D();
    else if (key == "InpRevSlAtrMult") p.rev_sl_atr_mult = D();
    else if (key == "InpRevMinRR") p.rev_min_rr = D();
    else if (key == "InpRevAnchorOffAtr") p.rev_anchor_off_atr = D();
    else if (key == "InpRevPocSlOffAtr") p.rev_poc_sl_off_atr = D();
    // htf bias
    else if (key == "InpEnableHtfBias") p.enable_htf_bias = mbool(val);
    else if (key == "InpHtfBiasMin") p.htf_bias_min = D();
    else if (key == "InpHtfRequireAlign") p.htf_require_align = mbool(val);
    // stacking / early exit
    else if (key == "InpEnableEarlyExit") p.enable_early_exit = mbool(val);
    else if (key == "InpExitNetMin") p.exit_net_min = D();
    else if (key == "InpEnableNetPersist") p.enable_net_persist = mbool(val);
    else if (key == "InpNetPersistBars") p.net_persist_bars = I();
    else if (key == "InpNetPersistMin") p.net_persist_min = D();
    else if (key == "InpEnableNetFlipExit") p.enable_net_flip_exit = mbool(val);
    else if (key == "InpNetFlipBars") p.net_flip_bars = I();
    else if (key == "InpNetFlipMin") p.net_flip_min = D();
    else if (key == "InpEnableM1FlushExit") p.enable_m1_flush_exit = mbool(val);
    else if (key == "InpM1FlushNetMin") p.m1_flush_net_min = D();
    else if (key == "InpM1FlushBars") p.m1_flush_bars = I();
    else if (key == "InpM1FlushUnderwater") p.m1_flush_underwater = mbool(val);
    else if (key == "InpEnableOverheadExit") p.enable_overhead_exit = mbool(val);
    else if (key == "InpOverheadExitUnderwater") p.overhead_exit_underwater = mbool(val);
    // edge candidates
    else if (key == "InpEnableFailedBreakExit") p.enable_failed_break_exit = mbool(val);
    else if (key == "InpFailBreakBars") p.fail_break_bars = I();
    else if (key == "InpFailBreakNetFlip") p.fail_break_net_flip = D();
    else if (key == "InpFailBreakRGate") p.fail_break_r_gate = D();
    else if (key == "InpEnableStructuralTp2") p.enable_structural_tp2 = mbool(val);
    else if (key == "InpStp2HvnFrac") p.stp2_hvn_frac = D();
    else if (key == "InpStp2EdgeOffAtr") p.stp2_edge_off_atr = D();
    else if (key == "InpStp2MinRr") p.stp2_min_rr = D();
    else if (key == "InpStp2MaxRr") p.stp2_max_rr = D();
    // ---- shared ProfitManager toggles ----
    else if (key == "InpPmBeProtect") p.pm.be_protect = mbool(val);
    else if (key == "InpPmBeTriggerR") p.pm.be_trigger_r = D();
    else if (key == "InpPmBeBufferR") p.pm.be_buffer_r = D();
    else if (key == "InpPmProgTrail") p.pm.prog_trail = mbool(val);
    else if (key == "InpPmProgTriggerR") p.pm.prog_trigger_r = D();
    else if (key == "InpPmProgIncrementR") p.pm.prog_increment_r = D();
    else if (key == "InpPmProgStepR") p.pm.prog_step_r = D();
    else if (key == "InpPmGiveback") p.pm.giveback = mbool(val);
    else if (key == "InpPmGivebackArmR") p.pm.giveback_arm_r = D();
    else if (key == "InpPmGivebackCapFrac") p.pm.giveback_cap_frac = D();
    else if (key == "InpPmTpExtension") p.pm.tp_extension = mbool(val);
    else if (key == "InpPmTpExtProgress") p.pm.tp_ext_progress = D();
    else if (key == "InpPmTpExtAtrMult") p.pm.tp_ext_atr_mult = D();
    else if (key == "InpPmTpExtMax") p.pm.tp_ext_max = I();
    else if (key == "InpPmPreBeStructure") p.pm.pre_be_structure = mbool(val);
    else if (key == "InpPmPreBeTriggerR") p.pm.pre_be_trigger_r = D();
    else if (key == "InpPmPreBeBuffer") p.pm.pre_be_buffer = D();
    else if (key == "InpPmPartialTp") p.pm.partial_tp = mbool(val);
    else if (key == "InpPmPartialTriggerR") p.pm.partial_trigger_r = D();
    else if (key == "InpPmPartialFrac") p.pm.partial_frac = D();
    else if (key == "InpEnableHvnShelfSl") p.enable_hvn_shelf_sl = mbool(val);
    else if (key == "InpShelfNearAtr") p.shelf_near_atr = D();
    else if (key == "InpShelfFarAtr") p.shelf_far_atr = D();
    else if (key == "InpShelfBufAtr") p.shelf_buf_atr = D();
    // sessions
    else if (key == "InpTradeAnytime") p.trade_anytime = mbool(val);
    else if (key == "InpEnableAsia") p.enable_asia = mbool(val);
    else if (key == "InpEnableLondon") p.enable_london = mbool(val);
    else if (key == "InpEnableNY") p.enable_ny = mbool(val);
    else if (key == "InpForceCloseSessNews") p.force_close_sess_news = mbool(val);
    else if (key == "InpBrokerGMTOffset") p.broker_gmt_offset = I();
    else if (key == "InpAsiaSess") p.asia_sess = val;
    else if (key == "InpLdnSess") p.ldn_sess = val;
    else if (key == "InpNySess") p.ny_sess = val;
    else if (key == "InpBlockedHoursStr") p.blocked_hours = val;
    else if (key == "InpMaxTradesPerSession") p.max_trades_per_session = I();
    // news
    else if (key == "InpAvoidNews") p.avoid_news = mbool(val);
    else if (key == "InpNewsMinsBefore") p.news_mins_before = I();
    else if (key == "InpNewsMinsAfter") p.news_mins_after = I();
    else return false;
    return true;
}

// Load a .set into p. Returns # keys applied (-1 if file missing).
inline int load_set(MonsterConfig& p, const std::string& path) {
    std::ifstream f(path);
    if (!f) return -1;
    int applied = 0;
    std::string line;
    while (std::getline(f, line)) {
        auto semic = line.find(';');
        if (semic != std::string::npos) line = line.substr(0, semic);
        line = detail::mtrim(line);
        if (line.empty()) continue;
        auto eq = line.find('=');
        if (eq == std::string::npos) continue;
        if (apply_kv(p, detail::mtrim(line.substr(0, eq)), detail::mtrim(line.substr(eq + 1)))) applied++;
    }
    return applied;
}

}  // namespace kk::monster
