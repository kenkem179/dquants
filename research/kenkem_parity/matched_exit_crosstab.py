#!/usr/bin/env python3
"""matched_exit_crosstab.py — on the MATCHED trade pairs (engine vs MT5), build the exit-tag
crosstab and dump the disagreements (esp. engine rides to TP where MT5 took an SL-WIN trail).

Reuses diff_kk's loader + greedy matcher. Usage:
  matched_exit_crosstab.py --engine /tmp/e.csv --mt5 .../trades.csv [--lag-min 5]
"""
import argparse, sys, os
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
from diff_kk import load, match  # noqa

def norm(tag):
    t = tag.upper()
    if "SL" in t and "WIN" in t: return "SL-WIN"
    if "SL" in t and ("LOSS" in t or "STOP" in t): return "SL-LOSS"
    if "TP" in t: return "TP"
    return t or "?"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True); ap.add_argument("--mt5", required=True)
    ap.add_argument("--lag-min", type=float, default=5)
    a = ap.parse_args()
    mt5, eng = load(a.mt5), load(a.engine)
    pairs, miss, over = match(mt5, eng, a.lag_min)
    print(f"matched={len(pairs)} missed={len(miss)} overfire={len(over)}")

    ct = Counter()
    rows = []
    for i, j in pairs:
        m, e = mt5[i], eng[j]
        mt, et = norm(m["tag"]), norm(e["tag"])
        ct[(mt, et)] += 1
        rows.append((m, e, mt, et))

    tags = sorted(set([k[0] for k in ct] + [k[1] for k in ct]))
    print("\n=== matched exit-tag crosstab (rows=MT5, cols=engine) ===")
    print("  MT5\\eng  " + "".join(f"{t:>9}" for t in tags) + "   | total")
    for mt in tags:
        line = f"  {mt:>8} "
        tot = 0
        for et in tags:
            n = ct.get((mt, et), 0); tot += n
            line += f"{n:>9}"
        print(line + f"   | {tot}")
    agree = sum(n for (mt, et), n in ct.items() if mt == et)
    print(f"\ntag-agreement: {agree}/{len(pairs)} = {agree/max(1,len(pairs)):.0%}")

    # net on matched
    mnet = sum(m["pnl"] for m, e, mt, et in rows)
    enet = sum(e["pnl"] for m, e, mt, et in rows)
    print(f"matched net: engine {enet:+.1f}  vs  mt5 {mnet:+.1f}")

    print("\n=== ENGINE-TP but MT5-SL-WIN (trail-overshoot suspects) ===")
    for m, e, mt, et in rows:
        if mt == "SL-WIN" and et == "TP":
            print(f"  {m['t']} {m['dir']} entry={m['entry']:.3f} | "
                  f"MT5 exit={m['exit']:.3f} pnl={m['pnl']:+.1f} mfeR={m['mfe'] if 'mfe' in m else '?'} | "
                  f"ENG exit={e['exit']:.3f} pnl={e['pnl']:+.1f}")
    # also dump all SL-WIN MT5 trades and what engine did
    print("\n=== all matched where MT5=SL-WIN ===")
    for m, e, mt, et in rows:
        if mt == "SL-WIN":
            print(f"  {m['t']} {m['dir']} entry={m['entry']:.3f} risk={m['risk']:.3f} | "
                  f"MT5 {m['tag']:>10} exit={m['exit']:.3f} {m['pnl']:+.1f} | "
                  f"ENG {e['tag']:>10} exit={e['exit']:.3f} {e['pnl']:+.1f}")

if __name__ == "__main__":
    main()
