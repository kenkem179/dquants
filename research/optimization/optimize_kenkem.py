#!/usr/bin/env python3
"""Optuna search for the distilled KenKem engine (kk::kenkem).

Param names = the real KenKem InputParams schema, so the winning .set drops into
kenkem/MQL5/Experts/KenKem/Config/. The C++ engine is lookahead-free + cost-modelled;
this search finds the plateau that lifts the untuned baseline (BTC PF~1.06 / XAU ~1.07).

Objective = full net / (1 + maxDD) with a train/test consistency bonus, guarded by a
min-trades floor and a PF>1 gate (degenerate / unprofitable trials score ~0).

Usage: python research/optimization/optimize_kenkem.py <btc|xau> [n_trials] [n_jobs]
Outputs: optuna_kenkem_<sym>.csv ; best_kenkem_<sym>.set
"""
import csv, os, subprocess, sys, tempfile
import optuna

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BIN = os.path.join(ROOT, "cpp_core", "build", "kenkem", "backtester")

SYMS = {
    "btc": dict(flag="--symbol-btc", m1=os.path.join(ROOT, "cpp_core/tools/bars_btcusd_2025_m1.csv"), spread=2.0),
    "xau": dict(flag="--symbol-xau", m1=os.path.join(ROOT, "cpp_core/tools/bars_xauusd_2025_m1.csv"), spread=0.05),
}

# (key, lo, hi, is_int)
SPACE = [
    ("SIDEWAYS_BLOCK_THRESHOLD", 40, 62, True),
    ("MIN_MOMENTUM_ADX_REQUIRED", 15.0, 30.0, False),
    ("ADX_HIGH_THRESHOLD", 22.0, 35.0, False),
    ("SL_EMA_DISTANCE", 8, 45, True),
    ("E1_RR", 1.2, 3.0, False), ("E2_RR", 1.2, 2.6, False),
    ("E4_RR", 1.5, 3.2, False), ("E4_RR_SHORT", 1.2, 2.6, False),
    ("E1_MAX_CROSS_AGE", 15, 90, True), ("E2_MAX_TOUCH_AGE", 10, 60, True), ("E4_MAX_CROSS_AGE", 8, 40, True),
    ("E1_ATR_SL_CAP_MULTIPLIER", 2.0, 5.0, False), ("E2_ATR_SL_CAP_MULTIPLIER", 2.0, 4.5, False),
    ("E4_ATR_SL_CAP_MULTIPLIER", 2.0, 5.0, False),
    ("E1_TRAILING_SL_FACTOR", 0.2, 0.7, False), ("E2_TRAILING_SL_FACTOR", 0.2, 0.7, False),
    ("E4_TRAILING_SL_FACTOR", 0.2, 0.7, False),
    ("E1_PARTIAL_TP_TRIGGER", 0.5, 0.95, False), ("E2_PARTIAL_TP_TRIGGER", 0.5, 0.95, False),
    ("E4_PARTIAL_TP_TRIGGER", 0.5, 0.95, False),
    ("E1_HTF_MIN_ADX", 15.0, 28.0, False), ("E2_HTF_MIN_ADX", 15.0, 28.0, False), ("E4_HTF_MIN_ADX", 15.0, 28.0, False),
    # E5 (SuperBros)
    ("E5_RR", 1.2, 2.6, False), ("E5_MAX_EMA_CROSS_AGE", 10, 50, True),
    ("E5_MIN_MOMENTUM_ADX", 0.0, 26.0, False), ("E5_ATR_SL_CAP_MULTIPLIER", 2.0, 5.0, False),
    ("E5_TRAILING_SL_FACTOR", 0.2, 0.7, False), ("E5_PARTIAL_TP_TRIGGER", 0.4, 0.9, False),
    ("E5_HTF_MIN_ADX", 15.0, 28.0, False),
    # indicator LENGTHS (the "textbook" values the user wants challenged). Non-overlapping ranges
    # keep the EMA stack ordered (EMA0<EMA1<EMA2<EMA3<EMA4) by construction.
    ("INPUT_EMA0_PERIOD", 6, 14, True), ("INPUT_EMA1_PERIOD", 18, 40, True),
    ("INPUT_EMA2_PERIOD", 50, 85, True), ("INPUT_EMA3_PERIOD", 90, 130, True),
    ("INPUT_EMA4_PERIOD", 150, 230, True),
    ("ADX_LEN", 8, 20, True), ("RSI_LEN", 8, 20, True),
]
TOGGLES = ["ENABLE_E1_ENTRIES", "ENABLE_E2_ENTRIES", "ENABLE_E4_ENTRIES", "ENABLE_E5_ENTRIES"]

MIN_TRADES = 400


def write_set(path, ov):
    with open(path, "w") as f:
        f.write("; KenKem distilled optimizer set\n")
        for k, v in ov.items():
            f.write(f"{k}={v}\n")


def metrics(pnls):
    if not pnls:
        return dict(n=0, net=0.0, pf=0.0, dd=0.0)
    net = sum(pnls)
    gp = sum(p for p in pnls if p > 0); gl = -sum(p for p in pnls if p < 0)
    peak = 0.0; cum = 0.0; dd = 0.0
    for p in pnls:
        cum += p; peak = max(peak, cum); dd = max(dd, peak - cum)
    return dict(n=len(pnls), net=net, pf=(gp / gl if gl > 0 else (1e9 if gp > 0 else 0.0)), dd=dd)


def run_trial(cfg, ov, tmp, tag):
    out_set = os.path.join(tmp, f"kk_{tag}.set")
    out_csv = os.path.join(tmp, f"kk_{tag}.csv")
    write_set(out_set, ov)
    subprocess.run([BIN, "--bars-m1", cfg["m1"], cfg["flag"], "--spread", str(cfg["spread"]),
                    "--set", out_set, "--out", out_csv],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    rows = []
    with open(out_csv) as f:
        for r in csv.DictReader(f):
            rows.append((int(r["ts_ms"]), float(r["pnlUsd"])))
    rows.sort()
    return rows


def make_objective(cfg, rows_out):
    def objective(trial):
        ov = {}
        for key, lo, hi, is_int in SPACE:
            ov[key] = trial.suggest_int(key, int(lo), int(hi)) if is_int \
                else round(trial.suggest_float(key, lo, hi), 4)
        for t in TOGGLES:
            ov[t] = trial.suggest_categorical(t, ["true", "false"])
        if all(ov[t] == "false" for t in TOGGLES):
            return 0.0
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
        base = full["net"] / (1.0 + full["dd"])
        score = base * (1.15 if (tr["net"] > 0 and te["net"] > 0) else 0.85)
        rows_out.append({**ov, "score": round(score, 4), "full_net": round(full["net"], 1),
                         "full_pf": round(full["pf"], 4), "full_dd": round(full["dd"], 1), "n": full["n"],
                         "train_net": round(tr["net"], 1), "test_net": round(te["net"], 1),
                         "test_pf": round(te["pf"], 4)})
        trial.set_user_attr("full_net", full["net"]); trial.set_user_attr("full_pf", full["pf"])
        trial.set_user_attr("full_dd", full["dd"]); trial.set_user_attr("n", full["n"])
        trial.set_user_attr("test_net", te["net"]); trial.set_user_attr("test_pf", te["pf"])
        return score
    return objective


def main():
    sym = sys.argv[1] if len(sys.argv) > 1 else "btc"
    n_trials = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    n_jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    cfg = SYMS[sym]
    optuna.logging.set_verbosity(optuna.logging.WARNING)
    study = optuna.create_study(direction="maximize",
                                sampler=optuna.samplers.TPESampler(multivariate=True, seed=7))
    rows = []
    study.optimize(make_objective(cfg, rows), n_trials=n_trials, n_jobs=n_jobs)

    with open(os.path.join(HERE, f"optuna_kenkem_{sym}.csv"), "w", newline="") as f:
        if rows:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)

    best = study.best_trial
    write_set(os.path.join(HERE, f"best_kenkem_{sym}.set"), best.params)
    a = best.user_attrs
    print(f"[kenkem:{sym}] BEST score={best.value:.2f} full_net={a['full_net']:.0f} "
          f"full_pf={a['full_pf']:.3f} dd={a['full_dd']:.0f} n={a['n']} "
          f"test_net={a['test_net']:.0f} test_pf={a['test_pf']:.3f}")
    print(f"  -> best_kenkem_{sym}.set")


if __name__ == "__main__":
    main()
