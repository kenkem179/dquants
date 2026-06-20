#!/usr/bin/env python3
"""
sweep_xrev.py — Extreme-Reversion (XRev) param sweep for KK-MasterVP.

XRev is a rare failed-breakout liquidity-sweep family (toggle OFF by default). To measure its
standalone signal quality we ISOLATE it: breakout OFF + reversion OFF + XRev ON, on top of the
locked base config for the symbol/TF. Each grid point runs TRAIN + OOS tick windows and reports
n / win% / PF / net / maxDD for both, plus a both-windows-robust flag.

NOTE: isolation OVER-counts XRev opportunity (it owns the single position slot). The realistic
incremental contribution is measured separately by enabling XRev ADDITIVE on top of the locked
base (see --additive). Use isolation to tune the filters, additive to confirm it helps + doesn't
hurt the base.

Usage (run from repo root):
  python3 research/mastervp_parity/sweep_xrev.py --symbol xau --tf m3 \
      --grid '{"InpXRevNetDeltaMin":[0.0,0.2,0.4],"InpXRevWickFrac":[0.0,0.5,1.0]}'
  python3 research/mastervp_parity/sweep_xrev.py --symbol btc --tf m3 --additive \
      --overrides '{"InpXRevNetDeltaMin":0.2,...}'
"""
import argparse, csv, itertools, json, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT = ROOT / "cpp_core/build/backtester"
START_BAL = 10000.0

# (bars, train_ticks, train_from, oos_ticks, oos_from) per symbol/tf. from=0 => file already windowed.
DATA = {
    ("xau", "m3"): ("bars_xauusd_2025_2026_m3.csv", "ticks_xau_train.csv", 1750291200000,
                    "ticks_xau_oos.csv", 1769904000000),
    ("xau", "m5"): ("bars_xauusd_2025_2026_m5.csv", "ticks_xau_train.csv", 1750291200000,
                    "ticks_xau_oos.csv", 1769904000000),
    ("btc", "m3"): ("bars_btcusd_2025_2026_m3.csv", "ticks_btcusd_2025_window.csv", 0,
                    "ticks_btcusd_2026_oos.csv", 0),
    ("btc", "m5"): ("bars_btcusd_2025_2026_m5.csv", "ticks_btcusd_2025_window.csv", 0,
                    "ticks_btcusd_2026_oos.csv", 0),
}
BASESET = {
    ("xau", "m3"): "cpp_core/tools/mastervp/kkmastervp_xau_m3_LOCKED.set",
    ("xau", "m5"): "cpp_core/tools/mastervp/kkmastervp_xau_m5_LOCKED.set",
    ("btc", "m3"): "cpp_core/tools/mastervp/monster_btc_m3_LOCKED.set",
    ("btc", "m5"): "cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set",
}

def read_base(path):
    out = []
    for line in Path(path).read_text().splitlines():
        s = line.split(";", 1)[0].strip()
        if "=" in s:
            k, v = s.split("=", 1)
            out.append((k.strip(), v.strip()))
    return out

def write_set(base_kv, overrides, isolate, path):
    d = dict(base_kv)
    if isolate:
        d["InpEnableBreakout"] = "false"
        d["InpEnableReversion"] = "false"
    d["InpEnableExtremeReversion"] = "true"
    d.update({k: str(v) for k, v in overrides.items()})
    with open(path, "w") as f:
        for k, v in d.items():
            f.write(f"{k}={v}\n")

def run_bt(set_path, bars, ticks, frm, symbol, out_csv):
    cmd = [str(BT), "--bars", str(ROOT / "cpp_core/tools" / bars),
           "--ticks", str(ROOT / "cpp_core/tools" / ticks),
           "--set-all", str(set_path), f"--symbol-{symbol}", "--out", str(out_csv)]
    if frm > 0:
        cmd += ["--trade-from-ms", str(frm)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-400:]); return None
    return out_csv

def metrics(csv_path):
    pnls, tags = [], []
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            pnls.append(float(row["realizedUsd"])); tags.append(row.get("exitTag", ""))
    n = len(pnls)
    if n == 0:
        return dict(n=0, win=0, pf=0, net=0, maxdd=0, maxdd_pct=0)
    wins = [p for p in pnls if p > 0]; gl = -sum(p for p in pnls if p <= 0); gw = sum(wins)
    eq, peak, maxdd = START_BAL, START_BAL, 0.0
    for p in pnls:
        eq += p; peak = max(peak, eq); maxdd = max(maxdd, peak - eq)
    return dict(n=n, win=100*len(wins)/n, pf=(gw/gl if gl > 0 else 999.0),
                net=sum(pnls), maxdd=maxdd, maxdd_pct=100*maxdd/peak if peak else 0)

def evaluate(base_kv, overrides, symbol, tf, isolate):
    bars, tr_t, tr_f, oo_t, oo_f = DATA[(symbol, tf)]
    with tempfile.TemporaryDirectory() as td:
        sp = Path(td) / "x.set"
        write_set(base_kv, overrides, isolate, sp)
        tr = run_bt(sp, bars, tr_t, tr_f, symbol, Path(td) / "tr.csv")
        oo = run_bt(sp, bars, oo_t, oo_f, symbol, Path(td) / "oo.csv")
        return (metrics(tr) if tr else dict(n=0), metrics(oo) if oo else dict(n=0))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbol", required=True, choices=["xau", "btc"])
    ap.add_argument("--tf", required=True, choices=["m3", "m5"])
    ap.add_argument("--grid", help='JSON {key:[values]} cartesian sweep')
    ap.add_argument("--overrides", help='JSON {key:value} single config (with --additive)')
    ap.add_argument("--base-overrides", default="{}", help='JSON {key:value} held fixed across the grid')
    ap.add_argument("--additive", action="store_true", help="keep base breakout/reversion ON (realistic)")
    ap.add_argument("--min-trades", type=int, default=20)
    args = ap.parse_args()
    base_kv = read_base(ROOT / BASESET[(args.symbol, args.tf)])
    isolate = not args.additive
    fixed = json.loads(args.base_overrides)

    if args.overrides:
        ov = {**fixed, **json.loads(args.overrides)}
        tr, oo = evaluate(base_kv, ov, args.symbol, args.tf, isolate)
        print(f"=== {args.symbol.upper()} {args.tf.upper()} {'ADDITIVE' if args.additive else 'ISOLATED'} ===")
        for w, m in [("TRAIN", tr), ("OOS", oo)]:
            print(f"  {w}: n={m['n']:4d} win={m.get('win',0):5.1f}% PF={m.get('pf',0):5.3f} "
                  f"net={m.get('net',0):+9.1f} maxDD={m.get('maxdd_pct',0):4.1f}%")
        return

    grid = json.loads(args.grid)
    keys = list(grid)
    combos = list(itertools.product(*[grid[k] for k in keys]))
    rows = []
    for combo in combos:
        ov = {**fixed, **dict(zip(keys, combo))}
        tr, oo = evaluate(base_kv, ov, args.symbol, args.tf, isolate)
        robust = (tr["n"] >= args.min_trades and oo["n"] >= args.min_trades
                  and tr.get("pf", 0) > 1.0 and oo.get("pf", 0) > 1.0)
        rows.append((ov, tr, oo, robust))
        tag = " ".join(f"{k.replace('InpXRev','')}={v}" for k, v in dict(zip(keys, combo)).items())
        print(f"[{'ROBUST' if robust else '      '}] {tag:48s} "
              f"TR n={tr['n']:3d} PF={tr.get('pf',0):5.3f} net={tr.get('net',0):+8.0f} | "
              f"OOS n={oo['n']:3d} PF={oo.get('pf',0):5.3f} net={oo.get('net',0):+8.0f}", flush=True)
    print(f"\n{sum(1 for r in rows if r[3])}/{len(rows)} combos robust (both windows PF>1, n>={args.min_trades})")

if __name__ == "__main__":
    main()
