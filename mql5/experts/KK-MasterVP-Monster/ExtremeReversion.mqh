//+------------------------------------------------------------------+
//|  KK-MasterVP/ExtremeReversion.mqh — failed-breakout liquidity-     |
//|  sweep reversal entry (XRev). 1:1 port of cpp_core                 |
//|  kk::detect_extreme_reversion (extreme_reversion.hpp).             |
//|  Toggle OFF by default => never invoked; base byte-identical.      |
//|                                                                    |
//|  Canonical SHORT at master VAH: price SWEEPS max(mVAH, recent      |
//|  swing-high), closes back BELOW mVAH on a big sell-flow candle with |
//|  a visible upper rejection wick, after an aged round-trip up from   |
//|  mVAL. Target = mVAL. LONG = exact mirror at mVAL. Shift map        |
//|  identical to MVP_DetectSignal: signal/rejection bar = shift 2,     |
//|  entry anchor = close[1]. Lookback scalars are caller-precomputed   |
//|  (sweep_hi/lo, closes_above/below, aged_short/long) exactly as the  |
//|  C++ tick_engine computes them.                                    |
//+------------------------------------------------------------------+
#ifndef KKMVP_EXTREMEREVERSION_MQH
#define KKMVP_EXTREMEREVERSION_MQH

#include "../VP-Common/Types.mqh"
#include "Inputs.mqh"
#include "Strategy.mqh"   // SignalBar

Signal MVP_DetectExtremeReversion(const VPResult &master_cur,const SignalBar &s,
                                  double sweep_hi,double sweep_lo,
                                  int closes_above,int closes_below,
                                  bool aged_short,bool aged_long,
                                  const NodeState &ns_vah,const NodeState &ns_val,const NodeState &ns_px,
                                  double pipSize,double mintick)
{
   Signal out; out.valid=false; out.reason="";
   if(!InpEnableExtremeReversion || !master_cur.valid) return out;
   if(s.c<=0||s.o<=0||s.h<=0||s.l<=0||s.h<s.l) return out;
   if(s.entry_close<=0) return out;

   double atr2=s.atr2, atr1=s.atr1;
   if(atr2<=0.0||atr1<=0.0) return out;
   double mVah=master_cur.vah, mVal=master_cur.val;
   if(mVah<=0.0||mVal<=0.0||mVah<=mVal) return out;

   double rng=MathMax(s.h-s.l,mintick);
   double bodyPct=MathAbs(s.c-s.o)/rng;
   double bodyAbs=MathAbs(s.c-s.o);
   double upWick=s.h-MathMax(s.o,s.c);
   double dnWick=MathMin(s.o,s.c)-s.l;

   bool bigRange=(rng>=InpXRevBigCandleAtr*atr2);
   bool wickShort=(upWick>=InpXRevWickFrac*bodyAbs);
   bool wickLong =(dnWick>=InpXRevWickFrac*bodyAbs);

   // A. failed-acceptance count (min, optional max)
   bool countAbove=(closes_above>=InpXRevMinClosesBeyond) && (InpXRevMaxClosesBeyond<=0 || closes_above<=InpXRevMaxClosesBeyond);
   bool countBelow=(closes_below>=InpXRevMinClosesBeyond) && (InpXRevMaxClosesBeyond<=0 || closes_below<=InpXRevMaxClosesBeyond);

   // SHORT
   bool sweptShort=(s.h>sweep_hi);
   bool failBackShort=(s.c<mVah);
   bool bearBody=(s.c<s.o)&&(bodyPct>=InpXRevBodyPctMin);
   bool netShort=(ns_px.net<=-InpXRevNetDeltaMin);
   bool nodeShortOk=!InpXRevUseNodeGate || (ns_vah.absorbed || ns_vah.state<=0);
   bool shortXR=countAbove && aged_short && sweptShort && failBackShort && bearBody && bigRange && wickShort && netShort && nodeShortOk;

   // LONG mirror
   bool sweptLong=(s.l<sweep_lo);
   bool failBackLong=(s.c>mVal);
   bool bullBody=(s.c>s.o)&&(bodyPct>=InpXRevBodyPctMin);
   bool netLong=(ns_px.net>=InpXRevNetDeltaMin);
   bool nodeLongOk=!InpXRevUseNodeGate || (ns_val.absorbed || ns_val.state>=0);
   bool longXR=countBelow && aged_long && sweptLong && failBackLong && bullBody && bigRange && wickLong && netLong && nodeLongOk;

   if(longXR==shortXR) return out;   // exactly one direction

   out.is_long=longXR; out.entry=s.entry_close;
   if(shortXR){
      double sl=sweep_hi+InpXRevSlAtr*atr1;
      double risk=sl-s.entry_close; if(risk<=0.0) return out;
      double runway=s.entry_close-mVal; if(runway<=0.0) return out;
      if(runway/risk<InpXRevRrMin) return out;
      out.sl=sl; out.risk=risk;
      out.tp1=s.entry_close-risk*InpTp1R; out.tp2=mVal; out.reason="S-XREV";
   } else {
      double sl=sweep_lo-InpXRevSlAtr*atr1;
      double risk=s.entry_close-sl; if(risk<=0.0) return out;
      double runway=mVah-s.entry_close; if(runway<=0.0) return out;
      if(runway/risk<InpXRevRrMin) return out;
      out.sl=sl; out.risk=risk;
      out.tp1=s.entry_close+risk*InpTp1R; out.tp2=mVah; out.reason="L-XREV";
   }
   out.valid=true; out.is_rev=true;

   double atrF=(atr2>0.0)?atr2:1.0;
   out.f_body_pct=bodyPct; out.f_node_net=ns_px.net;
   out.f_brk_dist_atr=longXR?(mVal-s.c)/atrF:(s.c-mVah)/atrF;
   out.f_runway_atr  =longXR?(mVah-s.entry_close)/atrF:(s.entry_close-mVal)/atrF;
   out.f_adx=0.0; out.f_di_spread=0.0;
   return out;
}

#endif // KKMVP_EXTREMEREVERSION_MQH
