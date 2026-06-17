#!/usr/bin/env python3
"""Build the 2-year XAU anchor M1 bars + tick stream DIRECTLY from the NEW raw Exness tick CSVs.

WHY: the data/processed/*.parquet are from an OLD export with whole-day holes. The fresh raw
CSVs at ~/Downloads/Exness XAU MT5 Tick data 2024-2026/ are complete. Build straight from them
so the engine sees exactly what the MT5 2024.01.01->2026.06.01 run saw.

Raw format (tab-separated): <DATE> <TIME> <BID> <ASK> <LAST> <VOLUME> <FLAGS>
  DATE=YYYY.MM.DD  TIME=HH:MM:SS.mmm  (MT5 server time @ GMT0 == UTC, per proven bar-parity)

Outputs (engine-ready):
  bars_xauusd_2024_2026_m1.csv   ts_ms,open,high,low,close,tick_count  (BID M1 bars)
  ticks_xauusd_2024_2026.csv     ts_ms,bid,ask
Also prints the missing-weekday gap report (the data-health signal).
"""
import duckdb, datetime as dt, os

RAW_DIR = "/Users/tokyotechies/Downloads/Exness XAU MT5 Tick data 2024-2026"
FILES = [f"{RAW_DIR}/XAUUSD_ticks_mt5_{y}.csv" for y in (2024, 2025, 2026)]
LO = "2024-01-01"          # MT5 test start
HI = "2026-06-01"          # MT5 test end (exclusive)
OUT = "cpp_core/tools"
os.makedirs(OUT, exist_ok=True)

con = duckdb.connect()
con.sql("PRAGMA threads=8")
# Parse raw -> normalized tick view. strptime handles dotted date + ms.
flist = ",".join(f"'{f}'" for f in FILES)
con.sql(f"""
  create or replace view ticks as
  select epoch_ms(strptime("<DATE>" || ' ' || "<TIME>", '%Y.%m.%d %H:%M:%S.%g')) as ts_ms,
         "<BID>"::double as bid, "<ASK>"::double as ask
  from read_csv([{flist}], delim='\t', header=true, ignore_errors=true,
                columns={{'<DATE>':'VARCHAR','<TIME>':'VARCHAR','<BID>':'DOUBLE','<ASK>':'DOUBLE',
                          '<LAST>':'DOUBLE','<VOLUME>':'BIGINT','<FLAGS>':'BIGINT'}})
""")
lo_ms = int((dt.datetime.strptime(LO, "%Y-%m-%d") - dt.datetime(1970,1,1)).total_seconds()*1000)
hi_ms = int((dt.datetime.strptime(HI, "%Y-%m-%d") - dt.datetime(1970,1,1)).total_seconds()*1000)

# Tick stream (engine replay). Full precision.
tpath = f"{OUT}/ticks_xauusd_2024_2026.csv"
con.sql(f"""copy (select ts_ms,bid,ask from ticks
                  where ts_ms>={lo_ms} and ts_ms<{hi_ms} and bid>0 and ask>0
                  order by ts_ms) to '{tpath}' (header, delimiter ',')""")
nt = con.sql(f"select count(*) from read_csv_auto('{tpath}')").fetchone()[0]
print(f"[anchor] ticks: {nt} -> {tpath}")

# M1 BID bars (MT5-faithful: open=first bid, close=last bid, high/low extremes, tick_count).
con.sql(f"""
  create temp table m1 as
  select (ts_ms//60000)*60000 as ts_ms,
         arg_min(bid,ts_ms) as open, max(bid) as high, min(bid) as low,
         arg_max(bid,ts_ms) as close, count(*) as tick_count
  from ticks where ts_ms>={lo_ms} and ts_ms<{hi_ms} and bid>0
  group by 1 order by 1
""")
bpath = f"{OUT}/bars_xauusd_2024_2026_m1.csv"
con.sql(f"copy (select ts_ms,open,high,low,close,tick_count from m1 order by ts_ms) to '{bpath}' (header, delimiter ',')")
nb = con.sql("select count(*) from m1").fetchone()[0]
print(f"[anchor] M1 bars: {nb} -> {bpath}")

# Gap report (missing UTC weekdays = export-vs-MT5 holes).
perday = con.sql("select (ts_ms//86400000) as d, count(*) n from m1 group by 1").fetchall()
have = {int(d): int(n) for d, n in perday}
d0, d1 = min(have), max(have)
missing = [dt.datetime.utcfromtimestamp(dd*86400).date()
           for dd in range(d0, d1+1)
           if dt.datetime.utcfromtimestamp(dd*86400).date().weekday() < 5 and have.get(dd,0)==0]
print(f"[anchor] MISSING weekdays (0 bars): {len(missing)}")
runs = []
for day in missing:
    if runs and (day - runs[-1][1]).days == 1: runs[-1] = (runs[-1][0], day)
    else: runs.append((day, day))
for a, b in runs:
    print(f"    {a}{'' if a==b else f' .. {b} ({(b-a).days+1}d)'}")
print("[anchor] DONE")
