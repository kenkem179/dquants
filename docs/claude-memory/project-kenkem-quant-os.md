---
name: project-kenkem-quant-os
description: "What the dquants repo is — KenKem Quant OS, a tick-data quant research stack for XAUUSD/BTCUSD scalping"
metadata: 
  node_type: memory
  type: project
  originSessionId: 93eabcdd-ed73-4c3a-8a0a-c1d68af64676
---

`dquants` is **KenKem Quant OS**: a quant research stack to find/validate/deploy XAUUSD & BTCUSD
scalping edges on M1/M3 using real MT5 tick data. Master plan: `docs/KENKEM_QUANT_OS.md`. Guidance:
`CLAUDE.md`.

Four-layer architecture (the load-bearing design): Layer 1 Python research (`pipeline/`, `research/`,
DuckDB+Parquet) → Layer 2 C++ strategy core (`cpp_core/`, PURE logic, no MT5 APIs) → Layer 3 C++ tick
backtester (the true tester, not MT5) → Layer 4 thin MQL5 EA (`mql5/`). Only signal/SL/TP port to MQL5;
OrderSend/etc stay in Layer 4.

10-phase SOP is encoded as project skills: `/quant-import-data` → `validate-data` → `build-features` →
`discovery` → `hypothesis` → `backtest` → `sensitivity` → `walkforward` → `promote-mt5`.

Raw data: `data/btcusd/BTCUSD_ticks_mt5_<year>.csv`, tab-separated, ~12GB (2025≈7.2GB/148M rows),
gitignored, left in place. LAST/VOLUME are 0 on this feed — use tick count, not volume. See
[[python-env-kenkem]] and [[user-goal-quant-stack]].
