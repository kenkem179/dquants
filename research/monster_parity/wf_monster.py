#!/usr/bin/env python3
"""
wf_monster.py — WALK-FORWARD / multi-fold robustness harness for KK-MasterVP-Monster (BTCUSD M3).

Why this exists: the single 2025-train / 2026-OOS split can curve-fit one OOS window. To decide
whether a *secondary* (inherited) param is worth re-tuning for Monster — or is correctly left at its
default — we score every candidate across SIX disjoint time folds (2 in the train tick file, 4 in the
OOS tick file) and only adopt a change that is robust ACROSS folds (improves the pooled result without
degrading the worst fold and without dropping fold-win consistency). Uses the engine's `--trade-to-ms`
fold cap so each fold is a clean, non-overlapping window carved from the existing tick subsets.

Usage (from repo root):
  python3 research/monster_parity/wf_monster.py \
      --grid '{"InpImpulseEntryBufAtr":[0.1,0.15,0.2]}' --tag imp_entrybuf
  python3 research/monster_parity/wf_monster.py --grid '{}' --tag baseline   # baseline only
"""
import argparse, csv, itertools, json, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT = ROOT / "cpp_core/build/backtester"
T = ROOT / "cpp_core/tools"
START_BAL = 10000.0
LOCKED = ROOT / "cpp_core/tools/mastervp/monster_btc_m3_LOCKED.set"

# Six disjoint walk-forward folds carved from the two prepared tick subsets.
#   train file ticks_btcusd_2025_window.csv : 2025-08-11 .. 2025-11-30  -> F1,F2
#   oos   file ticks_btcusd_2026_oos.csv    : 2026-01-01 .. 2026-06-09  -> F3..F6
# Each fold ~6-8 weeks (~100-150 trades) so base-param effects have statistical power.
FOLDS = [
    # name, seg, from_ms,        to_ms,         (to_ms=0 -> run to file end)
    ("F1_2508", "train", 1754870400000, 1759276800000),  # 2025-08-11 .. 2025-10-01
    ("F2_2510", "train", 1759276800000, 0),              # 2025-10-01 .. 2025-11-30 (file end)
    ("F3_2601", "oos",   1767225600000, 1771113600000),  # 2026-01-01 .. 2026-02-15
    ("F4_2602", "oos",   1771113600000, 1775001600000),  # 2026-02-15 .. 2026-04-01
    ("F5_2604", "oos",   1775001600000, 1778803200000),  # 2026-04-01 .. 2026-05-15
    ("F6_2605", "oos",   1778803200000, 0),              # 2026-05-15 .. 2026-06-09 (file end)
]
SEG = {
    "train": dict(bars=T/"bars_btcusd_2025_m3.csv", m1=T/"bars_btcusd_2025_m1.csv",
                  ticks=T/"ticks_btcusd_2025_window.csv"),
    "oos":   dict(bars=T/"bars_btcusd_2026_m3.csv", m1=T/"bars_btcusd_2026_m1.csv",
                  ticks=T/"ticks_btcusd_2026_oos.csv"),
}


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
    _, seg, frm, to = fold
    s = SEG[seg]
    cmd = [str(BT), "--bars", str(s["bars"]), "--bars-m1", str(s["m1"]), "--ticks", str(s["ticks"]),
           "--symbol-btc", "--set-all", str(set_path), "--trade-from-ms", str(frm),
           "--out", str(out_csv)]
    if to > 0:
        cmd += ["--trade-to-ms", str(to)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-400:]); return None
    return out_csv


def read_trades(csv_path):
    pnls, reasons = [], []
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            pnls.append(float(row["realizedUsd"])); reasons.append(row.get("entryReason", ""))
    return pnls, reasons


def stats(pnls, reasons):
    n = len(pnls)
    if n == 0:
        return dict(n=0, imp=0, pf=0.0, net=0.0, maxdd_pct=0.0, win=0.0, imp_net=0.0)
    wins = [p for p in pnls if p > 0]; losses = [p for p in pnls if p <= 0]
    gw, gl = sum(wins), -sum(losses)
    eq, peak, maxdd = START_BAL, START_BAL, 0.0
    for p in pnls:
        eq += p; peak = max(peak, eq); maxdd = max(maxdd, peak - eq)
    imp = sum(1 for r in reasons if "IMP" in r)
    return dict(n=n, imp=imp, win=100*len(wins)/n, pf=(gw/gl if gl > 0 else float("inf")),
                net=sum(pnls), maxdd_pct=100*maxdd/peak if peak else 0.0,
                imp_net=sum(p for p, r in zip(pnls, reasons) if "IMP" in r))


def eval_combo(set_path, tmpd, idx):
    """Run all folds for one config; return per-fold stats + pooled stats."""
    per = []
    pool_pnls, pool_reasons = [], []
    for j, fold in enumerate(FOLDS):
        oc = tmpd / f"c{idx}_f{j}.csv"
        if run_fold(set_path, fold, oc) is None:
            per.append(dict(n=0, pf=0.0, net=0.0, maxdd_pct=0.0, win=0.0, imp=0))
            continue
        pnls, reasons = read_trades(oc)
        per.append(stats(pnls, reasons))
        pool_pnls += pnls; pool_reasons += reasons
    pooled = stats(pool_pnls, pool_reasons)
    pfs = [f["pf"] for f in per if f["n"] > 0]
    folds_pos = sum(1 for f in per if f["net"] > 0)
    folds_pf1 = sum(1 for f in per if f["pf"] > 1.0)
    pooled["per"] = per
    pooled["worst_pf"] = min(pfs) if pfs else 0.0
    pooled["mean_pf"] = sum(pfs) / len(pfs) if pfs else 0.0
    pooled["folds_pos"] = folds_pos
    pooled["folds_pf1"] = folds_pf1
    return pooled


def robust_score(m):
    # primary: fold-win consistency (folds with PF>1); tie-break: pooled PF then worst-fold PF.
    return (m["folds_pf1"], round(m["pf"], 4), round(m["worst_pf"], 4))


def fmt_pooled(m):
    return (f"POOLED n={m['n']} (imp={m['imp']}) win={m['win']:.1f} PF={m['pf']:.3f} "
            f"net={m['net']:,.0f} dd={m['maxdd_pct']:.1f}% | folds+={m['folds_pos']}/6 "
            f"PF>1={m['folds_pf1']}/6 worstPF={m['worst_pf']:.3f} meanPF={m['mean_pf']:.3f} "
            f"impNet={m['imp_net']:,.0f}")


def fmt_perfold(m):
    cells = []
    for fold, f in zip(FOLDS, m["per"]):
        cells.append(f"{fold[0]}:PF{f['pf']:.2f}/n{f['n']}/${f['net']:,.0f}")
    return "      " + "  ".join(cells)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--grid", required=True)
    ap.add_argument("--base", default=str(LOCKED))
    ap.add_argument("--tag", default="wf")
    ap.add_argument("--max-combos", type=int, default=120)
    ap.add_argument("--show-folds", action="store_true", help="print per-fold breakdown per combo")
    a = ap.parse_args()

    grid = json.loads(a.grid)
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys])) if keys else [()]
    if () not in combos and keys:
        combos = [()] + combos  # always include baseline (no override)
    if len(combos) > a.max_combos:
        sys.exit(f"grid too large: {len(combos)} > {a.max_combos}")
    base_kv = read_base(a.base)
    tmpd = Path(tempfile.mkdtemp(prefix=f"wfmon_{a.tag}_"))
    print(f"# WALK-FORWARD monster [{a.tag}]: {len(combos)} combos × 6 folds over {keys or '(baseline only)'}",
          flush=True)
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
