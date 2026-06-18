//+------------------------------------------------------------------+
//|  KK-Monster/Config.mqh — MonsterConfig struct (mirrors cpp_core    |
//|  kk::monster::MonsterConfig) + inputs + populate. The signal/engine|
//|  take `const MonsterConfig&` so the C++ logic ports near-verbatim. |
//+------------------------------------------------------------------+
#ifndef KKM_CONFIG_MQH
#define KKM_CONFIG_MQH

struct MonsterConfig
{
   // execution / risk
   double max_spread_pips; double risk_acc_pct; double be_buf_atr; bool trail_runner;
   double runner_rr; double trail_atr_mult; double min_atr_pct; double max_atr_pct;
   double max_lot; int deviation_points;
   // VP / node
   int vp_lookback; int vp_bins; double va_pct; int master_mult;
   double node_touch_atr; double node_decay; double node_neutral_band; double node_saturation; int atr_len;
   // net
   bool use_weighted_net; int tf_net_look; double net_win_atr; double w_hvn; double w_mvn; double w_lvn;
   bool net_confirm_m1_or_m3; bool net_confirm_m5;
   // tp1
   double tp1_rr_brk; double tp1_rr_rev;
   // breakout
   bool enable_breakout; int brk_fresh_bars; double brk_local_tol_atr; double brk_entry_buf_atr;
   double brk_max_dist_atr; double brk_net_min; double brk_net_min_m3; double brk_opp_max;
   double brk_sl_buf_atr; double brk_sl_atr_mult; double brk_rr_far; double brk_rr_near; int brk_rr_lookback_bars;
   bool brk_overhead_veto; double brk_proj_atr; int brk_overhead_look; double brk_overhead_hvn_pct; double brk_overhead_net_max;
   // impulse
   bool enable_impulse; double impulse_candle_atr; double impulse_entry_buf_atr; double impulse_net_min;
   double impulse_max_dist_atr; double impulse_rr; int impulse_trend_slope_bars; int impulse_predict_bars;
   // regime / poc stability
   bool enable_regime_gate; double regime_tau_high; double regime_tau_low;
   double poc_stable_max_atr; bool brk_require_poc_stable; bool rev_require_poc_stable;
   // reversion
   bool enable_reversion; int rev_fresh_bars; double rev_entry_dist_atr; double rev_max_dist_atr;
   double rev_net_min; double rev_opp_max; double rev_sl_buf_atr; double rev_sl_atr_mult; double rev_min_rr;
   double rev_anchor_off_atr; double rev_poc_sl_off_atr;
   // htf bias
   bool enable_htf_bias; double htf_bias_min; bool htf_require_align;
   // edge candidates (default off)
   bool enable_hvn_shelf_sl; double shelf_near_atr; double shelf_far_atr; double shelf_buf_atr;
   bool enable_structural_tp2; double stp2_hvn_frac; double stp2_edge_off_atr; double stp2_min_rr; double stp2_max_rr;
   // failed-break exit
   bool enable_failed_break_exit; int fail_break_bars; double fail_break_net_flip; double fail_break_r_gate;
   // symbol
   double pip_size; double mintick;
   int master_len() const { return vp_lookback*master_mult; }
};

input group "===== Monster: enables ====="
input bool   InpEnableBreakout  = true;
input bool   InpEnableImpulse   = true;
input bool   InpEnableReversion = false;
input bool   InpEnableRegimeGate= false;
input bool   InpEnableHtfBias   = false;
input group "===== Risk ====="
input double InpRiskAccPct      = 1.6;
input double InpMaxLot          = 0.0;
input int    InpDeviationPoints = 200;
input double InpMinAtrPct       = 0.04;
input double InpMaxAtrPct       = 0.2;
input group "===== VP / node ====="
input int    InpVpLookback      = 50;
input int    InpVpBins          = 40;
input double InpVaPct           = 70.0;
input int    InpMasterMult      = 3;
input double InpNodeTouchAtr    = 0.05;
input double InpNodeDecay       = 0.94;
input int    InpAtrLen          = 14;
input group "===== Net ====="
input bool   InpUseWeightedNet  = true;
input int    InpTfNetLook       = 50;
input double InpNetWinAtr       = 1.5;
input double InpWHvn=1.5, InpWMvn=1.0, InpWLvn=0.5;
input bool   InpNetConfirmM1orM3= false;
input bool   InpNetConfirmM5    = true;
input group "===== TP1 / breakout ====="
input double InpTp1RrBrk=1.05, InpTp1RrRev=1.0;
input int    InpBrkFreshBars    = 7;
input double InpBrkLocalTolAtr  = 0.1;
input double InpBrkEntryBufAtr  = 1.0;
input double InpBrkMaxDistAtr   = 1.8;
input double InpBrkNetMin       = 0.80;
input double InpBrkNetMinM3     = 0.80;
input double InpBrkOppMax       = 0.80;
input double InpBrkSlBufAtr     = 0.25;
input double InpBrkSlAtrMult    = 2.0;
input double InpBrkRrFar=3.0, InpBrkRrNear=2.0;
input int    InpBrkRrLookbackBars=25;
input group "===== Impulse ====="
input double InpImpulseCandleAtr= 1.7;
input double InpImpulseEntryBufAtr=0.4;
input double InpImpulseNetMin   = 0.95;
input double InpImpulseMaxDistAtr=2.5;
input double InpImpulseRr        = 3.0;
input int    InpImpulseTrendSlopeBars=10;
input int    InpImpulsePredictBars=10;
input group "===== Reversion ====="
input int    InpRevFreshBars    = 6;
input double InpRevEntryDistAtr = 1.0;
input double InpRevMaxDistAtr   = 2.0;
input double InpRevNetMin       = 0.80;
input double InpRevOppMax       = 0.80;
input double InpRevSlBufAtr     = 0.2;
input double InpRevSlAtrMult    = 2.0;
input double InpRevMinRr        = 1.5;
input double InpRevAnchorOffAtr = 0.06;
input double InpRevPocSlOffAtr  = 0.1;
input group "===== Regime / HTF / misc ====="
input double InpRegimeTauHigh=0.5, InpRegimeTauLow=0.25;
input double InpPocStableMaxAtr=0.2;
input double InpHtfBiasMin=0.5; input bool InpHtfRequireAlign=false;
input double InpBeBufAtr=0.05; input bool InpTrailRunner=false; input double InpRunnerRr=10.0; input double InpTrailAtrMult=3.6;
input ulong  InpMonMagic=6262610;

void FillMonsterConfig(MonsterConfig &c)
{
   c.max_spread_pips=0; c.risk_acc_pct=InpRiskAccPct; c.be_buf_atr=InpBeBufAtr; c.trail_runner=InpTrailRunner;
   c.runner_rr=InpRunnerRr; c.trail_atr_mult=InpTrailAtrMult; c.min_atr_pct=InpMinAtrPct; c.max_atr_pct=InpMaxAtrPct;
   c.max_lot=InpMaxLot; c.deviation_points=InpDeviationPoints;
   c.vp_lookback=InpVpLookback; c.vp_bins=InpVpBins; c.va_pct=InpVaPct; c.master_mult=InpMasterMult;
   c.node_touch_atr=InpNodeTouchAtr; c.node_decay=InpNodeDecay; c.node_neutral_band=0.15; c.node_saturation=4.0; c.atr_len=InpAtrLen;
   c.use_weighted_net=InpUseWeightedNet; c.tf_net_look=InpTfNetLook; c.net_win_atr=InpNetWinAtr;
   c.w_hvn=InpWHvn; c.w_mvn=InpWMvn; c.w_lvn=InpWLvn; c.net_confirm_m1_or_m3=InpNetConfirmM1orM3; c.net_confirm_m5=InpNetConfirmM5;
   c.tp1_rr_brk=InpTp1RrBrk; c.tp1_rr_rev=InpTp1RrRev;
   c.enable_breakout=InpEnableBreakout; c.brk_fresh_bars=InpBrkFreshBars; c.brk_local_tol_atr=InpBrkLocalTolAtr;
   c.brk_entry_buf_atr=InpBrkEntryBufAtr; c.brk_max_dist_atr=InpBrkMaxDistAtr; c.brk_net_min=InpBrkNetMin;
   c.brk_net_min_m3=InpBrkNetMinM3; c.brk_opp_max=InpBrkOppMax; c.brk_sl_buf_atr=InpBrkSlBufAtr; c.brk_sl_atr_mult=InpBrkSlAtrMult;
   c.brk_rr_far=InpBrkRrFar; c.brk_rr_near=InpBrkRrNear; c.brk_rr_lookback_bars=InpBrkRrLookbackBars;
   c.brk_overhead_veto=false; c.brk_proj_atr=1.5; c.brk_overhead_look=200; c.brk_overhead_hvn_pct=70.0; c.brk_overhead_net_max=0.5;
   c.enable_impulse=InpEnableImpulse; c.impulse_candle_atr=InpImpulseCandleAtr; c.impulse_entry_buf_atr=InpImpulseEntryBufAtr;
   c.impulse_net_min=InpImpulseNetMin; c.impulse_max_dist_atr=InpImpulseMaxDistAtr; c.impulse_rr=InpImpulseRr;
   c.impulse_trend_slope_bars=InpImpulseTrendSlopeBars; c.impulse_predict_bars=InpImpulsePredictBars;
   c.enable_regime_gate=InpEnableRegimeGate; c.regime_tau_high=InpRegimeTauHigh; c.regime_tau_low=InpRegimeTauLow;
   c.poc_stable_max_atr=InpPocStableMaxAtr; c.brk_require_poc_stable=false; c.rev_require_poc_stable=false;
   c.enable_reversion=InpEnableReversion; c.rev_fresh_bars=InpRevFreshBars; c.rev_entry_dist_atr=InpRevEntryDistAtr;
   c.rev_max_dist_atr=InpRevMaxDistAtr; c.rev_net_min=InpRevNetMin; c.rev_opp_max=InpRevOppMax; c.rev_sl_buf_atr=InpRevSlBufAtr;
   c.rev_sl_atr_mult=InpRevSlAtrMult; c.rev_min_rr=InpRevMinRr; c.rev_anchor_off_atr=InpRevAnchorOffAtr; c.rev_poc_sl_off_atr=InpRevPocSlOffAtr;
   c.enable_htf_bias=InpEnableHtfBias; c.htf_bias_min=InpHtfBiasMin; c.htf_require_align=InpHtfRequireAlign;
   c.enable_hvn_shelf_sl=false; c.shelf_near_atr=0.5; c.shelf_far_atr=2.5; c.shelf_buf_atr=0.25;
   c.enable_structural_tp2=false; c.stp2_hvn_frac=0.66; c.stp2_edge_off_atr=0.2; c.stp2_min_rr=1.2; c.stp2_max_rr=3.0;
   c.enable_failed_break_exit=false; c.fail_break_bars=6; c.fail_break_net_flip=0.5; c.fail_break_r_gate=0.5;
   c.pip_size=0.01; c.mintick=0.01;
}

#endif // KKM_CONFIG_MQH
