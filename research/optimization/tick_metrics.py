#!/usr/bin/env python3
"""9-column metrics from the kk::kenkem TICK backtester trades.csv (the validated engine; the BAR
engine is P&L-sign-unreliable — see memory bar-engine-systemic-defect). Parses entryTimeUTC + realizedUsd.

Usage: python tick_metrics.py <trades.csv> [label] [--ann 252] [--from YYYY.MM.DD] [--to YYYY.MM.DD]
"""
import sys, csv, datetime as dt
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from report_metrics import full_metrics


def load(path, dfrom=None, dto=None):
    rows = []
    for r in csv.DictReader(open(path)):
        t = dt.datetime.strptime(r["entryTimeUTC"], "%Y.%m.%d %H:%M")
        d = r["entryTimeUTC"][:10]
        if dfrom and d < dfrom:
            continue
        if dto and d > dto:
            continue
        ts_ms = int(t.replace(tzinfo=dt.timezone.utc).timestamp() * 1000)
        rows.append((ts_ms, float(r["realizedUsd"]), r.get("kind", "")))
    return rows


def main():
    a = sys.argv[1:]
    path = a[0]
    label = a[1] if len(a) > 1 and not a[1].startswith("--") else path.split("/")[-1]
    ann = 252
    dfrom = dto = None
    for i, x in enumerate(a):
        if x == "--ann":
            ann = int(a[i + 1])
        if x == "--from":
            dfrom = a[i + 1]
        if x == "--to":
            dto = a[i + 1]
    rows = load(path, dfrom, dto)
    m = full_metrics([(t, p) for t, p, _ in rows], ann_days=ann)
    print(f"{label:38s} n={m['n']:4d} net={m['net']:+9.0f} PF={m['pf']:.3f} "
          f"rec={m['recovery']:.2f} dd={m['dd']:7.0f} sharpe={m['sharpe']:.2f} tpd={m['tpd']:.2f}")
    return m


if __name__ == "__main__":
    main()
