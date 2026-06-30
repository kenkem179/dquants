# Mixed Prop Portfolio — v1.0

One FundedNext Stellar-2 $100K account running three legs together.

| component | version | EA file | symbol · TF | mixed .set | risk/trade |
|-----------|---------|---------|-------------|------------|-----------|
| MasterVP XAU | 1.08 | `KK-MasterVP-1.08.ex5` | XAUUSD · M5 | `KK-MasterVP-1.08-xauusd-m5-mixed-fn.set` | 0.43% |
| MasterVP BTC | 1.08 | `KK-MasterVP-1.08.ex5` | BTCUSD · M5 | `KK-MasterVP-1.08-btcusd-m5-mixed-fn.set` | 0.15% |
| KenKem XAU   | 1.04 | `KK-KenKem-1.04.ex5` | XAUUSD · M1 | `KK-KenKem-1.04-xauusd-m1-mixed-fn.set` | 0.10% |

**Joint DD caps (both EAs, measured on the SHARED equity HWM):** daily 4.2% ·
soft-derisk 7.8% · hard-halt 9.2%.

## Overall-DD anchor (no manual seeding needed)
Both mixed sets bake the contract-baseline anchor (`InpPropBaselineEquity` /
`PROP_BASELINE_EQUITY` = **100000**). On a fresh attach the overall-DD high-water
mark is seeded at the contract size, so a drawn-down account is read at its TRUE
drawdown (not 0%). Change this to your contract size for a $50K/$200K account.
The HWM trails UP from the baseline as new equity peaks print, and persists to
the shared file `Common/Files/KK_PropState_<login>.txt` (RESET = delete that file).

## Deploy
1. Copy both `.ex5` into `MQL5/Experts/` (or the symlinked `Experts/dquants/` path).
2. Attach 3 charts on the SAME account: XAUUSD M5, BTCUSD M5, XAUUSD M1.
3. Load the matching mixed `.set` on each (Inputs -> Load).
4. KenKem only: clear any stale `KKG.*` global variables before attach.
5. Confirm in the log: MasterVP prints `prop baseline floor applied: peakEquity=100000.00`.

> Bundle assembled by `scripts/make_prop_portfolio.sh 1.0`. Bump the portfolio
> version whenever a component EA is re-released.
