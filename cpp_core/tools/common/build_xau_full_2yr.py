#!/usr/bin/env python3
"""Build the COMPLETE 2-year XAU anchor (M1 bid bars + tick stream).

The MT5-tab raws (data/xauusd/) have THREE export holes vs the MT5 run (verified against trace.csv.gz):
late-Nov→Dec 2024, all of 2025 H2, and 2026-04-07→05-29. The user supplied each as Exness monthly CSVs
(~/Downloads/Exness_XAUUSD_YYYY_MM.csv). Verified bit-identical to the tab raws on overlap days (same UTC
clock, same Exness feed). We partition: monthly owns a set of half-open intervals (the hole windows), tab
owns everything else — so each ts_ms comes from exactly one source, no dedup needed.

Sources (all UTC):
  - data/xauusd/XAUUSD_ticks_mt5_2024.csv        tab  (2024; good through ~2024-11-18, holed after)
  - data/xauusd/XAUUSD_ticks_mt5_2025_2026.csv   tab  (2025 H1 + 2026 Q1 through 2026-04-06)
  - ~/Downloads/Exness_XAUUSD_{2024_11,2024_12,2025_07..12,2026_04,2026_05}.csv  iso

MONTHLY-OWNED intervals (the holes): [2024-11-19,2025-01-01) ∪ [2025-07-17,2026-01-01) ∪ [2026-04-01,2026-06-01)

Outputs (engine-ready, overwrite the existing files):
  cpp_core/tools/bars_xauusd_2024_2026_m1.csv   ts_ms,open,high,low,close,tick_count  (BID M1 bars)
  cpp_core/tools/ticks_xauusd_2024_2026.csv     ts_ms,bid,ask
"""
import duckdb, datetime as dt, os, glob

OUT = "cpp_core/tools"
HOME = os.path.expanduser("~")
TAB24 = "data/xauusd/XAUUSD_ticks_mt5_2024.csv"
TAB2526 = "data/xauusd/XAUUSD_ticks_mt5_2025_2026.csv"
MONTHLY = sorted(glob.glob(f"{HOME}/Downloads/Exness_XAUUSD_2024_1*.csv") +
                 glob.glob(f"{HOME}/Downloads/Exness_XAUUSD_2025_*.csv") +
                 glob.glob(f"{HOME}/Downloads/Exness_XAUUSD_2026_*.csv"))

LO = "2024-01-01"; HI = "2026-06-01"           # MT5 test window (HI exclusive)
def ms(s): return int((dt.datetime.strptime(s, "%Y-%m-%d") - dt.datetime(1970,1,1)).total_seconds()*1000)
lo_ms, hi_ms = ms(LO), ms(HI)
# Each hole the tab raws lack; monthly files own these, tab owns the complement.
HOLES = [("2024-11-19","2025-01-01"), ("2025-07-17","2026-01-01"), ("2026-04-01","2026-06-01")]
hole_ms = [(ms(a), ms(b)) for a, b in HOLES]
in_holes  = " or ".join(f"(ts_ms>={a} and ts_ms<{b})" for a, b in hole_ms)   # monthly-owned
not_holes = " and ".join(f"not (ts_ms>={a} and ts_ms<{b})" for a, b in hole_ms)  # tab-owned

con = duckdb.connect(); con.sql("PRAGMA threads=8")
TAB_COLS = {'<DATE>':'VARCHAR','<TIME>':'VARCHAR','<BID>':'DOUBLE','<ASK>':'DOUBLE',
            '<LAST>':'DOUBLE','<VOLUME>':'BIGINT','<FLAGS>':'BIGINT'}
EXN_COLS = {'Exness':'VARCHAR','Symbol':'VARCHAR','Timestamp':'VARCHAR','Bid':'DOUBLE','Ask':'DOUBLE'}
def tab(path):
    return (f"select epoch_ms(strptime(\"<DATE>\"||' '||\"<TIME>\",'%Y.%m.%d %H:%M:%S.%g')) ts_ms, "
            f"\"<BID>\"::double bid, \"<ASK>\"::double ask from read_csv(['{path}'], delim='\t', "
            f"header=true, ignore_errors=true, columns={TAB_COLS})")
mon = ",".join(f"'{m}'" for m in MONTHLY)
exn = (f"select epoch_ms(strptime(replace(Timestamp,'Z',''),'%Y-%m-%d %H:%M:%S.%g')) ts_ms, "
       f"Bid::double bid, Ask::double ask from read_csv([{mon}], header=true, ignore_errors=true, columns={EXN_COLS})")

print(f"[full] monthly files: {len(MONTHLY)}")
con.sql(f"""create or replace view ticks as
  select * from ({tab(TAB24)})     where ts_ms>={lo_ms} and ts_ms<{hi_ms} and ({not_holes}) and bid>0 and ask>0
  union all
  select * from ({tab(TAB2526)})   where ts_ms>={lo_ms} and ts_ms<{hi_ms} and ({not_holes}) and bid>0 and ask>0
  union all
  select * from ({exn})            where ts_ms>={lo_ms} and ts_ms<{hi_ms} and ({in_holes}) and bid>0 and ask>0
""")

tpath = f"{OUT}/ticks_xauusd_2024_2026.csv"
con.sql(f"copy (select ts_ms,bid,ask from ticks order by ts_ms) to '{tpath}' (header, delimiter ',')")
nt = con.sql(f"select count(*) from read_csv_auto('{tpath}')").fetchone()[0]
print(f"[full] ticks: {nt} -> {tpath}")

con.sql("""create temp table m1 as
  select (ts_ms//60000)*60000 ts_ms, arg_min(bid,ts_ms) "open", max(bid) "high", min(bid) "low",
         arg_max(bid,ts_ms) "close", count(*) tick_count
  from ticks group by 1 order by 1""")
bpath = f"{OUT}/bars_xauusd_2024_2026_m1.csv"
con.sql(f'copy (select ts_ms,"open","high","low","close",tick_count from m1 order by ts_ms) to \'{bpath}\' (header, delimiter \',\')')
nb = con.sql("select count(*) from m1").fetchone()[0]
print(f"[full] M1 bars: {nb} -> {bpath}")

# Gap report (missing UTC weekdays).
perday = con.sql("select (ts_ms//86400000) d, count(*) n from m1 group by 1").fetchall()
have = {int(d): int(n) for d, n in perday}
d0, d1 = min(have), max(have)
missing = [dt.datetime.utcfromtimestamp(dd*86400).date()
           for dd in range(d0, d1+1)
           if dt.datetime.utcfromtimestamp(dd*86400).date().weekday() < 5 and have.get(dd,0)==0]
print(f"[full] first bar {dt.datetime.utcfromtimestamp(min(have)*86400).date()}, "
      f"last {dt.datetime.utcfromtimestamp(max(have)*86400).date()}")
print(f"[full] MISSING weekdays (0 bars): {len(missing)}")
runs = []
for day in missing:
    if runs and (day - runs[-1][1]).days == 1: runs[-1] = (runs[-1][0], day)
    else: runs.append((day, day))
for a, b in runs:
    print(f"    {a}{'' if a==b else f' .. {b} ({(b-a).days+1}d)'}")
print("[full] DONE")
