#!/usr/bin/env python3
"""Parquet -> tick CSV bridge for the C++ backtester (Layer-3 tick replay).

The C++ engine is dependency-free, so DuckDB does the 12GB-scale Parquet read here and
emits a compact, streamable tick CSV (the engine reads it line-by-line, flat memory).

Output columns (full precision; the engine does any rounding): ts_ms,bid,ask
  - ts_ms  epoch milliseconds UTC (== MT5 server time, InpBrokerGMTOffset=0)
  - bid/ask raw quote (mid/spread/flags dropped; the engine derives spread = ask - bid)

Ticks are emitted in strict ts order over [START, END) so the TickEngine sees a monotone
stream. Restrict to the MT5 test period (warmup bars are supplied separately via the bars
CSV) so the C++ trade stream lines up with the tester reference window.

Usage:
  python cpp_core/tools/export_ticks.py <year> <clean|raw> <START> <END> <out_csv> [symbol]
Example (the 1-year MT5 run's test period, BTCUSD M3 2025-08-11..11-30):
  python cpp_core/tools/export_ticks.py 2025 clean 2025-08-11 2025-12-01 \\
         cpp_core/tools/ticks_btcusd_2025_window.csv btcusd
"""
import sys
import duckdb

YEAR = sys.argv[1]
SRC = sys.argv[2]
START = sys.argv[3]
END = sys.argv[4]
OUT = sys.argv[5]
SYM = sys.argv[6] if len(sys.argv) > 6 else "btcusd"
TICKS = f"data/processed/ticks_{SYM}_{YEAR}{'_clean' if SRC == 'clean' else ''}.parquet"


def main():
    con = duckdb.connect()
    con.sql(f"""
        copy (
          select epoch_ms(ts) as ts_ms, bid, ask
          from '{TICKS}'
          where ts >= timestamp '{START}' and ts < timestamp '{END}'
          order by ts
        ) to '{OUT}' (header, delimiter ',')
    """)
    n = con.sql(f"select count(*) from '{OUT}'").fetchone()[0]
    print(f"[export_ticks] {SYM} {START}..{END}: wrote {n} ticks -> {OUT}")


if __name__ == "__main__":
    main()
