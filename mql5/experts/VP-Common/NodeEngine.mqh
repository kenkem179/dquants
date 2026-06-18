//+------------------------------------------------------------------+
//|  VP-Common/NodeEngine.mqh — synthetic order-flow node engine.     |
//|  Faithful transcription of cpp_core kk::NodeEngine                 |
//|  (== Core/NodeStateEngine.mqh). Per-bin decayed buy/sell/touch     |
//|  over the SLIDING master [lo,hi] grid (grid moves every bar — do   |
//|  not "fix" the slide). Update once per just-closed bar.           |
//+------------------------------------------------------------------+
#ifndef VPC_NODEENGINE_MQH
#define VPC_NODEENGINE_MQH

#include "Types.mqh"
#include "VolumeProfile.mqh"   // VP_ClampI

class CNodeEngine
{
private:
   int    m_bins;
   double m_buy[], m_sell[], m_touch[];
   double m_lo, m_hi, m_step;
public:
   void Init(int bins)
   {
      m_bins=bins;
      ArrayResize(m_buy,bins);  ArrayInitialize(m_buy,0.0);
      ArrayResize(m_sell,bins); ArrayInitialize(m_sell,0.0);
      ArrayResize(m_touch,bins);ArrayInitialize(m_touch,0.0);
      m_lo=0; m_hi=0; m_step=0;
   }

   // One just-closed bar. masterVP supplies the current sliding master lo/hi.
   void Update(const VPResult &masterVP,double o,double h,double l,double c,long volTicks,double atr,
               double pipSize,double mintick,double nodeTouchAtr,double nodeDecay)
   {
      if(!masterVP.valid) return;
      double m_lo_=masterVP.lo, m_hi_=masterVP.hi;
      double m_step_=(m_hi_-m_lo_)/m_bins;
      if(m_step_<=0.0) return;
      m_lo=m_lo_; m_hi=m_hi_; m_step=m_step_;

      double vol=(double)volTicks;
      if(o<=0||h<=0||l<=0||c<=0||h<l) return;
      double touchDist=MathMax(nodeTouchAtr*atr, 2.0*pipSize);
      double dirProxy=(c-o)/MathMax(h-l,mintick);
      double buyProxy=vol*MathMax(dirProxy,0.0);
      double sellProxy=vol*MathMax(-dirProxy,0.0);

      for(int b=0;b<m_bins;b++){ m_buy[b]*=nodeDecay; m_sell[b]*=nodeDecay; m_touch[b]*=nodeDecay; }

      int lowIdx =VP_ClampI((int)MathFloor((l-m_lo)/m_step),0,m_bins-1);
      int highIdx=VP_ClampI((int)MathFloor((h-m_lo)/m_step),0,m_bins-1);
      double span=MathMax((double)(highIdx-lowIdx+1),1.0);
      for(int b=lowIdx;b<=highIdx;b++){
         double nodePx=m_lo+(b+0.5)*m_step;
         bool touched=(MathAbs(c-nodePx)<=touchDist)||(l<=nodePx && h>=nodePx);
         if(touched){ m_touch[b]+=1.0; m_buy[b]+=buyProxy/span; m_sell[b]+=sellProxy/span; }
      }
   }

   int PickIdx(double px) const
   {
      if(m_step<=0.0) return 0;
      return VP_ClampI((int)MathFloor((px-m_lo)/m_step),0,m_bins-1);
   }

   NodeState StateAt(int idx,double nodeSaturation,double nodeNeutralBand) const
   {
      NodeState ns; ns.state=0; ns.net=0; ns.touch=0; ns.absorbed=false;
      if(idx<0||idx>=m_bins) return ns;
      double b=m_buy[idx], s=m_sell[idx], t=m_touch[idx];
      double net=(b-s)/MathMax(b+s,1.0);
      bool absorbed=(t>=nodeSaturation)&&(MathAbs(net)<=nodeNeutralBand);
      ns.state=absorbed?0:(net>nodeNeutralBand?1:(net<-nodeNeutralBand?-1:0));
      ns.net=net; ns.touch=t; ns.absorbed=absorbed;
      return ns;
   }

   NodeState StateAtPrice(double px,double nodeSaturation,double nodeNeutralBand) const
   { return StateAt(PickIdx(px),nodeSaturation,nodeNeutralBand); }
};

#endif // VPC_NODEENGINE_MQH
