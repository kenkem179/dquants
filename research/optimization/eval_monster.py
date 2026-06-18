#!/usr/bin/env python3
"""Evaluate a single KK-Monster .set over the C++ tick backtester for one symbol.
Prints n / net / PF / maxDD for the full window and the test split. Reusable by hand and
by the F2 sweep. Usage:
    python research/optimization/eval_monster.py <btc|xau> <path.set>
"""
import csv, os, subprocess, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BIN = os.path.join(ROOT, "cpp_core/build/monster_backtester")
T = os.path.join(ROOT, "cpp_core/tools")
SYMS = {
    "btc": dict(m3=f"{T}/bars_btcusd_2025_m3.csv", m1=f"{T}/bars_btcusd_2025_m1.csv",
                m5=f"{T}/bars_btcusd_2025_m5.csv", ticks=f"{T}/ticks_btcusd_2025_window.csv",
                flag="--symbol-btc", trade_from=1754870400000, split="2025.11.01"),
    "xau": dict(m3=f"{T}/bars_xauusd_2025_m3.csv", m1=f"{T}/bars_xauusd_2025_m1.csv",
                m5=f"{T}/bars_xauusd_2025_m5.csv", ticks=f"{T}/ticks_xauusd_window.csv",
                flag="--symbol-xau", trade_from=1754006400000, split="2025.11.01"),
}


def metrics(x):
    n = len(x)
    if n == 0:
        return dict(n=0, net=0.0, pf=0.0, dd=0.0)
    net = sum(x); gp = sum(t for t in x if t > 0); gl = -sum(t for t in x if t < 0)
    cum = peak = dd = 0.0
    for t in x:
        cum += t; peak = max(peak, cum); dd = max(dd, peak - cum)
    return dict(n=n, net=net, pf=(gp / gl if gl > 0 else (9.9 if gp > 0 else 0.0)), dd=dd)


def run(sym, set_path):
    cfg = SYMS[sym]
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "t.csv")
        r = subprocess.run([BIN, "--bars-m3", cfg["m3"], "--bars-m1", cfg["m1"],
                            "--bars-m5", cfg["m5"], "--ticks", cfg["ticks"], "--out", out,
                            "--trade-from-ms", str(cfg["trade_from"]), cfg["flag"],
                            "--set", set_path], cwd=ROOT, capture_output=True, text=True)
        if r.returncode != 0:
            raise SystemExit(f"monster backtester failed:\n{r.stderr}")
        train, test = [], []
        with open(out) as f:
            for row in csv.DictReader(f):
                u = float(row["realizedUsd"])
                (train if row["entryTimeUTC"] < cfg["split"] else test).append(u)
    return metrics(train), metrics(test), metrics(train + test)


def main():
    sym, set_path = sys.argv[1], sys.argv[2]
    tr, te, full = run(sym, set_path)
    print(f"[{sym}] {os.path.basename(set_path)}")
    for name, m in (("full", full), ("test", te)):
        print(f"  {name:5s} n={m['n']:4d} net={m['net']:9.1f} pf={m['pf']:.3f} dd={m['dd']:8.1f}")


if __name__ == "__main__":
    main()
