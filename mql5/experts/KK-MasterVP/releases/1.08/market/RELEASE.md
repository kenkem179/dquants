# KK-MasterVP (MQL5-Market edition) — release 1.08

- Built: `2026-06-30T12:18:59Z` (UTC)
- Source commit: `b70c7d8` on `3-codex-handoff`
- EA: `KK-MasterVP-Market-1.08.ex5` — strategy internals are HIDDEN (fixed);
  only the user-facing inputs (risk, profit-taking, trading hours, news, basic
  execution safety) appear in the dialog.
- Internals hidden via `release.market.whitelist` (non-whitelisted inputs stripped
  to fixed globals + locked defaults baked in); dev source restored after build.
- `.set` files are stripped to the user-facing keys only (no internal params leaked).

## User-facing parameter sets

| variant | .set file | base preset | overrides |
|---------|-----------|-------------|-----------|
| xauusd-m5 | `KK-MasterVP-Market-1.08-xauusd-m5.set` | `KK-MasterVP-XAUUSD-M5.set` | — |
| xauusd-m5-prop | `KK-MasterVP-Market-1.08-xauusd-m5-prop.set` | `KK-MasterVP-XAUUSD-M5.set` | InpRiskAccPct=0.43 InpMaxDailyDDPct=4.4 InpSoftBlockDDPct=8.0 InpSoftBlockLotMult=0.5 InpMaxPeakDDPct=9.5 |
