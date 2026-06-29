//+------------------------------------------------------------------+
//|  KK-Common/AccountGuardian.mqh                                    |
//|  D1 - Cross-EA prop-firm Account Risk Guardian (Layer 4, live).   |
//|                                                                    |
//|  AccountInfoDouble(BALANCE|EQUITY) is already account-wide, so the |
//|  live numbers need no sharing. What IS shared across every KK EA   |
//|  on one terminal are the DERIVED anchors (start-of-day equity,     |
//|  running peak, breach latch). They live in terminal GlobalVariables|
//|  keyed by account login, so MasterVP / KenKem / Monster all agree. |
//|                                                                    |
//|  Equity-based, flatten-BEFORE-the-line (configurable buffer). Day  |
//|  boundary = broker SERVER time (TimeTradeServer, auto-DST) -        |
//|  deliberately separate from the strategy's UTC session logic.      |
//|                                                                    |
//|  The PURE MATH (KKG_* free functions) calls no MT5 API, so it is   |
//|  unit-testable headlessly via the KK-Common-Tests drag-drop EA.    |
//+------------------------------------------------------------------+
#ifndef KK_ACCOUNT_GUARDIAN_MQH
#define KK_ACCOUNT_GUARDIAN_MQH

// ===================================================================
//  PURE MATH - no MT5 API, no globals. Unit-testable in isolation.
// ===================================================================

// Loss (account currency) that trips the protective action. We act when the
// loss reaches (limitPct - bufferPct) of the anchor, i.e. a safety margin
// BEFORE the hard firm line. bufferPct >= limitPct => trip at zero loss
// (degenerate; clamped to 0 so it never goes negative).
double KKG_TriggerLoss(double anchor,double limitPct,double bufferPct)
{
   if(anchor<=0.0 || limitPct<=0.0) return 0.0;
   double eff=limitPct-bufferPct;
   if(eff<0.0) eff=0.0;
   return anchor*eff/100.0;
}

// Daily loss breach: equity dropped >= trigger below the day-start anchor.
bool KKG_DailyBreached(double equity,double dayStartAnchor,double limitPct,double bufferPct)
{
   if(dayStartAnchor<=0.0 || limitPct<=0.0) return false;
   return (dayStartAnchor-equity)>=KKG_TriggerLoss(dayStartAnchor,limitPct,bufferPct);
}

// Overall / max-drawdown breach vs the DD anchor (trailing peak OR static bal).
bool KKG_OverallBreached(double equity,double ddAnchor,double limitPct,double bufferPct)
{
   if(ddAnchor<=0.0 || limitPct<=0.0) return false;
   return (ddAnchor-equity)>=KKG_TriggerLoss(ddAnchor,limitPct,bufferPct);
}

// Day key (yyyymmdd) from a server-time datetime - the day-roll boundary.
int KKG_DayKey(datetime serverTime)
{
   MqlDateTime dt; TimeToStruct(serverTime,dt);
   return dt.year*10000+dt.mon*100+dt.day;
}

// ===================================================================
//  STATEFUL, CROSS-EA - uses MT5 API + terminal GlobalVariables.
// ===================================================================

enum KKG_DDAnchorMode
{
   KKG_DD_TRAILING_PEAK = 0,  // max drawdown measured from the running equity peak (most prop firms)
   KKG_DD_STATIC_BALANCE= 1   // max drawdown measured from the initial account balance
};

struct KKGuardConfig
{
   bool   enabled;          // master toggle (false => guardian inert)
   double dailyLossPct;     // daily loss limit % of day-start anchor (e.g. 4.0)
   double overallDDPct;     // max overall drawdown % of DD anchor (e.g. 8.0)
   double bufferPct;        // act this many % BEFORE each line (e.g. 0.5)
   int    ddAnchorMode;     // KKG_DDAnchorMode
   double manualDayAnchor;  // >0 overrides the reconstructed day-start anchor
   double staticAnchorOverride; // >0 pins the static-DD anchor to this value (e.g. prop INITIAL balance);
                                // authoritative across restarts/EAs so the floor stays the firm line
                                // regardless of the balance at attach. 0 = auto-detect at first attach.
   bool   flattenOnBreach;  // true=close all positions; false=block new entries only
};

class KKAccountGuardian
{
private:
   KKGuardConfig m_cfg;
   long   m_login;
   string m_kDayKey,m_kDayStart,m_kPeak,m_kStatic,m_kLatch;
   bool   m_inited;

   string K(string suffix){ return "KKG."+IntegerToString(m_login)+"."+suffix; }
   double GVget(string name,double def){ return GlobalVariableCheck(name)?GlobalVariableGet(name):def; }

   // Reconstruct day-start balance = balance_now - sum(closed-deal P/L since
   // server-midnight). Lets a mid-day cold-start (cleared GVs / fresh attach)
   // recover the correct daily anchor instead of using "now".
   double ReconstructDayStartBalance(double balNow)
   {
      datetime now=TimeTradeServer(); if(now<=0) now=TimeCurrent();
      MqlDateTime dt; TimeToStruct(now,dt); dt.hour=0; dt.min=0; dt.sec=0;
      datetime midnight=StructToTime(dt);
      double pl=0.0;
      if(HistorySelect(midnight,now))
      {
         int total=HistoryDealsTotal();
         for(int i=0;i<total;i++)
         {
            ulong tk=HistoryDealGetTicket(i);
            long entry=HistoryDealGetInteger(tk,DEAL_ENTRY);
            if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_INOUT || entry==DEAL_ENTRY_OUT_BY)
               pl+=HistoryDealGetDouble(tk,DEAL_PROFIT)
                  +HistoryDealGetDouble(tk,DEAL_SWAP)
                  +HistoryDealGetDouble(tk,DEAL_COMMISSION);
         }
      }
      return balNow-pl;
   }

   // Roll the shared day anchor when the server day changes (first EA to notice
   // claims it atomically via SetOnCondition; others read what it wrote).
   void RollDayIfNeeded(int today,double bal)
   {
      if(!GlobalVariableCheck(m_kDayKey) || !GlobalVariableCheck(m_kDayStart))
      {
         GlobalVariableSet(m_kDayKey,today);
         GlobalVariableSet(m_kDayStart,m_cfg.manualDayAnchor>0.0?m_cfg.manualDayAnchor
                                                                :ReconstructDayStartBalance(bal));
         GlobalVariableSet(m_kLatch,0);
         return;
      }
      int stored=(int)GVget(m_kDayKey,-1);
      if(stored==today) return;
      if(GlobalVariableSetOnCondition(m_kDayKey,today,stored))
      {
         GlobalVariableSet(m_kDayStart,m_cfg.manualDayAnchor>0.0?m_cfg.manualDayAnchor
                                                                :ReconstructDayStartBalance(bal));
         GlobalVariableSet(m_kLatch,0);   // clear the flatten latch for the new day
      }
   }

   double DDAnchor(double eq)
   {
      if(m_cfg.ddAnchorMode==KKG_DD_STATIC_BALANCE)
         return GVget(m_kStatic,AccountInfoDouble(ACCOUNT_BALANCE));
      double peak=GVget(m_kPeak,eq);
      return MathMax(peak,eq);
   }

public:
   void Init(const KKGuardConfig &cfg)
   {
      m_cfg=cfg; m_inited=true;
      m_login=(long)AccountInfoInteger(ACCOUNT_LOGIN);
      m_kDayKey=K("dayKey"); m_kDayStart=K("dayStart"); m_kPeak=K("peak");
      m_kStatic=K("staticBal"); m_kLatch=K("latch");
      if(!m_cfg.enabled) return;

      double eq =AccountInfoDouble(ACCOUNT_EQUITY);
      double bal=AccountInfoDouble(ACCOUNT_BALANCE);
      datetime now=TimeTradeServer(); if(now<=0) now=TimeCurrent();

      // static-DD anchor. With an override (prop initial balance) we ASSERT it every
      // attach so it is authoritative across restarts and never drifts to the attach
      // balance; without one we seed once to current balance and persist.
      if(m_cfg.staticAnchorOverride>0.0)        GlobalVariableSet(m_kStatic,m_cfg.staticAnchorOverride);
      else if(!GlobalVariableCheck(m_kStatic))  GlobalVariableSet(m_kStatic,bal);
      if(!GlobalVariableCheck(m_kPeak))   GlobalVariableSet(m_kPeak,eq);     // peak seed
      RollDayIfNeeded(KKG_DayKey(now),bal);
      GlobalVariablesFlush();
   }

   // Call every tick BEFORE entry/manage. Returns true if trading is halted.
   bool Update()
   {
      if(!m_inited || !m_cfg.enabled) return false;
      double eq =AccountInfoDouble(ACCOUNT_EQUITY);
      double bal=AccountInfoDouble(ACCOUNT_BALANCE);
      datetime now=TimeTradeServer(); if(now<=0) now=TimeCurrent();
      RollDayIfNeeded(KKG_DayKey(now),bal);

      double peak=GVget(m_kPeak,eq);            // shared high-water mark
      if(eq>peak){ GlobalVariableSet(m_kPeak,eq); peak=eq; }

      double dayStart=GVget(m_kDayStart,eq);
      bool breach=KKG_DailyBreached(eq,dayStart,m_cfg.dailyLossPct,m_cfg.bufferPct)
               || KKG_OverallBreached(eq,DDAnchor(eq),m_cfg.overallDDPct,m_cfg.bufferPct);
      if(breach && GVget(m_kLatch,0.0)<1.0){ GlobalVariableSet(m_kLatch,1); GlobalVariablesFlush(); }
      return Halted();
   }

   bool Enabled()      { return m_cfg.enabled; }
   bool Halted()       { return m_cfg.enabled && GVget(m_kLatch,0.0)>=1.0; }
   bool ShouldFlatten(){ return Halted() && m_cfg.flattenOnBreach; }

   // Human-readable status for notifications / debug.
   string Status()
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      double ds=GVget(m_kDayStart,eq), pk=DDAnchor(eq);
      double dayDD=(ds>0.0)?(ds-eq)/ds*100.0:0.0;
      double ovrDD=(pk>0.0)?(pk-eq)/pk*100.0:0.0;
      return StringFormat("eq=%.2f dayDD=%.2f%%/%.1f%% ovrDD=%.2f%%/%.1f%% halted=%s",
                          eq,dayDD,m_cfg.dailyLossPct,ovrDD,m_cfg.overallDDPct,(Halted()?"YES":"no"));
   }
};

#endif // KK_ACCOUNT_GUARDIAN_MQH
