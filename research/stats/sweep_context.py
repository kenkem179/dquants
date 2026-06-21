#!/usr/bin/env python3
"""Sweep-context capture — emit the search width a Deflated Sharpe needs, straight from the optimizer.

The overfitting gate (gate.py / overfitting.py) deflates a locked Sharpe by *how hard the sweep
searched*: it needs `n_trials` (configs evaluated) and `sr_trial_std` (std of per-trade Sharpe across
those trials). Until now those were guessed. These two helpers wire the REAL numbers out of any
optimize_*.py with two hooks:

  1. inside the Optuna objective, after you have the trial's trade stream:
        trial.set_user_attr("sharpe", trial_sharpe(train + test))
  2. after study.optimize(...), once the best .set is written:
        report_sweep_context(study, best_set_path, label="mastervp:xau")

It prints n_trials + sr_trial_std, the ready-to-paste gate.py command, and drops a sidecar
`<best>.set.sweepctx.json` so the lock carries its own search provenance.
"""
from __future__ import annotations

import json
import math

from .overfitting import sharpe_ratio


def trial_sharpe(pnls) -> float:
    """Per-trade Sharpe of one trial's trade stream. Store it as a trial user_attr so the dispersion
    across all trials (sr_trial_std) can be recovered after the study — that dispersion IS the
    search width the Deflated Sharpe deflates against."""
    return sharpe_ratio(pnls)


def report_sweep_context(study, best_set_path=None, label="LOCKED", attr="sharpe"):
    """Summarize an Optuna study's search width for the overfitting gate.

    Reads each COMPLETE trial's per-trade Sharpe (set via trial.set_user_attr(attr, ...)), computes
    n_trials + sr_trial_std, prints them with the exact gate.py command, and writes a sidecar JSON
    next to best_set_path. Returns the context dict (or None if too few usable trials).
    """
    sh = [t.user_attrs.get(attr) for t in study.trials
          if getattr(t.state, "name", "") == "COMPLETE"
          and t.user_attrs.get(attr) is not None
          and math.isfinite(t.user_attrs.get(attr))]
    n_trials = len(sh)
    if n_trials < 2:
        print(f"[sweep-context] only {n_trials} usable trial Sharpe(s) — cannot estimate dispersion; "
              f"did the objective call trial.set_user_attr('{attr}', trial_sharpe(...))?")
        return None
    mean = sum(sh) / n_trials
    sr_trial_std = math.sqrt(sum((x - mean) ** 2 for x in sh) / (n_trials - 1))
    ctx = dict(label=label, n_trials=n_trials, sr_trial_std=sr_trial_std,
               sharpe_mean=mean, sharpe_best=max(sh))
    print(f"[sweep-context] {label}: n_trials={n_trials}  sr_trial_std={sr_trial_std:.4f}  "
          f"(per-trial Sharpe mean={mean:.4f}, best={max(sh):.4f})")
    print(f"[sweep-context] deflate this lock through the overfitting gate:")
    print(f"    python research/stats/gate.py --trades <locked trades.csv> "
          f"--n-trials {n_trials} --sr-trial-std {sr_trial_std:.4f}")
    if best_set_path:
        side = str(best_set_path) + ".sweepctx.json"
        with open(side, "w") as f:
            json.dump(ctx, f, indent=2)
        print(f"[sweep-context] wrote {side}")
    return ctx
