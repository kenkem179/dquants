#!/usr/bin/env python3
"""Validate whether a bar-level tick-count profile is stable enough to study.

This is a reliability screen, not a profitability backtest. It compares daily
POC/VAH/VAL levels built from M3/M1 bars under deterministic perturbations of
the tick-count proxy.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]


def load_bars(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    df["ts"] = pd.to_datetime(df["ts_ms"], unit="ms", utc=True)
    df["date"] = df["ts"].dt.date
    return df


def profile_levels(prices: np.ndarray, weights: np.ndarray, bins: int = 48) -> tuple[float, float, float]:
    if len(prices) < 10 or np.nanmax(prices) <= np.nanmin(prices):
        return (np.nan, np.nan, np.nan)
    hist, edges = np.histogram(prices, bins=bins, weights=weights)
    centers = (edges[:-1] + edges[1:]) / 2.0
    total = hist.sum()
    if total <= 0:
        return (np.nan, np.nan, np.nan)
    poc_i = int(hist.argmax())
    selected = {poc_i}
    mass = hist[poc_i]
    left = poc_i - 1
    right = poc_i + 1
    target = total * 0.70
    while mass < target and (left >= 0 or right < len(hist)):
        left_mass = hist[left] if left >= 0 else -1
        right_mass = hist[right] if right < len(hist) else -1
        if right_mass >= left_mass:
            selected.add(right)
            mass += max(right_mass, 0)
            right += 1
        else:
            selected.add(left)
            mass += max(left_mass, 0)
            left -= 1
    idx = sorted(selected)
    return (float(centers[poc_i]), float(centers[max(idx)]), float(centers[min(idx)]))


def deterministic_keep(ts_ms: pd.Series, salt: int, keep: float) -> np.ndarray:
    # Stable pseudo-random mask from timestamp; avoids non-reproducible RNG.
    x = ((ts_ms.astype("int64") // 60000) * 1103515245 + salt) & 0x7FFFFFFF
    return (x % 10000) < int(keep * 10000)


def daily_compare(df: pd.DataFrame, min_bars: int, bins: int) -> pd.DataFrame:
    rows = []
    for date, g in df.groupby("date", sort=True):
        if len(g) < min_bars:
            continue
        prices = g["close"].to_numpy(float)
        full_w = g["tick_count"].to_numpy(float)
        ref = profile_levels(prices, full_w, bins=bins)
        variants = {
            "unweighted": np.ones(len(g)),
            "drop30_a": full_w[deterministic_keep(g["ts_ms"], 17, 0.70)],
            "drop30_b": full_w[deterministic_keep(g["ts_ms"], 97, 0.70)],
            "filter_low_activity": full_w[g["tick_count"] >= g["tick_count"].quantile(0.20)],
        }
        variant_prices = {
            "unweighted": prices,
            "drop30_a": prices[deterministic_keep(g["ts_ms"], 17, 0.70)],
            "drop30_b": prices[deterministic_keep(g["ts_ms"], 97, 0.70)],
            "filter_low_activity": prices[g["tick_count"] >= g["tick_count"].quantile(0.20)],
        }
        day_range = max(float(g["high"].max() - g["low"].min()), 1e-9)
        close = float(g["close"].iloc[-1])
        for name, weights in variants.items():
            levels = profile_levels(variant_prices[name], weights, bins=bins)
            rows.append(
                {
                    "date": str(date),
                    "variant": name,
                    "bars": len(g),
                    "tick_count": int(g["tick_count"].sum()),
                    "day_range": day_range,
                    "close": close,
                    "poc_ref": ref[0],
                    "vah_ref": ref[1],
                    "val_ref": ref[2],
                    "poc_var": levels[0],
                    "vah_var": levels[1],
                    "val_var": levels[2],
                    "poc_shift_range": abs(levels[0] - ref[0]) / day_range,
                    "vah_shift_range": abs(levels[1] - ref[1]) / day_range,
                    "val_shift_range": abs(levels[2] - ref[2]) / day_range,
                    "poc_shift_bps": abs(levels[0] - ref[0]) / close * 10000,
                }
            )
    return pd.DataFrame(rows)


def summary(cmp: pd.DataFrame) -> pd.DataFrame:
    parts = []
    for variant, g in cmp.groupby("variant"):
        parts.append(
            {
                "variant": variant,
                "days": len(g),
                "poc_shift_range_median": g["poc_shift_range"].median(),
                "poc_shift_range_p90": g["poc_shift_range"].quantile(0.90),
                "vah_shift_range_median": g["vah_shift_range"].median(),
                "val_shift_range_median": g["val_shift_range"].median(),
                "poc_shift_bps_median": g["poc_shift_bps"].median(),
                "unstable_days_poc_gt_10pct_range": (g["poc_shift_range"] > 0.10).mean(),
            }
        )
    return pd.DataFrame(parts).sort_values("variant")


def df_to_markdown(df: pd.DataFrame, floatfmt: str = ".4f") -> str:
    if df.empty:
        return "(empty)"
    cols = list(df.columns)
    lines = ["| " + " | ".join(cols) + " |", "|" + "|".join(["---"] * len(cols)) + "|"]
    for _, row in df.iterrows():
        vals = []
        for col in cols:
            val = row[col]
            if isinstance(val, float):
                vals.append(format(val, floatfmt))
            else:
                vals.append(str(val))
        lines.append("| " + " | ".join(vals) + " |")
    return "\n".join(lines)


def write_report(out_md: Path, bars_path: Path, cmp: pd.DataFrame, summ: pd.DataFrame, focus: str) -> None:
    if cmp.empty:
        verdict = "BLOCKED: no comparable daily profiles were produced."
    else:
        worst = summ["unstable_days_poc_gt_10pct_range"].max()
        p90 = summ["poc_shift_range_p90"].max()
        if worst <= 0.20 and p90 <= 0.25:
            verdict = "PASS-WARN: POC is usually stable under local perturbations, but still quote-activity only."
        else:
            verdict = "FAIL/WARN: POC shifts materially under local perturbations; do not build new VP alpha yet."

    md = f"""# Tick-Profile Proxy Validation - {focus}

Generated by `research/data_quality/validate_tick_profile_proxy.py`.

## Codex-Step-2 Verdict

{verdict}

This validates only **local stability of the MT5/Exness tick-count proxy**. It does **not** validate real traded
volume. A second broker or exchange-volume proxy remains required before claiming real-volume profile edge.

## Inputs

- Bars: `{bars_path}`
- Profile basis: close price weighted by `tick_count`
- Variants: unweighted bars, two deterministic 30% bar drops, and bottom-20% activity filter

## Summary

{df_to_markdown(summ, ".4f")}

## Decision Use

- If PASS-WARN: BTC M3/MasterVP may proceed to event-taxonomy research, but every VP feature remains labeled
  quote-activity VP.
- If FAIL/WARN: stop BTC M3 VP alpha work and acquire/compare a better feed first.
"""
    out_md.write_text(md)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bars", required=True, type=Path)
    ap.add_argument("--focus", default="unknown")
    ap.add_argument("--out-dir", default=ROOT / "research" / "data_quality", type=Path)
    ap.add_argument("--min-bars", default=120, type=int)
    ap.add_argument("--bins", default=48, type=int)
    args = ap.parse_args()

    df = load_bars(args.bars)
    cmp = daily_compare(df, min_bars=args.min_bars, bins=args.bins)
    summ = summary(cmp)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    stem = args.focus.lower().replace(" ", "_").replace("/", "_")
    cmp_path = args.out_dir / f"{stem}_tick_profile_proxy_daily.csv"
    sum_path = args.out_dir / f"{stem}_tick_profile_proxy_summary.csv"
    md_path = args.out_dir / f"{stem.upper()}_TICK_PROFILE_PROXY_VALIDATION.md"
    cmp.to_csv(cmp_path, index=False)
    summ.to_csv(sum_path, index=False)
    write_report(md_path, args.bars, cmp, summ, args.focus)
    print(md_path)
    print(sum_path)
    print(cmp_path)


if __name__ == "__main__":
    main()
