#!/usr/bin/env python3
"""Walk-forward robustness of the XAU-M3 FVG-REQUIRE entry gate vs OFF.

The single train/OOS split made REQ look great on XAU OOS (PF 1.32->1.50) but it HURT train and
REVERSED on BTC-M5 — smells regime-dependent. WF test: run each config over the full XAU range,
bucket trades by calendar month, and check whether REQ beats OFF in a MAJORITY of months (robust) or
only in the OOS tail (lucky). A real edge wins most folds; a curve-fit wins the held-out window only.
"""
import csv, subprocess, sys, tempfile, collections
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT   = ROOT / "cpp_core/build/backtester"
T    = ROOT / "cpp_core/tools"
BARS = T / "bars_xauusd_2025_2026_m3.csv"
BASE = ROOT / "cpp_core/tools/mastervp/kkmastervp_xau_m3_LOCKED.set"
# full usable XAU range = train + oos windows, run as two passes then merged
PASSES = [("ticks_xau_train.csv", 1750291200000, 1769904000000),
          ("ticks_xau_oos.csv",   1769904000000, 1775520000000)]

CONFIGS = {
  "OFF": {},
  "REQ_rep_VA_min.50_cap2.5": dict(InpEnableFvgSl="true", InpFvgRequire="true", InpFvgMode=0,
                                   InpFvgBeyondVa="false", InpFvgMinAtr=0.50, InpFvgMaxRiskAtr=2.5, InpFvgBufAtr=0.10),
  "REQ_wdn_VA_min.25_cap3.0": dict(InpEnableFvgSl="true", InpFvgRequire="true", InpFvgMode=1,
                                   InpFvgBeyondVa="false", InpFvgMinAtr=0.25, InpFvgMaxRiskAtr=3.0, InpFvgBufAtr=0.10),
}

def read_base():
    out={}
    for line in BASE.read_text().splitlines():
        s=line.split(";",1)[0].strip()
        if "=" in s: k,v=s.split("=",1); out[k.strip()]=v.strip()
    return out

def write_set(ov):
    d=read_base(); d.update({k:str(v) for k,v in ov.items()})
    sp=tempfile.mktemp(suffix=".set")
    with open(sp,"w") as f:
        for k,v in d.items(): f.write(f"{k}={v}\n")
    return sp

def run_trades(sp):
    rows=[]
    for tk,frm,to in PASSES:
        out=tempfile.mktemp(suffix=".csv")
        cmd=[str(BT),"--bars",str(BARS),"--ticks",str(T/tk),"--set-all",sp,"--symbol-xau",
             "--trade-from-ms",str(frm),"--trade-to-ms",str(to),"--out",out]
        r=subprocess.run(cmd,capture_output=True,text=True)
        if r.returncode!=0: sys.stderr.write(r.stderr[-400:]); continue
        with open(out) as f:
            for row in csv.DictReader(f): rows.append(row)
    return rows

def fold_pf(rows):
    # bucket realizedUsd by YYYY.MM of entryTimeUTC ("2026.02.01 23:09")
    buck=collections.defaultdict(list)
    for row in rows:
        mon=row["entryTimeUTC"][:7]   # YYYY.MM
        buck[mon].append(float(row["realizedUsd"]))
    res={}
    for mon,pn in sorted(buck.items()):
        gw=sum(x for x in pn if x>0); gl=-sum(x for x in pn if x<=0)
        res[mon]=dict(n=len(pn), net=sum(pn), pf=(gw/gl if gl>0 else 999.0))
    return res

if __name__=="__main__":
    data={name: fold_pf(run_trades(write_set(ov))) for name,ov in CONFIGS.items()}
    months=sorted({m for d in data.values() for m in d})
    names=list(CONFIGS)
    print(f"{'month':<9} " + " | ".join(f"{n:^26}" for n in names))
    print("-"*9 + "-"+ "-".join("-"*28 for _ in names))
    wins={n:0 for n in names if n!="OFF"}
    for m in months:
        cells=[]
        off=data["OFF"].get(m,{})
        for n in names:
            d=data[n].get(m,{})
            cells.append(f"PF{d.get('pf',0):.2f} net{d.get('net',0):+7.0f} n{d.get('n',0):4d}" if d else " "*26)
            if n!="OFF" and d and off and d['pf']>off['pf']: wins[n]+=1
        print(f"{m:<9} " + " | ".join(f"{c:^26}" for c in cells))
    nm=len(months)
    print(f"\nFolds (months) = {nm}")
    for n,w in wins.items():
        print(f"  {n}: beats OFF in {w}/{nm} folds  -> {'ROBUST' if w>nm/2 else 'NOT robust (OOS-lucky / regime-dependent)'}")
