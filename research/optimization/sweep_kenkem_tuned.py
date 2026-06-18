#!/usr/bin/env python3
"""KenKem per-entry tuning -> combination study (user request 2026-06-14).

Two phases, so each entry's own knobs (RR, sideways-RR, trend-quality score, per-entry + shared ADX/
sideways gates, momentum-bypass "risky entry", SL/trail/partial) are tuned FIRST in isolation, then the
best-tuned entries are combined:

  phaseA <sym>  -- for each of E1/E2/E4/E5: enable ONLY it, search its full knob set + the shared regime
                   gates on 2025, validate the winner on 2026 (true OOS), write best_tuned_<e>_<sym>.json
                   (per-entry knobs to freeze) + print OOS + a plateau spread of the top trials.
  phaseB <sym>  -- for each requested combo {E1_E2,E1_E5,E2_E5,E1_E2_E5,E4_E5}: FREEZE every active
                   entry's per-entry knobs at their phaseA best, re-tune ONLY the shared regime gates,
                   validate on 2026 OOS, write best_kenkem_<combo>_<sym>.set. Ranks combos by OOS PF.

Engine SHAPE params (EMA0-4 periods, ADX_LEN, RSI_LEN, SL_EMA_DISTANCE base) are FIXED at the current
production best_kenkem_<sym>.set so entries remain combinable (they must share one indicator stack).
Trend-quality gating is forced ON; MIN_TREND_QUALITY_Ex=0 means "no gate", so the threshold folds the
on/off into one swept knob. Promotion to the locked .set stays a separate, explicit step (user decides).

Usage:
  python research/optimization/sweep_kenkem_tuned.py phaseA <btc|xau> [n_trials] [n_jobs]
  python research/optimization/sweep_kenkem_tuned.py phaseB <btc|xau> [n_trials] [n_jobs]
"""
import os, sys, csv, json, subprocess, tempfile
import optuna
from sweep_kenkem_entrysets import SYMS, run_bars, metrics, HERE, TOGGLE, ALL_ENTRIES

# ---- per-entry knob spaces: (key, lo, hi, is_int) ----
ENTRY_SPACE = {
    "e1": [("E1_RR", 1.2, 3.0, False), ("E1_RR_SIDEWAY", 0.8, 1.8, False),
           ("E1_MAX_CROSS_AGE", 30, 120, True), ("E1_ATR_SL_CAP_MULTIPLIER", 1.5, 4.5, False),
           ("E1_TRAILING_SL_FACTOR", 0.2, 0.7, False), ("E1_PARTIAL_TP_TRIGGER", 0.5, 0.95, False),
           ("E1_PARTIAL_TP_RATIO", 0.15, 0.5, False), ("E1_HTF_MIN_ADX", 12.0, 30.0, False),
           ("E1_MIN_MOMENTUM_ADX", 12.0, 28.0, False), ("E1_MOMENTUM_BYPASS_LEVEL", 0, 2, True),
           ("E1_SL_TO_BREAKEVEN_BUFFER", 0.02, 0.15, False), ("MIN_TREND_QUALITY_E1", 0, 6, True)],
    "e2": [("E2_RR", 1.2, 3.0, False), ("E2_RR_SIDEWAY", 0.8, 1.8, False),
           ("E2_MAX_TOUCH_AGE", 12, 60, True), ("E2_ATR_SL_CAP_MULTIPLIER", 1.5, 4.0, False),
           ("E2_TRAILING_SL_FACTOR", 0.2, 0.7, False), ("E2_PARTIAL_TP_TRIGGER", 0.5, 0.95, False),
           ("E2_PARTIAL_TP_RATIO", 0.15, 0.5, False), ("E2_HTF_MIN_ADX", 12.0, 30.0, False),
           ("E2_MIN_MOMENTUM_ADX", 12.0, 28.0, False),
           ("E2_SL_TO_BREAKEVEN_BUFFER", 0.02, 0.15, False), ("MIN_TREND_QUALITY_E2", 0, 6, True)],
    "e4": [("E4_RR", 1.5, 3.2, False), ("E4_RR_SHORT", 1.2, 2.6, False), ("E4_RR_SIDEWAY", 0.8, 1.8, False),
           ("E4_MAX_CROSS_AGE", 12, 50, True), ("E4_ATR_SL_CAP_MULTIPLIER", 1.5, 4.5, False),
           ("E4_TRAILING_SL_FACTOR", 0.2, 0.7, False), ("E4_PARTIAL_TP_TRIGGER", 0.5, 0.95, False),
           ("E4_PARTIAL_TP_RATIO", 0.15, 0.5, False), ("E4_HTF_MIN_ADX", 12.0, 30.0, False),
           ("E4_MIN_MOMENTUM_ADX", 12.0, 28.0, False), ("E4_MOMENTUM_BYPASS_LEVEL", 0, 2, True),
           ("E4_MAX_SIDEWAY_SCORE", 20, 60, True), ("E4_MIN_CLOUD_THICKNESS_ATR_MULT", 0.0, 0.3, False),
           ("E4_SL_TO_BREAKEVEN_BUFFER", 0.02, 0.15, False), ("MIN_TREND_QUALITY_E4", 0, 6, True)],
    "e5": [("E5_RR", 1.2, 2.5, False), ("E5_RR_SIDEWAY", 0.8, 1.8, False),
           ("E5_MAX_EMA_CROSS_AGE", 10, 50, True), ("E5_MIN_MOMENTUM_ADX", 0.0, 25.0, False),
           ("E5_ATR_SL_CAP_MULTIPLIER", 1.5, 4.5, False), ("E5_TRAILING_SL_FACTOR", 0.2, 0.7, False),
           ("E5_PARTIAL_TP_TRIGGER", 0.2, 0.6, False), ("E5_PARTIAL_TP_RATIO", 0.2, 0.6, False),
           ("E5_HTF_MIN_ADX", 12.0, 30.0, False), ("E5_SL_TO_BREAKEVEN_BUFFER", 0.02, 0.15, False)],
}
# shared regime gates — tuned in phaseA with each single, re-tuned per-combo in phaseB
SHARED_SPACE = [("SIDEWAYS_BLOCK_THRESHOLD", 40, 62, True), ("SIDEWAYS_WARNING_THRESHOLD", 30, 50, True),
                ("MIN_MOMENTUM_ADX_REQUIRED", 12.0, 28.0, False), ("ADX_LOW_THRESHOLD", 10.0, 20.0, False),
                ("ADX_HIGH_THRESHOLD", 20.0, 32.0, False), ("SL_EMA_DISTANCE", 8, 45, True)]
SHARED_CAT = [("REQUIRE_ADX_CONFLUENCE", ["true", "false"])]

COMBOS = {"E1_E2": ["e1", "e2"], "E1_E5": ["e1", "e5"], "E2_E5": ["e2", "e5"],
          "E1_E2_E5": ["e1", "e2", "e5"], "E4_E5": ["e4", "e5"]}
MIN_TRADES = 80


def read_set(path):
    ov = {}
    for ln in open(path):
        ln = ln.strip()
        if "=" in ln and not ln.startswith(";"):
            k, v = ln.split("=", 1)
            ov[k.strip()] = v.strip()
    return ov


def write_set(path, ov):
    with open(path, "w") as f:
        f.write("; KenKem tuned sweep\n")
        for k, v in ov.items():
            f.write(f"{k}={v}\n")


def base_for(sym):
    """Current production set = the FIXED engine shape (EMA stack / lengths) + sane defaults."""
    b = read_set(os.path.join(HERE, f"best_kenkem_{sym}.set"))
    b["ENABLE_TREND_QUALITY_GATES"] = "true"   # gating folded into MIN_TREND_QUALITY_Ex (0 = off)
    return b


def toggles(active):
    return {TOGGLE[e]: ("true" if e in active else "false") for e in ALL_ENTRIES}


def suggest(trial, space):
    ov = {}
    for key, lo, hi, is_int in space:
        ov[key] = trial.suggest_int(key, int(lo), int(hi)) if is_int \
            else round(trial.suggest_float(key, lo, hi), 4)
    return ov


def evaluate(cfg, ov):
    with tempfile.TemporaryDirectory() as tmp:
        rows = run_bars(cfg, ov, cfg["m1"], tmp, "is")
        if len(rows) < MIN_TRADES:
            return None
        pnls = [p for _, p in rows]
        full = metrics(pnls)
        if full["pf"] < 1.0:
            return None
        t0, t1 = rows[0][0], rows[-1][0]
        cut = t0 + 0.67 * (t1 - t0)
        tr = metrics([p for ts, p in rows if ts < cut])
        te = metrics([p for ts, p in rows if ts >= cut])
        oos = metrics([p for _, p in run_bars(cfg, ov, cfg["oos"], tmp, "oos")])
    score = (full["net"] / (1.0 + full["dd"])) * (1.15 if (tr["net"] > 0 and te["net"] > 0) else 0.80)
    return dict(score=score, full=full, tr=tr, te=te, oos=oos)


def phaseA(sym, n_trials, n_jobs):
    cfg = SYMS[sym]
    base = base_for(sym)
    print(f"===== KenKem phaseA per-entry tuning [{sym.upper()}] trials={n_trials} =====")
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
            trial.set_user_attr("ov", ov); trial.set_user_attr("r", r)
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
        # freeze ONLY this entry's per-entry knobs (shared gates re-tuned per combo in phaseB)
        entry_keys = [k for k, *_ in ENTRY_SPACE[e]]
        frozen = {k: best_ov[k] for k in entry_keys}
        json.dump(frozen, open(os.path.join(HERE, f"best_tuned_{e}_{sym}.json"), "w"), indent=2)
        write_set(os.path.join(HERE, f"best_tuned_{e}_{sym}.set"), best_ov)
        # plateau: spread of RR + key gates across top-8
        top = rows[:8]
        def spread(k):
            vals = [float(o[k]) for _, o, _ in top if k in o]
            return f"{min(vals):.2f}-{max(vals):.2f}" if vals else "-"
        rrk = {"e1": "E1_RR", "e2": "E2_RR", "e4": "E4_RR", "e5": "E5_RR"}[e]
        print(f"  {e.upper()}: IS pf={r['full']['pf']:.3f} net={r['full']['net']:>8.0f} n={r['full']['n']:>4d} "
              f"dd={r['full']['dd']:>7.0f} | OOS26 pf={r['oos']['pf']:.3f} net={r['oos']['net']:>8.0f} "
              f"n={r['oos']['n']:>4d}")
        print(f"        best {rrk}={best_ov.get(rrk)} | top8 {rrk}∈[{spread(rrk)}] "
              f"SIDEWAYS_BLOCK∈[{spread('SIDEWAYS_BLOCK_THRESHOLD')}] MIN_MOM_ADX∈[{spread('MIN_MOMENTUM_ADX_REQUIRED')}]")
    print(f"\n  phaseA done -> best_tuned_<e>_{sym}.json (frozen per-entry knobs) + .set")


def phaseB(sym, n_trials, n_jobs):
    cfg = SYMS[sym]
    base = base_for(sym)
    # load frozen per-entry knobs
    frozen = {}
    for e in ALL_ENTRIES:
        p = os.path.join(HERE, f"best_tuned_{e}_{sym}.json")
        if os.path.exists(p):
            frozen[e] = json.load(open(p))
    print(f"===== KenKem phaseB combinations [{sym.upper()}] trials={n_trials} =====")
    summary = []
    for name, active in COMBOS.items():
        if any(e not in frozen for e in active):
            print(f"  {name}: missing phaseA for {[e for e in active if e not in frozen]} — run phaseA first")
            continue
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
            trial.set_user_attr("ov", ov); trial.set_user_attr("r", r)
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
        write_set(os.path.join(HERE, f"best_kenkem_{name}_{sym}.set"), best_ov)
        summary.append(dict(combo=name, oos_pf=round(r["oos"]["pf"], 3), oos_net=round(r["oos"]["net"]),
                            oos_n=r["oos"]["n"], is_pf=round(r["full"]["pf"], 3), is_net=round(r["full"]["net"]),
                            te_net=round(r["te"]["net"])))
        print(f"  {name:9s}: IS pf={r['full']['pf']:.3f} net={r['full']['net']:>8.0f} | "
              f"OOS26 pf={r['oos']['pf']:.3f} net={r['oos']['net']:>8.0f} n={r['oos']['n']:>4d}")
    if summary:
        print(f"\n----- {sym.upper()} combos ranked by 2026 OOS PF -----")
        for r in sorted(summary, key=lambda r: -r["oos_pf"]):
            flag = "" if (r["oos_pf"] >= 1.0 and r["te_net"] > 0) else "  <-- fails OOS/consistency"
            print(f"  {r['combo']:9s} OOS pf={r['oos_pf']:.3f} net={r['oos_net']:>8.0f} | IS pf={r['is_pf']:.3f}{flag}")
        with open(os.path.join(HERE, f"sweep_kenkem_tuned_{sym}.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(summary[0].keys())); w.writeheader(); w.writerows(summary)


def main():
    phase = sys.argv[1] if len(sys.argv) > 1 else "phaseA"
    sym = sys.argv[2] if len(sys.argv) > 2 else "btc"
    n_trials = int(sys.argv[3]) if len(sys.argv) > 3 else (300 if phase == "phaseA" else 150)
    n_jobs = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    (phaseA if phase == "phaseA" else phaseB)(sym, n_trials, n_jobs)


if __name__ == "__main__":
    main()
