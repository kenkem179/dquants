#!/usr/bin/env python3
"""
profit_lock_sweep_2026-06-23.py — engine WF sweep of the ProfitManager profit-lock ladder
(progressive_trail + giveback_cap) across XAU/BTC x M3/M5, 6 disjoint folds.

CONTEXT (read first): the tick engine OVER-CREDITS the trailed runner ([[mastervp-feed-spread-10x-mismatch]],
HANDOFF 2026-06-23 "engine exit-model is directionally UNRELIABLE"). So this sweep CANNOT pick a "winner" —
it will always prefer protection OFF. Its job is narrow:
  (1) confirm PM-OFF == base (regression),
  (2) quantify, per config, the engine's COST (net/PF/dd) and the mechanical ROUND-TRIP rate it removes,
  (3) pick the LEAST-aggressive config that still meaningfully fills the 0.8R..trail dead zone,
      as an MT5 A/B candidate. MT5 is the judge, not this script.

Round-trip metric (the user's actual pain): of trades whose peak MFE reached >= RT_ARM_R, what fraction
ended at <= RT_BACK_R realized-R (gave it all back). realized-R is approximated lot-independently as
realizedUsd / median(|realizedUsd| of full-R SL-LOSS trades) — i.e. one losing-R unit per fold — which is
robust to the engine's equity-compounding lot growth (ratios within a fold are what matter).
"""
import csv, itertools, json, statistics, subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from slice_ticks_by_fold import FOLDS
from wf_mvp_generic import MARKETS, read_base, write_set, run_fold, stats, slice_path

ROOT = Path(__file__).resolve().parents[2]
RT_ARM_R = 1.0     # only count trades that ran to at least +1R peak
RT_BACK_R = 0.15   # ... and ended at <= +0.15R realized = "round-tripped"


def realized_R(rows):
    """Per-fold lot-independent realized-R: normalize realizedUsd by the typical full-R loss size."""
    losses = [abs(float(r["realizedUsd"])) for r in rows
              if r["exitTag"] == "SL-LOSS" and abs(float(r["realizedUsd"])) > 0]
    unit = statistics.median(losses) if losses else None
    out = []
    for r in rows:
        u = float(r["realizedUsd"])
        out.append(u / unit if unit else 0.0)
    return out


def roundtrip_rate(fold_rows):
    """Across pooled folds: count trades with mfeR>=ARM that realized<=BACK_R, normalized per-fold."""
    armed = back = 0
    for rows in fold_rows:
        rR = realized_R(rows)
        for r, rr in zip(rows, rR):
            if float(r["mfeR"]) >= RT_ARM_R:
                armed += 1
                if rr <= RT_BACK_R:
                    back += 1
    return armed, back, (100.0 * back / armed if armed else 0.0)


def eval_combo(mkt, symbol, set_path, tmpd, idx):
    pool, fold_rows = [], []
    for j, fold in enumerate(FOLDS):
        oc = tmpd / f"c{idx}_f{j}.csv"
        if run_fold(mkt, set_path, fold, oc, slice_path(symbol, fold)) is None:
            continue
        rows = list(csv.DictReader(open(oc)))
        fold_rows.append(rows)
        pool += [float(r["realizedUsd"]) for r in rows]
    m = stats(pool)
    m["armed"], m["back"], m["rt_pct"] = roundtrip_rate(fold_rows)
    return m


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbol", required=True, choices=["xau", "btc"])
    ap.add_argument("--tf", required=True, choices=["m3", "m5"])
    ap.add_argument("--mode", required=True, choices=["prog", "giveback"])
    a = ap.parse_args()

    mkt = dict(MARKETS[(a.symbol, a.tf)])
    base_kv = read_base(mkt["base"])
    tmpd = Path(tempfile.mkdtemp(prefix=f"plock_{a.symbol}{a.tf}_{a.mode}_"))

    if a.mode == "prog":
        # progressive_trail: SL->entry at trigger, then +step_r per increment_r of extra gain. Smooth ratchet.
        grid = {"InpPmProgTrail": ["true"],
                "InpPmProgTriggerR": ["0.8", "1.0"],
                "InpPmProgIncrementR": ["0.3", "0.5"],
                "InpPmProgStepR": ["0.10", "0.20"]}
    else:
        # giveback_cap: once peak>=arm, lock (1-cap) of peak. Hard profit floor.
        grid = {"InpPmGiveback": ["true"],
                "InpPmGivebackArmR": ["1.0", "1.5", "2.0"],
                "InpPmGivebackCapFrac": ["0.25", "0.33", "0.50"]}

    keys = list(grid.keys())
    combos = [()] + list(itertools.product(*[grid[k] for k in keys]))
    print(f"# PROFIT-LOCK {a.symbol.upper()}-{a.tf.upper()} [{a.mode}]: {len(combos)} combos x 6 folds")
    print(f"# base={mkt['base'].name}  (round-trip = mfeR>={RT_ARM_R} ending <= {RT_BACK_R}R)")
    rows = []
    for i, vals in enumerate(combos):
        ov = dict(zip(keys, vals)) if vals else {}
        sp = tmpd / f"c{i}.set"; write_set(base_kv, ov, sp)
        m = eval_combo(mkt, a.symbol, sp, tmpd, i)
        m["_ov"] = ov
        rows.append(m)
        tag = "BASELINE (PM off)" if not ov else json.dumps(ov)
        print(f"  [{i:2d}] n={m['n']:4d} PF={m['pf']:.3f} net={m['net']:9,.0f} dd={m['maxdd_pct']:4.1f}% "
              f"win={m['win']:.1f} | roundtrip {m['back']}/{m['armed']}={m['rt_pct']:.1f}%  {tag}", flush=True)
    base = rows[0]
    print(f"\n# base round-trip rate = {base['rt_pct']:.1f}% ({base['back']}/{base['armed']}); "
          f"base net={base['net']:,.0f} dd={base['maxdd_pct']:.1f}%")
    print("# pick: lowest roundtrip% with smallest net give-up vs base, dd not worse — that's the MT5 candidate")


if __name__ == "__main__":
    main()
