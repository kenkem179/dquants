#!/usr/bin/env python3
"""Validate the M3 RR-rescale candidate: RR plateau check + OOS + full-window + exit mix."""
import csv, os, re, subprocess, sys, tempfile
from concurrent.futures import ProcessPoolExecutor

ROOT = "/Users/tokyotechies/Workspace/KEM/dquants"
BIN  = f"{ROOT}/cpp_core/build/kenkem/tick_backtester"
BARS = f"{ROOT}/cpp_core/tools/bars_xauusd_2024_2026_m3.csv"
TICKS= f"{ROOT}/cpp_core/tools/ticks_xauusd_2024_2026.csv"
BASE = f"{ROOT}/research/kenkem_parity/KK-KenKem-XAUUSD-M1-D5-E4Long.set"
OUTD = f"{ROOT}/research/kenkem_parity/m3_sweep"
T_SPLIT = 1759276800000   # 2025-10-01

WINDOWS = {  # name -> (from_ms, to_ms)
    "train": (0, T_SPLIT),
    "oos":   (T_SPLIT, 0),
    "full":  (0, 0),
}
FIXED = {"EMA_ALIGNMENT_TOLERANCE_PIPS":35.0, "SL_EMA_DISTANCE":55,
         "MIN_ENTRY_ATR_PERCENTILE":70, "SIDEWAYS_BLOCK_THRESHOLD":45}
RRS = [3.2, 4.0, 4.5, 5.0, 5.5, 6.0]

def load_base():
    kv={}
    for ln in open(BASE):
        ln=ln.strip()
        if ln and "=" in ln and not ln.startswith(";"):
            k,v=ln.split("=",1); kv[k.strip()]=v.strip()
    return kv

def quarter(t): y=int(t[:4]); mo=int(t[5:7]); return f"{y}Q{(mo-1)//3+1}"

def run(args):
    rr, win = args
    fr, to = WINDOWS[win]
    base=load_base(); base.update({k:str(v) for k,v in FIXED.items()}); base["E1_RR"]=str(rr)
    fd,sp=tempfile.mkstemp(suffix=".set",dir=OUTD); os.close(fd)
    with open(sp,"w") as f:
        for k,v in base.items(): f.write(f"{k}={v}\n")
    out=os.path.join(OUTD,f"v_rr{rr}_{win}.csv")
    cmd=[BIN,"--bars-m1",BARS,"--ticks",TICKS,"--symbol-xau","--set",sp,"--out",out]
    if fr: cmd+=["--from-ms",str(fr)]
    if to: cmd+=["--to-ms",str(to)]
    r=subprocess.run(cmd,capture_output=True,text=True); os.unlink(sp)
    o=r.stdout
    def gf(p,d=0.0):
        m=re.search(p,o); return float(m.group(1)) if m else d
    res={"rr":rr,"win":win,"n":int(gf(r"trades:\s+(\d+)")),"winp":gf(r"win% (\d+\.\d+)"),
         "net":gf(r"net:\s+(-?\d+\.\d+)"),"pf":gf(r"PF:\s+(\d+\.\d+)"),"dd":gf(r"max DD:\s+(\d+\.\d+)")}
    # exit-tag mix + per-quarter
    et={}; pq={}
    try:
        for row in csv.DictReader(open(out)):
            et[row["exitTag"]]=et.get(row["exitTag"],0)+1
            q=quarter(row["entryTimeUTC"]); pq[q]=pq.get(q,0.0)+float(row["realizedUsd"])
    except FileNotFoundError: pass
    res["exits"]=";".join(f"{k}:{et[k]}" for k in sorted(et))
    res["perq"]=";".join(f"{q}:{pq[q]:.0f}" for q in sorted(pq))
    return res

if __name__=="__main__":
    work=[(rr,w) for rr in RRS for w in ("train","oos","full")]
    rows=list(ProcessPoolExecutor(max_workers=6).map(run, work))
    by={}
    for r in rows: by.setdefault(r["rr"],{})[r["win"]]=r
    print(f"{'RR':>5} | {'window':>6} {'n':>5} {'win%':>6} {'PF':>7} {'net':>8} {'dd':>7}  exits")
    for rr in RRS:
        for w in ("train","oos","full"):
            r=by[rr][w]
            print(f"{rr:>5} | {w:>6} {r['n']:>5} {r['winp']:>6.1f} {r['pf']:>7.3f} {r['net']:>8.0f} {r['dd']:>7.0f}  {r['exits']}")
        print(f"      | full perq: {by[rr]['full']['perq']}")
    # also write csv
    with open(f"{OUTD}/validate_results.csv","w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=["rr","win","n","winp","net","pf","dd","exits","perq"])
        w.writeheader()
        for r in rows: w.writerow(r)
