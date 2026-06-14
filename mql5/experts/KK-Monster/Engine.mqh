//+------------------------------------------------------------------+
//|  KK-Monster/Engine.mqh — OnTick orchestration (port of the EA      |
//|  loop in cpp_core monster_engine.hpp, minus the backtest harness). |
//|  Chart TF = entry TF (M3). Per new bar: master/local/pred VP +     |
//|  node accumulate + multi-TF near-net + fresh-cross + regime +      |
//|  EvaluateMonster + risk fill. Per tick: TP1 -> BE (-> trail).      |
//+------------------------------------------------------------------+
#ifndef KKM_ENGINE_MQH
#define KKM_ENGINE_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include "../KK-Common/Sizing.mqh"
#include "Config.mqh"
#include "Signal.mqh"

CTrade        monTrade;
CPositionInfo monPos;
MonsterConfig g_cfg;
MonNode  g_node; MonMPoc g_mph; MonCross g_cross;
int  hAtrC,hAtrM1,hAtrM5,hAtrM15;
double g_mpip=0.01,g_mtick=0.01,g_mvppl=100.0;
datetime g_monLastBar=0; int g_barIdx=0; bool g_tp1=false; double g_mbest=0;

double AtrC(int s){ double v[]; return (CopyBuffer(hAtrC,0,s,1,v)==1)?v[0]:0.0; }

// near-net at refShift on `tf` (port of tf_net_near_at / net_prev_at_time [1] read).
double MonNearNet(ENUM_TIMEFRAMES tf,int hAtr,int look,double winAtr,int refShift,bool &valid)
{
   valid=false; double refC=iClose(_Symbol,tf,refShift); if(refC<=0) return 0.0; valid=true;
   double a[]; double atr=(CopyBuffer(hAtr,0,refShift,1,a)==1)?a[0]:0.0; if(atr<=0) return 0.0;
   double win=winAtr*atr;
   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,tf,refShift,look,r)<1) return 0.0;
   double tB=0,tS=0; int n=ArraySize(r);
   for(int i=0;i<n;i++){ double p=(r[i].high+r[i].low+r[i].close)/3.0; if(MathAbs(p-refC)>win) continue;
      double rng=MathMax(r[i].high-r[i].low,g_mtick); double dp=(r[i].close-r[i].open)/rng; double v=(double)r[i].tick_volume;
      tB+=v*MathMax(dp,0.0); tS+=v*MathMax(-dp,0.0); }
   double tot=tB+tS; return (tot>0)?(tB-tS)/tot:0.0;
}

// master VP at shift `sh` from a shift-indexed window (h/l/c/v sized total).
void MasterVPAt(const double &h[],const double &l[],const double &c[],const long &v[],int total,int sh,MVP &m,MVP &loc,MVP &pred)
{
   MonComputeVP(h,l,c,v,total,sh,g_cfg.master_len(),g_cfg.vp_bins,g_cfg.va_pct,0,m);
   MonComputeVP(h,l,c,v,total,sh,g_cfg.vp_lookback,g_cfg.vp_bins,g_cfg.va_pct,0,loc);
   pred.valid=false;
   if(g_cfg.impulse_predict_bars>0) MonComputeVP(h,l,c,v,total,sh,g_cfg.master_len(),g_cfg.vp_bins,g_cfg.va_pct,g_cfg.impulse_predict_bars,pred);
}

int OnInit()
{
   FillMonsterConfig(g_cfg);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(StringFind(_Symbol,"BTCUSD")>=0) g_mpip=1.0; else g_mpip=MathPow(10.0,-digits);
   g_mtick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); if(g_mtick<=0) g_mtick=g_mpip;
   g_cfg.pip_size=g_mpip; g_cfg.mintick=g_mtick;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE), ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   g_mvppl=(ts>0)?tv/ts:SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   hAtrC =iATR(_Symbol,PERIOD_CURRENT,g_cfg.atr_len);
   hAtrM1=iATR(_Symbol,PERIOD_M1,g_cfg.atr_len);
   hAtrM5=iATR(_Symbol,PERIOD_M5,g_cfg.atr_len);
   hAtrM15=iATR(_Symbol,PERIOD_M15,g_cfg.atr_len);
   g_node.Init(g_cfg.vp_bins); g_mph.Init(g_cfg.impulse_trend_slope_bars); g_cross.Init();
   monTrade.SetExpertMagicNumber(InpMonMagic); monTrade.SetTypeFillingBySymbol(_Symbol); monTrade.SetDeviationInPoints(g_cfg.deviation_points);

   // warmup: replay node/cross/mph over recent history (oldest->newest).
   int WARM=120, W=WARM+g_cfg.master_len()+30;
   double h[],l[],c[]; long v[]; MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,PERIOD_CURRENT,0,W,r)>g_cfg.master_len()){
      int tot=ArraySize(r); ArrayResize(h,tot);ArrayResize(l,tot);ArrayResize(c,tot);ArrayResize(v,tot);
      for(int i=0;i<tot;i++){ h[i]=r[i].high; l[i]=r[i].low; c[i]=r[i].close; v[i]=r[i].tick_volume; }
      for(int sh=MathMin(WARM,tot-g_cfg.master_len());sh>=1;sh--){
         MVP m,loc,pred; MasterVPAt(h,l,c,v,tot,sh,m,loc,pred);
         if(!m.valid) continue;
         g_node.Accumulate(iOpen(_Symbol,PERIOD_CURRENT,sh),h[sh],l[sh],c[sh],(double)v[sh],AtrC(sh),m,g_cfg);
         MonRegime reg; g_mph.ComputeRegime(AtrC(sh),m.poc,pred.valid,pred.poc,g_cfg,reg);
         g_cross.UpdateFresh(c[sh],m,g_barIdx); g_mph.Push(m.poc); g_barIdx++;
      }
   }
   PrintFormat("[KK-Monster] init pip=%.5f vppl=%.2f masterLen=%d warmIdx=%d",g_mpip,g_mvppl,g_cfg.master_len(),g_barIdx);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r){ IndicatorRelease(hAtrC);IndicatorRelease(hAtrM1);IndicatorRelease(hAtrM5);IndicatorRelease(hAtrM15); }

bool MonHasPos(){ for(int i=PositionsTotal()-1;i>=0;i--){ if(!monPos.SelectByIndex(i)) continue; if(monPos.Symbol()==_Symbol&&monPos.Magic()==InpMonMagic) return true; } return false; }

void MonOnNewBar()
{
   int W=g_cfg.master_len()+60; MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,PERIOD_CURRENT,0,W,r)<=g_cfg.master_len()) return;
   int tot=ArraySize(r); double h[],l[],c[]; long v[]; ArrayResize(h,tot);ArrayResize(l,tot);ArrayResize(c,tot);ArrayResize(v,tot);
   for(int i=0;i<tot;i++){ h[i]=r[i].high; l[i]=r[i].low; c[i]=r[i].close; v[i]=r[i].tick_volume; }
   MVP m,loc,pred; MasterVPAt(h,l,c,v,tot,1,m,loc,pred); if(!m.valid) return;
   double atr1=AtrC(1); double o1=iOpen(_Symbol,PERIOD_CURRENT,1);
   g_node.Accumulate(o1,h[1],l[1],c[1],(double)v[1],atr1,m,g_cfg);
   MonNet net; net.netM1=0;net.netM3=0;net.netM5=0;net.netM15=0; net.hasM1=false;net.hasM5=false;net.hasM15=false; net.ovhRawLong=false; net.ovhRawShort=false;
   net.netM3=g_node.NetM3W(c[1],atr1,g_cfg);
   net.netM1=MonNearNet(PERIOD_M1,hAtrM1,g_cfg.tf_net_look,g_cfg.net_win_atr,2,net.hasM1);
   net.netM5=MonNearNet(PERIOD_M5,hAtrM5,g_cfg.tf_net_look,g_cfg.net_win_atr,2,net.hasM5);
   if(g_cfg.enable_htf_bias) net.netM15=MonNearNet(PERIOD_M15,hAtrM15,g_cfg.tf_net_look,g_cfg.net_win_atr,2,net.hasM15);
   g_cross.UpdateFresh(c[1],m,g_barIdx);
   MonRegime reg; g_mph.ComputeRegime(atr1,m.poc,pred.valid,pred.poc,g_cfg,reg);

   double atrFrac=(c[1]>0)?atr1/c[1]:0.0;
   bool ceilOk=(g_cfg.max_atr_pct<=0)||(atrFrac<=g_cfg.max_atr_pct);
   bool inBand=(g_cfg.max_atr_pct>0)&&(atrFrac>g_cfg.max_atr_pct);
   bool floorOk=(g_cfg.min_atr_pct<=0)||(atrFrac>=g_cfg.min_atr_pct);
   MonSignal L,Sx; EvaluateMonster(g_cfg,o1,h[1],l[1],c[1],m,loc,pred,reg,atr1,atrFrac,ceilOk,inBand,g_barIdx,g_node,g_cross,net,L,Sx);
   g_mph.Push(m.poc);

   if(floorOk && !MonHasPos()){
      MonSignal sig; bool have=false;
      if(L.valid){ sig=L; have=true; } else if(Sx.valid){ sig=Sx; have=true; }
      if(have){
         double spread=SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double entry=sig.is_long?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double sl=sig.sl, tp=sig.tp2, risk0=MathAbs(entry-sl);
         if(risk0>0){
            double minDist=KKMinStopDist(_Symbol); KKClampStops(sig.is_long,entry,minDist,sl,tp);
            double risk=MathAbs(entry-sl);
            if(risk>0){
               double lot=KKPositionSize(AccountInfoDouble(ACCOUNT_BALANCE),g_cfg.risk_acc_pct*0.01,risk,g_mvppl,
                          SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),(g_cfg.max_lot>0?g_cfg.max_lot:SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP));
               sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
               bool ok=sig.is_long?monTrade.Buy(lot,_Symbol,0.0,sl,tp,sig.reason):monTrade.Sell(lot,_Symbol,0.0,sl,tp,sig.reason);
               if(ok){ g_tp1=false; g_mbest=entry; if(sig.is_long) g_cross.lastLongEntryBar=g_barIdx; else g_cross.lastShortEntryBar=g_barIdx; g_cross.Consume(sig.kind,sig.is_long); }
            }
         }
      }
   }
   g_barIdx++;
}

void MonManage()
{
   if(!MonHasPos()){ g_tp1=false; g_mbest=0; return; }
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!monPos.SelectByIndex(i)) continue;
      if(monPos.Symbol()!=_Symbol||monPos.Magic()!=InpMonMagic) continue;
      bool isLong=(monPos.PositionType()==POSITION_TYPE_BUY); ulong tk=monPos.Ticket();
      double entry=monPos.PriceOpen(),sl=monPos.StopLoss(),tp=monPos.TakeProfit(),vol=monPos.Volume();
      double price=isLong?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double risk=MathAbs(entry-sl); if(risk<=0) continue; double minDist=KKMinStopDist(_Symbol);
      if(g_mbest==0) g_mbest=entry; if(isLong){ if(price>g_mbest) g_mbest=price; } else { if(price<g_mbest) g_mbest=price; }
      if(!g_tp1){
         double tp1=isLong?entry+risk*g_cfg.tp1_rr_brk:entry-risk*g_cfg.tp1_rr_brk;
         bool hit=isLong?(price>=tp1):(price<=tp1);
         if(hit){ double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            double q=vol*0.5; if(step>0) q=MathFloor(q/step)*step; if(q>=mn&&q<vol) monTrade.PositionClosePartial(tk,q);
            g_tp1=true; double be=isLong?entry+g_cfg.be_buf_atr*AtrC(1):entry-g_cfg.be_buf_atr*AtrC(1); be=NormalizeDouble(be,_Digits);
            bool okS=(isLong&&be>sl)||(!isLong&&be<sl), okD=(isLong?(price-be>=minDist):(be-price>=minDist)); if(okS&&okD) monTrade.PositionModify(tk,be,tp); }
      }
      if(g_tp1&&g_cfg.trail_runner){ double atr1=AtrC(1); double trail=isLong?g_mbest-g_cfg.trail_atr_mult*atr1:g_mbest+g_cfg.trail_atr_mult*atr1; trail=NormalizeDouble(trail,_Digits);
         double cur=monPos.StopLoss(); bool okS=(isLong&&trail>cur)||(!isLong&&trail<cur), okD=(isLong?(price-trail>=minDist):(trail-price>=minDist)); if(okS&&okD) monTrade.PositionModify(tk,trail,monPos.TakeProfit()); }
   }
}

void OnTick(){ MonManage(); datetime t=iTime(_Symbol,PERIOD_CURRENT,0); if(t==g_monLastBar) return; g_monLastBar=t; MonOnNewBar(); }

#endif // KKM_ENGINE_MQH
