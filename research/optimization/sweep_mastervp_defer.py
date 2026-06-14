#!/usr/bin/env python3
"""DeferredEntry sweep for KK-MasterVP: hold the locked best_mastervp_<sym>.set FIXED and sweep
ONLY the pullback-limit knobs (InpEnableDeferEntry + defer_pullback_atr + defer_bars). Isolates
the marginal effect of waiting for a better entry price. ADOPT only if it strictly beats the
feature-OFF baseline (full PF↑ AND net↑, test net non-negative).

Usage:  python research/optimization/sweep_mastervp_defer.py <btc|xau> [n_trials]
Outputs: sweep_mastervp_defer_<sym>.csv ; prints baseline vs best + VERDICT (no auto-overwrite).
"""
import csv, os, sys, tempfile
import optuna
from eval_mastervp import run

HERE = os.path.dirname(__file__)


def fmt(tag, full, te):
    return (f"{tag:9s} full[n={full['n']:4d} pf={full['pf']:.3f} net={full['net']:8.1f} "
            f"dd={full['dd']:7.1f}] test[pf={te['pf']:.3f} net={te['net']:7.1f}]")


def main():
    sym = sys.argv[1] if len(sys.argv) > 1 else "btc"
    n_trials = int(sys.argv[2]) if len(sys.argv) > 2 else 80
    base_set = os.path.join(HERE, f"best_mastervp_{sym}.set")
    base_lines = [ln.rstrip("\n") for ln in open(base_set) if "=" in ln]

    def write_set(path, ov):
        keys = set(ov)
        with open(path, "w") as f:
            for ln in base_lines:
                if ln.split("=", 1)[0] not in keys:
                    f.write(ln + "\n")
            for k, v in ov.items():
                f.write(f"{k}={v}\n")

    def eval_ov(ov):
        with tempfile.TemporaryDirectory() as tmp:
            s = os.path.join(tmp, "s.set"); write_set(s, ov)
            return run(sym, s)

    b_tr, b_te, b_full = run(sym, base_set)
    print(fmt("BASELINE", b_full, b_te))

    rows = []

    def objective(trial):
        ov = {"InpEnableDeferEntry": "true",
              "InpDeferPullbackAtr": round(trial.suggest_float("InpDeferPullbackAtr", 0.1, 1.5), 3),
              "InpDeferBars": trial.suggest_int("InpDeferBars", 1, 6)}
        tr, te, full = eval_ov(ov)
        if full["n"] < 0.4 * b_full["n"]:   # deferral misses some fills; allow more shrinkage
            return -1e6 + full["n"]
        score = (full["net"] / (1.0 + full["dd"])) * (1.15 if (tr["net"] > 0 and te["net"] > 0) else 1.0)
        rows.append({**ov, "score": round(score, 3), "full_pf": round(full["pf"], 3),
                     "full_net": round(full["net"], 1), "full_dd": round(full["dd"], 1),
                     "n": full["n"], "test_pf": round(te["pf"], 3), "test_net": round(te["net"], 1)})
        for k, v in (("full_pf", full["pf"]), ("full_net", full["net"]), ("full_dd", full["dd"]),
                     ("n", full["n"]), ("test_pf", te["pf"]), ("test_net", te["net"])):
            trial.set_user_attr(k, v)
        return score

    optuna.logging.set_verbosity(optuna.logging.WARNING)
    study = optuna.create_study(direction="maximize",
                                sampler=optuna.samplers.TPESampler(seed=42, n_startup_trials=15))
    study.optimize(objective, n_trials=n_trials)

    a = study.best_trial.user_attrs
    best_full = dict(n=a["n"], pf=a["full_pf"], net=a["full_net"], dd=a["full_dd"])
    best_te = dict(pf=a["test_pf"], net=a["test_net"])
    print(fmt("DEF-BEST", best_full, best_te))
    print("PARAMS:", study.best_trial.params)
    better = (best_full["pf"] > b_full["pf"] and best_full["net"] > b_full["net"]
              and best_te["net"] >= 0)
    print(f"VERDICT: {'ADOPT — Defer improves ' + sym.upper() if better else 'REJECT — keep Defer OFF for ' + sym.upper()}")
    if better:
        print(f"  PF {b_full['pf']:.3f} -> {best_full['pf']:.3f} | net {b_full['net']:.0f} -> {best_full['net']:.0f}")

    if rows:
        fields = sorted(set().union(*(r.keys() for r in rows)))
        with open(os.path.join(HERE, f"sweep_mastervp_defer_{sym}.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields, restval="", extrasaction="ignore")
            w.writeheader(); w.writerows(sorted(rows, key=lambda r: r["score"], reverse=True))


if __name__ == "__main__":
    main()
