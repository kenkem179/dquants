//+------------------------------------------------------------------+
//|  KK-Monster.mq5 — VP-family Monster (breakout / 2x reversion /     |
//|  impulse) with node-flow + master-POC regime + multi-TF near-net. |
//|  THIN SHELL. Logic in KK-Monster/{Config,Signal,Engine}.mqh +      |
//|  KK-Common/. Faithful transcription of cpp_core kk::monster.       |
//|  Attach to the entry TF (M3). Params: best_monster_{btc,xau}.set.  |
//+------------------------------------------------------------------+
#property copyright "KenKem / dquants"
#property version   "1.00"
#property strict

#include "Config.mqh"
#include "Signal.mqh"
#include "Engine.mqh"
//+------------------------------------------------------------------+
