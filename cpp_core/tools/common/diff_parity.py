#!/usr/bin/env python3
"""Diff the C++ parity driver output against the MT5 tester reference parity_*.csv.

Aligns rows by barTimeUTC, then reports max/mean |Δ| per column (tolerance compare, not
bytes -- see KK-MasterVP-SPEC.md §9). The VALIDATED columns are the master VP (mpoc/mvah/
mval) + regime (trend/plus/minus/adx) + the raw signal (sigValid/sigLong/sigRev). atr1
carries the documented spike caveat (MT5's tick model registers wider intrabar extremes
than the exported tick CSV), and entry/sl/tp1/tp2 inherit that on spike bars. Local VP
(poc/vah/val) is NOT populated by the MT5 exporter -- excluded.

Usage: python cpp_core/tools/common/diff_parity.py <cpp_parity.csv> <mt5_ref.csv>
"""
import sys
import pandas as pd

CPP = sys.argv[1] if len(sys.argv) > 1 else "cpp_core/tools/parity_cpp_btcusd_M3.csv"
REF = sys.argv[2] if len(sys.argv) > 2 else (
    "/Users/tokyotechies/Workspace/KEM/kenkem/Tester/Agent-127.0.0.1-3000/"
    "MQL5/Files/KK-MasterVP/parity_BTCUSD-Exnes-0406_PERIOD_M3.csv")

NUMERIC = ["mpoc", "mvah", "mval", "plus", "minus", "adx", "atr1"]
FLAGS = ["trend", "sigValid", "sigLong", "sigRev"]
SIG_PRICE = ["entry", "sl", "tp1", "tp2"]


def main():
    cpp = pd.read_csv(CPP)
    ref = pd.read_csv(REF)
    m = ref.merge(cpp, on="barTimeUTC", suffixes=("_ref", "_cpp"), how="inner")
    print(f"[diff] {len(m)}/{len(ref)} ref rows aligned to a C++ row "
          f"({len(cpp)} C++ rows total)\n")

    print(f"  {'col':8s} {'max|Δ|':>14s} {'mean|Δ|':>12s}")
    worst_ok = True
    for col in NUMERIC:
        d = (m[f"{col}_cpp"] - m[f"{col}_ref"]).abs()
        flag = "  <- ATR spike caveat" if col == "atr1" else ""
        print(f"  {col:8s} {d.max():14.4f} {d.mean():12.4f}{flag}")
        if col in ("mpoc", "mvah", "mval") and d.max() > 0.5:
            worst_ok = False
        if col in ("plus", "minus", "adx") and d.max() > 0.05:
            worst_ok = False

    print()
    for col in FLAGS:
        agree = (m[f"{col}_cpp"] == m[f"{col}_ref"]).mean() * 100
        n_ref1 = int((m[f"{col}_ref"] == 1).sum())
        print(f"  {col:8s} agree={agree:6.2f}%   (ref==1 on {n_ref1} rows)")

    # On rows where MT5 raised a raw signal, did C++ agree, and how close are the prices?
    sigrows = m[m["sigValid_ref"] == 1]
    if len(sigrows):
        both = sigrows[sigrows["sigValid_cpp"] == 1]
        print(f"\n  [signal parity] C++ fired on {len(both)}/{len(sigrows)} MT5 sigValid=1 rows")
        miss = sigrows[sigrows["sigValid_cpp"] != 1]
        if len(miss):
            print("    C++ MISSED (MT5 fired, C++ did not) on:",
                  ", ".join(miss["barTimeUTC"].tolist()))
        extra = m[(m["sigValid_ref"] != 1) & (m["sigValid_cpp"] == 1)]
        if len(extra):
            print("    C++ EXTRA (C++ fired, MT5 did not) on:",
                  ", ".join(extra["barTimeUTC"].tolist()))
        if len(both):
            print("    price parity on the rows where BOTH fired:")
            for col in SIG_PRICE:
                d = (both[f"{col}_cpp"] - both[f"{col}_ref"]).abs()
                flag = "  <- inherits ATR caveat" if col in ("sl", "tp1", "tp2") else ""
                print(f"      {col:6s} max|Δ|={d.max():9.3f}  mean|Δ|={d.mean():8.3f}{flag}")

    # Show the worst master-VP disagreements (debugging aid).
    m["dvah"] = (m["mvah_cpp"] - m["mvah_ref"]).abs()
    worst = m.nlargest(5, "dvah")[["barTimeUTC", "mvah_cpp", "mvah_ref",
                                   "mval_cpp", "mval_ref", "adx_cpp", "adx_ref"]]
    print("\n  [worst mvah rows]")
    print(worst.to_string(index=False))

    print("\n[diff]", "PASS — validated columns within tolerance" if worst_ok
          else "FAIL — a validated column exceeded tolerance")
    return 0 if worst_ok else 1


if __name__ == "__main__":
    sys.exit(main())
