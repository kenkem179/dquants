//+------------------------------------------------------------------+
//|  KenKem/Entries/E1.mqh — EMA-stack cross (trend continuation).    |
//|  Trigger: M1/M3/M5 stack just-crossed, OR EMA200 touch while      |
//|  M1+M3 aligned. Gate: hard trend-quality (Engine) + M1/M3 align + |
//|  HTF. SL anchor: ema100 +/- 0.75*|ema100-ema200|.                 |
//+------------------------------------------------------------------+
#ifndef KENKEM_E1_MQH
#define KENKEM_E1_MQH

#include "../State.mqh"
#include "../Gates.mqh"

void E1_UpdateTrigger(datetime now,double tol)
{
   bool m1u=!EmasReady(0,2,true,true,tol)&&EmasReady(0,1,true,true,tol);
   bool m3u=!EmasReady(1,2,true,true,tol)&&EmasReady(1,1,true,true,tol);
   bool m5u=!EmasReady(2,2,true,false,tol)&&EmasReady(2,1,true,false,tol);
   if(gE1Up==0 && (m1u||m3u||m5u) && EmasReady(0,1,true,true,tol) && EmasReady(1,1,true,true,tol)){ gE1Up=now; gE1Dn=0; }
   bool m1d=!EmasReady(0,2,false,true,tol)&&EmasReady(0,1,false,true,tol);
   bool m3d=!EmasReady(1,2,false,true,tol)&&EmasReady(1,1,false,true,tol);
   bool m5d=!EmasReady(2,2,false,false,tol)&&EmasReady(2,1,false,false,tol);
   if(gE1Dn==0 && (m1d||m3d||m5d) && EmasReady(0,1,false,true,tol) && EmasReady(1,1,false,true,tol)){ gE1Dn=now; gE1Up=0; }
   double ema200=Ema(0,4,1), lo=iLow(_Symbol,PERIOD_M1,1), hi=iHigh(_Symbol,PERIOD_M1,1);
   if(lo<=ema200 && hi>=ema200){
      if(gE1Up==0 && EmasReady(0,1,true,true,tol) && EmasReady(1,1,true,true,tol)){ gE1Up=now; gE1Dn=0; }
      else if(gE1Dn==0 && EmasReady(0,1,false,true,tol) && EmasReady(1,1,false,true,tol)){ gE1Dn=now; gE1Up=0; }
   }
}

bool E1_Gate(const Snap &s,bool isLong)
{
   double tol=Tol();
   if(!EmasReady(0,1,isLong,true,tol)||!EmasReady(1,1,isLong,true,tol)) return false;
   return HtfOk(s,isLong,InpE1HtfMode,InpE1HtfMinAdx,InpE1HtfMinDi);
}

double E1_CustomLevel(bool isLong,const Snap &s){ double d=MathAbs(s.emaM1[3]-s.emaM1[4])*0.75; return isLong?s.emaM1[3]-d:s.emaM1[3]+d; }
void   E1_AtrCaps(double &cap,double &flr){ cap=InpE1AtrSlCap; flr=InpE1AtrSlFloor; }
double E1_Rr(bool isLong,bool sw){ return sw?InpRrSidewayAll:(isLong?InpE1Rr:InpE1Rr*0.875); }
void   E1_Mgmt(double &trig,double &ratio,double &be,double &trail){ trig=InpE1PartTrig; ratio=InpE1PartRatio; be=InpE1Be; trail=InpE1Trail; }

#endif // KENKEM_E1_MQH
