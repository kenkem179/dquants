#!/usr/bin/env python3
"""
resweep_2026-06-22.py — post-Monster-merge sanity re-sweep of KK-MasterVP on all 4 cases
(XAU/BTC x M3/M5). Confirms the consolidated engine (impulse now a first-class, default-OFF
MasterVP lever) (A) still reproduces each lock, (B) whether the now-integrated impulse path
opens any OOS gain when run above a vol ceiling, and (C) that the locked dominant levers still
sit on a local plateau. Read-only on the .set files; writes temp sets to /tmp.

Run from repo root, conda env kenkem:
  python research/mastervp_parity/resweep_2026-06-22.py
"""
import csv, subprocess, sys, tempfile, os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT   = ROOT / "cpp_core/build/backtester"
T    = ROOT / "cpp_core/tools"
START_BAL = 10000.0

CASES = {
  "XAU-M3": dict(symbol="xau", bars="bars_xauusd_2025_2026_m3.csv", m1="bars_xauusd_2024_2026_m1.csv",
                 oos="ticks_xau_oos.csv",            oos_from=1769904000000,
                 train="ticks_xau_train.csv",        train_from=1750291200000,
                 base="cpp_core/tools/mastervp/kkmastervp_xau_m3_LOCKED.set",
                 doc_oos="lock OOS PF 1.114 / dd 17.5%"),
  "XAU-M5": dict(symbol="xau", bars="bars_xauusd_2025_2026_m5.csv", m1="bars_xauusd_2024_2026_m1.csv",
                 oos="ticks_xau_oos.csv",            oos_from=1769904000000,
                 train="ticks_xau_train.csv",        train_from=1750291200000,
                 base="cpp_core/tools/mastervp/kkmastervp_xau_m5_LOCKED.set",
                 doc_oos="lock OOS PF 1.327 / dd 10.3% (front-runner)"),
  "BTC-M5": dict(symbol="btc", bars="bars_btcusd_2025_2026_m5.csv", m1="bars_btcusd_2024_2026_m1.csv",
                 oos="ticks_btcusd_2026_oos.csv",    oos_from=1767225605830,
                 train="ticks_btcusd_2025_window.csv", train_from=1754870400114,
                 base="cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set",
                 doc_oos="lock OOS PF 1.214 / dd 14.2% (tail-skewed)"),
  "BTC-M3": dict(symbol="btc", bars="bars_btcusd_2025_2026_m3.csv", m1="bars_btcusd_2024_2026_m1.csv",
                 oos="ticks_btcusd_2026_oos.csv",    oos_from=1767225605830,
                 train="ticks_btcusd_2025_window.csv", train_from=1754870400114,
                 base="cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set",   # no lock; btc structural base
                 doc_oos="NO LOCK (prior: no edge, OOS collapses)"),
}

def read_base(path):
    out = []
    for line in (ROOT/path).read_text().splitlines():
        s = line.split(";",1)[0].strip()
        if "=" in s:
            k,v = s.split("=",1); out.append((k.strip(), v.strip()))
    return out

def write_set(base_kv, ov, path):
    d = dict(base_kv); d.update({k:str(v) for k,v in ov.items()})
    with open(path,"w") as f:
        for k,v in d.items(): f.write(f"{k}={v}\n")

def run(case, set_path, ticks, frm, with_m1):
    c = CASES[case]
    out = tempfile.mktemp(suffix=".csv")
    cmd = [str(BT), "--bars", str(T/c["bars"]), "--ticks", str(T/ticks),
           "--set-all", str(set_path), f"--symbol-{c['symbol']}",
           "--trade-from-ms", str(frm), "--out", out]
    if with_m1: cmd += ["--bars-m1", str(T/c["m1"])]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-400:]); return None
    return metrics(out)

def metrics(csv_path):
    pnls, tags = [], []
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            pnls.append(float(row["realizedUsd"])); tags.append(row["exitTag"])
    n = len(pnls)
    if n == 0: return dict(n=0, net=0, pf=0, maxdd_pct=0, calmar=0, win=0)
    wins=[p for p in pnls if p>0]; losses=[p for p in pnls if p<=0]
    gw,gl=sum(wins),-sum(losses)
    eq,peak,maxdd=START_BAL,START_BAL,0.0
    for p in pnls:
        eq+=p; peak=max(peak,eq); maxdd=max(maxdd,peak-eq)
    return dict(n=n, win=100*len(wins)/n, pf=(gw/gl if gl>0 else 999.0),
                net=sum(pnls), maxdd_pct=100*maxdd/peak if peak else 0,
                calmar=(sum(pnls)/maxdd if maxdd>0 else 999.0))

def fmt(m):
    if m is None: return "  (run failed)"
    if m["n"]==0: return "  n=0 (no trades)"
    return f"n={m['n']:4d}  win={m['win']:4.1f}%  PF={m['pf']:.3f}  net={m['net']:+9.0f}  maxDD={m['maxdd_pct']:4.1f}%  calmar={m['calmar']:.2f}"

CEILINGS = [0.158, 0.30]          # vol ceilings to test impulse above (0.158 = Monster's)
LEVERS = {                        # one-at-a-time plateau probe around each lock value
  "InpBreakBufAtr":  [-0.15, +0.15],
  "InpSlAtrBrk":     [-0.3,  +0.3],
  "InpTrailAtrMult": [-0.5,  +0.5],
}

def main():
    for case, c in CASES.items():
        base = read_base(c["base"])
        bd = dict(base)
        print("\n" + "="*78)
        print(f"{case}   base={Path(c['base']).name}   [{c['doc_oos']}]")
        print("="*78)

        # (A) regression: lock as-is on OOS (impulse off)
        sp = tempfile.mktemp(suffix=".set"); write_set(base, {}, sp)
        a = run(case, sp, c["oos"], c["oos_from"], with_m1=False)
        print(f"(A) lock OOS                : {fmt(a)}")

        # (B) impulse opportunity: ceiling-only vs ceiling+impulse, OOS
        for C in CEILINGS:
            sp1=tempfile.mktemp(suffix=".set")
            write_set(base, {"InpMaxAtrPct":C, "InpEnableImpulse":"false"}, sp1)
            b1=run(case, sp1, c["oos"], c["oos_from"], with_m1=False)
            sp2=tempfile.mktemp(suffix=".set")
            write_set(base, {"InpMaxAtrPct":C, "InpEnableImpulse":"true"}, sp2)
            b2=run(case, sp2, c["oos"], c["oos_from"], with_m1=True)
            print(f"(B) ceiling {C:>5} only      : {fmt(b1)}")
            print(f"(B) ceiling {C:>5} +impulse  : {fmt(b2)}")

        # (C) plateau probe: vary each dominant lever +/- one step, OOS
        for key, deltas in LEVERS.items():
            if key not in bd: continue
            try: cur=float(bd[key])
            except: continue
            cells=[]
            for d in deltas:
                v=round(cur+d,3)
                if v<=0: cells.append(f"{key.replace('Inp','')}={v}:skip"); continue
                spc=tempfile.mktemp(suffix=".set"); write_set(base,{key:v},spc)
                m=run(case, spc, c["oos"], c["oos_from"], with_m1=False)
                cells.append(f"{v}->PF{m['pf']:.3f}/net{m['net']:+.0f}" if m and m['n'] else f"{v}->n0")
            print(f"(C) {key:<18} lock={cur:<6} | " + "  ".join(cells))

if __name__=="__main__":
    main()
