#!/usr/bin/env python3
"""Feature #1 sweep for KK-MasterVP: hold the locked best_mastervp_<sym>.set FIXED and sweep
ONLY the multi-bar net-volume knobs (persistence-on-entry + N-bar flip-exit). This isolates
F1's marginal contribution. We only ever ADOPT a result that strictly beats the feature-OFF
baseline on BOTH full PF and full net (and does not wreck the test split or DD).

Usage:  python research/optimization/sweep_mastervp_f1.py <btc|xau> [n_trials]
Outputs: sweep_mastervp_f1_<sym>.csv ; (does NOT overwrite the .set — adoption is manual/guarded)
Prints the baseline and the best feature-on trial side by side + a VERDICT.
"""
import csv, os, sys
import optuna
from eval_mastervp import run, SYMS  # reuse the exact backtest harness

HERE = os.path.dirname(__file__)


def fmt(tag, full, te):
    return (f"{tag:9s} full[n={full['n']:4d} pf={full['pf']:.3f} net={full['net']:8.1f} "
            f"dd={full['dd']:7.1f}] test[pf={te['pf']:.3f} net={te['net']:7.1f}]")


def main():
    sym = sys.argv[1] if len(sys.argv) > 1 else "btc"
    n_trials = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    base_set = os.path.join(HERE, f"best_mastervp_{sym}.set")
    base_lines = [ln.rstrip("\n") for ln in open(base_set) if "=" in ln]

    import tempfile
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

    # ---- baseline: feature OFF (the locked .set as-is) ----
    b_tr, b_te, b_full = run(sym, base_set)
    print(fmt("BASELINE", b_full, b_te))

    rows = []

    def objective(trial):
        ov = {"InpEnableNetPersist": "true",
              "InpNetPersistBars": trial.suggest_int("InpNetPersistBars", 1, 6),
              "InpNetPersistMin": round(trial.suggest_float("InpNetPersistMin", 0.05, 1.5), 3),
              "InpNetVolAvgLen": trial.suggest_int("InpNetVolAvgLen", 20, 80)}
        flip = trial.suggest_categorical("flip", [False, True])
        if flip:
            ov["InpEnableNetFlipExit"] = "true"
            ov["InpNetFlipBars"] = trial.suggest_int("InpNetFlipBars", 1, 6)
            ov["InpNetFlipMin"] = round(trial.suggest_float("InpNetFlipMin", 0.05, 1.5), 3)
        tr, te, full = eval_ov(ov)
        # min-trade floor: don't let persistence starve the strategy to a handful of trades
        if full["n"] < 0.5 * b_full["n"]:
            return -1e6 + full["n"]
        # objective: net/(1+dd) with a consistency bonus, same shape as the main optimizer
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
                                sampler=optuna.samplers.TPESampler(seed=42, n_startup_trials=20))
    study.optimize(objective, n_trials=n_trials)

    if rows:
        with open(os.path.join(HERE, f"sweep_mastervp_f1_{sym}.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader()
            w.writerows(sorted(rows, key=lambda r: r["score"], reverse=True))

    a = study.best_trial.user_attrs
    best_full = dict(n=a["n"], pf=a["full_pf"], net=a["full_net"], dd=a["full_dd"])
    best_te = dict(pf=a["test_pf"], net=a["test_net"])
    print(fmt("F1-BEST", best_full, best_te))
    print("PARAMS:", study.best_trial.params)

    better = (best_full["pf"] > b_full["pf"] and best_full["net"] > b_full["net"]
              and best_te["net"] >= 0)
    print(f"VERDICT: {'ADOPT — F1 improves ' + sym.upper() if better else 'REJECT — keep F1 OFF for ' + sym.upper()}")
    if better:
        print(f"  PF {b_full['pf']:.3f} -> {best_full['pf']:.3f} | net {b_full['net']:.0f} -> {best_full['net']:.0f}")


if __name__ == "__main__":
    main()
