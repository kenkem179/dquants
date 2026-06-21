//+------------------------------------------------------------------+
//|  KK-KenKem.mq5 — clean, faithful rewrite of the original          |
//|  KenKemExpert (../kenkem v1.8.154) for entries E1 + E2 + E5.      |
//|  E4 excluded (confirmed MT5 net-loser). Source of truth =          |
//|  KenKemExpert's own MQL5 (transcribe; do NOT port the C++ engine). |
//|                                                                    |
//|  Pruned vs the original: Alerts/Discord/Telegram, adaptive-        |
//|  learning/coordinate-descent, StatePersistence, E3/E4, CSV export. |
//|  Kept faithful: indicator/state machinery, E1/E2/E5 entries, the   |
//|  full exit engine (it carries the edge).                           |
//|                                                                    |
//|  Inputs use KenKemExpert's verbatim ALL_CAPS names so the          |
//|  MT5-confirmed D-series .set files (research/kenkem_parity/) load  |
//|  directly → parity = same-.set MT5 diff. Attach to XAUUSD M1.      |
//|                                                                    |
//|  Build plan: docs/BUILD-PLAN-KENKEM-REWRITE.md                     |
//+------------------------------------------------------------------+
#property copyright "KenKem / dquants"
#property version   "1.0"
#property strict
#property description "KK-KenKem — faithful E1/E2/E5 rewrite of KenKemExpert (P1 foundation, pre-release)"

#define VERSION "KK-KenKem 1.0-dev"

#include "Inputs.mqh"

//+------------------------------------------------------------------+
//| P1 FOUNDATION — compiles green, no trades yet.                    |
//| State / Indicators / Snapshot modules are wired in incrementally; |
//| OnTick stays inert until P2 (E1+E2 entries).                      |
//+------------------------------------------------------------------+
int OnInit()
{
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   // No trading logic yet — P1 is the input + indicator/state scaffold only.
}

void OnDeinit(const int reason)
{
}
//+------------------------------------------------------------------+
