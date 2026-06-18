#!/usr/bin/env python3
"""Reconstruct the original KenKemExpert executed-trade ledger from the MT5 tester journal.

Input : winrun.log  (the KenKemExpert.ex5 run section, de-nulled, extracted from the 20260615.log
        journal via:  LC_ALL=C tail -n +<start> 20260615.log | LC_ALL=C tr -d '\\000' > winrun.log)
Output: ground_truth_ledger.csv  (156 executed trades; E1=86, E2=70)

Pairs each ENTERING line (entry type/dir/price/SL/TP/RR) to its close (exit reason + PnL) via the
ALERT ticket emitted at the same timestamp. Validated against the MT5 report (net ~+1969 after costs,
45.95% win rate).
"""
import re, csv, os

WORK = os.path.dirname(os.path.abspath(__file__))
lines = open(f"{WORK}/winrun.log", encoding="latin1").read().splitlines()

ent_re = re.compile(
    r'(\d{4}\.\d\d\.\d\d \d\d:\d\d:\d\d)\s+ENTERING:[^|]*\|[^|]*\|\s*([LS])-(E\d)\s*\|\s*'
    r'Entry:\s*([\d.]+)\s*\|\s*SL:\s*([\d.]+)\s*\|\s*TP:\s*([\d.]+)\s*\|\s*Lot:\s*([\d.]+)\s*\|\s*'
    r'Risk:\s*([\d.]+)\s*pips\s*\|\s*Reward:\s*([\d.]+)\s*pips\s*\|\s*RR:\s*([\d.]+)')
alert_re = re.compile(r'(\d{4}\.\d\d\.\d\d \d\d:\d\d:\d\d)\s+ALERT:[^#]*#(\d+) at ([\d.]+)')
close_re = re.compile(
    r'(\d{4}\.\d\d\.\d\d \d\d:\d\d:\d\d)\s+Position #\d+\s+([LS])-(E\d)\s+#(\d+)\s+'
    r'closed by ([^()]+?)(?:\s*\(| PnL:)\s*.*?PnL:\s*(-?[\d.]+)')

entries = [m for m in (ent_re.search(l) for l in lines) if m]
alerts  = [m for m in (alert_re.search(l) for l in lines) if m]
closes  = {m.group(4): m for m in (close_re.search(l) for l in lines) if m}

rows, used = [], set()
for e in entries:
    t, d, et = e.group(1), e.group(2), e.group(3)
    entry = float(e.group(4))
    tk = None
    for a in alerts:
        if a.group(2) in used:
            continue
        if a.group(1) == t and abs(float(a.group(3)) - entry) < 0.5:
            tk = a.group(2); used.add(tk); break
    c = closes.get(tk)
    rows.append(dict(entry_time=t, dir=d, et=et, entry=entry, sl=float(e.group(5)),
                     tp=float(e.group(6)), lot=float(e.group(7)), rr=float(e.group(10)),
                     ticket=tk or '', exit_time=c.group(1) if c else '',
                     exit_reason=c.group(5).strip() if c else 'OPEN/UNMATCHED',
                     pnl=float(c.group(6)) if c else ''))

with open(f"{WORK}/ground_truth_ledger.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)

matched = [r for r in rows if r['pnl'] != '']
print(f"entries={len(rows)} matched_exit={len(matched)} "
      f"wins={sum(1 for r in matched if r['pnl'] > 0)} sum_pnl={sum(r['pnl'] for r in matched):.2f}")
