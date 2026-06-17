#!/usr/bin/env python3
"""diff_kk.py — KenKem trade-level parity diff (engine cpp_trades.csv vs MT5 TradeJournal trades.csv).

Both files share the KenKem TradeJournal schema:
  entryTimeUTC,dir,kind,entry,riskPrice,exitPrice,realizedUsd,mfeR,maeR,exitTag
  (engine emits exitPrice/maeR best-effort; MT5 is ground truth)

Matching: greedy nearest-entry-time within SAME (dir, kind), bounded by --lag-min minutes.
Reports: per-kind counts, matched / MT5-only (MISSED) / engine-only (OVERFIRE),
timing-offset distribution, and price/SL/PnL deltas on matched pairs.

stdlib only.  Usage:
  diff_kk.py --engine cpp_trades.csv --mt5 trades.csv [--lag-min 5] [--kind E1] [--show 40]
"""
import argparse, csv
from datetime import datetime, timedelta

FMT = "%Y.%m.%d %H:%M"

def load(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            if not r.get("entryTimeUTC"): continue
            rows.append({
                "t": datetime.strptime(r["entryTimeUTC"].strip(), FMT),
                "dir": r["dir"].strip(), "kind": r["kind"].strip(),
                "entry": float(r["entry"]), "risk": float(r["riskPrice"]),
                "exit": float(r.get("exitPrice", 0) or 0), "pnl": float(r["realizedUsd"]),
                "tag": r["exitTag"].strip(),
            })
    return rows

def match(mt5, eng, lag):
    cand = []
    for i, m in enumerate(mt5):
        for j, e in enumerate(eng):
            if m["dir"] != e["dir"] or m["kind"] != e["kind"]: continue
            dt = abs((e["t"] - m["t"]).total_seconds())
            if dt <= lag*60: cand.append((dt, i, j))
    cand.sort()
    um, ue = set(range(len(mt5))), set(range(len(eng)))
    pairs = []
    for dt, i, j in cand:
        if i in um and j in ue:
            um.discard(i); ue.discard(j); pairs.append((i, j))
    return pairs, sorted(um), sorted(ue)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True); ap.add_argument("--mt5", required=True)
    ap.add_argument("--lag-min", type=float, default=5); ap.add_argument("--kind", default=None)
    ap.add_argument("--show", type=int, default=0)
    a = ap.parse_args()
    mt5, eng = load(a.mt5), load(a.engine)
    if a.kind:
        mt5 = [r for r in mt5 if r["kind"] == a.kind]; eng = [r for r in eng if r["kind"] == a.kind]
    # window-filter engine to MT5 entry span
    if mt5:
        lo, hi = mt5[0]["t"], mt5[-1]["t"]
        eng = [r for r in eng if lo - timedelta(minutes=a.lag_min) <= r["t"] <= hi + timedelta(minutes=a.lag_min)]
    pairs, miss, over = match(mt5, eng, a.lag_min)

    print(f"\n=== KenKem parity diff  (lag {a.lag_min}min{', kind '+a.kind if a.kind else ''}) ===")
    print(f"MT5 trades:    {len(mt5)}")
    print(f"engine trades: {len(eng)}")
    print(f"matched:       {len(pairs)}")
    print(f"MISSED (MT5-only, engine failed to fire): {len(miss)}")
    print(f"OVERFIRE (engine-only, no MT5 trade):     {len(over)}")
    # per-kind
    kinds = sorted(set([r['kind'] for r in mt5] + [r['kind'] for r in eng]))
    print("\n  kind |  MT5 | eng | matched | missed | overfire")
    for k in kinds:
        m = [r for r in mt5 if r['kind']==k]; e=[r for r in eng if r['kind']==k]
        pm = [p for p in pairs if mt5[p[0]]['kind']==k]
        mi = [i for i in miss if mt5[i]['kind']==k]; ov=[j for j in over if eng[j]['kind']==k]
        print(f"  {k:>4} | {len(m):>4} | {len(e):>3} | {len(pm):>7} | {len(mi):>6} | {len(ov):>8}")
    if pairs:
        offs = sorted((eng[j]["t"]-mt5[i]["t"]).total_seconds()/60 for i,j in pairs)
        de = [abs(eng[j]["entry"]-mt5[i]["entry"]) for i,j in pairs]
        dr = [abs(eng[j]["risk"]-mt5[i]["risk"]) for i,j in pairs]
        dp = [abs(eng[j]["pnl"]-mt5[i]["pnl"]) for i,j in pairs]
        n=len(pairs)
        med=lambda L: sorted(L)[len(L)//2]
        print(f"\n  matched timing offset min (eng-mt5): median {med(offs):+.1f}  range [{offs[0]:+.0f},{offs[-1]:+.0f}]")
        print(f"  matched |Δentry| median {med(de):.3f} max {max(de):.3f}")
        print(f"  matched |Δrisk(SL)| median {med(dr):.3f} max {max(dr):.3f}")
        print(f"  matched |ΔpnlUSD| median {med(dp):.2f} max {max(dp):.2f}")
        exact = sum(1 for x in offs if abs(x)<1e-9)
        print(f"  exact-minute matches: {exact}/{n}")
    if a.show:
        print(f"\n  --- first {a.show} MISSED (MT5 trades engine didn't make) ---")
        for i in miss[:a.show]:
            r=mt5[i]; print(f"   MISS {r['t']} {r['dir']} {r['kind']} entry={r['entry']:.3f} pnl={r['pnl']:+.1f} {r['tag']}")
        print(f"\n  --- first {a.show} OVERFIRE (engine trades with no MT5 match) ---")
        for j in over[:a.show]:
            r=eng[j]; print(f"   OVER {r['t']} {r['dir']} {r['kind']} entry={r['entry']:.3f} pnl={r['pnl']:+.1f} {r['tag']}")

if __name__ == "__main__":
    main()
