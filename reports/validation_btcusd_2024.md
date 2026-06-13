# Validation Report — BTCUSD 2024

- Source: `ticks_btcusd_2024.parquet`
- Clean output: `ticks_btcusd_2024_clean.parquet`
- Status: **PASS**  ·  validated in 32.9s

## Row accounting

| Metric | Rows | % |
|---|---:|---:|
| Input | 83,350,554 | 100% |
| Kept (clean) | 83,264,725 | 99.897% |
| Dropped | 85,829 | 0.103% |

### Dropped (removed — clearly bad)

| Reason | Rows | % |
|---|---:|---:|
| bad_px | 0 | 0.000% |
| neg_spread | 0 | 0.000% |
| exact_dup | 85,828 | 0.103% |
| spike | 1 | 0.000% |

### Flagged (kept — noted for review)

| Reason | Rows | Note |
|---|---:|---|
| ts_collision | 85,867 | distinct ticks sharing one ms — legitimate |
| zero_spread | 0 | bid == ask |
| wide_spread | 5,964 | spread > 5.0× median |

## Spread distribution (clean)

| mean | median | p95 | p99 | min | max |
|---:|---:|---:|---:|---:|---:|
| 23.4832 | 20.29 | 47.45 | 58.34 | 4.09 | 180.24 |

## Time gaps (clean)

| > 1s | > 10s | > 60s | > 5m | > 1h | max gap |
|---:|---:|---:|---:|---:|---:|
| 12,088,496 | 4,984 | 195 | 33 | 18 | 24919.5s |

Largest gaps:

| start | end | gap (s) |
|---|---|---:|
| 2024-04-08 17:04:40.84 | 2024-04-09 00:00:00.314 | 24919.5 |
| 2024-04-28 18:00:51.513 | 2024-04-29 00:00:00.303 | 21548.8 |
| 2024-04-02 19:02:39.65 | 2024-04-03 00:00:00.164 | 17840.5 |
| 2024-04-21 20:00:52.761 | 2024-04-22 00:00:00.439 | 14347.7 |
| 2024-03-30 20:01:15.85 | 2024-03-31 00:00:00.247 | 14324.4 |

## Coverage (clean)

- Days with data: **366** (2024-01-01 → 2024-12-31)
- Ticks/day: min 73,388 · median 209,219 · max 736,341
- Missing hours-of-day (across whole year): none

## Residual check (post-clean — must all be 0)

| bad_px | neg_spread | exact_dup |
|---:|---:|---:|
| 0 | 0 | 0 |
