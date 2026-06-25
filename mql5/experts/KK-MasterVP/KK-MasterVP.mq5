//+------------------------------------------------------------------+
//|  KK-MasterVP.mq5 - Volume-Profile breakout/reversion (VP family). |
//|  THIN SHELL. Logic in VP-Common/ (VP, regime, node engine) +      |
//|  KK-MasterVP/ (Inputs, Strategy, Engine) + KK-Common/ generics.    |
//|  Faithful transcription of cpp_core kk::mastervp (source of truth).|
//|  Attach to the entry TF (M1 or M3 - never M5).                    |
//+------------------------------------------------------------------+
#property copyright "KenKem / dquants"
#property link      "https://kenkem.biz"
#property version   "1.06"
#property strict
#property description "KK-MasterVP - volume-profile breakout expert for XAUUSD & BTCUSD."
#property description "Trades confirmed breaks of the master value area with ATR-based"
#property description "stops, break-even and trailing management, plus a daily/overall"
#property description "drawdown guard for prop-firm rules."
#property description "Educational tool only - not financial advice. Trading carries risk."
#property description "For more details, visit https://kenkem.biz"

#include "Inputs.mqh"
#include "Engine.mqh"
//+------------------------------------------------------------------+
