//+------------------------------------------------------------------+
//|  KenKem/Entries/E4.mqh — Ichimoku Tenkan/Kijun cross (early trend)|
//|  Trigger: TK cross with M1 AND M3 flipping together.              |
//|  Gate: hard trend-quality (Engine) + own ADX-min + real Senkou    |
//|  cloud agreement + cloud thickness + M5-or-M15 HTF.               |
//|  SL anchor: ema100 +/- 0.75*|ema100-ema200| (same as E1).         |
//+------------------------------------------------------------------+
#ifndef KENKEM_E4_MQH
#define KENKEM_E4_MQH

#include "../State.mqh"
#include "../Gates.mqh"

void E4_UpdateTrigger(datetime now,double tol)
{
   bool m1c=CloudBull(hIchiM1,1),m3c=CloudBull(hIchiM3,1),m1p=CloudBull(hIchiM1,2),m3p=CloudBull(hIchiM3,2);
   bool bbC=m1c&&m3c,bbP=m1p&&m3p,brC=!m1c&&!m3c,brP=!m1p&&!m3p;
   if(bbC&&!bbP&&gE4Up==0){ gE4Up=now; gE4Dn=0; }
   if(brC&&!brP&&gE4Dn==0){ gE4Dn=now; gE4Up=0; }
}

bool E4_Gate(const Snap &s,bool isLong)
{
   if(s.adx[0]<InpE4MinMomAdx) return false;
   bool green=s.senkouA_M3>s.senkouB_M3;
   if(InpE4ReqCloud && (isLong? !green : green)) return false;
   double thick=MathAbs(s.senkouA_M3-s.senkouB_M3);
   if(InpE4MinCloudThickAtr>0 && s.atrM1>0 && thick<InpE4MinCloudThickAtr*s.atrM1) return false;
   return HtfOk(s,isLong,InpE4HtfMode,InpE4HtfMinAdx,InpE4HtfMinDi);
}

double E4_CustomLevel(bool isLong,const Snap &s){ double d=MathAbs(s.emaM1[3]-s.emaM1[4])*0.75; return isLong?s.emaM1[3]-d:s.emaM1[3]+d; }
void   E4_AtrCaps(double &cap,double &flr){ cap=InpE4AtrSlCap; flr=InpE4AtrSlFloor; }
double E4_Rr(bool isLong,bool sw){ return sw?InpRrSidewayAll:(isLong?InpE4Rr:InpE4RrShort*0.875); }
void   E4_Mgmt(double &trig,double &ratio,double &be,double &trail){ trig=InpE4PartTrig; ratio=InpE4PartRatio; be=InpE4Be; trail=InpE4Trail; }

#endif // KENKEM_E4_MQH
