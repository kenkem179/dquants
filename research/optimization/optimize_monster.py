#!/usr/bin/env python3
"""KK-MasterVP-Monster edition — exhaustive JOINT optimization over the full wired param
space (breakout + reversion + exits + regime + node + gates + sizing), on the parity-validated
C++ tick engine. Unlike the first BTC pass (9 exit/economics params), Monster:

  * ACTIVATES the dormant reversion leg (mean-revert at VA edges in balance regimes) and tunes it
    jointly with the breakout core,
  * searches regime / node-engine / volatility-gate / sizing params too,
  * toggles the optional momentum/flow filters as categorical choices.

Symbol-parameterized (btc | xau). Objective + train/test consistency + plateau/MC/walk-forward
robustness are inherited from the BTC workflow (see FINDINGS.md). Each trial = one ~5s backtest.

Usage:
  python research/optimization/optimize_monster.py <btc|xau> [n_trials] [n_jobs]
Outputs: research/optimization/optuna_monster_<sym>.csv ; best printed + written to best_monster_<sym>.set
"""
import csv
import os
import subprocess
import sys
import tempfile
import optuna

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.dirname(__file__)
BIN = os.path.join(ROOT, "cpp_core/build/backtester")

SYM = {
    "btc": dict(bars="cpp_core/tools/bars_btcusd_2025_m3.csv",
                ticks="cpp_core/tools/ticks_btcusd_2025_window.csv",
                base="cpp_core/tools/btc_ref_run.set", flag="--symbol-btc",
                trade_from=1754870400000, split="2025.11.01"),
    "xau": dict(bars="cpp_core/tools/bars_xauusd_2025_m3.csv",
                ticks="cpp_core/tools/ticks_xauusd_window.csv",
                base="cpp_core/tools/xau_ref_run.set", flag="--symbol-xau",
                trade_from=1754006400000, split="2025.11.01"),   # window Aug-Dec25: train Aug-Oct, test Nov-Dec
}

# Full joint search space: (key, low, high, is_int). Reversion is forced ON (Monster) below.
SPACE = [
    # breakout
    ("InpBreakBufAtr",  0.25, 1.00, False), ("InpBreakMaxAtr",  4.0, 12.0, False),
    ("InpSlAtrBrk",     1.4,  3.0,  False), ("InpRrBrk",        1.2,  4.0,  False),
    # reversion (activated)
    ("InpRetestAtr",    0.2,  1.0,  False), ("InpBodyPctMin",   0.2,  0.6,  False),
    ("InpRrRev",        1.0,  2.5,  False), ("InpSlAtrRev",     1.0,  2.2,  False),
    # exits
    ("InpTp1R",         0.5,  1.5,  False), ("InpTp1ClosePct",  5.0, 50.0,  False),
    ("InpBeBufAtr",     0.0,  0.30, False), ("InpTrailAtrMult", 1.6,  4.5,  False),
    ("InpRunnerRr",     4.0,  14.0, False),
    # regime
    ("InpAdxTrendMin",  16.0, 30.0, False), ("InpDiSpreadMin",  3.0, 10.0,  False),
    ("InpEmaSepAtr",    0.05, 0.50, False),
    # node engine
    ("InpNodeTouchAtr", 0.02, 0.12, False), ("InpNodeDecay",    0.88, 0.98, False),
    ("InpNodeNeutralBand", 0.05, 0.30, False),
    # volatility gate + sizing
    ("InpMinAtrPct",    0.005, 0.03, False), ("InpMaxAtrPct",   0.08, 0.30, False),
    ("InpRiskAccPct",   0.5,  2.0,  False),
]
TOGGLES = ["InpUseMomVeto", "InpBrkRequireFlow"]
FORCE = {"InpEnableReversion": "true"}   # Monster activates the reversion leg
MIN_TRADES = 200


def load_base(path):
    return [ln for ln in open(path).read().splitlines() if "=" in ln]


def write_set(path, base_lines, ov):
    keys = set(ov)
    with open(path, "w") as f:
        for ln in base_lines:
            if ln.split("=", 1)[0] not in keys:
                f.write(ln + "\n")
        for k, v in ov.items():
            f.write(f"{k}={v}\n")


def metrics(x):
    if not x:
        return dict(n=0, net=0.0, pf=0.0, dd=0.0)
    net = sum(x)
    gp = sum(t for t in x if t > 0)
    gl = -sum(t for t in x if t < 0)
    cum = pk = dd = 0.0
    for t in x:
        cum += t; pk = max(pk, cum); dd = max(dd, pk - cum)
    return dict(n=len(x), net=net, pf=(gp / gl if gl > 0 else 0.0), dd=dd)


def make_objective(cfg, base_lines, rows_out):
    def objective(trial):
        ov = dict(FORCE)
        for key, lo, hi, is_int in SPACE:
            ov[key] = trial.suggest_int(key, int(lo), int(hi)) if is_int \
                else round(trial.suggest_float(key, lo, hi), 4)
        for t in TOGGLES:
            ov[t] = trial.suggest_categorical(t, ["true", "false"])
        tmp = tempfile.gettempdir()
        out_set = os.path.join(tmp, f"mon_{cfg['flag']}_{trial.number}.set")
        out_trades = os.path.join(tmp, f"mon_{cfg['flag']}_{trial.number}.csv")
        write_set(out_set, base_lines, ov)
        r = subprocess.run([BIN, "--bars", os.path.join(ROOT, cfg["bars"]),
                            "--ticks", os.path.join(ROOT, cfg["ticks"]), "--out", out_trades,
                            "--trade-from-ms", str(cfg["trade_from"]), cfg["flag"],
                            "--set", out_set], cwd=ROOT, capture_output=True, text=True)
        train, test = [], []
        if r.returncode == 0 and os.path.exists(out_trades):
            for row in csv.DictReader(open(out_trades)):
                u = float(row["realizedUsd"])
                (train if row["entryTimeUTC"] < cfg["split"] else test).append(u)
        for p in (out_set, out_trades):
            try:
                os.remove(p)
            except OSError:
                pass
        tr, te, full = metrics(train), metrics(test), metrics(train + test)
        if full["n"] < MIN_TRADES:
            score = -1e6 + full["n"]
        else:
            base = full["net"] / (1.0 + full["dd"])
            score = base * (1.15 if (tr["net"] > 0 and te["net"] > 0) else 1.0)
        rows_out.append({**ov, "score": round(score, 4), "full_net": round(full["net"], 2),
                         "full_pf": round(full["pf"], 3), "full_dd": round(full["dd"], 2),
                         "train_net": round(tr["net"], 2), "test_net": round(te["net"], 2),
                         "test_pf": round(te["pf"], 3), "n": full["n"]})
        trial.set_user_attr("full_net", full["net"]); trial.set_user_attr("full_pf", full["pf"])
        trial.set_user_attr("test_net", te["net"]); trial.set_user_attr("test_pf", te["pf"])
        return score
    return objective


def main():
    sym = sys.argv[1] if len(sys.argv) > 1 else "btc"
    n_trials = int(sys.argv[2]) if len(sys.argv) > 2 else 400
    n_jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    cfg = SYM[sym]
    base_lines = load_base(os.path.join(ROOT, cfg["base"]))
    rows = []
    optuna.logging.set_verbosity(optuna.logging.WARNING)
    study = optuna.create_study(direction="maximize",
                                sampler=optuna.samplers.TPESampler(seed=7, n_startup_trials=60))
    study.optimize(make_objective(cfg, base_lines, rows), n_trials=n_trials, n_jobs=n_jobs)

    res = os.path.join(HERE, f"optuna_monster_{sym}.csv")
    if rows:
        cols = list(rows[0].keys())
        with open(res, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=cols); w.writeheader()
            w.writerows(sorted(rows, key=lambda r: r["score"], reverse=True))
    # write the winner's full .set
    best = study.best_trial
    ov = dict(FORCE, **best.params)
    write_set(os.path.join(HERE, f"best_monster_{sym}.set"), base_lines, ov)
    print(f"[monster:{sym}] {len(rows)} trials -> {res}")
    print(f"[monster:{sym}] BEST score={best.value:.2f} full_net={best.user_attrs['full_net']:.0f} "
          f"full_pf={best.user_attrs['full_pf']:.3f} test_net={best.user_attrs['test_net']:.0f} "
          f"test_pf={best.user_attrs['test_pf']:.3f}")


if __name__ == "__main__":
    main()
