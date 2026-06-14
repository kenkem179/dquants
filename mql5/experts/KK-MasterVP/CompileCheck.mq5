//+------------------------------------------------------------------+
//|  KK-MasterVP/CompileCheck.mq5 — compiles the VP-Common foundation |
//|  + MasterVP inputs/strategy in isolation (no broker logic yet).   |
//|  The OnTick orchestration integrator is the next step.            |
//+------------------------------------------------------------------+
#property strict

#include "../VP-Common/Types.mqh"
#include "../VP-Common/VolumeProfile.mqh"
#include "../VP-Common/Regime.mqh"
#include "../VP-Common/NodeEngine.mqh"
#include "Inputs.mqh"
#include "Strategy.mqh"

CNodeEngine g_node;

int OnInit()
{
   g_node.Init(InpVpBins*InpMasterMult);
   // Exercise the foundation so the compiler type-checks it end to end.
   double h[3]={11,12,13}, l[3]={9,10,11}, c[3]={10,11,12}; long v[3]={5,7,6};
   VPResult vp=VP_ComputeBars(h,l,c,v,3,InpVpBins,InpVaPct);
   RegimeState rg=VP_ComputeRegime(1.0,10,9,30,28,8,InpAdxTrendMin,InpDiSpreadMin,InpEmaSepAtr);
   g_node.Update(vp,10,12,9,11,6,1.0,0.01,0.01,InpNodeTouchAtr,InpNodeDecay);
   NodeState ns=g_node.StateAtPrice(11.0,InpNodeSaturation,InpNodeNeutralBand);
   SignalBar sb; sb.o=10; sb.h=12; sb.l=9; sb.c=11.5; sb.atr2=1.0; sb.atr1=1.0; sb.entry_close=11.5;
   Signal sig=MVP_DetectSignal(vp,vp,vp,rg,sb,ns,ns,ns,0.01,0.01,1.0);
   PrintFormat("[MVP CompileCheck] vp.valid=%d regime.trend=%d sig.valid=%d",vp.valid,rg.trend,sig.valid);
   return INIT_SUCCEEDED;
}
void OnTick(){}
//+------------------------------------------------------------------+
