#!/usr/bin/env python3
"""Deep E1 re-tune (user request 2026-06-14): give E1 a fair shot.

The first entry-set sweep (sweep_kenkem_entrysets.py) tuned E1 with only its RR + age + SL/trail/partial
+ E1_HTF_MIN_ADX, plus the shared ADX/sideways knobs. It did NOT expose the levers that most shape E1's
selectivity: the trend-quality HARD-GATE toggle, E1's HTF filter MODE + DI-spread, E1's own momentum-ADX,
the EMA-alignment tolerance (E1 requires EMA-stack alignment at decision time), and E1's sideways RR.
This script re-runs the E1-containing entry-sets with that EXPANDED space and more trials, then prints the
before/after vs the baseline sweep so we can see whether E1 was genuinely weak or just under-tuned.

Live trend-quality gate (gates.hpp trend_core_score, 0-6): ADX pts (min_momentum_adx / adx_high_threshold),
DI-spread pts (HARDCODED 1.0/3.0 — not .set-tunable), MTF-alignment pts (hardcoded). The HARD GATE that
blocks the trade when any component is 0 is toggled by ENABLE_TREND_QUALITY_GATES. So the tunable
"trend-quality" surface for E1 = {enable_tq_gates, min_momentum_adx, adx_high_threshold} + the HTF filter.

Usage: python research/optimization/sweep_kenkem_e1_deep.py <btc|xau> [n_trials] [n_jobs] [combos_csv]
"""
import os, sys, csv, tempfile
import optuna
from sweep_kenkem_entrysets import (SYMS, SPACE, COMBOS, run_bars, metrics, base_overrides,
                                    write_set, HERE)

# Expanded E1 levers absent from the baseline sweep. (key, lo, hi, kind)
#   kind: "int" | "float" | choice-list (for categoricals)
E1_EXTRA = [
    ("ENABLE_TREND_QUALITY_GATES", ["true", "false"]),   # hard-gate on/off (biggest volume lever)
    ("E1_HTF_TREND_FILTER", [0, 1, 3, 4]),               # off / M5 / M15 / M5-or-M15
    ("E1_HTF_MIN_DI_SPREAD", 2.0, 10.0, "float"),
    ("E1_MIN_MOMENTUM_ADX", 14.0, 28.0, "float"),
    ("E1_RR_SIDEWAY", 1.0, 2.2, "float"),
    ("EMA_ALIGNMENT_TOLERANCE_PIPS", 5.0, 45.0, "float"),
    ("EXTREME_DI_SPREAD_THRESHOLD", 10.0, 22.0, "float"),
]
# widen E1_RR beyond the baseline's 1.2-3.0
E1_RR_WIDE = ("E1_RR", 1.2, 3.6, False, "e1")

MIN_TRADES = 120


def make_objective(cfg, active):
    tags = {"shared"} | set(active)
    space = [s for s in SPACE if s[4] in tags and s[0] != "E1_RR"] + [E1_RR_WIDE]

    def objective(trial):
        ov = base_overrides(active)
        for key, lo, hi, is_int, _ in space:
            ov[key] = trial.suggest_int(key, int(lo), int(hi)) if is_int \
                else round(trial.suggest_float(key, lo, hi), 4)
        for spec in E1_EXTRA:
            key = spec[0]
            if isinstance(spec[1], list):
                ov[key] = trial.suggest_categorical(key, spec[1])
            else:
                _, lo, hi, _kind = spec
                ov[key] = round(trial.suggest_float(key, lo, hi), 4)
        with tempfile.TemporaryDirectory() as tmp:
            rows = run_bars(cfg, ov, cfg["m1"], tmp, str(trial.number))
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
        score = (full["net"] / (1.0 + full["dd"])) * (1.15 if (tr["net"] > 0 and te["net"] > 0) else 0.80)
        trial.set_user_attr("ov", ov)
        trial.set_user_attr("is", full)
        trial.set_user_attr("tr", tr)
        trial.set_user_attr("te", te)
        return score
    return objective


def main():
    sym = sys.argv[1] if len(sys.argv) > 1 else "btc"
    n_trials = int(sys.argv[2]) if len(sys.argv) > 2 else 700
    n_jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    only = sys.argv[4].split(",") if len(sys.argv) > 4 else ["E1", "E1_E2", "E1_E5", "E1_E2_E4", "ALL"]
    cfg = SYMS[sym]
    optuna.logging.set_verbosity(optuna.logging.WARNING)

    summary = []
    print(f"===== KenKem DEEP-E1 sweep [{sym.upper()}]  trials={n_trials} jobs={n_jobs} =====")
    for name in only:
        active = COMBOS[name]
        study = optuna.create_study(
            direction="maximize",
            sampler=optuna.samplers.TPESampler(multivariate=True, seed=7))
        study.optimize(make_objective(cfg, active), n_trials=n_trials, n_jobs=n_jobs)
        bt = study.best_trial
        if bt.value <= 0.0 or "ov" not in bt.user_attrs:
            print(f"[{sym}:{name:9s}] no valid config")
            continue
        ov = bt.user_attrs["ov"]
        iss, tr, te = bt.user_attrs["is"], bt.user_attrs["tr"], bt.user_attrs["te"]
        with tempfile.TemporaryDirectory() as tmp:
            oos = metrics([p for _, p in run_bars(cfg, ov, cfg["oos"], tmp, f"{name}_oos")])
        write_set(os.path.join(HERE, f"best_kenkem_{name}_deep_{sym}.set"), ov)
        summary.append(dict(combo=name, is_n=iss["n"], is_net=round(iss["net"]), is_pf=round(iss["pf"], 3),
                            is_dd=round(iss["dd"]), te_pf=round(te["pf"], 3),
                            oos_n=oos["n"], oos_net=round(oos["net"]), oos_pf=round(oos["pf"], 3),
                            oos_dd=round(oos["dd"]),
                            tq_gate=ov.get("ENABLE_TREND_QUALITY_GATES"),
                            e1_htf=ov.get("E1_HTF_TREND_FILTER"), e1_rr=ov.get("E1_RR")))
        print(f"[{sym}:{name:9s}] IS pf={iss['pf']:.3f} net={iss['net']:>9.0f} n={iss['n']:>5d} "
              f"dd={iss['dd']:>7.0f} te_pf={te['pf']:.3f} | OOS26 pf={oos['pf']:.3f} net={oos['net']:>9.0f} "
              f"n={oos['n']:>5d} dd={oos['dd']:>7.0f} | tq={ov.get('ENABLE_TREND_QUALITY_GATES')} "
              f"htf={ov.get('E1_HTF_TREND_FILTER')} rr={ov.get('E1_RR')}")

    out = os.path.join(HERE, f"sweep_kenkem_e1_deep_{sym}.csv")
    if summary:
        with open(out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(summary[0].keys()))
            w.writeheader()
            w.writerows(summary)
    print(f"\n[{sym}] deep-E1 summary -> {out}")


if __name__ == "__main__":
    main()
