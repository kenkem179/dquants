#!/usr/bin/env python3
"""KenKem entry-set comparison (user request 2026-06-14): which entries to keep in production.

The joint optimizer (optimize_kenkem.py) sweeps the 4 entry toggles TOGETHER with all params and
reports a single winner (this is how BTC landed on E5-only and XAU on E2+E4+E5). That entangles the
toggle choice with the param plateau and hides the per-entry-set picture. This script instead runs a
CONTROLLED experiment: for each entry-set combination, FIX the toggles and run an independent Optuna
search over the same param SPACE, then tabulate full/test net, PF and maxDD so we can SEE which
combination is best to keep.

Entry-sets cover the user's list (E3 does not exist in the distilled kk::kenkem engine — only E1/E2/E4/
E5 — so the requested "E1&E3&E5" is run as E1&E5 and flagged):
  singles: E1, E2, E4, E5
  combos : E1+E2, E1+E5 (=E1&E3&E5 proxy), E2+E5, plus E2+E4+E5 and ALL as references.

Adoption stays risk-adjusted: a combination is only a production candidate if it beats the current
locked set on net AND maxDD (Calmar-style), with a positive out-of-sample (test) split. This script
only REPORTS + writes per-set CSVs; promoting a new production .set is a separate, explicit step.

Usage: python research/optimization/sweep_kenkem_entrysets.py <btc|xau> [n_trials] [n_jobs]
Outputs: sweep_kenkem_entrysets_<sym>.csv (best row per entry-set) + console comparison table.
"""
import csv, os, sys, tempfile
import optuna
from optimize_kenkem import SYMS, SPACE, run_trial, metrics, HERE

# label -> the entries that are ON (others forced OFF)
ENTRY_SETS = [
    ("E1",        {"E1"}),
    ("E2",        {"E2"}),
    ("E4",        {"E4"}),
    ("E5",        {"E5"}),
    ("E1+E2",     {"E1", "E2"}),
    ("E1+E5",     {"E1", "E5"}),     # proxy for user's "E1&E3&E5" (no E3 in this engine)
    ("E2+E5",     {"E2", "E5"}),
    ("E2+E4+E5",  {"E2", "E4", "E5"}),
    ("ALL",       {"E1", "E2", "E4", "E5"}),
]
ALL_TOGGLES = {"E1": "ENABLE_E1_ENTRIES", "E2": "ENABLE_E2_ENTRIES",
               "E4": "ENABLE_E4_ENTRIES", "E5": "ENABLE_E5_ENTRIES"}
MIN_TRADES = 80   # lower than the joint optimizer's 400 so single-entry sets aren't unfairly rejected


def toggles_for(on_set):
    return {k: ("true" if name in on_set else "false") for name, k in
            [(n, ALL_TOGGLES[n]) for n in ALL_TOGGLES]}


def make_objective(cfg, fixed_toggles, rows_out):
    def objective(trial):
        ov = dict(fixed_toggles)
        for key, lo, hi, is_int in SPACE:
            ov[key] = trial.suggest_int(key, int(lo), int(hi)) if is_int \
                else round(trial.suggest_float(key, lo, hi), 4)
        with tempfile.TemporaryDirectory() as tmp:
            rows = run_trial(cfg, ov, tmp, str(trial.number))
        if len(rows) < MIN_TRADES:
            return 0.0
        pnls = [p for _, p in rows]
        full = metrics(pnls)
        if full["pf"] < 1.0:
            return 0.0
        t0, t1 = rows[0][0], rows[-1][0]
        cut = t0 + 0.67 * (t1 - t0)
        tr = metrics([p for ts, p in rows if ts < cut])
        te = metrics([p for ts, p in rows if ts >= cut])
        score = (full["net"] / (1.0 + full["dd"])) * (1.15 if (tr["net"] > 0 and te["net"] > 0) else 0.85)
        rows_out.append({**ov, "score": round(score, 4), "full_net": round(full["net"], 1),
                         "full_pf": round(full["pf"], 4), "full_dd": round(full["dd"], 1), "n": full["n"],
                         "train_net": round(tr["net"], 1), "test_net": round(te["net"], 1),
                         "test_pf": round(te["pf"], 4)})
        for k, v in (("full_net", full["net"]), ("full_pf", full["pf"]), ("full_dd", full["dd"]),
                     ("n", full["n"]), ("test_net", te["net"]), ("test_pf", te["pf"])):
            trial.set_user_attr(k, v)
        return score
    return objective


def main():
    sym = sys.argv[1] if len(sys.argv) > 1 else "btc"
    n_trials = int(sys.argv[2]) if len(sys.argv) > 2 else 80
    n_jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    cfg = SYMS[sym]
    optuna.logging.set_verbosity(optuna.logging.WARNING)

    summary = []
    best_rows = []
    for label, on_set in ENTRY_SETS:
        fixed = toggles_for(on_set)
        rows = []
        study = optuna.create_study(direction="maximize",
                                    sampler=optuna.samplers.TPESampler(multivariate=True, seed=7))
        study.optimize(make_objective(cfg, fixed, rows), n_trials=n_trials, n_jobs=n_jobs)
        if not rows:
            print(f"  {label:9s}  (no valid trial — too few trades / PF<1 everywhere)")
            summary.append((label, None))
            continue
        a = study.best_trial.user_attrs
        rec = dict(entry_set=label, score=round(study.best_value, 3), full_net=round(a["full_net"], 1),
                   full_pf=round(a["full_pf"], 3), full_dd=round(a["full_dd"], 1), n=int(a["n"]),
                   test_net=round(a["test_net"], 1), test_pf=round(a["test_pf"], 3))
        summary.append((label, rec))
        # keep the full best param row (for promotion later)
        best = max(rows, key=lambda r: r["score"])
        best_rows.append({"entry_set": label, **best})
        print(f"  {label:9s}  net={rec['full_net']:9.0f}  pf={rec['full_pf']:.3f}  dd={rec['full_dd']:8.0f}  "
              f"n={rec['n']:5d}  test_net={rec['test_net']:8.0f}  test_pf={rec['test_pf']:.3f}  score={rec['score']:.2f}")

    print(f"\n===== KenKem entry-set ranking [{sym.upper()}] (by risk-adjusted score) =====")
    ranked = sorted([s for _, s in summary if s], key=lambda r: -r["score"])
    for r in ranked:
        oos = "OOS+" if r["test_net"] > 0 else "OOS-"
        print(f"  {r['entry_set']:9s}  score={r['score']:8.2f}  net={r['full_net']:9.0f}  pf={r['full_pf']:.3f}  "
              f"dd={r['full_dd']:8.0f}  {oos}")
    if ranked:
        top = ranked[0]
        print(f"\n  TOP by score: {top['entry_set']}  (net={top['full_net']:.0f}, pf={top['full_pf']:.3f}, "
              f"dd={top['full_dd']:.0f}, test_net={top['test_net']:.0f})")

    if best_rows:
        fields = sorted(set().union(*(r.keys() for r in best_rows)))
        out = os.path.join(HERE, f"sweep_kenkem_entrysets_{sym}.csv")
        with open(out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields, restval="", extrasaction="ignore")
            w.writeheader()
            w.writerows(sorted(best_rows, key=lambda r: -r["score"]))
        print(f"\n  wrote {out}")


if __name__ == "__main__":
    main()
