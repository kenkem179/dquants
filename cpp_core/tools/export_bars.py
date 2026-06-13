#!/usr/bin/env python3
"""Parquet -> bid M3 bars CSV bridge for the C++ parity driver.

The C++ engine is dependency-free (no Parquet reader), so DuckDB (the right tool for
the 12GB tick store) does the Parquet read here and emits a compact, deterministic
bars CSV that the C++ driver consumes. This mirrors EXACTLY the bid M3 bar
construction in cpp_core/tools/validate_parity_py.py (which matched the MT5 tester).

Output columns (full precision, no rounding -- the C++ side does the MT5 3-decimal
rounding at emit time): ts_ms,open,high,low,close,tick_count
  - ts_ms      epoch milliseconds UTC (== MT5 server time, InpBrokerGMTOffset=0)
  - o/h/l/c    BID OHLC of the M3 bar
  - tick_count per-bar tick count (== MT5 tick_volume, the Stage-A VP weight)

Usage:
  python cpp_core/tools/export_bars.py [year] [clean|raw] [end_date] [out_csv] [symbol]
Defaults: year 2026, clean ticks, end < 2026-04-10, out = cpp_core/tools/bars_<sym>_<year>_m3.csv
Example (the 1-year MT5 run spans 2025-08..11):
  python cpp_core/tools/export_bars.py 2025 clean 2025-12-01 cpp_core/tools/bars_btcusd_2025_m3.csv
"""
import sys
import duckdb

YEAR = sys.argv[1] if len(sys.argv) > 1 else "2026"
SRC = sys.argv[2] if len(sys.argv) > 2 else "clean"
END = sys.argv[3] if len(sys.argv) > 3 else "2026-04-10"
SYM = sys.argv[5] if len(sys.argv) > 5 else "btcusd"
OUT = sys.argv[4] if len(sys.argv) > 4 else f"cpp_core/tools/bars_{SYM}_{YEAR}_m3.csv"
TICKS = f"data/processed/ticks_{SYM}_{YEAR}{'_clean' if SRC == 'clean' else ''}.parquet"


def main():
    con = duckdb.connect()
    con.sql(f"""
        copy (
          with b as (
            select
              time_bucket(interval '3 minutes', ts) as bts,
              epoch_ms(time_bucket(interval '3 minutes', ts)) as ts_ms,
              arg_min(bid, ts) as open,
              max(bid)         as high,
              min(bid)         as low,
              arg_max(bid, ts) as close,
              count(*)         as tick_count
            from '{TICKS}'
            where ts < timestamp '{END}'
            group by 1
          )
          select ts_ms, open, high, low, close, tick_count
          from b order by bts
        ) to '{OUT}' (header, delimiter ',')
    """)
    n = con.sql(f"select count(*) c, min(ts_ms) lo, max(ts_ms) hi from read_csv_auto('{OUT}')").df()
    print(f"[export_bars] wrote {OUT}")
    print(f"[export_bars] {int(n.c[0])} bid M3 bars, ts_ms {int(n.lo[0])}..{int(n.hi[0])}")


if __name__ == "__main__":
    main()
