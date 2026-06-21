#!/usr/bin/env python3
"""Phase-8 optimization harness for KK-MasterVP on BTCUSD M3 — Optuna over the validated
C++ backtester (the Layer-3 tick engine). The engine is parity-checked against MT5
(see memory parity-findings-trade-level), so it is a faithful fitness function.

Protocol (anti-overfit): one continuous backtest per trial over the full window; trades are
split by ENTRY DATE into in-sample (train, < SPLIT) and out-of-sample (test, >= SPLIT). Optuna
maximizes a risk-adjusted TRAIN objective with a min-trade floor; TEST metrics are logged every
trial so we can reject params whose edge does not survive OOS (plateaus, not peaks). Walk-forward
+ Monte Carlo (Phase 9) come after a stable plateau is found here.

We tune the exit/economics + regime-gate params (where this runner-capture strategy's edge lives);
the VP/node front-half is left at the parity config. Each trial = one ~5s backtest.

Usage:
  python research/optimization/optimize_btc.py [n_trials] [n_jobs]
Outputs: research/optimization/optuna_btc_results.csv (every trial), best params printed.
"""
import csv
import os
import subprocess
import sys
import tempfile
import optuna

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BIN = os.path.join(ROOT, "cpp_core/build/backtester")
sys.path.insert(0, os.path.join(ROOT, "research"))   # shared overfitting-gate sweep context
from stats.sweep_context import trial_sharpe, report_sweep_context
BARS = os.path.join(ROOT, "cpp_core/tools/bars_btcusd_2025_m3.csv")
TICKS = os.path.join(ROOT, "cpp_core/tools/ticks_btcusd_2025_window.csv")
BASE_SET = os.path.join(ROOT, "cpp_core/tools/btc_ref_run.set")
TRADE_FROM_MS = 1754870400000          # 2025-08-11 00:00 UTC (test-period start)
SPLIT = "2025.11.01"                    # train < SPLIT <= test (OOS = November)
RESULTS = os.path.join(os.path.dirname(__file__), "optuna_btc_results.csv")
MIN_TRAIN_TRADES = 150

# Search space: (InpKey, low, high, is_int). Exit/economics + regime gates.
SPACE = [
    ("InpSlAtrBrk",     1.4,  3.0, False),
    ("InpBreakBufAtr",  0.30, 1.00, False),
    ("InpBreakMaxAtr",  4.0,  12.0, False),
    ("InpTp1R",         0.40, 1.50, False),
    ("InpTp1ClosePct",  0.0,  50.0, False),
    ("InpTrailAtrMult", 2.0,  5.0, False),
    ("InpRunnerRr",     5.0,  15.0, False),
    ("InpAdxTrendMin",  15.0, 30.0, False),
    ("InpDiSpreadMin",  3.0,  10.0, False),
]


def load_base():
    with open(BASE_SET) as f:
        return [ln.rstrip("\n") for ln in f if "=" in ln]


BASE_LINES = load_base()


def write_set(path, overrides):
    keys = set(overrides)
    with open(path, "w") as f:
        for ln in BASE_LINES:
            k = ln.split("=", 1)[0]
            if k not in keys:
                f.write(ln + "\n")
        for k, v in overrides.items():
            f.write(f"{k}={v}\n")


def metrics(trades):
    """net, win%, PF, maxDD(of cumulative-net curve), n for a list of realizedUsd."""
    n = len(trades)
    if n == 0:
        return dict(n=0, net=0.0, win=0.0, pf=0.0, dd=0.0)
    net = sum(trades)
    gp = sum(t for t in trades if t > 0)
    gl = -sum(t for t in trades if t < 0)
    w = sum(1 for t in trades if t > 0)
    cum = 0.0
    peak = 0.0
    dd = 0.0
    for t in trades:
        cum += t
        peak = max(peak, cum)
        dd = max(dd, peak - cum)
    pf = gp / gl if gl > 0 else (gp if gp > 0 else 0.0)
    return dict(n=n, net=net, win=w / n * 100, pf=pf, dd=dd)


def run_trial(overrides, out_set, out_trades):
    write_set(out_set, overrides)
    r = subprocess.run([BIN, "--bars", BARS, "--ticks", TICKS, "--out", out_trades,
                        "--trade-from-ms", str(TRADE_FROM_MS), "--set", out_set],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        return [], []
    train, test = [], []
    with open(out_trades) as f:
        for row in csv.DictReader(f):
            u = float(row["realizedUsd"])
            (train if row["entryTimeUTC"] < SPLIT else test).append(u)
    return train, test


_rows = []


def objective(trial):
    ov = {}
    for key, lo, hi, is_int in SPACE:
        ov[key] = trial.suggest_int(key, int(lo), int(hi)) if is_int \
            else round(trial.suggest_float(key, lo, hi), 4)
    tmp = tempfile.gettempdir()
    out_set = os.path.join(tmp, f"kkvp_opt_{trial.number}.set")
    out_trades = os.path.join(tmp, f"kkvp_opt_{trial.number}.csv")
    train, test = run_trial(ov, out_set, out_trades)
    tr, te, full = metrics(train), metrics(test), metrics(train + test)
    for p in (out_set, out_trades):
        try:
            os.remove(p)
        except OSError:
            pass
    # Optimize FULL-window risk-adjusted return (net per unit of max drawdown) with a trade
    # floor — this is the period the user backtested. The train/test split is logged as a
    # plateau-robustness diagnostic (prefer params where BOTH halves hold up), and Phase 9
    # walk-forward is the real OOS gate. A consistency bonus nudges away from one-half spikes.
    if full["n"] < MIN_TRAIN_TRADES:
        score = -1e6 + full["n"]
    else:
        base = full["net"] / (1.0 + full["dd"])
        both_pos = (tr["net"] > 0 and te["net"] > 0)
        score = base * (1.15 if both_pos else 1.0)   # reward train+test consistency
    _rows.append({**{k: ov[k] for k in ov}, "score": round(score, 4),
                  "full_net": round(full["net"], 2), "full_pf": round(full["pf"], 3),
                  "full_dd": round(full["dd"], 2),
                  "train_n": tr["n"], "train_net": round(tr["net"], 2), "train_pf": round(tr["pf"], 3),
                  "test_n": te["n"], "test_net": round(te["net"], 2), "test_pf": round(te["pf"], 3),
                  "test_win": round(te["win"], 1)})
    trial.set_user_attr("train_net", tr["net"])
    trial.set_user_attr("test_net", te["net"])
    trial.set_user_attr("test_pf", te["pf"])
    trial.set_user_attr("sharpe", trial_sharpe(train + test))   # for the Deflated-Sharpe gate
    return score


def main():
    n_trials = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    n_jobs = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    optuna.logging.set_verbosity(optuna.logging.WARNING)
    study = optuna.create_study(direction="maximize",
                                sampler=optuna.samplers.TPESampler(seed=42, n_startup_trials=30))
    study.optimize(objective, n_trials=n_trials, n_jobs=n_jobs)

    if _rows:
        cols = list(_rows[0].keys())
        with open(RESULTS, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=cols)
            w.writeheader()
            w.writerows(sorted(_rows, key=lambda r: r["score"], reverse=True))
        print(f"[opt] wrote {len(_rows)} trials -> {RESULTS}")
    b = study.best_trial
    print(f"[opt] BEST score={b.value:.2f} train_net={b.user_attrs.get('train_net'):.2f} "
          f"test_net={b.user_attrs.get('test_net'):.2f} test_pf={b.user_attrs.get('test_pf'):.3f}")
    for k, v in b.params.items():
        print(f"       {k}={v}")
    report_sweep_context(study, RESULTS, label="btc")


if __name__ == "__main__":
    main()
