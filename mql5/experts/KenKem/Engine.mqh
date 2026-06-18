//+------------------------------------------------------------------+
//|  KenKem/Engine.mqh — orchestrator: OnInit/OnTick, trigger update, |
//|  first-match dispatch (E1->E2->E4->E5), SL/TP, sizing, management.|
//|  Pulls family modules + KK-Common generics. Include AFTER Inputs. |
//+------------------------------------------------------------------+
#ifndef KENKEM_ENGINE_MQH
#define KENKEM_ENGINE_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include "../KK-Common/Indicators.mqh"
#include "../KK-Common/Sizing.mqh"
#include "../KK-Common/PositionManager.mqh"
#include "State.mqh"
#include "Indicators.mqh"
#include "Snapshot.mqh"
#include "Gates.mqh"
#include "Entries/E1.mqh"
#include "Entries/E2.mqh"
#include "Entries/E4.mqh"
#include "Entries/E5.mqh"

//==================== per-entry routing ============================
double CustomLevel(int kind,bool isLong,const Snap &s){
   if(kind==1) return E1_CustomLevel(isLong,s);
   if(kind==2) return E2_CustomLevel(isLong,s);
   if(kind==4) return E4_CustomLevel(isLong,s);
   return E5_CustomLevel(isLong,s);
}
void AtrCaps(int kind,double &cap,double &flr){
   if(kind==1) E1_AtrCaps(cap,flr); else if(kind==2) E2_AtrCaps(cap,flr);
   else if(kind==4) E4_AtrCaps(cap,flr); else E5_AtrCaps(cap,flr);
}
double EntryRr(int kind,bool isLong,const Snap &s){
   bool sw=(s.sideways>=InpSidewaysWarn);
   if(kind==1) return E1_Rr(isLong,sw);
   if(kind==2) return E2_Rr(isLong,sw);
   if(kind==4) return E4_Rr(isLong,sw);
   return E5_Rr(isLong,sw);
}
void MgmtParams(int kind,double &trig,double &ratio,double &be,double &trail){
   if(kind==1) E1_Mgmt(trig,ratio,be,trail); else if(kind==2) E2_Mgmt(trig,ratio,be,trail);
   else if(kind==4) E4_Mgmt(trig,ratio,be,trail); else E5_Mgmt(trig,ratio,be,trail);
}
bool GateOk(int kind,bool isLong,const Snap &s){
   if(s.sideways>=InpSidewaysBlock) return false;
   if(kind!=5 && TrendCore(s,isLong)==0) return false;   // E5 skips the hard gate (loose entry)
   if(kind==1) return E1_Gate(s,isLong);
   if(kind==2) return E2_Gate(s,isLong);
   if(kind==4) return E4_Gate(s,isLong);
   return E5_Gate(s,isLong);
}

//==================== SL / TP ======================================
void RecentRange(int lb,double &hi,double &lo){
   hi=-1e300; lo=1e300; for(int i=1;i<=lb;i++){ hi=MathMax(hi,iHigh(_Symbol,PERIOD_M1,i)); lo=MathMin(lo,iLow(_Symbol,PERIOD_M1,i)); }
}
double ComputeSL(int kind,bool isLong,double entry,const Snap &s,double hi,double lo){
   double lvl=CustomLevel(kind,isLong,s);
   double base=isLong?MathMin(lo,lvl):MathMax(hi,lvl);
   double stop=isLong?base-InpSlEmaDistance*g_pip:base+InpSlEmaDistance*g_pip;
   double cap,flr; AtrCaps(kind,cap,flr);
   if(s.atrM1>0){
      double dP=MathAbs(entry-stop)/g_pip, aP=s.atrM1/g_pip, fP=dP;
      if(fP>aP*cap) fP=aP*cap; if(fP<aP*flr) fP=aP*flr;
      if(fP!=dP) stop=isLong?entry-fP*g_pip:entry+fP*g_pip;
   }
   return stop;
}
double ComputeTP(int kind,bool isLong,double entry,double sl,const Snap &s){
   double rr=EntryRr(kind,isLong,s), risk=MathAbs(entry-sl); return isLong?entry+rr*risk:entry-rr*risk;
}

//==================== INIT / DEINIT ================================
int OnInit()
{
   KenKemCreateHandles();
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   if(StringFind(_Symbol,"BTCUSD")>=0) g_pip=1.0;
   else if(StringFind(_Symbol,"XAUUSD")>=0||StringFind(_Symbol,"GOLD")>=0) g_pip=MathPow(10.0,-digits);
   else g_pip=(digits==3||digits==5)?0.0001:MathPow(10.0,-digits);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE), ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   g_vppl=(ts>0)?tv/ts:SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);
   PrintFormat("[KK-KenKem] init pip=%.5f vppl=%.5f  E1=%d E2=%d E4=%d E5=%d",g_pip,g_vppl,InpE1On,InpE2On,InpE4On,InpE5On);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){ KenKemReleaseHandles(); }

//==================== TRIGGERS =====================================
void UpdateTriggers(){
   datetime now=iTime(_Symbol,PERIOD_M1,1); double tol=Tol();
   if(InpE1On) E1_UpdateTrigger(now,tol);
   if(InpE2On) E2_UpdateTrigger(now,tol);
   if(InpE4On) E4_UpdateTrigger(now,tol);
   if(InpE5On) E5_UpdateTrigger(now,tol);
}

//==================== ENTRY ========================================
int CountPos(int dir){
   int n=0; for(int i=PositionsTotal()-1;i>=0;i--){ if(!posinfo.SelectByIndex(i)) continue;
      if(posinfo.Symbol()!=_Symbol||posinfo.Magic()!=InpMagic) continue;
      if(dir==0) n++; else if(dir==1&&posinfo.PositionType()==POSITION_TYPE_BUY) n++;
      else if(dir==-1&&posinfo.PositionType()==POSITION_TYPE_SELL) n++; } return n;
}
void ConsumeTrigger(int kind,bool isLong){
   if(kind==1){ if(isLong) gE1Up=0; else gE1Dn=0; }
   else if(kind==2){ if(isLong) gE2Up=0; else gE2Dn=0; }
   else if(kind==4){ if(isLong) gE4Up=0; else gE4Dn=0; }
   else { if(isLong) gE5Up=0; else gE5Dn=0; }
}
bool TryOne(int kind,bool on,datetime up,datetime dn,int maxAge,const Snap &s)
{
   if(!on) return false;
   for(int d=0;d<2;d++){
      bool isLong=(d==0); datetime fired=isLong?up:dn; if(fired==0) continue;
      int age=iBarShift(_Symbol,PERIOD_M1,fired);
      if(age>maxAge){ ConsumeTrigger(kind,isLong); continue; }
      if(!GateOk(kind,isLong,s)) continue;
      if(InpBlockOpposite && CountPos(isLong?-1:1)>0) continue;
      double spread=SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(InpMaxSpreadPrice>0 && spread>InpMaxSpreadPrice) continue;
      double entry=isLong?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double hi,lo; RecentRange(InpRangeLookback,hi,lo);
      double sl=ComputeSL(kind,isLong,entry,s,hi,lo);
      double tp=ComputeTP(kind,isLong,entry,sl,s);
      double minDist=KKMinStopDist(_Symbol);
      KKClampStops(isLong,entry,minDist,sl,tp);            // clamp before sizing -> honest risk
      double risk=MathAbs(entry-sl); if(risk<=0) continue;
      double bal=(InpRiskBaseBalance>0)?InpRiskBaseBalance:AccountInfoDouble(ACCOUNT_BALANCE);
      double lot=KKPositionSize(bal,InpRiskPerTrade,risk,g_vppl,
                                SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),
                                SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),
                                SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP));
      sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
      string cmt="KKE"+IntegerToString(kind);
      bool ok=isLong?trade.Buy(lot,_Symbol,0.0,sl,tp,cmt):trade.Sell(lot,_Symbol,0.0,sl,tp,cmt);
      if(ok){ ConsumeTrigger(kind,isLong); return true; }
      PrintFormat("[KK-KenKem] E%d order failed ret=%d %s",kind,trade.ResultRetcode(),trade.ResultRetcodeDescription());
   }
   return false;
}
void TryEnter(){
   if(CountPos(0)>=InpMaxConcurrent) return;
   Snap s; if(!BuildSnap(s)) return;
   if(TryOne(1,InpE1On,gE1Up,gE1Dn,InpE1MaxAge,s)) return;
   if(TryOne(2,InpE2On,gE2Up,gE2Dn,InpE2MaxAge,s)) return;
   if(TryOne(4,InpE4On,gE4Up,gE4Dn,InpE4MaxAge,s)) return;
   TryOne(5,InpE5On,gE5Up,gE5Dn,InpE5MaxAge,s);
}

//==================== MANAGEMENT ===================================
#define MAXPOS 128
ulong  st_tk[MAXPOS]; double st_best[MAXPOS]; bool st_part[MAXPOS]; int st_kind[MAXPOS]; int st_n=0;
int StIdx(ulong tk,int kind){
   for(int i=0;i<st_n;i++) if(st_tk[i]==tk) return i;
   if(st_n<MAXPOS){ st_tk[st_n]=tk; st_best[st_n]=0; st_part[st_n]=false; st_kind[st_n]=kind; return st_n++; } return -1;
}
void StForget(ulong tk){ for(int i=0;i<st_n;i++) if(st_tk[i]==tk){ st_tk[i]=st_tk[st_n-1]; st_best[i]=st_best[st_n-1]; st_part[i]=st_part[st_n-1]; st_kind[i]=st_kind[st_n-1]; st_n--; return; } }
int KindFromComment(string c){ if(StringFind(c,"KKE1")>=0) return 1; if(StringFind(c,"KKE2")>=0) return 2; if(StringFind(c,"KKE5")>=0) return 5; return 4; }
void Manage(){
   for(int i=PositionsTotal()-1;i>=0;i--){
      if(!posinfo.SelectByIndex(i)) continue;
      if(posinfo.Symbol()!=_Symbol||posinfo.Magic()!=InpMagic) continue;
      ulong tk=posinfo.Ticket(); bool isLong=(posinfo.PositionType()==POSITION_TYPE_BUY);
      int kind=KindFromComment(posinfo.Comment());
      int si=StIdx(tk,kind); if(si<0) continue;
      double entry=posinfo.PriceOpen(), sl=posinfo.StopLoss(), tp=posinfo.TakeProfit(), vol=posinfo.Volume();
      double price=isLong?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double risk=MathAbs(entry-sl); if(risk<=0) continue;
      double trig,ratio,beBuf,trailF; MgmtParams(st_kind[si],trig,ratio,beBuf,trailF);
      KKManagePosition(trade,_Symbol,tk,isLong,entry,sl,tp,vol,price,risk,
                       KKMinStopDist(_Symbol),trig,ratio,beBuf,trailF,st_best[si],st_part[si]);
   }
   for(int i=st_n-1;i>=0;i--) if(!posinfo.SelectByTicket(st_tk[i])) StForget(st_tk[i]);
}

//==================== ONTICK =======================================
void OnTick(){
   Manage();
   datetime t=iTime(_Symbol,PERIOD_M1,0);
   if(t==g_lastBarTime) return;
   g_lastBarTime=t;
   UpdateTriggers();
   TryEnter();
}

#endif // KENKEM_ENGINE_MQH
