//+------------------------------------------------------------------+
//|  KK-MasterVP/Engine.mqh — OnTick orchestration (port of the EA    |
//|  OnTick loop inside cpp_core mastervp/tick_engine.hpp, minus the   |
//|  backtest harness). Per new bar: master VP (lookback*mult) + local |
//|  VP + node update + regime + DetectSignal(shift-2 bar) + essential |
//|  gates + risk-correct fill. Per tick: TP1 -> BE -> ATR trail.      |
//|  Distilled: heavy DD-breaker/session suite deferred (shared infra).|
//+------------------------------------------------------------------+
#ifndef KKMVP_ENGINE_MQH
#define KKMVP_ENGINE_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include "../KK-Common/Indicators.mqh"
#include "../KK-Common/Sizing.mqh"
#include "../VP-Common/Types.mqh"
#include "../VP-Common/VolumeProfile.mqh"
#include "../VP-Common/Regime.mqh"
#include "../VP-Common/NodeEngine.mqh"
#include "Inputs.mqh"
#include "Strategy.mqh"

CTrade        mvpTrade;
CPositionInfo mvpPos;
CNodeEngine   g_node;
int  hAtr,hRsi,hAdx,hEmaF,hEmaS,hM15EmaF,hM15EmaS;
double g_pip=0.01,g_mintick=0.01,g_vppl=100.0;
datetime g_mvpLastBar=0;
int  g_masterLen=150;
// per-position management state
bool   g_tp1Done=false; double g_best=0.0;

double AtrAt(int s){ return KKBuf(hAtr,0,s); }

// VP over `count` bars ending at shift `startShift` (newest at startShift, going back).
bool VPWindow(int startShift,int count,VPResult &out)
{
   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,PERIOD_CURRENT,startShift,count,r)<count){ out.valid=false; return false; }
   double h[],l[],c[]; long v[]; ArrayResize(h,count); ArrayResize(l,count); ArrayResize(c,count); ArrayResize(v,count);
   for(int i=0;i<count;i++){ h[i]=r[i].high; l[i]=r[i].low; c[i]=r[i].close; v[i]=r[i].tick_volume; }
   out=VP_ComputeBars(h,l,c,v,count,InpVpBins,InpVaPct);
   return out.valid;
}

int OnInit()
{
   hAtr =iATR(_Symbol,PERIOD_CURRENT,InpAtrLen);
   hRsi =iRSI(_Symbol,PERIOD_CURRENT,14,PRICE_CLOSE);
   hAdx =iADX(_Symbol,PERIOD_CURRENT,InpAdxLen);
   hEmaF=iMA(_Symbol,PERIOD_CURRENT,InpEmaFast,0,MODE_EMA,PRICE_CLOSE);
   hEmaS=iMA(_Symbol,PERIOD_CURRENT,InpEmaSlow,0,MODE_EMA,PRICE_CLOSE);
   hM15EmaF=iMA(_Symbol,PERIOD_M15,InpEmaFast,0,MODE_EMA,PRICE_CLOSE);
   hM15EmaS=iMA(_Symbol,PERIOD_M15,InpEmaSlow,0,MODE_EMA,PRICE_CLOSE);
   g_masterLen=InpVpLookback*InpMasterMult;
   g_node.Init(InpVpBins);

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(StringFind(_Symbol,"BTCUSD")>=0){ g_pip=1.0; g_mintick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); }
   else { g_pip=MathPow(10.0,-digits); g_mintick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); }
   if(g_mintick<=0) g_mintick=g_pip;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE), ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   g_vppl=(ts>0)?tv/ts:SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);

   mvpTrade.SetExpertMagicNumber(InpMVPMagic);
   mvpTrade.SetTypeFillingBySymbol(_Symbol);
   mvpTrade.SetDeviationInPoints(InpDeviationPoints);
   PrintFormat("[KK-MasterVP] init pip=%.5f vppl=%.2f masterLen=%d",g_pip,g_vppl,g_masterLen);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r){
   IndicatorRelease(hAtr);IndicatorRelease(hRsi);IndicatorRelease(hAdx);IndicatorRelease(hEmaF);IndicatorRelease(hEmaS);
   IndicatorRelease(hM15EmaF);IndicatorRelease(hM15EmaS);
}

bool MvpHasPosition(){
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!mvpPos.SelectByIndex(i)) continue;
      if(mvpPos.Symbol()==_Symbol && mvpPos.Magic()==InpMVPMagic) return true; } return false;
}

// MTF (M15 EMA shift1) + RSI(shift1) quality gate.
bool QualityOk(bool isLong)
{
   double hf=KKBuf(hM15EmaF,0,1), hs=KKBuf(hM15EmaS,0,1);
   if(hf>0.0 && hs>0.0){
      bool bull=hf>hs, bear=hf<hs;          // mtf_hard_veto
      if(isLong && !bull) return false;
      if(!isLong && !bear) return false;
   }
   double rsi=KKBuf(hRsi,0,1);
   if(rsi>0.0){ if(isLong && rsi<50.0) return false; if(!isLong && rsi>50.0) return false; }
   return true;
}

void OnNewBar()
{
   // master VP + node update through the just-closed bar (shift 1), then local VP + regime.
   VPResult masterCur; if(!VPWindow(1,g_masterLen,masterCur)) return;
   // node update for the just-closed bar (shift 1) on the master grid
   g_node.Update(masterCur,iOpen(_Symbol,PERIOD_CURRENT,1),iHigh(_Symbol,PERIOD_CURRENT,1),
                 iLow(_Symbol,PERIOD_CURRENT,1),iClose(_Symbol,PERIOD_CURRENT,1),
                 (long)iVolume(_Symbol,PERIOD_CURRENT,1),AtrAt(1),g_pip,g_mintick,InpNodeTouchAtr,InpNodeDecay);
   VPResult localCur; VPWindow(1,InpVpLookback,localCur);
   RegimeState regime=VP_ComputeRegime(AtrAt(1),KKBuf(hEmaF,0,1),KKBuf(hEmaS,0,1),
                                       KKBuf(hAdx,0,1),KKBuf(hAdx,1,1),KKBuf(hAdx,2,1),
                                       InpAdxTrendMin,InpDiSpreadMin,InpEmaSepAtr);
   // signal bar = shift 2; entry anchor = close[1]
   SignalBar s; s.o=iOpen(_Symbol,PERIOD_CURRENT,2); s.h=iHigh(_Symbol,PERIOD_CURRENT,2);
   s.l=iLow(_Symbol,PERIOD_CURRENT,2); s.c=iClose(_Symbol,PERIOD_CURRENT,2);
   s.atr2=AtrAt(2); s.atr1=AtrAt(1); s.entry_close=iClose(_Symbol,PERIOD_CURRENT,1);
   NodeState nsVah=g_node.StateAtPrice(masterCur.vah,InpNodeSaturation,InpNodeNeutralBand);
   NodeState nsVal=g_node.StateAtPrice(masterCur.val,InpNodeSaturation,InpNodeNeutralBand);
   NodeState nsPx =g_node.StateAtPrice(s.c,InpNodeSaturation,InpNodeNeutralBand);
   Signal sig=MVP_DetectSignal(masterCur,masterCur,localCur,regime,s,nsVah,nsVal,nsPx,g_pip,g_mintick,1.0);
   if(!sig.valid) return;

   if(MvpHasPosition()) return;
   if(!QualityOk(sig.is_long)) return;
   // ATR% band gate
   double atrPct=(s.entry_close>0)?AtrAt(1)/s.entry_close*100.0:0.0;
   if(atrPct< (InpAtrLen>0?0.0:0.0)) {}   // (min/max ATR% breakers deferred — see header)
   // spread gate
   double spread=SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(spread> 40.0*g_pip) return;

   double entry=sig.is_long?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double risk=MathAbs(entry-sig.sl); if(risk<=0) return;
   double minDist=KKMinStopDist(_Symbol);
   double sl=sig.sl, tp=sig.tp2;
   KKClampStops(sig.is_long,entry,minDist,sl,tp);
   risk=MathAbs(entry-sl); if(risk<=0) return;
   double lot=KKPositionSize(AccountInfoDouble(ACCOUNT_BALANCE),InpRiskAccPct*0.01,risk,g_vppl,
                             SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),
                             (InpMaxLot>0?InpMaxLot:SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)),
                             SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP));
   sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
   bool ok=sig.is_long?mvpTrade.Buy(lot,_Symbol,0.0,sl,tp,sig.reason):mvpTrade.Sell(lot,_Symbol,0.0,sl,tp,sig.reason);
   if(ok){ g_tp1Done=false; g_best=entry; }
}

// Per-tick: TP1 partial -> BE, then ATR chandelier trail (tighten-only).
void MvpManage()
{
   if(!MvpHasPosition()) { g_tp1Done=false; g_best=0; return; }
   mvpPos.SelectByIndex(0);   // single position by design (flat-check before entry)
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!mvpPos.SelectByIndex(i)) continue;
      if(mvpPos.Symbol()!=_Symbol||mvpPos.Magic()!=InpMVPMagic) continue;
      bool isLong=(mvpPos.PositionType()==POSITION_TYPE_BUY);
      ulong tk=mvpPos.Ticket(); double entry=mvpPos.PriceOpen(), sl=mvpPos.StopLoss(), tp=mvpPos.TakeProfit(), vol=mvpPos.Volume();
      double price=isLong?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double risk=MathAbs(entry-sl); if(risk<=0) continue;
      double minDist=KKMinStopDist(_Symbol);
      if(g_best==0) g_best=entry;
      if(isLong){ if(price>g_best) g_best=price; } else { if(price<g_best) g_best=price; }
      // TP1 partial -> BE
      if(!g_tp1Done){
         double tp1=isLong?entry+risk*InpTp1R:entry-risk*InpTp1R;
         bool hit=isLong?(price>=tp1):(price<=tp1);
         if(hit){
            double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            double q=vol*(InpTp1ClosePct*0.01); if(step>0) q=MathFloor(q/step)*step;
            if(q>=mn && q<vol) mvpTrade.PositionClosePartial(tk,q);
            g_tp1Done=true;
            if(InpBeAfterTp1){
               double be=isLong?entry+InpBeBufAtr*AtrAt(1):entry-InpBeBufAtr*AtrAt(1); be=NormalizeDouble(be,_Digits);
               bool okSide=(isLong&&be>sl)||(!isLong&&be<sl), okDist=(isLong?(price-be>=minDist):(be-price>=minDist));
               if(okSide&&okDist) mvpTrade.PositionModify(tk,be,tp);
            }
         }
      }
      // ATR chandelier trail (after TP1), tighten-only
      if(g_tp1Done && InpTrailRunner){
         double atr1=AtrAt(1);
         double trail=isLong?g_best-InpTrailAtrMult*atr1:g_best+InpTrailAtrMult*atr1; trail=NormalizeDouble(trail,_Digits);
         double cur=mvpPos.StopLoss();
         bool okSide=(isLong&&trail>cur)||(!isLong&&trail<cur), okDist=(isLong?(price-trail>=minDist):(trail-price>=minDist));
         if(okSide&&okDist) mvpTrade.PositionModify(tk,trail,mvpPos.TakeProfit());
      }
   }
}

void OnTick()
{
   MvpManage();
   datetime t=iTime(_Symbol,PERIOD_CURRENT,0);
   if(t==g_mvpLastBar) return;
   g_mvpLastBar=t;
   OnNewBar();
}

#endif // KKMVP_ENGINE_MQH
