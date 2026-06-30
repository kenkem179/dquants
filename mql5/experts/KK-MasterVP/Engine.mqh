//+------------------------------------------------------------------+
//|  KK-MasterVP/Engine.mqh - OnTick orchestration. Faithful port of   |
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
#include "../KK-Common/AccountLock.mqh"
#include "../KK-Common/AccountGuardian.mqh"   // D1 cross-EA prop guardian
#include "../KK-Common/PropState.mqh"         // account-level HWM persistence (shared, restart-safe)
#include "../KK-Common/TradeLogger.mqh"       // D2 live per-EA trade CSV
#include "../KK-Common/Notifier.mqh"          // D3 Discord/Telegram/Email
#include "../VP-Common/Types.mqh"
#include "../VP-Common/VolumeProfile.mqh"
#include "../VP-Common/Regime.mqh"
#include "../VP-Common/NodeEngine.mqh"
#include "Inputs.mqh"
#include "Strategy.mqh"
#include "ExtremeReversion.mqh"
#include "Decision.mqh"
#include "NetVolume.mqh"
#include "SessionNews.mqh"
#include "ProfitManager.mqh"
#include "Parity.mqh"

CTrade        mvpTrade;
CPositionInfo mvpPos;
CNodeEngine   g_node;
// ----- Deployment/ops modules (Layer 4, live only; all inert by default) -----
KKAccountGuardian g_guard;     // D1
KKTradeLogger     g_tradeLog;  // D2
KKNotifier        g_notify;    // D3
#define KKMVP_EA_TAG "MasterVP"
int  hAtr,hRsi,hAdx,hEmaF,hEmaS,hHtfEmaF,hHtfEmaS,hAtrM1;   // hAtrM1: impulse M1 near-price-net window ATR
double g_pip=0.01,g_mintick=0.01,g_vppl=100.0;
datetime g_mvpLastBar=0;
int  g_masterLen=480;
// per-position management state
bool   g_tp1Done=false; double g_best=0.0;
bool   g_effTrail=true;   // effective trail flag for the OPEN position (resolved at fill; mirrors cpp eff_trail_)
// D3 notification follow-up context (live only; no trading effect)
string g_openReason="";          // original entry reason -> strategy name on follow-up/close alerts
bool   g_openIsLong=false;        // original side (DEAL_COMMENT is "sl"/"tp" at close, so we cache this)
bool   g_beNotified=false;        // SL->BE alert sent once per position
double g_lastTrailNotifySL=0.0;   // last SL we alerted a trail for (0.4R throttle)
// ProfitManager (profit-lock ladder) per-position state (mirrors cpp PositionManager risk_/pm_*).
double g_riskOpen=0.0;    // ORIGINAL risk |entry-initialSL| captured at fill (R unit for InpPm* toggles)
bool   g_pmPartialDone=false;   // PM one-shot partial already executed
int    g_pmTpExt=0;             // PM TP extensions taken so far

// Per-entry-type trail override (mirrors cpp PositionManager open). reason encodes the family:
// XREV > IMP > REV(is_rev) > BRK. -1 => inherit InpTrailRunner (default => base byte-identical).
bool KKResolveTrail(const Signal &sig)
{
   int ov=InpTrailBrk;
   if(StringFind(sig.reason,"XREV")>=0)      ov=InpTrailXRev;
   else if(StringFind(sig.reason,"IMP")>=0)  ov=InpTrailImp;
   else if(sig.is_rev)                       ov=InpTrailRev;
   return (ov>=0)?(ov!=0):InpTrailRunner;
}
// risk-manager state (port of RiskManager.mqh)
double   g_peakEquity=0.0, g_dayStartEquity=0.0, g_dayPeakEquity=0.0;   // g_dayPeakEquity: H10c giveback
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

bool g_mvpAccessExpired=false;   // set true once the baked ACCESS_EXPIRY passes (runtime)

int OnInit()
{
   // Account lock: hidden ALLOWED_ACCOUNT_ID/SERVER (empty=any) are baked
   // per-account by the release script. On mismatch the shared guard Alerts
   // and we abort init so MT5 never ticks the EA (no detection, no execution).
   if(!KK_AccountAuthorized(ALLOWED_ACCOUNT_ID, ALLOWED_ACCOUNT_SERVER))
      return INIT_FAILED;

   // Access expiry: if already past the baked date at attach, start in
   // MANAGE-ONLY mode (no new trades) so any pre-existing position still gets
   // managed (e.g. after a VPS restart). Alert once here; OnTick won't re-alert.
   if(KK_AccessExpired(ACCESS_EXPIRY)){
      g_mvpAccessExpired=true;
      Alert("Expired Access");
      PrintFormat("[ACCESS] KK-MasterVP access expired (%s) - no new trades; managing open positions only.",ACCESS_EXPIRY);
   }

   hAtr =iATR(_Symbol,PERIOD_CURRENT,InpAtrLen);
   hRsi =iRSI(_Symbol,PERIOD_CURRENT,InpRsiLen,PRICE_CLOSE);
   hAdx =iADX(_Symbol,PERIOD_CURRENT,InpAdxLen);
   hEmaF=iMA(_Symbol,PERIOD_CURRENT,InpEmaFast,0,MODE_EMA,PRICE_CLOSE);
   hEmaS=iMA(_Symbol,PERIOD_CURRENT,InpEmaSlow,0,MODE_EMA,PRICE_CLOSE);
   hHtfEmaF=iMA(_Symbol,PERIOD_M15,InpEmaFast,0,MODE_EMA,PRICE_CLOSE);
   hHtfEmaS=iMA(_Symbol,PERIOD_M15,InpEmaSlow,0,MODE_EMA,PRICE_CLOSE);
   hAtrM1=iATR(_Symbol,PERIOD_M1,InpAtrLen);   // impulse path M1 near-price-net window ATR (inert when impulse off)
   g_masterLen=(int)MathRound(InpVpLookback*InpMasterMult);   // float mult -> rounded master VP length
   g_node.Init(InpVpBins);
   SN_Init();

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(StringFind(_Symbol,"BTCUSD")>=0){ g_pip=1.0; g_mintick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); }
   else { g_pip=MathPow(10.0,-digits); g_mintick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); }
   if(g_mintick<=0) g_mintick=g_pip;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE), ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   g_vppl=(ts>0)?tv/ts:SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);

   // Account-level prop state. LIVE: adopt the persisted equity high-water mark
   // (+ day anchors) from the shared COMMON file so the trailing-DD halt/soft-block
   // survive reloads/restarts and are shared across legs on this account. A reload
   // therefore does NOT reset the guard -- only deleting the file does. In the
   // Tester KKPropStateLoad() returns false, so we seed from current equity exactly
   // as before (backtests unchanged). See KK-Common/PropState.mqh.
   double curEq=AccountInfoDouble(ACCOUNT_EQUITY);
   KKPropState g_ps;
   if(KKPropStateLoad(g_ps)){
      g_peakEquity    =MathMax(g_ps.peakEquity,curEq);          // never below the persisted HWM
      g_dayStartEquity=(g_ps.dayStartEquity>0.0?g_ps.dayStartEquity:curEq);
      g_dayPeakEquity =MathMax(g_ps.dayPeakEquity,curEq);
      g_lastDayKey    =(int)g_ps.dayKey;                        // same-day restart keeps the day anchor; OnNewBar resets on a new day
      PrintFormat("[KK-MasterVP] prop state loaded: peakEquity=%.2f dayStart=%.2f (curEq=%.2f)",
                  g_peakEquity,g_dayStartEquity,curEq);
   } else {
      g_peakEquity=curEq; g_dayStartEquity=curEq; g_dayPeakEquity=curEq; g_lastDayKey=-1;
   }
   // Prop contract-baseline floor (LIVE only): anchor the overall-DD peak at the
   // contract size so a fresh attach on a drawn-down account measures DD from the
   // baseline (e.g. 100000), not from current equity. Tester-skipped so backtests
   // are unchanged. The persisted HWM still trails UP from here as new peaks print.
   if(!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION) && InpPropBaselineEquity>0.0){
      g_peakEquity=MathMax(g_peakEquity,InpPropBaselineEquity);
      PrintFormat("[KK-MasterVP] prop baseline floor applied: peakEquity=%.2f (baseline=%.2f, curEq=%.2f)",
                  g_peakEquity,InpPropBaselineEquity,curEq);
   }
   g_cooldownUntil=0;

   mvpTrade.SetExpertMagicNumber(InpMVPMagic);
   mvpTrade.SetTypeFillingBySymbol(_Symbol);
   mvpTrade.SetDeviationInPoints(InpDeviationPoints);

   // ----- Deployment/ops modules (live only; self-guard the Tester) -----
   KKGuardConfig gc;
   gc.enabled        =InpGuardEnable;
   gc.dailyLossPct   =InpGuardDailyLossPct;
   gc.overallDDPct   =InpGuardOverallDDPct;
   gc.bufferPct      =InpGuardBufferPct;
   gc.ddAnchorMode   =InpGuardDDAnchor;
   gc.manualDayAnchor=InpGuardManualDayAnchor;
   gc.flattenOnBreach=InpGuardFlatten;
   g_guard.Init(gc);
   g_tradeLog.Init(InpLiveTradeCsv,KKMVP_EA_TAG);
   g_notify.Init(InpNotifyChannel,InpNotifyMode,InpDiscordWebhookUrl,
                 InpTelegramBotToken,InpTelegramChatId,KKMVP_EA_TAG,(long)InpMVPMagic);
   g_notify.Startup();

   ParityInit();
   PrintFormat("[KK-MasterVP] init pip=%.5f vppl=%.2f masterLen=%d (VP %dx%.2f)",
               g_pip,g_vppl,g_masterLen,InpVpLookback,InpMasterMult);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r){
   MvpSavePropState();    // persist final account HWM before unload (live only)
   IndicatorRelease(hAtr);IndicatorRelease(hRsi);IndicatorRelease(hAdx);IndicatorRelease(hEmaF);IndicatorRelease(hEmaS);
   IndicatorRelease(hHtfEmaF);IndicatorRelease(hHtfEmaS);IndicatorRelease(hAtrM1);
   g_tradeLog.Deinit();   // D2: flush + close the live trade CSV
   ParityClose();
}

// Per-closed-trade hook. Drives BOTH the tester-only parity export AND the
// live-only deployment ops (D2 CSV + D3 close notification). The modules
// self-guard their own context (parity = tester, D2/D3 = live), so this single
// filtered path serves both without interfering.
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &req,const MqlTradeResult &res){
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=(long)InpMVPMagic) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;

   // D2/D3 (live only; inert in Tester)
   g_tradeLog.LogDeal(trans.deal);
   // D3 close alert: ONLY on a FULL close (the position is gone). A TP1 partial is
   // also a DEAL_ENTRY_OUT but leaves the position open -> it is alerted as "TP1 hit"
   // from MvpManage(), not here. Classify the final close: broker comment "tp" => TP2,
   // else net>=0 => SL+ (stopped at break-even+), net<0 => SL (loss).
   if(g_notify.Enabled() && !PositionSelectByTicket(trans.position)){
      double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
      double net   =profit+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
      string cm=HistoryDealGetString(trans.deal,DEAL_COMMENT); StringToLower(cm);
      int ev=(StringFind(cm,"tp")>=0) ? KKN_EV_TP2 : (net>=0.0 ? KKN_EV_SLPLUS : KKN_EV_SL);
      g_notify.TradeClose(g_openIsLong,ev,net,g_openReason);
   }

   // Parity export (tester only)
   if(InpExportParity) ParityOnDealOut(trans.deal,trans.position);
}

bool MvpHasPosition(){
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!mvpPos.SelectByIndex(i)) continue;
      if(mvpPos.Symbol()==_Symbol && mvpPos.Magic()==InpMVPMagic) return true; } return false;
}

// Volume already open for this symbol+magic in the given direction (counts against the
// broker's per-symbol/direction SYMBOL_VOLUME_LIMIT). MasterVP is single-position, so this
// is normally 0 at entry; computed defensively for the volume-limit clamp.
double MvpOpenVolume(bool isLong){
   double v=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!mvpPos.SelectByIndex(i)) continue;
      if(mvpPos.Symbol()!=_Symbol || mvpPos.Magic()!=InpMVPMagic) continue;
      if((mvpPos.PositionType()==POSITION_TYPE_BUY)==isLong) v+=mvpPos.Volume(); }
   return v;
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

// Persist the account-level HWM + day anchors to the shared COMMON file. No-op in
// the Tester. Called once per closed bar (cheap) + on deinit, so a restart loses
// at most the current bar's peak movement (the HWM is monotonic and re-establishes
// immediately). KKPropStateSave merges MAX(peak) across legs so it never regresses.
void MvpSavePropState()
{
   KKPropState st;
   st.peakEquity=g_peakEquity; st.dayStartEquity=g_dayStartEquity;
   st.dayPeakEquity=g_dayPeakEquity; st.dayKey=g_lastDayKey;
   KKPropStateSave(st);
}
bool IsPeakDDHalt(double eq){ return InpMaxPeakDDPct>0.0 && PeakDDPct(eq)>=InpMaxPeakDDPct; }
double PeakDDLotMult(double eq){ if(InpSoftBlockDDPct<=0.0) return 1.0; return PeakDDPct(eq)>=InpSoftBlockDDPct?InpSoftBlockLotMult:1.0; }
// Predictive daily-DD: adds the next trade's worst-case loss so one trade can't open through the cap.
bool IsDailyDDHit(double eq,double nextRiskBudget){
   if(InpMaxDailyDDPct<=0.0 || g_dayStartEquity<=0.0) return false;
   double proj=MathMax(0.0,(g_dayStartEquity-eq+nextRiskBudget)/g_dayStartEquity*100.0);
   return proj>=InpMaxDailyDDPct;
}
// H10c session-giveback halt: stand down for the rest of the day once the account has handed back
// >= InpGivebackPct of the day's peak gain. Arms only on a green day (dayPeak>dayStart); evaluated
// flat at the entry gate so the open runner is never truncated. 0 = OFF.
bool IsGivebackHalt(double eq){
   if(InpGivebackPct<=0.0 || g_dayStartEquity<=0.0) return false;
   double gain=g_dayPeakEquity-g_dayStartEquity;
   if(gain<=0.0) return false;
   double givenback=g_dayPeakEquity-eq;
   return givenback>=InpGivebackPct/100.0*gain;
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
   // Session/day context in UTC.
   datetime barServer=iTime(_Symbol,PERIOD_CURRENT,1);
   datetime utc=SN_UtcTime(barServer);
   MqlDateTime rdt; TimeToStruct(utc,rdt);
   int dayKey=rdt.year*10000+rdt.mon*100+rdt.day;
   int sessionId=SN_UpdateSession(utc);
   if(g_dayStartEquity<=0.0 || dayKey!=g_lastDayKey){ g_dayStartEquity=eq; g_dayPeakEquity=eq; g_lastDayKey=dayKey; }  // H10c: reset giveback peak on new day
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
   // ----- entry detection -----
   // Impulse-thrust (the Monster delta, OFF by default) REPLACES the base entry ABOVE the vol ceiling
   // (the band the base breakout/reversion never trades), so the two paths never compete on a bar.
   // Mirrors tick_engine.hpp. InpEnableImpulse=false => the else branch always runs => base byte-identical.
   bool   isImpulse=false;
   double sigAtrPct=(s.entry_close>0)?AtrAt(1)/s.entry_close*100.0:0.0;
   bool   aboveCeil=(InpMaxAtrPct>0.0)&&(sigAtrPct>InpMaxAtrPct);
   Signal sig;
   if(InpEnableImpulse && aboveCeil){
      VPResult masterPred=masterCur;                            // predicted (aged-out) master VP
      if(InpImpulsePredictBars>0){
         int predLen=(int)MathMax(InpVpBins,g_masterLen-InpImpulsePredictBars);
         VPResult mp; if(VPWindow(1,predLen,mp)) masterPred=mp;
      }
      bool slopeUp=false, slopeDn=false;                        // master-POC slope over the lookback
      VPResult mPrev;
      if(VPWindow(1+InpImpulseTrendSlopeBars,g_masterLen,mPrev) && mPrev.valid && masterCur.poc>0 && mPrev.poc>0){
         slopeUp=masterCur.poc>mPrev.poc; slopeDn=masterCur.poc<mPrev.poc;
      }
      bool hasM1=false;
      double netM1=M1NetNear(hAtrM1,InpTfNetLook,InpTfNetWinAtr,g_mintick,hasM1);
      sig=MVP_DetectImpulse(masterCur,masterPred,s,slopeUp,slopeDn,netM1,hasM1,g_pip);
      isImpulse=sig.valid;
   } else {
      sig=MVP_DetectSignal(masterCur,masterCur,localCur,regime,s,nsVah,nsVal,nsPx,g_pip,g_mintick,1.0);

      // Extreme Reversion (XRev) priority - mirrors tick_engine.hpp: when enabled and its (stricter)
      // failed-breakout-sweep conditions hold, XRev OVERRIDES the base signal; otherwise the base
      // breakout/reversion signal stands. OFF by default => this block is skipped and sig is unchanged.
      if(InpEnableExtremeReversion){
         int needN=MathMax(InpXRevMinAgeBars+2,MathMax(InpXRevFailLookback+2,InpXRevHHLookback+3))+2;
         MqlRates xr[]; ArraySetAsSeries(xr,true);
         if(CopyRates(_Symbol,PERIOD_CURRENT,0,needN,xr)>=needN){
            double sweepHi=masterCur.vah, sweepLo=masterCur.val;
            for(int k=3;k<=InpXRevHHLookback+2 && k<needN;k++){          // N bars preceding the rejection bar (shift 2)
               sweepHi=MathMax(sweepHi,xr[k].high); sweepLo=MathMin(sweepLo,xr[k].low);
            }
            int closesAbove=0, closesBelow=0;
            for(int k=2;k<=InpXRevFailLookback+1 && k<needN;k++){        // M bars ending at the rejection bar
               if(xr[k].close>masterCur.vah) closesAbove++;
               if(xr[k].close<masterCur.val) closesBelow++;
            }
            bool agedShort=true, agedLong=true;                          // no opposite-edge cross within min_age_bars
            for(int j=2;j<=InpXRevMinAgeBars+1 && j+1<needN;j++){
               if(xr[j+1].close<=masterCur.val && xr[j].close>masterCur.val) agedShort=false;
               if(xr[j+1].close>=masterCur.vah && xr[j].close<masterCur.vah) agedLong=false;
            }
            Signal xs=MVP_DetectExtremeReversion(masterCur,s,sweepHi,sweepLo,closesAbove,closesBelow,
                                                 agedShort,agedLong,nsVah,nsVal,nsPx,g_pip,g_mintick);
            if(xs.valid) sig=xs;
         }
      }
   }
   if(!sig.valid) return;

   // ----- safety gate stack (order mirrors tick_engine.hpp on_bar_closed_) -----
   // (1) CHART-DETERMINISTIC gates - shared verbatim with the Profiler indicator
   //     via Decision.mqh (quality / session / ATR% / ATR-ticks / blocked-hour /
   //     news). No side effects, so evaluating them as one group up front is
   //     behaviour-identical to the old interleaved sequence.
   double price=s.entry_close;
   double atrPct=(price>0)?AtrAt(1)/price*100.0:0.0;
   double hf=KKBuf(hHtfEmaF,0,1), hs=KKBuf(hHtfEmaS,0,1), rsiQ=KKBuf(hRsi,0,1);
   if(!MVP_DeterministicGatesPass(sig,sessionId,atrPct,AtrAt(1),g_mintick,
                                  SN_IsBlockedHour(utc),SN_InNewsWindow(utc),hf,hs,rsiQ,isImpulse)) return;

   // (2) LIVE / STATEFUL gates - EA-only (account equity, open position, fire-tick
   //     spread). An indicator has none of these; in the locked config they are
   //     OFF/inert except max-trades (replayed indicator-side) and the predictive
   //     daily-DD (rarely binds).
   if(MvpHasPosition()) return;                                             // flat check
   if(g_guard.Halted()) return;                                             // D1: account guardian halt (no new entries)
   if(g_mvpAccessExpired) return;                                           // access expired: no new entries (open positions still managed in OnTick)
   double nextBudget=RiskBudgetUsd();
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(InpMaxSpreadPips>0.0 && g_pip>0.0 && (ask-bid)/g_pip>InpMaxSpreadPips) return;    // spread (off)
   if(!SN_MaxTradesOk()) return;                                            // max trades/session
   if(IsGivebackHalt(eq)) return;                                           // H10c session giveback halt (off)
   if(IsDailyDDHit(eq,nextBudget)) return;                                  // daily DD (predictive)
   if(IsPeakDDHalt(eq)) return;                                             // peak DD halt (off)
   if(IsInCooldown()) return;                                               // cooldown
   // TP1 cost-clearance (off=0)
   if(InpMaxSpreadTp1Frac>0.0){ double t1=MathAbs(sig.tp1-sig.entry); if(t1>0.0 && (ask-bid)>InpMaxSpreadTp1Frac*t1) return; }

   double entry=sig.is_long?ask:bid;
   double risk=MathAbs(entry-sig.sl); if(risk<=0) return;
   // Min legal SL/TP distance + a safety margin (current spread + 2 points) so a market
   // order's stops always clear the broker's stops/freeze level even as price ticks.
   double minDist=KKMinStopDist(_Symbol)+(ask-bid)+2.0*_Point;
   // Runner TP backstop - MIRROR cpp position_manager.hpp:93-97. With InpTrailRunner the runner
   // target is entry+/-risk*RunnerRr (~trail-to-exit); the chandelier trail does the real exit.
   // The old `tp=sig.tp2` capped the runner at rrBrk (1.8R) -> EA hit TP where the engine trailed
   // (parity: EA 170 TP vs engine 10 TP). Uses signal entry/risk like the engine, not the fill.
   double sl=sig.sl;
   bool effTrail=KKResolveTrail(sig);   // per-entry-type override of InpTrailRunner
   double tp=(effTrail && sig.risk>0.0)
             ? (sig.is_long ? sig.entry+sig.risk*InpRunnerRr : sig.entry-sig.risk*InpRunnerRr)
             : sig.tp2;
   KKClampStops(sig.is_long,entry,minDist,sl,tp);
   risk=MathAbs(entry-sl); if(risk<=0) return;
   // Sizing-risk floor: at the daily rollover the broker spread blows out (112-420 pips vs ~25
   // normal), which collapses the post-clamp `risk` (== minDist == ~one spread) to a tiny fraction
   // of a sane stop. KKPositionSize divides by it -> the lot explodes ~12x (capped only by the
   // broker volume limit), producing the equity/deposit-load spike. Floor the distance used for
   // SIZING at InpMinRiskAtrMult*ATR (the strategy's nominal stop is ~1.2*ATR, so this never bites
   // a healthy trade). The REAL sl/tp below are untouched -> a genuinely tight stop just takes a
   // smaller-than-budget loss instead of a catastrophic position. Mirrors the C++ engine, which
   // already sizes on the clean signal risk (sig.risk ~1.2*ATR) and so never blows up.
   double sizeRisk=risk;
   if(InpMinRiskAtrMult>0.0){ double rFloor=InpMinRiskAtrMult*AtrAt(1); if(sizeRisk<rFloor) sizeRisk=rFloor; }
   // lot from risk budget (port of RiskManager::compute_lot; risk_unit honored via RiskBudgetUsd).
   double budget=nextBudget*PeakDDLotMult(eq);
   double lot=KKPositionSize(budget,1.0,sizeRisk,g_vppl,
                             SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),
                             (InpMaxLot>0?InpMaxLot:SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)),
                             SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),
                             SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT),
                             MvpOpenVolume(sig.is_long));
   if(lot<=0.0) return;
   sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
   // Affordability guard: never send an order the account can't cover (prevents
   // "not enough money / No money" failures on tiny-deposit / high-margin runs).
   ENUM_ORDER_TYPE otype=sig.is_long?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double marginReq=0.0;
   if(!OrderCalcMargin(otype,_Symbol,lot,entry,marginReq)) return;   // can't price margin -> skip
   if(marginReq>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) return;      // not enough free margin -> skip
   bool ok=sig.is_long?mvpTrade.Buy(lot,_Symbol,0.0,sl,tp,sig.reason):mvpTrade.Sell(lot,_Symbol,0.0,sl,tp,sig.reason);
   if(ok){
      g_tp1Done=false; g_best=entry; g_effTrail=effTrail; SN_OnFill();
      g_riskOpen=risk; g_pmPartialDone=false; g_pmTpExt=0;   // capture original R for the profit-lock ladder
      g_openReason=sig.reason; g_openIsLong=sig.is_long;     // D3 follow-up/close context
      g_beNotified=false; g_lastTrailNotifySL=sl;            // D3 trail throttle baseline (0.4R)
      // D3 open notify (live). Shows the strategy's logical TP1/TP2, not the runner backstop.
      if(g_notify.Enabled()) g_notify.TradeOpen(sig.is_long,lot,entry,sl,sig.tp1,sig.tp2,sig.reason);
      if(InpExportParity && PositionSelect(_Symbol)){
         double fill=mvpTrade.ResultPrice(); if(fill<=0.0) fill=PositionGetDouble(POSITION_PRICE_OPEN);
         ParityOnFill((ulong)PositionGetInteger(POSITION_IDENTIFIER),utc,sig,sessionId,
                      regime.trend,fill,sl,(ask-bid),AtrAt(1));
      }
   }
}

// Guarded SL/TP modify. A broker rejects a modify whose requested SL/TP equal the
// position's CURRENT SL/TP with "invalid stops"; without this guard the manager
// re-sends that same no-op every tick (log spam + wasted requests, e.g. after the
// recomputed level rounds back onto the existing one). Skipping a no-op is
// behaviour-neutral -- the position is already at those levels -- so engine parity
// is unaffected. Returns true when nothing needs sending.
bool MvpSafeModify(ulong tk,double newSL,double newTP)
{
   newSL=NormalizeDouble(newSL,_Digits);
   newTP=NormalizeDouble(newTP,_Digits);
   double curSL=NormalizeDouble(mvpPos.StopLoss(),_Digits);
   double curTP=NormalizeDouble(mvpPos.TakeProfit(),_Digits);
   if(MathAbs(newSL-curSL)<=_Point && MathAbs(newTP-curTP)<=_Point)
      return true;   // already at target -> skip the broker round-trip

   // Broker freeze/stop guard. A modify is rejected with "...close to market" when
   // either the EXISTING or the NEW SL/TP sits within the broker's stop/freeze level
   // of the current market price. stops_level & freeze_level are reported 0 on many
   // symbols (e.g. EURUSD on some servers) yet the server still enforces a floating
   // buffer, so fall back to spread, floored at 10 points. Skipping is behaviour-
   // neutral: the level is simply re-applied on a later tick once price has moved
   // away. On XAU the validated trails clear this distance easily, so the locked
   // result is unchanged -- this only suppresses modifies the broker would reject.
   double stops =SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*_Point;
   double spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
   double effMin=MathMax(MathMax(stops,freeze),spread);
   if(effMin<=0) effMin=10*_Point;
   bool isLong=(mvpPos.PositionType()==POSITION_TYPE_BUY);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   // Position already frozen (current SL/TP within the level) -> ANY modify is
   // rejected; leave it to close naturally at its existing levels.
   if(curSL>0){ double ref=isLong?bid:ask; if((isLong?(ref-curSL):(curSL-ref))<effMin) return true; }
   if(curTP>0){ double ref=isLong?ask:bid; if((isLong?(curTP-ref):(ref-curTP))<effMin) return true; }
   // New levels would be too close to market -> skip, retry on a later tick.
   if(newSL>0){ double ref=isLong?bid:ask; if((isLong?(ref-newSL):(newSL-ref))<effMin) return true; }
   if(newTP>0){ double ref=isLong?ask:bid; if((isLong?(newTP-ref):(ref-newTP))<effMin) return true; }
   return mvpTrade.PositionModify(tk,newSL,newTP);
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
            if(g_notify.Enabled()) g_notify.Tp1Hit(isLong,price,g_openReason);   // D3: TP1 hit
            if(InpBeAfterTp1){
               double be=isLong?entry+InpBeBufAtr*AtrAt(1):entry-InpBeBufAtr*AtrAt(1); be=NormalizeDouble(be,_Digits);
               bool okSide=(isLong&&be>sl)||(!isLong&&be<sl), okDist=(isLong?(price-be>=minDist):(be-price>=minDist));
               if(okSide&&okDist){
                  MvpSafeModify(tk,be,tp);
                  if(g_notify.Enabled() && !g_beNotified){   // D3: SL -> BE (once)
                     g_notify.SlToBe(isLong,be,g_openReason); g_beNotified=true; g_lastTrailNotifySL=be;
                  }
               }
            }
         }
      }
      // ATR chandelier trail (after TP1), tighten-only
      if(g_tp1Done && g_effTrail){
         double atr1=AtrAt(1);
         double trail=isLong?g_best-InpTrailAtrMult*atr1:g_best+InpTrailAtrMult*atr1; trail=NormalizeDouble(trail,_Digits);
         double cur=mvpPos.StopLoss();
         bool okSide=(isLong&&trail>cur)||(!isLong&&trail<cur), okDist=(isLong?(price-trail>=minDist):(trail-price>=minDist));
         if(okSide&&okDist){
            MvpSafeModify(tk,trail,mvpPos.TakeProfit());
            // D3: SL trailed - throttle to >=0.4R moves so trending bars don't spam.
            if(g_notify.Enabled() && g_riskOpen>0.0 &&
               MathAbs(trail-g_lastTrailNotifySL)>=0.4*g_riskOpen){
               g_notify.SlTrailed(isLong,trail,g_openReason); g_lastTrailNotifySL=trail;
            }
         }
      }
      // ProfitManager profit-lock ladder (mirrors cpp on_tick step 4: pm_evaluate merged tighten-only SL /
      // extend-only TP / one-shot partial). Runs every tick, independent of TP1/BE/trail, against the
      // ORIGINAL risk g_riskOpen. All toggles OFF => MvpPmAny() false => skipped => base byte-identical.
      if(MvpPmAny() && g_riskOpen>0.0){
         double pmAtr=AtrAt(1);
         double curSL=mvpPos.StopLoss(), curTP=mvpPos.TakeProfit();
         MvpPmActions act=MvpPmEvaluate(isLong,entry,curSL,curTP,price,g_best,g_riskOpen,pmAtr,
                                        g_pmTpExt,g_pmPartialDone,(g_tp1Done&&InpBeAfterTp1),0.0,false);
         double newSL=curSL, newTP=curTP; bool changed=false;
         // SL: tighten-only AND must clear the broker stop distance, else leave it for a later tick.
         if((isLong?(act.sl>curSL):(act.sl<curSL))
            && (isLong?(price-act.sl>=minDist):(act.sl-price>=minDist))){
            newSL=NormalizeDouble(act.sl,_Digits); changed=true;
         }
         // TP: extend-only (further from price) AND must clear the broker stop
         // distance, else the broker rejects it ("invalid stops") and we'd re-send
         // every tick. Leave it for a later tick when price has moved away.
         if((isLong?(act.tp>curTP):(act.tp<curTP))
            && (isLong?(act.tp-price>=minDist):(price-act.tp>=minDist))){
            newTP=NormalizeDouble(act.tp,_Digits); g_pmTpExt++; changed=true;
         }
         if(changed) MvpSafeModify(tk,newSL,newTP);
         // one-shot partial close
         if(act.partial_frac>0.0 && !g_pmPartialDone){
            double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            double q=vol*act.partial_frac; if(step>0) q=MathFloor(q/step)*step;
            if(q>=mn && q<vol) mvpTrade.PositionClosePartial(tk,q);
            g_pmPartialDone=true;
         }
      }
   }
}

// D1: close every MasterVP position (used when the guardian breaches with flatten-on).
void MvpFlattenAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!mvpPos.SelectByIndex(i)) continue;
      if(mvpPos.Symbol()==_Symbol && mvpPos.Magic()==InpMVPMagic) mvpTrade.PositionClose(mvpPos.Ticket()); }
}

void OnTick()
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>g_peakEquity) g_peakEquity=eq;   // monotonic peak (UpdatePeakEquity)
   if(eq>g_dayPeakEquity) g_dayPeakEquity=eq;   // H10c: intraday peak trails within the day

   // Access expiry (server-time): once past the baked date, stop opening new
   // trades. MvpManage() below still runs, so any OPEN position keeps its
   // BE/trail/TP management until it closes naturally. Alert once.
   if(!g_mvpAccessExpired && KK_AccessExpired(ACCESS_EXPIRY)){
      g_mvpAccessExpired=true;
      Alert("Expired Access");
      Print("[ACCESS] KK-MasterVP access expired - no new trades; managing open positions only.");
   }

   // D1 guardian: update shared anchors; on breach flatten (if configured) and
   // notify once. The entry gate in OnNewBar also blocks new trades while halted.
   if(g_guard.Enabled()){
      static bool s_alerted=false;
      bool halted=g_guard.Update();
      if(halted){
         if(g_guard.ShouldFlatten()) MvpFlattenAll();
         if(!s_alerted){ g_notify.AlertMsg("account guardian HALT - "+g_guard.Status()); s_alerted=true; }
      } else s_alerted=false;
   }

   MvpManage();
   datetime t=iTime(_Symbol,PERIOD_CURRENT,0);
   if(t==g_mvpLastBar) return;
   g_mvpLastBar=t;
   OnNewBar();
   MvpSavePropState();   // persist account HWM + day anchors once per closed bar (live only)
}

#endif // KKMVP_ENGINE_MQH
