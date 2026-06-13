# Validation Report — BTCUSD 2025

- Source: `ticks_btcusd_2025.parquet`
- Clean output: `ticks_btcusd_2025_clean.parquet`
- Status: **PASS**  ·  validated in 57.5s

## Row accounting

| Metric | Rows | % |
|---|---:|---:|
| Input | 148,657,447 | 100% |
| Kept (clean) | 148,534,200 | 99.917% |
| Dropped | 123,247 | 0.083% |

### Dropped (removed — clearly bad)

| Reason | Rows | % |
|---|---:|---:|
| bad_px | 0 | 0.000% |
| neg_spread | 0 | 0.000% |
| exact_dup | 123,247 | 0.083% |
| spike | 0 | 0.000% |

### Flagged (kept — noted for review)

| Reason | Rows | Note |
|---|---:|---|
| ts_collision | 14,285 | distinct ticks sharing one ms — legitimate |
| zero_spread | 0 | bid == ask |
| wide_spread | 7,625 | spread > 5.0× median |

## Spread distribution (clean)

| mean | median | p95 | p99 | min | max |
|---:|---:|---:|---:|---:|---:|
| 17.3831 | 20.16 | 20.31 | 20.31 | 7.85 | 306.41 |

## Time gaps (clean)

| > 1s | > 10s | > 60s | > 5m | > 1h | max gap |
|---:|---:|---:|---:|---:|---:|
| 3,024,239 | 57,861 | 155 | 14 | 4 | 172801.5s |

Largest gaps:

| start | end | gap (s) |
|---|---|---:|
| 2025-03-29 23:59:58.603 | 2025-04-01 00:00:00.118 | 172801.5 |
| 2025-04-26 23:59:58.948 | 2025-04-28 00:00:00.118 | 86401.2 |
| 2025-11-30 18:29:04.65 | 2025-12-01 00:00:01.017 | 19856.4 |
| 2025-05-17 03:15:55.356 | 2025-05-17 04:37:40.774 | 4905.4 |
| 2025-12-13 07:19:24.534 | 2025-12-13 08:01:17.831 | 2513.3 |

## Coverage (clean)

- Days with data: **362** (2025-01-01 → 2025-12-31)
- Ticks/day: min 29,618 · median 508,762 · max 677,423
- Missing hours-of-day (across whole year): none

Low-coverage days (< 25% of median):

| day | ticks |
|---|---:|
| 2025-12-27 | 29,618 |
| 2025-12-13 | 29,642 |
| 2025-10-25 | 31,576 |
| 2025-12-28 | 32,138 |
| 2025-11-30 | 32,535 |
| 2025-11-01 | 34,088 |
| 2025-12-20 | 36,102 |
| 2025-11-29 | 40,236 |
| 2025-10-18 | 41,884 |
| 2025-12-06 | 45,686 |

## Residual check (post-clean — must all be 0)

| bad_px | neg_spread | exact_dup |
|---:|---:|---:|
| 0 | 0 | 0 |
