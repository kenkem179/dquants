#!/usr/bin/env python3
"""
sweep.py — grid/param sweep harness for the Pine-faithful KK-MasterVP engine.

Runs the C++ backtester over a cartesian grid of .set overrides on the TRAIN tick window,
parses each trades CSV, and ranks combos by a robust objective (Calmar-like net/maxDD, gated
by a min-trade floor and PF>1). Designed for the S1-S6 sweeps; the winner is then re-validated
on the held-out OOS window before locking.

Metrics per run (from the engine trades CSV — realizedUsd already reflects 2%/acct compounding):
  n, win%, PF, net, maxDD%, TP2% (runner reached target), Calmar = net / maxDD$.

Usage:
  python3 sweep.py --grid '{"InpBreakBufAtr":[0.4,0.5,0.65],"InpSlAtrBrk":[1.2,1.48,1.8]}' \
      --base cpp_core/tools/mastervp/pine_faithful_xau.set --tag s1_entry
  (run from repo root; honors --bars/--ticks/--from defaults for the train window)
"""
import argparse, csv, itertools, json, os, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT = ROOT / "cpp_core/build/backtester"
DEF_BARS = ROOT / "cpp_core/tools/bars_xauusd_2025_2026_m3.csv"
DEF_TRAIN = ROOT / "cpp_core/tools/ticks_xau_train.csv"
DEF_OOS = ROOT / "cpp_core/tools/ticks_xau_oos.csv"
TRAIN_FROM = 1750291200000   # 2025-06-19
OOS_FROM = 1769904000000     # 2026-02-01
START_BAL = 10000.0

def read_base(path):
    """Return list of (key,val) lines from the base .set (comments/blanks dropped)."""
    out = []
    for line in Path(path).read_text().splitlines():
        s = line.split(";", 1)[0].strip()
        if "=" in s:
            k, v = s.split("=", 1)
            out.append((k.strip(), v.strip()))
    return out

def write_set(base_kv, overrides, path):
    d = dict(base_kv)
    d.update({k: str(v) for k, v in overrides.items()})
    with open(path, "w") as f:
        for k, v in d.items():
            f.write(f"{k}={v}\n")

def run_bt(set_path, ticks, frm, out_csv):
    cmd = [str(BT), "--bars", str(DEF_BARS), "--ticks", str(ticks),
           "--set-all", str(set_path), "--symbol-xau", "--trade-from-ms", str(frm),
           "--out", str(out_csv)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-500:])
        return None
    return out_csv

def metrics(csv_path):
    pnls, tags = [], []
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            pnls.append(float(row["realizedUsd"])); tags.append(row["exitTag"])
    n = len(pnls)
    if n == 0:
        return dict(n=0)
    wins = [p for p in pnls if p > 0]; losses = [p for p in pnls if p <= 0]
    gw, gl = sum(wins), -sum(losses)
    # equity curve (compounded; realizedUsd already sized off running balance)
    eq, peak, maxdd = START_BAL, START_BAL, 0.0
    for p in pnls:
        eq += p; peak = max(peak, eq); maxdd = max(maxdd, peak - eq)
    return dict(n=n, win=100*len(wins)/n, pf=(gw/gl if gl > 0 else float("inf")),
                net=sum(pnls), maxdd=maxdd, maxdd_pct=100*maxdd/peak if peak else 0,
                tp2=100*sum(1 for t in tags if t == "TP")/n,
                calmar=(sum(pnls)/maxdd if maxdd > 0 else float("inf")))

def score(m, min_trades):
    if m.get("n", 0) < min_trades or m.get("pf", 0) <= 1.0:
        return -1e9
    return m["calmar"]   # net/maxDD$ — robust risk-adjusted; plateau picked by inspection

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--grid", required=True, help='JSON {key:[values]}')
    ap.add_argument("--base", default=str(ROOT / "cpp_core/tools/mastervp/pine_faithful_xau.set"))
    ap.add_argument("--tag", default="sweep")
    ap.add_argument("--min-trades", type=int, default=150)
    ap.add_argument("--ticks", default=str(DEF_TRAIN))
    ap.add_argument("--from-ms", type=int, default=TRAIN_FROM)
    ap.add_argument("--max-combos", type=int, default=200)
    a = ap.parse_args()

    grid = json.loads(a.grid)
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys]))
    if len(combos) > a.max_combos:
        sys.exit(f"grid too large: {len(combos)} > {a.max_combos}")
    base_kv = read_base(a.base)
    tmpd = Path(tempfile.mkdtemp(prefix=f"mvp_{a.tag}_"))
    print(f"# sweep {a.tag}: {len(combos)} combos over {keys}  (ticks={Path(a.ticks).name})", flush=True)

    rows = []
    for i, vals in enumerate(combos):
        ov = dict(zip(keys, vals))
        sp = tmpd / f"c{i}.set"; oc = tmpd / f"t{i}.csv"
        write_set(base_kv, ov, sp)
        if run_bt(sp, a.ticks, a.from_ms, oc) is None:
            print(f"  [{i}] FAILED {ov}", flush=True); continue
        m = metrics(oc); m["_ov"] = ov; m["_sc"] = score(m, a.min_trades)
        rows.append(m)
        print(f"  [{i:3d}] {ov}  n={m.get('n',0)} win={m.get('win',0):.1f} "
              f"PF={m.get('pf',0):.3f} net={m.get('net',0):,.0f} dd={m.get('maxdd_pct',0):.1f}% "
              f"tp2={m.get('tp2',0):.0f}% calmar={m.get('calmar',0):.2f}", flush=True)

    rows.sort(key=lambda r: r["_sc"], reverse=True)
    print(f"\n=== TOP 10 by Calmar (net/maxDD, gated n>={a.min_trades} & PF>1) — {a.tag} ===")
    for m in rows[:10]:
        print(f"  PF={m['pf']:.3f} net={m['net']:,.0f} dd={m['maxdd_pct']:.1f}% "
              f"win={m['win']:.1f} tp2={m['tp2']:.0f}% n={m['n']} calmar={m['calmar']:.2f}  {m['_ov']}")

if __name__ == "__main__":
    main()
