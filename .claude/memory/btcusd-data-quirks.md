---
name: btcusd-data-quirks
description: "Non-obvious quirks in the BTCUSD MT5 tick data (missing days, flat-spread years) that affect backtest realism"
metadata: 
  node_type: memory
  type: project
  originSessionId: 93eabcdd-ed73-4c3a-8a0a-c1d68af64676
---

Discovered during Phase 2 validation (`/quant-validate-data`) of the BTCUSD MT5 tick feed:

**Spread realism differs sharply by year** — this is the biggest trap:
- 2024: realistic *variable* spread — median 20.3, p99 58.3 (widens ~3× in volatility).
- 2025: nearly *flat* spread — median 20.2, p99 20.3.
- 2026: *perfectly fixed* spread — median 12.6, p99 12.6.
**Why it matters:** spread is a dominant scalping cost. Execution sims calibrated on 2025/2026 will
understate cost during volatile periods. Prefer 2024 for cost-model calibration, or model spread
conservatively. (Playbook Part A: broker-specific behavior / spread analysis.)

**2025 is missing 3 full calendar days**: Mar 30, Mar 31 (one 48h gap) and Apr 27 (24h gap) → 362
days, not 365. Likely broker weekend/outage; ticks simply don't exist in source. Backtests spanning
those dates must tolerate the gap.

**Weekends have ~10× lower tick density** on this CFD feed (~30–45k ticks/day vs ~508k weekday median).
Not an error — reduced weekend BTC CFD liquidity.

**ts collisions are normal**: many ticks share a millisecond (up to 4). Validation KEEPS these (real
sub-ms ticks) and only drops exact-duplicate rows (same ts AND bid AND ask). LAST/VOLUME are always 0.

Validated/clean data lives in `data/processed/ticks_btcusd_<year>_clean.parquet`; per-year reports in
`reports/validation_btcusd_<year>.md`. Downstream phases should read the **`_clean`** files. See
[[project-kenkem-quant-os]].
