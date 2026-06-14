//+------------------------------------------------------------------+
//|  KK-Common/DeferredEntry.mqh                                     |
//|  Shared "deferred / pullback limit" entry mechanism for all       |
//|  families. Instead of a market fill on the first tick of the      |
//|  signal bar, arm a VIRTUAL limit at a more favourable price and    |
//|  let it fill within `expiry_bars` (default 3) if still valid —     |
//|  cancels on expiry or explicit invalidation. Trades a small        |
//|  missed-fill rate for better entry R + lower spread cost.          |
//|                                                                  |
//|  Standard technique (pullback / retest / passive-limit entry).    |
//|  Virtual (EA-managed) rather than a broker pending order, so the   |
//|  strategy can re-check conditions each bar before filling.         |
//|                                                                  |
//|  Usage:                                                          |
//|    On a signal (instead of market entry): DeferArm(d, isLong,kind, |
//|      limitPx, sl, tp, InpDeferBars, iTime(_Symbol,PERIOD_CURRENT,0)|
//|    Each NEW bar BEFORE detecting fresh signals:                    |
//|      if(DeferTryFill(d, barsSinceArm(d), high1, low1)) -> open at  |
//|         d.limit_px with d.sl / d.tp.                               |
//|      if(setup no longer valid)  DeferInvalidate(d);                |
//+------------------------------------------------------------------+
#ifndef KKC_DEFERREDENTRY_MQH
#define KKC_DEFERREDENTRY_MQH

struct DeferIntent
{
   bool     active;
   bool     is_long;
   int      kind;            // entry kind tag (family-specific)
   double   limit_px;        // the favourable price to wait for
   double   sl, tp, risk;    // protective levels (recompute off limit_px if desired)
   datetime arm_time;        // bar open time when armed
   int      expiry_bars;     // cancel after this many bars without a fill
};

void DeferReset(DeferIntent &d){ d.active=false; d.is_long=false; d.kind=0; d.limit_px=0; d.sl=0; d.tp=0; d.risk=0; d.arm_time=0; d.expiry_bars=0; }

// Arm a deferred limit. limitPx = the "more reasonable" price (e.g. breakout retest level / EMA / VAH).
void DeferArm(DeferIntent &d,bool isLong,int kind,double limitPx,double sl,double tp,int expiryBars,datetime barTime)
{
   d.active=true; d.is_long=isLong; d.kind=kind; d.limit_px=limitPx;
   d.sl=sl; d.tp=tp; d.risk=MathAbs(limitPx-sl); d.arm_time=barTime; d.expiry_bars=expiryBars;
}

void DeferInvalidate(DeferIntent &d){ d.active=false; }

// Bars elapsed since arm (count of distinct M1/chart bars). Caller passes current bar time.
int DeferBarsElapsed(const DeferIntent &d,datetime curBarTime,int tfSeconds)
{
   if(!d.active || tfSeconds<=0) return 0;
   return (int)((curBarTime-d.arm_time)/tfSeconds);
}

// Per-new-bar test: did this bar trade through the limit (long: low<=limit; short: high>=limit)?
// Cancels on expiry. Returns true (and deactivates) on a fill. `barsElapsed` from DeferBarsElapsed.
bool DeferTryFill(DeferIntent &d,int barsElapsed,double barHigh,double barLow)
{
   if(!d.active) return false;
   if(barsElapsed>d.expiry_bars){ d.active=false; return false; }   // expired -> cancel
   bool touched = d.is_long ? (barLow<=d.limit_px) : (barHigh>=d.limit_px);
   if(touched){ d.active=false; return true; }
   return false;
}

#endif // KKC_DEFERREDENTRY_MQH
