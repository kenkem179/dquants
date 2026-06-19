//+------------------------------------------------------------------+
//|  KK-MasterVP-Monster/NetVolume.mqh — M1 near-price net tick volume |
//|  for the impulse path. 1:1 with cpp_core kk::net_prev_at_time +     |
//|  tf_net_near_at on the M1 series.                                  |
//|                                                                    |
//|  PARITY-CRITICAL: net is built from iVolume(...) = M1 tick_volume  |
//|  (== the engine's per-bar tick_count), NOT real broker volume      |
//|  (~0 on Exness) — the bug that made the old Monster EA trade ZERO. |
//|                                                                    |
//|  Decision time = current chart bar open (the entry bar). The last  |
//|  CLOSED M1 bar before it is shift `sClosed`; the net is evaluated  |
//|  one M1 bar earlier (the Pine [1] read) -> refShift = sClosed+1.   |
//+------------------------------------------------------------------+
#ifndef KKMON_NETVOLUME_MQH
#define KKMON_NETVOLUME_MQH

#include "../KK-Common/Indicators.mqh"

// Returns the M1 near-price net in [-1,+1]; valid=false only when the reference M1 bar is unreadable.
double M1NetNear(int atrM1Handle,int look,double winAtr,double mintick,bool &valid)
{
   valid=false;
   datetime T=iTime(_Symbol,PERIOD_CURRENT,0);            // entry-bar open = decision time
   int sClosed=iBarShift(_Symbol,PERIOD_M1,T-1,false);    // last CLOSED M1 bar before T
   if(sClosed<0) return 0.0;
   int refShift=sClosed+1;                                // the [1] read
   double px=iClose(_Symbol,PERIOD_M1,refShift);
   if(px<=0.0) return 0.0;
   valid=true;
   double a=KKBuf(atrM1Handle,0,refShift);
   if(a<=0.0) return 0.0;                                 // na/0 ATR -> 0 net, still valid
   double win=winAtr*a;
   double tB=0.0,tS=0.0;
   for(int k=0;k<look;k++){
      int sh=refShift+k;                                  // `look` bars ending at refShift, going back
      double hi=iHigh(_Symbol,PERIOD_M1,sh), lo=iLow(_Symbol,PERIOD_M1,sh);
      double op=iOpen(_Symbol,PERIOD_M1,sh), cl=iClose(_Symbol,PERIOD_M1,sh);
      if(cl<=0.0||hi<lo) continue;
      double rng=MathMax(hi-lo,mintick);
      double dp=(cl-op)/rng;
      double p=(hi+lo+cl)/3.0;
      if(MathAbs(p-px)<=win){
         double v=(double)iVolume(_Symbol,PERIOD_M1,sh);  // tick_volume (parity-critical)
         tB+=v*MathMax(dp,0.0); tS+=v*MathMax(-dp,0.0);
      }
   }
   double tot=tB+tS; return (tot>0.0)?(tB-tS)/tot:0.0;
}

#endif // KKMON_NETVOLUME_MQH
