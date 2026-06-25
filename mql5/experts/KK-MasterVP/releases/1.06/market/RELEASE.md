# KK-MasterVP (MQL5-Market edition) — release 1.06

- Built: `2026-06-25T11:19:52Z` (UTC)
- Source commit: `7b3e486` on `UTC-time-fix`
- EA: `KK-MasterVP-Market-1.06.ex5` — strategy internals are HIDDEN (fixed);
  only the user-facing inputs (risk, profit-taking, trading hours, news, basic
  execution safety) appear in the dialog.
- Single-source: `Inputs.mqh` is hand-curated, so the `input` keyword in the live
  source is the visibility control — the dev build IS the market build.
- `.set` files are stripped to the user-facing keys only (no internal params leaked).

## User-facing parameter sets

| variant | .set file | base preset | overrides |
|---------|-----------|-------------|-----------|
| xauusd-m5 | `KK-MasterVP-Market-1.06-xauusd-m5.set` | `KK-MasterVP-XAUUSD-M5.set` | — |
| xauusd-m5-prop | `KK-MasterVP-Market-1.06-xauusd-m5-prop.set` | `KK-MasterVP-XAUUSD-M5.set` | InpRiskAccPct=0.5 InpMaxDailyDDPct=4.4 InpMaxPeakDDPct=9.0 |
