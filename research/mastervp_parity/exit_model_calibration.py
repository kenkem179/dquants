#!/usr/bin/env python3
"""
R6 — Exit-model calibration audit for MasterVP (XAU M5).

Quantifies where the C++ tick engine DISAGREES with MT5 on the EXIT side, using
the two post-TP-fix MT5<->engine trade-level parity runs that ship both a MT5
trade CSV and a matched-window engine trade CSV:

  mt5_runs/RUN_2026-06-20_xau_m5_parity_v2_tpfix/   (period 2026.01..2026.06, lock .set)
  mt5_runs/RUN_2026-06-20_xau_m5_T2_hourblock/      (period 2026.01..2026.06, +hour-block)

Both CSVs share an identical schema (entryTimeUTC,dir,...,mfeR,maeR,realizedUsd,exitTag).
We match trades by (entryTimeUTC, dir) with an entry-price sanity tolerance, then
decompose the realized-P&L gap by exit tag and by winner/loser, and estimate the
runner over-credit and a haircut policy.

RESEARCH-ONLY. Reads CSVs only. No engine re-run, no file writes other than stdout.

Run:  conda run -n kenkem python research/mastervp_parity/exit_model_calibration.py
"""
from __future__ import annotations
import csv
import os
from collections import defaultdict
from dataclasses import dataclass

HERE = os.path.dirname(os.path.abspath(__file__))
RUNS = os.path.join(HERE, "mt5_runs")

DATASETS = [
    # label, dir, engine_csv (0-spread = logic parity), mt5_csv
    (
        "parity_v2_tpfix (lock, 0-spread)",
        os.path.join(RUNS, "RUN_2026-06-20_xau_m5_parity_v2_tpfix"),
        "trades_cpp_xau_m5_0spread.csv",
        "trades_mt5_xau_m5.csv",
    ),
    (
        "parity_v2_tpfix (lock, +0.17 spread)",
        os.path.join(RUNS, "RUN_2026-06-20_xau_m5_parity_v2_tpfix"),
        "trades_cpp_xau_m5_extraspread017.csv",
        "trades_mt5_xau_m5.csv",
    ),
    (
        "T2_hourblock (lock+hourblk, 0-spread)",
        os.path.join(RUNS, "RUN_2026-06-20_xau_m5_T2_hourblock"),
        "trades_cpp_xau_m5_0spread.csv",
        "trades_mt5_xau_m5.csv",
    ),
    (
        "T2_hourblock (lock+hourblk, +0.17 spread)",
        os.path.join(RUNS, "RUN_2026-06-20_xau_m5_T2_hourblock"),
        "trades_cpp_xau_m5_extraspread017.csv",
        "trades_mt5_xau_m5.csv",
    ),
]


@dataclass
class Trade:
    ts: str
    dir: str
    entry: float
    mfeR: float
    maeR: float
    usd: float
    tag: str


def load(path: str) -> list[Trade]:
    out = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            try:
                out.append(
                    Trade(
                        ts=row["entryTimeUTC"],
                        dir=row["dir"],
                        entry=float(row["entry"]),
                        mfeR=float(row.get("mfeR", "nan") or "nan"),
                        maeR=float(row.get("maeR", "nan") or "nan"),
                        usd=float(row["realizedUsd"]),
                        tag=row["exitTag"],
                    )
                )
            except (KeyError, ValueError):
                continue
    return out


def match(cpp: list[Trade], mt5: list[Trade], entry_tol=2.0):
    """Match by (ts,dir); allow a small entry-price gap. Greedy, one-to-one."""
    by_key = defaultdict(list)
    for t in mt5:
        by_key[(t.ts, t.dir)].append(t)
    pairs = []
    used = set()
    for c in cpp:
        cands = by_key.get((c.ts, c.dir), [])
        best = None
        bestd = entry_tol
        for i, m in enumerate(cands):
            if id(m) in used:
                continue
            d = abs(m.entry - c.entry)
            if d <= bestd:
                bestd = d
                best = m
        if best is not None:
            used.add(id(best))
            pairs.append((c, best))
    matched_cpp = {id(p[0]) for p in pairs}
    unm_cpp = [c for c in cpp if id(c) not in matched_cpp]
    unm_mt5 = [m for m in mt5 if id(m) not in used]
    return pairs, unm_cpp, unm_mt5


def summarize(label, cpp, mt5):
    pairs, unm_cpp, unm_mt5 = match(cpp, mt5)
    print("=" * 78)
    print(label)
    print("-" * 78)
    net_c = sum(t.usd for t in cpp)
    net_m = sum(t.usd for t in mt5)
    print(f"  trades       engine={len(cpp):4d}   mt5={len(mt5):4d}   matched={len(pairs)}")
    print(f"  unmatched    engine-only={len(unm_cpp)}   mt5-only={len(unm_mt5)}")
    print(f"  FULL net     engine={net_c:10.2f}   mt5={net_m:10.2f}   "
          f"Δ={net_c-net_m:+9.2f}  ({(net_c/net_m-1)*100 if net_m else 0:+.1f}%)")

    # matched-only nets
    mc = sum(c.usd for c, _ in pairs)
    mm = sum(m.usd for _, m in pairs)
    print(f"  MATCHED net  engine={mc:10.2f}   mt5={mm:10.2f}   "
          f"Δ={mc-mm:+9.2f}  ({(mc/mm-1)*100 if mm else 0:+.1f}%)")

    # decompose matched gap by exit-tag (engine's tag)
    print("\n  matched-pair realized-USD gap by engine exit tag:")
    print("    tag        n     eng_sum    mt5_sum     Δsum    Δ/trade")
    buckets = defaultdict(lambda: [0, 0.0, 0.0])
    for c, m in pairs:
        b = buckets[c.tag]
        b[0] += 1
        b[1] += c.usd
        b[2] += m.usd
    for tag in sorted(buckets):
        n, es, ms = buckets[tag]
        print(f"    {tag:9s} {n:4d}  {es:9.1f}  {ms:9.1f}  {es-ms:+8.1f}  {(es-ms)/n:+7.2f}")

    # winners vs losers (by engine sign) — runner over-credit lives in winners
    win = [(c, m) for c, m in pairs if c.usd > 0]
    los = [(c, m) for c, m in pairs if c.usd <= 0]
    we, wm = sum(c.usd for c, _ in win), sum(m.usd for _, m in win)
    le, lm = sum(c.usd for c, _ in los), sum(m.usd for _, m in los)
    print("\n  winner/loser split (engine sign):")
    print(f"    engine-WINNERS n={len(win):4d}  eng_sum={we:9.1f}  mt5_sum={wm:9.1f}  "
          f"Δ={we-wm:+8.1f}  (engine over-credit if >0)")
    print(f"    engine-LOSERS  n={len(los):4d}  eng_sum={le:9.1f}  mt5_sum={lm:9.1f}  "
          f"Δ={le-lm:+8.1f}")
    if we:
        print(f"    >>> winner over-credit = {(we-wm):+.1f} USD = "
              f"{(we-wm)/we*100:+.1f}% of engine winner gross")

    # exit-tag flips
    flips = sum(1 for c, m in pairs if c.tag != m.tag)
    print(f"\n  exit-tag flips: {flips}/{len(pairs)} = {flips/len(pairs)*100:.1f}%")
    flipmat = defaultdict(int)
    for c, m in pairs:
        if c.tag != m.tag:
            flipmat[(c.tag, m.tag)] += 1
    for (ct, mt), n in sorted(flipmat.items(), key=lambda x: -x[1]):
        print(f"      eng={ct:9s} -> mt5={mt:9s}  : {n}")

    # mfeR/maeR realism on matched winners (path metric, less biased than net)
    dmfe = [c.mfeR - m.mfeR for c, m in pairs
            if c.mfeR == c.mfeR and m.mfeR == m.mfeR]
    if dmfe:
        dmfe.sort()
        print(f"\n  matched mfeR diff (engine-mt5): mean={sum(dmfe)/len(dmfe):+.3f}  "
              f"median={dmfe[len(dmfe)//2]:+.3f}  n={len(dmfe)}")
    return {
        "label": label, "net_c": net_c, "net_m": net_m,
        "matched_c": mc, "matched_m": mm,
        "win_over": we - wm, "win_gross": we, "n_pairs": len(pairs),
    }


def main():
    rows = []
    for label, d, cpp_f, mt5_f in DATASETS:
        cpp = load(os.path.join(d, cpp_f))
        mt5 = load(os.path.join(d, mt5_f))
        rows.append(summarize(label, cpp, mt5))

    print("=" * 78)
    print("HAIRCUT SYNTHESIS (matched-pair winner over-credit, the runner bias)")
    print("-" * 78)
    print(f"  {'dataset':46s} {'win_over':>9s} {'%winGross':>9s}")
    for r in rows:
        pct = r["win_over"] / r["win_gross"] * 100 if r["win_gross"] else 0
        print(f"  {r['label']:46s} {r['win_over']:9.1f} {pct:8.1f}%")
    print("-" * 78)
    # aggregate the 0-spread (logic-only) datasets for the headline haircut
    logic = [r for r in rows if "0-spread" in r["label"]]
    if logic:
        tot_over = sum(r["win_over"] for r in logic)
        tot_gross = sum(r["win_gross"] for r in logic)
        tot_net_c = sum(r["matched_c"] for r in logic)
        tot_net_m = sum(r["matched_m"] for r in logic)
        print(f"  0-spread logic-parity aggregate:")
        print(f"    winner over-credit = {tot_over:+.1f} USD "
              f"= {tot_over/tot_gross*100:+.1f}% of engine winner gross")
        print(f"    matched net: engine={tot_net_c:.1f} mt5={tot_net_m:.1f} "
              f"= engine {(tot_net_c/tot_net_m-1)*100:+.1f}% rich")


if __name__ == "__main__":
    main()
