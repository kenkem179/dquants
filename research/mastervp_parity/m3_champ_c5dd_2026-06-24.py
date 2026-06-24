#!/usr/bin/env python3
"""
m3_champ_c5dd_2026-06-24.py — Stage 3 of the M3-with-champion-exits follow-up.

Stage 1/2 (m3_champ_exits_2026-06-24.py) found C5 = M3 base + champion exits (tp1=0, trail2.5)
+ reversion + T2 blocked-hours(2,3,14) is the robustness winner:
  net 30,602 (+44% vs M5 champion) / dd 11.2% / 5-6 folds / worstPF 0.955 (F3 -834, was -4,002).
The auto DD-limiter sweep ran on C1 (highest raw net) not C5, missing the right base. This stacks DD
limiters on C5 to try to push the last negative fold (F3) green and lift worstPF >= champion 1.094.

T1 keeper: beat M5 champion on POOLED net AND worstPF >= 1.094. Engine = ranking proxy -> MT5 A/B before lock.
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
            k, v = s.split("=", 1); out.append((k.strip(), v.strip()))
    return out


def write_set(base_kv, overrides, path):
    d = dict(base_kv); d.update({k: str(v) for k, v in overrides.items()})
    with open(path, "w") as f:
        for k, v in d.items():
            f.write(f"{k}={v}\n")


def run_fold(bars, set_path, fold, out_csv, ticks):
    name, frm, to = fold
    cmd = [str(BT), "--bars", str(bars), "--ticks", str(ticks), "--set-all", str(set_path),
           "--trade-from-ms", str(frm), "--trade-to-ms", str(to), "--symbol-xau", "--out", str(out_csv)]
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


def eval_arm(bars, set_path, tmpd, idx):
    per, pool = [], []
    for j, fold in enumerate(FOLDS):
        tp = SLICE / f"ticks_xau_{fold[0]}.csv"; oc = tmpd / f"a{idx}_f{j}.csv"
        if run_fold(bars, set_path, fold, oc, tp) is None:
            per.append(stats([])); continue
        pnls = read_trades(oc); per.append(stats(pnls)); pool += pnls
    m = stats(pool); pfs = [f["pf"] for f in per if f["n"] > 0]
    m["per"] = per; m["worst_pf"] = min(pfs) if pfs else 0.0
    m["folds_pf1"] = sum(1 for f in per if f["pf"] > 1.0)
    m["folds_pos"] = sum(1 for f in per if f["net"] > 0)
    return m


def fmt(m):
    return (f"n={m['n']:4d} win={m['win']:4.1f} PF={m['pf']:.3f} net={m['net']:8,.0f} "
            f"dd={m['maxdd_pct']:4.1f}% | +={m['folds_pos']}/6 PF>1={m['folds_pf1']}/6 worstPF={m['worst_pf']:.3f}")


def perfold(m):
    return "        " + "  ".join(f"{fd[0]}:PF{f['pf']:.2f}/${f['net']:,.0f}" for fd, f in zip(FOLDS, m["per"]))


def main():
    tmpd = Path(tempfile.mkdtemp(prefix="c5dd_"))
    m3kv = read_base(M3_LOCK); m5kv = read_base(M5_LOCK)
    C5 = {"InpTp1ClosePct": "0.0", "InpTrailAtrMult": "2.5", "InpEnableReversion": "true",
          "InpBlockedHoursStr": "2,3,14"}

    arms = [("A M5champion(ref)", M5_BARS, m5kv, {}),
            ("C5 (no limiter)",   M3_BARS, m3kv, dict(C5))]
    for v in ["12.0", "15.0", "18.0", "20.0"]:
        arms.append((f"C5+peakDD={v}", M3_BARS, m3kv, {**C5, "InpMaxPeakDDPct": v}))
    for v in ["5.0", "7.0"]:
        arms.append((f"C5+dailyDD={v}", M3_BARS, m3kv, {**C5, "InpMaxDailyDDPct": v}))
    for v in ["3", "4"]:
        arms.append((f"C5+lossStrk={v}", M3_BARS, m3kv, {**C5, "InpLossStreakCount": v}))
    # best-combo guesses: peak + daily together
    arms.append(("C5+peak15+daily5", M3_BARS, m3kv, {**C5, "InpMaxPeakDDPct": "15.0", "InpMaxDailyDDPct": "5.0"}))
    arms.append(("C5+peak18+strk3",  M3_BARS, m3kv, {**C5, "InpMaxPeakDDPct": "18.0", "InpLossStreakCount": "3"}))

    print("# C5 DD-limiter Stage 3 — XAU 6 folds. C5 = M3 + champExit + reversion + blkhrs(2,3,14)", flush=True)
    results = []
    for i, (label, bars, base_kv, ov) in enumerate(arms):
        sp = tmpd / f"a{i}.set"; write_set(base_kv, ov, sp)
        m = eval_arm(bars, sp, tmpd, i); m["_label"] = label; results.append(m)
        print(f"  {label:20s} {fmt(m)}", flush=True); print(perfold(m), flush=True)

    champ = results[0]
    print(f"\n=== vs champion (A M5: PF {champ['pf']:.3f} net {champ['net']:,.0f} dd {champ['maxdd_pct']:.1f}% "
          f"worstPF {champ['worst_pf']:.3f}) ===", flush=True)
    for m in results[1:]:
        dn = m["net"] - champ["net"]; dpf = m["pf"] - champ["pf"]
        keep = "KEEPER" if (m["net"] > champ["net"] and m["worst_pf"] >= champ["worst_pf"]) else ""
        near = "NEAR" if (not keep and m["net"] > champ["net"] and m["worst_pf"] >= 1.0) else ""
        print(f"  {m['_label']:20s} dNet={dn:+8,.0f} dPF={dpf:+.3f} worstPF={m['worst_pf']:.3f} "
              f"dd={m['maxdd_pct']:.1f}% {keep}{near}", flush=True)


if __name__ == "__main__":
    main()
