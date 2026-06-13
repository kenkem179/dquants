#!/usr/bin/env python3
"""Level-2 trade-parity diff: C++ backtester trades_*.csv vs the MT5 tester reference.

Aligns trades by entryTimeUTC (one trade per signal bar) and reports:
  * MATCHED / MISSED (ref-only) / EXTRA (cpp-only) counts
  * for matched trades, max/mean |delta| per numeric column + dir/exitTag mismatches
Broker-spec-independent columns (dir, entry, riskPrice, mfeR, maeR, exitTag) are the
first-line check; realizedUsd ($) validates the broker specs on top.

Usage:
  python cpp_core/tools/diff_trades.py <cpp_trades.csv> <ref_trades.csv>
"""
import sys
import csv

NUM = ["entry", "riskPrice", "mfeR", "maeR", "realizedUsd",
       "brkDistAtr", "bodyPct", "adx", "diSpread", "runwayAtr", "nodeNet", "spreadPips", "spreadAtr"]
STR = ["dir", "rev", "regimeTrend", "session", "entryReason", "exitTag"]


def load(path):
    out = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            out[row["entryTimeUTC"]] = row
    return out


def main():
    cpp = load(sys.argv[1])
    ref = load(sys.argv[2])
    ck, rk = set(cpp), set(ref)
    matched = sorted(ck & rk)
    missed = sorted(rk - ck)    # ref took, we didn't
    extra = sorted(ck - rk)     # we took, ref didn't

    print(f"cpp={len(cpp)} ref={len(ref)} | matched={len(matched)} "
          f"missed(ref-only)={len(missed)} extra(cpp-only)={len(extra)}")

    if matched:
        print("\n--- matched-trade deltas (broker-spec-independent first) ---")
        for col in NUM:
            mx = mn = 0.0
            n = 0
            worst = None
            for t in matched:
                try:
                    a, b = float(cpp[t][col]), float(ref[t][col])
                except (ValueError, KeyError):
                    continue
                d = abs(a - b)
                mn += d
                n += 1
                if d > mx:
                    mx = d
                    worst = (t, a, b)
            if n:
                tag = f"  worst@{worst[0]} cpp={worst[1]} ref={worst[2]}" if worst and mx > 0 else ""
                print(f"  {col:12s} max|Δ|={mx:12.4f} mean|Δ|={mn/n:10.4f}{tag}")
        for col in STR:
            mism = [t for t in matched if cpp[t].get(col) != ref[t].get(col)]
            if mism:
                print(f"  {col:12s} MISMATCH on {len(mism)} rows, e.g. {mism[0]}: "
                      f"cpp={cpp[mism[0]].get(col)} ref={ref[mism[0]].get(col)}")
            else:
                print(f"  {col:12s} EXACT")

    def show(label, keys, src):
        if not keys:
            return
        print(f"\n--- {label} (first 15) ---")
        for t in keys[:15]:
            r = src[t]
            print(f"  {t}  {r['dir']} {r['entryReason']} entry={r['entry']} "
                  f"risk={r['riskPrice']} exit={r['exitTag']} usd={r['realizedUsd']}")

    show("MISSED (ref took, cpp skipped)", missed, ref)
    show("EXTRA (cpp took, ref skipped)", extra, cpp)


if __name__ == "__main__":
    main()
