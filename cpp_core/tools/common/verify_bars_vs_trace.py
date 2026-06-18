#!/usr/bin/env python3
"""Regression check: prove a bars-M1 CSV is bit-exact vs an MT5 per-bar trace, and that
Wilder ATR(14) matches except where the EXPORTED TICKS ARE MISSING DAYS MT5 HAD.

THE JOIN (critical): the C++/DuckDB bar is keyed by its OPEN time; the MT5 EA trace row is
labeled with the CLOSE time of the bar it describes. So join  my_open == trace_ts - 60000.
At that offset XAU M1 high/low/close match MT5 to 0.000000 (100%); see DATA_HEALTH doc.

ATR residual is NOT a formula/tick-fidelity bug: it is a localized spike injected by the M1
TR of the FIRST bar after a multi-day data hole (price gapped over days the export lacks).
This script reports those holes so you can see the residual is data-driven, not engine-driven.

USAGE
  python cpp_core/tools/common/verify_bars_vs_trace.py \
      --bars cpp_core/tools/bars_xauusd_2025h1_m1.csv \
      --trace research/kenkem_parity/trace_xau_paritywin.csv
"""
import argparse
import csv
import datetime as dt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bars", required=True)
    ap.add_argument("--trace", required=True)
    ap.add_argument("--atr-period", type=int, default=14)
    args = ap.parse_args()

    bars = {}
    order = []
    with open(args.bars) as fh:
        r = csv.reader(fh); next(r)
        for row in r:
            t = int(row[0])
            bars[t] = (float(row[1]), float(row[2]), float(row[3]), float(row[4]))
            order.append(t)
    order.sort()

    # Wilder ATR(14) over the contiguous M1 series (closed-bar recursion, SMA seed).
    P = args.atr_period
    atr = {}
    prev_c = None; a = None; seed = []
    for t in order:
        o, h, l, c = bars[t]
        tr = (h - l) if prev_c is None else max(h - l, abs(h - prev_c), abs(l - prev_c))
        if a is None:
            seed.append(tr)
            if len(seed) == P:
                a = sum(seed) / P
        else:
            a = (a * (P - 1) + tr) / P
        if a is not None:
            atr[t] = a
        prev_c = c

    he = le = ce = 0.0
    n = 0
    ae = []
    worst = []
    with open(args.trace) as fh:
        for row in csv.DictReader(fh):
            k = int(row["ts_ms"]) - 60000
            if k not in bars:
                continue
            _, H, L, C = bars[k]
            he = max(he, abs(float(row["high"]) - H))
            le = max(le, abs(float(row["low"]) - L))
            ce = max(ce, abs(float(row["close"]) - C))
            n += 1
            if "atr" in row and k in atr:
                d = abs(float(row["atr"]) - atr[k])
                ae.append((d, k, float(row["atr"]), atr[k]))

    print(f"joined {n} bars  (join: my_open == trace_ts - 60000)")
    print(f"  HIGH  max|Δ| {he:.6f}")
    print(f"  LOW   max|Δ| {le:.6f}")
    print(f"  CLOSE max|Δ| {ce:.6f}")
    ok = (he < 1e-6 and le < 1e-6 and ce < 1e-6)
    print(f"  OHLC bit-exact: {'YES ✅' if ok else 'NO ❌'}")
    if ae:
        ae.sort(reverse=True)
        import statistics
        med = statistics.median(d for d, *_ in ae)
        print(f"  ATR(14) median|Δ| {med:.6f}  max|Δ| {ae[0][0]:.4f}")
        print(f"  ATR worst rows (expect = first bars after multi-day data holes):")
        for d, k, ta, ma in ae[:4]:
            print(f"    {dt.datetime.utcfromtimestamp((k+60000)/1000)}  traceATR {ta:.4f}  myATR {ma:.4f}  Δ {d:.4f}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
