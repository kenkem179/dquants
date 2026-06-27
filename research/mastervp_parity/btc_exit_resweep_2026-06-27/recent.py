#!/usr/bin/env python3
"""Reconcile BTC backtest with the user's production experience:
- period breakdown (2025H1 / 2025H2 / 2026) for the DEPLOYED config
- Ladder preset (user may run this)
- BE-after-TP1 ON vs OFF (quantify the mechanism the user emphasizes)
Uses the DEPLOYED 1.07 .set as base; --set-all/--symbol-btc/--trade-from-ms."""
import csv, os, subprocess, tempfile
from concurrent.futures import ProcessPoolExecutor

ROOT="/Users/tokyotechies/Workspace/KEM/dquants"
BIN=f"{ROOT}/cpp_core/build/backtester"
OUTD=f"{ROOT}/research/mastervp_parity/btc_exit_resweep_2026-06-27"
TICKS=f"{ROOT}/cpp_core/tools/ticks_btcusd_2024_2026.csv"
BARS=f"{ROOT}/cpp_core/tools/bars_btcusd_2025_2026_m5.csv"
DEPLOYED=f"{ROOT}/mql5/experts/KK-MasterVP/releases/1.07/KK-MasterVP-1.07-btcusd-m5.set"
FRM="1735689600000"
LADDER={"InpPmProgTrail":"true","InpPmProgTriggerR":"1.0","InpPmProgIncrementR":"0.3","InpPmProgStepR":"0.20"}

def load_base():
    kv={}
    for ln in open(DEPLOYED):
        ln=ln.strip()
        if ln and "=" in ln and not ln.startswith(";"): k,v=ln.split("=",1); kv[k.strip()]=v.strip()
    return kv

def period(t):
    y=int(t[:4]); mo=int(t[5:7])
    if y==2025 and mo<=6: return "2025H1"
    if y==2025: return "2025H2"
    return "2026"

def run(job):
    name,ov=job
    base=load_base(); base.update(ov)
    fd,sp=tempfile.mkstemp(suffix=".set",dir=OUTD); os.close(fd)
    open(sp,"w").write("".join(f"{k}={v}\n" for k,v in base.items()))
    out=os.path.join(OUTD,f"rec_{name}.csv")
    subprocess.run([BIN,"--bars",BARS,"--ticks",TICKS,"--set-all",sp,"--symbol-btc",
                    "--trade-from-ms",FRM,"--out",out],capture_output=True,text=True)
    os.unlink(sp)
    per={}; tags={}; pnl=[]; eq=10000.0; peak=10000.0; dd=0.0
    for r in csv.DictReader(open(out)):
        p=float(r["realizedUsd"]); pnl.append(p)
        pp=period(r["entryTimeUTC"]); per.setdefault(pp,[]).append(p)
        tags[r["exitTag"]]=tags.get(r["exitTag"],0)+1
        eq+=p; peak=max(peak,eq); dd=max(dd,peak-eq)
    def pf(xs):
        w=sum(x for x in xs if x>0); l=abs(sum(x for x in xs if x<0)); return w/l if l else 9.99
    res={"name":name,"n":len(pnl),"net":sum(pnl),"pf":pf(pnl),"maxdd":dd,"tags":tags}
    for pp in ("2025H1","2025H2","2026"):
        xs=per.get(pp,[]); res[pp]=(len(xs),sum(xs),pf(xs))
    return res

if __name__=="__main__":
    jobs=[("deployed_BASE",{}),
          ("Ladder_T1.0",LADDER),
          ("BASE_noBE",{"InpBeAfterTp1":"false"})]
    rows=list(ProcessPoolExecutor(max_workers=2).map(run,jobs))
    print(f"\n{'config':>14} {'n':>5} {'PF':>6} {'net':>7} {'maxDD':>6} | "
          f"{'2025H1':>16} {'2025H2':>16} {'2026':>16}")
    for r in rows:
        def c(pp): n,nt,p=r[pp]; return f"{nt:+.0f}({p:.2f},n{n})"
        print(f"{r['name']:>14} {r['n']:>5} {r['pf']:>6.3f} {r['net']:>7.0f} {r['maxdd']:>6.0f} | "
              f"{c('2025H1'):>16} {c('2025H2'):>16} {c('2026'):>16}")
    print("\nexit-tag distribution (BE-protected exits visible here):")
    for r in rows: print(f"  {r['name']}: {r['tags']}")
