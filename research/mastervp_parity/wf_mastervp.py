#!/usr/bin/env python3
"""
wf_mastervp.py — WALK-FORWARD / multi-fold robustness grid sweep for KK-MasterVP (XAUUSD M5).

Sibling of research/monster_parity/wf_monster.py, but for the MasterVP XAU M5 lock. Same anti-overfit
objective: score every candidate across SIX disjoint time folds carved from the continuous XAU tick
file (--trade-from-ms/--trade-to-ms), and only adopt a change that is robust ACROSS folds (improves the
pooled result without degrading the worst fold or dropping fold-win consistency).

PORTABILITY NOTE: for the KK-MasterVP EA, InpNodeGateEnabled / InpUsePriorBarVP / InpBrkRequireFlow /
InpSfpFlowMin are compile-constants (config.hpp non_input_keys) — MT5 IGNORES .set values for them.
This sweep uses --set-all so the engine DOES honor them; if one helps, adopting it requires an EA
recompile (flip the compiled default), NOT just a preset. InpBrkVetoSfp / InpUseMomVeto / InpUseMtfAgree
ARE real EA inputs (shippable via .set). to_bool only accepts "true"/"1" -> pass grid bools as strings.

Usage (from repo root, after `make -C cpp_core backtester`):
  python3 research/mastervp_parity/wf_mastervp.py \
      --grid '{"InpBrkVetoSfp":["false","true"]}' --tag brk_veto_sfp
  python3 research/mastervp_parity/wf_mastervp.py --grid '{}' --tag baseline   # baseline only
"""
import argparse, csv, itertools, json, subprocess, sys, tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT = ROOT / "cpp_core/build/backtester"
T = ROOT / "cpp_core/tools"
START_BAL = 10000.0
LOCKED = T / "mastervp/kkmastervp_xau_m5_LOCKED.set"
BARS = T / "bars_xauusd_2025_2026_m5.csv"
TICKS = T / "ticks_xau_full.csv"


def ms(y, m, d):
    return int(datetime(y, m, d, tzinfo=timezone.utc).timestamp() * 1000)


# Six disjoint folds across the continuous XAU tick file (2025-06-19 .. 2026-05-30). ~2 months each.
FOLDS = [
    ("F1_2506", ms(2025, 6, 19), ms(2025, 8, 15)),
    ("F2_2508", ms(2025, 8, 15), ms(2025, 10, 15)),
    ("F3_2510", ms(2025, 10, 15), ms(2025, 12, 15)),
    ("F4_2512", ms(2025, 12, 15), ms(2026, 2, 15)),
    ("F5_2602", ms(2026, 2, 15), ms(2026, 4, 15)),
    ("F6_2604", ms(2026, 4, 15), 0),   # to file end (~2026-05-30)
]


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


def run_fold(set_path, fold, out_csv):
    _, frm, to = fold
    cmd = [str(BT), "--bars", str(BARS), "--ticks", str(TICKS), "--symbol-xau",
           "--set-all", str(set_path), "--trade-from-ms", str(frm), "--out", str(out_csv)]
    if to > 0:
        cmd += ["--trade-to-ms", str(to)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-400:]); return None
    return out_csv


def read_trades(csv_path):
    pnls = []
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            pnls.append(float(row["realizedUsd"]))
    return pnls


def stats(pnls):
    n = len(pnls)
    if n == 0:
        return dict(n=0, pf=0.0, net=0.0, maxdd_pct=0.0, win=0.0)
    wins = [p for p in pnls if p > 0]; losses = [p for p in pnls if p <= 0]
    gw, gl = sum(wins), -sum(losses)
    eq, peak, maxdd = START_BAL, START_BAL, 0.0
    for p in pnls:
        eq += p; peak = max(peak, eq); maxdd = max(maxdd, peak - eq)
    return dict(n=n, win=100*len(wins)/n, pf=(gw/gl if gl > 0 else float("inf")),
                net=sum(pnls), maxdd_pct=100*maxdd/peak if peak else 0.0)


def eval_combo(set_path, tmpd, idx):
    per, pool = [], []
    for j, fold in enumerate(FOLDS):
        oc = tmpd / f"c{idx}_f{j}.csv"
        if run_fold(set_path, fold, oc) is None:
            per.append(dict(n=0, pf=0.0, net=0.0, maxdd_pct=0.0, win=0.0)); continue
        pnls = read_trades(oc); per.append(stats(pnls)); pool += pnls
    pooled = stats(pool)
    pfs = [f["pf"] for f in per if f["n"] > 0]
    pooled["per"] = per
    pooled["worst_pf"] = min(pfs) if pfs else 0.0
    pooled["mean_pf"] = sum(pfs)/len(pfs) if pfs else 0.0
    pooled["folds_pos"] = sum(1 for f in per if f["net"] > 0)
    pooled["folds_pf1"] = sum(1 for f in per if f["pf"] > 1.0)
    return pooled


def robust_score(m):
    return (m["folds_pf1"], round(m["pf"], 4), round(m["worst_pf"], 4))


def fmt_pooled(m):
    return (f"POOLED n={m['n']} win={m['win']:.1f} PF={m['pf']:.3f} net={m['net']:,.0f} "
            f"dd={m['maxdd_pct']:.1f}% | folds+={m['folds_pos']}/6 PF>1={m['folds_pf1']}/6 "
            f"worstPF={m['worst_pf']:.3f} meanPF={m['mean_pf']:.3f}")


def fmt_perfold(m):
    return "      " + "  ".join(f"{fold[0]}:PF{f['pf']:.2f}/n{f['n']}/${f['net']:,.0f}"
                                for fold, f in zip(FOLDS, m["per"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--grid", required=True)
    ap.add_argument("--base", default=str(LOCKED))
    ap.add_argument("--tag", default="wf")
    ap.add_argument("--max-combos", type=int, default=64)
    ap.add_argument("--show-folds", action="store_true")
    a = ap.parse_args()

    grid = json.loads(a.grid)
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys])) if keys else [()]
    if () not in combos and keys:
        combos = [()] + combos
    if len(combos) > a.max_combos:
        sys.exit(f"grid too large: {len(combos)} > {a.max_combos}")
    base_kv = read_base(a.base)
    tmpd = Path(tempfile.mkdtemp(prefix=f"wfmvp_{a.tag}_"))
    print(f"# WALK-FORWARD mastervp [{a.tag}]: {len(combos)} combos × 6 folds over {keys or '(baseline only)'}", flush=True)
    print(f"# base={a.base}", flush=True)

    rows = []
    for i, vals in enumerate(combos):
        ov = dict(zip(keys, vals))
        sp = tmpd / f"c{i}.set"
        write_set(base_kv, ov, sp)
        m = eval_combo(sp, tmpd, i)
        m["_ov"] = ov; m["_sc"] = robust_score(m)
        rows.append(m)
        tag = "BASELINE" if not ov else str(ov)
        print(f"  [{i:3d}] {tag}\n      {fmt_pooled(m)}", flush=True)
        if a.show_folds:
            print(fmt_perfold(m), flush=True)

    rows.sort(key=lambda r: r["_sc"], reverse=True)
    print(f"\n=== RANKED by robustness (folds PF>1, then pooled PF, then worst-fold PF) — {a.tag} ===")
    for m in rows[:12]:
        tag = "BASELINE" if not m["_ov"] else str(m["_ov"])
        print(f"  {fmt_pooled(m)}  {tag}")


if __name__ == "__main__":
    main()
