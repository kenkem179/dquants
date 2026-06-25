//+------------------------------------------------------------------+
//|  KK-Common/AccountLock.mqh - shared access guard for all KK       |
//|  products (KK-KenKem, KK-MasterVP EAs + the KK-MasterVP-Profiler  |
//|  indicator). Two independent locks, both OFF (empty) by default:  |
//|                                                                   |
//|  1) ACCOUNT LOCK - two HIDDEN compiled-in strings (plain globals, |
//|     NOT `input`), both empty by default = runs on any account:    |
//|        ALLOWED_ACCOUNT_ID      - the MT5 login number             |
//|        ALLOWED_ACCOUNT_SERVER  - the MT5 trade-server name        |
//|     A login number is only unique WITHIN a server (the same       |
//|     number can exist on different brokers), so the lock pins      |
//|     both. KK_AccountAuthorized() at the very top of OnInit; on    |
//|     mismatch it raises Alert("Invalid Account ID") and returns    |
//|     false - the product MUST then abort (EA: return INIT_FAILED;  |
//|     indicator: stop all calculation).                             |
//|                                                                   |
//|  2) EXPIRY LOCK - one HIDDEN compiled-in string ACCESS_EXPIRY,    |
//|     empty by default = never expires. When baked to a date        |
//|     ("YYYY.MM.DD" or "YYYY.MM.DD HH:MM:SS") the build stops once  |
//|     the BROKER SERVER clock passes it (TimeTradeServer, so the    |
//|     user cannot bypass by changing their PC clock). It fails OPEN |
//|     when the server time is not yet known (brief startup/offline) |
//|     so a legit user is never falsely locked out - it re-checks    |
//|     every tick/calc. On expiry the product raises                 |
//|     Alert("Expired Access").                                      |
//|                                                                   |
//|  The per-account release script bakes one (id, server, expiry)    |
//|  triple in, producing one locked .ex5 per account.                |
//+------------------------------------------------------------------+
#ifndef KK_COMMON_ACCOUNTLOCK_MQH
#define KK_COMMON_ACCOUNTLOCK_MQH

// Returns true if the EA is allowed to run on the current broker account.
//   allowedId == ""                 -> unlocked build, any account (true)
//   id matches AND (server unset OR server matches) -> authorized (true)
//   otherwise                       -> Alert "Invalid Account ID", false
// allowedServer is optional: when empty only the login is checked.
bool KK_AccountAuthorized(const string allowedId, const string allowedServer = "")
{
   if(StringLen(allowedId) == 0)
      return true;   // unlocked build (dev / marketplace) - any account

   long   currentAccount = AccountInfoInteger(ACCOUNT_LOGIN);
   string currentServer  = AccountInfoString(ACCOUNT_SERVER);

   bool idOk     = (IntegerToString(currentAccount) == allowedId);
   bool serverOk = (StringLen(allowedServer) == 0) || (currentServer == allowedServer);

   if(idOk && serverOk)
   {
      PrintFormat("[ACCOUNT LOCK] Authorized for account %I64d @ %s",
                  currentAccount, currentServer);
      return true;
   }

   Alert("Invalid Account ID");
   PrintFormat("[ACCOUNT LOCK] EA not authorized for account %I64d @ %s. Expected: %s @ %s",
               currentAccount, currentServer, allowedId,
               (StringLen(allowedServer) == 0 ? "(any server)" : allowedServer));
   return false;
}

//------------------------------------------------------------------
//  EXPIRY LOCK
//------------------------------------------------------------------
// Best-known BROKER SERVER time. TimeTradeServer() is the calculated
// server clock (advances without a fresh tick); TimeCurrent() (last tick
// time) is the fallback. Returns 0 only when neither is known yet.
datetime KK_ServerNow()
{
   datetime t = TimeTradeServer();
   if(t <= 0) t = TimeCurrent();
   return t;
}

// Parse a baked expiry string into a datetime.
//   ""               -> 0  (perpetual / no expiry)
//   "YYYY.MM.DD"      -> that date (the build script bakes end-of-day 23:59:59)
//   "YYYY.MM.DD HH:MM:SS" -> exact moment
// An unparseable non-empty string returns 0 (treated as perpetual) - the build
// script validates the format before baking so this never silently hides a typo.
datetime KK_ParseExpiry(const string expiry)
{
   if(StringLen(expiry) == 0) return 0;
   return StringToTime(expiry);   // 0 on parse failure
}

// True only when an expiry is set AND the server clock has passed it.
// FAILS OPEN (returns false) when the expiry is empty/unparseable or the server
// time is not yet known, so a connected-but-valid or briefly-offline user is
// never falsely blocked; callers re-check this every tick/calc.
bool KK_AccessExpired(const string expiry)
{
   datetime exp = KK_ParseExpiry(expiry);
   if(exp <= 0) return false;        // perpetual / unparseable -> never expire
   datetime now = KK_ServerNow();
   if(now <= 0) return false;        // server time unknown -> fail OPEN
   return now > exp;
}

#endif // KK_COMMON_ACCOUNTLOCK_MQH
