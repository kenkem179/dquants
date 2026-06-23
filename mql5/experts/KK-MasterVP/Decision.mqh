//+------------------------------------------------------------------+
//|  KK-MasterVP/Decision.mqh - SHARED entry decision (single source). |
//|                                                                    |
//|  This is the load-bearing reuse boundary between the EA and the    |
//|  KK-MasterVP-Profiler INDICATOR. It holds ONLY chart-deterministic |
//|  logic: the signal (MVP_DetectSignal) plus the gates that can be   |
//|  reproduced from bar/indicator history alone - quality (MTF/RSI),  |
//|  session, ATR% band, ATR-ticks floor, blocked-hour, news.          |
//|                                                                    |
//|  NOTHING here touches the live account, open positions, spread at  |
//|  the fire tick, or CTrade. Those LIVE/STATEFUL gates (has-position, |
//|  spread, daily-DD, peak-DD, cooldown, TP1 cost-clearance) stay in   |
//|  the EA's Engine.mqh because an indicator has no equity/fills.      |
//|                                                                    |
//|  Because both the EA and the indicator call MVP_DeterministicGates  |
//|  Pass() over the SAME inputs, they cannot disagree on which bar a   |
//|  signal clears the deterministic gate stack - that is the parity    |
//|  guarantee. (Replay-reproducible stateful gates the indicator still |
//|  needs - max-trades/session and one-position-at-a-time - live in    |
//|  SessionNews.mqh + the indicator's own replay loop, not here.)      |
//+------------------------------------------------------------------+
#ifndef KKMVP_DECISION_MQH
#define KKMVP_DECISION_MQH

#include "Inputs.mqh"
#include "Strategy.mqh"

// MTF (HTF EMA shift1) + RSI(shift1) quality gate. Pure: caller supplies the
// already-read buffer values (EA: M15 EMAs + RSI at shift 1). Both gates OFF in
// the locked config, so this returns true there. Byte-identical to the body the
// EA used inline as QualityOk().
bool MVP_QualityOk(bool isLong,double hfFast,double hfSlow,double rsi)
{
   if(InpUseMtfAgree){
      if(hfFast>0.0 && hfSlow>0.0){
         bool bull=hfFast>hfSlow, bear=hfFast<hfSlow;
         if(InpMtfHardVeto){
            if(isLong && !bull) return false;
            if(!isLong && !bear) return false;
         } else {
            if(isLong && bear) return false;
            if(!isLong && bull) return false;
         }
      }
   }
   if(InpUseMomVeto){
      if(rsi>0.0){ if(isLong && rsi<InpRsiMidline) return false; if(!isLong && rsi>InpRsiMidline) return false; }
   }
   return true;
}

// The chart-deterministic gate stack applied to a VALID signal. Returns true iff
// the signal clears every gate that can be evaluated from chart history alone.
// Mirrors the corresponding early-returns in Engine.mqh::OnNewBar 1:1 (the set of
// conditions is identical; none of these gates has a side effect, so grouping the
// deterministic gates ahead of the EA's live/stateful gates is behaviour-neutral).
//   atrPct  = AtrAt(1)/price*100   (price = signal entry_close)
//   atr1    = AtrAt(1)             (for the ATR-ticks floor)
//   mintick = SYMBOL_TRADE_TICK_SIZE
//   isImpulse = true => skip ONLY the ATR% band (the impulse-thrust path deliberately
//               owns the band ABOVE the ceiling). Default false => byte-identical to the
//               base; every other gate still applies to impulse entries.
bool MVP_DeterministicGatesPass(const Signal &sig,int sessionId,double atrPct,
                                double atr1,double mintick,bool blockedHour,bool newsWindow,
                                double hfFast,double hfSlow,double rsi,bool isImpulse=false)
{
   if(!sig.valid)                       return false;
   if(!MVP_QualityOk(sig.is_long,hfFast,hfSlow,rsi)) return false;   // quality (MTF/RSI; off)
   if(sessionId==0)                     return false;                 // out of session
   if(!isImpulse && atrPct<InpMinAtrPct)              return false;   // ATR% min (off=0; impulse owns the band)
   if(!isImpulse && InpMaxAtrPct>0.0 && atrPct>InpMaxAtrPct) return false; // ATR% max (off=0; impulse owns the band)
   if(InpMinAtrTicks>0.0 && mintick>0.0 && atr1/mintick<InpMinAtrTicks) return false; // ATR-ticks floor
   if(blockedHour)                      return false;                 // blocked-hour veto
   if(newsWindow)                       return false;                 // news blackout (overlay; off)
   return true;
}

#endif // KKMVP_DECISION_MQH
