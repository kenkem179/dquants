#!/usr/bin/env python3
"""E5 2026 fresh-window parity diff (forming-ADX experiment harness).

Runs the tick backtester over the fresh 2026 window (--from-ms/--to-ms) with a given
.set, windows engine E5 trades to the MT5 2026 gate-trace trade span, and reports
matched/missed/overfire vs MT5 (108 E5 +949). Reuses diff_kk.load/match.

Usage:
  python research/kenkem_parity/diff_e5_2026.py [--set <file>] [--label NAME] [--out <csv>]
Default .set = MT5_E5_2026.set. Prints one summary line; with --out keeps engine trades.
"""
import os, sys, subprocess, tempfile, argparse
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from diff_kk import load, match  # noqa: E402

BIN   = os.path.join(ROOT, "cpp_core", "build", "kenkem", "tick_backtester")
TOOLS = os.path.join(ROOT, "cpp_core", "tools")
BARS  = os.path.join(TOOLS, "bars_xauusd_2024_2026_m1.csv")
TICKS = os.path.join(TOOLS, "ticks_xauusd_2024_2026.csv")
MT5   = os.path.join(HERE, "mt5_runs", "RUN_2026-06-20_1.8.154_xau_2026H1_E5only_gatetrace", "trades.csv")
FROM_MS, TO_MS = 1767225600000, 1780272000000   # fresh 2026 window (HANDOFF-documented)
SPREAD, LAG = 0.05, 5.0


def run(set_path, out_path):
    eng_all = load(out_path) if out_path and os.path.exists(out_path) else None
    if eng_all is None:
        tmp = out_path or os.path.join(tempfile.gettempdir(), "e5_2026_run.csv")
        r = subprocess.run(
            [BIN, "--bars-m1", BARS, "--ticks", TICKS, "--symbol-xau",
             "--spread", str(SPREAD), "--set", set_path,
             "--from-ms", str(FROM_MS), "--to-ms", str(TO_MS), "--out", tmp],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode != 0 or not os.path.exists(tmp):
            raise SystemExit(f"backtester failed rc={r.returncode}")
        eng_all = load(tmp)
    eng = [e for e in eng_all if e["kind"] == "E5"]
    mt5 = [r for r in load(MT5) if r["kind"] == "E5"]
    lo, hi = mt5[0]["t"], mt5[-1]["t"]
    engw = [e for e in eng if lo - timedelta(minutes=LAG) <= e["t"] <= hi + timedelta(minutes=LAG)]
    pairs, miss, over = match(mt5, engw, LAG)
    net = sum(e["pnl"] for e in engw)
    mnet = sum(engw[j]["pnl"] for _, j in pairs)
    onet = sum(engw[j]["pnl"] for j in over)
    return dict(n=len(engw), mt5=len(mt5), matched=len(pairs), missed=len(miss),
                overfire=len(over), recall=100.0*len(pairs)/len(mt5),
                net=net, mnet=mnet, onet=onet)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", default=os.path.join(HERE, "MT5_E5_2026.set"))
    ap.add_argument("--label", default="run")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    m = run(a.set, a.out)
    print(f"{a.label:<18} eng_n={m['n']:<4} net={m['net']:+7.0f} | "
          f"MT5={m['mt5']} matched={m['matched']:<3} missed={m['missed']:<3} "
          f"overfire={m['overfire']:<3} recall={m['recall']:4.1f}% | "
          f"mNet={m['mnet']:+7.0f} oNet={m['onet']:+7.0f}")


if __name__ == "__main__":
    main()
