//+------------------------------------------------------------------+
//|  KenKem/Snapshot.mqh — build the decision-time Snap (shift 1).    |
//|  Sideways chop score (0-100) + ATR percentile.                   |
//+------------------------------------------------------------------+
#ifndef KENKEM_SNAPSHOT_MQH
#define KENKEM_SNAPSHOT_MQH

#include "State.mqh"
#include "Indicators.mqh"

double AtrPct(double ref,int lb)
{
   if(lb<=0||ref<=0) return 50.0;
   double v[]; if(CopyBuffer(hAtrM1,0,1,lb,v)<=0) return 50.0;
   int below=0,n=ArraySize(v); for(int i=0;i<n;i++) if(v[i]<ref) below++;
   return n>0 ? (double)below/n*100.0 : 50.0;
}

int Sideways(const Snap &s)
{
   int sc=0;
   double mx=MathMax(MathMax(s.emaM1[1],s.emaM1[2]),MathMax(s.emaM1[3],s.emaM1[4]));
   double mn=MathMin(MathMin(s.emaM1[1],s.emaM1[2]),MathMin(s.emaM1[3],s.emaM1[4]));
   double sp=(s.atrM1>0)?(mx-mn)/s.atrM1:999.0;
   if(sp<1.75) sc+=25; else if(sp<3.25) sc+=15; else if(sp<4.0) sc+=8;
   int a=0; if(s.adx[0]<15)a+=15; else if(s.adx[0]<20)a+=10; else if(s.adx[0]<25)a+=5;
   if(s.adx[1]<18)a+=10; else if(s.adx[1]<22)a+=5; sc+=MathMin(25,a);
   double di=MathAbs(s.diP[0]-s.diM[0]); if(di<2.0)sc+=12; else if(di<4.0)sc+=8; else if(di<6.0)sc+=4;
   double r=s.rsiM1; if(r>=45&&r<=55)sc+=15; else if(r>=40&&r<=60)sc+=10; else if(r>=35&&r<=65)sc+=5;
   if(s.atr_pctile<15)sc+=15; else if(s.atr_pctile<25)sc+=10; else if(s.atr_pctile<35)sc+=5;
   return sc;
}

bool BuildSnap(Snap &s)
{
   for(int t=0;t<4;t++){ s.adx[t]=Adx(t,1); s.diP[t]=DiP(t,1); s.diM[t]=DiM(t,1); }
   for(int e=0;e<5;e++) s.emaM1[e]=Ema(0,e,1);
   s.atrM1=KKBuf(hAtrM1,0,1); s.rsiM1=KKBuf(hRsiM1,0,1);
   s.tenkanM1=KKBuf(hIchiM1,0,1); s.kijunM1=KKBuf(hIchiM1,1,1);
   s.senkouA_M3=KKBuf(hIchiM3,2,1); s.senkouB_M3=KKBuf(hIchiM3,3,1);
   if(s.atrM1<=0){ s.valid=false; return false; }
   s.atr_pctile=AtrPct(s.atrM1,32); s.sideways=Sideways(s); s.valid=true; return true;
}

#endif // KENKEM_SNAPSHOT_MQH
