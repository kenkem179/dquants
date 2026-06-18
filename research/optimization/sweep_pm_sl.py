#!/usr/bin/env python3
"""ProfitManager SL-toggle sweep (Phase-14 C5, round 1 — the two PURE, highest-EV stop toggles).

Holds the locked best_<engine>_<sym>.set FIXED and sweeps ONLY the kk::common::ProfitManager
SL toggles (default OFF in code):
  giveback_cap     -> once peak MFE >= arm_r, the stop locks >= (1-cap_frac) of peak gain
  progressive_trail-> at trigger_r the stop steps to entry, then ratchets step_r per increment_r

Each trial may enable either/both. ADOPT only if it satisfies the standing risk-adjusted rule:
**full net UP AND full maxDD DOWN** vs the toggle-OFF baseline, with the test split kept >= 0.
Otherwise keep the toggles OFF (.set unchanged).

Usage:  python research/optimization/sweep_pm_sl.py <mastervp|monster> <btc|xau> [n_trials]
Outputs: sweep_pm_sl_<engine>_<sym>.csv ; prints baseline vs best + VERDICT (no auto-overwrite).
"""
import csv, os, sys, tempfile
import optuna

HERE = os.path.dirname(__file__)

ENGINES = {
    "mastervp": dict(set_tmpl="best_mastervp_{sym}.set", run_mod="eval_mastervp"),
    "monster":  dict(set_tmpl="best_monster_real_{sym}.set", run_mod="eval_monster"),
}


def fmt(tag, full, te):
    return (f"{tag:9s} full[n={full['n']:4d} pf={full['pf']:.3f} net={full['net']:8.1f} "
            f"dd={full['dd']:7.1f}] test[pf={te['pf']:.3f} net={te['net']:7.1f}]")


def main():
    engine = sys.argv[1] if len(sys.argv) > 1 else "mastervp"
    sym = sys.argv[2] if len(sys.argv) > 2 else "btc"
    n_trials = int(sys.argv[3]) if len(sys.argv) > 3 else 160
    cfg = ENGINES[engine]
    run = __import__(cfg["run_mod"]).run

    base_set = os.path.join(HERE, cfg["set_tmpl"].format(sym=sym))
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
        ov = {}
        use_gb = trial.suggest_categorical("giveback", [False, True])
        use_pt = trial.suggest_categorical("prog_trail", [False, True])
        if not use_gb and not use_pt:
            return -1e6
        if use_gb:
            ov["InpPmGiveback"] = "true"
            ov["InpPmGivebackArmR"] = round(trial.suggest_float("InpPmGivebackArmR", 1.0, 3.5), 3)
            ov["InpPmGivebackCapFrac"] = round(trial.suggest_float("InpPmGivebackCapFrac", 0.15, 0.50), 3)
        if use_pt:
            ov["InpPmProgTrail"] = "true"
            ov["InpPmProgTriggerR"] = round(trial.suggest_float("InpPmProgTriggerR", 0.5, 2.0), 3)
            ov["InpPmProgIncrementR"] = round(trial.suggest_float("InpPmProgIncrementR", 0.25, 1.0), 3)
            ov["InpPmProgStepR"] = round(trial.suggest_float("InpPmProgStepR", 0.05, 0.40), 3)
        tr, te, full = eval_ov(ov)
        if full["n"] < 0.5 * b_full["n"]:
            return -1e6 + full["n"]
        # reward net per unit drawdown; bonus when both splits stay positive (robustness).
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
                                sampler=optuna.samplers.TPESampler(seed=42, n_startup_trials=24))
    study.optimize(objective, n_trials=n_trials)

    a = study.best_trial.user_attrs
    best_full = dict(n=a["n"], pf=a["full_pf"], net=a["full_net"], dd=a["full_dd"])
    best_te = dict(pf=a["test_pf"], net=a["test_net"])
    print(fmt("PM-BEST", best_full, best_te))
    print("PARAMS:", study.best_trial.params)
    # standing rule: risk-adjusted — net UP and drawdown DOWN (and OOS not negative).
    better = (best_full["net"] > b_full["net"] and best_full["dd"] < b_full["dd"]
              and best_te["net"] >= 0)
    tag = f"{engine.upper()}-{sym.upper()}"
    print(f"VERDICT: {'ADOPT — PM SL toggles improve ' + tag if better else 'REJECT — keep PM OFF for ' + tag}")
    print(f"  net {b_full['net']:.0f} -> {best_full['net']:.0f} | dd {b_full['dd']:.0f} -> {best_full['dd']:.0f}"
          f" | pf {b_full['pf']:.3f} -> {best_full['pf']:.3f}")

    if rows:
        fields = sorted(set().union(*(r.keys() for r in rows)))
        out = os.path.join(HERE, f"sweep_pm_sl_{engine}_{sym}.csv")
        with open(out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields, restval="", extrasaction="ignore")
            w.writeheader()
            w.writerows(sorted(rows, key=lambda r: r["score"], reverse=True))


if __name__ == "__main__":
    main()
