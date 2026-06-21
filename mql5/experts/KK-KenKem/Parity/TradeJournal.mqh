//+------------------------------------------------------------------+
//|                                             TradeJournal.mqh      |
//|     KenKem — per-trade parity journal (diagnostics only).         |
//|                                                                  |
//|     One CSV row per CLOSED trade, schema-aligned with the         |
//|     dquants C++ KenKem trade ledger so the two can be diffed      |
//|     1:1 to PROVE tick-level parity (entryTimeUTC is the join key).|
//|                                                                  |
//|     Design: SELF-CONTAINED, deal-history POLLING (no hooks into   |
//|     the EA's scattered OrderSend/PositionClose sites). Call        |
//|     KenKemJournalPoll() once per tick; it detects flat->position   |
//|     (open) and position->flat (close) transitions on _Symbol and   |
//|     reconstructs realized P&L + exit reason from the deal history.  |
//|     Partial TPs keep the same position ticket under netting, so a   |
//|     partial does NOT emit a close row; realizedUsd at final close   |
//|     sums ALL out-deals (partial + final), matching the C++ engine.  |
//|                                                                  |
//|     Entry time is emitted in UTC: POSITION_TIME (server) minus the  |
//|     live broker offset (TimeCurrent()-TimeGMT()). The EA already    |
//|     relies on TimeGMT() for sessions, validated as UTC at offset 9. |
//|                                                                  |
//|     Output: MQL5/Files/KenKem/trades_<sym>.csv                     |
//|     NO trading-logic effect. Include AFTER the EA inputs.          |
//+------------------------------------------------------------------+
#property strict

#ifndef KENKEM_TRADEJOURNAL_MQH
#define KENKEM_TRADEJOURNAL_MQH

input bool InpExportTradeJournal = false;   // PARITY: write per-trade CSV (diagnostics only)

int      g_kjHandle    = INVALID_HANDLE;
bool     g_kjOpen      = false;
ulong    g_kjTicket    = 0;
double   g_kjEntry     = 0.0;   // position open price
double   g_kjRisk      = 0.0;   // |entry - SL| at open (price)
bool     g_kjIsLong    = false;
string   g_kjKind      = "";    // E1/E2/E4/E5 parsed from POSITION_COMMENT
datetime g_kjEntryGMT  = 0;     // entry time in UTC
double   g_kjMaxFav    = 0.0;   // best favorable mark-to-market price
double   g_kjMaxAdv    = 0.0;   // worst adverse mark-to-market price

void InitKenKemJournal() {
   if(!InpExportTradeJournal) return;
   string fname = StringFormat("KenKem\\trades_%s.csv", _Symbol);
   g_kjHandle = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(g_kjHandle == INVALID_HANDLE) {
      Print("[KJOURNAL] cannot open ", fname, " err=", GetLastError());
      return;
   }
   FileWrite(g_kjHandle,
      "entryTimeUTC", "dir", "kind", "entry", "riskPrice",
      "exitPrice", "realizedUsd", "mfeR", "maeR", "exitTag");
   Print("[KJOURNAL] parity trade study -> ", fname);
}

// Parse "E1".."E5" out of a position comment like "KenKemST L-E2 #2026...".
string KJParseKind(string comment) {
   for(int k = 1; k <= 6; k++) {
      string tag = "E" + IntegerToString(k);
      if(StringFind(comment, "-" + tag) >= 0) return tag;
   }
   return "";
}

// Map the broker close reason of the position's last OUT deal to a short tag.
// Trail and BE both close via an SL modify, so they surface as "SL"; split by the
// realized sign in WriteClose so a trail/BE win is not misread as a stop-out loss.
string KJExitTag(ulong posTicket) {
   if(posTicket == 0 || !HistorySelectByPosition(posTicket)) return "NA";
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      long entryType = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY) continue;
      long reason = HistoryDealGetInteger(d, DEAL_REASON);
      switch((int)reason) {
         case DEAL_REASON_SL:     return "SL";
         case DEAL_REASON_TP:     return "TP";
         case DEAL_REASON_SO:     return "SO";
         case DEAL_REASON_EXPERT: return "EA";
         case DEAL_REASON_CLIENT: return "MAN";
         default:                 return "OTH";
      }
   }
   return "NA";
}

// Sum realized USD (profit+swap+commission) over ALL out-deals of the position, and
// return the last out-deal price as the (final) exit price.
double KJRealizedAndExit(ulong posTicket, double &exitPrice) {
   exitPrice = 0.0;
   if(posTicket == 0 || !HistorySelectByPosition(posTicket)) return 0.0;
   double realized = 0.0;
   datetime lastOutTime = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      long entryType = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY) continue;
      realized += HistoryDealGetDouble(d, DEAL_PROFIT)
                + HistoryDealGetDouble(d, DEAL_SWAP)
                + HistoryDealGetDouble(d, DEAL_COMMISSION);
      datetime dt = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      if(dt >= lastOutTime) { lastOutTime = dt; exitPrice = HistoryDealGetDouble(d, DEAL_PRICE); }
   }
   return realized;
}

void KJWriteClose() {
   if(g_kjHandle == INVALID_HANDLE || !g_kjOpen) return;
   double exitPrice = 0.0;
   double realizedUsd = KJRealizedAndExit(g_kjTicket, exitPrice);
   string exitTag = KJExitTag(g_kjTicket);
   if(exitTag == "SL") exitTag = (realizedUsd > 0.0) ? "SL-WIN" : "SL-LOSS";
   double mfeR = 0.0, maeR = 0.0;
   if(g_kjRisk > 0.0) {
      if(g_kjIsLong) { mfeR = (g_kjMaxFav - g_kjEntry) / g_kjRisk; maeR = (g_kjEntry - g_kjMaxAdv) / g_kjRisk; }
      else           { mfeR = (g_kjEntry - g_kjMaxFav) / g_kjRisk; maeR = (g_kjMaxAdv - g_kjEntry) / g_kjRisk; }
   }
   FileWrite(g_kjHandle,
      TimeToString(g_kjEntryGMT, TIME_DATE | TIME_MINUTES),
      (g_kjIsLong ? "L" : "S"), g_kjKind,
      DoubleToString(g_kjEntry, 3), DoubleToString(g_kjRisk, 3),
      DoubleToString(exitPrice, 3), DoubleToString(realizedUsd, 2),
      DoubleToString(mfeR, 2), DoubleToString(maeR, 2), exitTag);
   g_kjOpen = false;
   g_kjTicket = 0;
}

// Call once per tick. Detects open/close transitions on _Symbol and tracks MFE/MAE.
void KenKemJournalPoll(double bid, double ask) {
   if(g_kjHandle == INVALID_HANDLE) return;
   bool  hasPos    = PositionSelect(_Symbol);
   ulong curTicket = hasPos ? (ulong)PositionGetInteger(POSITION_TICKET) : 0;

   // Close (or replacement): we were tracking a ticket that is no longer the live one.
   if(g_kjOpen && curTicket != g_kjTicket) KJWriteClose();

   // Open: a live position we are not yet tracking.
   if(hasPos && !g_kjOpen) {
      g_kjTicket  = curTicket;
      g_kjIsLong  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      g_kjEntry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      g_kjRisk    = (sl > 0.0) ? MathAbs(g_kjEntry - sl) : 0.0;
      g_kjKind    = KJParseKind(PositionGetString(POSITION_COMMENT));
      datetime srvOpen = (datetime)PositionGetInteger(POSITION_TIME);
      g_kjEntryGMT = srvOpen - (TimeCurrent() - TimeGMT());   // server -> UTC
      g_kjMaxFav = g_kjEntry; g_kjMaxAdv = g_kjEntry;
      g_kjOpen = true;
   }

   // Mark-to-market on the realisable (exit) side while open.
   if(g_kjOpen && hasPos) {
      double mtm = g_kjIsLong ? bid : ask;
      if(g_kjIsLong) { if(mtm > g_kjMaxFav) g_kjMaxFav = mtm; if(mtm < g_kjMaxAdv) g_kjMaxAdv = mtm; }
      else           { if(mtm < g_kjMaxFav) g_kjMaxFav = mtm; if(mtm > g_kjMaxAdv) g_kjMaxAdv = mtm; }
   }
}

void CloseKenKemJournal() {
   if(g_kjHandle != INVALID_HANDLE) { FileClose(g_kjHandle); g_kjHandle = INVALID_HANDLE; }
}

#endif // KENKEM_TRADEJOURNAL_MQH
