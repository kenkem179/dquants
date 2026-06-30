# KK-KenKem — release 1.04

- Built: `2026-06-30T12:30:43Z` (UTC)
- Source commit: `6153e9e` on `3-codex-handoff`
- EA: `KK-KenKem-1.04.ex5` (locked build of `KK-KenKem.mq5`)

## Parameter sets

| variant | .set file | base preset | overrides |
|---------|-----------|-------------|-----------|
| xauusd-m1 | `KK-KenKem-1.04-xauusd-m1.set` | `KK-KenKem-XAUUSD-M1-D5-E4Long.set` | InpExportBarTrace=false |
| xauusd-m1-prop | `KK-KenKem-1.04-xauusd-m1-prop.set` | `KK-KenKem-XAUUSD-M1-D5-E4Long.set` | MAX_DAILY_LOSS_RATIO=0.044 ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN=0.07 ACCOUNT_DD_RATIO_TO_SOFT_BLOCK=0.09 USE_EQUITY_DD_BASIS=true PROP_BASELINE_EQUITY=100000 InpExportBarTrace=false |
| xauusd-m1-mixed-fn | `KK-KenKem-1.04-xauusd-m1-mixed-fn.set` | `KK-KenKem-XAUUSD-M1-D5-E4Long.set` | COMMON_MAX_RISK_PER_TRADE=0.001 MAX_DAILY_LOSS_RATIO=0.042 ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN=0.078 ACCOUNT_DD_RATIO_TO_SOFT_BLOCK=0.092 MADE_FOR_PROP_TRADING=true ENABLE_PEAK_BALANCE_DECAY=false USE_EQUITY_DD_BASIS=true PROP_BASELINE_EQUITY=100000 InpExportBarTrace=false |
