//+------------------------------------------------------------------+
//|  KK-Common/TradeLogger.mqh                                        |
//|  D2 - Per-EA trade CSV, append-immediately-on-close.              |
//|                                                                    |
//|  Each EA/chart writes its OWN file (no shared writer), keyed by    |
//|  EA + symbol + account login, in the per-terminal MQL5/Files dir:  |
//|    KKTrades_<EA>_<SYMBOL>_<login>.csv                             |
//|  One row is appended the INSTANT a position closes (FileFlush per  |
//|  row, cost is microseconds - it never bothers tick/entry logic).   |
//|  Header is written once for a new file; OnDeinit flushes + closes. |
//|                                                                    |
//|  LIVE-ONLY: writes are skipped under MQL_TESTER / MQL_OPTIMIZATION  |
//|  (the C++/parity export emits its own trades_*.csv - kept separate)|
//+------------------------------------------------------------------+
#ifndef KK_TRADE_LOGGER_MQH
#define KK_TRADE_LOGGER_MQH

class KKTradeLogger
{
private:
   bool   m_enabled;
   int    m_handle;
   string m_file;
   string m_eaTag;

public:
   KKTradeLogger(){ m_enabled=false; m_handle=INVALID_HANDLE; }

   // enabled : user toggle. eaTag : short EA name (e.g. "MasterVP").
   void Init(bool enabled,string eaTag)
   {
      m_enabled=false; m_handle=INVALID_HANDLE; m_eaTag=eaTag;
      if(!enabled) return;
      if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // live-only

      long login=(long)AccountInfoInteger(ACCOUNT_LOGIN);
      m_file="KKTrades_"+eaTag+"_"+_Symbol+"_"+IntegerToString(login)+".csv";
      bool isNew=!FileIsExist(m_file);
      m_handle=FileOpen(m_file,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(m_handle==INVALID_HANDLE)
      {
         Print("[KKTradeLogger] cannot open ",m_file," err=",GetLastError());
         return;
      }
      FileSeek(m_handle,0,SEEK_END);   // append mode
      if(isNew)
      {
         FileWrite(m_handle,
                   "close_time_server","ea","symbol","ticket","deal_type","volume",
                   "price","profit","swap","commission","net","comment","balance_after");
         FileFlush(m_handle);
      }
      m_enabled=true;
      Print("[KKTradeLogger] logging closed trades to ",m_file);
   }

   // Call from OnTradeTransaction for the closing (DEAL_ENTRY_OUT) deal.
   void LogDeal(ulong dealTicket)
   {
      if(!m_enabled || m_handle==INVALID_HANDLE) return;
      if(!HistoryDealSelect(dealTicket)) return;
      double profit=HistoryDealGetDouble(dealTicket,DEAL_PROFIT);
      double swap  =HistoryDealGetDouble(dealTicket,DEAL_SWAP);
      double comm  =HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);
      double net   =profit+swap+comm;
      long   dtype =HistoryDealGetInteger(dealTicket,DEAL_TYPE);
      string typ   =(dtype==DEAL_TYPE_BUY)?"buy":(dtype==DEAL_TYPE_SELL)?"sell":"other";
      datetime tm  =(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);

      FileSeek(m_handle,0,SEEK_END);
      FileWrite(m_handle,
                TimeToString(tm,TIME_DATE|TIME_SECONDS),
                m_eaTag,
                HistoryDealGetString(dealTicket,DEAL_SYMBOL),
                IntegerToString((long)dealTicket),
                typ,
                DoubleToString(HistoryDealGetDouble(dealTicket,DEAL_VOLUME),2),
                DoubleToString(HistoryDealGetDouble(dealTicket,DEAL_PRICE),_Digits),
                DoubleToString(profit,2),
                DoubleToString(swap,2),
                DoubleToString(comm,2),
                DoubleToString(net,2),
                HistoryDealGetString(dealTicket,DEAL_COMMENT),
                DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));
      FileFlush(m_handle);   // durable now - never lose a closed trade to a crash
   }

   void Deinit()
   {
      if(m_handle!=INVALID_HANDLE){ FileFlush(m_handle); FileClose(m_handle); m_handle=INVALID_HANDLE; }
   }
};

#endif // KK_TRADE_LOGGER_MQH
