#!/usr/bin/env python3
"""Build a 2-year engine anchor (M1 bars + tick stream) DIRECTLY from raw MT5 tick CSVs.

Generic over symbol. M3/M5/M15 are NOT emitted — the C++ engine derives every higher TF by
aggregating M1 (MT5-faithful), so M1 bars + the tick stream are all it needs.

Raw format (tab-separated): <DATE> <TIME> <BID> <ASK> <LAST> <VOLUME> <FLAGS>
  DATE=YYYY.MM.DD  TIME=HH:MM:SS.mmm  (MT5 server time @ GMT0 == UTC)

Usage:
  build_anchor_2yr.py --sym btcusd --raw-glob 'data/btcusd/BTCUSD_ticks_mt5_*.csv' \
      --from 2024-01-01 --to 2026-06-01 --out-dir cpp_core/tools
Outputs:  <out-dir>/bars_<sym>_<tag>_m1.csv , <out-dir>/ticks_<sym>_<tag>.csv  (tag default 2024_2026)
"""
import duckdb, datetime as dt, os, glob, argparse

ap = argparse.ArgumentParser()
ap.add_argument("--sym", required=True)
ap.add_argument("--raw-glob", required=True, help="glob for raw tick CSVs (tab-sep MT5 export)")
ap.add_argument("--from", dest="frm", default="2024-01-01")
ap.add_argument("--to", default="2026-06-01")
ap.add_argument("--out-dir", default="cpp_core/tools")
ap.add_argument("--tag", default="2024_2026")
args = ap.parse_args()

files = sorted(glob.glob(args.raw_glob))
assert files, f"no files match {args.raw_glob}"
print(f"[anchor] {args.sym}: {len(files)} raw files: {[os.path.basename(f) for f in files]}")
os.makedirs(args.out_dir, exist_ok=True)
e = dt.datetime(1970, 1, 1)
lo_ms = int((dt.datetime.strptime(args.frm, "%Y-%m-%d") - e).total_seconds() * 1000)
hi_ms = int((dt.datetime.strptime(args.to, "%Y-%m-%d") - e).total_seconds() * 1000)

con = duckdb.connect(); con.sql("PRAGMA threads=8")
flist = ",".join(f"'{f}'" for f in files)
con.sql(f"""
  create or replace view ticks as
  select epoch_ms(strptime("<DATE>" || ' ' || "<TIME>", '%Y.%m.%d %H:%M:%S.%g')) as ts_ms,
         "<BID>"::double as bid, "<ASK>"::double as ask
  from read_csv([{flist}], delim='\t', header=true, ignore_errors=true,
                columns={{'<DATE>':'VARCHAR','<TIME>':'VARCHAR','<BID>':'DOUBLE','<ASK>':'DOUBLE',
                          '<LAST>':'DOUBLE','<VOLUME>':'BIGINT','<FLAGS>':'BIGINT'}})
""")
tpath = f"{args.out_dir}/ticks_{args.sym}_{args.tag}.csv"
con.sql(f"""copy (select ts_ms,bid,ask from ticks
                  where ts_ms>={lo_ms} and ts_ms<{hi_ms} and bid>0 and ask>0
                  order by ts_ms) to '{tpath}' (header, delimiter ',')""")
nt = con.sql(f"select count(*) from read_csv_auto('{tpath}')").fetchone()[0]
print(f"[anchor] ticks: {nt} -> {tpath}")

con.sql(f"""create temp table m1 as
  select (ts_ms//60000)*60000 as ts_ms, arg_min(bid,ts_ms) as open, max(bid) as high,
         min(bid) as low, arg_max(bid,ts_ms) as close, count(*) as tick_count
  from ticks where ts_ms>={lo_ms} and ts_ms<{hi_ms} and bid>0 group by 1 order by 1""")
bpath = f"{args.out_dir}/bars_{args.sym}_{args.tag}_m1.csv"
con.sql(f"copy (select ts_ms,open,high,low,close,tick_count from m1 order by ts_ms) to '{bpath}' (header, delimiter ',')")
nb = con.sql("select count(*) from m1").fetchone()[0]
print(f"[anchor] M1 bars: {nb} -> {bpath}")

perday = con.sql("select (ts_ms//86400000) as d, count(*) n from m1 group by 1").fetchall()
have = {int(d): int(n) for d, n in perday}
miss = [dt.datetime.utcfromtimestamp(dd*86400).date() for dd in range(min(have), max(have)+1)
        if dt.datetime.utcfromtimestamp(dd*86400).date().weekday() < 5 and have.get(dd,0)==0]
print(f"[anchor] MISSING weekdays (0 bars): {len(miss)}")
runs=[]
for day in miss:
    if runs and (day-runs[-1][1]).days==1: runs[-1]=(runs[-1][0],day)
    else: runs.append((day,day))
for a,b in runs: print(f"    {a}{'' if a==b else f' .. {b} ({(b-a).days+1}d)'}")
print("[anchor] DONE")
