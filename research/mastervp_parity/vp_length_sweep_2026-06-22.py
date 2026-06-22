#!/usr/bin/env python3
"""
vp_length_sweep_2026-06-22.py — re-confirm we are not leaving VP-length edge on the table
for the three targets the user flagged: BTC M3, BTC M5, XAU M3.

Master VP length = InpVpLookback x InpMasterMult is the SOLE breakout driver (local VP is inert
in breakout-only mode — VP_LENGTH_STUDY.md). So we scan the master-bar count on BOTH the TRAIN and
OOS tick windows and plateau-pick: a length is only interesting if it is positive on BOTH windows
(not a train-only or OOS-only spike). We vary MasterMult at the lock's VpLookback (product = master
bars), so each row is a clean master-length probe against the locked config.

Run from repo root, conda env kenkem:
  python research/mastervp_parity/vp_length_sweep_2026-06-22.py [XAU-M3|BTC-M5|BTC-M3|all]
"""
import csv, os, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT   = ROOT / "cpp_core/build/backtester"
T    = ROOT / "cpp_core/tools"
START_BAL = 10000.0
OOS_END_XAU = 1775520000000   # ~2026-05-30 (train file already ends at OOS start, no leak)

# Each case: base .set, bars, train/oos tick files + trade-from gates, and the master-bar grid
# expressed as (VpLookback, MasterMult) so master = product. VpLookback fixed at the lock value.
CASES = {
  "XAU-M3": dict(symbol="xau", bars="bars_xauusd_2025_2026_m3.csv",
                 base="cpp_core/tools/mastervp/kkmastervp_xau_m3_LOCKED.set",
                 train="ticks_xau_train.csv",        train_from=1750291200000, train_to=1769904000000,
                 oos="ticks_xau_oos.csv",            oos_from=1769904000000,   oos_to=OOS_END_XAU,
                 vplb=120, mults=[2,3,4,5,6,8,10],   lock_master=480,
                 doc="lock 480b (120x4) OOS PF 1.114 / dd 17.5%"),
  "BTC-M5": dict(symbol="btc", bars="bars_btcusd_2025_2026_m5.csv",
                 base="cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set",
                 train="ticks_btcusd_2025_window.csv", train_from=1754870400114, train_to=1764527344650,
                 oos="ticks_btcusd_2026_oos.csv",      oos_from=1767225605830,   oos_to=1781049599584,
                 vplb=24, mults=[15,20,25,30,35,40,50,60], lock_master=720,
                 doc="lock 720b (24x30) OOS PF 1.214 / dd 14.2% (tail-skewed)"),
  "BTC-M3": dict(symbol="btc", bars="bars_btcusd_2025_2026_m3.csv",
                 base="cpp_core/tools/mastervp/m3_base_btc.set",
                 train="ticks_btcusd_2025_window.csv", train_from=1754870400114, train_to=1764527344650,
                 oos="ticks_btcusd_2026_oos.csv",      oos_from=1767225605830,   oos_to=1781049599584,
                 vplb=120, mults=[3,4,6,8,12,16,24],   lock_master=480,
                 doc="NO LOCK (prior: no edge, OOS collapses)"),
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
                net=sum(pnls), maxdd_pct=100*maxdd/peak if peak else 0,
                calmar=(sum(pnls)/maxdd if maxdd>0 else 999.0))

def cell(m):
    if m is None: return "   FAIL        "
    if m.get("n",0)==0: return "   n=0         "
    return f"PF{m['pf']:.3f} net{m['net']:+8.0f} dd{m['maxdd_pct']:4.1f}% n{m['n']:5d} w{m['win']:.0f}"

def sweep_case(name):
    c=CASES[name]; base=read_base(c["base"])
    print("\n"+"="*100)
    print(f"{name}   base={Path(c['base']).name}   [{c['doc']}]   VpLookback fixed={c['vplb']}")
    print("="*100)
    print(f"{'master':>7} {'mult':>4} | {'TRAIN':^42} | {'OOS':^42}  {'LOCK?':>6}")
    print("-"*100)
    rows=[]
    for mult in c["mults"]:
        master=c["vplb"]*mult
        ov={"InpVpLookback":c["vplb"], "InpMasterMult":mult}
        sp=tempfile.mktemp(suffix=".set"); write_set(base,ov,sp)
        tr=run(c, sp, c["train"], c["train_from"], c["train_to"])
        oo=run(c, sp, c["oos"],   c["oos_from"],   c["oos_to"])
        tag="<== LOCK" if master==c["lock_master"] else ""
        print(f"{master:>7} {mult:>4} | {cell(tr):^42} | {cell(oo):^42}  {tag}")
        rows.append((master,mult,tr,oo))
    return rows

SECONDARY = {  # lever -> absolute values to probe (around each lock), train+OOS
  "InpAdxTrendMin": [18.0, 22.0, 26.0, 30.0],
  "InpBreakBufAtr": [0.4, 0.55, 0.7, 0.85, 1.0],
  "InpSlAtrBrk":    [0.7, 1.0, 1.3, 1.8, 2.2],
}

def secondary_case(name):
    c=CASES[name]; base=read_base(c["base"]); bd=dict(base)
    print("\n"+"="*100)
    print(f"SECONDARY (lock VP) {name}   base={Path(c['base']).name}")
    print("="*100)
    for key,vals in SECONDARY.items():
        lock=bd.get(key,"?")
        print(f"-- {key}  (lock={lock}) --")
        for v in vals:
            sp=tempfile.mktemp(suffix=".set"); write_set(base,{key:v},sp)
            tr=run(c, sp, c["train"], c["train_from"], c["train_to"])
            oo=run(c, sp, c["oos"],   c["oos_from"],   c["oos_to"])
            tag="<==lock" if str(v)==str(lock) or f"{v:.1f}"==str(lock) else ""
            print(f"   {v:>6} | TRAIN {cell(tr):^42} | OOS {cell(oo):^42} {tag}")

# FVG-anchored SL probe: baseline (OFF) vs a grid of {mode, beyond_va, min_atr, max_risk_atr, buf}.
# The user's testcases are modest breakouts (gap close to the edge), so tight risk caps matter most.
FVG_GRID = [
  dict(label="OFF                              "),
  # replace mode
  dict(label="rep bVA min.25 cap1.5 buf.10", InpEnableFvgSl="true", InpFvgMode=0, InpFvgBeyondVa="true",  InpFvgMinAtr=0.25, InpFvgMaxRiskAtr=1.5, InpFvgBufAtr=0.10),
  dict(label="rep bVA min.25 cap2.5 buf.10", InpEnableFvgSl="true", InpFvgMode=0, InpFvgBeyondVa="true",  InpFvgMinAtr=0.25, InpFvgMaxRiskAtr=2.5, InpFvgBufAtr=0.10),
  dict(label="rep  VA min.25 cap2.5 buf.10", InpEnableFvgSl="true", InpFvgMode=0, InpFvgBeyondVa="false", InpFvgMinAtr=0.25, InpFvgMaxRiskAtr=2.5, InpFvgBufAtr=0.10),
  dict(label="rep  VA min.50 cap2.5 buf.10", InpEnableFvgSl="true", InpFvgMode=0, InpFvgBeyondVa="false", InpFvgMinAtr=0.50, InpFvgMaxRiskAtr=2.5, InpFvgBufAtr=0.10),
  # widen-only mode (only when the structural stop is FURTHER than the ATR stop, capped)
  dict(label="wdn bVA min.25 cap3.0 buf.10", InpEnableFvgSl="true", InpFvgMode=1, InpFvgBeyondVa="true",  InpFvgMinAtr=0.25, InpFvgMaxRiskAtr=3.0, InpFvgBufAtr=0.10),
  dict(label="wdn  VA min.25 cap3.0 buf.10", InpEnableFvgSl="true", InpFvgMode=1, InpFvgBeyondVa="false", InpFvgMinAtr=0.25, InpFvgMaxRiskAtr=3.0, InpFvgBufAtr=0.10),
  dict(label="wdn  VA min.25 cap2.0 buf.05", InpEnableFvgSl="true", InpFvgMode=1, InpFvgBeyondVa="false", InpFvgMinAtr=0.25, InpFvgMaxRiskAtr=2.0, InpFvgBufAtr=0.05),
  # tighten-only mode (structural stop INSIDE the ATR stop = smaller risk, more trades survive?)
  dict(label="tgt  VA min.25 flr.5 buf.10",  InpEnableFvgSl="true", InpFvgMode=2, InpFvgBeyondVa="false", InpFvgMinAtr=0.25, InpFvgMinRiskAtr=0.5, InpFvgBufAtr=0.10),
  # REQUIRE-FVG entry gate: only take breakouts that HAVE a qualifying structural gap (user thesis:
  # "ensure successful breakouts"). Pairs the gate with a sane widen-only beyond-VA stop.
  dict(label="REQ wdn bVA min.25 cap3.0",   InpEnableFvgSl="true", InpFvgRequire="true", InpFvgMode=1, InpFvgBeyondVa="true",  InpFvgMinAtr=0.25, InpFvgMaxRiskAtr=3.0, InpFvgBufAtr=0.10),
  dict(label="REQ wdn  VA min.25 cap3.0",   InpEnableFvgSl="true", InpFvgRequire="true", InpFvgMode=1, InpFvgBeyondVa="false", InpFvgMinAtr=0.25, InpFvgMaxRiskAtr=3.0, InpFvgBufAtr=0.10),
  dict(label="REQ rep bVA min.25 cap2.5",   InpEnableFvgSl="true", InpFvgRequire="true", InpFvgMode=0, InpFvgBeyondVa="true",  InpFvgMinAtr=0.25, InpFvgMaxRiskAtr=2.5, InpFvgBufAtr=0.10),
  dict(label="REQ rep  VA min.50 cap2.5",   InpEnableFvgSl="true", InpFvgRequire="true", InpFvgMode=0, InpFvgBeyondVa="false", InpFvgMinAtr=0.50, InpFvgMaxRiskAtr=2.5, InpFvgBufAtr=0.10),
]

def fvg_case(name):
    c=CASES[name]; base=read_base(c["base"])
    print("\n"+"="*108)
    print(f"FVG-SL {name}   base={Path(c['base']).name}   [{c['doc']}]")
    print("="*108)
    print(f"{'config':<30} | {'TRAIN':^42} | {'OOS':^42}")
    print("-"*108)
    only=os.environ.get("FVG_ONLY","")
    grid=[g for g in FVG_GRID if (not only) or only in g["label"] or g["label"].startswith("OFF")] if only else FVG_GRID
    for g in grid:
        ov={k:v for k,v in g.items() if k!="label"}
        sp=tempfile.mktemp(suffix=".set"); write_set(base,ov,sp)
        tr=run(c, sp, c["train"], c["train_from"], c["train_to"])
        oo=run(c, sp, c["oos"],   c["oos_from"],   c["oos_to"])
        print(f"{g['label']:<30} | {cell(tr):^42} | {cell(oo):^42}")

if __name__=="__main__":
    args=sys.argv[1:]
    mode="vp"
    if args and args[0]=="--fvg": mode="fvg"; args=args[1:]
    elif args and args[0]=="--secondary": mode="secondary"; args=args[1:]
    which=args[0] if args else "all"
    targets=[which] if which in CASES else list(CASES)
    for t in targets:
        if mode=="fvg": fvg_case(t)
        elif mode=="secondary": secondary_case(t)
        else: sweep_case(t)
