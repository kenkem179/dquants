#!/usr/bin/env python3
"""Phase-8 sensitivity / plateau analysis for KK-MasterVP on BTCUSD M3.

Takes a base config (the Optuna winner) and sweeps ONE param at a time across a grid,
re-running the parity-validated backtester for each value, and reports full/train/test
net + PF. The point (per the SOP) is to ACCEPT a parameter only where the metric is stable
across a neighbourhood — a plateau — not a lone spike that won't survive walk-forward.

Usage:
  python research/optimization/sensitivity_btc.py [base.set]
Default base = research/optimization/best_btc.set (write the Optuna winner there first).
Outputs a per-param table to stdout + research/optimization/sensitivity_btc.csv.
"""
import csv
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BIN = os.path.join(ROOT, "cpp_core/build/backtester")
BARS = os.path.join(ROOT, "cpp_core/tools/bars_btcusd_2025_m3.csv")
TICKS = os.path.join(ROOT, "cpp_core/tools/ticks_btcusd_2025_window.csv")
TRADE_FROM_MS = 1754870400000
SPLIT = "2025.11.01"
OUT = os.path.join(os.path.dirname(__file__), "sensitivity_btc.csv")

# Param -> sweep grid. Centred near typical optima; widen/narrow as needed.
GRID = {
    "InpSlAtrBrk":     [2.0, 2.35, 2.65, 2.9, 3.2],
    "InpBreakBufAtr":  [0.25, 0.31, 0.40, 0.55, 0.70],
    "InpBreakMaxAtr":  [5, 7, 9, 11],
    "InpTp1R":         [0.6, 0.8, 1.0, 1.2, 1.45],
    "InpTp1ClosePct":  [10, 20, 30, 40, 50],
    "InpTrailAtrMult": [1.8, 2.05, 2.4, 3.0, 3.6],
    "InpRunnerRr":     [4, 5.3, 7, 9, 12],
    "InpAdxTrendMin":  [20, 22, 24, 26, 28],
    "InpDiSpreadMin":  [4, 5, 6, 8],
}


def load_set(path):
    with open(path) as f:
        return {ln.split("=", 1)[0]: ln.split("=", 1)[1].strip()
                for ln in f if "=" in ln}


def write_set(path, d):
    with open(path, "w") as f:
        for k, v in d.items():
            f.write(f"{k}={v}\n")


def metrics(x):
    if not x:
        return 0.0, 0.0, 0
    net = sum(x)
    gp = sum(t for t in x if t > 0)
    gl = -sum(t for t in x if t < 0)
    return net, (gp / gl if gl > 0 else 0.0), len(x)


def run(base, key, val, idx):
    d = dict(base)
    d[key] = val
    s = f"/tmp/kkvp_sens_{key}_{idx}.set"
    c = f"/tmp/kkvp_sens_{key}_{idx}.csv"
    write_set(s, d)
    r = subprocess.run([BIN, "--bars", BARS, "--ticks", TICKS, "--out", c,
                        "--trade-from-ms", str(TRADE_FROM_MS), "--set", s],
                       cwd=ROOT, capture_output=True, text=True)
    tr, te = [], []
    if r.returncode == 0:
        for row in csv.DictReader(open(c)):
            u = float(row["realizedUsd"])
            (tr if row["entryTimeUTC"] < SPLIT else te).append(u)
    for p in (s, c):
        try:
            os.remove(p)
        except OSError:
            pass
    fn, fp, fnn = metrics(tr + te)
    trn, trp, _ = metrics(tr)
    ten, tep, _ = metrics(te)
    return dict(param=key, value=val, full_net=round(fn), full_pf=round(fp, 3), n=fnn,
                train_net=round(trn), train_pf=round(trp, 3),
                test_net=round(ten), test_pf=round(tep, 3))


def main():
    base_path = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(os.path.dirname(__file__), "best_btc.set")
    base = load_set(base_path)
    rows = []
    for key, vals in GRID.items():
        print(f"\n== {key} (base={base.get(key)}) ==")
        print(f"  {'value':>8} {'full_net':>9} {'full_pf':>8} {'train_net':>10} {'test_net':>9} {'test_pf':>8} {'n':>5}")
        for i, v in enumerate(vals):
            r = run(base, key, v, i)
            rows.append(r)
            star = "  <-base" if str(v) == str(base.get(key)) else ""
            print(f"  {v:>8} {r['full_net']:>9} {r['full_pf']:>8} {r['train_net']:>10} "
                  f"{r['test_net']:>9} {r['test_pf']:>8} {r['n']:>5}{star}")
    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"\n[sens] wrote {len(rows)} rows -> {OUT}")


if __name__ == "__main__":
    main()
