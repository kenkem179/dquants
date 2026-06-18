//+------------------------------------------------------------------+
//|  KK-KenKem.mq5 — distilled KenKem, multi-entry (E1/E2/E4/E5).     |
//|  THIN SHELL. All logic lives in the dquants Layer-4 library:      |
//|    experts/KenKem/  (family) + experts/KK-Common/ (shared).       |
//|  Faithful transcription of the validated kk::kenkem C++ engine    |
//|  (single source of truth). Each entry toggleable; off-entries     |
//|  create zero indicator handles. Attach to M1.                     |
//|                                                                  |
//|  Validated 2026 true-OOS: BTC E1+E4+E5 PF 1.145 (E4-only 1.239);  |
//|  XAU E4+E5 PF 1.132. See research/optimization/KENKEM-RESULTS.md. |
//+------------------------------------------------------------------+
#property copyright "KenKem / dquants"
#property version   "1.10"
#property strict

#include "../KenKem/Inputs.mqh"
#include "../KenKem/Engine.mqh"
//+------------------------------------------------------------------+
