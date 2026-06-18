#!/usr/bin/env python3
"""KK-MasterVP Optuna sweep over the C++ tick backtester — SEPARATE per symbol.
Tunes exit/economics + regime gates AND the front-half structure params the user flagged:
local-VP length (InpVpLookback, the hardcoded 50), ATR length, near-price ATR window
(InpNodeTouchAtr), ATR%-band gates (InpMinAtrPct/InpMaxAtrPct), VA%, EMA fast/slow.

One backtest per trial over the full window; trades split by entry date into train(<SPLIT)/test.
Objective = full net/(1+maxDD) x train/test consistency bonus, with a min-trade floor.

Usage:  python research/optimization/optimize_mastervp.py <btc|xau> [n_trials] [n_jobs]
Outputs: optuna_mastervp_<sym>.csv ; best_mastervp_<sym>.set
"""
import csv, os, subprocess, sys, tempfile
import optuna

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BIN = os.path.join(ROOT, "cpp_core/build/backtester")
HERE = os.path.dirname(__file__)
T = os.path.join(ROOT, "cpp_core/tools")
SYMS = {
    "btc": dict(bars=f"{T}/bars_btcusd_2025_m3.csv", ticks=f"{T}/ticks_btcusd_2025_window.csv",
                base=f"{T}/btc_ref_run.set", flag="--symbol-btc", trade_from=1754870400000),
    "xau": dict(bars=f"{T}/bars_xauusd_2025_m3.csv", ticks=f"{T}/ticks_xauusd_window.csv",
                base=f"{T}/xau_ref_run.set", flag="--symbol-xau", trade_from=1754006400000),
}
SPLIT = "2025.11.01"
MIN_TRADES = 150

SPACE = [
    # exit / economics / regime (original)
    ("InpSlAtrBrk", 1.4, 3.0, False), ("InpBreakBufAtr", 0.30, 1.00, False),
    ("InpBreakMaxAtr", 4.0, 12.0, False), ("InpTp1R", 0.40, 1.50, False),
    ("InpTp1ClosePct", 0.0, 50.0, False), ("InpTrailAtrMult", 2.0, 5.0, False),
    ("InpRunnerRr", 5.0, 15.0, False), ("InpAdxTrendMin", 15.0, 30.0, False),
    ("InpDiSpreadMin", 3.0, 10.0, False),
    # front-half STRUCTURE (user-flagged: challenge the hardcoded textbook values)
    ("InpVpLookback", 30, 90, True), ("InpVpBins", 20, 50, True),
    ("InpVaPct", 60.0, 80.0, False), ("InpAtrLen", 8, 22, True),
    ("InpNodeTouchAtr", 0.02, 0.15, False),
    ("InpMinAtrPct", 0.005, 0.05, False), ("InpMaxAtrPct", 0.08, 0.30, False),
    ("InpEmaFast", 14, 40, True), ("InpEmaSlow", 120, 240, True),
]

# TRUST GUARD: the KK-MasterVP EA HARDCODES these in InputParams.mqh (not inputs) — MT5 ignores any swept
# value, so optimizing them yields a config that loses when deployed. The C++ engine refuses them too
# (config.hpp::non_input_keys). Strip them from the search space. See research/kenkem_parity/PARAM_SURFACE_AUDIT.md.
EA_LOCKED = {
    "InpAtrLen", "InpVpBins", "InpVaPct", "InpMasterMult", "InpRsiLen", "InpRsiMidline",
    "InpVpFeedMode", "InpNodeGateEnabled", "InpUsePriorBarVP", "InpBrkRequireFlow",
    "InpSfpFlowMin", "InpUseAtrPctlGate",
}
_dropped = [s[0] for s in SPACE if s[0] in EA_LOCKED]
if _dropped:
    print(f"[trust-guard] dropping EA-hardcoded params from search space: {sorted(set(_dropped))}")
SPACE = [s for s in SPACE if s[0] not in EA_LOCKED]


def main():
    sym = sys.argv[1] if len(sys.argv) > 1 else "btc"
    n_trials = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    n_jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    cfg = SYMS[sym]
    base_lines = [ln.rstrip("\n") for ln in open(cfg["base"]) if "=" in ln]

    def write_set(path, ov):
        keys = set(ov)
        with open(path, "w") as f:
            for ln in base_lines:
                if ln.split("=", 1)[0] not in keys:
                    f.write(ln + "\n")
            for k, v in ov.items():
                f.write(f"{k}={v}\n")

    def metrics(x):
        n = len(x)
        if n == 0:
            return dict(n=0, net=0.0, pf=0.0, dd=0.0)
        net = sum(x); gp = sum(t for t in x if t > 0); gl = -sum(t for t in x if t < 0)
        cum = peak = dd = 0.0
        for t in x:
            cum += t; peak = max(peak, cum); dd = max(dd, peak - cum)
        return dict(n=n, net=net, pf=(gp / gl if gl > 0 else (9.9 if gp > 0 else 0.0)), dd=dd)

    rows = []

    def objective(trial):
        ov = {}
        for key, lo, hi, is_int in SPACE:
            ov[key] = trial.suggest_int(key, int(lo), int(hi)) if is_int else round(trial.suggest_float(key, lo, hi), 4)
        if ov["InpEmaFast"] >= ov["InpEmaSlow"]:
            return -1e6
        with tempfile.TemporaryDirectory() as tmp:
            os_set = os.path.join(tmp, "s.set"); os_csv = os.path.join(tmp, "t.csv")
            write_set(os_set, ov)
            r = subprocess.run([BIN, "--bars", cfg["bars"], "--ticks", cfg["ticks"], cfg["flag"],
                                "--trade-from-ms", str(cfg["trade_from"]), "--set", os_set, "--out", os_csv],
                               cwd=ROOT, capture_output=True, text=True)
            if r.returncode != 0:
                return -1e6
            train, test = [], []
            with open(os_csv) as f:
                for row in csv.DictReader(f):
                    u = float(row["realizedUsd"])
                    (train if row["entryTimeUTC"] < SPLIT else test).append(u)
        tr, te, full = metrics(train), metrics(test), metrics(train + test)
        if full["n"] < MIN_TRADES:
            return -1e6 + full["n"]
        score = (full["net"] / (1.0 + full["dd"])) * (1.15 if (tr["net"] > 0 and te["net"] > 0) else 1.0)
        rows.append({**ov, "score": round(score, 3), "full_net": round(full["net"], 1),
                     "full_pf": round(full["pf"], 3), "full_dd": round(full["dd"], 1), "n": full["n"],
                     "test_net": round(te["net"], 1), "test_pf": round(te["pf"], 3)})
        trial.set_user_attr("full_pf", full["pf"]); trial.set_user_attr("full_net", full["net"])
        trial.set_user_attr("test_pf", te["pf"]); trial.set_user_attr("n", full["n"])
        return score

    optuna.logging.set_verbosity(optuna.logging.WARNING)
    study = optuna.create_study(direction="maximize", sampler=optuna.samplers.TPESampler(seed=42, n_startup_trials=30))
    study.optimize(objective, n_trials=n_trials, n_jobs=n_jobs)

    if rows:
        with open(os.path.join(HERE, f"optuna_mastervp_{sym}.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader()
            w.writerows(sorted(rows, key=lambda r: r["score"], reverse=True))
    b = study.best_trial
    write_set(os.path.join(HERE, f"best_mastervp_{sym}.set"), b.params)
    a = b.user_attrs
    print(f"[mastervp:{sym}] BEST score={b.value:.2f} full_pf={a['full_pf']:.3f} full_net={a['full_net']:.0f} "
          f"n={a['n']} test_pf={a['test_pf']:.3f} -> best_mastervp_{sym}.set")


if __name__ == "__main__":
    main()
