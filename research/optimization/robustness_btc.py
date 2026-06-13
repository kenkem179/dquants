#!/usr/bin/env python3
"""Phase-9 (light) robustness checks for the optimized KK-MasterVP BTCUSD config.

Two cheap-but-honest stress tests on the refined config's realized trade sequence
(trades_best_btc.csv from best_btc.set):

  1. Monte Carlo — bootstrap-resample trades (with replacement) and shuffle order to get
     distributions of net P&L, PF, and max drawdown. Reports the share of profitable runs
     and the 5th-percentile (bad-luck) outcome — a risk-of-ruin sense the single backtest hides.
  2. Rolling stability — PF / net per calendar slice (month + half-month) to check the edge
     is spread across time, not carried by one lucky stretch.

This is NOT a full re-optimizing walk-forward (that needs a longer tick window + per-fold Optuna);
it is the temporal-stability + path-risk gate on the CHOSEN params. Deterministic (seeded).

Usage: python research/optimization/robustness_btc.py [trades.csv] [n_boot]
"""
import csv
import os
import random
import sys

HERE = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT = os.path.join(ROOT, "cpp_core/tools/trades_best_btc.csv")


def load(path):
    rows = []
    for r in csv.DictReader(open(path)):
        rows.append((r["entryTimeUTC"], float(r["realizedUsd"])))
    return rows


def pf(x):
    gp = sum(t for t in x if t > 0)
    gl = -sum(t for t in x if t < 0)
    return gp / gl if gl > 0 else (float("inf") if gp > 0 else 0.0)


def maxdd(seq):
    cum = pk = dd = 0.0
    for t in seq:
        cum += t
        pk = max(pk, cum)
        dd = max(dd, pk - cum)
    return dd


def pct(sorted_vals, p):
    i = max(0, min(len(sorted_vals) - 1, int(p / 100 * len(sorted_vals))))
    return sorted_vals[i]


def monte_carlo(pnl, n_boot, seed=42):
    rng = random.Random(seed)
    n = len(pnl)
    nets, pfs, dds = [], [], []
    prof = 0
    for _ in range(n_boot):
        sample = [pnl[rng.randrange(n)] for _ in range(n)]   # bootstrap w/ replacement
        net = sum(sample)
        nets.append(net)
        pfs.append(pf(sample))
        rng.shuffle(sample)
        dds.append(maxdd(sample))
        if net > 0:
            prof += 1
    nets.sort(); pfs.sort(); dds.sort()
    print(f"\n=== Monte Carlo ({n_boot} bootstraps of {n} trades) ===")
    print(f"  profitable runs : {prof/n_boot*100:.1f}%")
    print(f"  net  P5/P50/P95 : ${pct(nets,5):.0f} / ${pct(nets,50):.0f} / ${pct(nets,95):.0f}")
    print(f"  PF   P5/P50/P95 : {pct(pfs,5):.3f} / {pct(pfs,50):.3f} / {pct(pfs,95):.3f}")
    print(f"  maxDD P50/P95   : ${pct(dds,50):.0f} / ${pct(dds,95):.0f}  (P95 = bad-luck drawdown)")


def rolling(rows):
    def slices(keyfn, label):
        buckets = {}
        for t, u in rows:
            buckets.setdefault(keyfn(t), []).append(u)
        print(f"\n=== Rolling stability by {label} ===")
        print(f"  {'slice':>10} {'net':>9} {'pf':>7} {'n':>5}")
        for k in sorted(buckets):
            x = buckets[k]
            print(f"  {k:>10} {sum(x):9.0f} {pf(x):7.3f} {len(x):5d}")
    slices(lambda t: t[:7], "month")               # 2025.08
    slices(lambda t: t[:7] + ("a" if t[8:10] <= "15" else "b"), "half-month")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    n_boot = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
    rows = load(path)
    pnl = [u for _, u in rows]
    print(f"loaded {len(rows)} trades from {os.path.relpath(path, ROOT)}  "
          f"(net ${sum(pnl):.0f}, PF {pf(pnl):.3f}, maxDD ${maxdd(pnl):.0f})")
    monte_carlo(pnl, n_boot)
    rolling(rows)


if __name__ == "__main__":
    main()
