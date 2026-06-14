//+------------------------------------------------------------------+
//|  KK-Common/PositionManager.mqh                                   |
//|  Generic tick-fill management for ONE open position: partial-TP   |
//|  -> breakeven -> chandelier trail, with broker stop-distance      |
//|  guards. Shared by all families; family code owns the per-ticket  |
//|  state store and supplies the per-entry params.                   |
//+------------------------------------------------------------------+
#ifndef KKC_POSITIONMANAGER_MQH
#define KKC_POSITIONMANAGER_MQH

#include <Trade/Trade.mqh>

// Manage one (already-identified) position. `best`/`partDone` are the caller-owned per-ticket state
// (high-water mark + partial-taken flag), passed by reference. minDist = KKMinStopDist(sym).
void KKManagePosition(CTrade &exec,string sym,ulong tk,bool isLong,
                      double entry,double sl,double tp,double vol,double price,double risk,
                      double minDist,double trig,double ratio,double beBuf,double trailF,
                      double &best,bool &partDone)
{
   int dg = (int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   if(best==0.0) best=entry;
   if(isLong){ if(price>best) best=price; } else { if(price<best) best=price; }
   double curSL = sl;

   // Partial TP -> move to breakeven.
   if(!partDone && tp!=0.0)
   {
      double trgPx = isLong ? entry+trig*(tp-entry) : entry-trig*(entry-tp);
      bool hit = isLong ? (price>=trgPx) : (price<=trgPx);
      if(hit)
      {
         double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
         double q=vol*ratio; if(step>0.0) q=MathFloor(q/step)*step;
         if(q>=mn && q<vol) exec.PositionClosePartial(tk,q);
         partDone=true;
         double be = isLong ? entry+beBuf*risk : entry-beBuf*risk; be=NormalizeDouble(be,dg);
         bool okSide=(isLong && be>curSL)||(!isLong && be<curSL);
         bool okDist=(isLong ? (price-be>=minDist) : (be-price>=minDist));
         if(okSide && okDist){ exec.PositionModify(tk,be,tp); curSL=be; }
      }
   }
   // Chandelier trail once partial taken (raise/lower-only + stop-distance guard).
   if(partDone)
   {
      double trail = isLong ? best-trailF*risk : best+trailF*risk; trail=NormalizeDouble(trail,dg);
      bool okSide=(isLong && trail>curSL)||(!isLong && trail<curSL);
      bool okDist=(isLong ? (price-trail>=minDist) : (trail-price>=minDist));
      if(okSide && okDist) exec.PositionModify(tk,trail,tp);
   }
}

#endif // KKC_POSITIONMANAGER_MQH
