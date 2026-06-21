#!/usr/bin/env python3
"""Does Kaufman Efficiency Ratio (ER) separate E1 winners from losers?

Fast pre-build validation (2026-06-22). If losing E1 trades sit at systematically
LOWER ER (chop) than winners, an ER gate is worth wiring into the engine — both as a
chop-reject AND (loosening the laggy ADX gate) as an earlier trigger. No-lookahead:
ER is computed over closes ENDING ON THE BAR BEFORE the entry bar (strictly past data).

ER(N) = |close[t] - close[t-N]| / sum_{i}|close[t-i+1]-close[t-i]|   in [0,1]
0 = pure chop, 1 = perfectly clean directional move.

Usage: python3 er_discrim.py [trades_csv] [bars_csv]
"""
import csv, sys, datetime as dt

TRADES = sys.argv[1] if len(sys.argv) > 1 else "research/optimization/e1_decomp/trades_e1only_xau.csv"
BARS   = sys.argv[2] if len(sys.argv) > 2 else "cpp_core/tools/bars_xauusd_2024_2026_m1.csv"
NS = [5, 10, 20, 30]


def parse_dt(s):
    return dt.datetime.strptime(s.strip(), "%Y.%m.%d %H:%M").replace(tzinfo=dt.timezone.utc)


# load bars
bar_ts, close = [], []
with open(BARS) as f:
    for r in csv.DictReader(f):
        bar_ts.append(int(r["ts_ms"])); close.append(float(r["close"]))
idx = {t: i for i, t in enumerate(bar_ts)}


def er(end_i, N):
    # ER over closes[end_i-N .. end_i]  (end_i is last CLOSED bar before entry)
    if end_i - N < 0:
        return None
    net = abs(close[end_i] - close[end_i - N])
    vol = sum(abs(close[end_i - k] - close[end_i - k - 1]) for k in range(N))
    return (net / vol) if vol > 0 else None


# load trades, compute ER at entry-1
rows = []
with open(TRADES) as f:
    for r in csv.DictReader(f):
        d = parse_dt(r["entryTimeUTC"]); ms = int(d.timestamp() * 1000)
        ei = idx.get(ms - ms % 60000)
        if ei is None:
            continue
        rec = dict(d=d, pnl=float(r["realizedUsd"]), dir=r["dir"], win=float(r["realizedUsd"]) > 0)
        for N in NS:
            rec[f"er{N}"] = er(ei - 1, N)   # ei-1 = strictly past
        if d >= dt.datetime(2025, 3, 2, tzinfo=dt.timezone.utc):
            rows.append(rec)

W = [r for r in rows if r["win"]]
L = [r for r in rows if not r["win"]]
print(f"E1 trades: {len(rows)}  (win {len(W)}, loss {len(L)})\n")


def avg(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else float("nan")


def med(xs):
    xs = sorted(x for x in xs if x is not None)
    return xs[len(xs)//2] if xs else float("nan")


print(f"{'ER(N)':<7} {'win_mean':>9} {'loss_mean':>9} {'win_med':>8} {'loss_med':>8}  separation")
for N in NS:
    wm, lm = avg([r[f'er{N}'] for r in W]), avg([r[f'er{N}'] for r in L])
    print(f"er{N:<5} {wm:>9.3f} {lm:>9.3f} {med([r[f'er{N}'] for r in W]):>8.3f} "
          f"{med([r[f'er{N}'] for r in L]):>8.3f}  {'WIN>LOSS' if wm>lm else 'no-sep':>9} "
          f"(Δ={wm-lm:+.3f})")

# threshold sweep on the best-separating N: what does gating ER>=thr do?
print("\n--- ER gate simulation (reject trades with ER < threshold) ---")
def metrics(sub):
    if not sub: return (0,0.0,0.0,0.0)
    pnls=[r['pnl'] for r in sub]; net=sum(pnls)
    gp=sum(p for p in pnls if p>0); gl=-sum(p for p in pnls if p<0)
    pf=gp/gl if gl>0 else 9.99
    win=100*sum(1 for p in pnls if p>0)/len(pnls)
    return (len(sub),net,pf,win)
for N in NS:
    print(f"\n  N={N}:")
    base=metrics(rows); print(f"    no-gate          n={base[0]:>3d} net={base[1]:>8.1f} PF={base[2]:.2f} win={base[3]:.0f}%")
    for thr in [0.10,0.15,0.20,0.25,0.30,0.40]:
        kept=[r for r in rows if r[f'er{N}'] is not None and r[f'er{N}']>=thr]
        cut =[r for r in rows if r[f'er{N}'] is not None and r[f'er{N}']<thr]
        k=metrics(kept); c=metrics(cut)
        print(f"    ER>= {thr:.2f}       keep n={k[0]:>3d} net={k[1]:>8.1f} PF={k[2]:.2f} win={k[3]:.0f}%"
              f"  | cut n={c[0]:>3d} net={c[1]:>8.1f}")
