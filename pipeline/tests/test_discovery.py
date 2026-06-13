"""Tests for Phase 5 discovery pure-logic helpers (the ML steps are validated on real data)."""
from __future__ import annotations

import numpy as np
import pandas as pd

from research.discovery import discover as dc


def test_redundancy_groups_unions_correlated():
    cols = ["a", "b", "c", "d"]
    # a~b strongly, c~d strongly, no cross-correlation
    m = pd.DataFrame(np.eye(4), index=cols, columns=cols)
    m.loc["a", "b"] = m.loc["b", "a"] = 0.95
    m.loc["c", "d"] = m.loc["d", "c"] = 0.92
    groups = dc.redundancy_groups(m, threshold=0.9)
    assert sorted(map(sorted, groups)) == [["a", "b"], ["c", "d"]]


def test_redundancy_groups_transitive_chain():
    cols = ["a", "b", "c"]
    m = pd.DataFrame(np.eye(3), index=cols, columns=cols)
    m.loc["a", "b"] = m.loc["b", "a"] = 0.95
    m.loc["b", "c"] = m.loc["c", "b"] = 0.95   # a-b and b-c -> {a,b,c}
    groups = dc.redundancy_groups(m, threshold=0.9)
    assert sorted(groups[0]) == ["a", "b", "c"]


def test_redundancy_none_when_below_threshold():
    cols = ["a", "b"]
    m = pd.DataFrame([[1.0, 0.5], [0.5, 1.0]], index=cols, columns=cols)
    assert dc.redundancy_groups(m, threshold=0.9) == []


def test_representative_reduction_keeps_priority_and_avoids_chaining():
    # a~b~c chain (a-b 0.95, b-c 0.95) but a-c only 0.5. Single-linkage would merge all three;
    # greedy reduction keeps a (priority), drops b (≥0.9 with a), keeps c (only 0.5 with a).
    cols = ["a", "b", "c"]
    m = pd.DataFrame(np.eye(3), index=cols, columns=cols)
    m.loc["a", "b"] = m.loc["b", "a"] = 0.95
    m.loc["b", "c"] = m.loc["c", "b"] = 0.95
    m.loc["a", "c"] = m.loc["c", "a"] = 0.5
    kept, dropped = dc.representative_reduction(m, threshold=0.9, priority=["a", "b", "c"])
    assert kept == ["a", "c"]
    assert dropped == {"b": "a"}


def test_representative_reduction_no_redundancy():
    cols = ["a", "b"]
    m = pd.DataFrame([[1.0, 0.3], [0.3, 1.0]], index=cols, columns=cols)
    kept, dropped = dc.representative_reduction(m, threshold=0.9)
    assert set(kept) == {"a", "b"} and dropped == {}


def test_name_regimes_assigns_all_five_uniquely():
    centroids = pd.DataFrame({
        "adx": [40, 22, 12, 18, 25],
        "atr_pct": [0.6, 0.5, 0.15, 0.9, 0.55],
        "ema_compression": [0.02, 0.01, 0.002, 0.03, 0.015],
        "di_spread": [30, 5, 1, -2, -25],
    }, index=[0, 1, 2, 3, 4])
    mapping = dc.name_regimes(centroids)
    assert set(mapping.values()) == set(dc.REGIME_NAMES)
    assert mapping[2] == "Compression"   # lowest adx + atr_pct
    assert mapping[3] == "Expansion"     # highest atr_pct (of the rest)
    assert mapping[0] == "Strong Trend"  # highest adx (of the rest)


def test_sign_stability():
    assert dc.sign_stability({2024: 0.05, 2025: 0.04, 2026: 0.06}) == "stable+"
    assert dc.sign_stability({2024: -0.05, 2025: -0.04}) == "stable-"
    assert dc.sign_stability({2024: 0.05, 2025: -0.04}) == "unstable"
    # values below min_abs are ignored as noise
    assert dc.sign_stability({2024: 0.05, 2025: 0.0001}) == "stable+"


def test_feature_columns_excludes_ids_and_labels():
    df = pd.DataFrame(columns=[
        "ts", "close", "ema_12_dist", "rsi_14", "fwd_ret_5", "fwd_ret_20",
        "hit_tp_before_sl", "tp_first",
    ])
    cols = dc.feature_columns(df)
    assert "ema_12_dist" in cols and "rsi_14" in cols
    for excluded in ["ts", "close", "fwd_ret_5", "fwd_ret_20", "hit_tp_before_sl", "tp_first"]:
        assert excluded not in cols
