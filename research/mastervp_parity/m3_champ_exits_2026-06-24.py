#!/usr/bin/env python3
"""
m3_champ_exits_2026-06-24.py — FOLLOW-UP to the MTF-confluence study (REJECTED).

The MTF finding: acting earlier on M3 makes more NET (+18% vs the M5 champion) but is much rougher
(maxDD 13.7% vs 7.6%, 4/6 folds, worst-fold PF 0.732 vs 1.094). The confluence GATE destroyed the net
instead of taming the roughness. Open question the user approved: the M3 base inherits the OLD
Pine-faithful M3 lock's exits (TP1ClosePct=20, TrailAtrMult=2.0) — it NEVER received the champion's
WF-locked exit improvements. Does giving M3 the champion's research-validated exit geometry (+ T2/T3
locks) + a DD limiter recover robustness WITHOUT the gate?

Champion (M5 lock) post-baseline locks the M3 lock never got:
  - InpTp1ClosePct  20 -> 0    (T3 exit sweep: monotonic; banking partial caps the runner edge)
  - InpTrailAtrMult 2.0 -> 2.5 (M5 sweep)
  - InpEnableReversion false -> true  (T3: balance-regime fade, additive dd-smoothing)
  - InpBlockedHoursStr '' -> 2,3,14   (T2 hour-block lock)
NB: VP/buf/sl (120/0.7/1.0 vs 108/0.85/1.2) are TF-tuned and kept at the M3 lock — we are testing the
EXIT/limiter axis, not re-tuning entry geometry for M3.

Stage 1 (port champion exits onto the M3 base, cumulative):
  A  M5 champion (reference, main=M5)
  B  M3 lock as-is (the MTF study's "B")           -> net 25,162 / dd 13.7% / worstPF 0.732
  C1 B + TP1ClosePct=0
  C2 B + TrailAtrMult=2.5
  C3 B + TP1=0 + Trail2.5            (champion EXIT geometry)
  C4 C3 + Reversion=true             (+ champion T3)
  C5 C4 + BlockedHours=2,3,14        (+ champion T2)  == "M3 with ALL champion post-baseline locks"
Stage 2 (DD limiter on the best Stage-1 arm — picked at runtime as max net with worstPF gain):
  + MaxPeakDDPct in {15,20,25} ; + LossStreakCount in {3,4} ; + MaxDailyDDPct tighten {7,5}

T1 keeper rule: beat the M5 champion on POOLED net AND not degrade worst-fold PF (>= 1.094).
Engine = ranking proxy; any keeper needs an MT5 A/B before a lock.

Usage:  python3 research/mastervp_parity/m3_champ_exits_2026-06-24.py
"""
import csv, subprocess, sys, tempfile
from pathlib import Path
from slice_ticks_by_fold import FOLDS

ROOT = Path(__file__).resolve().parents[2]
BT = ROOT / "cpp_core/build/backtester"
T = ROOT / "cpp_core/tools"
SLICE = T / "fold_slices"
START_BAL = 10000.0
M3_BARS = T / "bars_xauusd_2025_2026_m3.csv"
M5_BARS = T / "bars_xauusd_2025_2026_m5.csv"
M5_LOCK = T / "mastervp/kkmastervp_xau_m5_LOCKED.set"
M3_LOCK = T / "mastervp/kkmastervp_xau_m3_LOCKED.set"


def read_base(path):
    out = []
    for line in Path(path).read_text().splitlines():
        s = line.split(";", 1)[0].strip()
        if "=" in s:
            k, v = s.split("=", 1)
            out.append((k.strip(), v.strip()))
    return out


def write_set(base_kv, overrides, path):
    d = dict(base_kv); d.update({k: str(v) for k, v in overrides.items()})
    with open(path, "w") as f:
        for k, v in d.items():
            f.write(f"{k}={v}\n")


def run_fold(bars, m5, set_path, fold, out_csv, ticks):
    name, frm, to = fold
    cmd = [str(BT), "--bars", str(bars), "--ticks", str(ticks), "--set-all", str(set_path),
           "--trade-from-ms", str(frm), "--trade-to-ms", str(to), "--symbol-xau", "--out", str(out_csv)]
    if m5:
        cmd += ["--bars-m5", str(m5)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-400:]); return None
    return out_csv


def read_trades(p):
    with open(p) as f:
        return [float(row["realizedUsd"]) for row in csv.DictReader(f)]


def stats(pnls):
    n = len(pnls)
    if n == 0:
        return dict(n=0, win=0.0, pf=0.0, net=0.0, maxdd_pct=0.0)
    wins = [p for p in pnls if p > 0]; gl = -sum(p for p in pnls if p <= 0); gw = sum(wins)
    eq = peak = START_BAL; maxdd = 0.0
    for p in pnls:
        eq += p; peak = max(peak, eq); maxdd = max(maxdd, peak - eq)
    return dict(n=n, win=100*len(wins)/n, pf=(gw/gl if gl > 0 else float("inf")),
                net=sum(pnls), maxdd_pct=100*maxdd/peak if peak else 0.0)


def eval_arm(bars, m5, set_path, tmpd, idx):
    per, pool = [], []
    for j, fold in enumerate(FOLDS):
        tp = SLICE / f"ticks_xau_{fold[0]}.csv"
        oc = tmpd / f"a{idx}_f{j}.csv"
        if run_fold(bars, m5, set_path, fold, oc, tp) is None:
            per.append(stats([])); continue
        pnls = read_trades(oc); per.append(stats(pnls)); pool += pnls
    m = stats(pool)
    pfs = [f["pf"] for f in per if f["n"] > 0]
    m["per"] = per
    m["worst_pf"] = min(pfs) if pfs else 0.0
    m["folds_pf1"] = sum(1 for f in per if f["pf"] > 1.0)
    m["folds_pos"] = sum(1 for f in per if f["net"] > 0)
    return m


def fmt(m):
    return (f"n={m['n']:4d} win={m['win']:4.1f} PF={m['pf']:.3f} net={m['net']:8,.0f} "
            f"dd={m['maxdd_pct']:4.1f}% | +={m['folds_pos']}/6 PF>1={m['folds_pf1']}/6 worstPF={m['worst_pf']:.3f}")


def perfold(m):
    return "        " + "  ".join(f"{fd[0]}:PF{f['pf']:.2f}/${f['net']:,.0f}" for fd, f in zip(FOLDS, m["per"]))


def main():
    tmpd = Path(tempfile.mkdtemp(prefix="m3champ_"))
    m3kv = read_base(M3_LOCK); m5kv = read_base(M5_LOCK)

    champ_exits = {"InpTp1ClosePct": "0.0", "InpTrailAtrMult": "2.5"}
    arms = [
        ("A M5champion(ref)", M5_BARS, None, m5kv, {}),
        ("B M3lock asis",     M3_BARS, None, m3kv, {}),
        ("C1 M3 +tp1=0",      M3_BARS, None, m3kv, {"InpTp1ClosePct": "0.0"}),
        ("C2 M3 +trail2.5",   M3_BARS, None, m3kv, {"InpTrailAtrMult": "2.5"}),
        ("C3 M3 +champExit",  M3_BARS, None, m3kv, dict(champ_exits)),
        ("C4 C3 +reversion",  M3_BARS, None, m3kv, {**champ_exits, "InpEnableReversion": "true"}),
        ("C5 C4 +blkhrs",     M3_BARS, None, m3kv, {**champ_exits, "InpEnableReversion": "true",
                                                    "InpBlockedHoursStr": "2,3,14"}),
    ]

    print("# M3-with-champion-exits follow-up — XAU, 6 folds. Stage 1: port champ exits onto M3 base", flush=True)
    champ = None
    stage1 = []
    for i, (label, bars, m5, base_kv, ov) in enumerate(arms):
        sp = tmpd / f"a{i}.set"; write_set(base_kv, ov, sp)
        m = eval_arm(bars, m5, sp, tmpd, i); m["_label"] = label; m["_base"] = base_kv; m["_ov"] = ov
        m["_bars"] = bars
        print(f"  {label:20s} {fmt(m)}", flush=True); print(perfold(m), flush=True)
        if i == 0:
            champ = m
        else:
            stage1.append(m)

    # pick best Stage-1 arm to carry into the DD-limiter stage: highest net among the M3 arms
    best = max(stage1, key=lambda m: m["net"])
    print(f"\n# Stage 2: DD-limiter sweep on best Stage-1 arm = {best['_label']} "
          f"(net {best['net']:,.0f}, worstPF {best['worst_pf']:.3f})", flush=True)
    limiters = []
    for v in ["15.0", "20.0", "25.0"]:
        limiters.append((f"L peakDD={v}", {**best["_ov"], "InpMaxPeakDDPct": v}))
    for v in ["3", "4"]:
        limiters.append((f"L lossStrk={v}", {**best["_ov"], "InpLossStreakCount": v}))
    for v in ["7.0", "5.0"]:
        limiters.append((f"L dailyDD={v}", {**best["_ov"], "InpMaxDailyDDPct": v}))

    stage2 = []
    for k, (label, ov) in enumerate(limiters):
        sp = tmpd / f"l{k}.set"; write_set(best["_base"], ov, sp)
        m = eval_arm(best["_bars"], None, sp, tmpd, 100 + k); m["_label"] = label
        print(f"  {label:20s} {fmt(m)}", flush=True); print(perfold(m), flush=True)
        stage2.append(m)

    print(f"\n=== vs champion (A M5: PF {champ['pf']:.3f} net {champ['net']:,.0f} "
          f"dd {champ['maxdd_pct']:.1f}% worstPF {champ['worst_pf']:.3f}) ===", flush=True)
    for m in stage1 + stage2:
        dn = m["net"] - champ["net"]; dpf = m["pf"] - champ["pf"]
        keep = "KEEPER" if (m["net"] > champ["net"] and m["worst_pf"] >= champ["worst_pf"]) else ""
        print(f"  {m['_label']:20s} dNet={dn:+8,.0f} dPF={dpf:+.3f} worstPF={m['worst_pf']:.3f} "
              f"dd={m['maxdd_pct']:.1f}% {keep}", flush=True)


if __name__ == "__main__":
    main()
