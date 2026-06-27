#!/usr/bin/env python3
"""KenKem M3 (3x-clock) surgical sweep harness.

Runs the kenkem tick_backtester over a parameter grid by generating .set
overlays on top of a base lock .set, executing in parallel, and collecting
net/PF/maxDD/per-entry/per-quarter for each cell.

Scope (build-plan K1, E1+E2): rescale pip/RR for M3 + recalibrate the quality
gate. Train window holds out the lock's golden 2025Q4 + 2026 as OOS.
"""
import csv, itertools, os, re, subprocess, sys, tempfile
from concurrent.futures import ProcessPoolExecutor

ROOT = "/Users/tokyotechies/Workspace/KEM/dquants"
BIN  = f"{ROOT}/cpp_core/build/kenkem/tick_backtester"
BARS = f"{ROOT}/cpp_core/tools/bars_xauusd_2024_2026_m3.csv"   # M3 base -> 3x clock
TICKS= f"{ROOT}/cpp_core/tools/ticks_xauusd_2024_2026.csv"
BASE = f"{ROOT}/research/kenkem_parity/KK-KenKem-XAUUSD-M1-D5-E4Long.set"
OUTD = f"{ROOT}/research/kenkem_parity/m3_sweep"

# epoch ms boundaries
T_2025Q4 = 1759276800000   # 2025-10-01 (train/OOS split: hold out Q4+2026)

def load_base():
    kv = {}
    with open(BASE) as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith(";") or "=" not in ln: continue
            k, v = ln.split("=", 1); kv[k.strip()] = v.strip()
    return kv

def quarter(ts_utc):  # "2025.07.03 14:22" -> "2025Q3"
    y = int(ts_utc[:4]); mo = int(ts_utc[5:7]); return f"{y}Q{(mo-1)//3+1}"

def run_cell(args):
    overrides, to_ms, tag = args
    base = load_base()
    base.update({k: str(v) for k, v in overrides.items()})
    fd, sp = tempfile.mkstemp(suffix=".set", dir=OUTD); os.close(fd)
    with open(sp, "w") as f:
        for k, v in base.items(): f.write(f"{k}={v}\n")
    outcsv = os.path.join(OUTD, f"tr_{tag}.csv")
    cmd = [BIN, "--bars-m1", BARS, "--ticks", TICKS, "--symbol-xau",
           "--set", sp, "--out", outcsv]
    if to_ms: cmd += ["--to-ms", str(to_ms)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    os.unlink(sp)
    out = r.stdout
    def gf(pat, d=0.0):
        m = re.search(pat, out); return float(m.group(1)) if m else d
    res = dict(overrides)
    res["tag"] = tag
    res["trades"] = int(gf(r"trades:\s+(\d+)"))
    res["win"]    = gf(r"win% (\d+\.\d+)")
    res["net"]    = gf(r"net:\s+(-?\d+\.\d+)")
    res["pf"]     = gf(r"PF:\s+(\d+\.\d+)")
    res["maxdd"]  = gf(r"max DD:\s+(\d+\.\d+)")
    me = re.search(r"E1 (\d+).*?E2 (\d+).*?E4 (\d+).*?E5 (\d+)", out)
    if me: res["e1"],res["e2"],res["e4"],res["e5"] = (int(me.group(i)) for i in range(1,5))
    # per-quarter net from the trade csv
    pq = {}
    try:
        with open(outcsv) as f:
            for row in csv.DictReader(f):
                q = quarter(row["entryTimeUTC"]); pq[q] = pq.get(q,0.0)+float(row["realizedUsd"])
    except FileNotFoundError: pass
    res["perq"] = ";".join(f"{q}:{pq[q]:.0f}" for q in sorted(pq))
    return res

def grid(spec):
    keys = list(spec); cells = []
    for combo in itertools.product(*[spec[k] for k in keys]):
        ov = dict(zip(keys, combo))
        tag = "_".join(f"{k.split('_')[0]}{v}" for k,v in ov.items())[:60]
        cells.append(ov)
    return cells

if __name__ == "__main__":
    # refined spec: extend RR (was monotone @2.8); add quality-gate levers to kill
    # the persistent 2025Q1/Q3 dead quarters. tol=35 / SL=55 fixed (weak effect).
    spec = {
        "EMA_ALIGNMENT_TOLERANCE_PIPS": [35.0],
        "SL_EMA_DISTANCE": [55],
        "E1_RR":                  [2.8, 3.2, 3.6, 4.0, 4.5],
        "MIN_ENTRY_ATR_PERCENTILE": [70, 80, 88],
        "SIDEWAYS_BLOCK_THRESHOLD": [45, 38, 32],
    }
    cells = grid(spec)
    print(f"[sweep] {len(cells)} cells, TRAIN window (to {T_2025Q4})", file=sys.stderr)
    work = [(ov, T_2025Q4, f"r{i:03d}") for i,ov in enumerate(cells)]
    rows = []
    with ProcessPoolExecutor(max_workers=6) as ex:
        for r in ex.map(run_cell, work):
            rows.append(r)
            print(f"  {r['tag']} tol={r.get('EMA_ALIGNMENT_TOLERANCE_PIPS')} "
                  f"rr={r.get('E1_RR')} sl={r.get('SL_EMA_DISTANCE')} -> "
                  f"n={r['trades']} pf={r['pf']:.3f} net={r['net']:.0f} dd={r['maxdd']:.0f}",
                  file=sys.stderr)
    # objective: PF with maxDD penalty, require n>=122
    def obj(r): return (r["pf"] if r["trades"]>=122 else 0.0) - r["maxdd"]/20000.0
    rows.sort(key=obj, reverse=True)
    cols = ["tag","EMA_ALIGNMENT_TOLERANCE_PIPS","E1_RR","SL_EMA_DISTANCE",
            "MIN_ENTRY_ATR_PERCENTILE","SIDEWAYS_BLOCK_THRESHOLD",
            "trades","win","net","pf","maxdd","e1","e2","e4","perq"]
    with open(f"{OUTD}/sweep_refined_results.csv","w",newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore"); w.writeheader()
        for r in rows: w.writerow(r)
    print("\n=== TOP 12 (train, to 2025Q4; obj=PF-dd/20k, n>=122) ===")
    print(f"{'rr':>5}{'atrP':>6}{'swB':>5}{'n':>6}{'pf':>8}{'net':>9}{'dd':>8}  perq")
    for r in rows[:12]:
        print(f"{r['E1_RR']:>5}{r['MIN_ENTRY_ATR_PERCENTILE']:>6}{r['SIDEWAYS_BLOCK_THRESHOLD']:>5}"
              f"{r['trades']:>6}{r['pf']:>8.3f}{r['net']:>9.0f}{r['maxdd']:>8.0f}  {r['perq']}")
