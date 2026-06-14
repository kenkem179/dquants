//+------------------------------------------------------------------+
//|  KK-Common/Indicators.mqh                                        |
//|  Generic indicator helpers shared by ALL strategy families.      |
//+------------------------------------------------------------------+
#ifndef KKC_INDICATORS_MQH
#define KKC_INDICATORS_MQH

// Single-value read from an indicator buffer at `shift` bars ago (newest-relative).
// Returns 0.0 on failure / invalid handle (MT5 "no data").
double KKBuf(int handle,int buffer,int shift)
{
   double v[];
   if(CopyBuffer(handle,buffer,shift,1,v)==1) return v[0];
   return 0.0;
}

#endif // KKC_INDICATORS_MQH
