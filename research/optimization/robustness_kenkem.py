#!/usr/bin/env python3
"""Robustness on OUR engine's trade logs (no MT5 needed — kk::kenkem is the authoritative backtest).
Monthly breakdown + Monte-Carlo bootstrap for a trades CSV (ts_ms,...,pnlUsd)."""
import csv, os, sys, random
from datetime import datetime, timezone

# shared, strategy-agnostic overfitting gate (research/stats/)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from stats.gate import run_gate, print_gate

def load(path):
    rows=[]
    for r in csv.DictReader(open(path)):
        rows.append((int(r["ts_ms"]), float(r["pnlUsd"]), r["kind"]))
    rows.sort()
    return rows

def pf(x):
    gp=sum(v for v in x if v>0); gl=-sum(v for v in x if v<0)
    return gp/gl if gl>0 else (9.9 if gp>0 else 0.0)

def maxdd(pnls):
    peak=cum=dd=0.0
    for p in pnls:
        cum+=p; peak=max(peak,cum); dd=max(dd,peak-cum)
    return dd

def report(label, path):
    rows=load(path)
    pnls=[p for _,p,_ in rows]
    print(f"\n=== {label} ===  trades={len(pnls)} net={sum(pnls):,.0f} PF={pf(pnls):.3f} maxDD={maxdd(pnls):,.0f}")
    # monthly
    months={}
    for ts,p,_ in rows:
        m=datetime.fromtimestamp(ts/1000,tz=timezone.utc).strftime("%Y-%m")
        months.setdefault(m,[]).append(p)
    pos=0
    print("  month     trades   net      PF")
    for m in sorted(months):
        x=months[m]; print(f"  {m}    {len(x):5d}  {sum(x):8,.0f}  {pf(x):.3f}")
        if sum(x)>0: pos+=1
    print(f"  -> {pos}/{len(months)} months positive")
    # by-entry
    byk={}
    for _,p,k in rows: byk.setdefault(k,[]).append(p)
    print("  by entry: " + "  ".join(f"{k}={sum(v):,.0f}/PF{pf(v):.2f}(n{len(v)})" for k,v in sorted(byk.items())))
    # Monte Carlo
    random.seed(7); B=5000; nets=[]; pfs=[]
    for _ in range(B):
        s=[random.choice(pnls) for _ in range(len(pnls))]
        nets.append(sum(s)); pfs.append(pf(s))
    nets.sort(); pfs.sort()
    prof=sum(1 for v in nets if v>0)/B*100
    print(f"  MC(5000): %profitable={prof:.1f}  netP5={nets[int(.05*B)]:,.0f}  PF_P5={pfs[int(.05*B)]:.3f}  PF_P50={pfs[int(.5*B)]:.3f}")
    # overfitting gate (fixed-$ sizing -> per-trade pnl IS the return series; Sharpe is scale-free)
    print_gate(run_gate(pnls), label)

if __name__=="__main__":
    for label,path in [("BTC 2026 OOS (E1+E4+E5)","/tmp/kk_btc26.csv"),
                       ("XAU 2026 OOS (E4+E5)","/tmp/kk_xau26.csv"),
                       ("BTC 2025 IS (E1+E4+E5)","/tmp/kk_btc25.csv"),
                       ("XAU 2025 IS (E4+E5)","/tmp/kk_xau25.csv")]:
        try: report(label,path)
        except FileNotFoundError: pass
