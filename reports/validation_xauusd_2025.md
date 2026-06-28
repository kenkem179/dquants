# Validation Report — XAUUSD 2025

- Source: `ticks_xauusd_2025.parquet`
- Clean output: `ticks_xauusd_2025_clean.parquet`
- Status: **PASS**  ·  validated in 23.9s

## Row accounting

| Metric | Rows | % |
|---|---:|---:|
| Input | 76,283,473 | 100% |
| Kept (clean) | 76,215,156 | 99.910% |
| Dropped | 68,317 | 0.090% |

### Dropped (removed — clearly bad)

| Reason | Rows | % |
|---|---:|---:|
| bad_px | 0 | 0.000% |
| neg_spread | 0 | 0.000% |
| exact_dup | 68,317 | 0.090% |
| spike | 0 | 0.000% |

### Flagged (kept — noted for review)

| Reason | Rows | Note |
|---|---:|---|
| ts_collision | 158,115 | distinct ticks sharing one ms — legitimate |
| zero_spread | 0 | bid == ask |
| wide_spread | 4,030 | spread > 5.0× median |

## Spread distribution (clean)

| mean | median | p95 | p99 | min | max |
|---:|---:|---:|---:|---:|---:|
| 0.1124 | 0.112 | 0.112 | 0.112 | 0.111 | 2.8 |

## Time gaps (clean)

| > 1s | > 10s | > 60s | > 5m | > 1h | max gap |
|---:|---:|---:|---:|---:|---:|
| 9,219,790 | 3,176 | 326 | 263 | 258 | 263222.0s |

Largest gaps:

| start | end | gap (s) |
|---|---|---:|
| 2025-04-17 20:57:58.076 | 2025-04-20 22:05:00.1 | 263222.0 |
| 2025-07-04 16:44:58.612 | 2025-07-06 22:05:00.07 | 192001.5 |
| 2025-11-28 19:44:58.942 | 2025-12-01 00:00:30.014 | 188131.1 |
| 2025-10-31 20:57:56.706 | 2025-11-02 23:01:30.015 | 180213.3 |
| 2025-04-04 20:57:58.43 | 2025-04-06 22:13:54.873 | 177356.4 |

## Coverage (clean)

- Days with data: **311** (2025-01-01 → 2025-12-31)
- Ticks/day: min 2,181 · median 232,600 · max 1,005,517
- Missing hours-of-day (across whole year): none

Low-coverage days (< 25% of median):

| day | ticks |
|---|---:|
| 2025-12-07 | 2,181 |
| 2025-01-01 | 3,060 |
| 2025-01-05 | 3,243 |
| 2025-01-19 | 4,789 |
| 2025-01-12 | 5,110 |
| 2025-02-23 | 6,067 |
| 2025-03-23 | 6,790 |
| 2025-09-14 | 7,105 |
| 2025-08-24 | 7,181 |
| 2025-07-20 | 7,790 |

## Residual check (post-clean — must all be 0)

| bad_px | neg_spread | exact_dup |
|---:|---:|---:|
| 0 | 0 | 0 |
