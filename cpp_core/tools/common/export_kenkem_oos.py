#!/usr/bin/env python3
"""Regenerate the gitignored KenKem 2026-OOS tick-engine inputs from the Parquet tick store.

The C++ tick engine needs two kinds of CSV:
  * M1 BID bars  (--bars-m1)  — warms the indicators; must cover history BEFORE the trade-start.
  * a bid/ask tick stream (--ticks) — drives real path-dependent management over the trade window.

The tick engine gates trading by --from-ms (2026-01-01 = 1767225600000) and warms indicators from the
M1 bars, so the bars file is built as 2025+2026 concat (2025 = warmup, 2026 = trade window) and the
tick file is the 2026 stream only. This mirrors the SYSTEMIC.md 2026-OOS re-baseline exactly.

Outputs (under cpp_core/tools/):
  bars_btcusd_2025_m1.csv, bars_btcusd_2026_m1.csv, bars_btcusd_2025_2026_m1.csv  (BTC warmup = concat)
  bars_xauusd_2025_m1.csv, bars_xauusd_2026_m1.csv, bars_xauusd_2025h2_2026_m1.csv (XAU warmup = concat)
  ticks_btcusd_2026_window.csv, ticks_xauusd_2026_window.csv

M1 bars are BID OHLC + per-bar tick_count, identical construction to export_bars.py but 1-minute buckets.
Run with the kenkem env:  ~/miniforge3/envs/kenkem/bin/python cpp_core/tools/common/export_kenkem_oos.py
Idempotent: pass --force to rebuild existing CSVs.
"""
import os
import sys
import duckdb

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "cpp_core", "tools")
FORCE = "--force" in sys.argv


def parquet(sym, year):
    return os.path.join(ROOT, "data", "processed", f"ticks_{sym}_{year}.parquet")


def export_m1_bars(sym, year, out):
    if os.path.exists(out) and not FORCE:
        print(f"  skip {os.path.basename(out)} (exists)")
        return
    con = duckdb.connect()
    con.sql(f"""
        copy (
          with b as (
            select
              time_bucket(interval '1 minute', ts) as bts,
              epoch_ms(time_bucket(interval '1 minute', ts)) as ts_ms,
              arg_min(bid, ts) as open,
              max(bid)         as high,
              min(bid)         as low,
              arg_max(bid, ts) as close,
              count(*)         as tick_count
            from '{parquet(sym, year)}'
            group by 1
          )
          select ts_ms, open, high, low, close, tick_count from b order by bts
        ) to '{out}' (header, delimiter ',')
    """)
    n = con.sql(f"select count(*) from read_csv_auto('{out}')").fetchone()[0]
    print(f"  wrote {os.path.basename(out)}: {n:,} M1 bars")


def export_ticks(sym, year, out):
    if os.path.exists(out) and not FORCE:
        print(f"  skip {os.path.basename(out)} (exists)")
        return
    con = duckdb.connect()
    con.sql(f"""
        copy (
          select epoch_ms(ts) as ts_ms, bid, ask from '{parquet(sym, year)}' order by ts
        ) to '{out}' (header, delimiter ',')
    """)
    n = con.sql(f"select count(*) from read_csv_auto('{out}')").fetchone()[0]
    print(f"  wrote {os.path.basename(out)}: {n:,} ticks")


def concat(parts, out):
    if os.path.exists(out) and not FORCE:
        print(f"  skip {os.path.basename(out)} (exists)")
        return
    with open(out, "w") as fo:
        for i, p in enumerate(parts):
            with open(p) as fi:
                for j, line in enumerate(fi):
                    if j == 0 and i > 0:   # keep header from first file only
                        continue
                    fo.write(line)
    n = sum(1 for _ in open(out)) - 1
    print(f"  wrote {os.path.basename(out)}: {n:,} rows (concat)")


def main():
    os.makedirs(OUT, exist_ok=True)
    print("BTCUSD")
    b25 = os.path.join(OUT, "bars_btcusd_2025_m1.csv")
    b26 = os.path.join(OUT, "bars_btcusd_2026_m1.csv")
    export_m1_bars("btcusd", "2025", b25)
    export_m1_bars("btcusd", "2026", b26)
    concat([b25, b26], os.path.join(OUT, "bars_btcusd_2025_2026_m1.csv"))
    export_ticks("btcusd", "2026", os.path.join(OUT, "ticks_btcusd_2026_window.csv"))

    print("XAUUSD")
    x25 = os.path.join(OUT, "bars_xauusd_2025_m1.csv")
    x26 = os.path.join(OUT, "bars_xauusd_2026_m1.csv")
    export_m1_bars("xauusd", "2025", x25)
    export_m1_bars("xauusd", "2026", x26)
    concat([x25, x26], os.path.join(OUT, "bars_xauusd_2025h2_2026_m1.csv"))
    export_ticks("xauusd", "2026", os.path.join(OUT, "ticks_xauusd_2026_window.csv"))
    print("done.")


if __name__ == "__main__":
    main()
