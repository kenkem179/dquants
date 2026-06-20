#!/usr/bin/env python3
"""
wf_t3.py — generalized WALK-FORWARD reversion (T3) sweep across symbol/TF/strategy configs.

T3 = mean-reversion activation (InpEnableReversion=true, kinds 2/3). Reversion fires ONLY in the
BALANCE (non-trend) regime — the complement of the breakout path — so it is potentially ADDITIVE.
All reversion keys (InpEnableReversion/RetestAtr/BodyPctMin/RrRev/SlAtrRev) are REAL EA inputs →
shippable via .set, no recompile.

Same anti-overfit objective as wf_mastervp.py / wf_monster.py: score every candidate across SIX
disjoint folds, rank by (folds PF>1, pooled PF, worst-fold PF). T1/T2 discipline: decompose per-fold
(--show-folds) and confirm the RECENT folds before locking anything.

Configs (--config):
  xau_m5   : KK-MasterVP XAU M5 lock   (ticks_xau_full.csv, single segment, M5 bars)
  xau_m3   : KK-MasterVP XAU M3 lock   (ticks_xau_full.csv, single segment, M3 bars)
  btc_m5   : KK-MasterVP BTC M5 lock   (train+oos tick segments, M5 bars)
  btc_m3   : KK-MasterVP-Monster BTC M3 lock (train+oos tick segments, M3 bars + M1 for impulse)

Usage:
  python3 research/mastervp_parity/wf_t3.py --config xau_m5 \
      --grid '{"InpEnableReversion":["false","true"]}' --tag t3screen --show-folds
"""
import argparse, csv, itertools, json, subprocess, sys, tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BT = ROOT / "cpp_core/build/backtester"
T = ROOT / "cpp_core/tools"
START_BAL = 10000.0


def ms(y, m, d):
    return int(datetime(y, m, d, tzinfo=timezone.utc).timestamp() * 1000)


# XAU single-file folds (ticks_xau_full.csv, 2025-06-19 .. 2026-05-30) — mirror wf_mastervp.py.
XAU_FOLDS = [
    ("F1_2506", "xau", ms(2025, 6, 19), ms(2025, 8, 15)),
    ("F2_2508", "xau", ms(2025, 8, 15), ms(2025, 10, 15)),
    ("F3_2510", "xau", ms(2025, 10, 15), ms(2025, 12, 15)),
    ("F4_2512", "xau", ms(2025, 12, 15), ms(2026, 2, 15)),
    ("F5_2602", "xau", ms(2026, 2, 15), ms(2026, 4, 15)),
    ("F6_2604", "xau", ms(2026, 4, 15), 0),
]
# BTC two-segment folds — mirror wf_monster.py.
BTC_FOLDS = [
    ("F1_2508", "train", 1754870400000, 1759276800000),
    ("F2_2510", "train", 1759276800000, 0),
    ("F3_2601", "oos",   1767225600000, 1771113600000),
    ("F4_2602", "oos",   1771113600000, 1775001600000),
    ("F5_2604", "oos",   1775001600000, 1778803200000),
    ("F6_2605", "oos",   1778803200000, 0),
]

CONFIGS = {
    "xau_m5": dict(base=T/"mastervp/kkmastervp_xau_m5_LOCKED.set", flag="--symbol-xau",
                   folds=XAU_FOLDS,
                   seg={"xau": dict(bars=T/"bars_xauusd_2025_2026_m5.csv", ticks=T/"ticks_xau_full.csv")}),
    "xau_m3": dict(base=T/"mastervp/kkmastervp_xau_m3_LOCKED.set", flag="--symbol-xau",
                   folds=XAU_FOLDS,
                   seg={"xau": dict(bars=T/"bars_xauusd_2025_2026_m3.csv", ticks=T/"ticks_xau_full.csv")}),
    "btc_m5": dict(base=T/"mastervp/kkmastervp_btc_m5_LOCKED.set", flag="--symbol-btc",
                   folds=BTC_FOLDS,
                   seg={"train": dict(bars=T/"bars_btcusd_2025_m5.csv", ticks=T/"ticks_btcusd_2025_window.csv"),
                        "oos":   dict(bars=T/"bars_btcusd_2026_m5.csv", ticks=T/"ticks_btcusd_2026_oos.csv")}),
    "btc_m3": dict(base=T/"mastervp/monster_btc_m3_LOCKED.set", flag="--symbol-btc",
                   folds=BTC_FOLDS,
                   seg={"train": dict(bars=T/"bars_btcusd_2025_m3.csv", m1=T/"bars_btcusd_2025_m1.csv",
                                      ticks=T/"ticks_btcusd_2025_window.csv"),
                        "oos":   dict(bars=T/"bars_btcusd_2026_m3.csv", m1=T/"bars_btcusd_2026_m1.csv",
                                      ticks=T/"ticks_btcusd_2026_oos.csv")}),
}


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


def run_fold(cfg, set_path, fold, out_csv):
    _, seg, frm, to = fold
    s = cfg["seg"][seg]
    cmd = [str(BT), "--bars", str(s["bars"]), "--ticks", str(s["ticks"]), cfg["flag"],
           "--set-all", str(set_path), "--trade-from-ms", str(frm), "--out", str(out_csv)]
    if "m1" in s:
        cmd += ["--bars-m1", str(s["m1"])]
    if to > 0:
        cmd += ["--trade-to-ms", str(to)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-400:]); return None
    return out_csv


def read_trades(csv_path):
    pnls, reasons = [], []
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            pnls.append(float(row["realizedUsd"])); reasons.append(row.get("entryReason", ""))
    return pnls, reasons


def stats(pnls, reasons):
    n = len(pnls)
    if n == 0:
        return dict(n=0, rev=0, pf=0.0, net=0.0, maxdd_pct=0.0, win=0.0, rev_net=0.0)
    wins = [p for p in pnls if p > 0]; losses = [p for p in pnls if p <= 0]
    gw, gl = sum(wins), -sum(losses)
    eq, peak, maxdd = START_BAL, START_BAL, 0.0
    for p in pnls:
        eq += p; peak = max(peak, eq); maxdd = max(maxdd, peak - eq)
    rev = sum(1 for r in reasons if "REV" in r)
    return dict(n=n, rev=rev, win=100*len(wins)/n, pf=(gw/gl if gl > 0 else float("inf")),
                net=sum(pnls), maxdd_pct=100*maxdd/peak if peak else 0.0,
                rev_net=sum(p for p, r in zip(pnls, reasons) if "REV" in r))


def eval_combo(cfg, set_path, tmpd, idx):
    per, pool_p, pool_r = [], [], []
    for j, fold in enumerate(cfg["folds"]):
        oc = tmpd / f"c{idx}_f{j}.csv"
        if run_fold(cfg, set_path, fold, oc) is None:
            per.append(stats([], [])); continue
        pnls, reasons = read_trades(oc); per.append(stats(pnls, reasons))
        pool_p += pnls; pool_r += reasons
    pooled = stats(pool_p, pool_r)
    pfs = [f["pf"] for f in per if f["n"] > 0]
    pooled["per"] = per
    pooled["worst_pf"] = min(pfs) if pfs else 0.0
    pooled["mean_pf"] = sum(pfs)/len(pfs) if pfs else 0.0
    pooled["folds_pos"] = sum(1 for f in per if f["net"] > 0)
    pooled["folds_pf1"] = sum(1 for f in per if f["pf"] > 1.0)
    return pooled


def robust_score(m):
    return (m["folds_pf1"], round(m["pf"], 4), round(m["worst_pf"], 4))


def fmt_pooled(m):
    return (f"POOLED n={m['n']} (rev={m['rev']}) win={m['win']:.1f} PF={m['pf']:.3f} net={m['net']:,.0f} "
            f"dd={m['maxdd_pct']:.1f}% | folds+={m['folds_pos']}/6 PF>1={m['folds_pf1']}/6 "
            f"worstPF={m['worst_pf']:.3f} meanPF={m['mean_pf']:.3f} revNet={m['rev_net']:,.0f}")


def fmt_perfold(cfg, m):
    return "      " + "  ".join(f"{fold[0]}:PF{f['pf']:.2f}/n{f['n']}/r{f['rev']}/${f['net']:,.0f}"
                                for fold, f in zip(cfg["folds"], m["per"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True, choices=list(CONFIGS.keys()))
    ap.add_argument("--grid", required=True)
    ap.add_argument("--tag", default="t3")
    ap.add_argument("--max-combos", type=int, default=120)
    ap.add_argument("--show-folds", action="store_true")
    a = ap.parse_args()

    cfg = CONFIGS[a.config]
    grid = json.loads(a.grid)
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys])) if keys else [()]
    if () not in combos and keys:
        combos = [()] + combos
    if len(combos) > a.max_combos:
        sys.exit(f"grid too large: {len(combos)} > {a.max_combos}")
    base_kv = read_base(cfg["base"])
    tmpd = Path(tempfile.mkdtemp(prefix=f"wft3_{a.config}_{a.tag}_"))
    print(f"# WALK-FORWARD T3 [{a.config}/{a.tag}]: {len(combos)} combos × 6 folds over {keys or '(baseline only)'}", flush=True)
    print(f"# base={cfg['base']}", flush=True)

    rows = []
    for i, vals in enumerate(combos):
        ov = dict(zip(keys, vals))
        sp = tmpd / f"c{i}.set"
        write_set(base_kv, ov, sp)
        m = eval_combo(cfg, sp, tmpd, i)
        m["_ov"] = ov; m["_sc"] = robust_score(m)
        rows.append(m)
        tag = "BASELINE" if not ov else str(ov)
        print(f"  [{i:3d}] {tag}\n      {fmt_pooled(m)}", flush=True)
        if a.show_folds:
            print(fmt_perfold(cfg, m), flush=True)

    rows.sort(key=lambda r: r["_sc"], reverse=True)
    print(f"\n=== RANKED by robustness (folds PF>1, then pooled PF, then worst-fold PF) — {a.config}/{a.tag} ===")
    for m in rows[:12]:
        tag = "BASELINE" if not m["_ov"] else str(m["_ov"])
        print(f"  {fmt_pooled(m)}  {tag}")


if __name__ == "__main__":
    main()
