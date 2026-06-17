// KenKem "original" multi-entry EA parameters — mirrors Config/InputParams.mqh.
// Struct defaults = the EA's default config EXACTLY (E1/E2/E4 ON; E3/E5 OFF; adaptive/news/limit/
// conservative-mgmt OFF). load_set() overrides from a .set file using the EA's real input variable
// names (e.g. E1_RR, MIN_TREND_QUALITY_E1) so an MT5 .set drops straight in.
//
// SEPARATE engine (kk::kenkem) — inherits only reusable value types + broker-spec economics from the
// mastervp/monster engines. Scope = the static default path (see research/hypotheses/KenKem-SPEC.md §0).
#pragma once
#include <string>
#include <fstream>
#include <iterator>
#include <algorithm>
#include <cmath>
#include <unordered_set>
#include <cstdio>
#include "kk/common/profit_manager.hpp"

namespace kk::kenkem {

// HTF trend filter mode (InputParams.mqh enum HTF_TREND_MODE).
enum HtfMode { HTF_DISABLED = 0, HTF_M5_ONLY = 1, HTF_M5_AND_M15 = 2, HTF_M15_ONLY = 3, HTF_M5_OR_M15 = 4 };

struct KenKemConfig {
    // ---- account / sizing ----
    double initial_balance        = 3500.0;
    int    leverage               = 500;
    double std_lot                = 0.15;     // MY_STANDARD_LOT_SIZE
    double common_max_risk        = 0.02;     // COMMON_MAX_RISK_PER_TRADE
    double max_loss_ratio_e1      = 0.02 * 1.05;
    double max_loss_ratio_e2      = 0.02 * 1.00;
    double max_loss_ratio_e4      = 0.02 * 1.02;
    bool   increase_lot_on_profit = true;
    double profit_scale_w_cur     = 0.65;     // PROFIT_SCALING_WEIGHT_CURRENT
    double profit_scale_w_init    = 0.35;     // PROFIT_SCALING_WEIGHT_INITIAL
    double min_risk_floor_ratio   = 0.005;
    double margin_level_percent   = 100.0;    // used in margin-cap (rarely binding)

    // ---- entry enables ----
    bool   enable_e1              = true;
    bool   enable_e2              = true;
    bool   enable_e4              = true;
    bool   enable_e5              = false;   // SuperBros M1 EMA-alignment (default off, like the EA)
    // E3 intentionally absent (counter-trend, out of scope).
    double max_loss_ratio_e5      = 0.02;    // COMMON_MAX_RISK_PER_TRADE * 1.0

    // ---- drawdown / daily / session guards ----
    double max_daily_loss_ratio   = 0.072;
    double dd_ratio_slowdown      = 0.105;
    double dd_ratio_soft_block    = 0.13;
    double soft_block_lot_mult    = 0.3;
    double recovery_lot_mult      = 0.6;
    int    max_session_losses     = 4;        // MAX_SESSION_LOSSES
    int    max_sltp_per_session   = 7;        // MAX_SLTP_COUNT_PER_SESSION
    int    min_seconds_between    = 60;       // MIN_SECONDS_BETWEEN_ENTRIES
    int    max_consec_losses_type = 3;        // MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE (0 = off)
    int    consec_loss_block_mins = 60;       // ENTRY_BLOCK_AFTER_CONSECUTIVE_LOSS_MINS
    int    max_entries_per_day    = 0;        // hard cap on NEW entries per UTC day (0 = off).
                                              // Robust backstop proxy for the original's per-session
                                              // SLTP caps; prevents over-trading bleed.
    int    max_concurrent_pos     = 2;        // MAX_CONCURRENT_POSITIONS_ALLOWED
    bool   block_opposite_dir     = true;
    bool   close_at_session_end   = true;

    // ---- execute-stage high-risk routing (HandleHighRiskEntry / getMaxLossUSD) ----
    // A detected trade whose worst-case loss (riskDist * lot * contractSize) >= getMaxLossUSD(type) is
    // routed to the high-risk path (accept flag + per-session cap + sideway veto + momentum check). The
    // EA routes essentially every wide-SL E2 here; most fail the strict M1&M3 momentum gate and SKIP.
    bool   enable_black_swan      = true;     // ENABLE_BLACK_SWAN_PROTECTION (gates ATR low/high blocks)
    bool   accept_high_risk_e1    = true;     // ACCEPT_HIGH_RISK_E1_ENTRIES
    bool   accept_high_risk_e2    = true;     // ACCEPT_HIGH_RISK_E2_ENTRIES
    bool   accept_high_risk_e4    = true;     // ACCEPT_HIGH_RISK_E4_ENTRIES
    bool   accept_high_risk_e5    = true;     // ACCEPT_HIGH_RISK_E5_ENTRIES
    int    hr_momentum_e1         = 3;        // HIGH_RISK_E1_MOMENTUM_CHECK (3 = M1_AND_M3)
    int    hr_momentum_e2         = 3;        // HIGH_RISK_E2_MOMENTUM_CHECK (3 = M1_AND_M3)
    int    hr_momentum_e4         = 11;       // HIGH_RISK_E4_MOMENTUM_CHECK (11 = E1_ACCEL_M1_AND_M3)
    double e1_hr_min_adx          = 19.5;     // E1_HIGH_RISK_MIN_ADX (E4 reuses this — EA Entry4 cfg)
    double e1_hr_min_di_spread    = 4.0;      // E1_HIGH_RISK_MIN_DI_SPREAD
    double e2_hr_min_adx          = 21.5;     // E2_HIGH_RISK_MIN_ADX
    double e2_hr_min_di_spread    = 5.0;      // E2_HIGH_RISK_MIN_DI_SPREAD
    int    max_high_risk_per_session = 5;     // MAX_HIGH_RISK_TRADES_PER_SESSION
    double hr_tp_mult_asia        = 0.65;     // HIGH_RISK_TP_MULTIPLIER_ASIA
    double hr_tp_mult_eu          = 0.65;     // HIGH_RISK_TP_MULTIPLIER_EU
    double hr_tp_mult_us          = 0.70;     // HIGH_RISK_TP_MULTIPLIER_US

    // ---- trend-quality scoring ----
    bool   enable_tq_gates        = true;     // ENABLE_TREND_QUALITY_GATES
    int    min_tq_e1              = 6;
    int    min_tq_e2              = 9;
    int    min_tq_e4              = 9;
    bool   use_ichimoku_e1        = true;
    bool   use_ichimoku_e2        = false;
    bool   use_ichimoku_e4        = false;
    bool   use_acceleration_bonus = true;

    // ---- conviction scoring ----
    bool   use_conviction_e1      = true;
    int    conviction_thr_e1      = 7;
    bool   use_conviction_e2      = true;
    int    conviction_thr_e2      = 10;
    bool   use_conviction_e4      = true;
    int    conviction_thr_e4      = 9;
    bool   use_htf_veto_e1        = false;
    bool   use_htf_veto_e2        = false;
    bool   use_htf_veto_e4        = false;

    // ---- momentum / ADX thresholds ----
    double min_momentum_adx       = 19.7;     // MIN_MOMENTUM_ADX_REQUIRED
    double adx_low_threshold      = 14.5;
    double adx_high_threshold     = 25.0;
    bool   require_adx_confluence = true;
    double ema_align_tol_pips     = 23.0;
    double extreme_di_spread      = 16.0;

    // ---- sideways detection ----
    int    sideways_block_thr     = 53;
    int    sideways_warning_thr   = 43;
    double ema_spread_tight_atr   = 1.75;
    double ema_spread_moderate_atr = 3.25;
    double ema_spread_wide_atr    = 4.0;
    double atr_percentile_low     = 20.0;
    double atr_percentile_high    = 90.0;
    bool   enable_atr_high_block  = true;
    double min_entry_atr_pctile   = 65.0;     // MIN_ENTRY_ATR_PERCENTILE (0=off)
    int    atr_percentile_lookback = 32;

    // ---- RSI divergence veto ----
    bool   enable_rsi_div_veto    = true;
    int    rsi_div_lookback       = 16;
    double rsi_div_min_price_pips = 60.0;
    double rsi_div_min_rsi_diff   = 6.5;

    // ---- stop-loss ----
    int    sl_ema_distance        = 27;       // pips
    double min_sl_spread_mult     = 0.5;
    bool   e1_atr_sl_arb          = true;
    double e1_atr_sl_cap          = 4.0;
    double e1_atr_sl_floor        = 1.2;
    bool   e2_atr_sl_arb          = true;
    double e2_atr_sl_cap          = 3.0;
    double e2_atr_sl_floor        = 1.1;
    bool   e4_atr_sl_arb          = true;
    double e4_atr_sl_cap          = 4.0;
    double e4_atr_sl_floor        = 1.25;
    int    atr_period_for_sl      = 14;
    int    range_hilo_lookback    = 18;       // RANGE_HI_LOW_LOOK_BACK_BARS

    // ---- dynamic RR / TP ----
    bool   use_dynamic_rr         = true;
    double r_mult_be_trigger      = 0.87;
    double r_mult_be_buffer       = 0.055;
    bool   allow_partial_tp       = true;
    bool   allow_tp_extension     = true;
    double min_tp_progress_for_ext = 0.92;
    double partial_tp_retrace     = 0.15;
    bool   use_dynamic_tp_ext     = true;
    double atr_tp_ext_mult        = 0.035;
    double tp_ext_min_pips        = 7.0;
    double tp_ext_max_pips        = 60.0;

    // ---- shared ProfitManager toggles (kk::common, default OFF/inert) ----
    kk::common::PMConfig pm;

    // ---- exit toggles (defaults) ----
    bool   panic_exit_e1          = true;
    bool   panic_exit_e2          = true;
    bool   panic_exit_e4          = true;
    double panic_min_sl_used      = 0.6;
    double panic_min_profit_giveback = 0.5;
    bool   score_drop_e1          = false;
    int    score_drop_thr_e1      = 3;
    bool   score_drop_e2          = true;
    int    score_drop_thr_e2      = 2;
    bool   score_drop_e4          = true;
    int    score_drop_thr_e4      = 3;
    int    score_drop_consec      = 3;

    // ---- E1 ----
    HtfMode e1_htf_filter         = HTF_M5_ONLY;
    double e1_htf_min_adx         = 18.5;
    double e1_htf_min_di_spread   = 4.0;
    double e1_min_momentum_adx    = 19.5;
    int    e1_max_cross_age       = 80;
    int    e1_momentum_bypass     = 1;
    double e1_rr                  = 1.9;
    double e1_rr_sideway          = 1.2;
    double e1_partial_tp_trigger  = 0.90;
    double e1_partial_tp_ratio    = 0.20;
    double e1_be_buffer           = 0.07;
    double e1_trailing_factor     = 0.40;
    int    e1_max_tp_ext          = 40;
    double e1_rr_boost            = 1.08;
    bool   e1_ladder              = true;
    double e1_ladder_s1_mult      = 1.05, e1_ladder_s2_mult = 1.11, e1_ladder_s3_mult = 1.17;
    double e1_ladder_s1_trail     = 0.45, e1_ladder_s2_trail = 0.55, e1_ladder_s3_trail = 0.65;

    // ---- E2 ----
    double e2_min_momentum_adx    = 20.0;
    int    e2_max_touch_age       = 36;
    HtfMode e2_htf_filter         = HTF_M15_ONLY;
    double e2_htf_min_adx         = 23.0;
    double e2_htf_min_di_spread   = 3.0;
    double e2_rr                  = 1.575;
    double e2_rr_sideway          = 1.1;
    double e2_partial_tp_trigger  = 0.70;
    double e2_partial_tp_ratio    = 0.25;
    double e2_be_buffer           = 0.07;
    double e2_trailing_factor     = 0.45;
    int    e2_max_tp_ext          = 30;
    double e2_rr_boost            = 1.04;
    bool   e2_ladder              = true;
    double e2_ladder_s1_mult      = 1.04, e2_ladder_s2_mult = 1.09, e2_ladder_s3_mult = 1.14;
    double e2_ladder_s1_trail     = 0.40, e2_ladder_s2_trail = 0.50, e2_ladder_s3_trail = 0.60;

    // ---- E4 ----
    int    e4_max_sideway_score   = 40;
    bool   e4_require_m5_di_align  = true;
    HtfMode e4_htf_filter         = HTF_M5_OR_M15;
    double e4_htf_min_adx         = 20.5;
    double e4_htf_min_di_spread   = 6.0;
    double e4_min_momentum_adx    = 19.75;
    double e4_min_cloud_thick_atr = 0.11;
    bool   e4_require_tenkan_kijun = true;
    bool   e4_require_chikou_clear = false;
    int    e4_momentum_bypass     = 1;
    int    e4_max_cross_age       = 20;
    double e4_rr                  = 2.4;
    double e4_rr_short            = 1.8;
    double e4_rr_sideway          = 1.15;
    double e4_partial_tp_trigger  = 0.70;
    double e4_partial_tp_ratio    = 0.20;
    double e4_be_buffer           = 0.07;
    double e4_trailing_factor     = 0.50;
    int    e4_max_tp_ext          = 30;
    double e4_rr_boost            = 1.02;
    bool   e4_ladder              = true;
    double e4_ladder_s1_mult      = 1.10, e4_ladder_s2_mult = 1.18, e4_ladder_s3_mult = 1.27;
    double e4_ladder_s1_trail     = 0.45, e4_ladder_s2_trail = 0.55, e4_ladder_s3_trail = 0.65;

    // ---- E5 (SuperBros: fresh strict M1 EMA-stack alignment + price>EMA25) ----
    int    e5_max_ema_cross_age   = 28;
    double e5_min_momentum_adx    = 18.0;     // 0 = disabled
    bool   e5_require_trend_core  = true;     // E5 must pass the hard trend-core gate (original runs
                                              // E5 with MIN_TREND_QUALITY_E5; not a loose entry).
    HtfMode e5_htf_filter         = HTF_M5_ONLY;
    double e5_htf_min_adx         = 18.0;
    double e5_htf_min_di_spread   = 4.0;
    double e5_rr                  = 1.5;
    double e5_rr_sideway          = 1.2;
    double e5_partial_tp_trigger  = 0.54;
    double e5_partial_tp_ratio    = 0.50;
    double e5_be_buffer           = 0.05;
    double e5_trailing_factor     = 0.38;
    double e5_atr_sl_cap          = 4.0;
    double e5_atr_sl_floor        = 1.2;
    int    min_tq_e5              = 5;         // MIN_TREND_QUALITY_E5 (Pine v1-stable 5/11; 0 = off)
    bool   e5_use_atr_sl_arb      = false;     // E5_USE_ATR_SL_ARBITRATION (false => pure EMA200 stop)
    double e5_min_sl_pips         = 50.0;      // E5_MIN_SL_PIPS — floor on the E5 stop distance

    // ---- Ichimoku periods ----
    int    ichimoku_tenkan        = 9;
    int    ichimoku_kijun         = 26;
    int    ichimoku_senkou        = 52;

    // ---- timeframe + EMA/RSI/ADX periods ----
    // LIVE EMA periods are 10/25/71/97/192 — NOT the round 10/25/75/100/200 the enum LABELS suggest
    // (GlobalState enum EMA_75/EMA_100/EMA_200 are just index names; RuntimeConfig's CFG.ema* set is
    // dead code). Values come straight from INPUT_EMA*_PERIOD. See portnotes 01 §3.
    int    ema0_period            = 10;   // INPUT_EMA0_PERIOD (fast)
    int    ema1_period            = 25;   // INPUT_EMA1_PERIOD (signal)
    int    ema2_period            = 71;   // INPUT_EMA2_PERIOD (pullback — label "75" is STALE)
    int    ema3_period            = 97;   // INPUT_EMA3_PERIOD (bounce  — label "100" is STALE)
    int    ema4_period            = 192;  // INPUT_EMA4_PERIOD (anchor  — label "200" is STALE)
    int    rsi_len                = 14;   // RSI_LEN
    int    adx_len                = 14;   // ADX_LEN
    // TF map is fixed: TF0=M1, TF1=M3, TF2=M5, TF3=M15, TF4=H1(reserved). NUM_TF=4, NUM_EMA=5.

    // ---- sessions (UTC, HHMM) ----
    // Converted 1:1 from the EA's legacy JST windows (JST = UTC+9) so this engine and the MQL5 EA
    // share one identical clock. JST 0900/1230/1400/1830/2100/2400 -> UTC 0000/0330/0500/0930/1200/1500.
    int    japan_start = 0,    japan_end = 330;
    int    london_start = 500, london_end = 930;
    int    ny_start = 1200,    ny_end = 1500;
    bool   ignore_valid_sessions  = false;
    int    server_gmt_offset      = 0;        // ticks are UTC and windows are UTC -> offset 0 (legacy knob)

    // ---- symbol/runtime + broker specs (per instrument, not from .set) ----
    double pip_size           = 0.01;
    double contract_size      = 100.0;
    double tick_value         = 1.0;
    double tick_size          = 0.01;
    double lot_step           = 0.01;
    double min_lot            = 0.01;
    double broker_max_lot     = 100.0;
    double commission_per_lot = 0.0;
    double start_balance      = 10000.0;
    // Broker minimum stop distance = max(SYMBOL_TRADE_STOPS_LEVEL, FREEZE_LEVEL) * point, IN PRICE.
    // The EA refuses to move a SL (BE/trail) closer than this to the market price (Engine.mqh:343-344,
    // 351-352). Default 0 = Exness XAU/BTC (stops level 0) ⇒ inert ⇒ no behavior change. Set per-broker
    // to keep the engine's managed exits byte-faithful to MT5 on brokers with a nonzero stops level.
    double stops_level_price  = 0.0;

    // Per-symbol overrides mirror KenKemExpert.mq5 OnInit (:122-163). Call AFTER load_set() so the
    // BTC std-lot ×2 override applies on top of the loaded MY_STANDARD_LOT_SIZE, exactly as the EA does.
    void apply_xauusd_specs() {
        // Gold branch (:122-126): pip = 10^-digits (2-digit Exness gold -> 0.01); contract from broker.
        pip_size = 0.01; contract_size = 100.0; tick_value = 1.00; tick_size = 0.01;
        lot_step = 0.01; min_lot = 0.01; commission_per_lot = 0.0; start_balance = 10000.0;
        // no std-lot multiplier for gold
    }
    void apply_btcusd_specs() {
        // BTCUSD override (:158-162): pipSize=1, contractSize=1, std-lot ×2, minLot=0.01.
        pip_size = 1.0; contract_size = 1.0; tick_value = 0.01; tick_size = 0.01;
        lot_step = 0.01; min_lot = 0.01; commission_per_lot = 0.0; start_balance = 10000.0;
        std_lot *= 2.0;   // EA doubles MY_STANDARD_LOT_SIZE for BTCUSD
    }
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
inline std::string ktrim(std::string s) {
    auto nb = s.find_first_not_of(" \t\r\n");
    auto ne = s.find_last_not_of(" \t\r\n");
    return nb == std::string::npos ? "" : s.substr(nb, ne - nb + 1);
}
inline bool kbool(const std::string& v) { return v == "true" || v == "1"; }
}  // namespace detail

// ===========================================================================================
// EA-LOCKED KEYS — the trust guarantee.
// These keys correspond to variables the KenKem EA HARDCODES in Config/InputParams.mqh — they are
// NOT `input`s, so MetaTrader SILENTLY IGNORES any .set value for them. Examples: ADX_LEN(:545)=14,
// RSI_LEN(:544)=14, ICHIMOKU_*(:132-134), USE_CONVICTION_SCORING_E{1,2,4}(:107/109/117),
// USE_HTF_VETO_E{1,2,4}(:114/115/119), USE_ICHIMOKU_E{1,2,4}(:124/126/128),
// IGNORE_VALID_SESSIONS(:550), and the JAPAN/LONDON/NY session windows.
// The C++ struct defaults already equal the EA's hardcoded values, so honoring a .set OVERRIDE for
// any of these would make dquants compute on a parameter MT5 can never change — guaranteeing a
// C++/MT5 divergence and poisoning every sweep that touched it (this is the ADX_LEN/RSI_LEN bug that
// inverted the KenKem verdict; 51 sweep .sets were contaminated). We therefore REFUSE the override
// and keep the EA value, warning once per key. Full audit: research/kenkem_parity/PARAM_SURFACE_AUDIT.md
inline bool is_ea_locked_key(const std::string& k) {
    static const std::unordered_set<std::string> locked = {
        "ADX_LEN", "RSI_LEN",
        "ICHIMOKU_TENKAN", "ICHIMOKU_KIJUN", "ICHIMOKU_SENKOU",
        "USE_CONVICTION_SCORING_E1", "USE_CONVICTION_SCORING_E2", "USE_CONVICTION_SCORING_E4",
        "USE_HTF_VETO_E1", "USE_HTF_VETO_E2", "USE_HTF_VETO_E4",
        "USE_ICHIMOKU_E1", "USE_ICHIMOKU_E2", "USE_ICHIMOKU_E4",
        "IGNORE_VALID_SESSIONS",
        "JAPAN_START", "JAPAN_END", "LONDON_START", "LONDON_END", "NY_START", "NY_END",
        "JAPAN_SESSION_START", "JAPAN_SESSION_END", "LONDON_SESSION_START", "LONDON_SESSION_END",
        "NEWYORK_SESSION_START", "NEWYORK_SESSION_END",
    };
    return locked.count(k) > 0;
}

// Apply one KEY=value using the EA's real input variable names. Unknown keys ignored gracefully.
inline bool apply_kv(KenKemConfig& p, const std::string& key, const std::string& val) {
    using detail::kbool;
    // Refuse EA-hardcoded params: MT5 ignores them, so honoring them here breaks parity. Warn once.
    if (is_ea_locked_key(key)) {
        static std::unordered_set<std::string> warned;
        if (warned.insert(key).second)
            std::fprintf(stderr,
                "[kenkem_config] IGNORING .set key '%s=%s' — the EA HARDCODES this (not an input); "
                "MT5 cannot honor it. Keeping the EA value to preserve parity.\n",
                key.c_str(), val.c_str());
        return false;  // not applied: leaves the EA-default in place; load_set won't count it
    }
    auto D = [&] { return std::stod(val); };
    auto I = [&] { return std::stoi(val); };
    auto H = [&] { return (HtfMode)std::stoi(val); };
    // account / sizing
    if (key == "MY_STANDARD_LOT_SIZE") p.std_lot = D();
    else if (key == "COMMON_MAX_RISK_PER_TRADE") p.common_max_risk = D();
    else if (key == "INCREASE_LOT_SIZE_BASED_ON_PROFIT") p.increase_lot_on_profit = kbool(val);
    else if (key == "PROFIT_SCALING_WEIGHT_CURRENT") p.profit_scale_w_cur = D();
    else if (key == "PROFIT_SCALING_WEIGHT_INITIAL") p.profit_scale_w_init = D();
    else if (key == "MIN_RISK_FLOOR_RATIO") p.min_risk_floor_ratio = D();
    // enables
    else if (key == "ENABLE_E1_ENTRIES") p.enable_e1 = kbool(val);
    else if (key == "ENABLE_E2_ENTRIES") p.enable_e2 = kbool(val);
    else if (key == "ENABLE_E4_ENTRIES") p.enable_e4 = kbool(val);
    else if (key == "ENABLE_E5_ENTRIES") p.enable_e5 = kbool(val);
    else if (key == "E5_MAX_EMA_CROSS_AGE") p.e5_max_ema_cross_age = I();
    else if (key == "E5_MIN_MOMENTUM_ADX") p.e5_min_momentum_adx = D();
    else if (key == "E5_REQUIRE_TREND_CORE") p.e5_require_trend_core = kbool(val);
    else if (key == "MAX_ENTRIES_PER_DAY") p.max_entries_per_day = I();
    else if (key == "E5_HTF_TREND_FILTER") p.e5_htf_filter = H();
    else if (key == "E5_HTF_MIN_ADX") p.e5_htf_min_adx = D();
    else if (key == "E5_HTF_MIN_DI_SPREAD") p.e5_htf_min_di_spread = D();
    else if (key == "E5_RR") p.e5_rr = D();
    else if (key == "E5_RR_SIDEWAY") p.e5_rr_sideway = D();
    else if (key == "E5_PARTIAL_TP_TRIGGER") p.e5_partial_tp_trigger = D();
    else if (key == "E5_PARTIAL_TP_RATIO") p.e5_partial_tp_ratio = D();
    else if (key == "E5_SL_TO_BREAKEVEN_BUFFER") p.e5_be_buffer = D();
    else if (key == "E5_TRAILING_SL_FACTOR") p.e5_trailing_factor = D();
    else if (key == "E5_ATR_SL_CAP_MULTIPLIER") p.e5_atr_sl_cap = D();
    else if (key == "E5_ATR_SL_FLOOR_MULTIPLIER") p.e5_atr_sl_floor = D();
    else if (key == "E5_USE_ATR_SL_ARBITRATION") p.e5_use_atr_sl_arb = kbool(val);
    else if (key == "E5_MIN_SL_PIPS") p.e5_min_sl_pips = D();
    // guards
    else if (key == "MAX_DAILY_LOSS_RATIO") p.max_daily_loss_ratio = D();
    else if (key == "ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN") p.dd_ratio_slowdown = D();
    else if (key == "ACCOUNT_DD_RATIO_TO_SOFT_BLOCK") p.dd_ratio_soft_block = D();
    else if (key == "SOFT_BLOCK_LOT_MULTIPLIER") p.soft_block_lot_mult = D();
    else if (key == "RECOVERY_MODE_LOT_MULTIPLIER") p.recovery_lot_mult = D();
    else if (key == "MAX_SESSION_LOSSES") p.max_session_losses = I();
    else if (key == "MAX_SLTP_COUNT_PER_SESSION") p.max_sltp_per_session = I();
    else if (key == "MIN_SECONDS_BETWEEN_ENTRIES") p.min_seconds_between = I();
    else if (key == "MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE") p.max_consec_losses_type = I();
    else if (key == "ENTRY_BLOCK_AFTER_CONSECUTIVE_LOSS_MINS") p.consec_loss_block_mins = I();
    else if (key == "MAX_CONCURRENT_POSITIONS_ALLOWED") p.max_concurrent_pos = I();
    else if (key == "BLOCK_OPPOSITE_DIRECTION_ENTRIES") p.block_opposite_dir = kbool(val);
    else if (key == "CLOSE_ALL_TRADES_AT_SESSION_END") p.close_at_session_end = kbool(val);
    // trend quality
    else if (key == "ENABLE_TREND_QUALITY_GATES") p.enable_tq_gates = kbool(val);
    else if (key == "MIN_TREND_QUALITY_E1") p.min_tq_e1 = I();
    else if (key == "MIN_TREND_QUALITY_E2") p.min_tq_e2 = I();
    else if (key == "MIN_TREND_QUALITY_E4") p.min_tq_e4 = I();
    else if (key == "MIN_TREND_QUALITY_E5") p.min_tq_e5 = I();
    else if (key == "USE_ICHIMOKU_E1") p.use_ichimoku_e1 = kbool(val);
    else if (key == "USE_ICHIMOKU_E2") p.use_ichimoku_e2 = kbool(val);
    else if (key == "USE_ICHIMOKU_E4") p.use_ichimoku_e4 = kbool(val);
    else if (key == "USE_ACCELERATION_BONUS") p.use_acceleration_bonus = kbool(val);
    // conviction
    else if (key == "USE_CONVICTION_SCORING_E1") p.use_conviction_e1 = kbool(val);
    else if (key == "CONVICTION_THRESHOLD_E1") p.conviction_thr_e1 = I();
    else if (key == "USE_CONVICTION_SCORING_E2") p.use_conviction_e2 = kbool(val);
    else if (key == "CONVICTION_THRESHOLD_E2") p.conviction_thr_e2 = I();
    else if (key == "USE_CONVICTION_SCORING_E4") p.use_conviction_e4 = kbool(val);
    else if (key == "CONVICTION_THRESHOLD_E4") p.conviction_thr_e4 = I();
    else if (key == "USE_HTF_VETO_E1") p.use_htf_veto_e1 = kbool(val);
    else if (key == "USE_HTF_VETO_E2") p.use_htf_veto_e2 = kbool(val);
    else if (key == "USE_HTF_VETO_E4") p.use_htf_veto_e4 = kbool(val);
    // momentum
    else if (key == "MIN_MOMENTUM_ADX_REQUIRED") p.min_momentum_adx = D();
    else if (key == "ADX_LOW_THRESHOLD") p.adx_low_threshold = D();
    else if (key == "ADX_HIGH_THRESHOLD") p.adx_high_threshold = D();
    else if (key == "REQUIRE_ADX_CONFLUENCE") p.require_adx_confluence = kbool(val);
    else if (key == "EMA_ALIGNMENT_TOLERANCE_PIPS") p.ema_align_tol_pips = D();
    else if (key == "EXTREME_DI_SPREAD_THRESHOLD") p.extreme_di_spread = D();
    // sideways
    else if (key == "SIDEWAYS_BLOCK_THRESHOLD") p.sideways_block_thr = I();
    else if (key == "SIDEWAYS_WARNING_THRESHOLD") p.sideways_warning_thr = I();
    else if (key == "EMA_SPREAD_TIGHT_ATR") p.ema_spread_tight_atr = D();
    else if (key == "EMA_SPREAD_MODERATE_ATR") p.ema_spread_moderate_atr = D();
    else if (key == "EMA_SPREAD_WIDE_ATR") p.ema_spread_wide_atr = D();
    else if (key == "ATR_PERCENTILE_LOW") p.atr_percentile_low = D();
    else if (key == "ATR_PERCENTILE_HIGH") p.atr_percentile_high = D();
    else if (key == "ENABLE_ATR_HIGH_BLOCK") p.enable_atr_high_block = kbool(val);
    else if (key == "MIN_ENTRY_ATR_PERCENTILE") p.min_entry_atr_pctile = D();
    else if (key == "ATR_PERCENTILE_LOOKBACK") p.atr_percentile_lookback = I();
    else if (key == "ENABLE_BLACK_SWAN_PROTECTION") p.enable_black_swan = kbool(val);
    // execute-stage high-risk routing
    else if (key == "ACCEPT_HIGH_RISK_E1_ENTRIES") p.accept_high_risk_e1 = kbool(val);
    else if (key == "ACCEPT_HIGH_RISK_E2_ENTRIES") p.accept_high_risk_e2 = kbool(val);
    else if (key == "ACCEPT_HIGH_RISK_E4_ENTRIES") p.accept_high_risk_e4 = kbool(val);
    else if (key == "ACCEPT_HIGH_RISK_E5_ENTRIES") p.accept_high_risk_e5 = kbool(val);
    else if (key == "HIGH_RISK_E1_MOMENTUM_CHECK") p.hr_momentum_e1 = I();
    else if (key == "HIGH_RISK_E2_MOMENTUM_CHECK") p.hr_momentum_e2 = I();
    else if (key == "HIGH_RISK_E4_MOMENTUM_CHECK") p.hr_momentum_e4 = I();
    else if (key == "E1_HIGH_RISK_MIN_ADX") p.e1_hr_min_adx = D();
    else if (key == "E1_HIGH_RISK_MIN_DI_SPREAD") p.e1_hr_min_di_spread = D();
    else if (key == "E2_HIGH_RISK_MIN_ADX") p.e2_hr_min_adx = D();
    else if (key == "E2_HIGH_RISK_MIN_DI_SPREAD") p.e2_hr_min_di_spread = D();
    else if (key == "MAX_HIGH_RISK_TRADES_PER_SESSION") p.max_high_risk_per_session = I();
    else if (key == "HIGH_RISK_TP_MULTIPLIER_ASIA") p.hr_tp_mult_asia = D();
    else if (key == "HIGH_RISK_TP_MULTIPLIER_EU") p.hr_tp_mult_eu = D();
    else if (key == "HIGH_RISK_TP_MULTIPLIER_US") p.hr_tp_mult_us = D();
    // rsi div
    else if (key == "ENABLE_RSI_DIVERGENCE_VETO") p.enable_rsi_div_veto = kbool(val);
    else if (key == "RSI_DIV_LOOKBACK") p.rsi_div_lookback = I();
    else if (key == "RSI_DIV_MIN_PRICE_DIFF_PIPS") p.rsi_div_min_price_pips = D();
    else if (key == "RSI_DIV_MIN_RSI_DIFF") p.rsi_div_min_rsi_diff = D();
    // stop loss
    else if (key == "SL_EMA_DISTANCE") p.sl_ema_distance = I();
    else if (key == "MIN_SL_SPREAD_MULT") p.min_sl_spread_mult = D();
    else if (key == "E1_USE_ATR_SL_ARBITRATION") p.e1_atr_sl_arb = kbool(val);
    else if (key == "E1_ATR_SL_CAP_MULTIPLIER") p.e1_atr_sl_cap = D();
    else if (key == "E1_ATR_SL_FLOOR_MULTIPLIER") p.e1_atr_sl_floor = D();
    else if (key == "E2_USE_ATR_SL_ARBITRATION") p.e2_atr_sl_arb = kbool(val);
    else if (key == "E2_ATR_SL_CAP_MULTIPLIER") p.e2_atr_sl_cap = D();
    else if (key == "E2_ATR_SL_FLOOR_MULTIPLIER") p.e2_atr_sl_floor = D();
    else if (key == "E4_USE_ATR_SL_ARBITRATION") p.e4_atr_sl_arb = kbool(val);
    else if (key == "E4_ATR_SL_CAP_MULTIPLIER") p.e4_atr_sl_cap = D();
    else if (key == "E4_ATR_SL_FLOOR_MULTIPLIER") p.e4_atr_sl_floor = D();
    else if (key == "ATR_PERIOD_FOR_SL") p.atr_period_for_sl = I();
    else if (key == "RANGE_HI_LOW_LOOK_BACK_BARS") p.range_hilo_lookback = I();
    // dynamic rr / tp
    else if (key == "USE_DYNAMIC_RR_SCALING") p.use_dynamic_rr = kbool(val);
    else if (key == "R_MULT_BE_TRIGGER") p.r_mult_be_trigger = D();
    else if (key == "R_MULT_BE_BUFFER") p.r_mult_be_buffer = D();
    else if (key == "ALLOW_PARTIAL_TP") p.allow_partial_tp = kbool(val);
    else if (key == "ALLOW_TP_EXTENSION") p.allow_tp_extension = kbool(val);
    else if (key == "MIN_TP_PROGRESS_FOR_EXTENSION") p.min_tp_progress_for_ext = D();
    else if (key == "PARTIAL_TP_RETRACE_RATIO") p.partial_tp_retrace = D();
    else if (key == "USE_DYNAMIC_TP_EXTENSION") p.use_dynamic_tp_ext = kbool(val);
    else if (key == "ATR_TP_EXTENSION_MULTIPLIER") p.atr_tp_ext_mult = D();
    else if (key == "TP_EXTENSION_MIN_PIPS") p.tp_ext_min_pips = D();
    else if (key == "TP_EXTENSION_MAX_PIPS") p.tp_ext_max_pips = D();
    // exits
    else if (key == "ENABLE_FAST_ADX_PANIC_EXIT_E1") p.panic_exit_e1 = kbool(val);
    else if (key == "ENABLE_FAST_ADX_PANIC_EXIT_E2") p.panic_exit_e2 = kbool(val);
    else if (key == "ENABLE_FAST_ADX_PANIC_EXIT_E4") p.panic_exit_e4 = kbool(val);
    else if (key == "PANIC_MIN_SL_USED_RATIO") p.panic_min_sl_used = D();
    else if (key == "PANIC_MIN_PROFIT_GIVEBACK") p.panic_min_profit_giveback = D();
    else if (key == "ENABLE_SCORE_DROP_EXIT_E1") p.score_drop_e1 = kbool(val);
    else if (key == "SCORE_DROP_THRESHOLD_E1") p.score_drop_thr_e1 = I();
    else if (key == "ENABLE_SCORE_DROP_EXIT_E2") p.score_drop_e2 = kbool(val);
    else if (key == "SCORE_DROP_THRESHOLD_E2") p.score_drop_thr_e2 = I();
    else if (key == "ENABLE_SCORE_DROP_EXIT_E4") p.score_drop_e4 = kbool(val);
    else if (key == "SCORE_DROP_THRESHOLD_E4") p.score_drop_thr_e4 = I();
    else if (key == "SCORE_DROP_CONSECUTIVE_CHECKS") p.score_drop_consec = I();
    // E1
    else if (key == "E1_HTF_TREND_FILTER") p.e1_htf_filter = H();
    else if (key == "E1_HTF_MIN_ADX") p.e1_htf_min_adx = D();
    else if (key == "E1_HTF_MIN_DI_SPREAD") p.e1_htf_min_di_spread = D();
    else if (key == "E1_MIN_MOMENTUM_ADX") p.e1_min_momentum_adx = D();
    else if (key == "E1_MAX_CROSS_AGE") p.e1_max_cross_age = I();
    else if (key == "E1_MOMENTUM_BYPASS_LEVEL") p.e1_momentum_bypass = I();
    else if (key == "E1_RR") p.e1_rr = D();
    else if (key == "E1_RR_SIDEWAY") p.e1_rr_sideway = D();
    else if (key == "E1_PARTIAL_TP_TRIGGER") p.e1_partial_tp_trigger = D();
    else if (key == "E1_PARTIAL_TP_RATIO") p.e1_partial_tp_ratio = D();
    else if (key == "E1_SL_TO_BREAKEVEN_BUFFER") p.e1_be_buffer = D();
    else if (key == "E1_TRAILING_SL_FACTOR") p.e1_trailing_factor = D();
    else if (key == "E1_MAX_TP_EXTENSIONS") p.e1_max_tp_ext = I();
    else if (key == "E1_ENABLE_LADDERED_EXTENSIONS") p.e1_ladder = kbool(val);
    else if (key == "E1_LADDER_STAGE1_MULTIPLIER") p.e1_ladder_s1_mult = D();
    else if (key == "E1_LADDER_STAGE2_MULTIPLIER") p.e1_ladder_s2_mult = D();
    else if (key == "E1_LADDER_STAGE3_MULTIPLIER") p.e1_ladder_s3_mult = D();
    else if (key == "E1_LADDER_STAGE1_TRAIL_RATIO") p.e1_ladder_s1_trail = D();
    else if (key == "E1_LADDER_STAGE2_TRAIL_RATIO") p.e1_ladder_s2_trail = D();
    else if (key == "E1_LADDER_STAGE3_TRAIL_RATIO") p.e1_ladder_s3_trail = D();
    // E2
    else if (key == "E2_MIN_MOMENTUM_ADX") p.e2_min_momentum_adx = D();
    else if (key == "E2_MAX_TOUCH_AGE") p.e2_max_touch_age = I();
    else if (key == "E2_HTF_TREND_FILTER") p.e2_htf_filter = H();
    else if (key == "E2_HTF_MIN_ADX") p.e2_htf_min_adx = D();
    else if (key == "E2_HTF_MIN_DI_SPREAD") p.e2_htf_min_di_spread = D();
    else if (key == "E2_RR") p.e2_rr = D();
    else if (key == "E2_RR_SIDEWAY") p.e2_rr_sideway = D();
    else if (key == "E2_PARTIAL_TP_TRIGGER") p.e2_partial_tp_trigger = D();
    else if (key == "E2_PARTIAL_TP_RATIO") p.e2_partial_tp_ratio = D();
    else if (key == "E2_SL_TO_BREAKEVEN_BUFFER") p.e2_be_buffer = D();
    else if (key == "E2_TRAILING_SL_FACTOR") p.e2_trailing_factor = D();
    else if (key == "E2_MAX_TP_EXTENSIONS") p.e2_max_tp_ext = I();
    else if (key == "E2_ENABLE_LADDERED_EXTENSIONS") p.e2_ladder = kbool(val);
    else if (key == "E2_LADDER_STAGE1_MULTIPLIER") p.e2_ladder_s1_mult = D();
    else if (key == "E2_LADDER_STAGE2_MULTIPLIER") p.e2_ladder_s2_mult = D();
    else if (key == "E2_LADDER_STAGE3_MULTIPLIER") p.e2_ladder_s3_mult = D();
    else if (key == "E2_LADDER_STAGE1_TRAIL_RATIO") p.e2_ladder_s1_trail = D();
    else if (key == "E2_LADDER_STAGE2_TRAIL_RATIO") p.e2_ladder_s2_trail = D();
    else if (key == "E2_LADDER_STAGE3_TRAIL_RATIO") p.e2_ladder_s3_trail = D();
    // E4
    else if (key == "E4_MAX_SIDEWAY_SCORE") p.e4_max_sideway_score = I();
    else if (key == "E4_REQUIRE_M5_DI_ALIGN") p.e4_require_m5_di_align = kbool(val);
    else if (key == "E4_HTF_TREND_FILTER") p.e4_htf_filter = H();
    else if (key == "E4_HTF_MIN_ADX") p.e4_htf_min_adx = D();
    else if (key == "E4_HTF_MIN_DI_SPREAD") p.e4_htf_min_di_spread = D();
    else if (key == "E4_MIN_MOMENTUM_ADX") p.e4_min_momentum_adx = D();
    else if (key == "E4_MIN_CLOUD_THICKNESS_ATR_MULT") p.e4_min_cloud_thick_atr = D();
    else if (key == "E4_REQUIRE_TENKAN_KIJUN_ALIGN") p.e4_require_tenkan_kijun = kbool(val);
    else if (key == "E4_REQUIRE_CHIKOU_CLEAR") p.e4_require_chikou_clear = kbool(val);
    else if (key == "E4_MOMENTUM_BYPASS_LEVEL") p.e4_momentum_bypass = I();
    else if (key == "E4_MAX_CROSS_AGE") p.e4_max_cross_age = I();
    else if (key == "E4_RR") p.e4_rr = D();
    else if (key == "E4_RR_SHORT") p.e4_rr_short = D();
    else if (key == "E4_RR_SIDEWAY") p.e4_rr_sideway = D();
    else if (key == "E4_PARTIAL_TP_TRIGGER") p.e4_partial_tp_trigger = D();
    else if (key == "E4_PARTIAL_TP_RATIO") p.e4_partial_tp_ratio = D();
    else if (key == "E4_SL_TO_BREAKEVEN_BUFFER") p.e4_be_buffer = D();
    else if (key == "E4_TRAILING_SL_FACTOR") p.e4_trailing_factor = D();
    else if (key == "E4_MAX_TP_EXTENSIONS") p.e4_max_tp_ext = I();
    else if (key == "E4_ENABLE_LADDERED_EXTENSIONS") p.e4_ladder = kbool(val);
    else if (key == "E4_LADDER_STAGE1_MULTIPLIER") p.e4_ladder_s1_mult = D();
    else if (key == "E4_LADDER_STAGE2_MULTIPLIER") p.e4_ladder_s2_mult = D();
    else if (key == "E4_LADDER_STAGE3_MULTIPLIER") p.e4_ladder_s3_mult = D();
    else if (key == "E4_LADDER_STAGE1_TRAIL_RATIO") p.e4_ladder_s1_trail = D();
    else if (key == "E4_LADDER_STAGE2_TRAIL_RATIO") p.e4_ladder_s2_trail = D();
    else if (key == "E4_LADDER_STAGE3_TRAIL_RATIO") p.e4_ladder_s3_trail = D();
    // ichimoku
    else if (key == "ICHIMOKU_TENKAN") p.ichimoku_tenkan = I();
    else if (key == "ICHIMOKU_KIJUN") p.ichimoku_kijun = I();
    else if (key == "ICHIMOKU_SENKOU") p.ichimoku_senkou = I();
    // ema / rsi / adx periods
    else if (key == "INPUT_EMA0_PERIOD") p.ema0_period = I();
    else if (key == "INPUT_EMA1_PERIOD") p.ema1_period = I();
    else if (key == "INPUT_EMA2_PERIOD") p.ema2_period = I();
    else if (key == "INPUT_EMA3_PERIOD") p.ema3_period = I();
    else if (key == "INPUT_EMA4_PERIOD") p.ema4_period = I();
    else if (key == "RSI_LEN") p.rsi_len = I();
    else if (key == "ADX_LEN") p.adx_len = I();
    // sessions
    else if (key == "JAPAN_START") p.japan_start = I();
    else if (key == "JAPAN_END") p.japan_end = I();
    else if (key == "LONDON_START") p.london_start = I();
    else if (key == "LONDON_END") p.london_end = I();
    else if (key == "NY_START") p.ny_start = I();
    else if (key == "NY_END") p.ny_end = I();
    else if (key == "IGNORE_VALID_SESSIONS") p.ignore_valid_sessions = kbool(val);
    else if (key == "SERVER_GMT_OFFSET") p.server_gmt_offset = I();
    else if (key == "JAPAN_SESSION_START") p.japan_start = I();
    else if (key == "JAPAN_SESSION_END") p.japan_end = I();
    else if (key == "LONDON_SESSION_START") p.london_start = I();
    else if (key == "LONDON_SESSION_END") p.london_end = I();
    else if (key == "NEWYORK_SESSION_START") p.ny_start = I();
    else if (key == "NEWYORK_SESSION_END") p.ny_end = I();
    // ---- shared ProfitManager toggles ----
    else if (key == "PM_BE_PROTECT") p.pm.be_protect = kbool(val);
    else if (key == "PM_BE_TRIGGER_R") p.pm.be_trigger_r = D();
    else if (key == "PM_BE_BUFFER_R") p.pm.be_buffer_r = D();
    else if (key == "PM_PROG_TRAIL") p.pm.prog_trail = kbool(val);
    else if (key == "PM_PROG_TRIGGER_R") p.pm.prog_trigger_r = D();
    else if (key == "PM_PROG_INCREMENT_R") p.pm.prog_increment_r = D();
    else if (key == "PM_PROG_STEP_R") p.pm.prog_step_r = D();
    else if (key == "PM_GIVEBACK") p.pm.giveback = kbool(val);
    else if (key == "PM_GIVEBACK_ARM_R") p.pm.giveback_arm_r = D();
    else if (key == "PM_GIVEBACK_CAP_FRAC") p.pm.giveback_cap_frac = D();
    else if (key == "PM_TP_EXTENSION") p.pm.tp_extension = kbool(val);
    else if (key == "PM_TP_EXT_PROGRESS") p.pm.tp_ext_progress = D();
    else if (key == "PM_TP_EXT_ATR_MULT") p.pm.tp_ext_atr_mult = D();
    else if (key == "PM_TP_EXT_MAX") p.pm.tp_ext_max = I();
    else if (key == "PM_PRE_BE_STRUCTURE") p.pm.pre_be_structure = kbool(val);
    else if (key == "PM_PRE_BE_TRIGGER_R") p.pm.pre_be_trigger_r = D();
    else if (key == "PM_PRE_BE_BUFFER") p.pm.pre_be_buffer = D();
    else if (key == "PM_PARTIAL_TP") p.pm.partial_tp = kbool(val);
    else if (key == "PM_PARTIAL_TRIGGER_R") p.pm.partial_trigger_r = D();
    else if (key == "PM_PARTIAL_FRAC") p.pm.partial_frac = D();
    // =====================================================================================
    // DEPLOY-VEHICLE SCHEMA (Inp*) — the KK-KenKem EA exposes a DIFFERENT key set than the original
    // KenKemExpert (KK-Common/KenKem/Inputs.mqh). Accepting it here lets ONE .set drive BOTH the engine
    // and the EA — the precondition for any meaningful parity_diff (ledger G1). The KK-KenKem EA un-locks
    // ADX/RSI/EMA periods (genuine inputs), so these are honored here (the lock still guards the ORIGINAL
    // names). MT5 .set lines look like `InpE1Rr=1.9||1.9||..||N`; std::stod/stoi stop at the first `|`.
    else if (key == "InpRiskPerTrade") {           // EA sizes every entry off ONE risk fraction
        p.common_max_risk = p.max_loss_ratio_e1 = p.max_loss_ratio_e2
            = p.max_loss_ratio_e4 = p.max_loss_ratio_e5 = D();
    }
    else if (key == "InpMaxConcurrent") p.max_concurrent_pos = I();
    else if (key == "InpBlockOpposite") p.block_opposite_dir = kbool(val);
    // shared gates / SL
    else if (key == "InpMinMomentumAdx") p.min_momentum_adx = D();
    else if (key == "InpAdxHighThreshold") p.adx_high_threshold = D();
    else if (key == "InpSidewaysBlock") p.sideways_block_thr = I();
    else if (key == "InpSidewaysWarn") p.sideways_warning_thr = I();
    else if (key == "InpSlEmaDistance") p.sl_ema_distance = I();
    else if (key == "InpRangeLookback") p.range_hilo_lookback = I();
    else if (key == "InpEmaAlignTolPips") p.ema_align_tol_pips = D();
    // E1
    else if (key == "InpE1On") p.enable_e1 = kbool(val);
    else if (key == "InpE1Rr") p.e1_rr = D();
    else if (key == "InpE1MaxAge") p.e1_max_cross_age = I();
    else if (key == "InpE1HtfMode") p.e1_htf_filter = H();
    else if (key == "InpE1HtfMinAdx") p.e1_htf_min_adx = D();
    else if (key == "InpE1HtfMinDi") p.e1_htf_min_di_spread = D();
    else if (key == "InpE1AtrSlCap") p.e1_atr_sl_cap = D();
    else if (key == "InpE1AtrSlFloor") p.e1_atr_sl_floor = D();
    else if (key == "InpE1PartTrig") p.e1_partial_tp_trigger = D();
    else if (key == "InpE1PartRatio") p.e1_partial_tp_ratio = D();
    else if (key == "InpE1Be") p.e1_be_buffer = D();
    else if (key == "InpE1Trail") p.e1_trailing_factor = D();
    // E2
    else if (key == "InpE2On") p.enable_e2 = kbool(val);
    else if (key == "InpE2Rr") p.e2_rr = D();
    else if (key == "InpE2MaxAge") p.e2_max_touch_age = I();
    else if (key == "InpE2HtfMode") p.e2_htf_filter = H();
    else if (key == "InpE2HtfMinAdx") p.e2_htf_min_adx = D();
    else if (key == "InpE2HtfMinDi") p.e2_htf_min_di_spread = D();
    else if (key == "InpE2AtrSlCap") p.e2_atr_sl_cap = D();
    else if (key == "InpE2AtrSlFloor") p.e2_atr_sl_floor = D();
    else if (key == "InpE2PartTrig") p.e2_partial_tp_trigger = D();
    else if (key == "InpE2PartRatio") p.e2_partial_tp_ratio = D();
    else if (key == "InpE2Be") p.e2_be_buffer = D();
    else if (key == "InpE2Trail") p.e2_trailing_factor = D();
    // E4
    else if (key == "InpE4On") p.enable_e4 = kbool(val);
    else if (key == "InpE4Rr") p.e4_rr = D();
    else if (key == "InpE4RrShort") p.e4_rr_short = D();
    else if (key == "InpE4MaxAge") p.e4_max_cross_age = I();
    else if (key == "InpE4HtfMode") p.e4_htf_filter = H();
    else if (key == "InpE4HtfMinAdx") p.e4_htf_min_adx = D();
    else if (key == "InpE4HtfMinDi") p.e4_htf_min_di_spread = D();
    else if (key == "InpE4MinMomAdx") p.e4_min_momentum_adx = D();
    else if (key == "InpE4MinCloudThickAtr") p.e4_min_cloud_thick_atr = D();
    else if (key == "InpE4ReqCloud") p.e4_require_tenkan_kijun = kbool(val);
    else if (key == "InpE4AtrSlCap") p.e4_atr_sl_cap = D();
    else if (key == "InpE4AtrSlFloor") p.e4_atr_sl_floor = D();
    else if (key == "InpE4PartTrig") p.e4_partial_tp_trigger = D();
    else if (key == "InpE4PartRatio") p.e4_partial_tp_ratio = D();
    else if (key == "InpE4Be") p.e4_be_buffer = D();
    else if (key == "InpE4Trail") p.e4_trailing_factor = D();
    // E5
    else if (key == "InpE5On") p.enable_e5 = kbool(val);
    else if (key == "InpE5Rr") p.e5_rr = D();
    else if (key == "InpE5MaxAge") p.e5_max_ema_cross_age = I();
    else if (key == "InpE5HtfMode") p.e5_htf_filter = H();
    else if (key == "InpE5HtfMinAdx") p.e5_htf_min_adx = D();
    else if (key == "InpE5HtfMinDi") p.e5_htf_min_di_spread = D();
    else if (key == "InpE5MinMomAdx") p.e5_min_momentum_adx = D();
    else if (key == "InpE5AtrSlCap") p.e5_atr_sl_cap = D();
    else if (key == "InpE5AtrSlFloor") p.e5_atr_sl_floor = D();
    else if (key == "InpE5PartTrig") p.e5_partial_tp_trigger = D();
    else if (key == "InpE5PartRatio") p.e5_partial_tp_ratio = D();
    else if (key == "InpE5Be") p.e5_be_buffer = D();
    else if (key == "InpE5Trail") p.e5_trailing_factor = D();
    // periods / misc — KK-KenKem un-locks these (genuine inputs), so honor them here
    else if (key == "InpEma0") p.ema0_period = I();
    else if (key == "InpEma1") p.ema1_period = I();
    else if (key == "InpEma2") p.ema2_period = I();
    else if (key == "InpEma3") p.ema3_period = I();
    else if (key == "InpEma4") p.ema4_period = I();
    else if (key == "InpAdxLen") p.adx_len = I();
    else if (key == "InpRsiLen") p.rsi_len = I();
    else if (key == "InpAtrLen") p.atr_period_for_sl = I();
    else if (key == "InpIchiTenkan") p.ichimoku_tenkan = I();
    else if (key == "InpIchiKijun") p.ichimoku_kijun = I();
    else if (key == "InpIchiSenkou") p.ichimoku_senkou = I();
    else if (key == "InpRrSidewayAll") {           // EA uses ONE sideway RR for every entry
        p.e1_rr_sideway = p.e2_rr_sideway = p.e4_rr_sideway = p.e5_rr_sideway = D();
    }
    // session filter (ledger A1/B2) — InpUseSessionFilter OFF => engine trades 24h (ignore sessions)
    else if (key == "InpUseSessionFilter") p.ignore_valid_sessions = !kbool(val);
    else if (key == "InpSessionGmtOffset") p.server_gmt_offset = I();
    else if (key == "InpJapanStart") p.japan_start = I();
    else if (key == "InpJapanEnd") p.japan_end = I();
    else if (key == "InpLondonStart") p.london_start = I();
    else if (key == "InpLondonEnd") p.london_end = I();
    else if (key == "InpNyStart") p.ny_start = I();
    else if (key == "InpNyEnd") p.ny_end = I();
    else if (key == "InpCloseAtSessionEnd") p.close_at_session_end = kbool(val);
    else return false;
    return true;
}

// Decode raw .set bytes to an ASCII string. MetaTrader EXPORTS .set files as UTF-16 LE with a BOM and
// CRLF line endings; reading those as bytes mangles every key (interleaved NULs) -> 0 keys applied -> the
// engine silently runs on struct DEFAULTS instead of the deploy config. That made any "parity" diff
// compare engine-defaults vs EA-config — a silent, severe trap. We detect the BOM and fold UTF-16 (LE/BE)
// down to its ASCII bytes (set keys/values are all ASCII), and also strip a UTF-8 BOM. CRLF handled below.
inline std::string decode_set_bytes(const std::string& raw) {
    if (raw.size() >= 2 && (unsigned char)raw[0] == 0xFF && (unsigned char)raw[1] == 0xFE) {  // UTF-16 LE
        std::string out;
        for (size_t i = 2; i + 1 < raw.size(); i += 2)
            if (raw[i + 1] == 0) out.push_back(raw[i]);   // ASCII low byte, high byte 0
        return out;
    }
    if (raw.size() >= 2 && (unsigned char)raw[0] == 0xFE && (unsigned char)raw[1] == 0xFF) {  // UTF-16 BE
        std::string out;
        for (size_t i = 2; i + 1 < raw.size(); i += 2)
            if (raw[i] == 0) out.push_back(raw[i + 1]);
        return out;
    }
    if (raw.size() >= 3 && (unsigned char)raw[0] == 0xEF && (unsigned char)raw[1] == 0xBB
        && (unsigned char)raw[2] == 0xBF)                                                     // UTF-8 BOM
        return raw.substr(3);
    return raw;
}

// Load a .set into p. Returns # keys applied (-1 if file missing). Accepts ASCII/UTF-8/UTF-16 .set files
// (MT5 exports UTF-16) and both LF and CRLF line endings.
inline int load_set(KenKemConfig& p, const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return -1;
    std::string raw((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    const std::string text = decode_set_bytes(raw);
    int applied = 0;
    size_t start = 0;
    while (start <= text.size()) {
        size_t nl = text.find('\n', start);
        std::string line = text.substr(start, nl == std::string::npos ? std::string::npos : nl - start);
        start = (nl == std::string::npos) ? text.size() + 1 : nl + 1;
        auto semic = line.find(';');
        if (semic != std::string::npos) line = line.substr(0, semic);
        line = detail::ktrim(line);   // ktrim also strips a trailing '\r' (CRLF)
        if (line.empty()) continue;
        auto eq = line.find('=');
        if (eq == std::string::npos) continue;
        if (apply_kv(p, detail::ktrim(line.substr(0, eq)), detail::ktrim(line.substr(eq + 1)))) applied++;
    }
    return applied;
}

}  // namespace kk::kenkem
