//+------------------------------------------------------------------+
//|  KK-MasterVP/Strategy.mqh — DetectSignal (breakout L/S +          |
//|  reversion L/S). Faithful transcription of cpp_core               |
//|  kk::detect_signal (== Entries/EntryVP.mqh::DetectSignal).        |
//|  Shift map (caller): signal-bar OHLC + atr2 = shift 2; entry_close |
//|  + atr1 = shift 1. Node states supplied by the caller.            |
//+------------------------------------------------------------------+
#ifndef KKMVP_STRATEGY_MQH
#define KKMVP_STRATEGY_MQH

#include "../VP-Common/Types.mqh"
#include "Inputs.mqh"

struct SignalBar { double o,h,l,c,atr2,atr1,entry_close; };

Signal MVP_DetectSignal(const VPResult &master_cur,const VPResult &master_sig,const VPResult &local_cur,
                        const RegimeState &regime,const SignalBar &s,
                        const NodeState &ns_vah,const NodeState &ns_val,const NodeState &ns_px,
                        double pipSize,double mintick,double rrScale)
{
   Signal out; out.valid=false; out.reason="";
   if(!master_cur.valid || !regime.valid) return out;
   if(s.c<=0||s.o<=0||s.h<=0||s.l<=0||s.h<s.l) return out;

   double sVah=master_sig.valid?master_sig.vah:0.0;
   double sVal=master_sig.valid?master_sig.val:0.0;
   bool   haveSig=master_sig.valid;

   double brkBuf=InpBreakBufAtr*s.atr2;
   double brkMax=InpBreakMaxAtr*s.atr2;
   double touch =MathMax(InpRetestAtr*s.atr2, 3.0*pipSize);

   double rng=MathMax(s.h-s.l,mintick);
   double bodyPct=MathAbs(s.c-s.o)/rng;
   bool   bullBody=(s.c>s.o)&&(bodyPct>=InpBodyPctMin);
   bool   bearBody=(s.c<s.o)&&(bodyPct>=InpBodyPctMin);
   double upWick=s.h-MathMax(s.o,s.c);
   double dnWick=MathMin(s.o,s.c)-s.l;
   double bodyAbs=MathAbs(s.c-s.o);

   bool brkLong =haveSig && (s.c>sVah+brkBuf) && (s.c<=sVah+brkMax);
   bool brkShort=haveSig && (s.c<sVal-brkBuf) && (s.c>=sVal-brkMax);
   bool brkLongOk =!InpNodeGateEnabled || (ns_vah.absorbed || ns_vah.state>=0);
   bool brkShortOk=!InpNodeGateEnabled || (ns_val.absorbed || ns_val.state<=0);
   bool buyFlowVahOk =(ns_vah.net>= InpSfpFlowMin)&&(ns_px.net>= InpSfpFlowMin);
   bool sellFlowValOk=(ns_val.net<=-InpSfpFlowMin)&&(ns_px.net<=-InpSfpFlowMin);
   bool brkFlowLongOk =!InpBrkRequireFlow || buyFlowVahOk;
   bool brkFlowShortOk=!InpBrkRequireFlow || sellFlowValOk;
   bool brkVetoLongOk =!InpBrkVetoSfp || !(upWick>dnWick && upWick>bodyAbs);
   bool brkVetoShortOk=!InpBrkVetoSfp || !(dnWick>upWick && dnWick>bodyAbs);

   bool longBrk =InpEnableBreakout && regime.trend && brkLong  && (regime.plus>regime.minus) && brkLongOk  && brkFlowLongOk  && brkVetoLongOk;
   bool shortBrk=InpEnableBreakout && regime.trend && brkShort && (regime.minus>regime.plus) && brkShortOk && brkFlowShortOk && brkVetoShortOk;

   bool nearVal=haveSig && (MathAbs(s.l-sVal)<=touch);
   bool nearVah=haveSig && (MathAbs(s.h-sVah)<=touch);
   bool revLongOk =!InpNodeGateEnabled || (!ns_val.absorbed && ns_val.state>=0);
   bool revShortOk=!InpNodeGateEnabled || (!ns_vah.absorbed && ns_vah.state<=0);
   bool longRev =InpEnableReversion && regime.balance && nearVal && bullBody && revLongOk;
   bool shortRev=InpEnableReversion && regime.balance && nearVah && bearBody && revShortOk;

   bool enterLong =longRev || longBrk;
   bool enterShort=shortRev || shortBrk;
   if(!enterLong && !enterShort) return out;
   if(enterLong && enterShort)   return out;
   if(s.entry_close<=0) return out;

   out.valid=true; out.is_long=enterLong; out.entry=s.entry_close;
   if(enterLong){
      bool isRev=longRev; double slAtrUse=isRev?InpSlAtrRev:InpSlAtrBrk;
      double sl=s.entry_close-MathMax(slAtrUse*s.atr1, 8.0*pipSize);
      if(isRev && local_cur.valid) sl=MathMin(sl, local_cur.lo-4.0*pipSize);
      double risk=s.entry_close-sl; double rr=(isRev?InpRrRev:InpRrBrk)*rrScale;
      out.is_rev=isRev; out.sl=sl; out.risk=risk;
      out.tp1=s.entry_close+risk*InpTp1R; out.tp2=s.entry_close+risk*rr;
      out.reason=isRev?"L-REV":"L-BRK";
   } else {
      bool isRev=shortRev; double slAtrUse=isRev?InpSlAtrRev:InpSlAtrBrk;
      double sl=s.entry_close+MathMax(slAtrUse*s.atr1, 8.0*pipSize);
      if(isRev && local_cur.valid) sl=MathMax(sl, local_cur.hi+4.0*pipSize);
      double risk=sl-s.entry_close; double rr=(isRev?InpRrRev:InpRrBrk)*rrScale;
      out.is_rev=isRev; out.sl=sl; out.risk=risk;
      out.tp1=s.entry_close-risk*InpTp1R; out.tp2=s.entry_close-risk*rr;
      out.reason=isRev?"S-REV":"S-BRK";
   }
   if(out.risk<=0.0){ out.valid=false; return out; }

   double atrF=(s.atr2>0.0)?s.atr2:1.0;
   if(enterLong){
      out.f_brk_dist_atr=(sVah>0.0)?(s.c-sVah)/atrF:0.0;
      out.f_runway_atr=(master_cur.hi-s.c)/atrF; out.f_node_net=ns_vah.net;
   } else {
      out.f_brk_dist_atr=(sVal>0.0)?(sVal-s.c)/atrF:0.0;
      out.f_runway_atr=(s.c-master_cur.lo)/atrF; out.f_node_net=ns_val.net;
   }
   out.f_body_pct=bodyPct; out.f_adx=regime.adx; out.f_di_spread=MathAbs(regime.plus-regime.minus);
   return out;
}

//+------------------------------------------------------------------+
//|  MVP_DetectImpulse — Monster impulse-thrust (kind 4). 1:1 with     |
//|  cpp_core kk::detect_impulse. Fires ONLY above the vol ceiling     |
//|  (caller enforces the band). SL reuses the base breakout SL.       |
//|  slopeUp/slopeDn: master-POC rising/falling over the slope         |
//|  lookback. netM1/hasM1: M1 near-price net at the decision time.    |
//+------------------------------------------------------------------+
Signal MVP_DetectImpulse(const VPResult &master_cur,const VPResult &master_pred,const SignalBar &s,
                         bool slopeUp,bool slopeDn,double netM1,bool hasM1,double pipSize)
{
   Signal out; out.valid=false; out.reason="";
   if(!InpEnableImpulse || !master_cur.valid) return out;
   if(s.c<=0||s.o<=0||s.h<=0||s.l<=0||s.h<s.l) return out;
   if(s.entry_close<=0) return out;
   double atrE=s.atr2, atrSL=s.atr1;
   if(atrE<=0.0) return out;

   double mVah=master_cur.vah, mVal=master_cur.val, mPoc=master_cur.poc;
   double pPocRef=master_pred.valid?master_pred.poc:mPoc;
   double pVahRef=master_pred.valid?master_pred.vah:mVah;
   double pValRef=master_pred.valid?master_pred.val:mVal;

   double candleH=s.h-s.l;
   bool thrustBull=(s.c>s.o)&&(candleH>=InpImpulseCandleAtr*atrE);
   bool thrustBear=(s.c<s.o)&&(candleH>=InpImpulseCandleAtr*atrE);
   bool netLongOk =hasM1 && (netM1>= InpImpulseNetMin);
   bool netShortOk=hasM1 && (netM1<=-InpImpulseNetMin);
   bool trendLong =slopeUp && (pPocRef>=mPoc);
   bool trendShort=slopeDn && (pPocRef<=mPoc);
   bool entryL=(s.c>=mVah+InpImpulseEntryBufAtr*atrE) && (InpImpulseMaxDistAtr<=0.0 || s.c<=pVahRef+InpImpulseMaxDistAtr*atrE);
   bool entryS=(s.c<=mVal-InpImpulseEntryBufAtr*atrE) && (InpImpulseMaxDistAtr<=0.0 || s.c>=pValRef-InpImpulseMaxDistAtr*atrE);

   bool longImp =thrustBull && entryL && trendLong  && netLongOk;
   bool shortImp=thrustBear && entryS && trendShort && netShortOk;
   if(longImp==shortImp) return out;   // exactly one direction

   out.is_long=longImp; out.entry=s.entry_close;
   if(longImp){
      double sl=s.entry_close-MathMax(InpSlAtrBrk*atrSL,8.0*pipSize);
      double risk=s.entry_close-sl; if(risk<=0.0) return out;
      out.sl=sl; out.risk=risk;
      out.tp1=s.entry_close+risk*InpTp1R; out.tp2=s.entry_close+risk*InpImpulseRr;
      out.reason="L-IMP";
   } else {
      double sl=s.entry_close+MathMax(InpSlAtrBrk*atrSL,8.0*pipSize);
      double risk=sl-s.entry_close; if(risk<=0.0) return out;
      out.sl=sl; out.risk=risk;
      out.tp1=s.entry_close-risk*InpTp1R; out.tp2=s.entry_close-risk*InpImpulseRr;
      out.reason="S-IMP";
   }
   out.valid=true; out.is_rev=false;
   double atrF=(atrE>0.0)?atrE:1.0;
   out.f_brk_dist_atr=longImp?(s.c-mVah)/atrF:(mVal-s.c)/atrF;
   out.f_runway_atr  =longImp?(master_cur.hi-s.c)/atrF:(s.c-master_cur.lo)/atrF;
   out.f_body_pct=MathAbs(s.c-s.o)/MathMax(candleH,pipSize); out.f_node_net=netM1;
   return out;
}

#endif // KKMVP_STRATEGY_MQH
