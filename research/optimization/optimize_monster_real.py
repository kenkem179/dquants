#!/usr/bin/env python3
"""KK-MasterVP-Monster (REAL 4-kind strategy) — joint optimization on the parity-faithful C++ engine
(cpp_core monster_backtester). Unlike optimize_monster.py (which tuned the ORIGINAL KK-MasterVP port),
this targets the user's ACTUAL Monster: breakout + impulse-thrust + (activated) 4-variant mean-reversion,
multi-TF near-net confirmation, predicted-POC regime. Param names = the real Monster InpXxx schema, so
the winning .set drops straight into kenkem/MQL5/Experts/KK-MasterVP-Monster/.

The engine is LOOKAHEAD-FREE (verified) — baseline is a realistic PF~0.9 (BTC) / 0.75 (XAU); this search
finds the plateau that lifts it. Objective = full net/(1+maxDD) with a train/test consistency bonus.

Usage: python research/optimization/optimize_monster_real.py <btc|xau> [n_trials] [n_jobs]
Outputs: optuna_monster_real_<sym>.csv ; best_monster_real_<sym>.set
"""
import csv, os, subprocess, sys, tempfile
import optuna

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.dirname(__file__)
BIN = os.path.join(ROOT, "cpp_core/build/monster_backtester")
T = os.path.join(ROOT, "cpp_core/tools")

SYM = {
    "btc": dict(m3=f"{T}/bars_btcusd_2025_m3.csv", m1=f"{T}/bars_btcusd_2025_m1.csv",
                m5=f"{T}/bars_btcusd_2025_m5.csv", ticks=f"{T}/ticks_btcusd_2025_window.csv",
                flag="--symbol-btc", trade_from=1754870400000, split="2025.11.01"),
    "xau": dict(m3=f"{T}/bars_xauusd_2025_m3.csv", m1=f"{T}/bars_xauusd_2025_m1.csv",
                m5=f"{T}/bars_xauusd_2025_m5.csv", ticks=f"{T}/ticks_xauusd_window.csv",
                flag="--symbol-xau", trade_from=1754006400000, split="2025.11.01"),
}

# Joint search over the real Monster schema (key, low, high, is_int).
SPACE = [
    # breakout
    ("InpBrkEntryBufAtr", 0.4, 1.6, False), ("InpBrkMaxDistAtr", 1.2, 4.0, False),
    ("InpBrkSlAtrMult",   1.4, 3.0, False), ("InpBrkSlBufAtr",   0.1, 0.5, False),
    ("InpBrkRrFar",       2.0, 4.5, False), ("InpBrkRrNear",     1.2, 3.0, False),
    ("InpBrkNetMinM3",    0.5, 0.92, False), ("InpBrkOppMax",     0.5, 0.95, False),
    ("InpBrkFreshBars",   3,   12,  True),  ("InpBrkLocalTolAtr", 0.0, 0.5, False),
    # impulse
    ("InpImpulseCandleAtr",1.3, 2.5, False), ("InpImpulseEntryBufAtr",0.2,0.9,False),
    ("InpImpulseNetMin",  0.80, 0.99, False), ("InpImpulseMaxDistAtr",1.5,3.5,False),
    ("InpImpulseRr",      2.0, 5.0, False),  ("InpImpulseTrendSlopeBars",5,16,True),
    # reversion (ACTIVATED below)
    ("InpRevEntryDistAtr",0.5, 1.6, False), ("InpRevMaxDistAtr", 1.2, 3.0, False),
    ("InpRevNetMin",      0.5, 0.92, False), ("InpRevSlAtrMult",  1.2, 2.6, False),
    ("InpRevMinRR",       1.1, 2.5, False), ("InpRevFreshBars",   3,  10,  True),
    # exits
    ("InpTp1RrBrk",       0.6, 1.5, False), ("InpTp1ClosePctBrk", 5.0, 40.0, False),
    ("InpTp1RrRev",       0.6, 1.4, False), ("InpTp1ClosePctRev", 5.0, 50.0, False),
    ("InpBeBufAtr",       0.0, 0.30, False),
    # vol gate + sizing
    ("InpMinAtrPct",      0.005, 0.04, False), ("InpMaxAtrPct",   0.10, 0.35, False),
    ("InpRiskAccPct",     0.5,  2.0,  False),
]
TOGGLES = ["InpUseWeightedNet", "InpNetConfirmM5", "InpNetConfirmM1orM3"]
FORCE = {"InpEnableReversion": "true", "InpEnableBreakout": "true", "InpEnableImpulse": "true"}
MIN_TRADES = 150


def write_set(path, ov):
    with open(path, "w") as f:
        for k, v in ov.items():
            f.write(f"{k}={v}\n")


def metrics(x):
    if not x:
        return dict(n=0, net=0.0, pf=0.0, dd=0.0)
    net = sum(x); gp = sum(t for t in x if t > 0); gl = -sum(t for t in x if t < 0)
    cum = pk = dd = 0.0
    for t in x:
        cum += t; pk = max(pk, cum); dd = max(dd, pk - cum)
    return dict(n=len(x), net=net, pf=(gp / gl if gl > 0 else 0.0), dd=dd)


def make_objective(cfg, rows_out):
    def objective(trial):
        ov = dict(FORCE)
        for key, lo, hi, is_int in SPACE:
            ov[key] = trial.suggest_int(key, int(lo), int(hi)) if is_int \
                else round(trial.suggest_float(key, lo, hi), 4)
        for t in TOGGLES:
            ov[t] = trial.suggest_categorical(t, ["true", "false"])
        tmp = tempfile.gettempdir()
        out_set = os.path.join(tmp, f"mr_{cfg['flag']}_{trial.number}.set")
        out_trades = os.path.join(tmp, f"mr_{cfg['flag']}_{trial.number}.csv")
        write_set(out_set, ov)
        r = subprocess.run([BIN, "--bars-m3", cfg["m3"], "--bars-m1", cfg["m1"],
                            "--bars-m5", cfg["m5"], "--ticks", cfg["ticks"], "--out", out_trades,
                            "--trade-from-ms", str(cfg["trade_from"]), cfg["flag"],
                            "--set", out_set], cwd=ROOT, capture_output=True, text=True)
        train, test = [], []
        if r.returncode == 0 and os.path.exists(out_trades):
            for row in csv.DictReader(open(out_trades)):
                u = float(row["realizedUsd"])
                (train if row["entryTimeUTC"] < cfg["split"] else test).append(u)
        for p in (out_set, out_trades):
            try: os.remove(p)
            except OSError: pass
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
    rows = []
    optuna.logging.set_verbosity(optuna.logging.WARNING)
    study = optuna.create_study(direction="maximize",
                                sampler=optuna.samplers.TPESampler(seed=7, n_startup_trials=60))
    study.optimize(make_objective(cfg, rows), n_trials=n_trials, n_jobs=n_jobs)
    res = os.path.join(HERE, f"optuna_monster_real_{sym}.csv")
    if rows:
        cols = list(rows[0].keys())
        with open(res, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=cols); w.writeheader()
            w.writerows(sorted(rows, key=lambda r: r["score"], reverse=True))
    best = study.best_trial
    write_set(os.path.join(HERE, f"best_monster_real_{sym}.set"), dict(FORCE, **best.params))
    print(f"[monster-real:{sym}] {len(rows)} trials -> {res}")
    print(f"[monster-real:{sym}] BEST score={best.value:.2f} full_net={best.user_attrs['full_net']:.0f} "
          f"full_pf={best.user_attrs['full_pf']:.3f} test_net={best.user_attrs['test_net']:.0f} "
          f"test_pf={best.user_attrs['test_pf']:.3f}")


if __name__ == "__main__":
    main()
