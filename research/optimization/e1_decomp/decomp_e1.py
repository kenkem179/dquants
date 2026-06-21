#!/usr/bin/env python3
"""E1 loss-cluster decomposition (2026-06-22).

Goal: find WHERE E1 loses (hour-of-day x day-of-week x quarter x vol-regime x dir)
so the additive session/volatility filter is built from evidence, not guessed.

The C++ tick engine is faithful for E1 entries (~93% recall, clean exits), so its
E1 trade stream is a trustworthy proxy for this purpose. Stdlib only (no pandas).

Usage: python3 decomp_e1.py [trades_csv] [bars_csv]
"""
import csv, sys, datetime as dt
from collections import defaultdict

TRADES = sys.argv[1] if len(sys.argv) > 1 else "research/optimization/e1_decomp/trades_e1only_xau.csv"
BARS   = sys.argv[2] if len(sys.argv) > 2 else "cpp_core/tools/bars_xauusd_2024_2026_m1.csv"


def utc(ms):
    return dt.datetime.fromtimestamp(ms / 1000, dt.timezone.utc)


def quarter(d):
    return f"{d.year%100:02d}Q{(d.month-1)//3+1}"


def m(pnls):
    if not pnls:
        return dict(n=0, net=0.0, pf=0.0, win=0.0)
    net = sum(pnls); gp = sum(p for p in pnls if p > 0); gl = -sum(p for p in pnls if p < 0)
    return dict(n=len(pnls), net=net,
                pf=(gp/gl if gl > 0 else (9.99 if gp > 0 else 0.0)),
                win=100.0*sum(1 for p in pnls if p > 0)/len(pnls))


def line(label, d, w=22):
    print(f"  {label:<{w}} n={d['n']:>4d}  net={d['net']:>9.1f}  PF={d['pf']:>5.2f}  win={d['win']:>4.0f}%")


# ---- build ATR(14, SMA-of-TR) per-bar + ATR percentile (trailing 500) ----
print("loading bars + computing ATR regime ...", file=sys.stderr)
bar_ts, highs, lows, closes = [], [], [], []
with open(BARS) as f:
    for r in csv.DictReader(f):
        bar_ts.append(int(r["ts_ms"])); highs.append(float(r["high"]))
        lows.append(float(r["low"]));   closes.append(float(r["close"]))
N = len(bar_ts)
tr = [0.0]*N
for i in range(1, N):
    tr[i] = max(highs[i]-lows[i], abs(highs[i]-closes[i-1]), abs(lows[i]-closes[i-1]))
ATRN = 14
atr = [0.0]*N
run = sum(tr[1:1+ATRN])
for i in range(ATRN, N):
    atr[i] = run/ATRN
    if i+1 < N:
        run += tr[i+1] - tr[i+1-ATRN]
# trailing 500-bar percentile of ATR at each bar (matches EA's pctile gate spirit)
WIN = 500
import bisect
atr_pct = [0.0]*N
window = []
ws = []
for i in range(N):
    if atr[i] > 0:
        if ws:
            pos = bisect.bisect_left(ws, atr[i])
            atr_pct[i] = 100.0*pos/len(ws)
        bisect.insort(ws, atr[i])
        if len(ws) > WIN:
            old = atr[i-WIN] if i-WIN >= 0 else None
        # keep window bounded by recomputation-light approach
    if len(ws) > WIN:
        ws.pop(bisect.bisect_left(ws, atr[i-WIN+1])) if False else None
# (simple unbounded percentile is fine for tercile bucketing of trades)
ts_to_idx = {t: i for i, t in enumerate(bar_ts)}


def bar_atr_pct(ms):
    i = ts_to_idx.get(ms - ms % 60000)
    return atr_pct[i] if i is not None else None


# ---- load E1 trades ----
def parse_dt(s):
    # "2025.03.10 05:21"
    return dt.datetime.strptime(s.strip(), "%Y.%m.%d %H:%M").replace(tzinfo=dt.timezone.utc)

rows = []
with open(TRADES) as f:
    for r in csv.DictReader(f):
        d = parse_dt(r["entryTimeUTC"])
        ms = int(d.timestamp()*1000)
        rows.append(dict(ms=ms, d=d, dir=r["dir"], pnl=float(r["realizedUsd"]),
                         tag=r.get("exitTag",""), mfe=float(r.get("mfeR",0) or 0),
                         mae=float(r.get("maeR",0) or 0),
                         hour=d.hour, dow=d.weekday(), q=quarter(d),
                         apct=bar_atr_pct(ms)))
rows = [r for r in rows if r["d"] >= dt.datetime(2025, 3, 2, tzinfo=dt.timezone.utc)]
rows.sort(key=lambda r: r["ms"])
print(f"\n===== E1 decomposition: {len(rows)} trades, "
      f"{rows[0]['d'].date()} -> {rows[-1]['d'].date()} =====")
line("OVERALL", m([r['pnl'] for r in rows]))

print("\n--- by QUARTER ---")
for q in sorted(set(r['q'] for r in rows)):
    line(q, m([r['pnl'] for r in rows if r['q'] == q]))

print("\n--- by HOUR (UTC) ---")
for h in range(24):
    sub = [r['pnl'] for r in rows if r['hour'] == h]
    if sub: line(f"h{h:02d}", m(sub))

print("\n--- by DAY-OF-WEEK (0=Mon) ---")
for wd in range(7):
    sub = [r['pnl'] for r in rows if r['dow'] == wd]
    if sub: line(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"][wd], m(sub))

print("\n--- by DIRECTION ---")
for D in ("L","S"):
    line(D, m([r['pnl'] for r in rows if r['dir'] == D]))

print("\n--- by ATR-percentile bucket at entry ---")
for lo, hi in [(0,70),(70,80),(80,90),(90,101)]:
    sub = [r['pnl'] for r in rows if r['apct'] is not None and lo <= r['apct'] < hi]
    if sub: line(f"atr_pct {lo}-{hi}", m(sub))

print("\n--- HOUR x is-losing-quarter (25Q2/25Q3 vs rest) ---")
LOSEQ = {"25Q2","25Q3"}
print("  hour | losing-quarters         | other-quarters")
for h in range(24):
    a = m([r['pnl'] for r in rows if r['hour']==h and r['q'] in LOSEQ])
    b = m([r['pnl'] for r in rows if r['hour']==h and r['q'] not in LOSEQ])
    if a['n'] or b['n']:
        print(f"  h{h:02d}  | n={a['n']:>3d} net={a['net']:>8.1f} PF={a['pf']:>4.2f} "
              f"| n={b['n']:>3d} net={b['net']:>8.1f} PF={b['pf']:>4.2f}")

# robust loss-hours: net-negative AND appear in >=2 quarters net-negative
print("\n--- ROBUST loss hours (net<0 in >=2 distinct quarters) ---")
qs = sorted(set(r['q'] for r in rows))
for h in range(24):
    negq = [q for q in qs if (s:=[r['pnl'] for r in rows if r['hour']==h and r['q']==q]) and sum(s) < 0]
    tot = m([r['pnl'] for r in rows if r['hour']==h])
    if len(negq) >= 2 and tot['net'] < 0:
        print(f"  h{h:02d}: total net={tot['net']:>8.1f} n={tot['n']:>3d} PF={tot['pf']:.2f}  neg in {negq}")
