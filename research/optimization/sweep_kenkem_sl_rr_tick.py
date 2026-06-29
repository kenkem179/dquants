#!/usr/bin/env python3
"""Per-knob SENSITIVITY sweep of KenKem SL/RR/exit geometry on the TICK engine.

WHY: the only prior KenKem sweep harness (optimize_kenkem.py) runs the BAR engine,
which has a P&L-sign defect -> its "optima" are unreliable. This runs the validated
TICK engine (cpp_core/build/kenkem/tick_backtester) over the FULL XAU M1 window, one
knob at a time around the D5-E4Long lock, and reports net / PF / maxDD with a
2025-train / 2026-test split so we can see PLATEAUS (not peaks) and OOS stability.

Only LIVE, EA-honorable knobs are swept (E4_ATR_SL_* is dead — E4 borrows E2's cap
per entries.hpp:62; ADX_LEN/RSI_LEN/Ichimoku are EA-hardcoded). Nothing here locks
anything — it produces sensitivity curves to design the gated joint refine + MT5 confirm.

Usage: conda run -n kenkem python research/optimization/sweep_kenkem_sl_rr_tick.py [n_jobs]
Outputs: sweep_kenkem_sl_rr_tick.csv + stdout sensitivity tables.
"""
import csv, os, subprocess, sys, tempfile
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BIN = os.path.join(ROOT, "cpp_core", "build", "kenkem", "tick_backtester")
KP  = os.path.join(ROOT, "research", "kenkem_parity")
M1  = os.path.join(KP, "bars_xauusd_M1_kk.csv")
TICKS = os.path.join(KP, "ticks_xau_full.csv")
LOCK = os.path.join(KP, "KK-KenKem-XAUUSD-M1-D5-E4Long.set")
TEST_CUT_MS = 1735689600000   # 2026-01-01 00:00 UTC ms -> train=2025, test=2026

# knob -> values to sweep (lock value included so the baseline row appears in each curve)
SWEEP = {
    "SL_EMA_DISTANCE":            [15, 19, 23, 27, 31, 35],
    "E1_ATR_SL_CAP_MULTIPLIER":   [2.5, 3.0, 3.5, 4.0, 4.5],
    "E1_ATR_SL_FLOOR_MULTIPLIER": [0.8, 1.0, 1.2, 1.5],
    "E2_ATR_SL_CAP_MULTIPLIER":   [2.0, 2.5, 3.0, 3.5, 4.0],   # also governs E4 (parity borrow)
    "E2_ATR_SL_FLOOR_MULTIPLIER": [0.8, 1.0, 1.1, 1.3],
    "E1_RR":                      [1.5, 1.7, 1.9, 2.1, 2.3, 2.5],
    "E2_RR":                      [1.3, 1.45, 1.575, 1.75, 1.9],
    "E4_RR":                      [1.8, 2.1, 2.4, 2.7, 3.0],
    "E4_RR_SHORT":                [1.5, 1.8, 2.1, 2.4],
    "E1_TRAILING_SL_FACTOR":      [0.25, 0.4, 0.55, 0.7],
    "E2_TRAILING_SL_FACTOR":      [0.3, 0.45, 0.6],
    "E4_TRAILING_SL_FACTOR":      [0.3, 0.5, 0.7],
    "E1_PARTIAL_TP_TRIGGER":      [0.5, 0.7, 0.9],   # BE/bank arm
    "E2_PARTIAL_TP_TRIGGER":      [0.5, 0.6, 0.7, 0.8],
    "E4_PARTIAL_TP_TRIGGER":      [0.5, 0.6, 0.7, 0.8],
}


def load_set(path):
    d = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(";") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            d[k.strip()] = v.strip()
    return d


BASE = load_set(LOCK)


def parse_ms(ts):  # "2025.03.03 07:18"
    d, t = ts.split(" ")
    y, mo, da = d.split("."); hh, mm = t.split(":")[:2]
    import datetime
    return int(datetime.datetime(int(y), int(mo), int(da), int(hh), int(mm),
                                 tzinfo=datetime.timezone.utc).timestamp() * 1000)


def metrics(pnls):
    if not pnls:
        return dict(n=0, net=0.0, pf=0.0, dd=0.0)
    net = sum(pnls)
    gp = sum(p for p in pnls if p > 0); gl = -sum(p for p in pnls if p < 0)
    peak = cum = dd = 0.0
    for p in pnls:
        cum += p; peak = max(peak, cum); dd = max(dd, peak - cum)
    return dict(n=len(pnls), net=net, pf=(gp / gl if gl > 0 else 0.0), dd=dd)


def run_one(args):
    knob, val = args
    ov = dict(BASE); ov[knob] = (str(int(val)) if knob == "SL_EMA_DISTANCE" else str(val))
    with tempfile.TemporaryDirectory() as tmp:
        sp = os.path.join(tmp, "s.set"); op = os.path.join(tmp, "o.csv")
        with open(sp, "w") as f:
            for k, v in ov.items():
                f.write(f"{k}={v}\n")
        subprocess.run([BIN, "--bars-m1", M1, "--ticks", TICKS, "--symbol-xau",
                        "--set", sp, "--out", op],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        tr_p, te_p, all_p = [], [], []
        with open(op) as f:
            for r in csv.DictReader(f):
                ms = parse_ms(r["entryTimeUTC"]); pnl = float(r["realizedUsd"])
                all_p.append(pnl)
                (te_p if ms >= TEST_CUT_MS else tr_p).append(pnl)
    a, t, e = metrics(all_p), metrics(tr_p), metrics(te_p)
    return dict(knob=knob, val=val, n=a["n"], net=round(a["net"], 0), pf=round(a["pf"], 3),
                dd=round(a["dd"], 0), train_net=round(t["net"], 0), train_pf=round(t["pf"], 3),
                test_net=round(e["net"], 0), test_pf=round(e["pf"], 3))


def main():
    n_jobs = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    jobs = [(k, v) for k, vals in SWEEP.items() for v in vals]
    print(f"[sweep] {len(jobs)} tick runs over {len(SWEEP)} knobs, n_jobs={n_jobs}\n")
    rows = []
    with ProcessPoolExecutor(max_workers=n_jobs) as ex:
        for r in ex.map(run_one, jobs):
            rows.append(r)
    out = os.path.join(HERE, "sweep_kenkem_sl_rr_tick.csv")
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)

    for knob in SWEEP:
        krows = [r for r in rows if r["knob"] == knob]
        lock_v = BASE.get(knob, "?")
        print(f"=== {knob}  (lock={lock_v}) ===")
        print(f"{'val':>8} {'n':>4} {'net':>7} {'pf':>6} {'maxDD':>6} | {'train_net':>9} {'test_net':>8} {'test_pf':>7}")
        for r in sorted(krows, key=lambda x: x["val"]):
            mark = "  <-lock" if str(r["val"]) == str(lock_v) or str(int(r["val"]) if isinstance(r["val"], (int, float)) and float(r["val"]).is_integer() else r["val"]) == str(lock_v) else ""
            print(f"{r['val']:>8} {r['n']:>4} {r['net']:>7.0f} {r['pf']:>6.3f} {r['dd']:>6.0f} | "
                  f"{r['train_net']:>9.0f} {r['test_net']:>8.0f} {r['test_pf']:>7.3f}{mark}")
        print()
    print(f"[out] {out}")


if __name__ == "__main__":
    main()
