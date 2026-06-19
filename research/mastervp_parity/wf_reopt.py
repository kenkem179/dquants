#!/usr/bin/env python3
"""
wf_reopt.py — Anchored walk-forward with RE-OPTIMIZATION of the dominant lever (master-VP length).

The locked M5 study established master-VP bars are the sole VP driver and the rest plateau. The
gold-standard walk-forward test: at each step, re-select master length on an EXPANDING in-sample
(anchored), then trade it un-touched on the next out-of-sample fold. If the *selection process*
generalizes, OOS PF stays >1 and WF-efficiency (OOS/IS) is healthy (~>0.5). This proves we are not
curve-fitting the single 70/30 split.

Uses the continuous tick file + --trade-from-ms/--trade-to-ms fold windowing (added this session).
Master length = InpVpLookback * InpMasterMult(=4). Candidates span the M5 study's tested band.

Run from repo root (after `make backtester`). ~30 engine runs, ~14s each over the full tick file.
"""
import csv, subprocess, tempfile, os, math
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BT = f"{ROOT}/cpp_core/build/backtester"
BARS = f"{ROOT}/cpp_core/tools/bars_xauusd_2025_2026_m5.csv"
TICKS = f"{ROOT}/cpp_core/tools/ticks_xau_full.csv"
BASE = f"{ROOT}/cpp_core/tools/mastervp/kkmastervp_xau_m5_LOCKED.set"
START_BAL = 10000.0
MIN_TRADES = 60   # IS floor to accept a candidate


def ms(y, m, d):
    return int(datetime(y, m, d, tzinfo=timezone.utc).timestamp() * 1000)


# Master-VP length candidates (InpVpLookback, master = x4 bars/hours-on-M5)
LOOKBACKS = [72, 96, 108, 120, 144]   # master 288/384/432/480/576 bars = 24/32/36/40/48 h

# Anchored folds: (IS_start, OOS_start, OOS_end). IS = [IS_start, OOS_start); OOS = [OOS_start, OOS_end).
IS0 = ms(2025, 6, 19)
FOLDS = [
    (IS0, ms(2025, 11, 1), ms(2025, 12, 15)),
    (IS0, ms(2025, 12, 15), ms(2026, 1, 30)),
    (IS0, ms(2026, 1, 30), ms(2026, 3, 15)),
    (IS0, ms(2026, 3, 15), ms(2026, 4, 30)),
    (IS0, ms(2026, 4, 30), ms(2026, 5, 30)),
]

_base_lines = open(BASE).read().splitlines()


def run(lookback, frm, to):
    txt = []
    for ln in _base_lines:
        if ln.split(";")[0].strip().startswith("InpVpLookback="):
            ln = f"InpVpLookback={lookback}"
        txt.append(ln)
    s = tempfile.NamedTemporaryFile("w", suffix=".set", delete=False); s.write("\n".join(txt)); s.close()
    o = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False); o.close()
    subprocess.run([BT, "--bars", BARS, "--ticks", TICKS, "--set-all", s.name, "--symbol-xau",
                    "--trade-from-ms", str(frm), "--trade-to-ms", str(to), "--out", o.name],
                   capture_output=True, text=True)
    m = metrics(o.name)
    os.unlink(s.name); os.unlink(o.name)
    return m


def metrics(path):
    pnls = []
    with open(path) as f:
        for r in csv.DictReader(f):
            pnls.append(float(r["realizedUsd"]))
    n = len(pnls)
    if n == 0:
        return dict(n=0, pf=0, net=0, dd=100, win=0)
    bal = START_BAL; eq = bal; peak = bal; maxdd = 0.0
    gw = gl = 0.0; wins = 0
    for p in pnls:
        if p > 0: gw += p; wins += 1
        else: gl += -p
        eq += p; peak = max(peak, eq); maxdd = max(maxdd, peak - eq)
    return dict(n=n, pf=(gw / gl if gl > 1e-9 else float("inf")), net=sum(pnls),
                dd=100 * maxdd / peak if peak else 0, win=100 * wins / n)


def main():
    print("==== Anchored walk-forward (re-optimize master-VP length) :: XAU M5 ====")
    print(f"candidates lookback={LOOKBACKS} (master x4 = {[x*4 for x in LOOKBACKS]} bars)")
    print(f"{'step':<5}{'IS span':<22}{'pick(lkbk/mstr)':<18}{'IS PF':>7}{'OOS span':<22}"
          f"{'OOS n':>6}{'OOS PF':>8}{'OOS net%':>9}{'OOS dd%':>8}{'WFeff':>7}")
    print("-" * 120)
    locked_lb = 108
    oos_pfs, locked_oos_pfs = [], []
    for i, (isf, ist, oe) in enumerate(FOLDS):
        # optimize on IS
        is_res = {lb: run(lb, isf, ist) for lb in LOOKBACKS}
        cands = {lb: m for lb, m in is_res.items() if m["n"] >= MIN_TRADES and m["pf"] > 1.0}
        if not cands:
            cands = is_res
        pick = max(cands, key=lambda lb: cands[lb]["pf"])
        ispf = is_res[pick]["pf"]
        # test on OOS with the picked lookback
        oos = run(pick, ist, oe)
        # also the LOCKED (108) on the same OOS for comparison
        oos_locked = run(locked_lb, ist, oe)
        oos_pfs.append(oos["pf"]); locked_oos_pfs.append(oos_locked["pf"])
        wfeff = (oos["pf"] / ispf) if ispf > 0 and math.isfinite(ispf) else float("nan")
        is_span = f"{datetime.utcfromtimestamp(isf/1000):%y-%m-%d}..{datetime.utcfromtimestamp(ist/1000):%m-%d}"
        oos_span = f"{datetime.utcfromtimestamp(ist/1000):%y-%m-%d}..{datetime.utcfromtimestamp(oe/1000):%m-%d}"
        net = 100 * oos["net"] / START_BAL
        print(f"{i+1:<5}{is_span:<22}{f'{pick}/{pick*4}b':<18}{ispf:>7.3f}{oos_span:<22}"
              f"{oos['n']:>6}{oos['pf']:>8.3f}{net:>+9.1f}{oos['dd']:>8.1f}{wfeff:>7.2f}")
    print("-" * 120)
    pos = sum(1 for p in oos_pfs if p > 1.0)
    print(f"RE-OPT WF: {pos}/{len(oos_pfs)} OOS folds PF>1 | median OOS PF {sorted(oos_pfs)[len(oos_pfs)//2]:.3f}"
          f" | mean OOS PF {sum(oos_pfs)/len(oos_pfs):.3f}")
    posl = sum(1 for p in locked_oos_pfs if p > 1.0)
    print(f"LOCKED-108 same folds: {posl}/{len(locked_oos_pfs)} PF>1 | median {sorted(locked_oos_pfs)[len(locked_oos_pfs)//2]:.3f}"
          f" | mean {sum(locked_oos_pfs)/len(locked_oos_pfs):.3f}")
    print("(re-opt ~= locked => the fixed 108/432b lock is not a curve-fit; the lever is stable across folds)")


if __name__ == "__main__":
    main()
