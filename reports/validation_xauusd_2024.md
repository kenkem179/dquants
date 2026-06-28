# Validation Report — XAUUSD 2024

- Source: `ticks_xauusd_2024.parquet`
- Clean output: `ticks_xauusd_2024_clean.parquet`
- Status: **PASS**  ·  validated in 12.1s

## Row accounting

| Metric | Rows | % |
|---|---:|---:|
| Input | 39,791,521 | 100% |
| Kept (clean) | 39,766,850 | 99.938% |
| Dropped | 24,671 | 0.062% |

### Dropped (removed — clearly bad)

| Reason | Rows | % |
|---|---:|---:|
| bad_px | 0 | 0.000% |
| neg_spread | 0 | 0.000% |
| exact_dup | 24,671 | 0.062% |
| spike | 0 | 0.000% |

### Flagged (kept — noted for review)

| Reason | Rows | Note |
|---|---:|---|
| ts_collision | 596 | distinct ticks sharing one ms — legitimate |
| zero_spread | 0 | bid == ask |
| wide_spread | 6,157 | spread > 5.0× median |

## Spread distribution (clean)

| mean | median | p95 | p99 | min | max |
|---:|---:|---:|---:|---:|---:|
| 0.1195 | 0.113 | 0.125 | 0.168 | 0.044 | 5.642 |

## Time gaps (clean)

| > 1s | > 10s | > 60s | > 5m | > 1h | max gap |
|---:|---:|---:|---:|---:|---:|
| 11,650,945 | 6,299 | 355 | 271 | 262 | 263280.6s |

Largest gaps:

| start | end | gap (s) |
|---|---|---:|
| 2024-03-28 20:56:59.854 | 2024-03-31 22:05:00.474 | 263280.6 |
| 2024-04-05 19:02:17.368 | 2024-04-08 00:00:00.045 | 190662.7 |
| 2024-11-29 18:29:58.996 | 2024-12-01 23:05:00.176 | 189301.2 |
| 2024-04-12 19:02:02.629 | 2024-04-14 22:09:32.086 | 184049.5 |
| 2024-11-01 20:57:58.673 | 2024-11-03 23:05:00.442 | 180421.8 |

## Coverage (clean)

- Days with data: **312** (2024-01-01 → 2024-12-31)
- Ticks/day: min 1,851 · median 135,517 · max 373,342
- Missing hours-of-day (across whole year): none

Low-coverage days (< 25% of median):

| day | ticks |
|---|---:|
| 2024-12-22 | 1,851 |
| 2024-12-15 | 1,931 |
| 2024-01-01 | 1,969 |
| 2024-02-25 | 2,092 |
| 2024-02-11 | 2,171 |
| 2024-12-25 | 2,365 |
| 2024-01-07 | 2,619 |
| 2024-01-14 | 2,673 |
| 2024-01-21 | 2,802 |
| 2024-03-03 | 2,894 |

## Residual check (post-clean — must all be 0)

| bad_px | neg_spread | exact_dup |
|---:|---:|---:|
| 0 | 0 | 0 |
