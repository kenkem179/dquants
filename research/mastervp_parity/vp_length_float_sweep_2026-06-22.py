#!/usr/bin/env python3
"""
vp_length_float_sweep_2026-06-22.py — FLOAT master-VP-multiple sweep (0.5 steps).

InpMasterMult is now a float: master_len = round(InpVpLookback * InpMasterMult). The prior integer
sweep could only probe master length in coarse VpLookback-sized jumps (e.g. XAU 120x: 360/480/600).
0.5 steps give half-VpLookback resolution (420/480/540) so we can see whether the lock sits on a
plateau interior at finer granularity, or whether a nearby half-step is meaningfully better.

Master VP length = InpVpLookback x InpMasterMult is the SOLE breakout driver (local VP is inert in
breakout-only mode). We scan mult on BOTH TRAIN and OOS tick windows and plateau-pick: a value is
only interesting if positive on BOTH windows (not a single-window spike) AND beats the lock on a
risk-adjusted basis without degrading the other window.

Run from repo root, conda env kenkem:
  python research/mastervp_parity/vp_length_float_sweep_2026-06-22.py [XAU-M3|XAU-M5|BTC-M5|BTC-M3|all]
"""
import csv, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT   = ROOT / "cpp_core/build/backtester"
T    = ROOT / "cpp_core/tools"
START_BAL = 10000.0
OOS_END_XAU = 1775520000000   # ~2026-05-30

def frange(a, b, step):
    out=[]; x=a
    while x <= b + 1e-9:
        out.append(round(x,2)); x+=step
    return out

# VpLookback fixed at each lock; mult swept in 0.5 steps over a range centred on the lock.
CASES = {
  "XAU-M3": dict(symbol="xau", bars="bars_xauusd_2025_2026_m3.csv",
                 base="cpp_core/tools/mastervp/kkmastervp_xau_m3_LOCKED.set",
                 train="ticks_xau_train.csv", train_from=1750291200000, train_to=1769904000000,
                 oos="ticks_xau_oos.csv",     oos_from=1769904000000,   oos_to=OOS_END_XAU,
                 vplb=120, mults=frange(2.0,6.0,0.5), lock_mult=4.0,
                 doc="lock 480b (120x4.0) OOS PF 1.114 / dd 17.5%"),
  "XAU-M5": dict(symbol="xau", bars="bars_xauusd_2025_2026_m5.csv",
                 base="cpp_core/tools/mastervp/kkmastervp_xau_m5_LOCKED.set",
                 train="ticks_xau_train.csv", train_from=1750291200000, train_to=1769904000000,
                 oos="ticks_xau_oos.csv",     oos_from=1769904000000,   oos_to=OOS_END_XAU,
                 vplb=108, mults=frange(2.0,6.0,0.5), lock_mult=4.0,
                 doc="lock 432b (108x4.0) OOS PF 1.327 / dd 10.3% (validated front-runner)"),
  "BTC-M5": dict(symbol="btc", bars="bars_btcusd_2025_2026_m5.csv",
                 base="cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set",
                 train="ticks_btcusd_2025_window.csv", train_from=1754870400114, train_to=1764527344650,
                 oos="ticks_btcusd_2026_oos.csv",      oos_from=1767225605830,   oos_to=1781049599584,
                 vplb=24, mults=frange(20.0,40.0,1.0), lock_mult=30.0,
                 doc="lock 720b (24x30.0) OOS PF 1.214 / dd 14.2% (tail-skewed); vplb=24 so 1.0 step=24 bars"),
  "BTC-M3": dict(symbol="btc", bars="bars_btcusd_2025_2026_m3.csv",
                 base="cpp_core/tools/mastervp/m3_base_btc.set",
                 train="ticks_btcusd_2025_window.csv", train_from=1754870400114, train_to=1764527344650,
                 oos="ticks_btcusd_2026_oos.csv",      oos_from=1767225605830,   oos_to=1781049599584,
                 vplb=120, mults=frange(2.0,8.0,0.5), lock_mult=4.0,
                 doc="NO LOCK (prior: breakout structurally dead, OOS collapses every length)"),
}

def read_base(path):
    out=[]
    for line in (ROOT/path).read_text().splitlines():
        s=line.split(";",1)[0].strip()
        if "=" in s:
            k,v=s.split("=",1); out.append((k.strip(),v.strip()))
    return out

def write_set(base_kv, ov, path):
    d=dict(base_kv); d.update({k:str(v) for k,v in ov.items()})
    with open(path,"w") as f:
        for k,v in d.items(): f.write(f"{k}={v}\n")

def run(c, set_path, ticks, frm, to):
    out=tempfile.mktemp(suffix=".csv")
    cmd=[str(BT), "--bars", str(T/c["bars"]), "--ticks", str(T/ticks),
         "--set-all", str(set_path), f"--symbol-{c['symbol']}",
         "--trade-from-ms", str(frm), "--trade-to-ms", str(to), "--out", out]
    r=subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode!=0:
        sys.stderr.write(r.stderr[-400:]); return None
    return metrics(out)

def metrics(p):
    pnls=[]
    with open(p) as f:
        for row in csv.DictReader(f): pnls.append(float(row["realizedUsd"]))
    n=len(pnls)
    if n==0: return dict(n=0)
    wins=[x for x in pnls if x>0]; losses=[x for x in pnls if x<=0]
    gw,gl=sum(wins),-sum(losses)
    eq,peak,maxdd=START_BAL,START_BAL,0.0
    for x in pnls:
        eq+=x; peak=max(peak,eq); maxdd=max(maxdd,peak-eq)
    return dict(n=n, win=100*len(wins)/n, pf=(gw/gl if gl>0 else 999.0),
                net=sum(pnls), maxdd_pct=100*maxdd/peak if peak else 0)

def cell(m):
    if m is None: return "   FAIL        "
    if m.get("n",0)==0: return "   n=0         "
    return f"PF{m['pf']:.3f} net{m['net']:+8.0f} dd{m['maxdd_pct']:4.1f}% n{m['n']:5d} w{m['win']:.0f}"

def sweep_case(name):
    c=CASES[name]; base=read_base(c["base"])
    print("\n"+"="*104)
    print(f"{name}   base={Path(c['base']).name}   [{c['doc']}]   VpLookback fixed={c['vplb']}")
    print("="*104)
    print(f"{'master':>7} {'mult':>5} | {'TRAIN':^42} | {'OOS':^42}  {'LOCK?':>6}")
    print("-"*104)
    for mult in c["mults"]:
        master=round(c["vplb"]*mult)
        ov={"InpVpLookback":c["vplb"], "InpMasterMult":mult}
        sp=tempfile.mktemp(suffix=".set"); write_set(base,ov,sp)
        tr=run(c, sp, c["train"], c["train_from"], c["train_to"])
        oo=run(c, sp, c["oos"],   c["oos_from"],   c["oos_to"])
        tag="<== LOCK" if abs(mult-c["lock_mult"])<1e-9 else ""
        print(f"{master:>7} {mult:>5.1f} | {cell(tr):^42} | {cell(oo):^42}  {tag}")

if __name__=="__main__":
    which=sys.argv[1] if len(sys.argv)>1 else "all"
    targets=[which] if which in CASES else list(CASES)
    for t in targets:
        sweep_case(t)
