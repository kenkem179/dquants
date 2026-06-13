"""Tests for causal indicators — correctness, ranges, and the no-lookahead property."""
from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from pipeline import indicators as ind


@pytest.fixture()
def trend_up():
    close = pd.Series(np.linspace(100, 200, 300))
    high = close + 1.0
    low = close - 1.0
    return high, low, close


def test_ema_matches_recursive():
    s = pd.Series([1.0, 2.0, 3.0, 4.0])
    out = ind.ema(s, 2)
    # adjust=False EMA, alpha = 2/(2+1) = 2/3
    a = 2 / 3
    expected = [1.0]
    for x in s.iloc[1:]:
        expected.append(a * x + (1 - a) * expected[-1])
    assert np.allclose(out.values, expected)


def test_wilder_rma_recursion():
    s = pd.Series([10.0, 11.0, 12.0, 13.0])
    out = ind.wilder_rma(s, 4)
    a = 1 / 4
    exp = [10.0]
    for x in s.iloc[1:]:
        exp.append(a * x + (1 - a) * exp[-1])
    assert np.allclose(out.values, exp)


def test_rsi_all_gains_is_100(trend_up):
    _, _, close = trend_up
    r = ind.rsi(close, 14).dropna()
    assert (r > 99.9).all()  # monotonically rising -> RSI pinned near 100


def test_rsi_range():
    rng = np.random.default_rng(0)
    close = pd.Series(100 + np.cumsum(rng.standard_normal(500)))
    r = ind.rsi(close, 14).dropna()
    assert r.between(0, 100).all()


def test_true_range_example():
    high = pd.Series([10.0, 12.0])
    low = pd.Series([8.0, 9.0])
    close = pd.Series([9.0, 11.0])
    tr = ind.true_range(high, low, close)
    # bar 1: max(12-9, |12-9|, |9-9|) = max(3,3,0) = 3
    assert tr.iloc[1] == 3.0


def test_atr_positive(trend_up):
    high, low, close = trend_up
    a = ind.atr(high, low, close, 14).dropna()
    assert (a > 0).all()


def test_dmi_uptrend_plus_di_dominates(trend_up):
    high, low, close = trend_up
    adx, plus_di, minus_di = ind.dmi_adx(high, low, close, 14)
    tail = slice(-50, None)
    assert plus_di.iloc[tail].mean() > minus_di.iloc[tail].mean()
    for s in (adx, plus_di, minus_di):
        assert s.dropna().between(0, 100).all()


def test_ichimoku_tenkan_is_midpoint():
    high = pd.Series(np.arange(1, 21, dtype=float))
    low = high - 1.0
    ich = ind.ichimoku(high, low, tenkan=9, kijun=26, senkou_b=52)
    # tenkan at idx 9 = (max(high[1..9]) + min(low[1..9]))/2 = (10 + 1)/2 = 5.5
    assert ich["tenkan"].iloc[9] == pytest.approx(5.5)


def test_ichimoku_senkou_is_forward_shifted_causal():
    rng = np.random.default_rng(1)
    high = pd.Series(100 + np.cumsum(rng.standard_normal(200)) + 1)
    low = high - 2.0
    ich = ind.ichimoku(high, low)
    conv = (high.rolling(9).max() + low.rolling(9).min()) / 2
    base = (high.rolling(26).max() + low.rolling(26).min()) / 2
    raw_a = (conv + base) / 2
    # senkou_a plotted at t must equal the raw value from t-26 (uses only past data)
    t = 120
    assert ich["senkou_a"].iloc[t] == pytest.approx(raw_a.iloc[t - 26])


def test_rolling_percentile_known():
    s = pd.Series([1.0, 2.0, 3.0, 4.0, 5.0])
    p = ind.rolling_percentile(s, 3)
    assert np.isnan(p.iloc[1])           # window not full
    assert p.iloc[2] == pytest.approx(1.0)  # 3 is largest of [1,2,3]
    assert p.iloc[4] == pytest.approx(1.0)  # 5 is largest of [3,4,5]


def test_volume_profile_poc_and_value_area():
    # Heavy weight concentrated at price 100; sparse tails.
    price = np.array([90, 95, 100, 100, 100, 105, 110], dtype=float)
    weight = np.array([1, 1, 50, 50, 50, 1, 1], dtype=float)
    poc, vah, val = ind.volume_profile_levels(price, weight, bins=20)
    assert 99 <= poc <= 101
    assert val <= poc <= vah
    assert val >= 90 and vah <= 110


def test_volume_profile_degenerate_single_price():
    poc, vah, val = ind.volume_profile_levels(
        np.array([100.0, 100.0]), np.array([5.0, 5.0]), bins=20
    )
    assert poc == 100.0 and vah == 100.0 and val == 100.0


def test_volume_profile_empty():
    poc, vah, val = ind.volume_profile_levels(np.array([]), np.array([]))
    assert np.isnan(poc) and np.isnan(vah) and np.isnan(val)


# ---- the no-lookahead property: appending FUTURE bars must not change PAST indicator values ----

@pytest.mark.parametrize("fn", [
    lambda h, l, c: ind.ema(c, 12),
    lambda h, l, c: ind.rsi(c, 14),
    lambda h, l, c: ind.atr(h, l, c, 14),
    lambda h, l, c: ind.dmi_adx(h, l, c, 14)[0],
    lambda h, l, c: ind.ichimoku(h, l)["senkou_a"],
    lambda h, l, c: ind.rolling_percentile(ind.atr(h, l, c, 14), 50),
])
def test_indicator_is_causal(fn):
    rng = np.random.default_rng(7)
    close = pd.Series(100 + np.cumsum(rng.standard_normal(400)))
    high, low = close + 0.5, close - 0.5
    full = fn(high, low, close)
    k = 300
    truncated = fn(high.iloc[:k], low.iloc[:k], close.iloc[:k])
    # Values up to k must be identical whether or not future bars exist.
    a = full.iloc[:k].to_numpy()
    b = truncated.to_numpy()
    both = ~(np.isnan(a) | np.isnan(b))
    assert np.allclose(a[both], b[both])
    assert both.sum() > 0
