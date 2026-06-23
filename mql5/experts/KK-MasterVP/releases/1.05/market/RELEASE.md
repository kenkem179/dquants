# KK-MasterVP (MQL5-Market edition) — release 1.05

- Built: `2026-06-23T10:22:16Z` (UTC)
- Source commit: `51b63e6` on `reliableBaseline`
- EA: `KK-MasterVP-Market-1.05.ex5` — strategy internals are HIDDEN (fixed);
  only the user-facing inputs (risk, profit-taking, trading hours, news, basic
  execution safety) appear in the dialog.
- Compiled by swapping `Inputs.release.mqh` in for the build; dev source untouched.
- `.set` files are stripped to the user-facing keys only (no internal params leaked).

## User-facing parameter sets

| variant | .set file | base preset | overrides |
|---------|-----------|-------------|-----------|
| xauusd-m5 | `KK-MasterVP-Market-1.05-xauusd-m5.set` | `KK-MasterVP-XAUUSD-M5.set` | — |
| xauusd-m5-prop | `KK-MasterVP-Market-1.05-xauusd-m5-prop.set` | `KK-MasterVP-XAUUSD-M5.set` | InpRiskAccPct=0.5 InpMaxDailyDDPct=4.4 InpMaxPeakDDPct=9.0 |
