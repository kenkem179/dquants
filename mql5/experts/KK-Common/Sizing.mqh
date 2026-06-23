//+------------------------------------------------------------------+
//|  KK-Common/Sizing.mqh                                            |
//|  Risk-correct position sizing + broker stop-distance helper.     |
//|  Shared by ALL families. Pure functions (no global state).       |
//+------------------------------------------------------------------+
#ifndef KKC_SIZING_MQH
#define KKC_SIZING_MQH

// Lot such that a full-stop loss == balance*riskRatio exactly.
//   vppl = value per price per lot = SYMBOL_TRADE_TICK_VALUE / SYMBOL_TRADE_TICK_SIZE.
//   riskPrice = |entry - sl| in price units. Result normalized to broker volume step/min/max.
//   volLimit       = SYMBOL_VOLUME_LIMIT: max TOTAL volume per symbol/direction (0 = none).
//   openVolSameDir = volume already open in the same direction (counts against volLimit).
// The risk-derived lot is clamped to min(volMax, volLimit-openVolSameDir) FLOORED to a valid
// step, so the EA never asks for more than the broker allows ("Volume limit reached"). Returns
// 0 when there is no legal room for even the minimum lot (caller should then skip the trade).
double KKPositionSize(double balance,double riskRatio,double riskPrice,double vppl,
                      double volMin,double volMax,double volStep,
                      double volLimit=0.0,double openVolSameDir=0.0)
{
   if(riskPrice<=0.0 || vppl<=0.0) return 0.0;
   double lot = balance*riskRatio/(riskPrice*vppl);
   if(volStep>0.0) lot = MathRound(lot/volStep)*volStep;       // unchanged for normal-sized lots
   // hard ceiling: per-order max AND remaining room under the per-symbol/direction limit
   double ceil = volMax;
   if(volLimit>0.0){ double room=volLimit-openVolSameDir; if(room<ceil) ceil=room; }
   if(volStep>0.0) ceil = MathFloor(ceil/volStep)*volStep;     // floor so we never step over it
   if(lot>ceil) lot=ceil;
   if(lot<volMin) return (volMin<=ceil)?volMin:0.0;            // no legal room -> skip
   return lot;
}

// Minimum legal distance (price units) of SL/TP from price: max(stops_level, freeze_level).
double KKMinStopDist(string sym)
{
   double pt = SymbolInfoDouble(sym,SYMBOL_POINT);
   return MathMax((double)SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL),
                  (double)SymbolInfoInteger(sym,SYMBOL_TRADE_FREEZE_LEVEL)) * pt;
}

// Clamp SL/TP outward so both sit >= minDist from `price` (entry anchor). Mutates sl/tp by ref.
void KKClampStops(bool isLong,double price,double minDist,double &sl,double &tp)
{
   if(isLong){ if(price-sl<minDist) sl=price-minDist; if(tp-price<minDist) tp=price+minDist; }
   else      { if(sl-price<minDist) sl=price+minDist; if(price-tp<minDist) tp=price-minDist; }
}

#endif // KKC_SIZING_MQH
