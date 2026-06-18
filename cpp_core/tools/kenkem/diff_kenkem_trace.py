#!/usr/bin/env python3
"""Field-by-field diff of the per-bar E5 decision trace: C++ trace_dumper vs the EA BarTrace.

Aligns the two 61-column traces on `dt` (UTC minute) and reports:
  1. indicator drift (max/mean |Δ| per indicator column) — is the engine reading the same numbers?
  2. fire disagreements (bars where cpp fire_dir != mt5 fire_dir), split by direction
  3. for each disagreement class, the gate column that differs most often (localizes the bug)
  4. optional --dump <dt> to print both rows side-by-side for one bar

Usage: diff_kenkem_trace.py <cpp_trace.csv> <mt5_trace.csv> [--dump "2025.03.05 05:55"]
"""
import sys, csv

IND_COLS = ["ema0","ema1","ema2","ema3","ema4","adx_m1","adx_m3","adx_m5","adx_m15",
            "diP_m1","diP_m3","diP_m5","diP_m15","diM_m1","diM_m3","diM_m5","diM_m15",
            "adxS","diPS","diMS","atr","rsi","close","atr_pctile"]
# Gate booleans that actually matter for E5 (exclude tcore/ichimoku — known semantic mismatch).
GATE_L = ["L_inage","L_swblk","L_atrlo","L_atrhi","L_price","L_tq","L_tqok","L_adx","L_htf","L_pass","L_fire"]
GATE_S = ["S_inage","S_swblk","S_atrlo","S_atrhi","S_price","S_tq","S_tqok","S_adx","S_htf","S_pass","S_fire"]

def load(path):
    with open(path) as f:
        return {r["dt"]: r for r in csv.DictReader(f)}

def main():
    cpp, mt5 = load(sys.argv[1]), load(sys.argv[2])
    dump = None
    if "--dump" in sys.argv:
        dump = sys.argv[sys.argv.index("--dump")+1]
    common = sorted(set(cpp) & set(mt5))
    print(f"cpp rows={len(cpp)} mt5 rows={len(mt5)} common(dt)={len(common)}")

    if dump:
        c, m = cpp.get(dump), mt5.get(dump)
        if not c or not m: print(f"  {dump} missing (cpp={bool(c)} mt5={bool(m)})"); return
        print(f"\n=== ROW DUMP {dump} ===")
        for k in c:
            if c[k] != m[k]: print(f"  {k:14s} cpp={c[k]:>14s}  mt5={m[k]:>14s}  <-- DIFFERS")
            else:            print(f"  {k:14s} {c[k]:>14s}")
        return

    print("\n--- indicator drift (max|Δ| / mean|Δ|) ---")
    for col in IND_COLS:
        ds = [abs(float(cpp[d][col]) - float(mt5[d][col])) for d in common]
        mx, mn = max(ds), sum(ds)/len(ds)
        worst = max(common, key=lambda d: abs(float(cpp[d][col])-float(mt5[d][col])))
        flag = "  <-- DRIFT" if mn > (0.5 if col in ("adx_m1","adx_m3","adx_m5","adx_m15","rsi","atr_pctile","adxS") else 0.05) else ""
        print(f"  {col:12s} max={mx:10.4f} mean={mn:8.4f}  worst@{worst} (cpp={cpp[worst][col]} mt5={mt5[worst][col]}){flag}")

    # fire disagreements
    dis = [d for d in common if cpp[d]["fire_dir"] != mt5[d]["fire_dir"]]
    cpp_only_L = [d for d in dis if cpp[d]["fire_dir"]=="1"  and mt5[d]["fire_dir"]!="1"]
    cpp_only_S = [d for d in dis if cpp[d]["fire_dir"]=="-1" and mt5[d]["fire_dir"]!="-1"]
    mt5_only_L = [d for d in dis if mt5[d]["fire_dir"]=="1"  and cpp[d]["fire_dir"]!="1"]
    mt5_only_S = [d for d in dis if mt5[d]["fire_dir"]=="-1" and cpp[d]["fire_dir"]!="-1"]
    print(f"\n--- fire disagreements: {len(dis)} bars ---")
    print(f"  cpp-only LONG ={len(cpp_only_L)}  cpp-only SHORT={len(cpp_only_S)}")
    print(f"  mt5-only LONG ={len(mt5_only_L)}  mt5-only SHORT={len(mt5_only_S)}")

    # For cpp-only fires (the over-fire): which gate does MT5 BLOCK that C++ passes?
    def gate_blame(dts, gates, side):
        from collections import Counter
        c = Counter()
        for d in dts:
            for g in gates:
                # a gate is "blocking" when its bool differs and mt5=0 (block) while cpp=1 (pass)
                if cpp[d][g] != mt5[d][g]:
                    c[g] += 1
        return c.most_common()
    if cpp_only_L:
        print(f"\n  cpp-only LONG over-fire — gate cols where cpp!=mt5 (count of {len(cpp_only_L)}):")
        for g,n in gate_blame(cpp_only_L, GATE_L, "L"): print(f"    {g:10s} {n}")
        ex = cpp_only_L[:5]
        print(f"    examples: {ex}")
    if cpp_only_S:
        print(f"\n  cpp-only SHORT over-fire — gate cols where cpp!=mt5 (count of {len(cpp_only_S)}):")
        for g,n in gate_blame(cpp_only_S, GATE_S, "S"): print(f"    {g:10s} {n}")

if __name__ == "__main__":
    main()
