#!/usr/bin/env python3
"""BTC exit-geometry A/B — does the proven XAU M5 exit (capped RR + ProgTrail ladder)
rescue BTC vs the abandoned RunnerRr=10 / wide-trail geometry the BTC verdict used?

Same entries in both arms (B overrides ONLY exit keys) -> isolates the exit effect.
mfeR is exit-agnostic -> also reports entry-quality diagnostic (entry vs exit problem)."""
import csv, os, re, subprocess, sys, tempfile, statistics as st
from concurrent.futures import ProcessPoolExecutor

ROOT = "/Users/tokyotechies/Workspace/KEM/dquants"
BIN  = f"{ROOT}/cpp_core/build/backtester"
OUTD = f"{ROOT}/research/mastervp_parity/btc_exit_resweep_2026-06-27"
TICKS= f"{ROOT}/cpp_core/tools/ticks_btcusd_2024_2026.csv"
BASE = f"{ROOT}/cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set"
BARS = {"m5": f"{ROOT}/cpp_core/tools/bars_btcusd_2025_2026_m5.csv",
        "m3": f"{ROOT}/cpp_core/tools/bars_btcusd_2025_2026_m3.csv"}

# B = the proven XAU M5 exit geometry transplanted onto BTC entries
XAU_EXIT = {
    "InpRunnerRr": "4.0", "InpTrailAtrMult": "2.75", "InpBeBufAtr": "0.02",
    "InpTp1ClosePct": "0.0",
    "InpPmProgTrail": "true", "InpPmProgTriggerR": "2.0",
    "InpPmProgIncrementR": "0.75", "InpPmProgStepR": "0.2",
}

def load_base():
    kv={}
    for ln in open(BASE):
        ln=ln.strip()
        if ln and "=" in ln and not ln.startswith(";"):
            k,v=ln.split("=",1); kv[k.strip()]=v.strip()
    return kv

def quarter(t): y=int(t[:4]); mo=int(t[5:7]); return f"{y}Q{(mo-1)//3+1}"

def run(args):
    tf, arm = args
    base=load_base()
    if arm=="B": base.update(XAU_EXIT)
    fd,sp=tempfile.mkstemp(suffix=".set",dir=OUTD); os.close(fd)
    with open(sp,"w") as f:
        for k,v in base.items(): f.write(f"{k}={v}\n")
    out=os.path.join(OUTD,f"trades_btc_{tf}_{arm}.csv")
    # match the WF/revisit invocation EXACTLY: --set-all (non-input keys too), --symbol-btc,
    # --trade-from-ms = first bar ts (VP warms up ~720 bars before first signal).
    FRM = "1735689600000"  # 2025-01-01 (bars_btcusd_2025_2026 start)
    cmd=[BIN,"--bars",BARS[tf],"--ticks",TICKS,"--set-all",sp,"--symbol-btc",
         "--trade-from-ms",FRM,"--out",out]
    r=subprocess.run(cmd,capture_output=True,text=True); os.unlink(sp)
    # parse trades csv
    pnl=[]; mfe=[]; pq={}; eq=10000.0; peak=10000.0; dd=0.0
    try:
        for row in csv.DictReader(open(out)):
            p=float(row["realizedUsd"]); pnl.append(p); mfe.append(float(row["mfeR"]))
            q=quarter(row["entryTimeUTC"]); pq[q]=pq.get(q,0.0)+p
            eq+=p; peak=max(peak,eq); dd=max(dd,peak-eq)
    except FileNotFoundError: pass
    wins=[p for p in pnl if p>0]; losses=[p for p in pnl if p<0]
    pf=(sum(wins)/abs(sum(losses))) if losses else float('inf')
    return {"tf":tf,"arm":arm,"n":len(pnl),"net":sum(pnl),"pf":pf,"maxdd":dd,
            "win%":100*len(wins)/len(pnl) if pnl else 0,
            "mfe_med":st.median(mfe) if mfe else 0,
            "reach1R":100*sum(1 for m in mfe if m>=1.0)/len(mfe) if mfe else 0,
            "reach2R":100*sum(1 for m in mfe if m>=2.0)/len(mfe) if mfe else 0,
            "perq":";".join(f"{q}:{pq[q]:.0f}" for q in sorted(pq))}

if __name__=="__main__":
    tfs = sys.argv[1:] or ["m5"]
    work=[(tf,arm) for tf in tfs for arm in ("A","B")]
    rows=list(ProcessPoolExecutor(max_workers=len(work)).map(run, work))
    print(f"\n{'tf':>3} {'arm':>4} {'n':>5} {'win%':>6} {'PF':>7} {'net':>9} {'maxDD':>8} | "
          f"{'mfeMed':>7} {'reach1R':>8} {'reach2R':>8}")
    for r in rows:
        lbl = "A=RR10/T6/noladder" if r["arm"]=="A" else "B=RR4/T2.75/ladder"
        print(f"{r['tf']:>3} {r['arm']:>4} {r['n']:>5} {r['win%']:>6.1f} {r['pf']:>7.3f} "
              f"{r['net']:>9.0f} {r['maxdd']:>8.0f} | {r['mfe_med']:>7.2f} {r['reach1R']:>7.1f}% "
              f"{r['reach2R']:>7.1f}%   {lbl}")
    print("\nper-quarter:")
    for r in rows:
        print(f"  {r['tf']} {r['arm']}: {r['perq']}")
    with open(f"{OUTD}/ab_results.csv","w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0].keys())); w.writeheader()
        for r in rows: w.writerow(r)
