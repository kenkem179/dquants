#!/usr/bin/env python3
"""
m3_champ_gate_2026-06-24.py — overfitting gate on the M3-champion-exits winner (C5+peakDD18).

Re-runs the Stage-3 DD-limiter arms (so the search width is explicit), captures each arm's pooled
per-trade pnl, computes sr_trial_std = std of per-trade Sharpe ACROSS the swept configs (the
deflation benchmark), then runs research/stats/gate.run_gate() on the winner's pooled return series.
n_trials = total distinct configs evaluated in the M3-champion-exits hunt (Stage1 C1..C5 = 5,
Stage2 limiters on C1 = 7, Stage3 limiters on C5 = 10) = 22.

PSR-vs-0 + MinTRL apply regardless of search context; DSR uses (n_trials, sr_trial_std).
This is a PRE-MT5 deflation check — a real lock still needs the MT5 A/B (engine = ranking proxy).
"""
import csv, subprocess, sys, tempfile, math
from pathlib import Path
import numpy as np
from slice_ticks_by_fold import FOLDS

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "research"))
from stats.gate import run_gate, return_fractions  # noqa: E402

BT = ROOT / "cpp_core/build/backtester"
T = ROOT / "cpp_core/tools"
SLICE = T / "fold_slices"
M3_BARS = T / "bars_xauusd_2025_2026_m3.csv"
M3_LOCK = T / "mastervp/kkmastervp_xau_m3_LOCKED.set"
N_TRIALS = 22  # full M3-champion-exits search width (Stage1 5 + Stage2 7 + Stage3 10)


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


def run_arm(base_kv, ov, tmpd, idx):
    sp = tmpd / f"a{idx}.set"; write_set(base_kv, ov, sp)
    rows_all = []   # dict rows with entryTimeUTC + realizedUsd, pooled across folds
    pnls = []
    for j, fold in enumerate(FOLDS):
        name, frm, to = fold
        tp = SLICE / f"ticks_xau_{name}.csv"; oc = tmpd / f"a{idx}_f{j}.csv"
        cmd = [str(BT), "--bars", str(M3_BARS), "--ticks", str(tp), "--set-all", str(sp),
               "--trade-from-ms", str(frm), "--trade-to-ms", str(to), "--symbol-xau", "--out", str(oc)]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            sys.stderr.write(r.stderr[-300:]); continue
        with open(oc) as f:
            for row in csv.DictReader(f):
                rows_all.append(row); pnls.append(float(row["realizedUsd"]))
    return rows_all, pnls


def per_trade_sharpe(pnls, start_bal=10000.0):
    rf = []
    bal = start_bal
    for p in pnls:
        rf.append(p / bal); bal += p
    rf = np.array(rf)
    if rf.size < 2 or rf.std(ddof=1) == 0:
        return 0.0
    return float(rf.mean() / rf.std(ddof=1))


def main():
    tmpd = Path(tempfile.mkdtemp(prefix="c5gate_"))
    m3kv = read_base(M3_LOCK)
    C5 = {"InpTp1ClosePct": "0.0", "InpTrailAtrMult": "2.5", "InpEnableReversion": "true",
          "InpBlockedHoursStr": "2,3,14"}
    # Stage-3 search arms (the configs evaluated to pick the winner)
    arms = [("C5", dict(C5))]
    for v in ["12.0", "15.0", "18.0", "20.0"]:
        arms.append((f"peakDD{v}", {**C5, "InpMaxPeakDDPct": v}))
    for v in ["5.0", "7.0"]:
        arms.append((f"dailyDD{v}", {**C5, "InpMaxDailyDDPct": v}))
    for v in ["3", "4"]:
        arms.append((f"lossStrk{v}", {**C5, "InpLossStreakCount": v}))
    arms.append(("peak15daily5", {**C5, "InpMaxPeakDDPct": "15.0", "InpMaxDailyDDPct": "5.0"}))
    arms.append(("peak18strk3",  {**C5, "InpMaxPeakDDPct": "18.0", "InpLossStreakCount": "3"}))

    sharpes = []; winner_rows = None
    for i, (label, ov) in enumerate(arms):
        rows, pnls = run_arm(m3kv, ov, tmpd, i)
        s = per_trade_sharpe(pnls)
        sharpes.append(s)
        print(f"  {label:16s} n={len(pnls):4d} net={sum(pnls):8,.0f} perTradeSharpe={s:.4f}", flush=True)
        if label == "peakDD18.0":
            winner_rows = rows
    sr_trial_std = float(np.std(sharpes, ddof=1))
    print(f"\nsr_trial_std (std of per-trade Sharpe across {len(sharpes)} stage-3 arms) = {sr_trial_std:.5f}")
    print(f"n_trials (full M3-champ-exits search) = {N_TRIALS}")

    # Gate on the winner's pooled return-fractions
    rf = return_fractions(winner_rows)
    rep = run_gate(rf, n_trials=N_TRIALS, sr_trial_std=sr_trial_std)
    print("\n=== OVERFITTING GATE — C5+peakDD18 (winner), pooled 6-fold ===")
    for k in ("n", "sharpe", "psr_vs_0", "min_trl", "sr_star", "dsr"):
        if k in rep and rep[k] is not None:
            print(f"  {k:10s} = {rep[k]}")
    dsr = rep.get("dsr")
    verdict = ("PASS" if (dsr is not None and dsr >= 0.95)
               else "WARN" if (dsr is not None and dsr >= 0.90)
               else "FAIL" if dsr is not None else "n/a")
    n_ok = rep["n"] >= rep.get("min_trl", 0)
    print(f"  MinTRL met = {n_ok} (n={rep['n']} vs MinTRL={rep.get('min_trl')})")
    print(f"  VERDICT (DSR {dsr}) = {verdict}  [PRE-MT5: still needs the MT5 A/B before lock]")


if __name__ == "__main__":
    main()
