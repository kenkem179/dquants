#!/usr/bin/env python3
"""Cross-dataset robustness validation for KenKem strategies.

Replay ONE locked .set across MANY broker datasets (OANDA / Exness / Binance, BTCUSD/XAUUSD)
and print PF / net / maxDD / #trades per dataset, so we can confirm an edge proven on our
Exness data still holds broker-to-broker. This is the "is it still perfect everywhere" check.

Datasets must first be normalised with ingest_dataset.py (which emits the *_m1/m3/m5.csv +
*_ticks.csv the C++ engines consume). This runner just dispatches the right engine per
strategy and aggregates results — no re-optimization (that would be overfitting per broker).

Engines (all dependency-free, built by `make -C cpp_core all`):
  mastervp : build/backtester           --bars(m3) --ticks            (tick-driven)
  monster  : build/monster_backtester   --bars-m1/m3/m5 --ticks       (tick-driven)
  kenkem   : build/kenkem/backtester     --bars-m1 --spread           (bar-driven, synth spread)

Usage:
  python research/validation/cross_validate.py <mastervp|monster|kenkem> <btc|xau> \\
         <path.set> <datasets.json> [name ...]
  (no names => every dataset whose symbol matches)

Per-dataset knobs in datasets.json (all optional):
  warmup_bars   (default 300)  bars reserved for indicator convergence before trading
  kenkem_spread (default btc 2.0 / xau 0.05)  synthetic spread for the bar-driven KenKem engine
"""
import csv
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BUILD = os.path.join(ROOT, "cpp_core", "build")
DEFAULT_KENKEM_SPREAD = {"btc": 2.0, "xau": 0.05}
DEFAULT_WARMUP = 300


def metrics(pnls):
    n = len(pnls)
    if n == 0:
        return dict(n=0, net=0.0, pf=0.0, dd=0.0)
    net = sum(pnls); gp = sum(t for t in pnls if t > 0); gl = -sum(t for t in pnls if t < 0)
    cum = peak = dd = 0.0
    for t in pnls:
        cum += t; peak = max(peak, cum); dd = max(dd, peak - cum)
    return dict(n=n, net=net, pf=(gp / gl if gl > 0 else (9.9 if gp > 0 else 0.0)), dd=dd)


def read_pnls(csv_path):
    pnls = []
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            v = row.get("realizedUsd", row.get("pnlUsd"))
            if v is not None and v != "":
                pnls.append(float(v))
    return pnls


def bars_ts_at(bars_csv, idx):
    """ts_ms of the idx-th data row (0-based) in a bars CSV, for the warmup boundary."""
    with open(bars_csv) as f:
        f.readline()  # header
        for i, line in enumerate(f):
            if i == idx:
                return int(line.split(",", 1)[0])
    return 0


def run_dataset(strategy, sym, set_path, normdir, name, ds):
    flag = "--symbol-xau" if sym == "xau" else "--symbol-btc"
    warmup = int(ds.get("warmup_bars", DEFAULT_WARMUP))
    p = lambda tf: os.path.join(normdir, f"{name}_{tf}.csv")
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "t.csv")
        if strategy == "mastervp":
            tf = bars_ts_at(p("m3"), warmup)
            cmd = [f"{BUILD}/backtester", "--bars", p("m3"), "--ticks", p("ticks"),
                   flag, "--trade-from-ms", str(tf), "--set", set_path, "--out", out]
        elif strategy == "monster":
            tf = bars_ts_at(p("m1"), warmup)
            cmd = [f"{BUILD}/monster_backtester", "--bars-m1", p("m1"), "--bars-m3", p("m3"),
                   "--bars-m5", p("m5"), "--ticks", p("ticks"), flag,
                   "--trade-from-ms", str(tf), "--set", set_path, "--out", out]
        elif strategy == "kenkem":
            spread = ds.get("kenkem_spread", DEFAULT_KENKEM_SPREAD.get(sym, 0.0))
            frm = bars_ts_at(p("m1"), warmup)
            cmd = [f"{BUILD}/kenkem/backtester", "--bars-m1", p("m1"), flag,
                   "--spread", str(spread), "--warmup", str(warmup), "--from-ms", str(frm),
                   "--set", set_path, "--out", out]
        else:
            raise SystemExit(f"unknown strategy {strategy}")
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if r.returncode != 0:
            return dict(n=0, net=0.0, pf=0.0, dd=0.0, err=r.stderr.strip().splitlines()[-1:])
        return metrics(read_pnls(out))


def main():
    if len(sys.argv) < 5:
        raise SystemExit(__doc__)
    strategy, sym, set_path, spec_path = sys.argv[1:5]
    wanted = set(sys.argv[5:])
    spec = json.load(open(spec_path))
    normdir = spec.get("outdir", "data/external/normalized")
    normdir = normdir if os.path.isabs(normdir) else os.path.join(ROOT, normdir)

    rows = []
    for ds in spec["datasets"]:
        if ds["symbol"] != sym:
            continue
        if wanted and ds["name"] not in wanted:
            continue
        name = ds["name"]
        if not os.path.exists(os.path.join(normdir, f"{name}_m1.csv")):
            print(f"  ! {name}: not ingested (run ingest_dataset.py first) — skipping")
            continue
        rows.append((name, run_dataset(strategy, sym, set_path, normdir, name, ds)))

    print(f"\n=== {strategy} / {sym.upper()} / {os.path.basename(set_path)} ===")
    print(f"{'dataset':28s} {'n':>5s} {'PF':>7s} {'net':>10s} {'maxDD':>9s}")
    print("-" * 62)
    for name, m in rows:
        if m.get("err"):
            print(f"{name:28s}  ERROR: {m['err']}")
            continue
        print(f"{name:28s} {m['n']:5d} {m['pf']:7.3f} {m['net']:10.1f} {m['dd']:9.1f}")
    pfs = [m["pf"] for _, m in rows if not m.get("err") and m["n"] > 0]
    if pfs:
        print("-" * 62)
        print(f"{'CONSISTENCY':28s} {'min PF':>7s}={min(pfs):.3f}  "
              f"{'profitable':>10s}={sum(p > 1.0 for p in pfs)}/{len(pfs)} datasets")


if __name__ == "__main__":
    main()
