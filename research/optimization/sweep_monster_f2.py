#!/usr/bin/env python3
"""Feature #2 sweep for KK-Monster: hold the locked best_monster_real_<sym>.set FIXED and
sweep ONLY the volume-node STRUCTURE SL/TP knobs (already implemented in monster_signal.hpp,
default OFF): HVN-shelf SL + structural TP2. This isolates F2's marginal contribution. We
only ADOPT a result that strictly beats the feature-OFF baseline on full PF AND full net
(and keeps the test split non-negative).

Each trial may turn on either/both of:
  InpEnableHvnShelfSl   -> SL snapped to the nearest high-volume-node shelf + buffer
  InpEnableStructuralTp2-> TP2 placed at node structure, clamped to [stp2_min_rr, stp2_max_rr]

Usage:  python research/optimization/sweep_monster_f2.py <btc|xau> [n_trials]
Outputs: sweep_monster_f2_<sym>.csv ; prints baseline vs best + a VERDICT (no auto-overwrite).
"""
import csv, os, sys, tempfile
import optuna
from eval_monster import run  # reuse the exact monster backtest harness

HERE = os.path.dirname(__file__)


def fmt(tag, full, te):
    return (f"{tag:9s} full[n={full['n']:4d} pf={full['pf']:.3f} net={full['net']:8.1f} "
            f"dd={full['dd']:7.1f}] test[pf={te['pf']:.3f} net={te['net']:7.1f}]")


def main():
    sym = sys.argv[1] if len(sys.argv) > 1 else "btc"
    n_trials = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    base_set = os.path.join(HERE, f"best_monster_real_{sym}.set")
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
        use_sl = trial.suggest_categorical("hvn_sl", [False, True])
        use_tp = trial.suggest_categorical("struct_tp2", [False, True])
        if not use_sl and not use_tp:
            return -1e6  # no-op trial; baseline already known
        if use_sl:
            ov["InpEnableHvnShelfSl"] = "true"
            ov["InpShelfNearAtr"] = round(trial.suggest_float("InpShelfNearAtr", 0.2, 1.2), 3)
            ov["InpShelfFarAtr"] = round(trial.suggest_float("InpShelfFarAtr", 1.5, 4.0), 3)
            ov["InpShelfBufAtr"] = round(trial.suggest_float("InpShelfBufAtr", 0.05, 0.6), 3)
        if use_tp:
            ov["InpEnableStructuralTp2"] = "true"
            ov["InpStp2HvnFrac"] = round(trial.suggest_float("InpStp2HvnFrac", 0.4, 0.9), 3)
            ov["InpStp2EdgeOffAtr"] = round(trial.suggest_float("InpStp2EdgeOffAtr", 0.05, 0.6), 3)
            lo = round(trial.suggest_float("InpStp2MinRr", 0.8, 2.0), 3)
            hi = round(trial.suggest_float("InpStp2MaxRr", 2.0, 5.0), 3)
            ov["InpStp2MinRr"] = lo
            ov["InpStp2MaxRr"] = max(hi, lo + 0.1)
        tr, te, full = eval_ov(ov)
        if full["n"] < 0.5 * b_full["n"]:
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
                                sampler=optuna.samplers.TPESampler(seed=42, n_startup_trials=20))
    study.optimize(objective, n_trials=n_trials)

    a = study.best_trial.user_attrs
    best_full = dict(n=a["n"], pf=a["full_pf"], net=a["full_net"], dd=a["full_dd"])
    best_te = dict(pf=a["test_pf"], net=a["test_net"])
    print(fmt("F2-BEST", best_full, best_te))
    print("PARAMS:", study.best_trial.params)
    better = (best_full["pf"] > b_full["pf"] and best_full["net"] > b_full["net"]
              and best_te["net"] >= 0)
    print(f"VERDICT: {'ADOPT — F2 improves ' + sym.upper() if better else 'REJECT — keep F2 OFF for ' + sym.upper()}")
    if better:
        print(f"  PF {b_full['pf']:.3f} -> {best_full['pf']:.3f} | net {b_full['net']:.0f} -> {best_full['net']:.0f}")

    if rows:  # union of keys across trials (SL-only / TP-only / both differ) — write last
        fields = sorted(set().union(*(r.keys() for r in rows)))
        with open(os.path.join(HERE, f"sweep_monster_f2_{sym}.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields, restval="", extrasaction="ignore")
            w.writeheader()
            w.writerows(sorted(rows, key=lambda r: r["score"], reverse=True))


if __name__ == "__main__":
    main()
