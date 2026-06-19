#!/usr/bin/env python3
"""
sweep_monster.py — grid sweep harness for KK-MasterVP-Monster (BTCUSD) on the C++ tick engine.

Inherits the faithful MasterVP base + the impulse-thrust delta. Runs the C++ backtester over a
cartesian grid of .set overrides on the TRAIN tick window, ranks by a robust Calmar objective
(net/maxDD$, gated by min-trades & PF>1), then auto-validates the top-K combos on the held-out OOS
window. Reports IMP vs BRK trade split so the impulse contribution is visible.

Usage (from repo root):
  python3 research/monster_parity/sweep_monster.py \
      --grid '{"InpBreakBufAtr":[0.4,0.65,0.9],"InpSlAtrBrk":[1.5,2.2,3.0]}' \
      --base cpp_core/tools/mastervp/monster_btc_m3.set --tag base --tf m3 --oos-validate 5
"""
import argparse, csv, itertools, json, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT = ROOT / "cpp_core/build/backtester"
T = ROOT / "cpp_core/tools"
START_BAL = 10000.0

# Per-timeframe data + windows. Train ticks: 2025-08-11..11-30; OOS: 2026-01..05.
TF = {
    "m3": dict(train_bars=T/"bars_btcusd_2025_m3.csv", oos_bars=T/"bars_btcusd_2026_m3.csv"),
    "m5": dict(train_bars=T/"bars_btcusd_2025_m5.csv", oos_bars=T/"bars_btcusd_2026_m5.csv"),
}
M1_TRAIN = T/"bars_btcusd_2025_m1.csv"
M1_OOS   = T/"bars_btcusd_2026_m1.csv"
TICKS_TRAIN = T/"ticks_btcusd_2025_window.csv"
TICKS_OOS   = T/"ticks_btcusd_2026_oos.csv"
TRAIN_FROM = 1754870400114   # 2025-08-11 (first train tick)
OOS_FROM   = 1767225605830   # 2026-01-01 (first OOS tick)

def read_base(path):
    out = []
    for line in Path(path).read_text().splitlines():
        s = line.split(";", 1)[0].strip()
        if "=" in s:
            k, v = s.split("=", 1)
            out.append((k.strip(), v.strip()))
    return out

def write_set(base_kv, overrides, path):
    d = dict(base_kv); d.update({k: str(v) for k, v in overrides.items()})
    with open(path, "w") as f:
        for k, v in d.items():
            f.write(f"{k}={v}\n")

def run_bt(set_path, bars, bars_m1, ticks, frm, out_csv):
    cmd = [str(BT), "--bars", str(bars), "--bars-m1", str(bars_m1), "--ticks", str(ticks),
           "--symbol-btc", "--set-all", str(set_path), "--trade-from-ms", str(frm),
           "--out", str(out_csv)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-400:]); return None
    return out_csv

def metrics(csv_path):
    pnls, tags, reasons = [], [], []
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            pnls.append(float(row["realizedUsd"])); tags.append(row["exitTag"])
            reasons.append(row.get("entryReason", ""))
    n = len(pnls)
    if n == 0:
        return dict(n=0, imp=0, brk=0)
    wins = [p for p in pnls if p > 0]; losses = [p for p in pnls if p <= 0]
    gw, gl = sum(wins), -sum(losses)
    eq, peak, maxdd = START_BAL, START_BAL, 0.0
    for p in pnls:
        eq += p; peak = max(peak, eq); maxdd = max(maxdd, peak - eq)
    imp = sum(1 for r in reasons if "IMP" in r)
    return dict(n=n, win=100*len(wins)/n, pf=(gw/gl if gl > 0 else float("inf")),
                net=sum(pnls), maxdd=maxdd, maxdd_pct=100*maxdd/peak if peak else 0,
                imp=imp, brk=n-imp,
                imp_net=sum(p for p, r in zip(pnls, reasons) if "IMP" in r),
                calmar=(sum(pnls)/maxdd if maxdd > 0 else float("inf")))

def score(m, min_trades):
    if m.get("n", 0) < min_trades or m.get("pf", 0) <= 1.0:
        return -1e9
    return m["calmar"]

def fmt(m):
    return (f"n={m.get('n',0)} (imp={m.get('imp',0)}) win={m.get('win',0):.1f} "
            f"PF={m.get('pf',0):.3f} net={m.get('net',0):,.0f} dd={m.get('maxdd_pct',0):.1f}% "
            f"impNet={m.get('imp_net',0):,.0f} calmar={m.get('calmar',0):.2f}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--grid", required=True)
    ap.add_argument("--base", default=str(ROOT/"cpp_core/tools/mastervp/monster_btc_m3.set"))
    ap.add_argument("--tag", default="sweep")
    ap.add_argument("--tf", default="m3", choices=list(TF))
    ap.add_argument("--min-trades", type=int, default=80)
    ap.add_argument("--max-combos", type=int, default=300)
    ap.add_argument("--oos-validate", type=int, default=0, help="validate top-K on OOS")
    a = ap.parse_args()

    cfg = TF[a.tf]
    grid = json.loads(a.grid)
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys]))
    if len(combos) > a.max_combos:
        sys.exit(f"grid too large: {len(combos)} > {a.max_combos}")
    base_kv = read_base(a.base)
    tmpd = Path(tempfile.mkdtemp(prefix=f"mon_{a.tag}_"))
    print(f"# monster sweep {a.tag} [{a.tf}]: {len(combos)} combos over {keys}", flush=True)

    rows = []
    for i, vals in enumerate(combos):
        ov = dict(zip(keys, vals))
        sp = tmpd/f"c{i}.set"; oc = tmpd/f"t{i}.csv"
        write_set(base_kv, ov, sp)
        if run_bt(sp, cfg["train_bars"], M1_TRAIN, TICKS_TRAIN, TRAIN_FROM, oc) is None:
            print(f"  [{i}] FAILED {ov}", flush=True); continue
        m = metrics(oc); m["_ov"] = ov; m["_sc"] = score(m, a.min_trades); m["_sp"] = sp
        rows.append(m)
        print(f"  [{i:3d}] {ov}  {fmt(m)}", flush=True)

    rows.sort(key=lambda r: r["_sc"], reverse=True)
    print(f"\n=== TOP 10 by Calmar (gated n>={a.min_trades} & PF>1) — {a.tag} [{a.tf}] TRAIN ===")
    for m in rows[:10]:
        print(f"  {fmt(m)}  {m['_ov']}")

    if a.oos_validate and rows:
        print(f"\n=== OOS validation of top {a.oos_validate} ===")
        for m in rows[:a.oos_validate]:
            if m["_sc"] <= -1e8:
                continue
            oc = tmpd/f"oos_{rows.index(m)}.csv"
            if run_bt(m["_sp"], cfg["oos_bars"], M1_OOS, TICKS_OOS, OOS_FROM, oc) is None:
                continue
            om = metrics(oc)
            print(f"  TRAIN[{fmt(m)}]\n    OOS[{fmt(om)}]  {m['_ov']}", flush=True)

if __name__ == "__main__":
    main()
