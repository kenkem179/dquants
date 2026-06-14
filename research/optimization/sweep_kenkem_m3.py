#!/usr/bin/env python3
"""KenKem per-entry tuning -> combination study on the M3 base TF (user request 2026-06-15).

Mirror of sweep_kenkem_tuned.py but with the engine's BASE bar series = M3 (so the higher-TF
confirmation map shifts to M9/M15/M45 — the fixed x3/x5/x15 aggregation off an M3 base). All
per-entry knobs + shared gates are RE-TUNED on M3 2025 and validated on M3 2026 (true OOS), so this
is a genuine M3 study, not M1-tuned params replayed on M3.

Outputs carry an `_m3` infix so the M1 artifacts are never overwritten:
  best_tuned_<e>_<sym>_m3.{json,set}, best_kenkem_<combo>_<sym>_m3.set, sweep_kenkem_tuned_<sym>_m3.csv

Usage:
  python research/optimization/sweep_kenkem_m3.py phaseA <btc|xau> [n_trials] [n_jobs]
  python research/optimization/sweep_kenkem_m3.py phaseB <btc|xau> [n_trials] [n_jobs]
"""
import os, sys, csv, json
import optuna
from sweep_kenkem_entrysets import metrics, HERE, TOGGLE, ALL_ENTRIES
from sweep_kenkem_tuned import (ENTRY_SPACE, SHARED_SPACE, SHARED_CAT, COMBOS,
                                base_for, toggles, suggest, evaluate, write_set)

ROOT = os.path.dirname(os.path.dirname(HERE))
# M3 base bars (built by export_bars.py over the SAME date windows as the M1 study).
SYMS_M3 = {
    "btc": dict(flag="--symbol-btc", spread=2.0,
                m1=os.path.join(ROOT, "cpp_core/tools/bars_btcusd_2025_m3.csv"),
                oos=os.path.join(ROOT, "cpp_core/tools/bars_btcusd_2026_m3.csv")),
    "xau": dict(flag="--symbol-xau", spread=0.05,
                m1=os.path.join(ROOT, "cpp_core/tools/bars_xauusd_2025_m3.csv"),
                oos=os.path.join(ROOT, "cpp_core/tools/bars_xauusd_2026_m3.csv")),
}


def phaseA(sym, n_trials, n_jobs):
    cfg = SYMS_M3[sym]
    base = base_for(sym)
    print(f"===== KenKem M3 phaseA per-entry tuning [{sym.upper()}] trials={n_trials} =====")
    for e in ALL_ENTRIES:
        space = ENTRY_SPACE[e] + SHARED_SPACE
        rows = []

        def objective(trial):
            ov = dict(base); ov.update(toggles([e])); ov.update(suggest(trial, space))
            for k, choices in SHARED_CAT:
                ov[k] = trial.suggest_categorical(k, choices)
            r = evaluate(cfg, ov)
            if r is None:
                return 0.0
            rows.append((r["score"], ov, r))
            return r["score"]

        study = optuna.create_study(direction="maximize",
                                    sampler=optuna.samplers.TPESampler(multivariate=True, seed=7))
        optuna.logging.set_verbosity(optuna.logging.WARNING)
        study.optimize(objective, n_trials=n_trials, n_jobs=n_jobs)
        if not rows:
            print(f"  {e.upper()}: no valid config"); continue
        rows.sort(key=lambda x: -x[0])
        best_ov, r = rows[0][1], rows[0][2]
        entry_keys = [k for k, *_ in ENTRY_SPACE[e]]
        frozen = {k: best_ov[k] for k in entry_keys}
        json.dump(frozen, open(os.path.join(HERE, f"best_tuned_{e}_{sym}_m3.json"), "w"), indent=2)
        write_set(os.path.join(HERE, f"best_tuned_{e}_{sym}_m3.set"), best_ov)
        print(f"  {e.upper()}: IS pf={r['full']['pf']:.3f} net={r['full']['net']:>8.0f} n={r['full']['n']:>4d} "
              f"dd={r['full']['dd']:>7.0f} | OOS26 pf={r['oos']['pf']:.3f} net={r['oos']['net']:>8.0f} "
              f"n={r['oos']['n']:>4d}")
    print(f"\n  M3 phaseA done -> best_tuned_<e>_{sym}_m3.json (frozen per-entry knobs) + .set")


def phaseB(sym, n_trials, n_jobs):
    cfg = SYMS_M3[sym]
    base = base_for(sym)
    frozen = {}
    for e in ALL_ENTRIES:
        p = os.path.join(HERE, f"best_tuned_{e}_{sym}_m3.json")
        if os.path.exists(p):
            frozen[e] = json.load(open(p))
    print(f"===== KenKem M3 phaseB combinations [{sym.upper()}] trials={n_trials} =====")
    summary = []
    for name, active in COMBOS.items():
        if any(e not in frozen for e in active):
            print(f"  {name}: missing M3 phaseA for {[e for e in active if e not in frozen]}"); continue
        per_entry = {}
        for e in active:
            per_entry.update(frozen[e])
        rows = []

        def objective(trial):
            ov = dict(base); ov.update(toggles(active)); ov.update(per_entry)
            ov.update(suggest(trial, SHARED_SPACE))
            for k, choices in SHARED_CAT:
                ov[k] = trial.suggest_categorical(k, choices)
            r = evaluate(cfg, ov)
            if r is None:
                return 0.0
            rows.append((r["score"], ov, r))
            return r["score"]

        study = optuna.create_study(direction="maximize",
                                    sampler=optuna.samplers.TPESampler(multivariate=True, seed=7))
        optuna.logging.set_verbosity(optuna.logging.WARNING)
        study.optimize(objective, n_trials=n_trials, n_jobs=n_jobs)
        if not rows:
            print(f"  {name:9s}: no valid config"); continue
        rows.sort(key=lambda x: -x[0])
        best_ov, r = rows[0][1], rows[0][2]
        write_set(os.path.join(HERE, f"best_kenkem_{name}_{sym}_m3.set"), best_ov)
        summary.append(dict(combo=name, oos_pf=round(r["oos"]["pf"], 3), oos_net=round(r["oos"]["net"]),
                            oos_n=r["oos"]["n"], is_pf=round(r["full"]["pf"], 3), is_net=round(r["full"]["net"]),
                            te_net=round(r["te"]["net"])))
        print(f"  {name:9s}: IS pf={r['full']['pf']:.3f} net={r['full']['net']:>8.0f} | "
              f"OOS26 pf={r['oos']['pf']:.3f} net={r['oos']['net']:>8.0f} n={r['oos']['n']:>4d}")
    if summary:
        print(f"\n----- {sym.upper()} M3 combos ranked by 2026 OOS PF -----")
        for r in sorted(summary, key=lambda r: -r["oos_pf"]):
            flag = "" if (r["oos_pf"] >= 1.0 and r["te_net"] > 0) else "  <-- fails OOS/consistency"
            print(f"  {r['combo']:9s} OOS pf={r['oos_pf']:.3f} net={r['oos_net']:>8.0f} | IS pf={r['is_pf']:.3f}{flag}")
        with open(os.path.join(HERE, f"sweep_kenkem_tuned_{sym}_m3.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(summary[0].keys())); w.writeheader(); w.writerows(summary)


def main():
    phase = sys.argv[1] if len(sys.argv) > 1 else "phaseA"
    sym = sys.argv[2] if len(sys.argv) > 2 else "btc"
    n_trials = int(sys.argv[3]) if len(sys.argv) > 3 else (300 if phase == "phaseA" else 150)
    n_jobs = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    (phaseA if phase == "phaseA" else phaseB)(sym, n_trials, n_jobs)


if __name__ == "__main__":
    main()
