//+------------------------------------------------------------------+
//|  KK-MasterVP-Debug.mq5 - INTERNAL / SWEEP build (NOT for release).|
//|  Identical engine + identical compiled-in defaults as the curated |
//|  KK-MasterVP.mq5, but it #defines KK_DEBUG_EXPOSE_ALL first so the |
//|  KK_IN macro in Inputs.mqh flips every hidden strategy global into |
//|  a visible `input`. Result: the FULL param surface is sweepable in |
//|  the MT5 Strategy-Tester optimizer (laddered/partial TP, profit-   |
//|  lock ladder, VP length, regime, SL/RR, etc.) while the shipped    |
//|  KK-MasterVP.mq5 / marketplace build stays curated and unchanged.  |
//|                                                                    |
//|  USE: optimizer/research only. NEVER ship this. Account-lock and   |
//|  expiry globals are intentionally NOT exposed (not KK_IN).         |
//|  Same magic + defaults => loading a lock .set reproduces the lock. |
//+------------------------------------------------------------------+
#property copyright "KenKem / dquants"
#property version   "1.06"
#property strict
#property description "KK-MasterVP INTERNAL sweep build - all params exposed for the MT5 optimizer."
#property description "Not for distribution. Behaviour-identical to KK-MasterVP at default inputs."

#define KK_DEBUG_EXPOSE_ALL
#include "Inputs.mqh"
#include "Engine.mqh"
//+------------------------------------------------------------------+
