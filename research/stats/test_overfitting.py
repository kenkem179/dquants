#!/usr/bin/env python3
"""Sanity + correctness tests for the overfitting-control stats.

Run: conda run -n kenkem python -m pytest research/stats/test_overfitting.py -q
"""
import numpy as np

from overfitting import (
    probabilistic_sharpe_ratio,
    deflated_sharpe_ratio,
    expected_max_sharpe,
    min_track_record_length,
    prob_backtest_overfit,
    benjamini_hochberg,
    bonferroni,
    overfitting_report,
)

RNG = np.random.default_rng(42)


def test_psr_monotonic_in_edge():
    """A genuinely positive-edge series should have high PSR vs 0; pure noise ~0.5."""
    edge = RNG.normal(0.10, 1.0, 2000)      # SR ~0.1/obs over 2000 obs -> strong
    noise = RNG.normal(0.0, 1.0, 2000)
    assert probabilistic_sharpe_ratio(edge, 0.0) > 0.95
    # a single noise draw varies; over many seeds it centers on 0.5. Just assert it's not "edge".
    noise_psrs = [probabilistic_sharpe_ratio(RNG.normal(0.0, 1.0, 2000), 0.0) for _ in range(20)]
    assert 0.4 < float(np.mean(noise_psrs)) < 0.6


def test_deflation_lowers_confidence():
    """DSR (deflated by search width) must be <= PSR vs 0 for the same series."""
    r = RNG.normal(0.05, 1.0, 1500)
    psr0 = probabilistic_sharpe_ratio(r, 0.0)
    dsr = deflated_sharpe_ratio(r, sr_trial_std=0.03, n_trials=200)
    assert dsr <= psr0
    assert 0.0 <= dsr <= 1.0


def test_expected_max_sharpe_grows_with_trials():
    """E[max SR] increases as you search more configs (more chances to get lucky)."""
    a = expected_max_sharpe(0.05, 10)
    b = expected_max_sharpe(0.05, 1000)
    assert b > a > 0


def test_min_trl_huge_when_near_zero_edge():
    """Near-zero edge needs an impractically large sample (>> the data we have) to trust."""
    flat = RNG.normal(0.0, 1.0, 500)
    mintrl = min_track_record_length(flat, 0.0)
    assert np.isinf(mintrl) or mintrl > len(flat)   # can't trust the Sharpe at this length


def test_pbo_noise_higher_than_edge():
    """Pure-noise selection should look far more overfit than selecting a genuine edge.

    Averaged over realizations: PBO(noise) centers ~0.5, PBO(true edge) ~0. We assert the gap.
    """
    T, N = 64, 30
    noise_pbo, edge_pbo = [], []
    for _ in range(8):
        noise_pbo.append(prob_backtest_overfit(RNG.normal(0.0, 1.0, (T, N)), n_splits=8)["pbo"])
        M = RNG.normal(0.0, 1.0, (T, N)); M[:, 0] += 0.8
        edge_pbo.append(prob_backtest_overfit(M, n_splits=8)["pbo"])
    assert np.mean(noise_pbo) > np.mean(edge_pbo) + 0.2


def test_pbo_true_edge_is_low():
    """One config has a real persistent edge -> selecting it should generalize -> low PBO."""
    T, N = 64, 30
    M = RNG.normal(0.0, 1.0, (T, N))
    M[:, 0] += 0.8                    # config 0 is genuinely better every period
    res = prob_backtest_overfit(M, n_splits=8)
    assert res["pbo"] < 0.20


def test_bh_and_bonferroni():
    p = np.array([0.001, 0.01, 0.2, 0.6, 0.9])
    bh = benjamini_hochberg(p, 0.05)
    bf = bonferroni(p, 0.05)
    assert bh["n_reject"] >= bf["n_reject"]   # BH never rejects fewer than Bonferroni
    assert bf["reject"][0] and bh["reject"][0]


def test_report_verdict_fields():
    r = RNG.normal(0.08, 1.0, 1200)
    rep = overfitting_report(r, sr_trial_std=0.02, n_trials=50, periods_per_year=252)
    assert rep["verdict"] in {"PASS", "WARN", "FAIL"}
    assert set(["deflated_sharpe", "min_track_record_length", "psr_vs_zero"]).issubset(rep)


if __name__ == "__main__":
    import sys
    import pytest
    sys.exit(pytest.main([__file__, "-q"]))
