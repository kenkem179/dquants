//+------------------------------------------------------------------+
//|  KK-MasterVP/ProfitManager.mqh                                    |
//|  1:1 MQL5 port of cpp_core kk::common::pm_evaluate                 |
//|  (cpp_core/include/kk/common/profit_manager.hpp).                  |
//|                                                                    |
//|  PURE: takes a snapshot of one open trade + the InpPm* toggles and |
//|  returns the (tighter) SL, (further) TP and a one-shot partial     |
//|  fraction. The caller merges tighten-only / extend-only EXACTLY    |
//|  like the headless engine, so the SAME InpPm .set reproduces the   |
//|  engine's profit-lock behaviour in MT5.                            |
//|                                                                    |
//|  DEFAULT = every toggle OFF => MvpPmEvaluate returns the inputs     |
//|  unchanged (sl, tp, partial_frac=0) => the EA is byte-for-byte     |
//|  identical to its pre-ProfitManager behaviour. Guard each per-tick  |
//|  call with MvpPmAny() so an all-OFF config is provably inert.      |
//+------------------------------------------------------------------+
#ifndef KKMVP_PROFITMANAGER_MQH
#define KKMVP_PROFITMANAGER_MQH

struct MvpPmActions { double sl; double tp; double partial_frac; };

// True if any profit-lock toggle is enabled (mirrors kk::common::pm_any).
bool MvpPmAny()
{
   return InpPmBeProtect || InpPmProgTrail || InpPmGiveback || InpPmTpExtension
       || InpPmPreBeStructure || InpPmPartialTp;
}

// Stateless evaluation of all enabled toggles. Same (state, cfg) -> same actions.
//   isLong/entry/sl/tp        : direction + current stop/target (absolute prices)
//   curPrice                  : current EXIT-side price (long->bid, short->ask)
//   bestPrice                 : MFE high-water on that same exit side
//   risk                      : ORIGINAL risk in price (|entry - initial SL|), captured at fill
//   atr                       : live ATR (price)
//   tpExtensions/partialDone  : engine-owned hysteresis (extensions taken, PM partial already done)
//   beDone                    : breakeven already applied (gates pre_be_structure)
//   structureLevel/trendWeak  : optional engine feeds (0 / false here, same as the cpp engine)
MvpPmActions MvpPmEvaluate(bool isLong,double entry,double sl,double tp,double curPrice,
                           double bestPrice,double risk,double atr,int tpExtensions,
                           bool partialDone,bool beDone,double structureLevel,bool trendWeakening)
{
   MvpPmActions a; a.sl=sl; a.tp=tp; a.partial_frac=0.0;
   if(risk<=0.0) return a;

   double dir       = isLong ? 1.0 : -1.0;
   double cur_gain  = (curPrice  - entry) * dir;   // signed -> favourable when > 0
   double peak_gain = (bestPrice - entry) * dir;
   double cur_r     = cur_gain  / risk;
   double peak_r    = peak_gain / risk;

   // (1) be_protect
   if(InpPmBeProtect && InpPmBeTriggerR>0.0 && cur_r>=InpPmBeTriggerR){
      double cand=entry+dir*InpPmBeBufferR*risk;
      if(isLong){ if(cand>a.sl) a.sl=cand; } else { if(cand<a.sl) a.sl=cand; }
   }

   // (5) pre_be_structure (kept strictly inside entry so it never crosses to profit-lock)
   if(InpPmPreBeStructure && !beDone && structureLevel>0.0
      && InpPmPreBeTriggerR>0.0 && cur_r>=InpPmPreBeTriggerR){
      double cand=structureLevel-dir*InpPmPreBeBuffer;
      double margin=isLong?(entry-1e-9):(entry+1e-9);
      if(isLong) cand=MathMin(cand,margin); else cand=MathMax(cand,margin);
      bool below_entry=isLong?(cand<entry):(cand>entry);
      if(below_entry){ if(isLong){ if(cand>a.sl) a.sl=cand; } else { if(cand<a.sl) a.sl=cand; } }
   }

   // (2) progressive_trail — SL -> entry at trigger, then advances step_r per increment_r of extra gain.
   if(InpPmProgTrail && InpPmProgTriggerR>=0.0 && InpPmProgIncrementR>0.0 && cur_r>=InpPmProgTriggerR){
      double over=cur_r-InpPmProgTriggerR;
      double steps=MathFloor(over/InpPmProgIncrementR);
      double shift_r=MathMax(0.0,steps)*InpPmProgStepR;       // SL = entry + shift_r*risk
      double cand=entry+dir*shift_r*risk;
      if(isLong){ if(cand>a.sl) a.sl=cand; } else { if(cand<a.sl) a.sl=cand; }
   }

   // (3) giveback_cap — lock >= (1 - cap_frac) of peak gain once MFE is armed.
   if(InpPmGiveback && InpPmGivebackArmR>0.0 && peak_r>=InpPmGivebackArmR && peak_gain>0.0){
      double locked=(1.0-InpPmGivebackCapFrac)*peak_gain;     // >= 0
      double cand=entry+dir*locked;
      if(isLong){ if(cand>a.sl) a.sl=cand; } else { if(cand<a.sl) a.sl=cand; }
   }

   // (4) tp_extension — extend the final TP while price nears it and the trend has NOT weakened.
   if(InpPmTpExtension && !trendWeakening && tpExtensions<InpPmTpExtMax && atr>0.0){
      double total=(tp-entry)*dir;
      double remaining=(tp-curPrice)*dir;
      if(total>0.0 && remaining>0.0){
         double progress=(total-remaining)/total;
         if(progress>=InpPmTpExtProgress) a.tp=tp+dir*InpPmTpExtAtrMult*atr;
      }
   }

   // (6) partial_tp — one-shot fractional close at an R trigger.
   if(InpPmPartialTp && !partialDone && InpPmPartialTriggerR>0.0
      && InpPmPartialFrac>0.0 && cur_r>=InpPmPartialTriggerR){
      a.partial_frac=MathMin(1.0,InpPmPartialFrac);
   }

   return a;
}
#endif
