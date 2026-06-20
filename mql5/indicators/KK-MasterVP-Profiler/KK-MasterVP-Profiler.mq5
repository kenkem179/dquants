//+------------------------------------------------------------------+
//|  KK-MasterVP-Profiler.mq5 — EA-EXACT visual twin of KK-MasterVP.   |
//|                                                                    |
//|  This indicator does NOT re-implement the strategy. It #includes   |
//|  the EA's OWN decision code (KK-MasterVP/Strategy.mqh + Decision.   |
//|  mqh + VP-Common + SessionNews) and REPLAYS the EA bar-by-bar, so  |
//|  an entry marker lands on the EXACT candle the EA would fire — the  |
//|  signal, the gates, the master-VP length, the SL/TP1 distances and  |
//|  the SL->BE->trail management are all the EA's, not an eyeballed    |
//|  copy. Display-only: never trades (an indicator cannot OrderSend).  |
//|                                                                    |
//|  Drive it from the EA's .set so its params == the EA's. All EA      |
//|  inputs are inherited verbatim from KK-MasterVP/Inputs.mqh; the     |
//|  display-only knobs below are prefixed InpViz* (no name clash).     |
//|                                                                    |
//|  PARITY SCOPE: reproduces every chart-deterministic gate + the      |
//|  replay-reproducible stateful ones (max-trades/session, one-        |
//|  position-at-a-time). The ONLY EA gate it ignores is the predictive |
//|  daily-DD cap (needs live equity; rarely binds) — by design.        |
//|                                                                    |
//|  Local POC: in the locked breakout-only config it is INERT (used    |
//|  only to tighten a REVERSION-trade SL, and reversion is OFF). It is  |
//|  drawn faint + labelled accordingly, not as a driver.               |
//+------------------------------------------------------------------+
#property copyright "KenKem / dquants"
#property version   "2.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

// plot1 mVAH
#property indicator_label1  "mVAH"
#property indicator_type1   DRAW_LINE
#property indicator_color1  C'120,160,210'
#property indicator_style1  STYLE_DOT
#property indicator_width1  1
// plot2 mVAL
#property indicator_label2  "mVAL"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'210,140,120'
#property indicator_style2  STYLE_DOT
#property indicator_width2  1
// plot3 mPOC
#property indicator_label3  "mPOC"
#property indicator_type3   DRAW_LINE
#property indicator_color3  C'200,200,90'
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1
// plot4 local POC (reversion-only; inert in the locked config)
#property indicator_label4  "localPOC (rev-only)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  C'90,90,90'
#property indicator_style4  STYLE_DOT
#property indicator_width4  1
// plot5 EMA fast (regime)
#property indicator_label5  "EMA fast (regime)"
#property indicator_type5   DRAW_LINE
#property indicator_color5  C'255,235,59'
#property indicator_width5  1
// plot6 EMA slow (regime)
#property indicator_label6  "EMA slow (regime)"
#property indicator_type6   DRAW_LINE
#property indicator_color6  C'156,39,176'
#property indicator_width6  2

//=== EA decision code (the single source of truth) ===================
#include "../../experts/VP-Common/Types.mqh"
#include "../../experts/VP-Common/VolumeProfile.mqh"
#include "../../experts/VP-Common/Regime.mqh"
#include "../../experts/VP-Common/NodeEngine.mqh"
#include "../../experts/KK-MasterVP/Inputs.mqh"
#include "../../experts/KK-MasterVP/Strategy.mqh"
#include "../../experts/KK-MasterVP/Decision.mqh"
#include "../../experts/KK-MasterVP/SessionNews.mqh"

//=== Display-only inputs (InpViz* — never clash with the EA's Inp*) ==
input group "===== Profiler display ====="
input bool   InpVizShowSetups   = true;   // draw EA entry markers (E/SL/TP1/TP2 + WON/LOST verdict)
input int    InpVizLookback      = 2500;   // bars replayed back (history cost cap)
input int    InpVizKeep          = 15;     // max recent setups drawn (oldest dropped)
input bool   InpVizShowTrail      = true;  // draw the SL->BE->ATR-trail stop path per trade
input bool   InpVizShowMasterVP   = true;  // master VAH/VAL/POC trail lines (at the EA's master length)
input bool   InpVizShowLocalPOC   = false; // local POC line (INERT in breakout-only — reversion SL only)
input bool   InpVizShowEMAs       = true;  // regime EMA fast/slow lines (the EMAs the EA actually uses)
input bool   InpVizShadeBlocked   = true;  // gray background over blocked trading hours (InpBlockedHoursStr)
input int    InpVizMaxBands       = 60;    // max blocked-hour shade bands drawn
input bool   InpVizShowPanel      = true;  // compact top-right status card

//=== Buffers ========================================================
double BufMVah[], BufMVal[], BufMPoc[], BufLPoc[], BufEmaF[], BufEmaS[];

#define OBJPFX "KKVPP_"

//=== Colors =========================================================
const color COL_BUY    = C'38,166,154';
const color COL_SELL   = C'239,83,80';
const color COL_UP_TXT = C'76,175,80';
const color COL_DN_TXT = C'239,83,80';
const color COL_BE     = C'255,167,38';   // BE / trail stop
const color COL_TP2    = C'38,166,154';

//=== EA-mirrored runtime state ======================================
CNodeEngine g_node;
int    hAtr=INVALID_HANDLE,hRsi=INVALID_HANDLE,hAdx=INVALID_HANDLE,hEmaF=INVALID_HANDLE,hEmaS=INVALID_HANDLE;
double g_pip=0.01,g_mintick=0.01;
int    g_masterLen=480;
int    g_digits=2;
datetime g_lastBar=0;

//=== Detected EA setups (rebuilt by the replay each new bar) =========
struct EaSetup {
   datetime tEntry, tExit;   // fill bar / final-exit bar open times
   int      dir;             // +1 long, -1 short
   int      status;          // 0 open, 1 WON (TP1 before SL), 2 LOST, 3 BE/trail stop in profit
   double   entry, sl, tp1, tp2, beLvl;
   bool     beArmed;
   string   reason;          // L-BRK / S-BRK / L-REV / S-REV
};
EaSetup g_setups[];
int     g_nSetups=0;

// Flat trail-path store (avoids dynamic arrays inside a struct array).
datetime g_trT[]; double g_trP[]; int g_trIdx[]; int g_trN=0;

//=== small helpers ==================================================
void ObjCommon(string id){ ObjectSetInteger(0,id,OBJPROP_HIDDEN,true); ObjectSetInteger(0,id,OBJPROP_SELECTABLE,false); }
void Seg(string id,datetime t1,double p1,datetime t2,double p2,color c,int w,ENUM_LINE_STYLE st){
   if(ObjectFind(0,id)<0){ if(!ObjectCreate(0,id,OBJ_TREND,0,t1,p1,t2,p2)) return; ObjCommon(id); ObjectSetInteger(0,id,OBJPROP_RAY_RIGHT,false); }
   ObjectSetInteger(0,id,OBJPROP_TIME,0,t1); ObjectSetDouble(0,id,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,id,OBJPROP_TIME,1,t2); ObjectSetDouble(0,id,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,id,OBJPROP_COLOR,c); ObjectSetInteger(0,id,OBJPROP_WIDTH,w); ObjectSetInteger(0,id,OBJPROP_STYLE,st);
}
void Rect(string id,datetime t1,double p1,datetime t2,double p2,color c){
   if(ObjectFind(0,id)<0){ if(!ObjectCreate(0,id,OBJ_RECTANGLE,0,t1,p1,t2,p2)) return; ObjCommon(id); ObjectSetInteger(0,id,OBJPROP_FILL,true); ObjectSetInteger(0,id,OBJPROP_BACK,true); }
   ObjectSetInteger(0,id,OBJPROP_TIME,0,t1); ObjectSetDouble(0,id,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,id,OBJPROP_TIME,1,t2); ObjectSetDouble(0,id,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,id,OBJPROP_COLOR,c);
}
void Txt(string id,datetime t,double p,string s,color c,int sz,ENUM_ANCHOR_POINT a){
   if(ObjectFind(0,id)<0){ if(!ObjectCreate(0,id,OBJ_TEXT,0,t,p)) return; ObjCommon(id); }
   ObjectSetInteger(0,id,OBJPROP_TIME,0,t); ObjectSetDouble(0,id,OBJPROP_PRICE,0,p);
   ObjectSetString(0,id,OBJPROP_TEXT,s); ObjectSetInteger(0,id,OBJPROP_COLOR,c);
   ObjectSetInteger(0,id,OBJPROP_FONTSIZE,sz); ObjectSetInteger(0,id,OBJPROP_ANCHOR,a);
}
void PanelBg(string id,int x,int y,int w,int h){
   if(ObjectFind(0,id)<0){ if(!ObjectCreate(0,id,OBJ_RECTANGLE_LABEL,0,0,0)) return; ObjCommon(id);
      ObjectSetInteger(0,id,OBJPROP_CORNER,CORNER_RIGHT_UPPER); ObjectSetInteger(0,id,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,id,OBJPROP_BGCOLOR,C'18,22,28'); ObjectSetInteger(0,id,OBJPROP_COLOR,C'70,80,90'); }
   ObjectSetInteger(0,id,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,id,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,id,OBJPROP_XSIZE,w); ObjectSetInteger(0,id,OBJPROP_YSIZE,h);
}
void Lbl(string id,int x,int y,string s,color c){
   if(ObjectFind(0,id)<0){ if(!ObjectCreate(0,id,OBJ_LABEL,0,0,0)) return; ObjCommon(id);
      ObjectSetInteger(0,id,OBJPROP_CORNER,CORNER_RIGHT_UPPER); ObjectSetInteger(0,id,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
      ObjectSetString(0,id,OBJPROP_FONT,"Consolas"); ObjectSetInteger(0,id,OBJPROP_FONTSIZE,8); }
   ObjectSetInteger(0,id,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,id,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,id,OBJPROP_TEXT,s); ObjectSetInteger(0,id,OBJPROP_COLOR,c);
}

// Bulk-copy a handle buffer into a NON-series array aligned to the price arrays
// (index 0 = oldest). Returns false if the indicator isn't ready yet.
bool CopyAligned(int handle,int bufNum,int count,double &dst[]){
   ArraySetAsSeries(dst,false);
   if(handle==INVALID_HANDLE) return false;
   return (CopyBuffer(handle,bufNum,0,count,dst)==count);
}

// Master/local VP over `count` bars ending at index endIdx (inclusive).
bool VPSlice(const double &H[],const double &L[],const double &C[],const long &V[],
             int endIdx,int count,VPResult &out){
   int start=endIdx-count+1;
   if(start<0){ out.valid=false; return false; }
   double h[],l[],c[]; long v[];
   ArrayResize(h,count); ArrayResize(l,count); ArrayResize(c,count); ArrayResize(v,count);
   for(int k=0;k<count;k++){ int idx=start+k; h[k]=H[idx]; l[k]=L[idx]; c[k]=C[idx]; v[k]=V[idx]; }
   out=VP_ComputeBars(h,l,c,v,count,InpVpBins,InpVaPct);
   return out.valid;
}

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0,BufMVah,INDICATOR_DATA); SetIndexBuffer(1,BufMVal,INDICATOR_DATA);
   SetIndexBuffer(2,BufMPoc,INDICATOR_DATA); SetIndexBuffer(3,BufLPoc,INDICATOR_DATA);
   SetIndexBuffer(4,BufEmaF,INDICATOR_DATA); SetIndexBuffer(5,BufEmaS,INDICATOR_DATA);
   for(int i=0;i<6;i++) PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   ArraySetAsSeries(BufMVah,false); ArraySetAsSeries(BufMVal,false); ArraySetAsSeries(BufMPoc,false);
   ArraySetAsSeries(BufLPoc,false); ArraySetAsSeries(BufEmaF,false); ArraySetAsSeries(BufEmaS,false);

   hAtr =iATR(_Symbol,PERIOD_CURRENT,InpAtrLen);
   hRsi =iRSI(_Symbol,PERIOD_CURRENT,InpRsiLen,PRICE_CLOSE);
   hAdx =iADX(_Symbol,PERIOD_CURRENT,InpAdxLen);
   hEmaF=iMA(_Symbol,PERIOD_CURRENT,InpEmaFast,0,MODE_EMA,PRICE_CLOSE);
   hEmaS=iMA(_Symbol,PERIOD_CURRENT,InpEmaSlow,0,MODE_EMA,PRICE_CLOSE);
   if(hAtr==INVALID_HANDLE||hRsi==INVALID_HANDLE||hAdx==INVALID_HANDLE||hEmaF==INVALID_HANDLE||hEmaS==INVALID_HANDLE)
      return INIT_FAILED;

   g_masterLen=InpVpLookback*InpMasterMult;
   g_node.Init(InpVpBins);
   SN_Init();

   g_digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   g_mintick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(StringFind(_Symbol,"BTCUSD")>=0) g_pip=1.0;
   else                                g_pip=MathPow(10.0,-g_digits);
   if(g_mintick<=0) g_mintick=g_pip;

   IndicatorSetString(INDICATOR_SHORTNAME,"KK-MasterVP-Profiler (EA twin)");
   PrintFormat("[Profiler] init pip=%.5f masterLen=%d (VP %dx%d) — EA-replay parity",
               g_pip,g_masterLen,InpVpLookback,InpMasterMult);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){
   IndicatorRelease(hAtr); IndicatorRelease(hRsi); IndicatorRelease(hAdx);
   IndicatorRelease(hEmaF); IndicatorRelease(hEmaS);
   ObjectsDeleteAll(0,OBJPFX);
}

//+------------------------------------------------------------------+
//| EA replay — fills g_setups + the master-VP/EMA buffers.          |
//| Mirrors Engine.mqh::OnNewBar shift map: forming bar = b,         |
//| shift1 = b-1, shift2 = b-2, master VP ends at b-1, fill at the   |
//| open of bar b (entry price = close[b-1] = sig.entry).            |
//+------------------------------------------------------------------+
void ReplayEA(int rt,const datetime &time[],const double &open[],const double &high[],
              const double &low[],const double &close[],const long &tvol[])
{
   g_nSetups=0; g_trN=0;
   double atr[],rsi[],adxM[],adxP[],adxN[],emaF[],emaS[];
   if(!CopyAligned(hAtr,0,rt,atr))  return;
   if(!CopyAligned(hRsi,0,rt,rsi))  return;
   if(!CopyAligned(hAdx,0,rt,adxM)) return;
   if(!CopyAligned(hAdx,1,rt,adxP)) return;
   if(!CopyAligned(hAdx,2,rt,adxN)) return;
   if(!CopyAligned(hEmaF,0,rt,emaF))return;
   if(!CopyAligned(hEmaS,0,rt,emaS))return;

   // export EMA buffers for the plotted regime lines
   if(InpVizShowEMAs) for(int i=0;i<rt;i++){ BufEmaF[i]=emaF[i]; BufEmaS[i]=emaS[i]; }

   // node engine warms from here; entries are only KEPT from drawFrom onward.
   g_node.Init(InpVpBins);
   g_curSessionId=-1; g_tradesThisSession=0;      // reset the SN per-session counter
   int b0=MathMax(g_masterLen+2,2);
   int lookStart=MathMax(b0,rt-InpVizLookback);
   int occUntil=-1;                                // one-position-at-a-time bookkeeping

   for(int b=b0;b<rt;b++){
      double a1=atr[b-1], a2=atr[b-2];
      if(a1<=0.0||a2<=0.0||close[b-1]<=0.0) continue;

      // master + local VP through the just-closed bar (b-1)
      VPResult masterCur; if(!VPSlice(high,low,close,tvol,b-1,g_masterLen,masterCur)) continue;
      VPResult localCur;  VPSlice(high,low,close,tvol,b-1,InpVpLookback,localCur);

      // node engine: update once per closed bar (decay is stateful → every bar)
      g_node.Update(masterCur,open[b-1],high[b-1],low[b-1],close[b-1],tvol[b-1],a1,
                    g_pip,g_mintick,InpNodeTouchAtr,InpNodeDecay);

      // master-VP display buffers (drawn over the visible window)
      if(b>=lookStart){
         if(InpVizShowMasterVP){ BufMVah[b]=masterCur.vah; BufMVal[b]=masterCur.val; BufMPoc[b]=masterCur.poc; }
         if(InpVizShowLocalPOC && localCur.valid) BufLPoc[b]=localCur.poc;
      }

      // session/day context in the reference tz, exactly as Engine.mqh OnNewBar
      datetime ref=SN_RefTime(time[b-1]);
      datetime utc=SN_UtcTime(time[b-1]);
      int sessionId=SN_UpdateSession(ref);

      // regime + signal (shift map identical to the EA caller)
      RegimeState regime=VP_ComputeRegime(a1,emaF[b-1],emaS[b-1],adxM[b-1],adxP[b-1],adxN[b-1],
                                          InpAdxTrendMin,InpDiSpreadMin,InpEmaSepAtr);
      SignalBar s; s.o=open[b-2]; s.h=high[b-2]; s.l=low[b-2]; s.c=close[b-2];
      s.atr2=a2; s.atr1=a1; s.entry_close=close[b-1];
      NodeState nsVah=g_node.StateAtPrice(masterCur.vah,InpNodeSaturation,InpNodeNeutralBand);
      NodeState nsVal=g_node.StateAtPrice(masterCur.val,InpNodeSaturation,InpNodeNeutralBand);
      NodeState nsPx =g_node.StateAtPrice(s.c,InpNodeSaturation,InpNodeNeutralBand);
      Signal sig=MVP_DetectSignal(masterCur,masterCur,localCur,regime,s,nsVah,nsVal,nsPx,g_pip,g_mintick,1.0);
      if(!sig.valid) continue;

      // chart-deterministic gates (shared verbatim with the EA via Decision.mqh)
      double atrPct=a1/close[b-1]*100.0;
      if(!MVP_DeterministicGatesPass(sig,sessionId,atrPct,a1,g_mintick,
                                     SN_IsBlockedHour(ref),SN_InNewsWindow(utc),0.0,0.0,rsi[b-1]))
         continue;

      // replay-reproducible stateful gates: one-position + max-trades/session.
      // (daily-DD ignored by design; spread/peak-DD/cooldown off in the lock.)
      if(b<=occUntil) continue;
      if(!SN_MaxTradesOk()) continue;

      // FIRE — fill at the open of bar b (entry = close[b-1] = sig.entry)
      SN_OnFill();
      int dir=sig.is_long?1:-1;
      double entry=sig.entry, sl=sig.sl, risk=sig.risk;

      // forward exit replay (EA management: TP1 → BE → ATR chandelier trail; runner cap)
      double tp1=sig.tp1;
      double best=entry, slEff=sl; bool tp1done=false, beArmed=false; double beLvl=0.0;
      int status=0, exitBar=rt-1;
      double tpRun=dir>0 ? entry+risk*InpRunnerRr : entry-risk*InpRunnerRr;
      // record the initial stop in the trail path
      if(InpVizShowTrail && b>=lookStart){ ArrayResize(g_trT,g_trN+1); ArrayResize(g_trP,g_trN+1); ArrayResize(g_trIdx,g_trN+1);
         g_trT[g_trN]=time[b]; g_trP[g_trN]=slEff; g_trIdx[g_trN]=g_nSetups; g_trN++; }
      for(int j=b;j<rt;j++){
         double jatr=(j>=1?atr[j-1]:a1); if(jatr<=0.0) jatr=a1;
         bool hitSL=(dir>0)?(low[j]<=slEff):(high[j]>=slEff);
         if(!tp1done){
            bool hitTP1=(dir>0)?(high[j]>=tp1):(low[j]<=tp1);
            if(hitSL){ status=2; exitBar=j; break; }            // SL before TP1 → LOST
            if(hitTP1){
               tp1done=true; status=1;                          // TP1 touched → WON
               if(InpBeAfterTp1){ beArmed=true; beLvl=(dir>0)?entry+InpBeBufAtr*jatr:entry-InpBeBufAtr*jatr;
                  slEff=(dir>0)?MathMax(slEff,beLvl):MathMin(slEff,beLvl); }
            }
         } else {
            if(hitSL){ status=(dir>0)?((slEff>=entry)?3:2):((slEff<=entry)?3:2); exitBar=j; break; }
         }
         // update best + ATR chandelier trail (tighten-only), after TP1
         if(dir>0){ if(high[j]>best) best=high[j]; } else { if(low[j]<best||best==entry) best=low[j]; }
         if(tp1done && InpTrailRunner){
            double trail=(dir>0)?best-InpTrailAtrMult*jatr:best+InpTrailAtrMult*jatr;
            slEff=(dir>0)?MathMax(slEff,trail):MathMin(slEff,trail);
         }
         bool hitRun=(dir>0)?(high[j]>=tpRun):(low[j]<=tpRun);
         if(hitRun){ status=(status==0?1:status); exitBar=j; break; }
         if(InpVizShowTrail && b>=lookStart){ ArrayResize(g_trT,g_trN+1); ArrayResize(g_trP,g_trN+1); ArrayResize(g_trIdx,g_trN+1);
            g_trT[g_trN]=time[j]; g_trP[g_trN]=slEff; g_trIdx[g_trN]=g_nSetups; g_trN++; }
      }
      occUntil=exitBar;

      if(b>=lookStart){
         if(g_nSetups>=ArraySize(g_setups)) ArrayResize(g_setups,g_nSetups+32);
         g_setups[g_nSetups].tEntry=time[b];
         g_setups[g_nSetups].tExit =time[exitBar];
         g_setups[g_nSetups].dir   =dir;
         g_setups[g_nSetups].status=status;
         g_setups[g_nSetups].entry =entry;
         g_setups[g_nSetups].sl    =sl;
         g_setups[g_nSetups].tp1   =tp1;
         g_setups[g_nSetups].tp2   =sig.tp2;
         g_setups[g_nSetups].beLvl =beLvl;
         g_setups[g_nSetups].beArmed=beArmed;
         g_setups[g_nSetups].reason=sig.reason;
         g_nSetups++;
      }
   }
}

//+------------------------------------------------------------------+
void DrawSetups(int rt,const datetime &time[])
{
   ObjectsDeleteAll(0,OBJPFX "st");
   if(!InpVizShowSetups || g_nSetups<=0) return;
   int ps=PeriodSeconds(_Period);
   int keep=(int)MathMax(1,MathMin(InpVizKeep,100));
   int first=(int)MathMax(0,g_nSetups-keep);
   datetime tNow=time[rt-1];

   for(int k=first;k<g_nSetups;k++){
      string idp=OBJPFX "st"+IntegerToString(k)+"_";
      datetime t0=g_setups[k].tEntry;
      datetime tR=(g_setups[k].tExit>t0)?g_setups[k].tExit:tNow;
      if(tR<t0+(datetime)(5*ps)) tR=t0+(datetime)(5*ps);
      color dCol=(g_setups[k].dir>0)?COL_BUY:COL_SELL;

      Seg(idp+"e", t0,g_setups[k].entry,tR,g_setups[k].entry,clrSilver,2,STYLE_SOLID);
      Seg(idp+"sl",t0,g_setups[k].sl,   tR,g_setups[k].sl,   COL_SELL,1,STYLE_SOLID);
      Seg(idp+"t1",t0,g_setups[k].tp1,  tR,g_setups[k].tp1,  COL_BUY, 1,STYLE_SOLID);
      Seg(idp+"t2",t0,g_setups[k].tp2,  tR,g_setups[k].tp2,  COL_TP2, 1,STYLE_DOT);

      Txt(idp+"eT", t0,g_setups[k].entry,
          (g_setups[k].dir>0?"▲ ":"▼ ")+g_setups[k].reason+" "+DoubleToString(g_setups[k].entry,g_digits),
          dCol,8,ANCHOR_LEFT_LOWER);
      Txt(idp+"slT",t0,g_setups[k].sl, "SL "+DoubleToString(g_setups[k].sl, g_digits),COL_DN_TXT,8,ANCHOR_LEFT_UPPER);
      Txt(idp+"t1T",t0,g_setups[k].tp1,"TP1 "+DoubleToString(g_setups[k].tp1,g_digits),COL_UP_TXT,8,ANCHOR_LEFT_LOWER);
      Txt(idp+"t2T",t0,g_setups[k].tp2,"TP2 "+DoubleToString(g_setups[k].tp2,g_digits),COL_TP2,   8,ANCHOR_LEFT_LOWER);

      string oc=(g_setups[k].status==1)?"WON":(g_setups[k].status==2)?"LOST":(g_setups[k].status==3)?"BE":"OPEN";
      color  occ=(g_setups[k].status==1)?COL_UP_TXT:(g_setups[k].status==2)?COL_DN_TXT:clrSilver;
      Txt(idp+"o",t0-(datetime)ps,g_setups[k].entry,oc+" ",occ,9,ANCHOR_RIGHT_LOWER);
   }

   // SL→BE→trail stop path: connect consecutive recorded points within each setup
   if(InpVizShowTrail){
      for(int i=1;i<g_trN;i++){
         if(g_trIdx[i]!=g_trIdx[i-1]) continue;
         if(g_trIdx[i]<first) continue;
         string tid=OBJPFX "sttr"+IntegerToString(i);
         Seg(tid,g_trT[i-1],g_trP[i-1],g_trT[i],g_trP[i],COL_BE,1,STYLE_DOT);
      }
   }
}

//+------------------------------------------------------------------+
//| Gray background over blocked trading hours (InpBlockedHoursStr). |
//+------------------------------------------------------------------+
void ShadeBlocked(int rt,const datetime &time[],const double &high[],const double &low[])
{
   ObjectsDeleteAll(0,OBJPFX "blk");
   if(!InpVizShadeBlocked) return;
   int from=(int)MathMax(1,rt-InpVizLookback);
   // price span of the visible window (a little padding so the band fills the pane)
   double pHi=-DBL_MAX,pLo=DBL_MAX;
   for(int i=from;i<rt;i++){ if(high[i]>pHi) pHi=high[i]; if(low[i]<pLo) pLo=low[i]; }
   if(pHi<=pLo) return;
   double pad=(pHi-pLo)*0.04; pHi+=pad; pLo-=pad;
   int ps=PeriodSeconds(_Period), bands=0;
   int i=from;
   while(i<rt && bands<InpVizMaxBands){
      bool blk=SN_IsBlockedHour(SN_RefTime(time[i]));
      if(!blk){ i++; continue; }
      int j=i; while(j<rt && SN_IsBlockedHour(SN_RefTime(time[j]))) j++;   // run [i..j-1]
      string id=OBJPFX "blk"+IntegerToString(bands);
      datetime t2=(j<rt)?time[j]:time[rt-1]+(datetime)ps;
      Rect(id,time[i],pHi,t2,pLo,C'40,44,52');
      bands++; i=j;
   }
}

//+------------------------------------------------------------------+
void DrawPanel(int rt)
{
   string bg=OBJPFX "pbg";
   if(!InpVizShowPanel){ ObjectsDeleteAll(0,OBJPFX "p"); return; }
   PanelBg(bg,6,18,234,104);
   int won=0,lost=0,be=0,open=0;
   for(int k=0;k<g_nSetups;k++){ int st=g_setups[k].status;
      if(st==1) won++; else if(st==2) lost++; else if(st==3) be++; else open++; }
   int decided=won+lost+be;
   double hit=(decided>0)?100.0*(won+be)/decided:0.0;
   int x=14,y=24,dy=15;
   Lbl(OBJPFX "p0",x,y,           "KK-MasterVP — EA twin",   C'180,200,220'); y+=dy;
   Lbl(OBJPFX "p1",x,y, StringFormat("master VP %d bars (%dx%d)",g_masterLen,InpVpLookback,InpMasterMult),clrSilver); y+=dy;
   Lbl(OBJPFX "p2",x,y, StringFormat("setups %d  WON %d  LOST %d  BE %d",g_nSetups,won,lost,be),clrSilver); y+=dy;
   Lbl(OBJPFX "p3",x,y, StringFormat("hit (incl BE) %.0f%%   open %d",hit,open),clrSilver); y+=dy;
   string bh=(StringLen(InpBlockedHoursStr)>0)?InpBlockedHoursStr:"(none)";
   Lbl(OBJPFX "p4",x,y, "blocked hrs(refTZ): "+bh, C'255,167,38'); y+=dy;
   Lbl(OBJPFX "p5",x,y, "reversion: "+(InpEnableReversion?"ON":"OFF (localPOC inert)"),C'150,150,150');
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<g_masterLen+5) return rates_total;
   ArraySetAsSeries(time,false); ArraySetAsSeries(open,false); ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);  ArraySetAsSeries(close,false); ArraySetAsSeries(tick_volume,false);

   // recompute only on a new closed bar (the replay is deterministic & O(lookback))
   if(time[rates_total-1]==g_lastBar && prev_calculated>0) return rates_total;
   g_lastBar=time[rates_total-1];

   // clear plotted buffers, then refill over the replay
   for(int i=0;i<rates_total;i++){ BufMVah[i]=EMPTY_VALUE; BufMVal[i]=EMPTY_VALUE; BufMPoc[i]=EMPTY_VALUE;
      BufLPoc[i]=EMPTY_VALUE; BufEmaF[i]=EMPTY_VALUE; BufEmaS[i]=EMPTY_VALUE; }

   ReplayEA(rates_total,time,open,high,low,close,tick_volume);
   ShadeBlocked(rates_total,time,high,low);
   DrawSetups(rates_total,time);
   DrawPanel(rates_total);
   ChartRedraw();
   return rates_total;
}
//+------------------------------------------------------------------+
