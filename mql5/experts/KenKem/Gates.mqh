//+------------------------------------------------------------------+
//|  KenKem/Gates.mqh — family-shared gates: EMA-stack alignment,     |
//|  trend-quality hard gate, HTF agreement filter.                  |
//+------------------------------------------------------------------+
#ifndef KENKEM_GATES_MQH
#define KENKEM_GATES_MQH

#include "State.mqh"
#include "Indicators.mqh"

// EMA-stack alignment (EMA1>EMA2>EMA3[>EMA4 strict]) with tolerance. EMA0/fast excluded.
bool EmasReady(int tf,int shift,bool isLong,bool strict,double tol)
{
   double e1=Ema(tf,1,shift),e2=Ema(tf,2,shift),e3=Ema(tf,3,shift),e4=Ema(tf,4,shift);
   if(isLong) return (e1>e2-tol)&&(e2>e3-tol)&&(!strict||(e3>e4-tol));
   return (e1<e2+tol)&&(e2<e3+tol)&&(!strict||(e3<e4+tol));
}

// Core trend-quality (0-6) = ADX(0-2)+DI spread(0-2)+MTF DI alignment(0-2). 0 = hard gate trips.
int TrendCore(const Snap &s,bool isLong)
{
   int adxPts=(s.adx[0]>=InpAdxHighThreshold)?2:((s.adx[0]>=InpMinMomentumAdx)?1:0);
   double sp=isLong?(s.diP[0]-s.diM[0]):(s.diM[0]-s.diP[0]);
   int diPts=(sp>=3.0)?2:((sp>=1.0)?1:0);
   int al=0; for(int t=0;t<3;t++){ bool ok=isLong?(s.diP[t]>s.diM[t]):(s.diM[t]>s.diP[t]); if(ok) al++; }
   int mtf=(al==3)?2:((al>=2)?1:0);
   if(adxPts==0||diPts==0||mtf==0) return 0;
   return adxPts+diPts+mtf;
}

bool HtfTfOk(const Snap &s,int tf,bool isLong,double minAdx,double minDi)
{
   if(s.adx[tf]<minAdx) return false;
   double sp=isLong?(s.diP[tf]-s.diM[tf]):(s.diM[tf]-s.diP[tf]); return sp>=minDi;
}

// mode: 0=off, 1=M5, 3=M15, 2=M5&M15, 4=M5|M15.
bool HtfOk(const Snap &s,bool isLong,int mode,double minAdx,double minDi)
{
   if(mode==0) return true;
   if(mode==1) return HtfTfOk(s,2,isLong,minAdx,minDi);
   if(mode==3) return HtfTfOk(s,3,isLong,minAdx,minDi);
   if(mode==2) return HtfTfOk(s,2,isLong,minAdx,minDi)&&HtfTfOk(s,3,isLong,minAdx,minDi);
   return HtfTfOk(s,2,isLong,minAdx,minDi)||HtfTfOk(s,3,isLong,minAdx,minDi);
}

#endif // KENKEM_GATES_MQH
