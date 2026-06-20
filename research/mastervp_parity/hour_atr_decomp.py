#!/usr/bin/env python3
"""
hour_atr_decomp.py — per-hour (and per-session) profitability decomposition for KK-MasterVP XAU M5.

T2 diagnostic: before blindly grid-searching 2^24 blocked-hour combos, find which BROKER hours
(UTC + InpBrokerGMTOffset, =10 for the M5 lock) are net-negative — AND whether that is consistent
across the 6 WF folds (a dead hour that's only dead in 2025 is a regime artifact, the T1 trap).

Input: a full-file engine trades CSV (entryTimeUTC,dir,...,realizedUsd,...).
Usage: python3 research/mastervp_parity/hour_atr_decomp.py /tmp/mvp_full_baseline.csv [--gmt 10]
"""
import argparse, csv
from datetime import datetime, timezone, timedelta

# Fold boundaries (UTC) mirror wf_mastervp.py FOLDS.
FOLDS = [
    ("F1_2506", datetime(2025, 6, 19, tzinfo=timezone.utc), datetime(2025, 8, 15, tzinfo=timezone.utc)),
    ("F2_2508", datetime(2025, 8, 15, tzinfo=timezone.utc), datetime(2025, 10, 15, tzinfo=timezone.utc)),
    ("F3_2510", datetime(2025, 10, 15, tzinfo=timezone.utc), datetime(2025, 12, 15, tzinfo=timezone.utc)),
    ("F4_2512", datetime(2025, 12, 15, tzinfo=timezone.utc), datetime(2026, 2, 15, tzinfo=timezone.utc)),
    ("F5_2602", datetime(2026, 2, 15, tzinfo=timezone.utc), datetime(2026, 4, 15, tzinfo=timezone.utc)),
    ("F6_2604", datetime(2026, 4, 15, tzinfo=timezone.utc), datetime(2099, 1, 1, tzinfo=timezone.utc)),
]


def pf(pnls):
    gw = sum(p for p in pnls if p > 0); gl = -sum(p for p in pnls if p <= 0)
    return gw / gl if gl > 0 else float("inf") if gw > 0 else 0.0


def fold_of(dt):
    for name, a, b in FOLDS:
        if a <= dt < b:
            return name
    return "?"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--gmt", type=int, default=10)
    a = ap.parse_args()

    rows = []
    with open(a.csv) as f:
        for r in csv.DictReader(f):
            dt = datetime.strptime(r["entryTimeUTC"], "%Y.%m.%d %H:%M").replace(tzinfo=timezone.utc)
            fo = fold_of(dt)
            if fo == "?":   # drop pre-F1 artifact trades (ticks effectively start 2025-06-19)
                continue
            bh = (dt + timedelta(hours=a.gmt)).hour
            rows.append((dt, bh, float(r["realizedUsd"]), fo))

    print(f"# {len(rows)} trades | broker hour = UTC+{a.gmt}\n")

    # ---- by broker hour, overall ----
    print("HOUR(brk)  n     net        PF     win%   | per-fold net (F1..F6)")
    by_h = {}
    for dt, bh, p, fo in rows:
        by_h.setdefault(bh, []).append((p, fo))
    tot_neg = 0.0
    for h in range(24):
        items = by_h.get(h, [])
        if not items:
            continue
        pnls = [p for p, _ in items]
        net = sum(pnls); wins = sum(1 for p in pnls if p > 0)
        ffn = []
        for fn, _, _ in FOLDS:
            fp = [p for p, fo in items if fo == fn]
            ffn.append(f"{sum(fp):>6.0f}" if fp else "     .")
        flag = " <== NEG" if net < 0 else ""
        if net < 0:
            tot_neg += net
        print(f"  {h:02d}     {len(pnls):>4} {net:>9.0f}  {pf(pnls):>5.2f}  {100*wins/len(pnls):>5.1f}  | "
              + " ".join(ffn) + flag)

    print(f"\nSum of all net-negative broker hours: {tot_neg:,.0f}")

    # ---- consistency: which hours are negative in MOST folds (regime-robust dead hours) ----
    print("\nHOUR  folds-with-trades  folds-NEGATIVE  (robust dead = negative in >=4 folds w/ trades)")
    for h in range(24):
        items = by_h.get(h, [])
        if not items:
            continue
        fneg = ftot = 0
        for fn, _, _ in FOLDS:
            fp = [p for p, fo in items if fo == fn]
            if fp:
                ftot += 1
                if sum(fp) < 0:
                    fneg += 1
        mark = " <== ROBUST DEAD" if ftot >= 4 and fneg >= 4 else (" <== mostly neg" if fneg >= ftot - 1 and ftot >= 3 else "")
        print(f"  {h:02d}        {ftot}/6              {fneg}/{ftot}{mark}")


if __name__ == "__main__":
    main()
