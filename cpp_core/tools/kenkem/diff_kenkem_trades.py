#!/usr/bin/env python3
"""KenKem trade-level parity diff: C++ tick ledger vs the MT5 EA reference.

Both files share the schema emitted by:
  * C++  : cpp_core/tools/kenkem/tick_backtester.cpp  (--out)
  * MT5  : MQL5/Experts/KenKem/Parity/TradeJournal.mqh (InpExportTradeJournal)
    -> entryTimeUTC,dir,kind,entry,riskPrice,exitPrice,realizedUsd,mfeR,maeR,exitTag

Trades are aligned by entryTimeUTC (one position per signal bar). Reports:
  * MATCHED / MISSED (ref-only) / EXTRA (cpp-only) counts  -> entry-selectivity parity
  * for matched trades: max/mean |delta| per numeric col, and dir/exitTag mismatches
The broker-spec-independent cols (dir, entry, riskPrice, exitPrice) prove the geometry;
realizedUsd proves the costed P&L (needs tester commission=0 to match the C++ default).

Usage:
  python diff_kenkem_trades.py <cpp_trades.csv> <mt5_trades.csv>
"""
import sys, csv

NUM = ["entry", "riskPrice", "exitPrice", "realizedUsd", "mfeR"]
STR = ["dir", "kind", "exitTag"]


def load(path):
    out = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            out[row["entryTimeUTC"]] = row
    return out


def main():
    cpp, ref = load(sys.argv[1]), load(sys.argv[2])
    ck, rk = set(cpp), set(ref)
    matched = sorted(ck & rk)
    missed = sorted(rk - ck)   # ref took, cpp didn't
    extra = sorted(ck - rk)    # cpp took, ref didn't

    print(f"cpp={len(cpp)} ref={len(ref)} | matched={len(matched)} "
          f"missed(ref-only)={len(missed)} extra(cpp-only)={len(extra)}")
    if matched:
        rate = 100.0 * len(matched) / max(len(ref), 1)
        print(f"entry parity: {len(matched)}/{len(ref)} ref trades reproduced ({rate:.1f}%)")
        print("\n--- matched-trade deltas (geometry first, $ last) ---")
        for col in NUM:
            mx = mn = 0.0; n = 0; worst = None
            for t in matched:
                try:
                    a, b = float(cpp[t][col]), float(ref[t][col])
                except (ValueError, KeyError):
                    continue
                d = abs(a - b); mn += d; n += 1
                if d > mx: mx, worst = d, (t, a, b)
            if n:
                tag = f"  worst@{worst[0]} cpp={worst[1]} ref={worst[2]}" if worst and mx > 0 else ""
                print(f"  {col:12s} max|Δ|={mx:12.4f} mean|Δ|={mn/n:10.4f}{tag}")
        for col in STR:
            mism = [t for t in matched if cpp[t].get(col) != ref[t].get(col)]
            print(f"  {col:12s} " + ("EXACT" if not mism else
                  f"MISMATCH on {len(mism)}, e.g. {mism[0]}: cpp={cpp[mism[0]].get(col)} ref={ref[mism[0]].get(col)}"))

    def show(label, keys, src):
        if not keys: return
        print(f"\n--- {label} (first 15) ---")
        for t in keys[:15]:
            r = src[t]
            print(f"  {t}  {r['dir']} {r['kind']} entry={r['entry']} "
                  f"risk={r['riskPrice']} exit={r['exitTag']} usd={r['realizedUsd']}")

    show("MISSED (ref took, cpp skipped)", missed, ref)
    show("EXTRA (cpp took, ref skipped)", extra, cpp)


if __name__ == "__main__":
    main()
