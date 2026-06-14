//+------------------------------------------------------------------+
//|  KK-MasterVP/Inputs.mqh — trading input schema (mirrors           |
//|  cpp_core kk::Params). Defaults = C++ struct defaults; load a      |
//|  validated .set to ship. Include BEFORE Strategy/Engine.          |
//+------------------------------------------------------------------+
#ifndef KKMVP_INPUTS_MQH
#define KKMVP_INPUTS_MQH

input group "===== VP core ====="
input int    InpVpLookback     = 50;
input int    InpVpBins         = 30;
input double InpVaPct          = 70.0;
input int    InpMasterMult     = 3;
input int    InpAtrLen         = 14;

input group "===== Node engine ====="
input double InpNodeTouchAtr   = 0.05;
input double InpNodeDecay      = 0.94;
input double InpNodeNeutralBand= 0.15;
input double InpNodeSaturation = 4.0;
input bool   InpNodeGateEnabled= true;
input bool   InpUsePriorBarVP  = false;
input bool   InpBrkRequireFlow = false;
input double InpSfpFlowMin     = 0.15;

input group "===== Regime ====="
input int    InpEmaFast        = 24;
input int    InpEmaSlow        = 194;
input int    InpAdxLen         = 14;
input double InpAdxTrendMin    = 22.0;
input double InpDiSpreadMin    = 6.0;
input double InpEmaSepAtr      = 0.25;

input group "===== Breakout ====="
input bool   InpEnableBreakout = true;
input double InpBreakBufAtr     = 0.65;
input double InpBreakMaxAtr      = 9.0;
input double InpRrBrk            = 1.4;
input double InpSlAtrBrk         = 2.2;
input bool   InpBrkVetoSfp       = false;

input group "===== Reversion ====="
input bool   InpEnableReversion = false;
input double InpRetestAtr        = 0.5;
input double InpBodyPctMin       = 0.4;
input double InpRrRev            = 1.35;
input double InpSlAtrRev         = 1.45;

input group "===== Exit ====="
input double InpTp1R            = 0.8;
input double InpTp1ClosePct     = 20.0;
input bool   InpBeAfterTp1      = true;
input double InpBeBufAtr        = 0.05;
input bool   InpTrailRunner     = true;
input double InpRunnerRr        = 10.0;
input double InpTrailAtrMult    = 3.6;

input group "===== Risk ====="
input double InpRiskAccPct      = 0.9;     // % of balance risked per trade
input double InpMaxLot          = 0.0;     // 0 = no cap
input int    InpDeviationPoints = 200;

input group "===== Misc ====="
input ulong  InpMVPMagic        = 5252510;
input double InpRrSidewayUnused = 1.0;     // (placeholder; no sideway-RR in MasterVP)

#endif // KKMVP_INPUTS_MQH
