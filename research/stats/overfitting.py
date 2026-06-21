#!/usr/bin/env python3
"""Overfitting-control statistics — the multiple-testing antidote for our sweep→lock workflow.

WHY THIS EXISTS
---------------
Our research loop is: run N Optuna trials / coordinate sweeps over a parameter grid, then LOCK the
config with the best net/PF. That selection step inflates the winner's in-sample Sharpe purely by
chance: the more configs you try, the higher the *expected maximum* Sharpe even on random noise.
Walk-forward and Monte-Carlo (research/mastervp_parity/wf_mc.py) test stability, but neither one
deflates the headline Sharpe by *how hard we searched*. This module does.

It implements the Bailey & Lopez de Prado family (the relevant "best practice" for backtest-driven
strategy selection — NOT the Green Book's option-pricing calculus, which does not apply to M1/M3
scalping):

  * probabilistic_sharpe_ratio (PSR)  -- P(true SR > benchmark SR), skew/kurtosis aware
  * deflated_sharpe_ratio    (DSR)    -- PSR with benchmark = E[max SR over N trials]
  * min_track_record_length  (MinTRL) -- #obs needed to trust the Sharpe at a confidence level
  * prob_backtest_overfit    (PBO)    -- CSCV: P(the IS-best config underperforms OOS median)
  * benjamini_hochberg / bonferroni   -- FWER/FDR control for many-strategy comparisons

Everything operates on the per-trade P&L lists our engines already emit, so it bolts onto existing
harnesses with no new data plumbing. Pure numpy/scipy; deterministic given inputs.

References:
  Bailey & Lopez de Prado (2012) "The Sharpe Ratio Efficient Frontier" (PSR, MinTRL)
  Bailey & Lopez de Prado (2014) "The Deflated Sharpe Ratio" (DSR)
  Bailey, Borwein, Lopez de Prado & Zhu (2017) "The Probability of Backtest Overfitting" (PBO/CSCV)
"""
from __future__ import annotations

import math
from itertools import combinations

import numpy as np
from scipy.stats import norm, skew, kurtosis

EULER_MASCHERONI = 0.5772156649015329


# ----------------------------------------------------------------------------- core SR moments
def sharpe_ratio(returns, periods_per_year: float | None = None) -> float:
    """Per-observation Sharpe of a return/PnL series. If periods_per_year given, annualizes it.

    PSR/DSR/MinTRL below expect the NON-annualized (per-observation) Sharpe, because they carry
    the sample length n explicitly. Pass periods_per_year only when you want a human-readable
    annualized number for reporting.
    """
    r = np.asarray(returns, dtype=float)
    if r.size < 2:
        return 0.0
    sd = r.std(ddof=1)
    if sd == 0:
        return 0.0
    sr = r.mean() / sd
    return sr * math.sqrt(periods_per_year) if periods_per_year else sr


def _moments(returns):
    """Return (sr_per_obs, n, skew, kurtosis_non_excess) for the PSR machinery."""
    r = np.asarray(returns, dtype=float)
    n = r.size
    sr = sharpe_ratio(r)
    g3 = float(skew(r, bias=False)) if n > 2 else 0.0
    g4 = float(kurtosis(r, fisher=False, bias=False)) if n > 3 else 3.0  # non-excess (normal=3)
    return sr, n, g3, g4


# ----------------------------------------------------------------------------- PSR
def probabilistic_sharpe_ratio(returns, sr_benchmark: float = 0.0) -> float:
    """P(true Sharpe > sr_benchmark) given the observed series.

    sr_benchmark is a PER-OBSERVATION Sharpe (same units as sharpe_ratio(returns)). Default 0.0
    asks "is the strategy better than a coin flip?". Returns a probability in [0, 1].

    Accounts for non-normal returns: positive skew and excess kurtosis (fat tails) REDUCE the
    confidence, which is exactly the correction scalping P&L needs.
    """
    sr, n, g3, g4 = _moments(returns)
    if n < 3:
        return float("nan")
    denom = math.sqrt(max(1.0 - g3 * sr + (g4 - 1.0) / 4.0 * sr * sr, 1e-12))
    z = (sr - sr_benchmark) * math.sqrt(n - 1) / denom
    return float(norm.cdf(z))


def expected_max_sharpe(sr_trial_std: float, n_trials: int) -> float:
    """E[max Sharpe across n_trials independent strategies], each with true SR=0.

    This is the benchmark the Deflated Sharpe deflates against: even N pure-noise strategies will
    produce a best-of-N Sharpe this large by luck. sr_trial_std is the cross-trial dispersion of
    the per-observation Sharpe estimates (std of the SRs you observed across your sweep).
    """
    if n_trials < 2 or sr_trial_std <= 0:
        return 0.0
    z1 = norm.ppf(1.0 - 1.0 / n_trials)
    z2 = norm.ppf(1.0 - 1.0 / (n_trials * math.e))
    return sr_trial_std * ((1.0 - EULER_MASCHERONI) * z1 + EULER_MASCHERONI * z2)


def deflated_sharpe_ratio(returns, sr_trial_std: float, n_trials: int) -> float:
    """Deflated Sharpe Ratio = PSR evaluated against E[max SR over n_trials].

    THE headline number for "I swept n_trials configs and locked the best — is the edge real?".
    DSR > 0.95 => the locked Sharpe survives the multiple-testing deflation at 95% confidence.
    DSR < 0.90 => the edge is plausibly a search artifact; do not trust the lock.

      returns       : per-trade PnL of the LOCKED (best) config
      sr_trial_std  : std of per-observation Sharpe across ALL trials you ran (the search width)
      n_trials      : how many configs you evaluated before locking
    """
    sr_star = expected_max_sharpe(sr_trial_std, n_trials)
    return probabilistic_sharpe_ratio(returns, sr_benchmark=sr_star)


def min_track_record_length(returns, sr_benchmark: float = 0.0,
                            confidence: float = 0.95) -> float:
    """Minimum #observations to assert (at `confidence`) that true SR > sr_benchmark.

    If MinTRL > len(returns), your sample is TOO SHORT to trust the Sharpe regardless of how good
    it looks — collect more trades / a longer window before locking.
    """
    sr, n, g3, g4 = _moments(returns)
    if sr <= sr_benchmark:
        return float("inf")
    z = norm.ppf(confidence)
    var_term = 1.0 - g3 * sr + (g4 - 1.0) / 4.0 * sr * sr
    return 1.0 + var_term * (z / (sr - sr_benchmark)) ** 2


# ----------------------------------------------------------------------------- PBO via CSCV
def prob_backtest_overfit(trial_returns: np.ndarray, n_splits: int = 16) -> dict:
    """Probability of Backtest Overfitting via Combinatorially Symmetric Cross-Validation.

    The gold-standard "is my selection process overfit?" test. Feed it the per-period return
    MATRIX of EVERY config you swept (not just the winner):

        trial_returns : shape (T, N) -- T time buckets (rows) x N trials/configs (cols).
                        Build it by binning each config's per-trade PnL into the SAME T time
                        buckets (e.g. per-day or per-week sums) so rows align across configs.
        n_splits      : S, must be even. The T rows are partitioned into S blocks; every way of
                        choosing S/2 blocks as in-sample (the rest OOS) is evaluated.

    For each split: pick the config that is BEST in-sample, then look at its OOS rank. If selection
    generalized, the IS-best should rank high OOS; if we overfit, it lands below the OOS median.
    PBO = fraction of splits where the IS-best is below the OOS median. PBO > 0.5 => the selection
    procedure is worse than random — your "best" config is an overfit.

    Returns dict(pbo, n_combos, logits) where logits is the per-split logit distribution.
    """
    M = np.asarray(trial_returns, dtype=float)
    if M.ndim != 2:
        raise ValueError("trial_returns must be 2-D (T time buckets x N trials)")
    T, N = M.shape
    if N < 2:
        raise ValueError("need >= 2 trials to assess overfitting")
    if n_splits % 2 != 0:
        raise ValueError("n_splits (S) must be even")
    S = min(n_splits, T)
    if S < 2:
        raise ValueError("need >= 2 time blocks; supply a longer/finer return matrix")

    # split rows into S contiguous, near-equal blocks
    blocks = np.array_split(np.arange(T), S)

    def _sr_cols(rows):
        sub = M[rows, :]
        mu = sub.mean(axis=0)
        sd = sub.std(axis=0, ddof=1)
        sd[sd == 0] = np.inf  # dead config -> SR 0, never selected
        return mu / sd

    logits = []
    half = S // 2
    for is_idx in combinations(range(S), half):
        is_rows = np.concatenate([blocks[i] for i in is_idx])
        oos_rows = np.concatenate([blocks[i] for i in range(S) if i not in is_idx])
        is_sr = _sr_cols(is_rows)
        oos_sr = _sr_cols(oos_rows)
        best = int(np.argmax(is_sr))
        # relative OOS rank of the IS-best, in (0,1)
        rank = (oos_sr <= oos_sr[best]).sum() / float(N)
        rank = min(max(rank, 1.0 / (N + 1)), 1.0 - 1.0 / (N + 1))
        logits.append(math.log(rank / (1.0 - rank)))

    logits = np.asarray(logits)
    pbo = float((logits <= 0).mean())  # logit<=0 <=> OOS rank <= median
    return dict(pbo=pbo, n_combos=len(logits), logits=logits)


# ----------------------------------------------------------------------------- multiple testing
def bonferroni(pvalues, alpha: float = 0.05) -> dict:
    """Family-wise error control. Reject H0_i where p_i <= alpha/m. Conservative."""
    p = np.asarray(pvalues, dtype=float)
    thr = alpha / max(len(p), 1)
    return dict(threshold=thr, reject=(p <= thr), n_reject=int((p <= thr).sum()))


def benjamini_hochberg(pvalues, alpha: float = 0.05) -> dict:
    """False-Discovery-Rate control (BH step-up). Less conservative than Bonferroni — the right
    choice when screening many candidate strategies/params and you can tolerate a few false leads.
    """
    p = np.asarray(pvalues, dtype=float)
    m = len(p)
    if m == 0:
        return dict(threshold=0.0, reject=np.array([], dtype=bool), n_reject=0)
    order = np.argsort(p)
    ranked = p[order]
    crit = alpha * (np.arange(1, m + 1) / m)
    passed = ranked <= crit
    k = np.nonzero(passed)[0].max() + 1 if passed.any() else 0
    thr = ranked[k - 1] if k > 0 else 0.0
    reject = np.zeros(m, dtype=bool)
    if k > 0:
        reject[order[:k]] = True
    return dict(threshold=float(thr), reject=reject, n_reject=int(reject.sum()))


# ----------------------------------------------------------------------------- convenience report
def overfitting_report(locked_returns, sr_trial_std: float, n_trials: int,
                       periods_per_year: float | None = None,
                       confidence: float = 0.95) -> dict:
    """One-call summary for a locked strategy. Returns the numbers + a PASS/WARN/FAIL verdict.

      locked_returns   : per-trade PnL of the locked config
      sr_trial_std     : std of per-observation Sharpe across the sweep (search width)
      n_trials         : number of configs evaluated before locking
      periods_per_year : only for the annualized display Sharpe (252 XAU / 365 crypto)
    """
    n = len(locked_returns)
    psr0 = probabilistic_sharpe_ratio(locked_returns, 0.0)
    dsr = deflated_sharpe_ratio(locked_returns, sr_trial_std, n_trials)
    mintrl = min_track_record_length(locked_returns, 0.0, confidence)
    verdict = "PASS" if (dsr >= 0.95 and mintrl <= n) else \
              "WARN" if (dsr >= 0.90) else "FAIL"
    return dict(
        n_obs=n,
        sharpe_per_obs=sharpe_ratio(locked_returns),
        sharpe_annual=sharpe_ratio(locked_returns, periods_per_year) if periods_per_year else None,
        psr_vs_zero=psr0,
        deflated_sharpe=dsr,
        expected_max_sharpe=expected_max_sharpe(sr_trial_std, n_trials),
        min_track_record_length=mintrl,
        sample_sufficient=bool(mintrl <= n),
        n_trials=n_trials,
        verdict=verdict,
    )


def print_report(rep: dict) -> None:
    print(f"  observations         : {rep['n_obs']}")
    print(f"  Sharpe (per-obs)     : {rep['sharpe_per_obs']:.4f}")
    if rep.get("sharpe_annual") is not None:
        print(f"  Sharpe (annualized)  : {rep['sharpe_annual']:.3f}")
    print(f"  PSR vs 0             : {rep['psr_vs_zero']:.3f}")
    print(f"  E[max SR] of search  : {rep['expected_max_sharpe']:.4f}  (n_trials={rep['n_trials']})")
    print(f"  Deflated Sharpe (DSR): {rep['deflated_sharpe']:.3f}   <- multiple-testing-corrected")
    print(f"  Min track record len : {rep['min_track_record_length']:.0f} obs "
          f"({'sufficient' if rep['sample_sufficient'] else 'TOO SHORT'} vs {rep['n_obs']})")
    print(f"  VERDICT              : {rep['verdict']}")
