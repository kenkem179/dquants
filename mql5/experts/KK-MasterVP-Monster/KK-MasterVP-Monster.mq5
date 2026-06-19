//+------------------------------------------------------------------+
//|  KK-MasterVP-Monster.mq5 — VP breakout + impulse-thrust (Monster). |
//|  THIN SHELL. INHERITS the KK-MasterVP engine + the impulse delta:  |
//|  a thrust candle that fires ABOVE the vol ceiling, confirmed by M1 |
//|  near-price net tick volume, trend-gated on the master-POC slope + |
//|  predicted (aged-out) master VP. 1:1 with cpp_core kk::mastervp +  |
//|  kk::detect_impulse. Attach to the entry TF (BTCUSD M3; M5 variant  |
//|  shipped separately). Defaults = the LOCKED BTCUSD-M3 preset.       |
//+------------------------------------------------------------------+
#property copyright "KenKem / dquants"
#property version   "1.00"
#property strict

#include "Inputs.mqh"
#include "Engine.mqh"
//+------------------------------------------------------------------+
