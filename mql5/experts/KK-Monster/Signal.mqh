//+------------------------------------------------------------------+
//|  KK-Monster/Signal.mqh — 4-kind signal core (breakout / rev1 /    |
//|  rev2 / impulse). Faithful transcription of cpp_core               |
//|  kk::monster::evaluate_monster_signals + NodeEngine + VP + regime  |
//|  + fresh-cross registry. Self-contained structs (no include clash).|
//+------------------------------------------------------------------+
#ifndef KKM_SIGNAL_MQH
#define KKM_SIGNAL_MQH

#include "Config.mqh"

int MonClampi(int v,int lo,int hi){ return v<lo?lo:(v>hi?hi:v); }

struct MVP { bool valid; double poc,vah,val,hi,lo; };
struct MonRegime { bool slope_known; double slope_norm; bool mpoc_slope_up,mpoc_slope_dn; bool poc_stable; };
struct MonNet { double netM1,netM3,netM5,netM15; bool hasM1,hasM5,hasM15,ovhRawLong,ovhRawShort; };
struct MonSignal {
   bool valid,is_long; int kind; double entry,sl,tp1,tp2,risk,edge; string reason;
   double f_brk_dist_atr,f_body_pct,f_slope,f_net_m1,f_net_m3,f_net_m5,f_atr_pct;
};
// kinds: 1=brk 2=rev1 3=rev2 4=impulse
void MonSigReset(MonSignal &s){ s.valid=false; s.is_long=false; s.kind=0; s.entry=0; s.sl=0; s.tp1=0; s.tp2=0; s.risk=0; s.edge=0; s.reason=""; }

void MonBuildVA(const double &hist[],int bins,double lo,double step,double vaPct,MVP &res)
{
   double total=0; int pocIdx=0; double pocVol=-1;
   for(int b=0;b<bins;b++){ double hv=hist[b]; total+=hv; if(hv>pocVol){ pocVol=hv; pocIdx=b; } }
   double target=total*(vaPct*0.01); double acc=hist[pocIdx]; int loIdx=pocIdx,hiIdx=pocIdx;
   while(acc<target && (loIdx>0||hiIdx<bins-1)){
      double nL=(loIdx>0)?hist[loIdx-1]:-1.0, nH=(hiIdx<bins-1)?hist[hiIdx+1]:-1.0;
      if(nH>=nL){ hiIdx++; acc+=hist[hiIdx]; } else { loIdx--; acc+=hist[loIdx]; }
   }
   res.poc=lo+(pocIdx+0.5)*step; res.vah=lo+(hiIdx+1.0)*step; res.val=lo+loIdx*step;
}

// VP over m3 bars [newestIdx-useLen+1 .. newestIdx]; skipOld drops oldest N (predicted master).
// bars passed as series arrays h[]/l[]/c[]/v[] indexed by SHIFT (0=newest); newestShift = shift of window's newest bar.
void MonComputeVP(const double &h[],const double &l[],const double &c[],const long &v[],int total,
                  int newestShift,int len,int bins,double vaPct,int skipOld,MVP &r)
{
   r.valid=false;
   int useLen=MathMax(bins,len-skipOld);
   int oldestShift=newestShift+useLen-1;            // older = larger shift
   if(newestShift<0 || oldestShift>=total || bins<1) return;
   double hi=-1e300,lo=1e300;
   for(int s=newestShift;s<=oldestShift;s++){ if(h[s]>hi) hi=h[s]; if(l[s]<lo) lo=l[s]; }
   if(!(hi>lo)) return;
   double step=(hi-lo)/bins; if(step<=0) return;
   double hist[]; ArrayResize(hist,bins); ArrayInitialize(hist,0.0);
   for(int s=newestShift;s<=oldestShift;s++){
      double hlc3=(h[s]+l[s]+c[s])/3.0; double vol=(v[s]>0)?(double)v[s]:1.0;
      int bi=MonClampi((int)MathFloor((hlc3-lo)/step),0,bins-1); hist[bi]+=vol;
   }
   MonBuildVA(hist,bins,lo,step,vaPct,r); r.hi=hi; r.lo=lo; r.valid=true;
}

//============ NODE ENGINE (sliding master grid) ============
struct MonNode {
   double buy[],sell[],touch[]; double mLo,mHi,mStep; int bins;
   void Init(int n){ bins=n; ArrayResize(buy,n); ArrayResize(sell,n); ArrayResize(touch,n);
      ArrayInitialize(buy,0); ArrayInitialize(sell,0); ArrayInitialize(touch,0); mLo=0; mHi=0; mStep=0; }
   void Accumulate(double o,double h,double l,double c,double vol,double atr,const MVP &m,const MonsterConfig &cfg){
      if(!m.valid) return; double lo=m.lo,hi=m.hi; double step=(hi-lo)/bins; if(step<=0) return;
      mLo=lo; mHi=hi; mStep=step; if(o<=0||h<=0||l<=0||c<=0||h<l) return;
      double td=MathMax(cfg.node_touch_atr*atr,2.0*cfg.mintick);
      double dp=(c-o)/MathMax(h-l,cfg.mintick); double bP=vol*MathMax(dp,0.0), sP=vol*MathMax(-dp,0.0);
      for(int b=0;b<bins;b++){ buy[b]*=cfg.node_decay; sell[b]*=cfg.node_decay; touch[b]*=cfg.node_decay; }
      int li=MonClampi((int)MathFloor((l-lo)/step),0,bins-1), hI=MonClampi((int)MathFloor((h-lo)/step),0,bins-1);
      double span=MathMax((double)(hI-li+1),1.0);
      for(int b=li;b<=hI;b++){ double npx=lo+(b+0.5)*step; bool t=(MathAbs(c-npx)<=td)||(l<=npx&&h>=npx);
         if(t){ touch[b]+=1.0; buy[b]+=bP/span; sell[b]+=sP/span; } }
   }
   double NetM3W(double px,double atrC,const MonsterConfig &cfg) const {
      if(mStep<=0||atrC<=0) return 0.0; double nd=cfg.net_win_atr*atrC; double mx=0;
      if(cfg.use_weighted_net) for(int b=0;b<bins;b++){ double bpx=mLo+(b+0.5)*mStep; if(MathAbs(bpx-px)<=nd) mx=MathMax(mx,buy[b]+sell[b]); }
      double tB=0,tS=0;
      for(int b=0;b<bins;b++){ double bpx=mLo+(b+0.5)*mStep; if(MathAbs(bpx-px)>nd) continue;
         double bv=buy[b],sv=sell[b],w=1.0;
         if(cfg.use_weighted_net&&mx>0){ double tier=(bv+sv)/mx; w=(tier>0.66)?cfg.w_hvn:(tier<0.33?cfg.w_lvn:cfg.w_mvn); }
         if(bv>sv) tB+=(bv-sv)*w; else tS+=(sv-bv)*w; }
      double tot=tB+tS; return (tot>0)?(tB-tS)/tot:0.0;
   }
   double HvnShelfSL(bool isLong,double entry,double atrv,double fb,const MonsterConfig &cfg) const {
      if(mStep<=0||atrv<=0) return fb;
      double nB=isLong?entry-cfg.shelf_near_atr*atrv:entry+cfg.shelf_near_atr*atrv;
      double fB=isLong?entry-cfg.shelf_far_atr*atrv:entry+cfg.shelf_far_atr*atrv;
      double wLo=MathMin(nB,fB),wHi=MathMax(nB,fB); double bestVol=0,bestPx=0;
      for(int b=0;b<bins;b++){ double bpx=mLo+(b+0.5)*mStep; if(bpx<wLo||bpx>wHi) continue; double v=buy[b]+sell[b]; if(v>bestVol){ bestVol=v; bestPx=bpx; } }
      if(bestVol<=0) return fb; double cand=isLong?bestPx-cfg.shelf_buf_atr*atrv:bestPx+cfg.shelf_buf_atr*atrv;
      if(isLong&&cand>=entry) return fb; if(!isLong&&cand<=entry) return fb; return cand;
   }
   double StructuralTP2(bool isLong,double entry,double risk,double tp1Px,double atrv,const MVP &pred,double fb,const MonsterConfig &cfg) const {
      if(risk<=0||atrv<=0) return fb; double cand=0;
      if(mStep>0){ double mxVol=0; for(int b=0;b<bins;b++) mxVol=MathMax(mxVol,buy[b]+sell[b]);
         if(mxVol>0){ if(isLong){ for(int b=0;b<bins;b++){ double bpx=mLo+(b+0.5)*mStep; if(bpx<=tp1Px) continue; if((buy[b]+sell[b])>=cfg.stp2_hvn_frac*mxVol){ cand=bpx-cfg.stp2_edge_off_atr*atrv; break; } } }
            else { for(int b=bins-1;b>=0;b--){ double bpx=mLo+(b+0.5)*mStep; if(bpx>=tp1Px) continue; if((buy[b]+sell[b])>=cfg.stp2_hvn_frac*mxVol){ cand=bpx+cfg.stp2_edge_off_atr*atrv; break; } } } } }
      if(cand<=0&&pred.valid) cand=isLong?pred.vah:pred.val; if(cand<=0) return fb;
      double cR=isLong?(cand-entry)/risk:(entry-cand)/risk; double rr=MathMin(MathMax(cR,cfg.stp2_min_rr),cfg.stp2_max_rr);
      return isLong?entry+rr*risk:entry-rr*risk;
   }
};

//============ master-POC history (regime/slope) ============
struct MonMPoc {
   double hist[]; int count;
   void Init(int slopeBars){ int capn=MathMax(slopeBars+2,4); ArrayResize(hist,capn); ArrayInitialize(hist,0); count=0; }
   void Push(double mPoc){ int capn=ArraySize(hist); if(capn<=0) return; for(int i=MathMin(count,capn-1);i>0;i--) hist[i]=hist[i-1]; hist[0]=mPoc; if(count<capn) count++; }
   bool BarsAgo(int ba,double &out){ if(ba<1||ba>count) return false; out=hist[ba-1]; return (out>0); }
   void ComputeRegime(double atrv,double mPoc,bool pV,double pMPoc,const MonsterConfig &cfg,MonRegime &r){
      r.slope_known=false; r.slope_norm=0; r.mpoc_slope_up=false; r.mpoc_slope_dn=false; double pa;
      if(mPoc>0&&atrv>0&&BarsAgo(cfg.impulse_trend_slope_bars,pa)){ r.slope_known=true; r.slope_norm=(mPoc-pa)/atrv; r.mpoc_slope_up=(mPoc>pa); r.mpoc_slope_dn=(mPoc<pa); }
      r.poc_stable=true; if(pV&&atrv>0) r.poc_stable=(MathAbs(pMPoc-mPoc)<=cfg.poc_stable_max_atr*atrv);
   }
};

//============ fresh-cross registry ============
struct MonCross {
   int xiUpVah,xiDnVal,xiUpPoc,xiDnPoc,xiUpVal,xiDnVah;
   double prevClose,prevMVah,prevMVal,prevMPoc; bool prevLvlValid; int lastLongEntryBar,lastShortEntryBar;
   void Init(){ xiUpVah=-1;xiDnVal=-1;xiUpPoc=-1;xiDnPoc=-1;xiUpVal=-1;xiDnVah=-1; prevClose=0;prevMVah=0;prevMVal=0;prevMPoc=0; prevLvlValid=false; lastLongEntryBar=-1; lastShortEntryBar=-1; }
   void UpdateFresh(double cl,const MVP &m,int sbi){
      if(m.valid&&prevLvlValid&&prevClose>0){
         if(cl>m.vah&&prevClose<=prevMVah) xiUpVah=sbi; if(cl<m.val&&prevClose>=prevMVal) xiDnVal=sbi;
         if(cl>m.poc&&prevClose<=prevMPoc) xiUpPoc=sbi; if(cl<m.poc&&prevClose>=prevMPoc) xiDnPoc=sbi;
         if(cl>m.val&&prevClose<=prevMVal) xiUpVal=sbi; if(cl<m.vah&&prevClose>=prevMVah) xiDnVah=sbi;
      }
      if(m.valid){ prevClose=cl; prevMVah=m.vah; prevMVal=m.val; prevMPoc=m.poc; prevLvlValid=true; } else prevLvlValid=false;
   }
   void Consume(int kind,bool isLong){ if(kind==1){ if(isLong) xiUpVah=-1; else xiDnVal=-1; } else if(kind==2){ if(isLong) xiUpPoc=-1; else xiDnPoc=-1; } else if(kind==3){ if(isLong) xiUpVal=-1; else xiDnVah=-1; } }
};
bool MonFresh(int xi,int bars,int sbi){ return (xi>=0)&&(sbi-xi)<=bars; }

//============ FULL ENTRY EVALUATION ============
void EvaluateMonster(const MonsterConfig &cfg,double o,double h,double l,double c,
                     const MVP &mC,const MVP &lC,const MVP &pC,const MonRegime &reg,double atrv,double atrPct,
                     bool atrCeilOk,bool inVolCeilBand,int sbi,const MonNode &node,const MonCross &cross,const MonNet &net,
                     MonSignal &L,MonSignal &S)
{
   MonSigReset(L); MonSigReset(S);
   if(!(mC.valid&&lC.valid)||atrv<=0) return;
   if(c<=0||o<=0||h<=0||l<=0||h<l) return;
   double mVah=mC.vah,mVal=mC.val,mPoc=mC.poc, vah=lC.vah,val=lC.val,poc=lC.poc;

   bool netLongOk=(net.netM3>=cfg.brk_net_min_m3)||(cfg.net_confirm_m1_or_m3&&net.hasM1&&net.netM1>=cfg.brk_net_min)||(cfg.net_confirm_m5&&net.hasM5&&net.netM5>=cfg.brk_net_min);
   bool netShortOk=(net.netM3<=-cfg.brk_net_min_m3)||(cfg.net_confirm_m1_or_m3&&net.hasM1&&net.netM1<=-cfg.brk_net_min)||(cfg.net_confirm_m5&&net.hasM5&&net.netM5<=-cfg.brk_net_min);
   bool oppLongOk=(net.netM3>-cfg.brk_opp_max)&&(!net.hasM5||net.netM5>-cfg.brk_opp_max);
   bool oppShortOk=(net.netM3<cfg.brk_opp_max)&&(!net.hasM5||net.netM5<cfg.brk_opp_max);
   bool rNetLongOk=(net.netM3>=cfg.rev_net_min)||(cfg.net_confirm_m1_or_m3&&net.hasM1&&net.netM1>=cfg.rev_net_min)||(cfg.net_confirm_m5&&net.hasM5&&net.netM5>=cfg.rev_net_min);
   bool rNetShortOk=(net.netM3<=-cfg.rev_net_min)||(cfg.net_confirm_m1_or_m3&&net.hasM1&&net.netM1<=-cfg.rev_net_min)||(cfg.net_confirm_m5&&net.hasM5&&net.netM5<=-cfg.rev_net_min);
   bool rOppLongOk=(net.netM3>-cfg.rev_opp_max)&&(!net.hasM5||net.netM5>-cfg.rev_opp_max);
   bool rOppShortOk=(net.netM3<cfg.rev_opp_max)&&(!net.hasM5||net.netM5<cfg.rev_opp_max);
   bool gateBrkL=!cfg.enable_regime_gate||(reg.slope_known&&reg.slope_norm>=cfg.regime_tau_high);
   bool gateBrkS=!cfg.enable_regime_gate||(reg.slope_known&&reg.slope_norm<=-cfg.regime_tau_high);
   bool gateRev=!cfg.enable_regime_gate||(reg.slope_known&&MathAbs(reg.slope_norm)<=cfg.regime_tau_low);
   bool brkPocOk=!cfg.brk_require_poc_stable||reg.poc_stable; bool revPocOk=!cfg.rev_require_poc_stable||reg.poc_stable;
   bool htfBull=net.hasM5&&net.hasM15&&(net.netM5>=cfg.htf_bias_min)&&(net.netM15>=cfg.htf_bias_min);
   bool htfBear=net.hasM5&&net.hasM15&&(net.netM5<=-cfg.htf_bias_min)&&(net.netM15<=-cfg.htf_bias_min);
   bool gateHtfL=!cfg.enable_htf_bias||(cfg.htf_require_align?htfBull:!htfBear);
   bool gateHtfS=!cfg.enable_htf_bias||(cfg.htf_require_align?htfBear:!htfBull);
   bool ovhBlockL=cfg.brk_overhead_veto&&net.ovhRawLong; bool ovhBlockS=cfg.brk_overhead_veto&&net.ovhRawShort;

   double slBrkL=MathMin(mVah-cfg.brk_sl_buf_atr*atrv,c-cfg.brk_sl_atr_mult*atrv); double riskBrkL=c-slBrkL;
   bool recentL=(cross.lastLongEntryBar>=0)&&(sbi-cross.lastLongEntryBar)<=cfg.brk_rr_lookback_bars; double rrBrkL=recentL?cfg.brk_rr_near:cfg.brk_rr_far; double tpBrkL=c+rrBrkL*riskBrkL;
   bool sigBrkL=cfg.enable_breakout&&MonFresh(cross.xiUpVah,cfg.brk_fresh_bars,sbi)&&(vah<=mVah+cfg.brk_local_tol_atr*atrv)&&(c>=mVah+cfg.brk_entry_buf_atr*atrv)&&(cfg.brk_max_dist_atr<=0||c<=mVah+cfg.brk_max_dist_atr*atrv)&&netLongOk&&oppLongOk&&(riskBrkL>0)&&gateBrkL&&gateHtfL&&!ovhBlockL&&brkPocOk;
   double slBrkS=MathMax(mVal+cfg.brk_sl_buf_atr*atrv,c+cfg.brk_sl_atr_mult*atrv); double riskBrkS=slBrkS-c;
   bool recentS=(cross.lastShortEntryBar>=0)&&(sbi-cross.lastShortEntryBar)<=cfg.brk_rr_lookback_bars; double rrBrkS=recentS?cfg.brk_rr_near:cfg.brk_rr_far; double tpBrkS=c-rrBrkS*riskBrkS;
   bool sigBrkS=cfg.enable_breakout&&MonFresh(cross.xiDnVal,cfg.brk_fresh_bars,sbi)&&(val>=mVal-cfg.brk_local_tol_atr*atrv)&&(c<=mVal-cfg.brk_entry_buf_atr*atrv)&&(cfg.brk_max_dist_atr<=0||c>=mVal-cfg.brk_max_dist_atr*atrv)&&netShortOk&&oppShortOk&&(riskBrkS>0)&&gateBrkS&&gateHtfS&&!ovhBlockS&&brkPocOk;

   double slRevL1=MathMin(c-cfg.rev_sl_atr_mult*atrv,MathMax(mPoc+cfg.rev_poc_sl_off_atr*atrv,poc)-cfg.rev_sl_buf_atr*atrv); double riskRevL1=c-slRevL1;
   double tpRevL1=(mVah>vah+atrv)?mVah:MathMax(mVah,vah); double rrRevL1=(riskRevL1>0)?(tpRevL1-c)/riskRevL1:-1.0;
   bool sigRevL1=cfg.enable_reversion&&MonFresh(cross.xiUpPoc,cfg.rev_fresh_bars,sbi)&&(c>=MathMax(mPoc+cfg.rev_anchor_off_atr*atrv,poc)+cfg.rev_entry_dist_atr*atrv)&&(cfg.rev_max_dist_atr<=0||c<=mPoc+cfg.rev_max_dist_atr*atrv)&&rNetLongOk&&rOppLongOk&&(riskRevL1>0)&&(tpRevL1>c)&&(rrRevL1>=cfg.rev_min_rr)&&gateRev&&revPocOk;
   double slRevS1=MathMax(c+cfg.rev_sl_atr_mult*atrv,MathMin(mPoc-cfg.rev_poc_sl_off_atr*atrv,poc)+cfg.rev_sl_buf_atr*atrv); double riskRevS1=slRevS1-c;
   double tpRevS1=(mVal<val-atrv)?mVal:MathMin(mVal,val); double rrRevS1=(riskRevS1>0)?(c-tpRevS1)/riskRevS1:-1.0;
   bool sigRevS1=cfg.enable_reversion&&MonFresh(cross.xiDnPoc,cfg.rev_fresh_bars,sbi)&&(c<=MathMin(mPoc-cfg.rev_anchor_off_atr*atrv,poc)-cfg.rev_entry_dist_atr*atrv)&&(cfg.rev_max_dist_atr<=0||c>=mPoc-cfg.rev_max_dist_atr*atrv)&&rNetShortOk&&rOppShortOk&&(riskRevS1>0)&&(tpRevS1<c)&&(rrRevS1>=cfg.rev_min_rr)&&gateRev&&revPocOk;

   double slRevL2=MathMin(c-cfg.rev_sl_atr_mult*atrv,MathMax(mVal+cfg.rev_anchor_off_atr*atrv,val)-cfg.rev_sl_buf_atr*atrv); double riskRevL2=c-slRevL2;
   double tpRevL2=(mPoc>poc+atrv)?mPoc:MathMax(mPoc,poc); double rrRevL2=(riskRevL2>0)?(tpRevL2-c)/riskRevL2:-1.0;
   bool sigRevL2=cfg.enable_reversion&&MonFresh(cross.xiUpVal,cfg.rev_fresh_bars,sbi)&&(c>=MathMax(mVal+cfg.rev_anchor_off_atr*atrv,val)+cfg.rev_entry_dist_atr*atrv)&&(cfg.rev_max_dist_atr<=0||c<=mVal+cfg.rev_max_dist_atr*atrv)&&rNetLongOk&&rOppLongOk&&(riskRevL2>0)&&(tpRevL2>c)&&(rrRevL2>=cfg.rev_min_rr)&&gateRev&&revPocOk;
   double slRevS2=MathMax(c+cfg.rev_sl_atr_mult*atrv,MathMin(mVah-cfg.rev_anchor_off_atr*atrv,vah)+cfg.rev_sl_buf_atr*atrv); double riskRevS2=slRevS2-c;
   double tpRevS2=(mPoc<poc-atrv)?mPoc:MathMin(mPoc,poc); double rrRevS2=(riskRevS2>0)?(c-tpRevS2)/riskRevS2:-1.0;
   bool sigRevS2=cfg.enable_reversion&&MonFresh(cross.xiDnVah,cfg.rev_fresh_bars,sbi)&&(c<=MathMin(mVah-cfg.rev_anchor_off_atr*atrv,vah)-cfg.rev_entry_dist_atr*atrv)&&(cfg.rev_max_dist_atr<=0||c>=mVah-cfg.rev_max_dist_atr*atrv)&&rNetShortOk&&rOppShortOk&&(riskRevS2>0)&&(tpRevS2<c)&&(rrRevS2>=cfg.rev_min_rr)&&gateRev&&revPocOk;

   double candleH=h-l; bool impBull=(c>o)&&(candleH>=cfg.impulse_candle_atr*atrv); bool impBear=(c<o)&&(candleH>=cfg.impulse_candle_atr*atrv);
   bool impNetL=net.hasM1&&(net.netM1>=cfg.impulse_net_min); bool impNetS=net.hasM1&&(net.netM1<=-cfg.impulse_net_min);
   double pPoc=pC.valid?pC.poc:mPoc, pVah=pC.valid?pC.vah:mVah, pVal=pC.valid?pC.val:mVal;
   bool impTrendL=reg.mpoc_slope_up&&(pPoc>=mPoc); bool impTrendS=reg.mpoc_slope_dn&&(pPoc<=mPoc);
   bool impEntryL=(c>=mVah+cfg.impulse_entry_buf_atr*atrv)&&(cfg.impulse_max_dist_atr<=0||c<=pVah+cfg.impulse_max_dist_atr*atrv);
   bool impEntryS=(c<=mVal-cfg.impulse_entry_buf_atr*atrv)&&(cfg.impulse_max_dist_atr<=0||c>=pVal-cfg.impulse_max_dist_atr*atrv);
   double slImpL=MathMin(mVah-cfg.brk_sl_buf_atr*atrv,c-cfg.brk_sl_atr_mult*atrv); double riskImpL=c-slImpL; double tpImpL=c+cfg.impulse_rr*riskImpL;
   bool sigImpL=cfg.enable_impulse&&inVolCeilBand&&impBull&&impEntryL&&impTrendL&&impNetL&&(riskImpL>0);
   double slImpS=MathMax(mVal+cfg.brk_sl_buf_atr*atrv,c+cfg.brk_sl_atr_mult*atrv); double riskImpS=slImpS-c; double tpImpS=c-cfg.impulse_rr*riskImpS;
   bool sigImpS=cfg.enable_impulse&&inVolCeilBand&&impBear&&impEntryS&&impTrendS&&impNetS&&(riskImpS>0);

   int lK=0; double lSL=0,lTP2=0,lRisk=0;
   if(sigImpL){ lK=4; lSL=slImpL; lTP2=tpImpL; lRisk=riskImpL; }
   else if(atrCeilOk&&sigBrkL){ lK=1; lSL=slBrkL; lTP2=tpBrkL; lRisk=riskBrkL; }
   else if(atrCeilOk&&sigRevL1&&(!sigRevL2||rrRevL1>=rrRevL2)){ lK=2; lSL=slRevL1; lTP2=tpRevL1; lRisk=riskRevL1; }
   else if(atrCeilOk&&sigRevL2){ lK=3; lSL=slRevL2; lTP2=tpRevL2; lRisk=riskRevL2; }
   int sK=0; double sSL=0,sTP2=0,sRisk=0;
   if(sigImpS){ sK=4; sSL=slImpS; sTP2=tpImpS; sRisk=riskImpS; }
   else if(atrCeilOk&&sigBrkS){ sK=1; sSL=slBrkS; sTP2=tpBrkS; sRisk=riskBrkS; }
   else if(atrCeilOk&&sigRevS1&&(!sigRevS2||rrRevS1>=rrRevS2)){ sK=2; sSL=slRevS1; sTP2=tpRevS1; sRisk=riskRevS1; }
   else if(atrCeilOk&&sigRevS2){ sK=3; sSL=slRevS2; sTP2=tpRevS2; sRisk=riskRevS2; }

   if(lK==1||lK==4){ double rrL=(lK==4)?cfg.impulse_rr:rrBrkL;
      if(cfg.enable_hvn_shelf_sl){ double sx=node.HvnShelfSL(true,c,atrv,lSL,cfg); if(sx!=lSL&&c-sx>0){ lSL=sx; lRisk=c-sx; lTP2=c+rrL*lRisk; } }
      if(cfg.enable_structural_tp2) lTP2=node.StructuralTP2(true,c,lRisk,c+cfg.tp1_rr_brk*lRisk,atrv,pC,lTP2,cfg); }
   if(sK==1||sK==4){ double rrS=(sK==4)?cfg.impulse_rr:rrBrkS;
      if(cfg.enable_hvn_shelf_sl){ double sx=node.HvnShelfSL(false,c,atrv,sSL,cfg); if(sx!=sSL&&sx-c>0){ sSL=sx; sRisk=sx-c; sTP2=c-rrS*sRisk; } }
      if(cfg.enable_structural_tp2) sTP2=node.StructuralTP2(false,c,sRisk,c-cfg.tp1_rr_brk*sRisk,atrv,pC,sTP2,cfg); }

   double rng=MathMax(h-l,cfg.mintick);
   if(lK!=0){ bool bf=(lK==1||lK==4); L.valid=true; L.is_long=true; L.kind=lK; L.entry=c; L.sl=lSL; L.risk=lRisk;
      L.tp1=c+(bf?cfg.tp1_rr_brk:cfg.tp1_rr_rev)*lRisk; L.tp2=lTP2; L.edge=bf?mVah:0.0;
      L.reason=(lK==1)?"L-BRK":(lK==2)?"L-MR1":(lK==3)?"L-MR2":"L-IMP";
      L.f_brk_dist_atr=(c-mVah)/atrv; L.f_body_pct=MathAbs(c-o)/rng; L.f_slope=reg.slope_known?reg.slope_norm:0.0;
      L.f_net_m1=net.hasM1?net.netM1:0.0; L.f_net_m3=net.netM3; L.f_net_m5=net.hasM5?net.netM5:0.0; L.f_atr_pct=atrPct; }
   if(sK!=0){ bool bf=(sK==1||sK==4); S.valid=true; S.is_long=false; S.kind=sK; S.entry=c; S.sl=sSL; S.risk=sRisk;
      S.tp1=c-(bf?cfg.tp1_rr_brk:cfg.tp1_rr_rev)*sRisk; S.tp2=sTP2; S.edge=bf?mVal:0.0;
      S.reason=(sK==1)?"S-BRK":(sK==2)?"S-MR1":(sK==3)?"S-MR2":"S-IMP";
      S.f_brk_dist_atr=(mVal-c)/atrv; S.f_body_pct=MathAbs(c-o)/rng; S.f_slope=reg.slope_known?reg.slope_norm:0.0;
      S.f_net_m1=net.hasM1?net.netM1:0.0; S.f_net_m3=net.netM3; S.f_net_m5=net.hasM5?net.netM5:0.0; S.f_atr_pct=atrPct; }
}

#endif // KKM_SIGNAL_MQH
