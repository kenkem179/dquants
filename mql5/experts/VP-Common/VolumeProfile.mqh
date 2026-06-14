//+------------------------------------------------------------------+
//|  VP-Common/VolumeProfile.mqh — POC / value-area construction.     |
//|  Faithful transcription of cpp_core kk::vp (== Core/VolumeProfile  |
//|  .mqh). Stage-A bar feed: each bar drops its whole tick_count into |
//|  the bin of its hlc3. VA grown from POC, heavier neighbour, ties   |
//|  -> HIGH side, until va_pct% enclosed.                            |
//+------------------------------------------------------------------+
#ifndef VPC_VOLUMEPROFILE_MQH
#define VPC_VOLUMEPROFILE_MQH

#include "Types.mqh"

int VP_ClampI(int v,int lo,int hi){ return v<lo?lo:(v>hi?hi:v); }

// Build value area from a per-bin histogram on grid [lo, lo+bins*step).
VPResult VP_BuildVAFromHist(const double &hist[],double lo,double step,double vaPct)
{
   VPResult res; res.valid=false; res.poc=0; res.vah=0; res.val=0; res.hi=0; res.lo=0;
   int bins=ArraySize(hist);
   if(bins==0) return res;
   double total=0.0,pocVol=-1.0; int pocIdx=0;
   for(int b=0;b<bins;b++){ total+=hist[b]; if(hist[b]>pocVol){ pocVol=hist[b]; pocIdx=b; } }
   double target=total*(vaPct*0.01);
   double acc=hist[pocIdx];
   int loIdx=pocIdx,hiIdx=pocIdx;
   while(acc<target && (loIdx>0 || hiIdx<bins-1)){
      double nextL=(loIdx>0)?hist[loIdx-1]:-1.0;
      double nextH=(hiIdx<bins-1)?hist[hiIdx+1]:-1.0;
      if(nextH>=nextL){ hiIdx+=1; acc+=hist[hiIdx]; } else { loIdx-=1; acc+=hist[loIdx]; }
   }
   res.poc=lo+(pocIdx+0.5)*step;
   res.vah=lo+(hiIdx+1.0)*step;
   res.val=lo+loIdx*step;
   res.lo=lo; res.hi=lo+bins*step; res.valid=true;
   return res;
}

// Stage-A VP over the given OHLC + tick_count arrays (index 0..len-1, any order).
VPResult VP_ComputeBars(const double &h[],const double &l[],const double &c[],const long &vol[],
                        int len,int bins,double vaPct)
{
   VPResult res; res.valid=false; res.poc=0; res.vah=0; res.val=0; res.hi=0; res.lo=0;
   if(len<=0 || bins<=0) return res;
   double lo=l[0],hi=h[0];
   for(int i=1;i<len;i++){ if(l[i]<lo) lo=l[i]; if(h[i]>hi) hi=h[i]; }
   double step=(hi-lo)/bins;
   if(step<=0.0){ res.hi=hi; res.lo=lo; return res; }
   double hist[]; ArrayResize(hist,bins); ArrayInitialize(hist,0.0);
   for(int i=0;i<len;i++){
      double p=(h[i]+l[i]+c[i])/3.0;
      int bi=VP_ClampI((int)MathFloor((p-lo)/step),0,bins-1);
      hist[bi]+=(double)vol[i];
   }
   res=VP_BuildVAFromHist(hist,lo,step,vaPct);
   res.hi=hi; res.lo=lo;
   return res;
}

#endif // VPC_VOLUMEPROFILE_MQH
