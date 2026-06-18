//+------------------------------------------------------------------+
//|  KenKem/Entries/E2.mqh — EMA75 pullback touch.                   |
//|  Trigger: M1 bar straddles EMA75, direction by close vs EMA75.    |
//|  Gate: hard trend-quality (Engine) + M1/M3 align + M15 HTF.       |
//|  SL anchor: ema100.                                              |
//+------------------------------------------------------------------+
#ifndef KENKEM_E2_MQH
#define KENKEM_E2_MQH

#include "../State.mqh"
#include "../Gates.mqh"

void E2_UpdateTrigger(datetime now,double tol)
{
   double ema75=Ema(0,2,1), lo=iLow(_Symbol,PERIOD_M1,1), hi=iHigh(_Symbol,PERIOD_M1,1), cl=iClose(_Symbol,PERIOD_M1,1);
   if(lo<=ema75 && hi>=ema75){ if(cl>ema75){ gE2Up=now; gE2Dn=0; } else if(cl<ema75){ gE2Dn=now; gE2Up=0; } }
}

bool E2_Gate(const Snap &s,bool isLong)
{
   double tol=Tol();
   if(!EmasReady(0,1,isLong,true,tol)||!EmasReady(1,1,isLong,true,tol)) return false;
   return HtfOk(s,isLong,InpE2HtfMode,InpE2HtfMinAdx,InpE2HtfMinDi);
}

double E2_CustomLevel(bool isLong,const Snap &s){ return s.emaM1[3]; }
void   E2_AtrCaps(double &cap,double &flr){ cap=InpE2AtrSlCap; flr=InpE2AtrSlFloor; }
double E2_Rr(bool isLong,bool sw){ return sw?InpRrSidewayAll:(isLong?InpE2Rr:InpE2Rr*0.867); }
void   E2_Mgmt(double &trig,double &ratio,double &be,double &trail){ trig=InpE2PartTrig; ratio=InpE2PartRatio; be=InpE2Be; trail=InpE2Trail; }

#endif // KENKEM_E2_MQH
