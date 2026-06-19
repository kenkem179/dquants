#!/usr/bin/env python3
"""Field-by-field diff of engine vs MT5 E5 per-bar TraceBar dumps.
Joins on ts_ms (auto-detects a constant offset), then decomposes where the
L_fire / S_fire / fire_dir decision diverges into the FIRST failing gate column.

Usage: diff_e5_trace.py --eng /tmp/e5_trace_eng.csv --mt5 <trace.csv(.gz)>
"""
import argparse, gzip, csv, io, sys
from collections import Counter

def load(path):
    op = gzip.open if path.endswith(".gz") else open
    with op(path, "rt") as f:
        rows = list(csv.DictReader(f))
    return rows

def to_i(v):
    try: return int(float(v))
    except: return 0
def to_f(v):
    try: return float(v)
    except: return 0.0

# gate columns, IN EVALUATION ORDER (first mismatch wins for blame)
GATE_COLS = ["e5up_age","e5dn_age","L_inage","L_swblk","L_atrlo","L_atrhi","L_price",
             "L_tcore","L_tq","L_tqok","L_adx","L_htf","L_pass","L_fire",
             "S_inage","S_swblk","S_atrlo","S_atrhi","S_price","S_tcore","S_tq",
             "S_tqok","S_adx","S_htf","S_pass","S_fire","session","fire_dir"]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eng", required=True)
    ap.add_argument("--mt5", required=True)
    ap.add_argument("--show", type=int, default=0)
    a = ap.parse_args()

    eng = load(a.eng); mt5 = load(a.mt5)
    print(f"eng rows {len(eng)}  mt5 rows {len(mt5)}")

    # index by ts_ms
    eidx = {to_i(r["ts_ms"]): r for r in eng}
    midx = {to_i(r["ts_ms"]): r for r in mt5}

    # auto-detect offset: try a few candidate offsets, pick max overlap
    ekeys = set(eidx); mkeys = set(midx)
    best_off, best_ov = 0, -1
    for off in (0, 60000, -60000, 3600000, -3600000):
        ov = len(ekeys & {k - off for k in mkeys})
        if ov > best_ov: best_off, best_ov = off, ov
    print(f"best offset (mt5_ts + off = eng_ts): {best_off} ms  overlap={best_ov}")
    off = best_off

    # build joined pairs
    joined = []
    for mk, mr in midx.items():
        ek = mk + off
        er = eidx.get(ek)
        if er: joined.append((er, mr))
    print(f"joined bars: {len(joined)}")

    # fire decision agreement
    fd_agree = fd_disagree = 0
    blame = Counter()
    examples = []
    for er, mr in joined:
        efd, mfd = to_i(er["fire_dir"]), to_i(mr["fire_dir"])
        if efd == mfd:
            fd_agree += 1
            continue
        fd_disagree += 1
        # find first gate col that differs (numeric/bool compare)
        first = None
        for c in GATE_COLS:
            ev, mv = er.get(c,""), mr.get(c,"")
            # numeric compare with tol for ages/scores, bool exact
            try:
                if abs(to_f(ev) - to_f(mv)) > 1e-9:
                    first = c; break
            except:
                if ev != mv: first = c; break
        blame[first] += 1
        if len(examples) < a.show:
            examples.append((er, mr, first))

    print(f"\nfire_dir agree {fd_agree}  disagree {fd_disagree}")
    print("\nFIRST-divergent gate column among disagreeing bars:")
    for c, n in blame.most_common():
        print(f"  {c:10s} {n}")

    # also: who fired where the other didn't
    eng_only = sum(1 for er,mr in joined if to_i(er["fire_dir"])!=0 and to_i(mr["fire_dir"])==0)
    mt5_only = sum(1 for er,mr in joined if to_i(er["fire_dir"])==0 and to_i(mr["fire_dir"])!=0)
    both     = sum(1 for er,mr in joined if to_i(er["fire_dir"])!=0 and to_i(mr["fire_dir"])!=0)
    print(f"\nsignal-fire: eng-only {eng_only}  mt5-only {mt5_only}  both(any dir) {both}")

    for er, mr, first in examples:
        print(f"\n--- {mr['dt']}  blame={first}  eng_fd={er['fire_dir']} mt5_fd={mr['fire_dir']}")
        for c in GATE_COLS:
            if er.get(c)!=mr.get(c):
                print(f"    {c:10s} eng={er.get(c):>10} mt5={mr.get(c):>10}")

if __name__ == "__main__":
    main()
