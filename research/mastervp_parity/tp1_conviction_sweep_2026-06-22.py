#!/usr/bin/env python3
"""
tp1_conviction_sweep_2026-06-22.py — TP1 / profit-protection redesign sweep.

The user's complaint: a winner nearly hit full TP then retraced and handed back >50% of the move.
Two complementary, default-OFF levers (engine):
  (A) GIVEBACK-CAP (blind, kk::common::ProfitManager #3): once MFE >= arm_r, ratchet the stop so it
      can never give back more than cap_frac of the PEAK gain. Keys InpPmGiveback / InpPmGivebackArmR
      / InpPmGivebackCapFrac.
  (B) CONVICTION-PROTECT (the user's idea): once MFE >= arm_r AND the near-price VP node-net flips
      AGAINST the trade (panel "Net ▼/over"), bank a one-shot partial AND lock lock_frac of the peak.
      Keys InpEnableConvictionProtect / InpConvictionArmR / InpConvictionNetMin /
      InpConvictionPartialFrac / InpConvictionLockFrac.

We sweep each ALONE and COMBINED on train+OOS, plateau-pick (positive on BOTH windows; must improve
risk-adjusted result — net AND/OR dd — without degrading the other window). The single chart is NOT
evidence; a winner here goes to walk-forward + the overfitting gate before any lock.

Run from repo root, conda env kenkem:
  python research/mastervp_parity/tp1_conviction_sweep_2026-06-22.py [XAU-M5|XAU-M3|BTC-M5|all]
"""
import csv, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT   = ROOT / "cpp_core/build/backtester"
T    = ROOT / "cpp_core/tools"
START_BAL = 10000.0
OOS_END_XAU = 1775520000000

CASES = {
  "XAU-M5": dict(symbol="xau", bars="bars_xauusd_2025_2026_m5.csv",
                 base="cpp_core/tools/mastervp/kkmastervp_xau_m5_LOCKED.set",
                 train="ticks_xau_train.csv", train_from=1750291200000, train_to=1769904000000,
                 oos="ticks_xau_oos.csv",     oos_from=1769904000000,   oos_to=OOS_END_XAU),
  "XAU-M3": dict(symbol="xau", bars="bars_xauusd_2025_2026_m3.csv",
                 base="cpp_core/tools/mastervp/kkmastervp_xau_m3_LOCKED.set",
                 train="ticks_xau_train.csv", train_from=1750291200000, train_to=1769904000000,
                 oos="ticks_xau_oos.csv",     oos_from=1769904000000,   oos_to=OOS_END_XAU),
  "BTC-M5": dict(symbol="btc", bars="bars_btcusd_2025_2026_m5.csv",
                 base="cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set",
                 train="ticks_btcusd_2025_window.csv", train_from=1754870400114, train_to=1764527344650,
                 oos="ticks_btcusd_2026_oos.csv",      oos_from=1767225605830,   oos_to=1781049599584),
}

# config rows: label + override keys. Baseline first.
GRID = [
  dict(label="BASE (off)"),
  # (A) blind giveback-cap: lock (1-cap) of peak after MFE>=arm
  dict(label="give arm1.0 cap0.3", InpPmGiveback="true", InpPmGivebackArmR=1.0, InpPmGivebackCapFrac=0.3),
  dict(label="give arm1.0 cap0.5", InpPmGiveback="true", InpPmGivebackArmR=1.0, InpPmGivebackCapFrac=0.5),
  dict(label="give arm1.5 cap0.3", InpPmGiveback="true", InpPmGivebackArmR=1.5, InpPmGivebackCapFrac=0.3),
  dict(label="give arm2.0 cap0.3", InpPmGiveback="true", InpPmGivebackArmR=2.0, InpPmGivebackCapFrac=0.3),
  dict(label="give arm2.0 cap0.5", InpPmGiveback="true", InpPmGivebackArmR=2.0, InpPmGivebackCapFrac=0.5),
  dict(label="give arm3.0 cap0.3", InpPmGiveback="true", InpPmGivebackArmR=3.0, InpPmGivebackCapFrac=0.3),
  # (B) conviction-protect: partial 50% + lock 50% of peak, gated on near-price net flip
  dict(label="conv arm1.0 net.2", InpEnableConvictionProtect="true", InpConvictionArmR=1.0, InpConvictionNetMin=0.2),
  dict(label="conv arm1.0 net.3", InpEnableConvictionProtect="true", InpConvictionArmR=1.0, InpConvictionNetMin=0.3),
  dict(label="conv arm1.0 net.5", InpEnableConvictionProtect="true", InpConvictionArmR=1.0, InpConvictionNetMin=0.5),
  dict(label="conv arm1.5 net.3", InpEnableConvictionProtect="true", InpConvictionArmR=1.5, InpConvictionNetMin=0.3),
  dict(label="conv arm2.0 net.3", InpEnableConvictionProtect="true", InpConvictionArmR=2.0, InpConvictionNetMin=0.3),
  dict(label="conv a1 n.3 p.3 lk.6", InpEnableConvictionProtect="true", InpConvictionArmR=1.0, InpConvictionNetMin=0.3, InpConvictionPartialFrac=0.3, InpConvictionLockFrac=0.6),
  dict(label="conv a1 n.3 p.7 lk.5", InpEnableConvictionProtect="true", InpConvictionArmR=1.0, InpConvictionNetMin=0.3, InpConvictionPartialFrac=0.7, InpConvictionLockFrac=0.5),
  # combined: blind cap as a floor + conviction partial as the active bank
  dict(label="give2.0c.3 + conv1.0n.3", InpPmGiveback="true", InpPmGivebackArmR=2.0, InpPmGivebackCapFrac=0.3,
       InpEnableConvictionProtect="true", InpConvictionArmR=1.0, InpConvictionNetMin=0.3),
]

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
    print("\n"+"="*108)
    print(f"{name}   base={Path(c['base']).name}")
    print("="*108)
    print(f"{'config':<24} | {'TRAIN':^42} | {'OOS':^42}")
    print("-"*108)
    for g in GRID:
        ov={k:v for k,v in g.items() if k!="label"}
        sp=tempfile.mktemp(suffix=".set"); write_set(base,ov,sp)
        tr=run(c, sp, c["train"], c["train_from"], c["train_to"])
        oo=run(c, sp, c["oos"],   c["oos_from"],   c["oos_to"])
        print(f"{g['label']:<24} | {cell(tr):^42} | {cell(oo):^42}")

if __name__=="__main__":
    which=sys.argv[1] if len(sys.argv)>1 else "all"
    targets=[which] if which in CASES else list(CASES)
    for t in targets:
        sweep_case(t)
