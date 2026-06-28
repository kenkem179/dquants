# Validation Report — XAUUSD 2026

- Source: `ticks_xauusd_2026.parquet`
- Clean output: `ticks_xauusd_2026_clean.parquet`
- Status: **PASS**  ·  validated in 17.5s

## Row accounting

| Metric | Rows | % |
|---|---:|---:|
| Input | 46,686,241 | 100% |
| Kept (clean) | 46,578,880 | 99.770% |
| Dropped | 107,361 | 0.230% |

### Dropped (removed — clearly bad)

| Reason | Rows | % |
|---|---:|---:|
| bad_px | 0 | 0.000% |
| neg_spread | 0 | 0.000% |
| exact_dup | 107,361 | 0.230% |
| spike | 0 | 0.000% |

### Flagged (kept — noted for review)

| Reason | Rows | Note |
|---|---:|---|
| ts_collision | 461,997 | distinct ticks sharing one ms — legitimate |
| zero_spread | 0 | bid == ask |
| wide_spread | 1,084 | spread > 5.0× median |

## Spread distribution (clean)

| mean | median | p95 | p99 | min | max |
|---:|---:|---:|---:|---:|---:|
| 0.1847 | 0.196 | 0.255 | 0.35 | 0.112 | 1.4 |

## Time gaps (clean)

| > 1s | > 10s | > 60s | > 5m | > 1h | max gap |
|---:|---:|---:|---:|---:|---:|
| 3,180,815 | 415 | 118 | 107 | 104 | 263027.1s |

Largest gaps:

| start | end | gap (s) |
|---|---|---:|
| 2026-04-02 20:57:58.668 | 2026-04-05 22:01:45.815 | 263027.1 |
| 2026-01-16 21:57:58.238 | 2026-01-18 23:09:53.405 | 177115.2 |
| 2026-01-02 21:57:58.775 | 2026-01-04 23:07:09.821 | 176951.0 |
| 2026-04-10 20:57:59.202 | 2026-04-12 22:06:02.528 | 176883.3 |
| 2026-03-27 20:57:57.974 | 2026-03-29 22:04:32.25 | 176794.3 |

## Coverage (clean)

- Days with data: **127** (2026-01-01 → 2026-05-29)
- Ticks/day: min 8,071 · median 300,328 · max 2,315,498
- Missing hours-of-day (across whole year): none

Low-coverage days (< 25% of median):

| day | ticks |
|---|---:|
| 2026-01-01 | 8,071 |
| 2026-02-15 | 10,072 |
| 2026-02-22 | 11,035 |
| 2026-05-03 | 11,882 |
| 2026-04-26 | 12,031 |
| 2026-05-10 | 13,182 |
| 2026-01-11 | 13,264 |
| 2026-02-08 | 14,015 |
| 2026-01-04 | 15,697 |
| 2026-05-24 | 15,864 |

## Residual check (post-clean — must all be 0)

| bad_px | neg_spread | exact_dup |
|---:|---:|---:|
| 0 | 0 | 0 |
