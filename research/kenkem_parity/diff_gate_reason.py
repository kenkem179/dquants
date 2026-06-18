#!/usr/bin/env python3
"""Join engine per-armed-bar E1 first-fail labels (GR,ts_ms,dir,label on stderr) against MT5's
kke1gate.csv (ts,dir,result,gate,detail) to localize the E1 gate over-pass.

Auto-detects the constant broker-time offset (engine UTC vs MT5 broker tz) that maximizes (ts,dir)
overlap, then prints a confusion matrix: for each MT5 first-fail gate, what did the engine decide
(and vice versa). The cell that matters: MT5=htf_trend/mtf/... where ENGINE=PASS  -> the leaking gate.
"""
import sys, csv, argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone

ap = argparse.ArgumentParser()
ap.add_argument("--engine", required=True, help="engine GR stderr file (KK_EMIT_GATE_REASON=1 2>file)")
ap.add_argument("--mt5", required=True, help="MT5 kke1gate.csv")
a = ap.parse_args()

# engine: GR,ts_ms,L|S,label  -> dict[(epoch_sec, dir)] = label
eng = {}
with open(a.engine) as f:
    for line in f:
        if not line.startswith("GR,"): continue
        _, ts_ms, d, lab = line.strip().split(",", 3)
        eng[(int(ts_ms)//1000, d)] = lab

# mt5: ts(broker str),dir,result,gate,detail -> dict[(epoch_sec_naive, dir)] = label
def mt5_label(result, gate):
    return "PASS" if result == "PASS" else gate
mt5 = {}
with open(a.mt5) as f:
    r = csv.reader(f)
    next(r)  # header
    for row in r:
        if len(row) < 4: continue
        ts, d, result, gate = row[0], row[1], row[2], row[3]
        dt = datetime.strptime(ts.strip(), "%Y.%m.%d %H:%M:%S").replace(tzinfo=timezone.utc)
        mt5[(int(dt.timestamp()), d)] = mt5_label(result, gate)

# find constant offset (seconds) maximizing overlap; broker tz is whole hours, bar shift +/-60s
eng_secs = set(k[0] for k in eng)
best = (None, -1)
for off in range(-13*3600, 13*3600 + 1, 60):   # +/-13h in 60s steps
    hit = sum(1 for (s, d) in mt5 if (s + off) in eng_secs)
    if hit > best[1]:
        best = (off, hit)
off = best[0]
print(f"best offset (mt5+off -> engine): {off:+d}s ({off/3600:+.2f}h)   overlap rows: {best[1]}")

# build confusion over the intersection
conf = defaultdict(Counter)   # conf[mt5_label][eng_label] = count
both = 0
for (s, d), ml in mt5.items():
    el = eng.get((s + off, d))
    if el is None: continue
    both += 1
    conf[ml][el] += 1
print(f"intersection (both armed & evaluated): {both}   (MT5 rows {len(mt5)}, engine rows {len(eng)})")

order = ["htf_trend","mtf","price_pos","momentum","trend_strength","trend_quality","rsi_div","PASS"]
eng_order = ["PASS","sideways","htf_trend","mtf","price_pos","trend_strength","trend_quality",
             "conviction","momentum","rsi_div"]
print("\n=== rows where MT5 BLOCKs a gate but ENGINE PASSes (the leak) ===")
leak_total = 0
for ml in order:
    if ml == "PASS": continue
    passed = conf[ml].get("PASS", 0)
    leak_total += passed
    tot = sum(conf[ml].values())
    if tot:
        print(f"  MT5={ml:<14} total={tot:<6} engine PASS={passed:<6} ({100*passed/tot:4.1f}% leak)")
print(f"  --> TOTAL engine-PASS-where-MT5-BLOCK: {leak_total}")

print("\n=== rows where ENGINE PASSes: what did MT5 say? ===")
ep = Counter()
for ml, c in conf.items():
    ep[ml] += c.get("PASS", 0)
for ml, n in ep.most_common():
    print(f"  engine PASS & MT5={ml:<14} {n}")

print("\n=== full confusion (MT5 row -> engine cols), top cells ===")
for ml in order:
    if not conf[ml]: continue
    cells = ", ".join(f"{el}:{n}" for el, n in conf[ml].most_common(4))
    print(f"  MT5={ml:<14} -> {cells}")
