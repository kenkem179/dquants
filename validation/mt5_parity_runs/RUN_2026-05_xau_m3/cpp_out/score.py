#!/usr/bin/env python3
import pandas as pd, numpy as np, re, sys

RUN = "validation/mt5_parity_runs/RUN_2026-05_xau_m3"
mt5 = pd.read_csv(f"{RUN}/mt5_ref/parity_mt5.csv")
cpp = pd.read_csv(f"{RUN}/cpp_out/parity_cpp_ema.csv")

# ---- Level-1: merge on barTimeUTC over overlap ----
m = mt5.merge(cpp, on="barTimeUTC", suffixes=("_mt5", "_cpp"))
print(f"[L1] mt5 bars={len(mt5)} cpp bars={len(cpp)} overlap={len(m)}")

def diffstat(col):
    a = m[f"{col}_mt5"].astype(float); b = m[f"{col}_cpp"].astype(float)
    d = (a - b).abs()
    return d.max(), d.mean()

print("\n[L1] per-column abs diff (master VP + regime):")
print(f"{'col':<8}{'max':>14}{'mean':>14}")
for c in ["mpoc","mvah","mval","plus","minus","adx"]:
    mx, mn = diffstat(c)
    print(f"{c:<8}{mx:>14.5f}{mn:>14.5f}")

# atr1 ratio (cpp/mt5) — both nonzero
a = m["atr1_mt5"].astype(float); b = m["atr1_cpp"].astype(float)
mask = (a > 0) & (b > 0)
ratio = (b[mask] / a[mask])
print(f"\n[L1] atr1 ratio cpp/mt5: median={ratio.median():.5f} mean={ratio.mean():.5f} "
      f"min={ratio.min():.5f} max={ratio.max():.5f}  (n={mask.sum()})")
mxd, mnd = diffstat("atr1")
print(f"[L1] atr1 abs diff: max={mxd:.5f} mean={mnd:.5f}")

# sigValid / sigLong disagreement
for c in ["sigValid","sigLong","sigRev"]:
    dis = (m[f"{c}_mt5"].astype(int) != m[f"{c}_cpp"].astype(int)).sum()
    print(f"[L1] {c} disagreement: {dis} / {len(m)}")

# ---- Level-2: gates.txt FILL lines vs MT5 trades ----
fills = []
for ln in open(f"{RUN}/cpp_out/gates.txt"):
    mo = re.search(r"\[gate\] (\S+ \S+) ([LS]) -> FILL entry=([\d.]+)", ln)
    if mo:
        fills.append((mo.group(1), mo.group(2), float(mo.group(3))))
fills = pd.DataFrame(fills, columns=["t","dir","entry"])
fills["ts"] = pd.to_datetime(fills["t"], format="%Y.%m.%d %H:%M")
print(f"\n[L2] C++ FILLs from gates.txt: {len(fills)}")

tr = pd.read_csv(f"{RUN}/mt5_ref/trades_mt5.csv")
tr["ts"] = pd.to_datetime(tr["entryTimeUTC"], format="%Y.%m.%d %H:%M")
print(f"[L2] MT5 trades: {len(tr)}")

# align by entry time (+-3min) and dir
TOL = pd.Timedelta(minutes=3)
matched, mt5_only, cpp_only = [], [], []
fused = set()
for _, r in tr.iterrows():
    cand = fills[(fills["dir"]==r["dir"]) & ((fills["ts"]-r["ts"]).abs()<=TOL)]
    cand = cand[~cand.index.isin(fused)]
    if len(cand):
        j = cand.index[0]; fused.add(j)
        matched.append((r["entryTimeUTC"], r["dir"], r["entry"], fills.loc[j,"entry"]))
    else:
        mt5_only.append((r["entryTimeUTC"], r["dir"], r["entry"]))
for j, f in fills.iterrows():
    if j not in fused:
        cpp_only.append((f["t"], f["dir"], f["entry"]))

print(f"\n[L2] matched: {len(matched)}/{len(tr)}")
print(f"[L2] MT5-only (C++ missed): {len(mt5_only)}")
for t,d,e in mt5_only: print(f"     {t} {d} entry={e}")
print(f"[L2] C++-only (extra): {len(cpp_only)}")
for t,d,e in cpp_only: print(f"     {t} {d} entry={e}")

# ---- For each MT5-only miss: find the gate block reason at that bar ----
gate_lines = open(f"{RUN}/cpp_out/gates.txt").read().splitlines()
def gate_at(tstr):
    # tstr like 2026.05.19 02:57 ; match exact bar minute, also +-3min
    base = pd.to_datetime(tstr, format="%Y.%m.%d %H:%M")
    out = []
    for off in [0,-3,3,-6,6]:
        key = (base+pd.Timedelta(minutes=off)).strftime("%Y.%m.%d %H:%M")
        for ln in gate_lines:
            if f"[gate] {key} " in ln:
                out.append(ln.strip())
    return out

if mt5_only:
    print("\n[L2] gate trace around each MT5-only miss:")
    for t,d,e in mt5_only:
        print(f"  --- {t} {d} ---")
        for g in gate_at(t): print(f"     {g}")

# ---- ATR% band straddle analysis ----
# read MaxAtrPct / MinAtrPct from set
setp = {}
for ln in open(f"{RUN}/cpp_out/xau_ref_run_ema.set"):
    if "=" in ln:
        k,v = ln.strip().split("=",1); setp[k]=v
maxatr = float(setp["InpMaxAtrPct"]); minatr=float(setp["InpMinAtrPct"])
print(f"\n[ATR] InpMinAtrPct={minatr}  InpMaxAtrPct={maxatr}")

# atr% = atr1 / close * 100? Need close. Use mt5 parity has no close col; compute atr% from mvah?
# The engine atr% = atr/price*100. Use entry price ~ mpoc. Tabulate at ATR-band-block bars.
band_blocks = [ln for ln in gate_lines if "ATR% band" in ln]
print(f"[ATR] {len(band_blocks)} 'ATR% band' BLOCK lines in gates.txt")
# extract times of ATR-band blocks and join atr1 from both sides
btimes = []
for ln in band_blocks:
    mo = re.search(r"\[gate\] (\S+ \S+) ", ln)
    if mo: btimes.append(mo.group(1))
bb = m[m["barTimeUTC"].isin(btimes)].copy()
if len(bb):
    # atr% needs price; approximate price = mpoc_mt5
    bb["atrpct_mt5"] = bb["atr1_mt5"].astype(float)/bb["mpoc_mt5"].astype(float)*100
    bb["atrpct_cpp"] = bb["atr1_cpp"].astype(float)/bb["mpoc_cpp"].astype(float)*100
    print(f"\n[ATR] band-block bars (atr% = atr1/mpoc*100), cap={maxatr}%:")
    print(f"{'barTimeUTC':<18}{'atr%_mt5':>10}{'atr%_cpp':>10}{'atr1_mt5':>10}{'atr1_cpp':>10}")
    for _, r in bb.iterrows():
        print(f"{r['barTimeUTC']:<18}{r['atrpct_mt5']:>10.4f}{r['atrpct_cpp']:>10.4f}"
              f"{float(r['atr1_mt5']):>10.3f}{float(r['atr1_cpp']):>10.3f}")
    nstraddle = ((bb["atrpct_mt5"]<maxatr) & (bb["atrpct_cpp"]>=maxatr)).sum()
    print(f"[ATR] bars where MT5 below cap but C++ above (straddle): {nstraddle}/{len(bb)}")
