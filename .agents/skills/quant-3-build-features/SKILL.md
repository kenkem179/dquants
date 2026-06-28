---
name: quant-3-build-features
description: Phase 3+4 of the KenKem Quant OS SOP — build M1/M3 bars, engineer indicator features, and create forward-return labels. Use after data validation.
---

# Phase 3+4 — Bars, Features, Labels

Turn clean ticks into the research dataset: bars → features → forward-return labels.

## Input
Cleaned `data/processed/ticks_<year>.parquet` (from `/quant-2-validate-data`).

## Output
- `data/processed/bars_M1_<year>.parquet`, `bars_M3_<year>.parquet`:
  `open,high,low,close,spread_mean,spread_max,tick_count`.
- `data/features/features.parquet`.
- `data/labels/labels.parquet`.

## Features (all causal — at bar `t` use only data ≤ `t`)
- **Trend:** EMA(12,25,50,75,100,200) — slope, distance, compression.
- **Momentum:** RSI(7,14,21) — value, slope, acceleration.
- **DMI:** ADX, DI+, DI- — DI spread, ADX trend/acceleration.
- **Volatility:** ATR — value, slope, **percentile**.
- **Structure:** Volume Profile — distance to POC / VAH / VAL.
- **Ichimoku:** distance to Tenkan / Kijun, cloud thickness.
- **Time:** session, hour, day-of-week.

## Labels
- `future_return_{5,10,20,60}` = `close(t+k) - close(t)`.
- `hit_tp_before_sl` (triple-barrier) — the most useful target for scalping.

Put logic in `pipeline/build_bars.py`, `pipeline/features.py`, `pipeline/labels.py`. Use `ta`/Polars.

## Acceptance
- **No lookahead** — verify each feature uses only past data; labels computed strictly from future bars.
- No unexpected nulls (warmup periods excepted and documented).
- Bars reconcile with tick aggregates (tick_count > 0, OHLC sane).

Next: `/quant-5-discovery`. See `docs/KENKEM_QUANT_OS.md` §7 (Phase 3–4).
