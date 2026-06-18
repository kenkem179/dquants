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
double KKPositionSize(double balance,double riskRatio,double riskPrice,double vppl,
                      double volMin,double volMax,double volStep)
{
   if(riskPrice<=0.0 || vppl<=0.0) return volMin;
   double lot = balance*riskRatio/(riskPrice*vppl);
   if(volStep>0.0) lot = MathRound(lot/volStep)*volStep;
   return MathMax(volMin, MathMin(volMax, lot));
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
