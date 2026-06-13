"""Phase 4 — Label Factory.

Generate the supervised targets from M1/M3 bars:

* ``fwd_ret_{5,10,20,60}`` — simple forward return ``close(t+k)/close(t) - 1``.
* ``hit_tp_before_sl`` — triple-barrier label: from each bar, place a take-profit at
  ``close + tp_mult*ATR`` and a stop at ``close - sl_mult*ATR`` and look forward up to ``horizon``
  bars. Value: ``+1`` if TP is touched first, ``-1`` if SL is touched first, ``0`` on timeout, and
  ``NaN`` when the horizon runs past the end of data (outcome unobservable). If both barriers fall in
  the same future bar the outcome is ambiguous, so we resolve it pessimistically to ``-1`` — this
  never overstates an edge.

Labels deliberately look FORWARD (that is their job); features must not. Output keyed by ``ts`` in
``data/labels/labels_<symbol>_<tf>.parquet``.

Usage:  python -m pipeline.labels --symbol btcusd --timeframes M1 M3 --force
"""
from __future__ import annotations

import argparse
import logging
import sys
import time

import numpy as np
import pandas as pd

from . import config, indicators as ind

log = logging.getLogger("labels")

FWD_HORIZONS = [5, 10, 20, 60]
TP_MULT = 1.0
SL_MULT = 1.0
TB_HORIZON = 60
ATR_PERIOD = 14


def triple_barrier(
    high: pd.Series, low: pd.Series, close: pd.Series, atr: pd.Series,
    *, tp_mult: float, sl_mult: float, horizon: int,
) -> np.ndarray:
    """Vectorized first-touch triple barrier. Returns float array of {+1,-1,0,NaN}."""
    n = len(close)
    high_a, low_a = high.to_numpy(), low.to_numpy()
    tp = (close + tp_mult * atr).to_numpy()
    sl = (close - sl_mult * atr).to_numpy()

    label = np.zeros(n, dtype=float)
    resolved = np.zeros(n, dtype=bool)
    valid_level = np.isfinite(tp) & np.isfinite(sl)

    for hh in range(1, horizon + 1):
        fh = np.full(n, np.nan)
        fl = np.full(n, np.nan)
        fh[: n - hh] = high_a[hh:]
        fl[: n - hh] = low_a[hh:]
        live = (~resolved) & valid_level & np.isfinite(fh)
        tp_hit = live & (fh >= tp)
        sl_hit = live & (fl <= sl)
        only_tp = tp_hit & ~sl_hit
        sl_or_both = sl_hit  # both-in-one-bar -> pessimistic SL
        label[only_tp] = 1.0
        label[sl_or_both] = -1.0
        resolved[only_tp | sl_or_both] = True

    # Unresolved bars whose horizon ran past the end of data are unobservable -> NaN.
    idx = np.arange(n)
    incomplete = (~resolved) & (idx > n - 1 - horizon)
    label[incomplete] = np.nan
    label[~valid_level] = np.nan
    return label


def build_labels(
    bars: pd.DataFrame, *, tp_mult: float = TP_MULT, sl_mult: float = SL_MULT,
    horizon: int = TB_HORIZON,
) -> pd.DataFrame:
    bars = bars.sort_values("ts").reset_index(drop=True)
    c = bars["close"]
    out = pd.DataFrame({"ts": bars["ts"]})
    for k in FWD_HORIZONS:
        out[f"fwd_ret_{k}"] = c.shift(-k) / c - 1.0
    atr = ind.atr(bars["high"], bars["low"], c, ATR_PERIOD)
    out["hit_tp_before_sl"] = triple_barrier(
        bars["high"], bars["low"], c, atr,
        tp_mult=tp_mult, sl_mult=sl_mult, horizon=horizon,
    )
    return out


def _load_bars(symbol: str, timeframe: str) -> pd.DataFrame:
    years = sorted(config.discover_raw_files(symbol))
    frames = [pd.read_parquet(config.bars_path(symbol, timeframe, y))
              for y in years if config.bars_path(symbol, timeframe, y).exists()]
    if not frames:
        raise FileNotFoundError(f"No bars for {symbol} {timeframe} — build bars first")
    return pd.concat(frames, ignore_index=True).sort_values("ts").reset_index(drop=True)


def build_symbol_timeframe(
    symbol: str, timeframe: str, *, overwrite: bool = False,
    tp_mult: float = TP_MULT, sl_mult: float = SL_MULT, horizon: int = TB_HORIZON,
) -> dict:
    dst = config.labels_path(symbol, timeframe)
    if dst.exists() and not overwrite:
        raise FileExistsError(f"{dst} exists (use --force)")
    dst.parent.mkdir(parents=True, exist_ok=True)

    t0 = time.perf_counter()
    bars = _load_bars(symbol, timeframe)
    lab = build_labels(bars, tp_mult=tp_mult, sl_mult=sl_mult, horizon=horizon)
    tmp = dst.with_suffix(".parquet.tmp")
    lab.to_parquet(tmp, compression="zstd", index=False)
    tmp.replace(dst)

    tb = lab["hit_tp_before_sl"]
    dist = tb.value_counts(dropna=False).to_dict()
    elapsed = round(time.perf_counter() - t0, 1)
    log.info("[%s %s] %s rows | triple-barrier tp=%s sl=%s H=%s -> "
             "+1:%s  -1:%s  0:%s  NaN:%s | %ss",
             symbol, timeframe, f"{len(lab):,}", tp_mult, sl_mult, horizon,
             int(dist.get(1.0, 0)), int(dist.get(-1.0, 0)), int(dist.get(0.0, 0)),
             int(tb.isna().sum()), elapsed)
    return dict(symbol=symbol, timeframe=timeframe, rows=len(lab), elapsed_s=elapsed)


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Phase 4 — build labels from bars")
    p.add_argument("--symbol", default="btcusd")
    p.add_argument("--timeframes", nargs="+", default=["M1", "M3"], choices=["M1", "M3"])
    p.add_argument("--tp-mult", type=float, default=TP_MULT)
    p.add_argument("--sl-mult", type=float, default=SL_MULT)
    p.add_argument("--horizon", type=int, default=TB_HORIZON)
    p.add_argument("--force", action="store_true")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args = _parse_args(argv)
    for tf in args.timeframes:
        dst = config.labels_path(args.symbol, tf)
        if dst.exists() and not args.force:
            log.info("[%s %s] %s exists — skipping (use --force)", args.symbol, tf, dst.name)
            continue
        build_symbol_timeframe(args.symbol, tf, overwrite=args.force,
                               tp_mult=args.tp_mult, sl_mult=args.sl_mult, horizon=args.horizon)
    return 0


if __name__ == "__main__":
    sys.exit(main())
