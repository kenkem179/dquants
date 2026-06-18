#!/usr/bin/env python3
"""KenKem entry-set comparison (user request 2026-06-14): which entries to keep in production.

The joint optimizer (optimize_kenkem.py) sweeps the 4 entry toggles TOGETHER with all params and
reports a single winner (this is how BTC landed on E5-only). That entangles the toggle choice with the
param plateau and hides the per-entry-set picture. This script runs a CONTROLLED experiment instead:
for each entry-set combination, FORCE the ENABLE_Ex toggles and run an INDEPENDENT Optuna search over
only the shared params + the active entries' params (so inert dimensions don't pollute the TPE search).
Each combo's winner is then re-run on 2026 bars as TRUE out-of-sample. The 2026 OOS numbers are the
production decider; the 2025 67/33 train/test split is an in-sample consistency gate.

E3 does not exist in the distilled kk::kenkem engine (only E1/E2/E4/E5), so the requested "E1&E3&E5" is
run as E1&E5 and flagged. This script only REPORTS + writes per-set .set files; promoting a new
production config is a separate, explicit step.

Usage:  python research/optimization/sweep_kenkem_entrysets.py <btc|xau> [n_trials] [n_jobs] [combos_csv]
Outputs: sweep_kenkem_entrysets_<sym>.csv + best_kenkem_<combo>_<sym>.set per combo + console table.
"""
import os, sys, csv, subprocess, tempfile
import optuna

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BIN = os.path.join(ROOT, "cpp_core", "build", "kenkem", "backtester")

SYMS = {
    "btc": dict(flag="--symbol-btc", spread=2.0,
                m1=os.path.join(ROOT, "cpp_core/tools/bars_btcusd_2025_m1.csv"),
                oos=os.path.join(ROOT, "cpp_core/tools/bars_btcusd_2026_m1.csv")),
    "xau": dict(flag="--symbol-xau", spread=0.05,
                m1=os.path.join(ROOT, "cpp_core/tools/bars_xauusd_2025_m1.csv"),
                oos=os.path.join(ROOT, "cpp_core/tools/bars_xauusd_2026_m1.csv")),
}

# (key, lo, hi, is_int, tag)  tag in {shared, e1, e2, e4, e5}
SPACE = [
    ("SIDEWAYS_BLOCK_THRESHOLD", 40, 62, True, "shared"),
    ("SIDEWAYS_WARNING_THRESHOLD", 30, 50, True, "shared"),
    ("MIN_MOMENTUM_ADX_REQUIRED", 15.0, 30.0, False, "shared"),
    ("ADX_HIGH_THRESHOLD", 22.0, 35.0, False, "shared"),
    ("SL_EMA_DISTANCE", 8, 45, True, "shared"),
    ("INPUT_EMA0_PERIOD", 6, 14, True, "shared"),
    ("INPUT_EMA1_PERIOD", 18, 40, True, "shared"),
    ("INPUT_EMA2_PERIOD", 50, 85, True, "shared"),
    ("INPUT_EMA3_PERIOD", 90, 130, True, "shared"),
    ("INPUT_EMA4_PERIOD", 150, 230, True, "shared"),
    ("ADX_LEN", 8, 20, True, "shared"),
    ("RSI_LEN", 8, 20, True, "shared"),
    # E1
    ("E1_RR", 1.2, 3.0, False, "e1"),
    ("E1_MAX_CROSS_AGE", 30, 120, True, "e1"),
    ("E1_ATR_SL_CAP_MULTIPLIER", 1.5, 4.5, False, "e1"),
    ("E1_TRAILING_SL_FACTOR", 0.2, 0.7, False, "e1"),
    ("E1_PARTIAL_TP_TRIGGER", 0.5, 0.95, False, "e1"),
    ("E1_PARTIAL_TP_RATIO", 0.15, 0.5, False, "e1"),
    ("E1_SL_TO_BREAKEVEN_BUFFER", 0.02, 0.15, False, "e1"),
    ("E1_HTF_MIN_ADX", 12.0, 30.0, False, "e1"),
    # E2
    ("E2_RR", 1.2, 3.0, False, "e2"),
    ("E2_MAX_TOUCH_AGE", 12, 60, True, "e2"),
    ("E2_ATR_SL_CAP_MULTIPLIER", 1.5, 4.0, False, "e2"),
    ("E2_TRAILING_SL_FACTOR", 0.2, 0.7, False, "e2"),
    ("E2_PARTIAL_TP_TRIGGER", 0.5, 0.95, False, "e2"),
    ("E2_PARTIAL_TP_RATIO", 0.15, 0.5, False, "e2"),
    ("E2_HTF_MIN_ADX", 12.0, 30.0, False, "e2"),
    # E4
    ("E4_RR", 1.5, 3.2, False, "e4"),
    ("E4_RR_SHORT", 1.2, 2.6, False, "e4"),
    ("E4_MAX_CROSS_AGE", 12, 50, True, "e4"),
    ("E4_ATR_SL_CAP_MULTIPLIER", 1.5, 4.5, False, "e4"),
    ("E4_TRAILING_SL_FACTOR", 0.2, 0.7, False, "e4"),
    ("E4_PARTIAL_TP_TRIGGER", 0.5, 0.95, False, "e4"),
    ("E4_PARTIAL_TP_RATIO", 0.15, 0.5, False, "e4"),
    ("E4_MIN_CLOUD_THICKNESS_ATR_MULT", 0.0, 0.3, False, "e4"),
    ("E4_HTF_MIN_ADX", 12.0, 30.0, False, "e4"),
    # E5
    ("E5_RR", 1.2, 2.5, False, "e5"),
    ("E5_MAX_EMA_CROSS_AGE", 10, 50, True, "e5"),
    ("E5_MIN_MOMENTUM_ADX", 0.0, 25.0, False, "e5"),
    ("E5_ATR_SL_CAP_MULTIPLIER", 1.5, 4.5, False, "e5"),
    ("E5_TRAILING_SL_FACTOR", 0.2, 0.7, False, "e5"),
    ("E5_PARTIAL_TP_TRIGGER", 0.2, 0.6, False, "e5"),
    ("E5_PARTIAL_TP_RATIO", 0.2, 0.6, False, "e5"),
    ("E5_HTF_MIN_ADX", 12.0, 30.0, False, "e5"),
]

ALL_ENTRIES = ["e1", "e2", "e4", "e5"]
TOGGLE = {"e1": "ENABLE_E1_ENTRIES", "e2": "ENABLE_E2_ENTRIES",
          "e4": "ENABLE_E4_ENTRIES", "e5": "ENABLE_E5_ENTRIES"}

# requested combos (+ legacy/all references). E1&E3&E5 -> E1&E5 (no E3 in engine).
COMBOS = {
    "E1":       ["e1"],
    "E2":       ["e2"],
    "E4":       ["e4"],
    "E5":       ["e5"],
    "E1_E2":    ["e1", "e2"],
    "E1_E5":    ["e1", "e5"],          # proxy for requested E1&E3&E5
    "E2_E5":    ["e2", "e5"],
    "E1_E2_E4": ["e1", "e2", "e4"],    # legacy default
    "ALL":      ["e1", "e2", "e4", "e5"],
}

MIN_TRADES = 120   # optimizer gate; low so single-entry combos aren't auto-zeroed


def write_set(path, ov):
    with open(path, "w") as f:
        f.write("; KenKem entry-set sweep\n")
        for k, v in ov.items():
            f.write(f"{k}={v}\n")


def metrics(pnls):
    if not pnls:
        return dict(n=0, net=0.0, pf=0.0, dd=0.0)
    net = sum(pnls)
    gp = sum(p for p in pnls if p > 0)
    gl = -sum(p for p in pnls if p < 0)
    peak = cum = dd = 0.0
    for p in pnls:
        cum += p
        peak = max(peak, cum)
        dd = max(dd, peak - cum)
    return dict(n=len(pnls), net=net,
                pf=(gp / gl if gl > 0 else (9.99 if gp > 0 else 0.0)), dd=dd)


def run_bars(cfg, ov, m1_path, tmp, tag):
    out_set = os.path.join(tmp, f"kk_{tag}.set")
    out_csv = os.path.join(tmp, f"kk_{tag}.csv")
    write_set(out_set, ov)
    subprocess.run([BIN, "--bars-m1", m1_path, cfg["flag"], "--spread", str(cfg["spread"]),
                    "--set", out_set, "--out", out_csv],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    rows = []
    with open(out_csv) as f:
        for r in csv.DictReader(f):
            rows.append((int(r["ts_ms"]), float(r["pnlUsd"])))
    rows.sort()
    return rows


def base_overrides(active):
    return {TOGGLE[e]: ("true" if e in active else "false") for e in ALL_ENTRIES}


def make_objective(cfg, active):
    tags = {"shared"} | set(active)
    space = [s for s in SPACE if s[4] in tags]

    def objective(trial):
        ov = base_overrides(active)
        for key, lo, hi, is_int, _ in space:
            ov[key] = trial.suggest_int(key, int(lo), int(hi)) if is_int \
                else round(trial.suggest_float(key, lo, hi), 4)
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
    n_trials = int(sys.argv[2]) if len(sys.argv) > 2 else 400
    n_jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    only = sys.argv[4].split(",") if len(sys.argv) > 4 else list(COMBOS)
    cfg = SYMS[sym]
    optuna.logging.set_verbosity(optuna.logging.WARNING)

    summary = []
    print(f"===== KenKem entry-set sweep [{sym.upper()}]  trials={n_trials} jobs={n_jobs} =====")
    for name in only:
        active = COMBOS[name]
        study = optuna.create_study(
            direction="maximize",
            sampler=optuna.samplers.TPESampler(multivariate=True, seed=7))
        study.optimize(make_objective(cfg, active), n_trials=n_trials, n_jobs=n_jobs)

        bt = study.best_trial
        if bt.value <= 0.0 or "ov" not in bt.user_attrs:
            print(f"[{sym}:{name:9s}] no valid config (best score {bt.value:.2f})")
            summary.append(dict(combo=name, valid=0))
            continue
        ov = bt.user_attrs["ov"]
        iss, tr, te = bt.user_attrs["is"], bt.user_attrs["tr"], bt.user_attrs["te"]
        with tempfile.TemporaryDirectory() as tmp:           # TRUE OOS on 2026 bars
            oos = metrics([p for _, p in run_bars(cfg, ov, cfg["oos"], tmp, f"{name}_oos")])

        write_set(os.path.join(HERE, f"best_kenkem_{name}_{sym}.set"), ov)
        summary.append(dict(
            combo=name, valid=1,
            is_n=iss["n"], is_net=round(iss["net"]), is_pf=round(iss["pf"], 3), is_dd=round(iss["dd"]),
            tr_net=round(tr["net"]), te_net=round(te["net"]), te_pf=round(te["pf"], 3),
            oos_n=oos["n"], oos_net=round(oos["net"]), oos_pf=round(oos["pf"], 3), oos_dd=round(oos["dd"])))
        print(f"[{sym}:{name:9s}] IS pf={iss['pf']:.3f} net={iss['net']:>9.0f} n={iss['n']:>4d} "
              f"dd={iss['dd']:>7.0f} te_pf={te['pf']:.3f} | "
              f"OOS26 pf={oos['pf']:.3f} net={oos['net']:>9.0f} n={oos['n']:>4d} dd={oos['dd']:>7.0f}")

    valid = [r for r in summary if r.get("valid")]
    out = os.path.join(HERE, f"sweep_kenkem_entrysets_{sym}.csv")
    if valid:
        with open(out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(valid[0].keys()))
            w.writeheader()
            w.writerows(valid)
        print(f"\n----- {sym.upper()} ranked by 2026 OOS PF (production decider) -----")
        for r in sorted(valid, key=lambda r: -r["oos_pf"]):
            flag = "" if (r["oos_pf"] >= 1.0 and r["te_net"] > 0) else "  <-- fails OOS/consistency"
            print(f"  {r['combo']:9s} OOS pf={r['oos_pf']:.3f} net={r['oos_net']:>9.0f} "
                  f"n={r['oos_n']:>4d} | IS pf={r['is_pf']:.3f}{flag}")
    print(f"\n[{sym}] summary -> {out}")


if __name__ == "__main__":
    main()
