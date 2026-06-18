//+------------------------------------------------------------------+
//|  KenKem/Inputs.mqh — input schema for the distilled KenKem family |
//|  Defaults = PROMOTED production best_kenkem_btc.set (E5 ONLY).     |
//|  Load KK-KenKem-E5-XAUUSD.set for the gold config. Include BEFORE  |
//|  Engine.mqh. Engine stays multi-entry; flip InpExOn to re-enable.  |
//+------------------------------------------------------------------+
#ifndef KENKEM_INPUTS_MQH
#define KENKEM_INPUTS_MQH

input group "===== Risk / portfolio ====="
input double InpRiskPerTrade      = 0.02;     // fraction of balance risked per trade
input double InpRiskBaseBalance   = 0.0;      // 0 = live balance (compounding); >0 = fixed base
input int    InpMaxConcurrent     = 2;        // max simultaneous positions
input bool   InpBlockOpposite     = true;     // block entries opposing an open position
input double InpMaxSpreadPrice    = 0.0;      // skip entry if spread > this (0 = off)

input group "===== Shared gates / SL ====="
input double InpMinMomentumAdx    = 13.9663;  // MIN_MOMENTUM_ADX (M1 ADX, 1pt)
input double InpAdxHighThreshold  = 31.5565;  // ADX_HIGH (M1 ADX, 2pt)
input int    InpSidewaysBlock     = 48;       // SIDEWAYS_BLOCK_THRESHOLD
input int    InpSidewaysWarn      = 33;       // SIDEWAYS_WARNING (sideway-RR band)
input int    InpSlEmaDistance     = 15;       // SL_EMA_DISTANCE (pips)
input int    InpRangeLookback     = 18;       // RANGE_HI_LOW_LOOK_BACK_BARS
input double InpEmaAlignTolPips    = 23.0;    // EMA_ALIGNMENT_TOLERANCE_PIPS

input group "===== E1  EMA-stack cross ====="
input bool   InpE1On=false; input double InpE1Rr=1.90; input int InpE1MaxAge=45;
input int    InpE1HtfMode=1; input double InpE1HtfMinAdx=22.4; input double InpE1HtfMinDi=4.0;
input double InpE1AtrSlCap=2.69; input double InpE1AtrSlFloor=1.2;
input double InpE1PartTrig=0.61; input double InpE1PartRatio=0.20; input double InpE1Be=0.07; input double InpE1Trail=0.476;

input group "===== E2  EMA75 pullback ====="
input bool   InpE2On=false; input double InpE2Rr=1.44; input int InpE2MaxAge=58;
input int    InpE2HtfMode=3; input double InpE2HtfMinAdx=18.2; input double InpE2HtfMinDi=3.0;
input double InpE2AtrSlCap=2.01; input double InpE2AtrSlFloor=1.1;
input double InpE2PartTrig=0.91; input double InpE2PartRatio=0.25; input double InpE2Be=0.07; input double InpE2Trail=0.344;

input group "===== E4  Ichimoku TK cross ====="
input bool   InpE4On=false; input double InpE4Rr=1.98; input double InpE4RrShort=2.03; input int InpE4MaxAge=38;
input int    InpE4HtfMode=4; input double InpE4HtfMinAdx=18.1; input double InpE4HtfMinDi=6.0;
input double InpE4MinMomAdx=19.75; input double InpE4MinCloudThickAtr=0.11; input bool InpE4ReqCloud=true;
input double InpE4AtrSlCap=2.06; input double InpE4AtrSlFloor=1.25;
input double InpE4PartTrig=0.53; input double InpE4PartRatio=0.20; input double InpE4Be=0.07; input double InpE4Trail=0.267;

input group "===== E5  SuperBros M1 alignment (PROMOTED, BTC-tuned) ====="
input bool   InpE5On=true;  input double InpE5Rr=1.2241; input int InpE5MaxAge=33;
input int    InpE5HtfMode=1; input double InpE5HtfMinAdx=12.9691; input double InpE5HtfMinDi=4.0; input double InpE5MinMomAdx=0.2788;
input double InpE5AtrSlCap=1.5267; input double InpE5AtrSlFloor=1.2;
input double InpE5PartTrig=0.2115; input double InpE5PartRatio=0.4239; input double InpE5Be=0.0642; input double InpE5Trail=0.2712;

input group "===== Periods / misc (BTC-tuned) ====="
input int    InpEma0=12, InpEma1=23, InpEma2=53, InpEma3=94, InpEma4=210;
input int    InpAdxLen=15, InpRsiLen=11, InpAtrLen=14;
input int    InpIchiTenkan=9, InpIchiKijun=26, InpIchiSenkou=52;
input double InpRrSidewayAll       = 1.4642;  // RR used when sideways in [warn,block)
input ulong  InpMagic              = 4242410;

#endif // KENKEM_INPUTS_MQH
