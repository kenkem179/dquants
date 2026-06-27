import pandas as pd, numpy as np
df = pd.read_csv("cpp_core/tools/trades_kenkem_lock_autopsy.csv")
print("mfeR/maeR sanity:", df.mfeR.describe()[["min","mean","max"]].to_dict(),
      "| maeR nonzero:", int((df.maeR!=0).sum()), "of", len(df))
print("\n## by exitTag — did EA-bails reach profit first? (mfeR = max favorable excursion in R)")
print(f"  {'tag':<10}{'n':>4}{'net':>8}{'win%':>6}{'mfeR':>7}{'maeR':>7}  {'reach>=1R%':>11}{'reach>=0.5R%':>13}")
for k,g in df.groupby("exitTag"):
    print(f"  {k:<10}{len(g):>4}{g.realizedUsd.sum():>8.0f}{100*(g.realizedUsd>0).mean():>6.1f}"
          f"{g.mfeR.mean():>7.2f}{g.maeR.mean():>7.2f}{100*(g.mfeR>=1.0).mean():>11.1f}{100*(g.mfeR>=0.5).mean():>13.1f}")
ea = df[df.exitTag=="EA"]
print(f"\n## EA-exit bucket (n={len(ea)}, net={ea.realizedUsd.sum():.0f}): mfeR distribution")
print("  reached>=1.0R:", int((ea.mfeR>=1.0).sum()), " >=0.75R:", int((ea.mfeR>=0.75).sum()),
      " >=0.5R:", int((ea.mfeR>=0.5).sum()), " <0.25R (never green):", int((ea.mfeR<0.25).sum()))
for k,g in ea.groupby("kind"):
    print(f"    {k}: n={len(g)} net={g.realizedUsd.sum():.0f} mfeR={g.mfeR.mean():.2f} reach1R%={100*(g.mfeR>=1).mean():.0f}")
