"""Causal technical indicators for Phase-3 feature engineering.

Every function here is **causal**: the value at bar ``t`` depends only on bars ``<= t``. This is the
hard requirement that keeps features lookahead-free (see ``features.py`` for the regression test).

Smoothing follows MT5/Wilder conventions so the eventual MQL5 EA reproduces the same indicator
values: EMA uses ``adjust=False`` recursion; RSI/ATR/ADX use Wilder's RMA (``alpha = 1/n``). Wilder's
classic SMA seed differs from the ``ewm`` seed only during warmup, which is discarded downstream.

All functions take/return ``pandas`` Series/values indexed by bar order (NOT wall-clock); they operate
on the bar *sequence*, consistent with sparse event-time bars.
"""
from __future__ import annotations

import numpy as np
import pandas as pd


# ---------- moving averages ----------

def ema(s: pd.Series, n: int) -> pd.Series:
    """Exponential MA, MT5 convention (recursive, no bias correction)."""
    return s.ewm(span=n, adjust=False).mean()


def wilder_rma(s: pd.Series, n: int) -> pd.Series:
    """Wilder's running moving average (a.k.a. RMA / SMMA): alpha = 1/n."""
    return s.ewm(alpha=1.0 / n, adjust=False).mean()


# ---------- momentum ----------

def rsi(close: pd.Series, n: int = 14) -> pd.Series:
    """Wilder's RSI in [0, 100]."""
    delta = close.diff()
    gain = delta.clip(lower=0.0)
    loss = (-delta).clip(lower=0.0)
    avg_gain = wilder_rma(gain, n)
    avg_loss = wilder_rma(loss, n)
    rs = avg_gain / avg_loss
    out = 100.0 - 100.0 / (1.0 + rs)
    # avg_loss == 0 -> RSI 100 (all gains); avg_gain == avg_loss == 0 -> neutral 50.
    out = out.where(avg_loss != 0, 100.0)
    out = out.where(~((avg_gain == 0) & (avg_loss == 0)), 50.0)
    return out


# ---------- volatility ----------

def true_range(high: pd.Series, low: pd.Series, close: pd.Series) -> pd.Series:
    prev_close = close.shift(1)
    tr = pd.concat(
        [(high - low), (high - prev_close).abs(), (low - prev_close).abs()], axis=1
    ).max(axis=1)
    return tr


def atr(high: pd.Series, low: pd.Series, close: pd.Series, n: int = 14) -> pd.Series:
    return wilder_rma(true_range(high, low, close), n)


# ---------- directional movement ----------

def dmi_adx(
    high: pd.Series, low: pd.Series, close: pd.Series, n: int = 14
) -> tuple[pd.Series, pd.Series, pd.Series]:
    """Return (adx, plus_di, minus_di), all Wilder-smoothed, in [0, 100]."""
    up = high.diff()
    down = -low.diff()
    plus_dm = pd.Series(np.where((up > down) & (up > 0), up, 0.0), index=high.index)
    minus_dm = pd.Series(np.where((down > up) & (down > 0), down, 0.0), index=high.index)

    atr_n = wilder_rma(true_range(high, low, close), n)
    plus_di = 100.0 * wilder_rma(plus_dm, n) / atr_n
    minus_di = 100.0 * wilder_rma(minus_dm, n) / atr_n

    di_sum = (plus_di + minus_di).replace(0.0, np.nan)
    dx = 100.0 * (plus_di - minus_di).abs() / di_sum
    adx = wilder_rma(dx.fillna(0.0), n)
    return adx, plus_di, minus_di


# ---------- Ichimoku ----------

def ichimoku(
    high: pd.Series, low: pd.Series, tenkan: int = 9, kijun: int = 26, senkou_b: int = 52
) -> dict[str, pd.Series]:
    """Tenkan, Kijun, and the two Senkou spans.

    Senkou spans are shifted FORWARD by ``kijun``: the value plotted at bar ``t`` was computed from
    data at ``t - kijun`` — so reading the cloud at ``t`` uses only past data (causal).
    """
    conv = (high.rolling(tenkan).max() + low.rolling(tenkan).min()) / 2.0
    base = (high.rolling(kijun).max() + low.rolling(kijun).min()) / 2.0
    span_a = ((conv + base) / 2.0).shift(kijun)
    span_b = ((high.rolling(senkou_b).max() + low.rolling(senkou_b).min()) / 2.0).shift(kijun)
    return {"tenkan": conv, "kijun": base, "senkou_a": span_a, "senkou_b": span_b}


# ---------- rolling percentile ----------

def rolling_percentile(s: pd.Series, window: int) -> pd.Series:
    """Percentile rank in [0, 1] of the current value within the trailing ``window`` (incl. self)."""
    return s.rolling(window, min_periods=window).rank(pct=True)


# ---------- tick-based volume profile (one period, e.g. a day) ----------

def volume_profile_levels(
    price: np.ndarray, weight: np.ndarray, bins: int = 100, value_area: float = 0.70
) -> tuple[float, float, float]:
    """POC / VAH / VAL from a weighted price histogram (weight = tick_count; no real volume exists).

    Value area is grown from the POC bin outward, always taking the heavier adjacent side, until
    ``value_area`` of total weight is enclosed — the standard Market-Profile construction.
    Returns (poc, vah, val) as prices. NaNs if input is empty or degenerate.
    """
    price = np.asarray(price, dtype=float)
    weight = np.asarray(weight, dtype=float)
    mask = np.isfinite(price) & np.isfinite(weight) & (weight > 0)
    price, weight = price[mask], weight[mask]
    if price.size == 0:
        return (np.nan, np.nan, np.nan)
    lo, hi = price.min(), price.max()
    if hi <= lo:  # all trades at one price
        return (float(lo), float(hi), float(lo))

    edges = np.linspace(lo, hi, bins + 1)
    centers = (edges[:-1] + edges[1:]) / 2.0
    hist, _ = np.histogram(price, bins=edges, weights=weight)

    poc_idx = int(np.argmax(hist))
    total = hist.sum()
    target = value_area * total

    acc = hist[poc_idx]
    lo_idx = hi_idx = poc_idx
    while acc < target and (lo_idx > 0 or hi_idx < bins - 1):
        below = hist[lo_idx - 1] if lo_idx > 0 else -1.0
        above = hist[hi_idx + 1] if hi_idx < bins - 1 else -1.0
        if above >= below:
            hi_idx += 1
            acc += hist[hi_idx]
        else:
            lo_idx -= 1
            acc += hist[lo_idx]
    return (float(centers[poc_idx]), float(centers[hi_idx]), float(centers[lo_idx]))
