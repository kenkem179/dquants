#!/usr/bin/env python3
"""Convention-aware trade parity diff: dquants monster/mastervp trades vs MT5 ref trades.

Handles the two known logging-convention differences so the JOIN reflects real parity:
  1. dquants logs the FILL bar time (signal bar + 1) with a :SS suffix; the MT5 journal logs
     the SIGNAL bar time at minute resolution. We shift cpp back by --bar-min and drop seconds.
  2. exit-tag vocab differs: cpp {SL,BE,TP2,...} vs ref {SL-LOSS,SL-WIN,TP}. We fold both into
     families {TP, SLWIN (stop in profit / BE), SLLOSS} for an apples-to-apples exit comparison.

Reports matched/missed/extra (by signal-minute + dir), entry & riskPrice deltas on matched trades,
and an exit-family confusion matrix (the executor's fingerprint). $ is NOT compared (sizing config
may differ); riskPrice (=|entry-sl|) and exit family isolate the executor logic from sizing.

Usage: diff_aligned.py <cpp_trades.csv> <ref_trades.csv> [--bar-min N] [--tol-min M]
"""
import sys, csv
from datetime import datetime, timedelta

def parse_args():
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    kw = {}
    for i, x in enumerate(sys.argv):
        if x == "--bar-min": kw["bar"] = int(sys.argv[i+1])
        if x == "--tol-min": kw["tol"] = int(sys.argv[i+1])
    return a[0], a[1], kw.get("bar", 3), kw.get("tol", 1)

def parse_ts(s):
    s = s.strip()
    fmt = "%Y.%m.%d %H:%M:%S" if s.count(":") == 2 else "%Y.%m.%d %H:%M"
    return datetime.strptime(s, fmt)

def fam(tag, pnl):
    t = tag.upper()
    if "TP" in t: return "TP"
    if "BE" in t: return "SLWIN"
    if "WIN" in t: return "SLWIN"
    if "LOSS" in t: return "SLLOSS"
    if t == "SL": return "SLWIN" if pnl > 0 else "SLLOSS"
    return t

def load(path, shift_min):
    rows = {}
    with open(path) as f:
        for r in csv.DictReader(f):
            t = parse_ts(r["entryTimeUTC"]) - timedelta(minutes=shift_min)
            key = (t.strftime("%Y.%m.%d %H:%M"), r["dir"])
            sl = float(r.get("sl", "nan")) if r.get("sl") not in (None, "") else None
            entry = float(r["entry"])
            risk = float(r["riskPrice"]) if r.get("riskPrice") else (abs(entry - sl) if sl is not None else None)
            rows[key] = dict(entry=entry, risk=risk, pnl=float(r["realizedUsd"]),
                             fam=fam(r["exitTag"], float(r["realizedUsd"])), raw=r)
    return rows

def main():
    cpp_p, ref_p, bar, tol = parse_args()
    cpp = load(cpp_p, bar)   # shift cpp fill-bar back to signal-bar
    ref = load(ref_p, 0)
    ck, rk = set(cpp), set(ref)

    # exact (minute+dir) match; then fuzzy ±tol minutes for the rest
    matched = sorted(ck & rk)
    cu, ru = ck - set(matched), rk - set(matched)
    fuzzy = []
    ru_by = {}
    for (ts, d) in ru: ru_by.setdefault(d, []).append(datetime.strptime(ts, "%Y.%m.%d %H:%M"))
    for (ts, d) in sorted(cu):
        c = datetime.strptime(ts, "%Y.%m.%d %H:%M")
        cand = [x for x in ru_by.get(d, []) if abs((x - c).total_seconds()) <= tol*60]
        if cand:
            best = min(cand, key=lambda x: abs((x - c).total_seconds()))
            fuzzy.append(((ts, d), (best.strftime("%Y.%m.%d %H:%M"), d)))
            ru_by[d].remove(best)
    pairs = [(k, k) for k in matched] + fuzzy
    missed = sorted(set(ru) - set(b for _, b in fuzzy))
    extra  = sorted(set(cu) - set(a for a, _ in fuzzy))

    print(f"cpp={len(cpp)} ref={len(ref)} | matched={len(pairs)} (exact={len(matched)} fuzzy±{tol}m={len(fuzzy)}) "
          f"missed(ref-only)={len(missed)} extra(cpp-only)={len(extra)}")

    if pairs:
        de = dr = 0.0; n = 0; mxe = mxr = 0.0
        conf = {}
        for ck_, rk_ in pairs:
            a, b = cpp[ck_], ref[rk_]
            de += abs(a["entry"]-b["entry"]); mxe = max(mxe, abs(a["entry"]-b["entry"]))
            if a["risk"] and b["risk"]:
                dr += abs(a["risk"]-b["risk"]); mxr = max(mxr, abs(a["risk"]-b["risk"])); n += 1
            conf[(a["fam"], b["fam"])] = conf.get((a["fam"], b["fam"]), 0) + 1
        print(f"\nmatched entry   max|Δ|={mxe:.4f} mean|Δ|={de/len(pairs):.4f}")
        if n: print(f"matched risk    max|Δ|={mxr:.4f} mean|Δ|={dr/n:.4f}")
        agree = sum(v for (cf, rf), v in conf.items() if cf == rf)
        print(f"\nexit-family agreement: {agree}/{len(pairs)} ({100*agree/len(pairs):.0f}%)")
        print("exit-family confusion (cpp -> ref : count):")
        for (cf, rf), v in sorted(conf.items(), key=lambda x: -x[1]):
            mark = "" if cf == rf else "   <-- MISMATCH"
            print(f"  {cf:7s} -> {rf:7s} : {v}{mark}")

if __name__ == "__main__":
    main()
