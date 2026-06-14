#property strict
#include "Config.mqh"
#include "Signal.mqh"
MonNode g_n; MonMPoc g_mp; MonCross g_cr;
int OnInit(){
   MonsterConfig cfg; FillMonsterConfig(cfg);
   g_n.Init(cfg.vp_bins); g_mp.Init(cfg.impulse_trend_slope_bars); g_cr.Init();
   double h[3]={12,13,14},l[3]={10,11,12},c[3]={11,12,13}; long v[3]={5,6,7};
   MVP m; MonComputeVP(h,l,c,v,3,0,3,cfg.vp_bins,cfg.va_pct,0,m);
   g_n.Accumulate(11,13,10,12,6,1.0,m,cfg);
   MonRegime reg; g_mp.ComputeRegime(1.0,m.poc,false,0,cfg,reg);
   g_cr.UpdateFresh(12,m,5);
   MonNet net; net.netM1=0;net.netM3=0.9;net.netM5=0.5;net.netM15=0; net.hasM1=true;net.hasM5=true;net.hasM15=false; net.ovhRawLong=false;net.ovhRawShort=false;
   MonSignal L,Sx; EvaluateMonster(cfg,11,13,10,12,m,m,m,reg,1.0,0.1,true,false,5,g_n,g_cr,net,L,Sx);
   PrintFormat("[Monster CC] vp=%d Lvalid=%d Svalid=%d",m.valid,L.valid,Sx.valid);
   return INIT_SUCCEEDED;
}
void OnTick(){}
