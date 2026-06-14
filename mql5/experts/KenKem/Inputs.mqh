//+------------------------------------------------------------------+
//|  KenKem/Inputs.mqh — input schema for the distilled KenKem family |
//|  Defaults = validated best_kenkem_btc.set (E1+E4+E5; E2 off).     |
//|  Include BEFORE Engine.mqh.                                       |
//+------------------------------------------------------------------+
#ifndef KENKEM_INPUTS_MQH
#define KENKEM_INPUTS_MQH

input group "===== Risk / portfolio ====="
input double InpRiskPerTrade      = 0.0204;   // fraction of balance risked per trade
input double InpRiskBaseBalance   = 0.0;      // 0 = live balance (compounding); >0 = fixed base
input int    InpMaxConcurrent     = 2;        // max simultaneous positions
input bool   InpBlockOpposite     = true;     // block entries opposing an open position
input double InpMaxSpreadPrice    = 0.0;      // skip entry if spread > this (0 = off)

input group "===== Shared gates / SL ====="
input double InpMinMomentumAdx    = 20.62;    // MIN_MOMENTUM_ADX (M1 ADX, 1pt)
input double InpAdxHighThreshold  = 24.39;    // ADX_HIGH (M1 ADX, 2pt)
input int    InpSidewaysBlock     = 53;       // SIDEWAYS_BLOCK_THRESHOLD
input int    InpSidewaysWarn      = 43;       // SIDEWAYS_WARNING (sideway-RR band)
input int    InpSlEmaDistance     = 10;       // SL_EMA_DISTANCE (pips)
input int    InpRangeLookback     = 18;       // RANGE_HI_LOW_LOOK_BACK_BARS
input double InpEmaAlignTolPips    = 23.0;    // EMA_ALIGNMENT_TOLERANCE_PIPS

input group "===== E1  EMA-stack cross ====="
input bool   InpE1On=true;  input double InpE1Rr=1.90; input int InpE1MaxAge=45;
input int    InpE1HtfMode=1; input double InpE1HtfMinAdx=22.4; input double InpE1HtfMinDi=4.0;
input double InpE1AtrSlCap=2.69; input double InpE1AtrSlFloor=1.2;
input double InpE1PartTrig=0.61; input double InpE1PartRatio=0.20; input double InpE1Be=0.07; input double InpE1Trail=0.476;

input group "===== E2  EMA75 pullback ====="
input bool   InpE2On=false; input double InpE2Rr=1.44; input int InpE2MaxAge=58;
input int    InpE2HtfMode=3; input double InpE2HtfMinAdx=18.2; input double InpE2HtfMinDi=3.0;
input double InpE2AtrSlCap=2.01; input double InpE2AtrSlFloor=1.1;
input double InpE2PartTrig=0.91; input double InpE2PartRatio=0.25; input double InpE2Be=0.07; input double InpE2Trail=0.344;

input group "===== E4  Ichimoku TK cross ====="
input bool   InpE4On=true;  input double InpE4Rr=1.98; input double InpE4RrShort=2.03; input int InpE4MaxAge=38;
input int    InpE4HtfMode=4; input double InpE4HtfMinAdx=18.1; input double InpE4HtfMinDi=6.0;
input double InpE4MinMomAdx=19.75; input double InpE4MinCloudThickAtr=0.11; input bool InpE4ReqCloud=true;
input double InpE4AtrSlCap=2.06; input double InpE4AtrSlFloor=1.25;
input double InpE4PartTrig=0.53; input double InpE4PartRatio=0.20; input double InpE4Be=0.07; input double InpE4Trail=0.267;

input group "===== E5  SuperBros M1 alignment ====="
input bool   InpE5On=true;  input double InpE5Rr=1.25; input int InpE5MaxAge=21;
input int    InpE5HtfMode=1; input double InpE5HtfMinAdx=18.0; input double InpE5HtfMinDi=4.0; input double InpE5MinMomAdx=3.92;
input double InpE5AtrSlCap=4.0; input double InpE5AtrSlFloor=1.2;
input double InpE5PartTrig=0.54; input double InpE5PartRatio=0.50; input double InpE5Be=0.05; input double InpE5Trail=0.38;

input group "===== Periods / misc ====="
input int    InpEma0=10, InpEma1=25, InpEma2=71, InpEma3=97, InpEma4=192;
input int    InpAdxLen=14, InpRsiLen=14, InpAtrLen=14;
input int    InpIchiTenkan=9, InpIchiKijun=26, InpIchiSenkou=52;
input double InpRrSidewayAll       = 1.20;    // RR used when sideways in [warn,block)
input ulong  InpMagic              = 4242410;

#endif // KENKEM_INPUTS_MQH
