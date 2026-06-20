//+------------------------------------------------------------------+
//|  KK-MasterVP/Engine.mqh — OnTick orchestration. Faithful port of   |
//|  cpp_core kk::mastervp::TickEngine (signal + FULL safety gate      |
//|  stack), minus the backtest harness. Per new bar: master VP        |
//|  (lookback*mult) + local VP + node update + regime +               |
//|  DetectSignal(shift-2) + gate stack (quality -> session -> ATR     |
//|  floor -> spread -> max-trades -> daily-DD -> blocked-hour ->       |
//|  peak-DD -> cooldown -> news) + risk-correct fill. Per tick: TP1 -> |
//|  BE -> ATR chandelier trail.                                       |
//|                                                                    |
//|  Gate order & formulas mirror tick_engine.hpp / filters.hpp /      |
//|  risk_manager.hpp 1:1. NOTE: the news blackout is a LIVE-ONLY       |
//|  safety overlay (the C++ backtest had no calendar, so it is not     |
//|  reflected in the locked PF); default OFF.                         |
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
#include "Decision.mqh"
#include "SessionNews.mqh"
#include "Parity.mqh"

CTrade        mvpTrade;
CPositionInfo mvpPos;
CNodeEngine   g_node;
int  hAtr,hRsi,hAdx,hEmaF,hEmaS,hHtfEmaF,hHtfEmaS;
double g_pip=0.01,g_mintick=0.01,g_vppl=100.0;
datetime g_mvpLastBar=0;
int  g_masterLen=480;
// per-position management state
bool   g_tp1Done=false; double g_best=0.0;
// risk-manager state (port of RiskManager.mqh)
double   g_peakEquity=0.0, g_dayStartEquity=0.0;
int      g_lastDayKey=-1;
datetime g_cooldownUntil=0;

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
   hRsi =iRSI(_Symbol,PERIOD_CURRENT,InpRsiLen,PRICE_CLOSE);
   hAdx =iADX(_Symbol,PERIOD_CURRENT,InpAdxLen);
   hEmaF=iMA(_Symbol,PERIOD_CURRENT,InpEmaFast,0,MODE_EMA,PRICE_CLOSE);
   hEmaS=iMA(_Symbol,PERIOD_CURRENT,InpEmaSlow,0,MODE_EMA,PRICE_CLOSE);
   hHtfEmaF=iMA(_Symbol,PERIOD_M15,InpEmaFast,0,MODE_EMA,PRICE_CLOSE);
   hHtfEmaS=iMA(_Symbol,PERIOD_M15,InpEmaSlow,0,MODE_EMA,PRICE_CLOSE);
   g_masterLen=InpVpLookback*InpMasterMult;
   g_node.Init(InpVpBins);
   SN_Init();

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(StringFind(_Symbol,"BTCUSD")>=0){ g_pip=1.0; g_mintick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); }
   else { g_pip=MathPow(10.0,-digits); g_mintick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); }
   if(g_mintick<=0) g_mintick=g_pip;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE), ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   g_vppl=(ts>0)?tv/ts:SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);

   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEquity=g_peakEquity; g_lastDayKey=-1; g_cooldownUntil=0;

   mvpTrade.SetExpertMagicNumber(InpMVPMagic);
   mvpTrade.SetTypeFillingBySymbol(_Symbol);
   mvpTrade.SetDeviationInPoints(InpDeviationPoints);
   ParityInit();
   PrintFormat("[KK-MasterVP] init pip=%.5f vppl=%.2f masterLen=%d (VP %dx%d)",
               g_pip,g_vppl,g_masterLen,InpVpLookback,InpMasterMult);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r){
   IndicatorRelease(hAtr);IndicatorRelease(hRsi);IndicatorRelease(hAdx);IndicatorRelease(hEmaF);IndicatorRelease(hEmaS);
   IndicatorRelease(hHtfEmaF);IndicatorRelease(hHtfEmaS);
   ParityClose();
}

// Trade-level parity: capture realized P&L + exit reason as each position closes (tester-only).
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &req,const MqlTradeResult &res){
   if(!InpExportParity) return;
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=(long)InpMVPMagic) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   ParityOnDealOut(trans.deal,trans.position);
}

bool MvpHasPosition(){
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!mvpPos.SelectByIndex(i)) continue;
      if(mvpPos.Symbol()==_Symbol && mvpPos.Magic()==InpMVPMagic) return true; } return false;
}

// ----- risk-manager ports (RiskManager.mqh) -----
double RiskBudgetUsd(){
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double pct=MathMax(bal*InpRiskAccPct/100.0,0.0);
   switch(InpRiskUnit){
      case 1:  return InpRiskUsd;
      case 2:  return MathMin(InpRiskUsd,pct);
      case 3:  return MathMax(InpRiskUsd,pct);
      default: return pct;
   }
}
double PeakDDPct(double eq){ if(g_peakEquity<=0) return 0.0; double dd=(g_peakEquity-eq)/g_peakEquity*100.0; return dd>0?dd:0.0; }
bool IsPeakDDHalt(double eq){ return InpMaxPeakDDPct>0.0 && PeakDDPct(eq)>=InpMaxPeakDDPct; }
double PeakDDLotMult(double eq){ if(InpSoftBlockDDPct<=0.0) return 1.0; return PeakDDPct(eq)>=InpSoftBlockDDPct?InpSoftBlockLotMult:1.0; }
// Predictive daily-DD: adds the next trade's worst-case loss so one trade can't open through the cap.
bool IsDailyDDHit(double eq,double nextRiskBudget){
   if(InpMaxDailyDDPct<=0.0 || g_dayStartEquity<=0.0) return false;
   double proj=MathMax(0.0,(g_dayStartEquity-eq+nextRiskBudget)/g_dayStartEquity*100.0);
   return proj>=InpMaxDailyDDPct;
}
bool IsInCooldown(){ return g_cooldownUntil>0 && TimeCurrent()<g_cooldownUntil; }
void ArmCooldown(double hours){
   if(hours<=0.0) return;
   datetime until=TimeCurrent()+(datetime)(hours*3600.0);
   if(until>g_cooldownUntil) g_cooldownUntil=until;   // extend-only
}

// NOTE: the MTF/RSI quality gate now lives in Decision.mqh as MVP_QualityOk()
// (pure, shared with the Profiler indicator); the EA reads the buffer values and
// calls it via MVP_DeterministicGatesPass() in OnNewBar.

void OnNewBar()
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   // Session/day context in the reference tz (UTC + InpBrokerGMTOffset), as the C++ engine does.
   datetime barServer=iTime(_Symbol,PERIOD_CURRENT,1);
   datetime ref=SN_RefTime(barServer);
   datetime utc=SN_UtcTime(barServer);
   MqlDateTime rdt; TimeToStruct(ref,rdt);
   int dayKey=rdt.year*10000+rdt.mon*100+rdt.day;
   int sessionId=SN_UpdateSession(ref);
   if(g_dayStartEquity<=0.0 || dayKey!=g_lastDayKey){ g_dayStartEquity=eq; g_lastDayKey=dayKey; }
   // arm the daily-DD cooldown the moment realized daily DD breaches the cap (no extra risk).
   if(InpDailyDDCooldownHrs>0.0 && IsDailyDDHit(eq,0.0)) ArmCooldown(InpDailyDDCooldownHrs);

   // Force-close out of session (news inert here; matches force_close_sess_news).
   if(InpForceCloseSessNews && MvpHasPosition() && sessionId==0){
      mvpPos.SelectByIndex(0);
      for(int i=PositionsTotal()-1;i>=0;i--){ if(!mvpPos.SelectByIndex(i)) continue;
         if(mvpPos.Symbol()==_Symbol && mvpPos.Magic()==InpMVPMagic) mvpTrade.PositionClose(mvpPos.Ticket()); }
   }

   // master VP + node update through the just-closed bar (shift 1), then local VP + regime.
   VPResult masterCur; if(!VPWindow(1,g_masterLen,masterCur)) return;
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

   // ----- safety gate stack (order mirrors tick_engine.hpp on_bar_closed_) -----
   // (1) CHART-DETERMINISTIC gates — shared verbatim with the Profiler indicator
   //     via Decision.mqh (quality / session / ATR% / ATR-ticks / blocked-hour /
   //     news). No side effects, so evaluating them as one group up front is
   //     behaviour-identical to the old interleaved sequence.
   double price=s.entry_close;
   double atrPct=(price>0)?AtrAt(1)/price*100.0:0.0;
   double hf=KKBuf(hHtfEmaF,0,1), hs=KKBuf(hHtfEmaS,0,1), rsiQ=KKBuf(hRsi,0,1);
   if(!MVP_DeterministicGatesPass(sig,sessionId,atrPct,AtrAt(1),g_mintick,
                                  SN_IsBlockedHour(ref),SN_InNewsWindow(utc),hf,hs,rsiQ)) return;

   // (2) LIVE / STATEFUL gates — EA-only (account equity, open position, fire-tick
   //     spread). An indicator has none of these; in the locked config they are
   //     OFF/inert except max-trades (replayed indicator-side) and the predictive
   //     daily-DD (rarely binds).
   if(MvpHasPosition()) return;                                             // flat check
   double nextBudget=RiskBudgetUsd();
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(InpMaxSpreadPips>0.0 && g_pip>0.0 && (ask-bid)/g_pip>InpMaxSpreadPips) return;    // spread (off)
   if(!SN_MaxTradesOk()) return;                                            // max trades/session
   if(IsDailyDDHit(eq,nextBudget)) return;                                  // daily DD (predictive)
   if(IsPeakDDHalt(eq)) return;                                             // peak DD halt (off)
   if(IsInCooldown()) return;                                               // cooldown
   // TP1 cost-clearance (off=0)
   if(InpMaxSpreadTp1Frac>0.0){ double t1=MathAbs(sig.tp1-sig.entry); if(t1>0.0 && (ask-bid)>InpMaxSpreadTp1Frac*t1) return; }

   double entry=sig.is_long?ask:bid;
   double risk=MathAbs(entry-sig.sl); if(risk<=0) return;
   double minDist=KKMinStopDist(_Symbol);
   // Runner TP backstop — MIRROR cpp position_manager.hpp:93-97. With InpTrailRunner the runner
   // target is entry±risk·RunnerRr (≈trail-to-exit); the chandelier trail does the real exit.
   // The old `tp=sig.tp2` capped the runner at rrBrk (1.8R) -> EA hit TP where the engine trailed
   // (parity: EA 170 TP vs engine 10 TP). Uses signal entry/risk like the engine, not the fill.
   double sl=sig.sl;
   double tp=(InpTrailRunner && sig.risk>0.0)
             ? (sig.is_long ? sig.entry+sig.risk*InpRunnerRr : sig.entry-sig.risk*InpRunnerRr)
             : sig.tp2;
   KKClampStops(sig.is_long,entry,minDist,sl,tp);
   risk=MathAbs(entry-sl); if(risk<=0) return;
   // lot from risk budget (port of RiskManager::compute_lot; risk_unit honored via RiskBudgetUsd).
   double budget=nextBudget*PeakDDLotMult(eq);
   double lot=KKPositionSize(budget,1.0,risk,g_vppl,
                             SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),
                             (InpMaxLot>0?InpMaxLot:SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)),
                             SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP));
   if(lot<=0.0) return;
   sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
   bool ok=sig.is_long?mvpTrade.Buy(lot,_Symbol,0.0,sl,tp,sig.reason):mvpTrade.Sell(lot,_Symbol,0.0,sl,tp,sig.reason);
   if(ok){
      g_tp1Done=false; g_best=entry; SN_OnFill();
      if(InpExportParity && PositionSelect(_Symbol)){
         double fill=mvpTrade.ResultPrice(); if(fill<=0.0) fill=PositionGetDouble(POSITION_PRICE_OPEN);
         ParityOnFill((ulong)PositionGetInteger(POSITION_IDENTIFIER),utc,sig,sessionId,
                      regime.trend,fill,sl,(ask-bid),AtrAt(1));
      }
   }
}

// Per-tick: TP1 partial -> BE, then ATR chandelier trail (tighten-only).
void MvpManage()
{
   if(!MvpHasPosition()) { g_tp1Done=false; g_best=0; return; }
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!mvpPos.SelectByIndex(i)) continue;
      if(mvpPos.Symbol()!=_Symbol||mvpPos.Magic()!=InpMVPMagic) continue;
      bool isLong=(mvpPos.PositionType()==POSITION_TYPE_BUY);
      ulong tk=mvpPos.Ticket(); double entry=mvpPos.PriceOpen(), sl=mvpPos.StopLoss(), tp=mvpPos.TakeProfit(), vol=mvpPos.Volume();
      double price=isLong?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double risk=MathAbs(entry-sl); if(risk<=0) continue;
      double minDist=KKMinStopDist(_Symbol);
      if(g_best==0) g_best=entry;
      if(isLong){ if(price>g_best) g_best=price; } else { if(price<g_best) g_best=price; }
      ParityTrackExcursion(price);
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
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>g_peakEquity) g_peakEquity=eq;   // monotonic peak (UpdatePeakEquity)
   MvpManage();
   datetime t=iTime(_Symbol,PERIOD_CURRENT,0);
   if(t==g_mvpLastBar) return;
   g_mvpLastBar=t;
   OnNewBar();
}

#endif // KKMVP_ENGINE_MQH
