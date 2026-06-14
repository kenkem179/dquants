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

namespace kk {

enum class Tf { M1, M3, M15 };   // entry TF is M1 or M3 (never M5); M15 only for the MTF gate

struct Params {
    // ---- VP core ----
    int    vp_lookback        = 50;
    int    vp_bins            = 30;
    double va_pct             = 70.0;
    int    master_mult        = 3;
    double node_touch_atr     = 0.05;
    double node_decay         = 0.94;
    double node_neutral_band  = 0.15;
    double node_saturation    = 4.0;
    int    atr_len            = 14;
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
    // ---- exit ----
    double tp1_r              = 0.8;
    double tp1_close_pct      = 20.0;
    bool   be_after_tp1       = true;
    double be_buf_atr         = 0.05;
    bool   trail_runner       = true;
    double runner_rr          = 10.0;
    double trail_atr_mult     = 3.6;
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
    double max_lot            = 0.0;
    int    deviation_points   = 200;
    bool   skip_if_minlot_over_risk = false;
    // ---- safety ----
    double min_atr_pct        = 0.0156;
    double max_atr_pct        = 0.158;
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
    int    broker_gmt_offset  = 0;
    std::string asia_sess     = "00:00-06:00";
    std::string ldn_sess      = "07:00-11:00";
    std::string ny_sess       = "12:30-16:30";
    std::string blocked_hours = "8,10,11,16";
    bool   force_close_sess_news = true;
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

    int master_len() const { return vp_lookback * master_mult; }
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

// Keys that are non-input compile-constants in InputParams.mqh (MT5 .set ignores them).
inline const std::unordered_set<std::string>& non_input_keys() {
    static const std::unordered_set<std::string> s = {
        "InpNodeGateEnabled", "InpUsePriorBarVP", "InpBrkRequireFlow", "InpSfpFlowMin",
        "InpUseAtrPctlGate", "InpRsiLen", "InpRsiMidline", "InpVpFeedMode",
        "InpVpBins", "InpVaPct", "InpMasterMult"};
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
    else if (key == "InpMasterMult") p.master_mult = I();
    else if (key == "InpNodeTouchAtr") p.node_touch_atr = D();
    else if (key == "InpNodeDecay") p.node_decay = D();
    else if (key == "InpNodeNeutralBand") p.node_neutral_band = D();
    else if (key == "InpNodeSaturation") p.node_saturation = D();
    else if (key == "InpAtrLen") p.atr_len = I();
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
    else if (key == "InpTp1R") p.tp1_r = D();
    else if (key == "InpTp1ClosePct") p.tp1_close_pct = D();
    else if (key == "InpBeAfterTp1") p.be_after_tp1 = to_bool(val);
    else if (key == "InpBeBufAtr") p.be_buf_atr = D();
    else if (key == "InpTrailRunner") p.trail_runner = to_bool(val);
    else if (key == "InpRunnerRr") p.runner_rr = D();
    else if (key == "InpTrailAtrMult") p.trail_atr_mult = D();
    else if (key == "InpEnableNetPersist") p.enable_net_persist = to_bool(val);
    else if (key == "InpNetPersistBars") p.net_persist_bars = I();
    else if (key == "InpNetPersistMin") p.net_persist_min = D();
    else if (key == "InpEnableNetFlipExit") p.enable_net_flip_exit = to_bool(val);
    else if (key == "InpNetFlipBars") p.net_flip_bars = I();
    else if (key == "InpNetFlipMin") p.net_flip_min = D();
    else if (key == "InpNetVolAvgLen") p.net_vol_avg_len = I();
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
    else if (key == "InpMaxLot") p.max_lot = D();
    else if (key == "InpDeviationPoints") p.deviation_points = I();
    else if (key == "InpSkipIfMinLotOverRisk") p.skip_if_minlot_over_risk = to_bool(val);
    else if (key == "InpMinAtrPct") p.min_atr_pct = D();
    else if (key == "InpMaxAtrPct") p.max_atr_pct = D();
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
    else if (key == "InpBrokerGMTOffset") p.broker_gmt_offset = I();
    else if (key == "InpAsiaSess") p.asia_sess = val;
    else if (key == "InpLdnSess") p.ldn_sess = val;
    else if (key == "InpNySess") p.ny_sess = val;
    else if (key == "InpBlockedHoursStr") p.blocked_hours = val;
    else if (key == "InpForceCloseSessNews") p.force_close_sess_news = to_bool(val);
    else if (key == "InpAvoidNews") p.avoid_news = to_bool(val);
    else if (key == "InpNewsMinsBefore") p.news_mins_before = I();
    else if (key == "InpNewsMinsAfter") p.news_mins_after = I();
    else if (key == "InpVpFeedMode") p.vp_feed_mode = I();
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
