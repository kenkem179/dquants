#!/usr/bin/env python3
"""Unified, MT5-faithful bar builder: tick Parquet -> M1/M3/M5/M15 bid OHLC CSVs (+ gap report).

WHY THIS EXISTS
  MT5 builds M1 bars from the real tick stream, then builds EVERY higher timeframe by
  AGGREGATING M1 bars (not by re-reading ticks). To match the tester exactly we do the same:
    1. M1  = bid OHLC per minute bucket, tick_count = ticks in the minute.
    2. M3/M5/M15 = aggregate the M1 bars (max high, min low, last close, sum tick_count),
       bucketed to the TF boundary anchored at the Unix epoch (== UTC == MT5 server @ GMT 0).
  This guarantees M1 and the higher TFs are mutually consistent and matches how MT5's iATR /
  iIchimoku / iADX read their bar history.

PROVEN: M1 OHLC built this way is bit-exact vs the MT5 per-bar trace (high/low/close max|Δ|
  = 0.000000 over 82k XAU bars; see research/kenkem_parity/DATA_HEALTH_AND_BAR_PARITY.md).
  M3/M5/M15 are exact by construction (deterministic max/min/last of bit-exact M1).

GAP REPORT
  Higher-TF ATR is poisoned for ~ATR_PERIOD*2 bars after any multi-minute hole (gap TR spike).
  The exported XAU tick CSVs are MISSING whole trading days that MT5's tester DOES have. This
  tool prints every weekday gap >= --gap-min minutes so those windows can be excluded or refetched.

USAGE
  python cpp_core/tools/common/build_bars.py --sym xauusd --year 2025 \
      --from 2025-02-15 --to 2025-06-01 --out-dir cpp_core/tools [--tfs 1,3,5,15] [--clean]
  Outputs: <out-dir>/bars_<sym>_<tag>_m{1,3,5,15}.csv  (tag defaults to <year>, override --tag)
  Columns: ts_ms,open,high,low,close,tick_count  (ts_ms = epoch ms of bar OPEN, UTC).
"""
import argparse
import datetime as dt
import duckdb


def epoch_ms(s: str) -> int:
    return int((dt.datetime.strptime(s, "%Y-%m-%d") - dt.datetime(1970, 1, 1)).total_seconds() * 1000)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sym", default="xauusd")
    ap.add_argument("--year", default="2025")
    ap.add_argument("--from", dest="frm", default=None, help="YYYY-MM-DD inclusive (default: year start)")
    ap.add_argument("--to", default=None, help="YYYY-MM-DD exclusive (default: year end)")
    ap.add_argument("--tfs", default="1,3,5,15")
    ap.add_argument("--out-dir", default="cpp_core/tools")
    ap.add_argument("--tag", default=None)
    ap.add_argument("--clean", action="store_true", help="use *_clean.parquet")
    ap.add_argument("--gap-min", type=int, default=2, help="report weekday gaps >= N minutes")
    args = ap.parse_args()

    tag = args.tag or args.year
    tfs = [int(x) for x in args.tfs.split(",")]
    src = f"data/processed/ticks_{args.sym}_{args.year}{'_clean' if args.clean else ''}.parquet"
    lo = epoch_ms(args.frm) if args.frm else epoch_ms(f"{args.year}-01-01")
    hi = epoch_ms(args.to) if args.to else epoch_ms(f"{int(args.year)+1}-01-01")

    con = duckdb.connect()
    # Normalize source: Parquet exposes `ts` (TIMESTAMP); window CSVs expose `ts_ms`. Both have `bid`.
    if src.endswith(".parquet"):
        norm = f"(select epoch_ms(ts) as ts_ms, bid from '{src}')"
    else:
        norm = f"(select ts_ms, bid from read_csv_auto('{src}'))"
    # M1 bid bars (the foundation). Integer-division bucketing (NOT '/', which is float in DuckDB).
    con.sql(f"""
        create temp table m1 as
        select (ts_ms // 60000) * 60000 as ts_ms,
               arg_min(bid, ts_ms) as open,
               max(bid)            as high,
               min(bid)            as low,
               arg_max(bid, ts_ms) as close,
               count(*)            as tick_count
        from {norm}
        where ts_ms >= {lo} and ts_ms < {hi}
        group by 1 order by 1
    """)
    n_m1 = con.sql("select count(*) from m1").fetchone()[0]
    print(f"[build_bars] {args.sym} {tag}: {n_m1} M1 bars  src={src}")

    for tf in tfs:
        out = f"{args.out_dir}/bars_{args.sym}_{tag}_m{tf}.csv"
        if tf == 1:
            con.sql(f"copy (select ts_ms,open,high,low,close,tick_count from m1 order by ts_ms) "
                    f"to '{out}' (header, delimiter ',')")
        else:
            w = tf * 60000
            # Aggregate M1 -> TF (MT5-faithful). open = first M1 open, close = last M1 close in bucket.
            con.sql(f"""
                copy (
                  with g as (
                    select (ts_ms // {w}) * {w} as bts, ts_ms, open, high, low, close, tick_count from m1
                  )
                  select bts as ts_ms,
                         arg_min(open, ts_ms)  as open,
                         max(high)             as high,
                         min(low)              as low,
                         arg_max(close, ts_ms) as close,
                         sum(tick_count)       as tick_count
                  from g group by bts order by bts
                ) to '{out}' (header, delimiter ',')
            """)
        n = con.sql(f"select count(*) from read_csv_auto('{out}')").fetchone()[0]
        print(f"[build_bars]   wrote M{tf}: {n} bars -> {out}")

    # THE authoritative health signal: full UTC weekdays (Mon-Fri) with ZERO M1 bars inside the
    # covered range. These are days the export LACKS that MT5's tester history may well have
    # (proven for XAU 2025-04-28..30). Each one poisons higher-TF ATR for ~ATR_PERIOD*2 bars after.
    perday = con.sql("""
        select (ts_ms // 86400000) as d, count(*) as n from m1 group by 1
    """).fetchall()
    have = {int(d): int(n) for d, n in perday}
    if have:
        d0 = min(have); d1 = max(have)
        missing = []
        for dd in range(d0, d1 + 1):
            day = dt.datetime.utcfromtimestamp(dd * 86400).date()
            if day.weekday() < 5 and have.get(dd, 0) == 0:
                missing.append(day)
        print(f"[build_bars] MISSING weekdays (0 bars, export-vs-MT5 holes): {len(missing)}")
        # collapse consecutive
        runs = []
        for day in missing:
            if runs and (day - runs[-1][1]).days == 1:
                runs[-1] = (runs[-1][0], day)
            else:
                runs.append((day, day))
        for a, b in runs:
            tag2 = "" if a == b else f" .. {b} ({(b - a).days + 1}d)"
            print(f"    {a}{tag2}  <== refetch ticks or exclude window")


if __name__ == "__main__":
    main()
