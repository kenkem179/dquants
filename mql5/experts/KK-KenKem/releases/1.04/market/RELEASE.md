# KK-KenKem (MQL5-Market edition) — release 1.04

- Built: `2026-06-30T12:19:31Z` (UTC)
- Source commit: `b70c7d8` on `3-codex-handoff`
- EA: `KK-KenKem-Market-1.04.ex5` — strategy internals are HIDDEN (fixed);
  only the user-facing inputs (risk, profit-taking, trading hours, news, basic
  execution safety) appear in the dialog.
- Internals hidden via `release.market.whitelist` (non-whitelisted inputs stripped
  to fixed globals + locked defaults baked in); dev source restored after build.
- `.set` files are stripped to the user-facing keys only (no internal params leaked).

## User-facing parameter sets

| variant | .set file | base preset | overrides |
|---------|-----------|-------------|-----------|
| xauusd-m1 | `KK-KenKem-Market-1.04-xauusd-m1.set` | `KK-KenKem-XAUUSD-M1-D5-E4Long.set` | InpExportBarTrace=false |
| xauusd-m1-prop | `KK-KenKem-Market-1.04-xauusd-m1-prop.set` | `KK-KenKem-XAUUSD-M1-D5-E4Long.set` | MAX_DAILY_LOSS_RATIO=0.044 ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN=0.07 ACCOUNT_DD_RATIO_TO_SOFT_BLOCK=0.09 USE_EQUITY_DD_BASIS=true InpExportBarTrace=false |
| xauusd-m1-mixed-fn | `KK-KenKem-Market-1.04-xauusd-m1-mixed-fn.set` | `KK-KenKem-XAUUSD-M1-D5-E4Long.set` | COMMON_MAX_RISK_PER_TRADE=0.001 MAX_DAILY_LOSS_RATIO=0.042 ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN=0.078 ACCOUNT_DD_RATIO_TO_SOFT_BLOCK=0.092 MADE_FOR_PROP_TRADING=true ENABLE_PEAK_BALANCE_DECAY=false USE_EQUITY_DD_BASIS=true InpExportBarTrace=false |
