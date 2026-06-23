# KK-KenKem (MQL5-Market edition) — release 1.02

- Built: `2026-06-23T08:25:37Z` (UTC)
- Source commit: `2c02a55` on `reliableBaseline`
- EA: `KK-KenKem-Market-1.02.ex5` — strategy internals are HIDDEN (fixed);
  only the user-facing inputs (risk, profit-taking, trading hours, news, basic
  execution safety) appear in the dialog.
- Compiled by swapping `Inputs.release.mqh` in for the build; dev source untouched.
- `.set` files are stripped to the user-facing keys only (no internal params leaked).

## User-facing parameter sets

| variant | .set file | base preset | overrides |
|---------|-----------|-------------|-----------|
| xauusd-m1 | `KK-KenKem-Market-1.02-xauusd-m1.set` | `KK-KenKem-XAUUSD-M1-D5-E4Long.set` | — |
| xauusd-m1-prop | `KK-KenKem-Market-1.02-xauusd-m1-prop.set` | `KK-KenKem-XAUUSD-M1-D5-E4Long.set` | MAX_DAILY_LOSS_RATIO=0.044 ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN=0.07 ACCOUNT_DD_RATIO_TO_SOFT_BLOCK=0.09 |
