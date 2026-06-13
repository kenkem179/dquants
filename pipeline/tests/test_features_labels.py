"""Tests for Phase 3 features and Phase 4 labels — causality, ranges, triple-barrier logic."""
from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from pipeline import features as fe
from pipeline import labels as lb


def _synthetic_bars(n=4000, seed=3):
    """A few days of plausible M1 bars (random walk, positive prices)."""
    rng = np.random.default_rng(seed)
    ts = pd.date_range("2025-01-01", periods=n, freq="1min", tz=None)
    close = 100.0 + np.cumsum(rng.standard_normal(n)) * 0.5 + 50
    spread = np.abs(rng.standard_normal(n)) * 0.1 + 0.2
    high = close + np.abs(rng.standard_normal(n)) * 0.3
    low = close - np.abs(rng.standard_normal(n)) * 0.3
    open_ = close - rng.standard_normal(n) * 0.1
    return pd.DataFrame({
        "ts": ts, "open": open_, "high": np.maximum.reduce([high, open_, close]),
        "low": np.minimum.reduce([low, open_, close]), "close": close,
        "spread_mean": spread, "spread_max": spread * 1.5,
        "tick_count": rng.integers(1, 100, n),
    })


# ---------------- features ----------------

def test_feature_frame_has_expected_columns():
    f = fe.build_features(_synthetic_bars(), "M1")
    for col in ["ema_200_dist", "ema_compression", "rsi_14", "rsi_14_slope", "adx",
                "di_spread", "atr", "atr_pct", "dist_poc", "dist_kijun",
                "cloud_thickness", "hour", "dow", "session"]:
        assert col in f.columns
    assert len(f) == 4000


def test_atr_percentile_in_unit_range():
    f = fe.build_features(_synthetic_bars(), "M1")
    ap = f["atr_pct"].dropna()
    assert ap.between(0, 1).all()


def test_rsi_in_range():
    f = fe.build_features(_synthetic_bars(), "M1")
    assert f["rsi_14"].dropna().between(0, 100).all()


def test_prior_day_vp_is_nan_on_first_day():
    bars = _synthetic_bars(n=3000)  # ~2 days of M1
    f = fe.build_features(bars, "M1")
    first_day = bars["ts"].dt.date == bars["ts"].dt.date.iloc[0]
    # No prior day exists for day 1 -> POC-based distances must be NaN there.
    assert f.loc[first_day.to_numpy(), "dist_poc"].isna().all()
    # A later day should have valid prior-day levels.
    assert f["dist_poc"].notna().any()


def test_feature_frame_is_causal():
    """THE critical guard: truncating future bars must not change any past feature value."""
    bars = _synthetic_bars(n=4000)
    full = fe.build_features(bars, "M1")
    k = 3000
    trunc = fe.build_features(bars.iloc[:k].copy(), "M1")
    num_cols = full.select_dtypes(include=[float, "float64", "float32"]).columns
    a = full.iloc[:k][num_cols].to_numpy()
    b = trunc[num_cols].to_numpy()
    both = ~(np.isnan(a) | np.isnan(b))
    assert both.sum() > 0
    assert np.allclose(a[both], b[both], rtol=1e-9, atol=1e-9)


# ---------------- labels ----------------

def test_triple_barrier_tp_first():
    # Price jumps straight up after bar 0 -> TP must trigger (+1).
    n = 10
    close = pd.Series([100.0] + [100.0] * 9)
    high = pd.Series([100.0] + [200.0] * 9)   # huge upside reachable
    low = pd.Series([100.0] * n)
    atr = pd.Series([1.0] * n)
    lab = lb.triple_barrier(high, low, close, atr, tp_mult=2.0, sl_mult=2.0, horizon=5)
    assert lab[0] == 1.0


def test_triple_barrier_sl_first():
    n = 10
    close = pd.Series([100.0] * n)
    high = pd.Series([100.0] * n)
    low = pd.Series([100.0] + [50.0] * 9)     # downside hit
    atr = pd.Series([1.0] * n)
    lab = lb.triple_barrier(high, low, close, atr, tp_mult=2.0, sl_mult=2.0, horizon=5)
    assert lab[0] == -1.0


def test_triple_barrier_both_same_bar_is_pessimistic():
    n = 5
    close = pd.Series([100.0] * n)
    high = pd.Series([100.0, 200.0, 100.0, 100.0, 100.0])  # TP reachable...
    low = pd.Series([100.0, 50.0, 100.0, 100.0, 100.0])    # ...and SL, same bar
    atr = pd.Series([1.0] * n)
    lab = lb.triple_barrier(high, low, close, atr, tp_mult=2.0, sl_mult=2.0, horizon=3)
    assert lab[0] == -1.0  # ambiguous -> SL


def test_triple_barrier_timeout_zero_and_tail_nan():
    n = 20
    close = pd.Series([100.0] * n)
    high = pd.Series([100.2] * n)   # never reaches TP at +2*atr
    low = pd.Series([99.8] * n)     # never reaches SL at -2*atr
    atr = pd.Series([1.0] * n)
    lab = lb.triple_barrier(high, low, close, atr, tp_mult=2.0, sl_mult=2.0, horizon=5)
    assert lab[0] == 0.0                 # full horizon observed, no touch -> timeout
    assert np.isnan(lab[n - 1])          # last bar: horizon runs past end -> NaN


def test_forward_returns_and_label_columns():
    lab = lb.build_labels(_synthetic_bars(n=500))
    for col in ["fwd_ret_5", "fwd_ret_10", "fwd_ret_20", "fwd_ret_60", "hit_tp_before_sl"]:
        assert col in lab.columns
    # forward returns at the very end are NaN (no future bars)
    assert lab["fwd_ret_60"].iloc[-1] != lab["fwd_ret_60"].iloc[-1]  # NaN
    assert set(lab["hit_tp_before_sl"].dropna().unique()) <= {-1.0, 0.0, 1.0}
