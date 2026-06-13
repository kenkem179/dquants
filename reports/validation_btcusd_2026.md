# Validation Report — BTCUSD 2026

- Source: `ticks_btcusd_2026.parquet`
- Clean output: `ticks_btcusd_2026_clean.parquet`
- Status: **PASS**  ·  validated in 6.0s

## Row accounting

| Metric | Rows | % |
|---|---:|---:|
| Input | 14,951,271 | 100% |
| Kept (clean) | 14,926,943 | 99.837% |
| Dropped | 24,328 | 0.163% |

### Dropped (removed — clearly bad)

| Reason | Rows | % |
|---|---:|---:|
| bad_px | 0 | 0.000% |
| neg_spread | 0 | 0.000% |
| exact_dup | 24,328 | 0.163% |
| spike | 0 | 0.000% |

### Flagged (kept — noted for review)

| Reason | Rows | Note |
|---|---:|---|
| ts_collision | 534 | distinct ticks sharing one ms — legitimate |
| zero_spread | 0 | bid == ask |
| wide_spread | 0 | spread > 5.0× median |

## Spread distribution (clean)

| mean | median | p95 | p99 | min | max |
|---:|---:|---:|---:|---:|---:|
| 11.2201 | 12.6 | 12.6 | 12.6 | 7.0 | 18.9 |

## Time gaps (clean)

| > 1s | > 10s | > 60s | > 5m | > 1h | max gap |
|---:|---:|---:|---:|---:|---:|
| 4,259,902 | 100,031 | 46 | 0 | 0 | 228.3s |

Largest gaps:

| start | end | gap (s) |
|---|---|---:|
| 2026-01-25 07:00:54.038 | 2026-01-25 07:04:42.346 | 228.3 |
| 2026-01-18 06:00:58.228 | 2026-01-18 06:04:05.815 | 187.6 |
| 2026-05-17 06:00:54.992 | 2026-05-17 06:04:00.916 | 185.9 |
| 2026-03-01 06:00:57.658 | 2026-03-01 06:04:03.526 | 185.9 |
| 2026-03-29 06:00:59.43 | 2026-03-29 06:04:05.29 | 185.9 |

## Coverage (clean)

- Days with data: **160** (2026-01-01 → 2026-06-09)
- Ticks/day: min 23,557 · median 83,698 · max 412,336
- Missing hours-of-day (across whole year): none

## Residual check (post-clean — must all be 0)

| bad_px | neg_spread | exact_dup |
|---:|---:|---:|
| 0 | 0 | 0 |
