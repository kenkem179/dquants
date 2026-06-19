#!/usr/bin/env python3
"""sweep_e5_entry.py — E5 ENTRY-QUALITY sweep on the canonical TICK engine over the FULL parity window.

Thesis (HANDOFF 2026-06-20): the engine's whole-run net (−480) is dragged by ENTRY OVERFIRE — 235
engine-only E5 trades MT5 rejects, which net −629 (avg −2.7/trade). The matched 401 trades net +125.
So tightening E5 entry-quality gates removes the losing overfire → improves BOTH parity (fewer overfire)
AND profitability (net up) at once. The risk is that tightening also kills MATCHED trades (recall down);
this harness measures both so we adopt only knobs that cut overfire far harder than matched.

Every lever is a REAL EA input (portable to MQL5):
  E5_MAX_EMA_CROSS_AGE        cut late-chase entries (28 -> lower)
  MIN_TREND_QUALITY_E5        0-11 trend-quality floor (5 -> higher)
  E5_MIN_MOMENTUM_ADX         M1 ADX floor (18 -> higher)
  E5_HTF_MIN_ADX              HTF (M5) ADX floor (18 -> higher)
  E5_HTF_MIN_DI_SPREAD        HTF DI spread floor (4 -> higher)
  MIN_ENTRY_ATR_PERCENTILE    ATR-regime gate at execute (65 -> higher)
  E5_SIDEWAYS_BLOCK_THRESHOLD sideways-score block (50 -> lower = block more)

Reports, per combo, the 9-col profitability table PLUS parity (matched/missed/overfire/recall) and the
overfire/matched net split — so the trade-off is explicit. Read-only on the locked .set.

Modes:
  --1d      coordinate (one-knob-at-a-time) sensitivity vs baseline   [default]
  --grid    focused Cartesian product over the promising knobs (set GRID below)

Usage:
  ~/miniforge3/envs/kenkem/bin/python research/kenkem_parity/sweep_e5_entry.py [--1d|--grid] [--workers N]
"""
import os, sys, csv, subprocess, tempfile, itertools, argparse
from datetime import datetime, timedelta
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "research", "optimization"))
from diff_kk import load, match                # noqa: E402
from report_metrics import full_metrics        # noqa: E402

BIN   = os.path.join(ROOT, "cpp_core", "build", "kenkem", "tick_backtester")
TOOLS = os.path.join(ROOT, "cpp_core", "tools")
BARS  = os.path.join(TOOLS, "bars_xauusd_2024_2026_m1.csv")
TICKS = os.path.join(TOOLS, "ticks_xauusd_2024_2026.csv")
BASE  = os.path.join(HERE, "MT5_E5_ONLY.set")
MT5   = os.path.join(HERE, "mt5_runs", "RUN_2026-06-19_1.8.154_xau_2yr_E5only_cd120", "trades.csv")
SPREAD, ANN, LAG = 0.05, 252, 5.0
FMT = "%Y.%m.%d %H:%M"

# Coordinate (1-D) sensitivity grid: each knob swept alone, baseline value implicit.
ONE_D = dict(
    E5_MAX_EMA_CROSS_AGE        = [5, 10, 15, 20],
    MIN_TREND_QUALITY_E5        = [6, 7, 8, 9],
    E5_MIN_MOMENTUM_ADX         = [20, 22, 24, 26],
    E5_HTF_MIN_ADX              = [20, 22, 25],
    E5_HTF_MIN_DI_SPREAD        = [5, 6, 8],
    MIN_ENTRY_ATR_PERCENTILE    = [70, 75, 80, 85],
    E5_SIDEWAYS_BLOCK_THRESHOLD = [45, 40, 35, 30],
)
# Focused product grid (post 1-D pass: ATR-pctile is the dominant net lever; cross-age & momentum-ADX
# are the parity-preserving levers — cross them to find interactions + a robust plateau).
GRID = dict(
    MIN_ENTRY_ATR_PERCENTILE    = [65, 70, 75, 80],
    E5_MAX_EMA_CROSS_AGE        = [15, 28],
    E5_MIN_MOMENTUM_ADX         = [18, 22],
)


def read_set(path):
    ov = {}
    for line in open(path):
        line = line.split(";")[0].strip()
        if "=" in line:
            k, v = line.split("=", 1)
            ov[k.strip()] = v.strip()
    return ov


def to_ms(dt):
    return int((dt - datetime(1970, 1, 1)).total_seconds() * 1000)


def run_one(args):
    label, base_ov, combo = args
    ov = dict(base_ov, **{k: str(v) for k, v in combo.items()})
    with tempfile.TemporaryDirectory() as tmp:
        st  = os.path.join(tmp, "c.set")
        out = os.path.join(tmp, "c.csv")
        with open(st, "w") as f:
            for k, v in ov.items():
                f.write(f"{k}={v}\n")
        r = subprocess.run(
            [BIN, "--bars-m1", BARS, "--ticks", TICKS, "--symbol-xau",
             "--spread", str(SPREAD), "--set", st, "--out", out],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode != 0 or not os.path.exists(out):
            return {"label": label, **combo, "n": 0}
        eng = [e for e in load(out) if e["kind"] == "E5"]
    # whole-run profitability
    rows = [(to_ms(e["t"]), e["pnl"]) for e in eng]
    m = full_metrics(rows, ann_days=ANN)
    wins = [p for _, p in rows if p > 0]
    m["winpct"] = 100.0 * len(wins) / len(rows) if rows else 0.0
    # parity vs MT5 (same windowing as diff_kk)
    mt5 = [r for r in load(MT5) if r["kind"] == "E5"]
    if mt5:
        lo, hi = mt5[0]["t"], mt5[-1]["t"]
        engw = [e for e in eng if lo - timedelta(minutes=LAG) <= e["t"] <= hi + timedelta(minutes=LAG)]
    else:
        engw = eng
    pairs, miss, over = match(mt5, engw, LAG)
    m["matched"]  = len(pairs)
    m["missed"]   = len(miss)
    m["overfire"] = len(over)
    m["recall"]   = 100.0 * len(pairs) / len(mt5) if mt5 else 0.0
    m["over_net"] = sum(engw[j]["pnl"] for j in over)
    m["match_net"] = sum(engw[j]["pnl"] for _, j in pairs)
    return {"label": label, **combo, **m}


def line(r):
    return (f"  {r['label']:<34} n={r.get('n',0):<4} win%={r.get('winpct',0):5.1f} "
            f"PF={r.get('pf',0):6.3f} net={r.get('net',0):+8.0f} DD={r.get('dd',0):7.0f} "
            f"| match={r.get('matched',0):<3} miss={r.get('missed',0):<3} "
            f"over={r.get('overfire',0):<3} rec={r.get('recall',0):4.1f}% "
            f"oNet={r.get('over_net',0):+6.0f} mNet={r.get('match_net',0):+6.0f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--grid", action="store_true")
    ap.add_argument("--workers", type=int, default=6)
    a = ap.parse_args()
    base_ov = read_set(BASE)

    if a.grid:
        keys = list(GRID.keys())
        combos = [dict(zip(keys, vals)) for vals in itertools.product(*[GRID[k] for k in keys])]
        tasks = [("BASELINE", base_ov, {})] + [
            (" ".join(f"{k.split('_')[-1] if k.startswith('E5') else k[:6]}={v}" for k, v in c.items()), base_ov, c)
            for c in combos]
        tag = "grid"
    else:
        tasks = [("BASELINE", base_ov, {})]
        for knob, vals in ONE_D.items():
            for v in vals:
                tasks.append((f"{knob}={v}", base_ov, {knob: v}))
        tag = "1d"

    print(f"[{tag}] {len(tasks)} runs (1 baseline + {len(tasks)-1}) on TICK engine, FULL parity window ...",
          flush=True)
    with ProcessPoolExecutor(max_workers=a.workers) as ex:
        results = list(ex.map(run_one, tasks))

    base = results[0]
    rest = results[1:]
    res_csv = os.path.join(HERE, f"sweep_e5_entry_{tag}.csv")
    cols = ["label", "n", "winpct", "pf", "net", "dd", "recovery", "sharpe", "tpd",
            "matched", "missed", "overfire", "recall", "over_net", "match_net"]
    with open(res_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in results:
            w.writerow(r)

    print("\n=== XAUUSD E5 entry-quality sweep (FULL 2yr parity window, TICK engine) ===")
    print(line(base))
    print("  --- all runs, sorted by whole-run net ---")
    for r in sorted(rest, key=lambda r: -r.get("net", -1e9)):
        print(line(r))
    # adoption rule: net beats baseline AND matched recall doesn't collapse (>= 95% of baseline matched)
    floor = 0.95 * base.get("matched", 0)
    elig = [r for r in rest if r.get("net", -1e9) > base["net"] and r.get("matched", 0) >= floor]
    elig.sort(key=lambda r: -r.get("net", -1e9))
    print(f"\n  --- adoption-eligible (net>base & matched>=95% of base={floor:.0f}): {len(elig)} ---")
    for r in elig[:12]:
        print(line(r))
    print(f"  -> {res_csv}\n", flush=True)


if __name__ == "__main__":
    main()
