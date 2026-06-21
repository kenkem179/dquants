#!/usr/bin/env python3
"""Resample an M1 OHLC bar CSV (ts_ms,open,high,low,close,tick_count) to M3 or M5 by flooring
each M1 bar's ts to the TF boundary. M3/M5 OHLC = first-open / max-high / min-low / last-close /
sum tick_count of the M1 bars within the window. This matches tick->TF aggregation exactly when the
M1 bars are themselves faithful tick aggregations. Usage: resample_m1.py <in_m1.csv> <out.csv> <3|5>"""
import csv, sys
inp, out, tf = sys.argv[1], sys.argv[2], int(sys.argv[3])
step = tf * 60_000
cur = None  # (bucket_ts, o,h,l,c, tc)
with open(inp) as f, open(out, "w", newline="") as g:
    r = csv.reader(f); w = csv.writer(g)
    hdr = next(r); w.writerow(hdr)
    for row in r:
        ts = int(row[0]); o=float(row[1]); h=float(row[2]); l=float(row[3]); c=float(row[4])
        tc = int(row[5]) if len(row) > 5 and row[5] != "" else 0
        b = (ts // step) * step
        if cur is None or b != cur[0]:
            if cur is not None:
                w.writerow([cur[0], f"{cur[1]:g}", f"{cur[2]:g}", f"{cur[3]:g}", f"{cur[4]:g}", cur[5]])
            cur = [b, o, h, l, c, tc]
        else:
            cur[2] = max(cur[2], h); cur[3] = min(cur[3], l); cur[4] = c; cur[5] += tc
    if cur is not None:
        w.writerow([cur[0], f"{cur[1]:g}", f"{cur[2]:g}", f"{cur[3]:g}", f"{cur[4]:g}", cur[5]])
print(f"wrote {out}")
