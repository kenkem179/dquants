//+------------------------------------------------------------------+
//|  KenKem/Indicators.mqh — family indicator handle set + accessors. |
//|  Creates only the handles the ENABLED entries read (off-entries   |
//|  cost zero). Accessors read shift-N via the generic KKBuf.        |
//+------------------------------------------------------------------+
#ifndef KENKEM_INDICATORS_MQH
#define KENKEM_INDICATORS_MQH

#include "../KK-Common/Indicators.mqh"
#include "State.mqh"
#include "Inputs.mqh"

double Ema(int tf,int e,int s){ return KKBuf(hEma[tf][e],0,s); }
double Adx(int tf,int s){ return KKBuf(hAdx[tf],0,s); }
double DiP(int tf,int s){ return KKBuf(hAdx[tf],1,s); }
double DiM(int tf,int s){ return KKBuf(hAdx[tf],2,s); }
double Tol(){ return InpEmaAlignTolPips*g_pip; }
bool   CloudBull(int h,int s){ return KKBuf(h,0,s)>KKBuf(h,1,s); }  // Tenkan>Kijun

int KK_EmaPeriod(int e){ return e==0?InpEma0:e==1?InpEma1:e==2?InpEma2:e==3?InpEma3:InpEma4; }

void KenKemCreateHandles()
{
   for(int t=0;t<4;t++) for(int e=0;e<5;e++) hEma[t][e]=INVALID_HANDLE;
   // M1 EMAs + ADX/DI(all TFs) + M1 ATR/RSI are shared by trend-core / sideways / HTF -> always.
   for(int e=0;e<5;e++) hEma[0][e]=iMA(_Symbol,PERIOD_M1,KK_EmaPeriod(e),0,MODE_EMA,PRICE_CLOSE);
   for(int t=0;t<4;t++) hAdx[t]=iADX(_Symbol,KK_TF[t],InpAdxLen);
   hAtrM1=iATR(_Symbol,PERIOD_M1,InpAtrLen);
   hRsiM1=iRSI(_Symbol,PERIOD_M1,InpRsiLen,PRICE_CLOSE);
   // M3/M5 EMA = E1/E2 alignment only; Ichimoku = E4 only; M15 EMA = never read.
   if(InpE1On||InpE2On) for(int e=0;e<5;e++) hEma[1][e]=iMA(_Symbol,PERIOD_M3,KK_EmaPeriod(e),0,MODE_EMA,PRICE_CLOSE);
   if(InpE1On)          for(int e=0;e<5;e++) hEma[2][e]=iMA(_Symbol,PERIOD_M5,KK_EmaPeriod(e),0,MODE_EMA,PRICE_CLOSE);
   if(InpE4On){
      hIchiM1=iIchimoku(_Symbol,PERIOD_M1,InpIchiTenkan,InpIchiKijun,InpIchiSenkou);
      hIchiM3=iIchimoku(_Symbol,PERIOD_M3,InpIchiTenkan,InpIchiKijun,InpIchiSenkou);
   }
}

void KenKemReleaseHandles()
{
   for(int t=0;t<4;t++){ for(int e=0;e<5;e++) IndicatorRelease(hEma[t][e]); IndicatorRelease(hAdx[t]); }
   IndicatorRelease(hAtrM1); IndicatorRelease(hRsiM1); IndicatorRelease(hIchiM1); IndicatorRelease(hIchiM3);
}

#endif // KENKEM_INDICATORS_MQH
