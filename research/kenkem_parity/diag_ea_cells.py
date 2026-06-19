#!/usr/bin/env python3
"""diag_ea_cells.py — for the matched pairs, bucket the EA->SL-LOSS and TP->SL-WIN crosstab cells
by MT5 maeR/mfeR to identify WHICH adaptive exit MT5 used (panic needs maeR>=~0.6; sideway any).
"""
import argparse, sys, os, csv
from datetime import datetime
sys.path.insert(0, os.path.dirname(__file__))
from diff_kk import load, match, FMT
from matched_exit_crosstab import norm

def load_excursions(path):
    d = {}
    with open(path) as f:
        for r in csv.DictReader(f):
            if not r.get("entryTimeUTC"): continue
            k = (datetime.strptime(r["entryTimeUTC"].strip(), FMT), r["dir"].strip())
            d[k] = (float(r["mfeR"]), float(r["maeR"]))
    return d

def hist(vals, edges):
    out = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        out.append(sum(1 for v in vals if lo <= v < hi))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True); ap.add_argument("--mt5", required=True)
    ap.add_argument("--lag-min", type=float, default=5)
    a = ap.parse_args()
    mt5, eng = load(a.mt5), load(a.engine)
    exc = load_excursions(a.mt5)
    pairs, _, _ = match(mt5, eng, a.lag_min)
    edges = [0, .3, .5, .6, .7, .8, .9, 1.01, 99]
    cells = {("EA","SL-LOSS"): [], ("EA","EA"): [], ("EA","SL-WIN"): [], ("TP","SL-WIN"): [], ("TP","TP"): []}
    for i, j in pairs:
        m, e = mt5[i], eng[j]
        key = (norm(m["tag"]), norm(e["tag"]))
        if key in cells:
            mfe, mae = exc.get((m["t"], m["dir"]), (None, None))
            cells[key].append((mfe, mae, m["pnl"], e["pnl"]))
    print(f"matched={len(pairs)}  edges(maeR)={edges}")
    for key, lst in cells.items():
        if not lst: continue
        maes = [x[1] for x in lst if x[1] is not None]
        mfes = [x[0] for x in lst if x[0] is not None]
        dpnl = sum(x[3]-x[2] for x in lst)
        print(f"\n{key[0]}->{key[1]}  n={len(lst)}  Σ(eng-mt5)pnl={dpnl:+.0f}")
        print(f"  MT5 maeR hist {hist(maes,edges)}  median={sorted(maes)[len(maes)//2]:.2f}")
        print(f"  MT5 mfeR median={sorted(mfes)[len(mfes)//2]:.2f}  >=0.8R: {sum(1 for v in mfes if v>=0.8)}/{len(mfes)}")

if __name__ == "__main__":
    main()
