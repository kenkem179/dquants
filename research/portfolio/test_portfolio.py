#!/usr/bin/env python3
"""Tests for the portfolio construction layer. Run: pytest research/portfolio/test_portfolio.py"""
import os
import sys
from datetime import datetime, timedelta

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from portfolio import portfolio as P  # noqa: E402


def _synth_matrix(n_periods=300, seed=7):
    """Two correlated streams + one diversifier, known structure."""
    rng = np.random.default_rng(seed)
    a = rng.normal(0.001, 0.01, n_periods)
    b = a * 0.8 + rng.normal(0.0008, 0.006, n_periods)  # highly correlated with a
    c = rng.normal(0.0012, 0.012, n_periods)            # independent diversifier
    idx = pd.date_range("2025-01-01", periods=n_periods, freq="D")
    return pd.DataFrame({"A": a, "B": b, "C": c}, index=idx)


def test_shrinkage_in_unit_interval_and_symmetric():
    mat = _synth_matrix()
    cov, shrink = P.shrink_cov_constant_corr(mat.values)
    assert 0.0 <= shrink <= 1.0
    assert np.allclose(cov, cov.T)
    assert np.all(np.linalg.eigvalsh(cov) > -1e-10)  # PSD


@pytest.mark.parametrize("method", list(P.ALLOC_METHODS))
def test_weights_simplex(method):
    mat = _synth_matrix()
    cov, _ = P.shrink_cov_constant_corr(mat.values)
    w = P.ALLOC_METHODS[method](mat, cov=cov)
    assert len(w) == 3
    assert np.all(w >= -1e-9), f"{method} produced negative weights"
    assert abs(w.sum() - 1.0) < 1e-6, f"{method} weights do not sum to 1"


def test_risk_parity_equalizes_risk_contributions():
    mat = _synth_matrix()
    cov, _ = P.shrink_cov_constant_corr(mat.values)
    w = P.weights_risk_parity(mat, cov=cov)
    met = P.portfolio_metrics(mat, w, cov=cov)
    rc = np.array(list(met["component_risk_pct"].values()))
    assert np.max(rc) - np.min(rc) < 0.05, f"ERC not balanced: {rc}"


def test_hrp_downweights_redundant_correlated_pair():
    """A and B are ~80% correlated; the independent C should get meaningful weight under HRP."""
    mat = _synth_matrix()
    w = P.weights_hrp(mat)
    wd = dict(zip(mat.columns, w))
    assert wd["C"] > 0.2, f"HRP starved the diversifier: {wd}"


def test_lot_multipliers_average_to_one():
    mat = _synth_matrix()
    w = P.weights_equal(mat)
    lots = P.lot_multipliers(w, mat.columns)
    assert all(abs(v - 1.0) < 1e-9 for v in lots.values())  # equal weight -> all 1.0x
    # general: multipliers average to 1.0 (they are w * N)
    w2 = P.weights_hrp(mat)
    lots2 = P.lot_multipliers(w2, mat.columns)
    assert abs(np.mean(list(lots2.values())) - 1.0) < 1e-9


def test_diversification_ratio_at_least_one():
    mat = _synth_matrix()
    for m in P.ALLOC_METHODS:
        cov, _ = P.shrink_cov_constant_corr(mat.values)
        w = P.ALLOC_METHODS[m](mat, cov=cov)
        met = P.portfolio_metrics(mat, w, cov=cov)
        assert met["diversification_ratio"] >= 0.999  # >=1 by construction (long-only)


def test_returns_matrix_build_and_align(tmp_path):
    """Two streams with disjoint trade days align on a daily grid with zero-fill."""
    s1 = [(datetime(2025, 1, 1, 10), 100.0), (datetime(2025, 1, 3, 10), -50.0)]
    s2 = [(datetime(2025, 1, 2, 10), 30.0),
          (datetime(2025, 1, 3, 10), 30.0), (datetime(2025, 1, 3, 12), 20.0)]  # two trades on Jan 3
    mat = P.build_returns_matrix({"X": s1, "Y": s2}, freq="D")
    assert list(mat.columns) == ["X", "Y"]
    assert mat.shape[0] == 3                       # Jan 1,2,3
    assert mat.loc["2025-01-02", "X"] == 0.0       # X flat that day
    assert mat.loc["2025-01-03", "Y"] == pytest.approx(50.0 / P.START_BALANCE)  # 30+20 summed


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
