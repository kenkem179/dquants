//+------------------------------------------------------------------+
//|  KenKem/State.mqh — shared globals + the decision-time Snapshot.  |
//|  One translation unit (textual includes); all family modules read |
//|  these. Include AFTER <Trade/Trade.mqh>.                          |
//+------------------------------------------------------------------+
#ifndef KENKEM_STATE_MQH
#define KENKEM_STATE_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        trade;
CPositionInfo posinfo;

ENUM_TIMEFRAMES KK_TF[4] = { PERIOD_M1, PERIOD_M3, PERIOD_M5, PERIOD_M15 };
int    hEma[4][5], hAdx[4], hAtrM1, hRsiM1;
int    hIchiM1=INVALID_HANDLE, hIchiM3=INVALID_HANDLE;
double g_pip=1.0, g_vppl=1.0;
datetime g_lastBarTime=0;

// Per-entry trigger state: bar OPEN time of last fire; 0 = inactive.
datetime gE1Up=0,gE1Dn=0, gE2Up=0,gE2Dn=0, gE4Up=0,gE4Dn=0, gE5Up=0,gE5Dn=0;

// Decision-time indicator snapshot (all reads at shift 1 = last closed bar).
struct Snap
{
   double adx[4],diP[4],diM[4];
   double emaM1[5];
   double atrM1,rsiM1;
   double tenkanM1,kijunM1;        // iIchimoku buffers 0/1 (the EA's "cloud" = TK lines)
   double senkouA_M3,senkouB_M3;   // iIchimoku buffers 2/3 (real Senkou cloud) on M3
   int    sideways;
   double atr_pctile;
   bool   valid;
};

#endif // KENKEM_STATE_MQH
