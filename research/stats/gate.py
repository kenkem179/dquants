#!/usr/bin/env python3
"""Strategy-AGNOSTIC overfitting / multiple-testing gate for any locked trade stream.

Every engine in this repo (KenKem, MasterVP, Monster, BTC sweeps) emits a trades CSV carrying at
least `entryTimeUTC` and `realizedUsd`. This module runs the Bailey & Lopez de Prado overfitting
gate on ANY such stream, so the same lock-hardening check applies uniformly to all strategies —
no per-strategy copy. The per-strategy harnesses (wf_mc.py, wf_monster.py, robustness_*.py) call
run_gate() instead of re-implementing it.

  python -m stats.gate --trades research/monster_parity/_locked.csv --n-trials 180 --sr-trial-std 0.04
  python research/stats/gate.py --trades research/kenkem_parity/cpp_trades_xau_paritywin.csv

The single-stream gate reports PSR-vs-0, Min Track Record Length, and (given the sweep width)
the Deflated Sharpe Ratio with a PASS/WARN/FAIL verdict. The Probability of Backtest Overfitting
(PBO) needs the full sweep's return MATRIX, not one stream — see overfitting.prob_backtest_overfit
and the --pbo-matrix option.
"""
from __future__ import annotations

import argparse
import csv
import math
import os
import sys
from datetime import datetime

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from stats.overfitting import (   # noqa: E402
    sharpe_ratio, probabilistic_sharpe_ratio, deflated_sharpe_ratio,
    expected_max_sharpe, min_track_record_length, prob_backtest_overfit,
)

START_BAL = 10000.0
# Columns we accept for the trade time / pnl, in priority order — covers every engine's schema.
_TIME_KEYS = ("entryTimeUTC", "entryTime", "openTime", "time")
_TIME_MS_KEYS = ("ts_ms", "tsMs", "entryMs")          # epoch-milliseconds variants
_PNL_KEYS = ("realizedUsd", "pnlUsd", "pnl", "profit", "netUsd")
_TIME_FMTS = ("%Y.%m.%d %H:%M", "%Y.%m.%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M")


def _pick(header, keys):
    for k in keys:
        if k in header:
            return k
    return None


def _parse_time(s):
    for fmt in _TIME_FMTS:
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    raise ValueError(f"unrecognized time format: {s!r}")


def load_trades(path):
    """Load any engine's trades CSV -> sorted list of (datetime, pnl_usd). Schema-tolerant.

    Accepts string timestamps (entryTimeUTC, ...) OR epoch-ms columns (ts_ms, ...), and any of the
    known pnl column names — so KenKem/MasterVP/Monster/BTC streams all load through one path.
    """
    from datetime import timezone
    with open(path) as f:
        reader = csv.DictReader(f)
        tk = _pick(reader.fieldnames, _TIME_KEYS)
        mk = _pick(reader.fieldnames, _TIME_MS_KEYS)
        pk = _pick(reader.fieldnames, _PNL_KEYS)
        if (not tk and not mk) or not pk:
            raise SystemExit(
                f"{path}: need a time col {_TIME_KEYS + _TIME_MS_KEYS} and a pnl col {_PNL_KEYS}; "
                f"got {reader.fieldnames}")
        rows = []
        for r in reader:
            if r[pk] in ("", None):
                continue
            t = (datetime.fromtimestamp(int(r[mk]) / 1000, tz=timezone.utc) if mk
                 else _parse_time(r[tk]))
            rows.append((t, float(r[pk])))
    rows.sort(key=lambda x: x[0])
    return rows


def return_fractions(rows, start_bal=START_BAL):
    """De-compound realizedUsd to per-trade return-fractions r_i = pnl_i / balance_before_i."""
    bal = start_bal
    out = []
    for _, pnl in rows:
        out.append(pnl / bal)
        bal += pnl
    return out


def run_gate(rfracs, n_trials=0, sr_trial_std=0.0, conf=0.95):
    """Compute the overfitting-gate metrics on a per-trade return-fraction series.

    Returns a dict; DSR/verdict are None unless BOTH n_trials and sr_trial_std are supplied
    (the sweep width is what makes the deflation meaningful).
    """
    n = len(rfracs)
    sr = sharpe_ratio(rfracs)
    psr0 = probabilistic_sharpe_ratio(rfracs, 0.0)
    mintrl = min_track_record_length(rfracs, 0.0, conf)
    sufficient = bool(mintrl <= n)
    rep = dict(n=n, sharpe=sr, psr0=psr0, mintrl=mintrl, sufficient=sufficient,
               n_trials=n_trials, sr_trial_std=sr_trial_std,
               sr_star=None, dsr=None, verdict=None)
    if n_trials and sr_trial_std and sr_trial_std > 0:
        rep["sr_star"] = expected_max_sharpe(sr_trial_std, n_trials)
        rep["dsr"] = deflated_sharpe_ratio(rfracs, sr_trial_std, n_trials)
        rep["verdict"] = ("PASS" if (rep["dsr"] >= 0.95 and sufficient)
                          else "WARN" if rep["dsr"] >= 0.90 else "FAIL")
    return rep


def print_gate(rep, label="LOCKED"):
    print(f"\n## MULTIPLE-TESTING / OVERFITTING GATE :: {label}  (Bailey & Lopez de Prado)")
    print(f"per-trade Sharpe        : {rep['sharpe']:.4f}   (n={rep['n']} trades)")
    print(f"PSR vs 0 (skew/kurt adj): {rep['psr0']:.3f}   P(true edge > coin-flip)")
    mtrl = "inf" if math.isinf(rep["mintrl"]) else f"{rep['mintrl']:.0f}"
    print(f"Min track record length: {mtrl} trades  "
          f"({'sufficient' if rep['sufficient'] else 'TOO SHORT'} vs {rep['n']} we have)")
    if rep["dsr"] is not None:
        print(f"E[max Sharpe] of search : {rep['sr_star']:.4f}   "
              f"(deflation benchmark, n_trials={rep['n_trials']})")
        print(f"DEFLATED SHARPE (DSR)   : {rep['dsr']:.3f}   <- multiple-testing-corrected confidence")
        print(f"VERDICT                 : {rep['verdict']}   "
              f"(PASS=>0.95 & sample-sufficient, WARN=>0.90, else FAIL)")
    else:
        print("DEFLATED SHARPE (DSR)   : n/a — pass --n-trials AND --sr-trial-std from the sweep")
        print("  (n_trials = #configs evaluated; sr-trial-std = std of per-trade Sharpe across them)")


def main():
    ap = argparse.ArgumentParser(description="Universal overfitting gate for any strategy's trades CSV")
    ap.add_argument("--trades", required=True, help="any engine's trades CSV (needs entryTimeUTC + realizedUsd)")
    ap.add_argument("--label", default="LOCKED")
    ap.add_argument("--n-trials", type=int, default=0,
                    help="configs the sweep evaluated before locking (for Deflated Sharpe)")
    ap.add_argument("--sr-trial-std", type=float, default=0.0,
                    help="std of per-trade Sharpe across those trials (search dispersion)")
    ap.add_argument("--start-bal", type=float, default=START_BAL)
    ap.add_argument("--pbo-matrix", default=None,
                    help="optional .npy/.csv of shape (T buckets x N trials) for PBO/CSCV")
    ap.add_argument("--pbo-splits", type=int, default=16)
    a = ap.parse_args()

    rows = load_trades(a.trades)
    rfracs = return_fractions(rows, a.start_bal)
    span = f"{rows[0][0]:%Y-%m-%d} -> {rows[-1][0]:%Y-%m-%d}"
    print(f"==== Overfitting gate :: {a.label} ====")
    print(f"trades {len(rows)} | span {span} | source {a.trades}")
    print_gate(run_gate(rfracs, a.n_trials, a.sr_trial_std), a.label)

    if a.pbo_matrix:
        M = (np.load(a.pbo_matrix) if a.pbo_matrix.endswith(".npy")
             else np.loadtxt(a.pbo_matrix, delimiter=","))
        res = prob_backtest_overfit(M, n_splits=a.pbo_splits)
        print(f"\n## PROBABILITY OF BACKTEST OVERFITTING (CSCV, {res['n_combos']} splits)")
        print(f"PBO = {res['pbo']:.3f}   (>0.5 => selection is worse than random — overfit)")


if __name__ == "__main__":
    main()
