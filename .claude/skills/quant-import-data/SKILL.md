---
name: quant-import-data
description: Phase 1 of the KenKem Quant OS SOP — stream raw MT5 tab-separated tick CSVs into typed, partitioned Parquet. Use when importing or re-importing tick data before any research.
---

# Phase 1 — Import Data

Convert raw MT5 tick exports into clean, typed Parquet. This is the entry point of the pipeline.

## Input
`data/btcusd/BTCUSD_ticks_mt5_<year>.csv` — tab-separated, header:
`<DATE>\t<TIME>\t<BID>\t<ASK>\t<LAST>\t<VOLUME>\t<FLAGS>`. ~12GB total; 2025 ≈ 148M rows.

## Output
`data/processed/ticks_<year>.parquet` with columns: `ts` (UTC timestamp), `bid`, `ask`, `mid`,
`spread`, `flags`. Partition by year (and month if helpful).

## How
- **Never** use `pandas.read_csv` — files are too large. Use **DuckDB** (`read_csv_auto` with
  `delim='\t'`) or **Polars** `scan_csv(separator='\t')` + `sink_parquet` (streaming, lazy).
- Parse `DATE` (`YYYY.MM.DD`) + `TIME` (`HH:MM:SS.mmm`) into one timestamp.
- Compute `mid=(bid+ask)/2`, `spread=ask-bid`.
- Ignore `LAST`/`VOLUME` (always 0 on this feed).
- Run inside the `kenkem` conda env.

Put the importer in `pipeline/import_data.py`.

## Acceptance
- Output row count matches input line count (minus header).
- No parse/cast errors; `ts` strictly typed; `spread` present.
- Spot-check first/last timestamps per year.

Next: `/quant-validate-data`. See `docs/KENKEM_QUANT_OS.md` §3–4 for the data contract.
