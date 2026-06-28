#!/usr/bin/env python3
"""Join KenKem M1 trades to causal tick-activity VP context.

This is Codex-Step-3: an audit to decide whether VP belongs in KenKem at all.
It does not modify strategy logic.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
BARS = ROOT / "cpp_core" / "tools" / "bars_xauusd_2024_2026_m1.csv"
TRADES = ROOT / "cpp_core" / "tools" / "trades_kenkem_lock_autopsy.csv"
OUT_DIR = ROOT / "research" / "kenkem_parity" / "vp_entry_audit"


def profile_levels(g: pd.DataFrame, bins: int = 64) -> tuple[float, float, float]:
    prices = g["close"].to_numpy(float)
    weights = g["tick_count"].to_numpy(float)
    if len(g) < 30 or prices.max() <= prices.min() or weights.sum() <= 0:
        return (np.nan, np.nan, np.nan)
    hist, edges = np.histogram(prices, bins=bins, weights=weights)
    centers = (edges[:-1] + edges[1:]) / 2.0
    poc_i = int(hist.argmax())
    selected = {poc_i}
    mass = hist[poc_i]
    total = hist.sum()
    left = poc_i - 1
    right = poc_i + 1
    while mass < total * 0.70 and (left >= 0 or right < len(hist)):
        lm = hist[left] if left >= 0 else -1
        rm = hist[right] if right < len(hist) else -1
        if rm >= lm:
            selected.add(right)
            mass += max(rm, 0)
            right += 1
        else:
            selected.add(left)
            mass += max(lm, 0)
            left -= 1
    idx = sorted(selected)
    return (float(centers[poc_i]), float(centers[max(idx)]), float(centers[min(idx)]))


def trade_context(bars: pd.DataFrame, trade: pd.Series, lookback: int) -> dict[str, float | str]:
    t = trade["entry_ts"]
    hist = bars[bars["ts"] < t].tail(lookback)
    poc, vah, val = profile_levels(hist)
    entry = float(trade["entry"])
    risk = max(abs(float(trade["riskPrice"])), 1e-9)
    if np.isnan(poc):
        loc = "missing"
    elif entry > vah:
        loc = "above_value"
    elif entry < val:
        loc = "below_value"
    else:
        loc = "inside_value"
    side = 1 if trade["dir"] == "L" else -1
    return {
        "poc": poc,
        "vah": vah,
        "val": val,
        "vp_location": loc,
        "signed_dist_poc_r": side * (entry - poc) / risk if not np.isnan(poc) else np.nan,
        "abs_dist_poc_r": abs(entry - poc) / risk if not np.isnan(poc) else np.nan,
        "value_width_r": (vah - val) / risk if not np.isnan(poc) else np.nan,
    }


def summarize(df: pd.DataFrame, group_col: str) -> pd.DataFrame:
    rows = []
    for key, g in df.groupby(group_col, dropna=False):
        wins = g["realizedUsd"] > 0
        gross_win = g.loc[wins, "realizedUsd"].sum()
        gross_loss = -g.loc[~wins, "realizedUsd"].sum()
        pf = np.inf if gross_loss <= 0 else gross_win / gross_loss
        rows.append(
            {
                group_col: key,
                "n": len(g),
                "net": g["realizedUsd"].sum(),
                "pf": pf,
                "win_rate": wins.mean(),
                "mfeR_mean": g["mfeR"].mean(),
                "abs_dist_poc_r_median": g["abs_dist_poc_r"].median(),
            }
        )
    return pd.DataFrame(rows).sort_values("n", ascending=False)


def df_to_markdown(df: pd.DataFrame, floatfmt: str = ".3f") -> str:
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


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bars = pd.read_csv(BARS)
    bars["ts"] = pd.to_datetime(bars["ts_ms"], unit="ms", utc=True).dt.tz_convert(None)
    trades = pd.read_csv(TRADES)
    trades["entry_ts"] = pd.to_datetime(trades["entryTimeUTC"], utc=True).dt.tz_convert(None)
    trades = trades[trades["entry_ts"] >= bars["ts"].min()].copy()

    contexts = []
    for _, tr in trades.iterrows():
        ctx = trade_context(bars, tr, lookback=240)
        contexts.append(ctx)
    out = pd.concat([trades.reset_index(drop=True), pd.DataFrame(contexts)], axis=1)
    out["poc_bucket"] = pd.cut(
        out["abs_dist_poc_r"],
        bins=[-np.inf, 0.5, 1.0, 2.0, np.inf],
        labels=["<=0.5R", "0.5-1R", "1-2R", ">2R"],
    )

    joined = OUT_DIR / "kenkem_m1_d5_e4long_vp_joined.csv"
    by_loc = summarize(out, "vp_location")
    by_bucket = summarize(out.dropna(subset=["poc_bucket"]), "poc_bucket")
    by_kind_loc = (
        out.groupby(["kind", "vp_location"])
        .agg(n=("realizedUsd", "size"), net=("realizedUsd", "sum"), mfeR_mean=("mfeR", "mean"))
        .reset_index()
        .sort_values(["kind", "n"], ascending=[True, False])
    )
    out.to_csv(joined, index=False)
    by_loc.to_csv(OUT_DIR / "summary_by_vp_location.csv", index=False)
    by_bucket.to_csv(OUT_DIR / "summary_by_poc_bucket.csv", index=False)
    by_kind_loc.to_csv(OUT_DIR / "summary_by_entry_and_location.csv", index=False)

    md = f"""# KenKem XAU M1 Tick-Activity VP Entry Audit

Generated by `research/kenkem_parity/kenkem_m1_vp_entry_audit.py`.

## Codex-Step-3 Verdict

This is a first-pass **causal rolling VP audit** for KenKem D5-E4Long. It joins each trade to the prior 240
M1 bars' tick-activity POC/VAH/VAL. It is not a strategy change and not proof of real traded volume.

## Summary by VP Location

{df_to_markdown(by_loc)}

## Summary by Distance to POC

{df_to_markdown(by_bucket)}

## Entry Type x VP Location

{df_to_markdown(by_kind_loc)}

## Decision Use

- If a VP bucket shows better MFE/MAE with enough sample, it becomes a candidate **state feature** for KenKem.
- If results are noisy/small-n, do not add VP logic yet; first improve schema and gather more trade evidence.
- Any VP feature here is quote-activity VP until cross-feed/real-volume evidence exists.

Artifacts:
- `{joined}`
- `{OUT_DIR / 'summary_by_vp_location.csv'}`
- `{OUT_DIR / 'summary_by_poc_bucket.csv'}`
- `{OUT_DIR / 'summary_by_entry_and_location.csv'}`
"""
    (OUT_DIR / "KENKEM_M1_VP_ENTRY_AUDIT.md").write_text(md)
    print(OUT_DIR / "KENKEM_M1_VP_ENTRY_AUDIT.md")


if __name__ == "__main__":
    main()
