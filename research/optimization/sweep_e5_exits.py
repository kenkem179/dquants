#!/usr/bin/env python3
"""KenKem-E5 EXIT-GEOMETRY sweep on the CANONICAL TICK engine (2026 OOS).

Root cause (SYSTEMIC.md / [[kenkem-e5-root-cause-exits]]): E5 wins ~71% but avg win ~0.3R vs avg loss
full -1R — the partial-TP/BE/chandelier machinery scratches winners while losers run to the stop, so
net is negative despite the high win rate. The bar engine HID this (synthetic OHLC walk resolves the
path-dependent partial->BE->trail favourably). This sweep fixes the geometry on the TICK engine only.

Levers (all REAL EA inputs -> portable to MQL5):
  E5_PARTIAL_TP_TRIGGER   fraction of entry->TP at which the partial fires (higher = let winners run)
  E5_PARTIAL_TP_RATIO     fraction of the lot closed at the partial (lower = bigger runner)
  E5_SL_TO_BREAKEVEN_BUFFER  where SL jumps after the partial (xR above entry)
  E5_TRAILING_SL_FACTOR   chandelier giveback (xR below high-water; higher = wider, lets winners breathe)
paired with
  E5_MAX_EMA_CROSS_AGE in {1,2,3}  (cut the late-chase over-firing; secondary amplifier of DD)

Base = research/optimization/best_kenkem_E5_<sym>.set (UPPERCASE format; the only format load_set reads).
Ranks by 2026-OOS PF. Reports the 9-column table + avg win / avg loss / ratio (the geometry signal).
Read-only on the locked .set files — adoption is a separate, manual step.

Usage: ~/miniforge3/envs/kenkem/bin/python research/optimization/sweep_e5_exits.py [btc|xau|both] [--quick]
"""
import os, sys, csv, subprocess, tempfile, itertools
from concurrent.futures import ProcessPoolExecutor
from report_metrics import full_metrics

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BIN = os.path.join(ROOT, "cpp_core", "build", "kenkem", "tick_backtester")
TOOLS = os.path.join(ROOT, "cpp_core", "tools")
FROM_MS = 1767225600000   # 2026-01-01 UTC
WARMUP = 300

SYMS = {
    "btc": dict(flag="--symbol-btc", spread=2.0, ann=365, label="BTCUSD",
                bars=os.path.join(TOOLS, "bars_btcusd_2025_2026_m1.csv"),
                ticks=os.path.join(TOOLS, "ticks_btcusd_2026_window.csv"),
                base=os.path.join(HERE, "best_kenkem_E5_btc.set")),
    "xau": dict(flag="--symbol-xau", spread=0.05, ann=252, label="XAUUSD",
                bars=os.path.join(TOOLS, "bars_xauusd_2025h2_2026_m1.csv"),
                ticks=os.path.join(TOOLS, "ticks_xauusd_2026_window.csv"),
                base=os.path.join(HERE, "best_kenkem_E5_xau.set")),
}

# Grid (full). --quick trims to the corners for a fast smoke test.
GRID = dict(
    E5_MAX_EMA_CROSS_AGE      = [1, 2, 3],
    E5_PARTIAL_TP_TRIGGER     = [0.22, 0.45, 0.70, 0.90],
    E5_PARTIAL_TP_RATIO       = [0.25, 0.476, 0.70],
    E5_SL_TO_BREAKEVEN_BUFFER = [0.0, 0.05, 0.20],
    E5_TRAILING_SL_FACTOR     = [0.435, 0.75, 1.20],
)
QUICK = dict(
    E5_MAX_EMA_CROSS_AGE      = [1, 3],
    E5_PARTIAL_TP_TRIGGER     = [0.22, 0.90],
    E5_PARTIAL_TP_RATIO       = [0.25, 0.476],
    E5_SL_TO_BREAKEVEN_BUFFER = [0.0, 0.20],
    E5_TRAILING_SL_FACTOR     = [0.435, 1.20],
)


def read_set(path):
    ov = {}
    for line in open(path):
        line = line.split(";")[0].strip()
        if "=" in line:
            k, v = line.split("=", 1)
            ov[k.strip()] = v.strip()
    return ov


def run_one(args):
    sym, base_ov, combo = args
    cfg = SYMS[sym]
    ov = dict(base_ov, **{k: str(v) for k, v in combo.items()})
    with tempfile.TemporaryDirectory() as tmp:
        st = os.path.join(tmp, "c.set")
        out = os.path.join(tmp, "c.csv")
        with open(st, "w") as f:
            for k, v in ov.items():
                f.write(f"{k}={v}\n")
        r = subprocess.run(
            [BIN, "--bars-m1", cfg["bars"], "--ticks", cfg["ticks"], cfg["flag"],
             "--spread", str(cfg["spread"]), "--set", st, "--from-ms", str(FROM_MS),
             "--warmup", str(WARMUP), "--out", out],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        rows = []
        if r.returncode == 0 and os.path.exists(out):
            for d in csv.DictReader(open(out)):
                rows.append((int(d["ts_ms"]), float(d["pnlUsd"])))
    m = full_metrics(rows, ann_days=cfg["ann"])
    wins = [p for _, p in rows if p > 0]
    losses = [p for _, p in rows if p < 0]
    m["avg_win"] = sum(wins) / len(wins) if wins else 0.0
    m["avg_loss"] = sum(losses) / len(losses) if losses else 0.0
    m["wl_ratio"] = (m["avg_win"] / -m["avg_loss"]) if losses else 0.0
    m["winpct"] = 100.0 * len(wins) / len(rows) if rows else 0.0
    return {**combo, **m}


def sweep(sym, quick):
    cfg = SYMS[sym]
    base_ov = read_set(cfg["base"])
    grid = QUICK if quick else GRID
    keys = list(grid.keys())
    combos = [dict(zip(keys, vals)) for vals in itertools.product(*[grid[k] for k in keys])]
    # baseline = the locked .set as-is (no overrides)
    tasks = [(sym, base_ov, {})] + [(sym, base_ov, c) for c in combos]
    print(f"[{sym}] {len(tasks)} runs (1 baseline + {len(combos)} grid) on TICK engine, 2026 OOS ...",
          flush=True)
    with ProcessPoolExecutor(max_workers=6) as ex:
        results = list(ex.map(run_one, tasks))

    base = results[0]
    grid_res = results[1:]
    grid_res.sort(key=lambda r: -r["pf"])

    res_csv = os.path.join(HERE, f"sweep_e5_exits_{sym}.csv")
    cols = keys + ["n", "winpct", "pf", "net", "dd", "recovery", "sharpe", "tpd",
                   "avg_win", "avg_loss", "wl_ratio"]
    with open(res_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerow({**{k: "BASE" for k in keys}, **base})
        for r in grid_res:
            w.writerow(r)

    def line(tag, r):
        return (f"  {tag:<26} n={r['n']:<4} win%={r['winpct']:5.1f} PF={r['pf']:6.3f} "
                f"net={r['net']:+9.0f} DD={r['dd']:8.0f} avgW={r['avg_win']:+7.1f} "
                f"avgL={r['avg_loss']:+7.1f} W/L={r['wl_ratio']:.2f}")
    short = lambda c: (f"age{c['E5_MAX_EMA_CROSS_AGE']} pt{c['E5_PARTIAL_TP_TRIGGER']} "
                       f"pr{c['E5_PARTIAL_TP_RATIO']} be{c['E5_SL_TO_BREAKEVEN_BUFFER']} "
                       f"tr{c['E5_TRAILING_SL_FACTOR']}")
    print(f"\n=== {cfg['label']} E5 exit-geometry sweep (2026 OOS, TICK engine) ===")
    print(line("BASELINE (locked .set)", base))
    print(f"  --- top 15 by OOS PF (of {len(grid_res)}) ---")
    for r in grid_res[:15]:
        print(line(short(r), r))
    # best risk-adjusted that also beats baseline net AND dd (the adoption rule)
    elig = [r for r in grid_res if r["net"] > base["net"] and r["dd"] < base["dd"]]
    elig.sort(key=lambda r: -r["pf"])
    print(f"  --- adoption-eligible (net>base AND DD<base): {len(elig)} ---")
    for r in elig[:8]:
        print(line(short(r), r))
    print(f"  -> {res_csv}\n", flush=True)
    return base, grid_res, elig


if __name__ == "__main__":
    which = "both"
    quick = "--quick" in sys.argv
    for a in sys.argv[1:]:
        if a in ("btc", "xau", "both"):
            which = a
    for s in (["btc", "xau"] if which == "both" else [which]):
        sweep(s, quick)
