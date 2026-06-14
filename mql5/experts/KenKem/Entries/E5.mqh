//+------------------------------------------------------------------+
//|  KenKem/Entries/E5.mqh — SuperBros M1 EMA alignment (loose).      |
//|  Trigger: fresh STRICT M1 4-EMA alignment onset (no tolerance).   |
//|  Gate: NO trend hard-gate (Engine skips it for E5) — just price   |
//|  on the right side of EMA25 + optional ADX floor + HTF.           |
//|  SL anchor: ema200.                                              |
//+------------------------------------------------------------------+
#ifndef KENKEM_E5_MQH
#define KENKEM_E5_MQH

#include "../State.mqh"
#include "../Gates.mqh"

void E5_UpdateTrigger(datetime now,double tol)
{
   bool u1=EmasReady(0,1,true,true,0.0),u2=EmasReady(0,2,true,true,0.0);
   bool d1=EmasReady(0,1,false,true,0.0),d2=EmasReady(0,2,false,true,0.0);
   if(!u1) gE5Up=0; else if(!u2&&gE5Up==0){ gE5Up=now; gE5Dn=0; }
   if(!d1) gE5Dn=0; else if(!d2&&gE5Dn==0){ gE5Dn=now; gE5Up=0; }
}

bool E5_Gate(const Snap &s,bool isLong)
{
   bool px=isLong?(iClose(_Symbol,PERIOD_M1,1)>s.emaM1[1]):(iClose(_Symbol,PERIOD_M1,1)<s.emaM1[1]);
   if(!px) return false;
   if(InpE5MinMomAdx>0 && s.adx[0]<InpE5MinMomAdx) return false;
   return HtfOk(s,isLong,InpE5HtfMode,InpE5HtfMinAdx,InpE5HtfMinDi);
}

double E5_CustomLevel(bool isLong,const Snap &s){ return s.emaM1[4]; }
void   E5_AtrCaps(double &cap,double &flr){ cap=InpE5AtrSlCap; flr=InpE5AtrSlFloor; }
double E5_Rr(bool isLong,bool sw){ return sw?InpRrSidewayAll:InpE5Rr; }
void   E5_Mgmt(double &trig,double &ratio,double &be,double &trail){ trig=InpE5PartTrig; ratio=InpE5PartRatio; be=InpE5Be; trail=InpE5Trail; }

#endif // KENKEM_E5_MQH
