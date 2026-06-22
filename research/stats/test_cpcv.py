#!/usr/bin/env python3
"""Tests for CPCV. Run: pytest research/stats/test_cpcv.py"""
import math
import os
import sys

import numpy as np
import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from stats import cpcv  # noqa: E402


def test_n_backtest_paths_formula():
    # C(8,2)*2/8 = 28*2/8 = 7
    assert cpcv.n_backtest_paths(8, 2) == 7
    # C(6,3)*3/6 = 20*3/6 = 10
    assert cpcv.n_backtest_paths(6, 3) == 10


def test_splits_train_test_disjoint_and_count():
    n = 200
    splits = list(cpcv.cpcv_splits(n, n_groups=6, test_size=2, embargo=0.0))
    assert len(splits) == math.comb(6, 2)  # 15 combinations
    for train, test in splits:
        assert set(train).isdisjoint(set(test))            # purge: no overlap
        assert len(test) > 0 and len(train) > 0


def test_embargo_removes_post_test_indices():
    n = 100
    no_emb = list(cpcv.cpcv_splits(n, n_groups=5, test_size=1, embargo=0.0))
    emb = list(cpcv.cpcv_splits(n, n_groups=5, test_size=1, embargo=0.1))
    # embargo can only REMOVE training indices, never add
    for (tr0, te0), (tr1, te1) in zip(no_emb, emb):
        assert np.array_equal(te0, te1)
        assert len(tr1) <= len(tr0)
    # at least one split must lose training rows to the embargo
    assert any(len(tr1) < len(tr0) for (tr0, _), (tr1, _) in zip(no_emb, emb))


def test_pbo_overfit_detection_on_noise():
    """Pure-noise configs: the IS-best should NOT generalize -> PBO near/above 0.5."""
    rng = np.random.default_rng(1)
    M = rng.normal(0, 1, size=(240, 30))  # 30 noise configs
    rep = cpcv.cpcv_pbo(M, n_groups=8, test_size=2, embargo=0.0)
    assert 0.0 <= rep["pbo"] <= 1.0
    assert rep["pbo"] > 0.35  # noise selection is far from reliable


def test_pbo_low_for_genuinely_dominant_config():
    """One config with a real, stationary edge should generalize -> low PBO."""
    rng = np.random.default_rng(2)
    M = rng.normal(0, 1, size=(240, 20))
    M[:, 0] += 0.6  # config 0 has a true positive mean every period
    rep = cpcv.cpcv_pbo(M, n_groups=8, test_size=2, embargo=0.0)
    assert rep["pbo"] < 0.1


def test_path_stats_positive_edge():
    rng = np.random.default_rng(3)
    r = rng.normal(0.05, 1.0, 300)  # mild positive edge
    st = cpcv.cpcv_path_stats(r, n_groups=8, test_size=2)
    assert st["n_paths"] > 0
    assert -1.0 < st["sharpe_mean"] < 1.0
    assert 0.0 <= st["frac_positive"] <= 1.0


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
