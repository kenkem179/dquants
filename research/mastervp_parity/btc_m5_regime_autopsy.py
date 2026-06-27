#!/usr/bin/env python3
"""
btc_m5_regime_autopsy.py — model-free per-trade regime decomposition of the BTC M5 lock.

WHY: the 6-fold WF shows BTC M5 = alternating unconditioned variance (F1- F2+ F3- F4+ F5+ F6-,
3/6 folds positive, worst PF 0.74, MOST-RECENT fold negative, MT5-disconfirms to ~1.06). With only
6 folds, any "turn off the losing folds" regime filter is overfit by construction. The legitimate,
non-overfitting question (project doctrine: model-free autopsy on hundreds of trades, not 6 folds):
does the edge CONCENTRATE in an economically-sensible, PRE-REGISTERED condition the way the XAU
ATR-regime filter does?

PRE-REGISTERED conditioning variables (chosen a priori from breakout economics, NOT from fold labels):
  adx        - trend strength; breakouts should follow through better in stronger trends
  diSpread   - directional conviction |+DI - -DI|; cleaner directional regime
  brkDistAtr - breakout extension at entry; chasing far-extended breaks may be worse (anti-chase)
  runwayAtr  - room to next structural node; more runway = more follow-through expected
  spreadAtr  - cost-in-ATR regime proxy (high = noisy/illiquid)

For each: quartile the trades and report n, win%, model-free mfeR, reach1R (mfeR>=1.0 frac), maeR,
and realized usd/tr + total. A real lever = a MONOTONE, economically-sensible gradient that is ROBUST
across the time-split (first half vs second half of the trades) — NOT a single cherry-picked cell.
"""
import sys
import pandas as pd
import numpy as np

CSV = sys.argv[1] if len(sys.argv) > 1 else "cpp_core/tools/trades_btc_m5_autopsy.csv"
df = pd.read_csv(CSV)
df["entryTimeUTC"] = pd.to_datetime(df["entryTimeUTC"], errors="coerce")
df = df.sort_values("entryTimeUTC").reset_index(drop=True)
n = len(df)
print(f"# BTC M5 lock trades: n={n}  span {df.entryTimeUTC.min()} .. {df.entryTimeUTC.max()}")
print(f"# pooled: win%={100*(df.realizedUsd>0).mean():.1f}  net=${df.realizedUsd.sum():,.0f}  "
      f"mfeR={df.mfeR.mean():.3f}  reach1R={100*(df.mfeR>=1.0).mean():.1f}%  maeR={df.maeR.mean():.3f}")

# time-split for robustness (NOT the calendar folds — just first/second half of the trade stream)
half = n // 2
df["era"] = np.where(df.index < half, "H1", "H2")
print(f"# H1 net=${df[df.era=='H1'].realizedUsd.sum():,.0f} (n={half})  "
      f"H2 net=${df[df.era=='H2'].realizedUsd.sum():,.0f} (n={n-half})")


def decomp(var, q=4):
    sub = df[df[var].notna()].copy()
    try:
        sub["bin"] = pd.qcut(sub[var], q, duplicates="drop")
    except ValueError:
        print(f"\n## {var}: not enough distinct values"); return
    print(f"\n## {var}  (quartiles)")
    print(f"  {'range':<22} {'n':>4} {'win%':>5} {'mfeR':>6} {'rch1R':>6} {'maeR':>6} "
          f"{'usd/tr':>8} {'totUsd':>9}  | H1usd/tr H2usd/tr")
    for b, g in sub.groupby("bin", observed=True):
        h1 = g[g.era == "H1"].realizedUsd
        h2 = g[g.era == "H2"].realizedUsd
        print(f"  {str(b):<22} {len(g):>4} {100*(g.realizedUsd>0).mean():>5.1f} "
              f"{g.mfeR.mean():>6.3f} {100*(g.mfeR>=1.0).mean():>6.1f} {g.maeR.mean():>6.3f} "
              f"{g.realizedUsd.mean():>8.1f} {g.realizedUsd.sum():>9,.0f}  | "
              f"{(h1.mean() if len(h1) else float('nan')):>8.1f} "
              f"{(h2.mean() if len(h2) else float('nan')):>8.1f}")


for v in ["adx", "diSpread", "brkDistAtr", "runwayAtr", "spreadAtr"]:
    if v in df.columns:
        decomp(v)

# entry-reason / direction split (free, sometimes informative)
print("\n## by entryReason")
for r, g in df.groupby("entryReason"):
    print(f"  {r:<10} n={len(g):>4} win%={100*(g.realizedUsd>0).mean():>5.1f} "
          f"mfeR={g.mfeR.mean():.3f} usd/tr={g.realizedUsd.mean():>7.1f} tot={g.realizedUsd.sum():>9,.0f}")
print("\n## by dir")
for r, g in df.groupby("dir"):
    print(f"  dir={r:<3} n={len(g):>4} win%={100*(g.realizedUsd>0).mean():>5.1f} "
          f"mfeR={g.mfeR.mean():.3f} usd/tr={g.realizedUsd.mean():>7.1f} tot={g.realizedUsd.sum():>9,.0f}")
