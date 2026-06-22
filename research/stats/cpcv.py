#!/usr/bin/env python3
"""Combinatorial Purged Cross-Validation (CPCV) — many OOS paths instead of one.

WHY THIS EXISTS
---------------
Walk-forward (wf_mc.py) gives ONE out-of-sample path: train [0,t), test [t,T). Its verdict depends
entirely on where the single fold boundary happens to fall. CPCV (Lopez de Prado, *Advances in
Financial Machine Learning*, ch. 7 & 12) fixes this: split the timeline into N groups, hold out every
combination of k groups as the test set, and reconstruct φ = C(N,k)·k/N distinct OOS backtest paths.
You get a *distribution* of OOS Sharpe/PF/maxDD, and an embargo-aware Probability of Backtest
Overfitting — the rigorous answer to "is the OOS number luck of the boundary?".

Two leakage controls that plain k-fold lacks:
  * PURGE   — drop training observations whose information window overlaps the test set.
  * EMBARGO — additionally drop training observations for a short span AFTER each test block, because
              serial correlation leaks forward (a trade's outcome correlates with the next few).

This module is strategy-agnostic and operates on the per-period return MATRIX our sweeps already
produce (or a single stream for path analysis). numpy/scipy only; deterministic.

CLI:
  python research/stats/cpcv.py --matrix trial_returns.csv --groups 8 --test 2 --embargo 0.01
      (rows = time buckets, cols = swept configs; reports CPCV-PBO with embargo)
"""
from __future__ import annotations

import argparse
import csv
import math
from itertools import combinations

import numpy as np


def n_backtest_paths(n_groups: int, test_size: int) -> int:
    """φ = C(N,k)·k/N — the number of distinct OOS paths CPCV reconstructs."""
    return math.comb(n_groups, test_size) * test_size // n_groups


def cpcv_splits(n_obs: int, n_groups: int = 8, test_size: int = 2, embargo: float = 0.0):
    """Yield (train_idx, test_idx) for every combination of `test_size` held-out groups.

      n_obs     : number of observations (rows / trades / periods)
      n_groups  : N contiguous, near-equal groups the timeline is cut into
      test_size : k groups held out per split (k>=2 is what makes it *combinatorial*)
      embargo   : fraction of n_obs to drop from training AFTER each test block (serial-corr guard)

    Purge is automatic: any training index inside or adjacent-after a test block (within the embargo)
    is removed. Indices are plain positional ints into the time-sorted sample.
    """
    if test_size >= n_groups:
        raise ValueError("test_size must be < n_groups")
    groups = np.array_split(np.arange(n_obs), n_groups)
    emb = int(round(embargo * n_obs))
    for combo in combinations(range(n_groups), test_size):
        test_idx = np.concatenate([groups[g] for g in combo])
        test_set = set(test_idx.tolist())
        # embargo: forbid training indices in [end_of_test_block, end+emb] for each test block
        forbidden = set(test_set)
        for g in combo:
            end = int(groups[g][-1])
            for j in range(end + 1, min(end + 1 + emb, n_obs)):
                forbidden.add(j)
        train_idx = np.array([i for i in range(n_obs) if i not in forbidden], dtype=int)
        yield train_idx, np.sort(test_idx)


def cpcv_pbo(trial_returns, n_groups: int = 8, test_size: int = 2, embargo: float = 0.0) -> dict:
    """Probability of Backtest Overfitting via CPCV (embargo-aware generalization of CSCV).

      trial_returns : (T, M) matrix — T time buckets x M swept configs. Build by binning each config's
                      per-trade PnL into the SAME T buckets so rows align across configs.

    For each combinatorial split: pick the config best IN-SAMPLE (train groups), measure its rank
    OUT-OF-SAMPLE (test groups). PBO = fraction of splits where the IS-best lands below the OOS median.
    PBO > 0.5 => the selection procedure is worse than random; the "best" config is an overfit.
    Returns dict(pbo, n_paths, n_configs, logits, oos_sharpe_of_is_best).
    """
    M = np.asarray(trial_returns, dtype=float)
    if M.ndim != 2:
        raise ValueError("trial_returns must be 2-D (T buckets x M configs)")
    T, m = M.shape
    if m < 2:
        raise ValueError("need >= 2 configs")
    n_groups = min(n_groups, T)

    def sr(rows):
        sub = M[rows, :]
        mu = sub.mean(axis=0)
        sd = sub.std(axis=0, ddof=1)
        sd[sd == 0] = np.inf
        return mu / sd

    logits, oos_best = [], []
    for train_idx, test_idx in cpcv_splits(T, n_groups, test_size, embargo):
        if len(train_idx) < 2 or len(test_idx) < 2:
            continue
        is_sr = sr(train_idx)
        oos_sr = sr(test_idx)
        best = int(np.argmax(is_sr))
        rank = (oos_sr <= oos_sr[best]).sum() / float(m)
        rank = min(max(rank, 1.0 / (m + 1)), 1.0 - 1.0 / (m + 1))
        logits.append(math.log(rank / (1.0 - rank)))
        oos_best.append(float(oos_sr[best]))

    logits = np.asarray(logits)
    return dict(
        pbo=float((logits <= 0).mean()) if len(logits) else float("nan"),
        n_paths=len(logits),
        n_configs=m,
        logits=logits,
        oos_sharpe_of_is_best=np.asarray(oos_best),
    )


def cpcv_path_stats(returns, n_groups: int = 8, test_size: int = 2, embargo: float = 0.0,
                    periods_per_year: float | None = None) -> dict:
    """Distribution of OOS performance for a SINGLE config across all CPCV test blocks.

    returns: 1-D per-period return series of one config. We evaluate the config on each held-out test
    block (the train side is irrelevant for a fixed config — this isolates *period* dependence the way
    walk-forward does, but over C(N,k) overlapping OOS slices instead of one). Reports the spread of
    OOS Sharpe — a tight, all-positive spread is a robust edge; a wide one that crosses zero is fragile.
    """
    r = np.asarray(returns, dtype=float)
    T = r.size
    n_groups = min(n_groups, T)
    seen, srs = set(), []
    for _, test_idx in cpcv_splits(T, n_groups, test_size, embargo):
        key = tuple(test_idx.tolist())
        if key in seen:
            continue
        seen.add(key)
        seg = r[test_idx]
        if seg.size < 2 or seg.std(ddof=1) == 0:
            continue
        s = seg.mean() / seg.std(ddof=1)
        if periods_per_year:
            s *= math.sqrt(periods_per_year)
        srs.append(s)
    srs = np.asarray(srs)
    if srs.size == 0:
        return dict(n_paths=0)
    return dict(
        n_paths=int(srs.size),
        sharpe_mean=float(srs.mean()),
        sharpe_std=float(srs.std(ddof=1)) if srs.size > 1 else 0.0,
        sharpe_min=float(srs.min()),
        sharpe_p05=float(np.percentile(srs, 5)),
        sharpe_median=float(np.median(srs)),
        sharpe_max=float(srs.max()),
        frac_positive=float((srs > 0).mean()),
    )


# ----------------------------------------------------------------------------- CLI
def _load_matrix(path):
    with open(path) as f:
        rows = list(csv.reader(f))
    # optional header row of non-numeric labels
    try:
        float(rows[0][0])
        data = rows
    except ValueError:
        data = rows[1:]
    return np.array([[float(x) for x in r] for r in data], dtype=float)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Combinatorial Purged Cross-Validation.")
    ap.add_argument("--matrix", required=True, help="CSV: rows=time buckets, cols=configs")
    ap.add_argument("--groups", type=int, default=8)
    ap.add_argument("--test", type=int, default=2)
    ap.add_argument("--embargo", type=float, default=0.01)
    args = ap.parse_args(argv)

    M = _load_matrix(args.matrix)
    T, m = M.shape
    print(f"matrix: {T} time buckets x {m} configs")
    print(f"CPCV: N={args.groups} groups, k={args.test} test, "
          f"{n_backtest_paths(args.groups, args.test)} backtest paths, embargo={args.embargo}")
    rep = cpcv_pbo(M, args.groups, args.test, args.embargo)
    print(f"  evaluated splits     : {rep['n_paths']}")
    print(f"  PBO                  : {rep['pbo']:.3f}  "
          f"({'OVERFIT' if rep['pbo'] > 0.5 else 'OK' if rep['pbo'] < 0.2 else 'CAUTION'})")
    ob = rep["oos_sharpe_of_is_best"]
    if ob.size:
        print(f"  OOS Sharpe of IS-best: median {np.median(ob):.3f}, "
              f"5th pct {np.percentile(ob, 5):.3f}, frac>0 {(ob > 0).mean():.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
