//+------------------------------------------------------------------+
//|  VP-Common/Regime.mqh — trend vs balance regime (Core/Regime.mqh).|
//|  Read on the just-closed bar (shift 1).                          |
//+------------------------------------------------------------------+
#ifndef VPC_REGIME_MQH
#define VPC_REGIME_MQH

#include "Types.mqh"

RegimeState VP_ComputeRegime(double atr,double emaFast,double emaSlow,double adx,double plus,double minus,
                             double adxTrendMin,double diSpreadMin,double emaSepAtr)
{
   RegimeState r;
   r.atr1=atr; r.plus=plus; r.minus=minus; r.adx=adx;
   r.valid=(atr>0.0 && emaSlow!=0.0);
   r.trend=(adx>adxTrendMin) && (MathAbs(plus-minus)>diSpreadMin) && (MathAbs(emaFast-emaSlow)>emaSepAtr*atr);
   r.balance=!r.trend;
   return r;
}

#endif // VPC_REGIME_MQH
