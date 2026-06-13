"""Phase 3 (part 2) — Feature Factory.

Build the causal feature set from M1/M3 bars: trend (EMA), momentum (RSI), directional (ADX/DI),
volatility (ATR), structure (tick volume profile), Ichimoku, and time-of-day. All years for a
timeframe are concatenated in ts order so indicators warm up exactly once.

Causality is the contract: every feature at bar ``t`` uses only bars ``<= t`` (verified by
``test_features.py::test_feature_frame_is_causal``). The tick volume profile uses the *prior*
completed day's POC/VAH/VAL — both how those levels are traded and trivially lookahead-free.

Output: ``data/features/features_<symbol>_<tf>.parquet`` keyed by ``ts`` (plus ``close``, ``atr`` for
downstream convenience). Warmup rows (leading, until EMA200 / ATR-percentile window fill) carry NaNs
by design and are reported, not dropped.

Usage:  python -m pipeline.features --symbol btcusd --timeframes M1 M3 --force
"""
from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

from . import config, indicators as ind

log = logging.getLogger("features")

EMA_PERIODS = [12, 25, 50, 75, 100, 200]
RSI_PERIODS = [7, 14, 21]
ADX_PERIOD = 14
ATR_PERIOD = 14
SLOPE_K = 3                       # bars used for slope/acceleration deltas
# Roughly one trading day of bars, for the ATR percentile window.
ATR_PCT_WINDOW = {"M1": 1440, "M3": 480}
VP_BINS = 100
SESSIONS = [(0, 7, "asia"), (7, 13, "london"), (13, 21, "ny"), (21, 24, "late")]


def _session(hour: int) -> str:
    for lo, hi, name in SESSIONS:
        if lo <= hour < hi:
            return name
    return "late"


def _prior_day_vp(bars: pd.DataFrame) -> pd.DataFrame:
    """POC/VAH/VAL per day, then shifted to the PRIOR day and merged onto each bar (causal)."""
    typ = (bars["high"] + bars["low"] + bars["close"]) / 3.0
    tmp = pd.DataFrame({"date": bars["ts"].dt.date, "typ": typ, "w": bars["tick_count"]})
    rows = []
    for date, g in tmp.groupby("date", sort=True):
        poc, vah, val = ind.volume_profile_levels(g["typ"].to_numpy(), g["w"].to_numpy(), bins=VP_BINS)
        rows.append((date, poc, vah, val))
    daily = pd.DataFrame(rows, columns=["date", "poc", "vah", "val"]).sort_values("date")
    daily[["poc", "vah", "val"]] = daily[["poc", "vah", "val"]].shift(1)  # use prior day's levels
    merged = pd.DataFrame({"date": bars["ts"].dt.date}).merge(daily, on="date", how="left")
    return merged[["poc", "vah", "val"]].reset_index(drop=True)


def build_features(bars: pd.DataFrame, timeframe: str) -> pd.DataFrame:
    """bars: DataFrame with ts, open, high, low, close, spread_*, tick_count (ts-sorted)."""
    bars = bars.sort_values("ts").reset_index(drop=True)
    h, l, c = bars["high"], bars["low"], bars["close"]
    f = pd.DataFrame({"ts": bars["ts"], "close": c})

    # --- Trend: EMA value / distance / slope, plus compression across the ribbon ---
    ema_cols = {}
    for n in EMA_PERIODS:
        e = ind.ema(c, n)
        ema_cols[n] = e
        f[f"ema_{n}_dist"] = (c - e) / c
        f[f"ema_{n}_slope"] = e.pct_change(SLOPE_K)
    ema_df = pd.DataFrame(ema_cols)
    f["ema_compression"] = (ema_df.max(axis=1) - ema_df.min(axis=1)) / c

    # --- Momentum: RSI value / slope / acceleration ---
    for n in RSI_PERIODS:
        r = ind.rsi(c, n)
        f[f"rsi_{n}"] = r
        slope = r.diff(SLOPE_K)
        f[f"rsi_{n}_slope"] = slope
        f[f"rsi_{n}_accel"] = slope.diff(SLOPE_K)

    # --- Directional movement ---
    adx, plus_di, minus_di = ind.dmi_adx(h, l, c, ADX_PERIOD)
    f["adx"] = adx
    f["di_plus"] = plus_di
    f["di_minus"] = minus_di
    f["di_spread"] = plus_di - minus_di
    f["adx_slope"] = adx.diff(SLOPE_K)            # ADX trend
    f["adx_accel"] = adx.diff(SLOPE_K).diff(SLOPE_K)

    # --- Volatility ---
    a = ind.atr(h, l, c, ATR_PERIOD)
    f["atr"] = a
    f["atr_slope"] = a.pct_change(SLOPE_K)
    f["atr_pct"] = ind.rolling_percentile(a, ATR_PCT_WINDOW[timeframe])

    # --- Structure: prior-day tick volume profile ---
    vp = _prior_day_vp(bars)
    f["dist_poc"] = (c - vp["poc"]) / c
    f["dist_vah"] = (c - vp["vah"]) / c
    f["dist_val"] = (c - vp["val"]) / c

    # --- Ichimoku ---
    ich = ind.ichimoku(h, l)
    f["dist_tenkan"] = (c - ich["tenkan"]) / c
    f["dist_kijun"] = (c - ich["kijun"]) / c
    cloud_top = pd.concat([ich["senkou_a"], ich["senkou_b"]], axis=1).max(axis=1)
    cloud_bot = pd.concat([ich["senkou_a"], ich["senkou_b"]], axis=1).min(axis=1)
    f["cloud_thickness"] = (ich["senkou_a"] - ich["senkou_b"]).abs() / c
    f["dist_cloud"] = np.where(c > cloud_top, (c - cloud_top) / c,
                       np.where(c < cloud_bot, (c - cloud_bot) / c, 0.0))

    # --- Time ---
    hour = bars["ts"].dt.hour
    f["hour"] = hour.astype("int16")
    f["dow"] = bars["ts"].dt.dayofweek.astype("int16")
    f["session"] = hour.map(_session).astype("category")
    return f


def _load_bars(symbol: str, timeframe: str) -> pd.DataFrame:
    years = sorted(config.discover_raw_files(symbol))
    frames = []
    for y in years:
        p = config.bars_path(symbol, timeframe, y)
        if p.exists():
            frames.append(pd.read_parquet(p))
    if not frames:
        raise FileNotFoundError(
            f"No bars for {symbol} {timeframe} — run /quant-build-features (build_bars) first"
        )
    return pd.concat(frames, ignore_index=True).sort_values("ts").reset_index(drop=True)


def build_symbol_timeframe(symbol: str, timeframe: str, *, overwrite: bool = False) -> dict:
    dst = config.features_path(symbol, timeframe)
    if dst.exists() and not overwrite:
        raise FileExistsError(f"{dst} exists (use --force)")
    dst.parent.mkdir(parents=True, exist_ok=True)

    t0 = time.perf_counter()
    bars = _load_bars(symbol, timeframe)
    feats = build_features(bars, timeframe)
    tmp = dst.with_suffix(".parquet.tmp")
    feats.to_parquet(tmp, compression="zstd", index=False)
    tmp.replace(dst)

    feature_cols = [col for col in feats.columns if col not in ("ts", "close")]
    warmup = int(feats[feature_cols].isna().any(axis=1).to_numpy().argmin())  # first all-valid row
    elapsed = round(time.perf_counter() - t0, 1)
    stats = dict(symbol=symbol, timeframe=timeframe, rows=len(feats),
                 n_features=len(feature_cols), warmup_rows=warmup, elapsed_s=elapsed)
    log.info("[%s %s] %s rows, %s features, warmup≈%s bars, %ss",
             symbol, timeframe, f"{len(feats):,}", len(feature_cols), f"{warmup:,}", elapsed)
    return stats


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Phase 3 — build features from bars")
    p.add_argument("--symbol", default="btcusd")
    p.add_argument("--timeframes", nargs="+", default=["M1", "M3"], choices=["M1", "M3"])
    p.add_argument("--force", action="store_true")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args = _parse_args(argv)
    results = []
    for tf in args.timeframes:
        dst = config.features_path(args.symbol, tf)
        if dst.exists() and not args.force:
            log.info("[%s %s] %s exists — skipping (use --force)", args.symbol, tf, dst.name)
            continue
        results.append(build_symbol_timeframe(args.symbol, tf, overwrite=args.force))
    if results:
        log.info("\n=== Features built ===")
        for r in results:
            log.info("  %s %s -> %s", r["symbol"], r["timeframe"],
                     config.features_path(r["symbol"], r["timeframe"]).name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
