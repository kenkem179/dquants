---
name: cross-dataset-harness
description: Ready-to-run DuckDB multi-broker robustness harness — validate a locked .set across OANDA/Exness/Binance datasets
metadata: 
  node_type: memory
  type: project
  originSessionId: 35fbde55-89b4-4144-9fa7-95c311572ed0
---

User goal (2026-06-14): be able, on request, to use DuckDB to pull HUGE tick/bar datasets from OTHER brokers
(mainly BTCUSD/XAUUSD on **OANDA / Exness / Binance**) and sweep/validate that locked edges still hold across
datasets. **Code is built and ready (no data needed yet)** in `research/validation/` (commit `3301505`):

- `ingest_dataset.py` — DuckDB normalises any broker export → canonical Parquet (ts,bid,ask) + M1/M3/M5 BID
  bars + ticks CSV that the dependency-free C++ engines consume (same construction as the MT5-matched
  `cpp_core/tools/common/export_bars.py`). Supported `format`s: `mt5_tab` (Exness/MT5 tab CSV),
  `bidask_csv` (OANDA), `price_csv`, `binance_aggtrades`, `binance_klines` (synthesises a 4-tick O→L→H→C tape
  + synthetic spread). Smoke-tested on synthetic mt5_tab + klines.
- `cross_validate.py` — replays ONE `.set` across many datasets, prints PF/net/maxDD per dataset + a
  consistency summary (min PF, #profitable). Dispatches all 3 engines: mastervp (M3+ticks), monster
  (M1/M3/M5+ticks), kenkem (M1 bars, bar-driven w/ synthetic spread). **No per-broker re-optimization** (that
  would be overfitting) — it's a hold-the-edge robustness check.
- `datasets.example.json` — ready specs for OANDA/Exness/Binance × BTC/XAU. Added `make kenkem` so all three
  backtesters build via `make -C cpp_core all`.

**To run when data arrives:** drop files under `data/external/<broker>/` (gitignored), copy
`datasets.example.json`→`datasets.json` and fix paths/columns, then:
`python research/validation/ingest_dataset.py datasets.json` →
`python research/validation/cross_validate.py <mastervp|monster|kenkem> <btc|xau> <best_*.set> datasets.json`.
Use the kenkem env python `~/miniforge3/envs/kenkem/bin/python`. Relates to [[rnd-volume-features]],
[[milestone-production-promotion]], [[python-env-kenkem]].
