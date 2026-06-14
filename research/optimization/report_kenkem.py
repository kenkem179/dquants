#!/usr/bin/env python3
"""Standardized 9-column performance table for KenKem configs (per-entry tuned + tuned combos).

Loads each saved .set, replays it on 2025 (IS) and 2026 (true OOS) M1 bars via the kk::kenkem
backtester, and prints the user's required 9-column table. Read-only on the .set files.

Usage: python research/optimization/report_kenkem.py [btc|xau|both]
"""
import os, sys, csv, subprocess, tempfile
from report_metrics import full_metrics, fmt_row, HEADER

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BIN = os.path.join(ROOT, "cpp_core", "build", "kenkem", "backtester")

SYMS = {
    "btc": dict(flag="--symbol-btc", spread=2.0, tf="M1", ann=365, label="BTCUSD",
                m1=os.path.join(ROOT, "cpp_core/tools/bars_btcusd_2025_m1.csv"),
                oos=os.path.join(ROOT, "cpp_core/tools/bars_btcusd_2026_m1.csv")),
    "xau": dict(flag="--symbol-xau", spread=0.05, tf="M1", ann=252, label="XAUUSD",
                m1=os.path.join(ROOT, "cpp_core/tools/bars_xauusd_2025_m1.csv"),
                oos=os.path.join(ROOT, "cpp_core/tools/bars_xauusd_2026_m1.csv")),
}

# (display name, settings string, set-file template).  {s}=sym
CONFIGS = [
    ("E1 (tuned)",       "E1 only · native trail+partial ON · ProfitManager OFF",  "best_tuned_e1_{s}.set"),
    ("E2 (tuned)",       "E2 only · native trail+partial ON · ProfitManager OFF",  "best_tuned_e2_{s}.set"),
    ("E4 (tuned)",       "E4 only · native trail+partial ON · ProfitManager OFF",  "best_tuned_e4_{s}.set"),
    ("E5 (tuned)",       "E5 only · native trail+partial ON · ProfitManager OFF",  "best_tuned_e5_{s}.set"),
    ("E1+E2",            "E1+E2 · native trail+partial ON · ProfitManager OFF",    "best_kenkem_E1_E2_{s}.set"),
    ("E1+E5",            "E1+E5 · native trail+partial ON · ProfitManager OFF",    "best_kenkem_E1_E5_{s}.set"),
    ("E2+E5",            "E2+E5 · native trail+partial ON · ProfitManager OFF",    "best_kenkem_E2_E5_{s}.set"),
    ("E1+E2+E5",         "E1+E2+E5 · native trail+partial ON · ProfitManager OFF", "best_kenkem_E1_E2_E5_{s}.set"),
    ("E4+E5",            "E4+E5 · native trail+partial ON · ProfitManager OFF",    "best_kenkem_E4_E5_{s}.set"),
]


def run(set_path, sym, bars):
    cfg = SYMS[sym]
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "r.csv")
        subprocess.run([BIN, "--bars-m1", bars, cfg["flag"], "--spread", str(cfg["spread"]),
                        "--set", set_path, "--out", out],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        rows = []
        with open(out) as f:
            for r in csv.DictReader(f):
                rows.append((int(r["ts_ms"]), float(r["pnlUsd"])))
    return full_metrics(rows, ann_days=cfg["ann"])


def report(sym):
    cfg = SYMS[sym]
    print(f"\n### KenKem — {cfg['label']} {cfg['tf']}  (IS = 2025, OOS = 2026 true out-of-sample)\n")
    for window, bars_key in (("2026 OOS", "oos"), ("2025 IS", "m1")):
        print(f"**{window}**\n")
        print(HEADER)
        results = []
        for name, settings, tmpl in CONFIGS:
            sp = os.path.join(HERE, tmpl.format(s=sym))
            if not os.path.exists(sp):
                continue
            m = run(sp, sym, cfg[bars_key])
            results.append((name, settings, m))
        # rank by OOS PF for the OOS block, keep order for IS
        if window.startswith("2026"):
            results.sort(key=lambda x: -x[2]["pf"])
        for name, settings, m in results:
            print(fmt_row(name, settings, f"{cfg['label']} {cfg['tf']}", m))
        print()


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "both"
    for s in (["btc", "xau"] if which == "both" else [which]):
        report(s)
