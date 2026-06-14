//+------------------------------------------------------------------+
//|  VP-Common/Types.mqh — value types shared by the VP family        |
//|  (MasterVP, Monster). Mirrors cpp_core kk::VPResult/RegimeState/   |
//|  NodeState/Signal.                                                |
//+------------------------------------------------------------------+
#ifndef VPC_TYPES_MQH
#define VPC_TYPES_MQH

struct VPResult { bool valid; double poc,vah,val,hi,lo; };

struct RegimeState { bool valid,trend,balance; double plus,minus,adx,atr1; };

// Node-state read at one master bin.
struct NodeState { int state; double net,touch; bool absorbed; };   // state: +1 buy / -1 sell / 0 flat-absorbed

// Entry signal from DetectSignal. reason: "L-BRK"/"S-BRK"/"L-REV"/"S-REV".
struct Signal {
   bool   valid,is_long,is_rev;
   double entry,sl,tp1,tp2,risk;
   string reason;
   // diagnostics (no trading effect)
   double f_brk_dist_atr,f_runway_atr,f_node_net,f_body_pct,f_adx,f_di_spread;
};

#endif // VPC_TYPES_MQH
