import pandas as pd, numpy as np
df = pd.read_csv("cpp_core/tools/trades_kenkem_lock_autopsy.csv")
df["t"] = pd.to_datetime(df["entryTimeUTC"], errors="coerce", utc=True)
df = df.sort_values("t").reset_index(drop=True)
u = df.realizedUsd
def pf(x):
    w,l = x[x>0].sum(), -x[x<0].sum()
    return w/l if l>0 else float('inf')
print(f"# KenKem lock: n={len(df)}  net=${u.sum():,.0f}  PF={pf(u):.3f}  win%={100*(u>0).mean():.1f}  "
      f"span {df.t.min().date()}..{df.t.max().date()}")
print(f"# avg win ${u[u>0].mean():.1f}  avg loss ${u[u<0].mean():.1f}  "
      f"largest win ${u.max():.0f}  largest loss ${u.min():.0f}")

print("\n## tail-dependence (sorted winners)")
sw = u.sort_values(ascending=False).values
tot = u.sum()
for k in [1,3,5,10]:
    print(f"  top-{k:>2} winners = ${sw[:k].sum():,.0f}  = {100*sw[:k].sum()/tot:.0f}% of net  | "
          f"net ex-top{k} = ${tot - sw[:k].sum():,.0f}  PF ex-top{k}={pf(np.concatenate([sw[k:], u[u<0].values])):.3f}")

print("\n## per-quarter (time robustness)")
df["q"] = df.t.dt.to_period("Q")
for q,g in df.groupby("q"):
    x=g.realizedUsd
    print(f"  {q}  n={len(g):>3}  net=${x.sum():>7,.0f}  PF={pf(x):>5.2f}  win%={100*(x>0).mean():>5.1f}")

print("\n## per entry-type")
for k,g in df.groupby("kind"):
    x=g.realizedUsd
    print(f"  {k}  n={len(g):>3}  net=${x.sum():>7,.0f}  PF={pf(x):>5.2f}  win%={100*(x>0).mean():>5.1f}  "
          f"mfeR={g.mfeR.mean():.2f} maeR={g.maeR.mean():.2f}  avgWin${x[x>0].mean():.0f} avgLoss${x[x<0].mean():.0f}")

print("\n## per direction")
for k,g in df.groupby("dir"):
    x=g.realizedUsd
    print(f"  dir={k}  n={len(g):>3}  net=${x.sum():>7,.0f}  PF={pf(x):>5.2f}  win%={100*(x>0).mean():>5.1f}")

print("\n## by exitTag")
for k,g in df.groupby("exitTag"):
    x=g.realizedUsd
    print(f"  {k:<14} n={len(g):>3}  net=${x.sum():>7,.0f}  win%={100*(x>0).mean():>5.1f}  avg${x.mean():>6.1f}")

# how many trades does the gate sample have? MinTRL was 122<126 -> any sweep must keep n high
print(f"\n# NOTE: n={len(df)} trades. MinTRL ~122. Sweeps that REDUCE n below ~122 break the gate.")
