# KK-MasterVP (MQL5-Market edition) — release 1.07

- Built: `2026-06-27T12:21:05Z` (UTC)
- Source commit: `1ac0db1` on `2-stabilization`
- EA: `KK-MasterVP-Market-1.07.ex5` — strategy internals are HIDDEN (fixed);
  only the user-facing inputs (risk, profit-taking, trading hours, news, basic
  execution safety) appear in the dialog.
- Internals hidden via `release.market.whitelist` (non-whitelisted inputs stripped
  to fixed globals + locked defaults baked in); dev source restored after build.
- `.set` files are stripped to the user-facing keys only (no internal params leaked).

## User-facing parameter sets

| variant | .set file | base preset | overrides |
|---------|-----------|-------------|-----------|
| xauusd-m5 | `KK-MasterVP-Market-1.07-xauusd-m5.set` | `KK-MasterVP-XAUUSD-M5.set` | — |
| xauusd-m5-prop | `KK-MasterVP-Market-1.07-xauusd-m5-prop.set` | `KK-MasterVP-XAUUSD-M5.set` | InpRiskAccPct=0.5 InpMaxDailyDDPct=4.4 InpMaxPeakDDPct=9.0 |
