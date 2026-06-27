#!/usr/bin/env python3
"""Focused BTC exit sweep (after the A/B showed the XAU exit helps marginally).
M5: RR x partial-TP (BTC-specific: partial may help BTC even though it hurt XAU).
M3: A baseline vs B XAU-geometry. Full window, --set-all/--symbol-btc/--trade-from-ms."""
import csv, os, subprocess, tempfile, statistics as st
from concurrent.futures import ProcessPoolExecutor

ROOT="/Users/tokyotechies/Workspace/KEM/dquants"
BIN=f"{ROOT}/cpp_core/build/backtester"
OUTD=f"{ROOT}/research/mastervp_parity/btc_exit_resweep_2026-06-27"
TICKS=f"{ROOT}/cpp_core/tools/ticks_btcusd_2024_2026.csv"
BARS={"m5":f"{ROOT}/cpp_core/tools/bars_btcusd_2025_2026_m5.csv",
      "m3":f"{ROOT}/cpp_core/tools/bars_btcusd_2025_2026_m3.csv"}
BASE={"m5":f"{ROOT}/cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set",
      "m3":f"{ROOT}/cpp_core/tools/mastervp/m3_base_btc.set"}
FRM="1735689600000"
LADDER={"InpPmProgTrail":"true","InpPmProgTriggerR":"2.0",
        "InpPmProgIncrementR":"0.75","InpPmProgStepR":"0.2",
        "InpTrailAtrMult":"2.75","InpBeBufAtr":"0.02"}

def load_base(tf):
    kv={}
    for ln in open(BASE[tf]):
        ln=ln.strip()
        if ln and "=" in ln and not ln.startswith(";"): k,v=ln.split("=",1); kv[k.strip()]=v.strip()
    return kv
def quarter(t): return f"{int(t[:4])}Q{(int(t[5:7])-1)//3+1}"

def run(job):
    tf,ov,tag=job
    base=load_base(tf); base.update(ov)
    fd,sp=tempfile.mkstemp(suffix=".set",dir=OUTD); os.close(fd)
    open(sp,"w").write("".join(f"{k}={v}\n" for k,v in base.items()))
    out=os.path.join(OUTD,f"s2_{tf}_{tag}.csv")
    subprocess.run([BIN,"--bars",BARS[tf],"--ticks",TICKS,"--set-all",sp,"--symbol-btc",
                    "--trade-from-ms",FRM,"--out",out],capture_output=True,text=True)
    os.unlink(sp)
    pnl=[];mfe=[];pq={};eq=10000.0;peak=10000.0;dd=0.0
    for r in csv.DictReader(open(out)):
        p=float(r["realizedUsd"]);pnl.append(p);mfe.append(float(r["mfeR"]))
        q=quarter(r["entryTimeUTC"]);pq[q]=pq.get(q,0.0)+p
        eq+=p;peak=max(peak,eq);dd=max(dd,peak-eq)
    w=[p for p in pnl if p>0];l=[p for p in pnl if p<0]
    return {"tf":tf,"tag":tag,"n":len(pnl),"net":sum(pnl),
            "pf":(sum(w)/abs(sum(l))) if l else 9.99,"maxdd":dd,
            "perq":";".join(f"{q}:{pq[q]:.0f}" for q in sorted(pq))}

if __name__=="__main__":
    jobs=[]
    # M5: RR x partial, with the proven ladder
    for rr in ("3.2","4.0"):
        for part in ("0.0","20.0","33.0"):
            ov=dict(LADDER); ov["InpRunnerRr"]=rr; ov["InpTp1ClosePct"]=part
            jobs.append(("m5",ov,f"rr{rr}_p{part}"))
    # M3: A baseline (no override) vs B XAU-geometry
    jobs.append(("m3",{},"A_base"))
    ovB=dict(LADDER); ovB["InpRunnerRr"]="4.0"; ovB["InpTp1ClosePct"]="0.0"
    jobs.append(("m3",ovB,"B_xaugeom"))

    rows=list(ProcessPoolExecutor(max_workers=2).map(run,jobs))
    print(f"\n{'tf':>3} {'config':>16} {'n':>5} {'PF':>7} {'net':>8} {'maxDD':>7}  perq")
    for r in sorted(rows,key=lambda x:(x['tf'],-x['pf'])):
        flag=" <-- PF>1" if r['pf']>1.0 else ""
        print(f"{r['tf']:>3} {r['tag']:>16} {r['n']:>5} {r['pf']:>7.3f} {r['net']:>8.0f} {r['maxdd']:>7.0f}  {r['perq']}{flag}")
    with open(f"{OUTD}/sweep2_results.csv","w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0].keys()));w.writeheader()
        for r in rows: w.writerow(r)
