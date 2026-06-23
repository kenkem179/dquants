//+------------------------------------------------------------------+
//|  KK-Common/AccountLock.mqh - shared account-lock guard for all    |
//|  KK EAs (KK-KenKem, KK-MasterVP, ...).                            |
//|                                                                   |
//|  Each EA carries two HIDDEN compiled-in strings (plain globals,   |
//|  NOT `input`), both empty by default = runs on any account:       |
//|     ALLOWED_ACCOUNT_ID      - the MT5 login number                |
//|     ALLOWED_ACCOUNT_SERVER  - the MT5 trade-server name           |
//|  A login number is only unique WITHIN a server (the same number   |
//|  can exist on different brokers/servers), so the lock pins both.  |
//|  The per-account release script bakes one (id, server) pair in,   |
//|  producing one account-locked .ex5 per account.                   |
//|                                                                   |
//|  Call KK_AccountAuthorized(ALLOWED_ACCOUNT_ID, ALLOWED_ACCOUNT_   |
//|  SERVER) at the very top of OnInit. On mismatch it raises         |
//|  Alert("Invalid Account ID") and returns false; the EA MUST then  |
//|  `return INIT_FAILED` so MT5 never calls OnTick - no detection,   |
//|  no execution, nothing.                                           |
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

#endif // KK_COMMON_ACCOUNTLOCK_MQH
