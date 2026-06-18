//+------------------------------------------------------------------+
//|  KK-MasterVP.mq5 — Volume-Profile breakout/reversion (VP family). |
//|  THIN SHELL. Logic in VP-Common/ (VP, regime, node engine) +      |
//|  KK-MasterVP/ (Inputs, Strategy, Engine) + KK-Common/ generics.    |
//|  Faithful transcription of cpp_core kk::mastervp (source of truth).|
//|  Attach to the entry TF (M1 or M3 — never M5).                    |
//+------------------------------------------------------------------+
#property copyright "KenKem / dquants"
#property version   "1.00"
#property strict

#include "Inputs.mqh"
#include "Engine.mqh"
//+------------------------------------------------------------------+
