---
name: pipeline-phase3-conventions
description: "Phase 3/4 dataset conventions — bar construction, feature set, labels, output paths"
metadata: 
  node_type: memory
  type: project
  originSessionId: 93eabcdd-ed73-4c3a-8a0a-c1d68af64676
---

Phase 3 (`/quant-build-features`) is implemented across `pipeline/build_bars.py`, `indicators.py`,
`features.py`, `labels.py` (all unit-tested in `pipeline/tests/`).

**Bars** (`data/processed/bars_btcusd_<tf>_<year>.parquet`, tf ∈ {M1,M3}):
- OHLC built on **mid** = (bid+ask)/2 (broker-neutral); `spread_mean`/`spread_max`/`tick_count` kept
  separately. The execution sim / MQL5 EA must apply half-spread at fill time and compute indicators
  on mid for parity.
- **Sparse / event-time**: a bar exists only for a minute with ≥1 tick (matches MT5; skips weekends &
  missing days). Indicators operate on the bar *sequence*, not wall-clock.

**Indicators** (`pipeline/indicators.py`): hand-written, causal, Wilder/MT5 conventions (EMA
adjust=False; RSI/ATR/ADX use Wilder RMA alpha=1/n). Volume profile uses **tick_count** as the weight
(no real volume) and references the **prior completed day's** POC/VAH/VAL (causal).

**Features** (`data/features/features_btcusd_<tf>.parquet`, all years, one file/tf): 41 features keyed
by `ts` (+ `close`,`atr`). EMA(12/25/50/75/100/200) dist+slope+compression; RSI(7/14/21)
value/slope/accel; ADX/DI+di_spread/adx_slope/adx_accel; ATR/atr_slope/atr_pct(rolling percentile);
prior-day dist_poc/vah/val; Ichimoku dist_tenkan/kijun/cloud_thickness/dist_cloud; hour/dow/session.
Fully dense after ~1440-bar (M1) / 480-bar (M3) warmup.

**Labels** (`data/labels/labels_btcusd_<tf>.parquet`): `fwd_ret_{5,10,20,60}` and
`hit_tp_before_sl` (triple-barrier, default tp=sl=1×ATR, horizon=60; +1 TP-first, -1 SL-first/ambiguous,
0 timeout, NaN unobservable). M1 split ≈ 49.6%/50.4% — balanced.

**No-lookahead** is enforced by `test_features.py::test_feature_frame_is_causal` (truncating future
bars must not change past features). Next: `/quant-discovery` joins features+labels on `ts`. See
[[pipeline-phase3-conventions]] sibling [[btcusd-data-quirks]] and [[project-kenkem-quant-os]].
