#!/usr/bin/env python3
"""
wf_mvp_generic.py — generalized WALK-FORWARD grid sweep for KK-MasterVP across BTC/XAU x M3/M5.

Generalizes wf_mastervp.py (which was XAU-M5 hardcoded) to any (symbol, tf), reusing the SAME 6
disjoint calendar folds (slice_ticks_by_fold.FOLDS) so results are comparable across markets. Reads
small PER-FOLD tick slices (slice_ticks_by_fold.py) instead of re-streaming the multi-GB full file.

Anti-overfit objective (unchanged from the repo standard): score each candidate across all 6 folds and
prefer a change only if it improves the POOLED result AND does NOT degrade the worst-fold PF (the T1
rule, [[mastervp-m5-gate-sweep-lock]]). Per-fold output (--show-folds) exposes recent-regime behaviour.

Usage (from repo root, after `make -C cpp_core backtester`):
  # one-time: slice ticks per fold
  python3 research/mastervp_parity/slice_ticks_by_fold.py --ticks cpp_core/tools/ticks_xau_full.csv \
        --out-dir cpp_core/tools/fold_slices --symbol xau
  # verify slicing reproduces the full-file run on one fold (do this ONCE per symbol):
  python3 research/mastervp_parity/wf_mvp_generic.py --symbol xau --tf m5 --grid '{}' --verify-slice
  # run a grid:
  python3 research/mastervp_parity/wf_mvp_generic.py --symbol xau --tf m5 \
        --grid '{"InpTp1ClosePct":["0","25"]}' --tag tp1 --show-folds
"""
import argparse, csv, itertools, json, subprocess, sys, tempfile
from pathlib import Path
from slice_ticks_by_fold import FOLDS, ms  # single source of truth for folds

ROOT = Path(__file__).resolve().parents[2]
BT = ROOT / "cpp_core/build/backtester"
T = ROOT / "cpp_core/tools"
SLICE_DIR = T / "fold_slices"
START_BAL = 10000.0

# Per-market base set + bars + full tick file (for --verify-slice). XAU-M3/M5 + BTC-M5 have locks;
# BTC-M3 has no lock (breakout structurally weak) -> use its base set.
MARKETS = {
    ("xau", "m3"): dict(base=T/"mastervp/kkmastervp_xau_m3_LOCKED.set",
                        bars=T/"bars_xauusd_2025_2026_m3.csv", full=T/"ticks_xau_full.csv", xau=True),
    ("xau", "m5"): dict(base=T/"mastervp/kkmastervp_xau_m5_LOCKED.set",
                        bars=T/"bars_xauusd_2025_2026_m5.csv", full=T/"ticks_xau_full.csv", xau=True),
    ("btc", "m3"): dict(base=T/"mastervp/m3_base_btc.set",
                        bars=T/"bars_btcusd_2025_2026_m3.csv", full=T/"ticks_btcusd_2024_2026.csv", xau=False),
    ("btc", "m5"): dict(base=T/"mastervp/kkmastervp_btc_m5_LOCKED.set",
                        bars=T/"bars_btcusd_2025_2026_m5.csv", full=T/"ticks_btcusd_2024_2026.csv", xau=False),
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


def run_fold(mkt, set_path, fold, out_csv, ticks_path, full=False):
    name, frm, to = fold
    cmd = [str(BT), "--bars", str(mkt["bars"]), "--ticks", str(ticks_path),
           "--set-all", str(set_path), "--trade-from-ms", str(frm), "--out", str(out_csv)]
    cmd += ["--symbol-xau"] if mkt["xau"] else ["--symbol-btc"]
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


def slice_path(symbol, fold):
    return SLICE_DIR / f"ticks_{symbol}_{fold[0]}.csv"


def eval_combo(mkt, symbol, set_path, tmpd, idx, dump_csv=None):
    per, pool = [], []
    pooled_rows = []
    for j, fold in enumerate(FOLDS):
        oc = tmpd / f"c{idx}_f{j}.csv"
        tp = slice_path(symbol, fold)
        if run_fold(mkt, set_path, fold, oc, tp) is None:
            per.append(dict(n=0, pf=0.0, net=0.0, maxdd_pct=0.0, win=0.0)); continue
        pnls = read_trades(oc); per.append(stats(pnls)); pool += pnls
        if dump_csv:
            rows = Path(oc).read_text().splitlines()
            if j == 0:
                pooled_rows.append(rows[0])  # header once
            pooled_rows += rows[1:]
    if dump_csv and pooled_rows:
        Path(dump_csv).write_text("\n".join(pooled_rows) + "\n")
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


def verify_slice(mkt, symbol):
    """Run one mid fold (F3) full-file vs sliced; assert identical net + trade count."""
    tmpd = Path(tempfile.mkdtemp(prefix="verify_"))
    base = mkt["base"]
    bkv = read_base(base); sp = tmpd / "v.set"; write_set(bkv, {}, sp)
    fold = FOLDS[2]  # F3
    # full
    full_csv = tmpd / "full.csv"
    run_fold(mkt, sp, fold, full_csv, mkt["full"])
    f_pnls = read_trades(full_csv); fs = stats(f_pnls)
    # sliced
    sl_csv = tmpd / "slice.csv"
    run_fold(mkt, sp, fold, sl_csv, slice_path(symbol, fold))
    s_pnls = read_trades(sl_csv); ss = stats(s_pnls)
    ok = (fs["n"] == ss["n"] and abs(fs["net"] - ss["net"]) < 1e-6)
    print(f"[verify-slice {symbol}-{fold[0]}] FULL: n={fs['n']} net={fs['net']:.2f} PF={fs['pf']:.3f}")
    print(f"[verify-slice {symbol}-{fold[0]}] SLICE:n={ss['n']} net={ss['net']:.2f} PF={ss['pf']:.3f}")
    print("RESULT:", "IDENTICAL ✓ (slicing safe)" if ok else "MISMATCH ✗ (do NOT use slices)")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbol", required=True, choices=["xau", "btc"])
    ap.add_argument("--tf", required=True, choices=["m3", "m5"])
    ap.add_argument("--grid", default="{}")
    ap.add_argument("--base", default=None)
    ap.add_argument("--tag", default="wf")
    ap.add_argument("--max-combos", type=int, default=120)
    ap.add_argument("--show-folds", action="store_true")
    ap.add_argument("--verify-slice", action="store_true")
    ap.add_argument("--dump-best", default=None, help="write pooled trades CSV of the top-ranked config")
    a = ap.parse_args()

    mkt = dict(MARKETS[(a.symbol, a.tf)])
    if a.base:
        mkt["base"] = Path(a.base)

    if a.verify_slice:
        sys.exit(0 if verify_slice(mkt, a.symbol) else 1)

    grid = json.loads(a.grid)
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys])) if keys else [()]
    if () not in combos and keys:
        combos = [()] + combos
    if len(combos) > a.max_combos:
        sys.exit(f"grid too large: {len(combos)} > {a.max_combos}")
    base_kv = read_base(mkt["base"])
    tmpd = Path(tempfile.mkdtemp(prefix=f"wf_{a.symbol}{a.tf}_{a.tag}_"))
    print(f"# WF {a.symbol.upper()}-{a.tf.upper()} [{a.tag}]: {len(combos)} combos x 6 folds "
          f"over {keys or '(baseline only)'}", flush=True)
    print(f"# base={mkt['base']}", flush=True)

    rows = []
    for i, vals in enumerate(combos):
        ov = dict(zip(keys, vals))
        sp = tmpd / f"c{i}.set"
        write_set(base_kv, ov, sp)
        m = eval_combo(mkt, a.symbol, sp, tmpd, i)
        m["_ov"] = ov; m["_sc"] = robust_score(m); m["_set"] = sp
        rows.append(m)
        tag = "BASELINE" if not ov else str(ov)
        print(f"  [{i:3d}] {tag}\n      {fmt_pooled(m)}", flush=True)
        if a.show_folds:
            print(fmt_perfold(m), flush=True)

    rows.sort(key=lambda r: r["_sc"], reverse=True)
    print(f"\n=== RANKED by robustness (folds PF>1, pooled PF, worst-fold PF) — {a.symbol}-{a.tf} {a.tag} ===")
    for m in rows[:12]:
        tag = "BASELINE" if not m["_ov"] else str(m["_ov"])
        print(f"  {fmt_pooled(m)}  {tag}")

    if a.dump_best:
        best = rows[0]
        # re-run the winner with a pooled dump
        eval_combo(mkt, a.symbol, best["_set"], tmpd, 999, dump_csv=a.dump_best)
        print(f"\n[dump-best] pooled trades of winner {best['_ov']} -> {a.dump_best}")


if __name__ == "__main__":
    main()
