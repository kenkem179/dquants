# KK-MasterVP 1.05 — account-locked builds

- Built: `2026-06-23T13:09:34Z` (UTC) · commit `4235983` on `reliableBaseline`
- Each EA refuses to run on any account but the one baked in
  (Alert "Invalid Account ID" + INIT_FAILED via KK-Common/AccountLock.mqh).
- `.ex5` files are gitignored build artifacts; deploy them per account.

| account id | server | file |
|------------|--------|------|
| 433801493 | Exness-MT5Trial7 | `KK-MasterVP-1.05_433801493.ex5` |
