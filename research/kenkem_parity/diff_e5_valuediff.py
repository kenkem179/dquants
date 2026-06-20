#!/usr/bin/env python3
"""E5 2026 detection-miss VALUE-DIFF.

Joins the EA realtrace (now carrying gate INPUTS: M1 ema25/75/100/200, M1 di+/-,
M5/M15 adx+di) against engine value dumps (E5V = M1 EMA stack + alignment verdict,
E5D = M1/M5/M15 DI+ADX closed AND forming, E5G = per-bar armed-state + gate label),
on the signal-bar ts grid, for every MT5 E5 trade the engine MISSED.

Buckets each missed trade by the engine's state at its signal bar and reports the
numeric divergence in the binding gate's inputs:
  unarmed     -> M1 4-EMA stack (engine ema vs EA ema) + strict-alignment verdicts
  htf         -> M5/M15 adx/di (engine closed+forming vs EA)
  trend_core  -> M1 di/adx (engine closed+forming vs EA)

Usage: python research/kenkem_parity/diff_e5_valuediff.py [--eng /tmp/e5v_run/trades.csv]
                                                          [--diag /tmp/e5v_run/diag.log]
"""
import os, sys, csv, calendar, argparse
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from diff_kk import load, match  # noqa: E402

RUN = os.path.join(HERE, "mt5_runs", "RUN_2026-06-20_1.8.154_xau_2026H1_E5only_realtrace_v2cols")
RT  = os.path.join(RUN, "realtrace_XAUUSD-Exness-KK.csv")
MT5 = os.path.join(HERE, "mt5_runs", "RUN_2026-06-20_1.8.154_xau_2026H1_E5only_gatetrace", "trades.csv")
LAG = 5.0


def ms_of(dt):  # UTC epoch ms from a naive UTC datetime
    return calendar.timegm(dt.timetuple()) * 1000


def fnum(x):
    try: return float(x)
    except Exception: return float("nan")


def load_diag(path):
    """Return dicts keyed by ts_ms: e5v[ts], e5d[ts], e5g[(ts,dir)]."""
    e5v, e5d, e5g = {}, {}, {}
    for ln in open(path):
        if ln.startswith("E5V,"):
            p = ln.rstrip("\n").split(",")
            ts = int(p[1])
            e5v[ts] = dict(ema25=fnum(p[2]), ema75=fnum(p[3]), ema100=fnum(p[4]), ema200=fnum(p[5]),
                           up1=int(p[6]), up2=int(p[7]), dn1=int(p[8]), dn2=int(p[9]),
                           e5_up=int(p[10]), e5_down=int(p[11]),
                           e25_b1=fnum(p[12]) if len(p) > 12 else float("nan"),
                           e25_b3=fnum(p[13]) if len(p) > 13 else float("nan"),
                           al_b1=int(p[14]) if len(p) > 14 else -1,
                           al_b3=int(p[15]) if len(p) > 15 else -1)
        elif ln.startswith("E5D,"):
            p = ln.rstrip("\n").split(",")
            ts = int(p[1])
            keys = ["m1_diP","m1_diM","m1_diPF","m1_diMF","m1_adx","m1_adxF",
                    "m5_adx","m5_diP","m5_diM","m5_adxF","m5_diPF","m5_diMF",
                    "m15_adx","m15_diP","m15_diM","m15_adxF","m15_diPF","m15_diMF"]
            e5d[ts] = {k: fnum(v) for k, v in zip(keys, p[2:])}
        elif ln.startswith("E5G,"):
            p = ln.rstrip("\n").split(",")
            ts, d, st = int(p[1]), p[2], p[3]
            label = p[5] if len(p) > 5 else "-"
            e5g[(ts, d)] = dict(state=st, label=label)
    return e5v, e5d, e5g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eng", default="/tmp/e5v_run/trades.csv")
    ap.add_argument("--diag", default="/tmp/e5v_run/diag.log")
    a = ap.parse_args()

    mt5 = [r for r in load(MT5) if r["kind"] == "E5"]
    eng = [e for e in load(a.eng) if e["kind"] == "E5"]
    lo, hi = mt5[0]["t"], mt5[-1]["t"]
    engw = [e for e in eng if lo - timedelta(minutes=LAG) <= e["t"] <= hi + timedelta(minutes=LAG)]
    pairs, miss, over = match(mt5, engw, LAG)
    missed = [mt5[i] for i in miss]
    print(f"MT5 E5={len(mt5)} eng={len(engw)} matched={len(pairs)} MISSED={len(missed)} overfire={len(over)}")

    rt = list(csv.DictReader(open(RT)))
    rt_by_ts = {}
    for r in rt:
        rt_by_ts.setdefault(int(r["ts_ms"]), []).append(r)
    e5v, e5d, e5g = load_diag(a.diag)

    def signal_row(entry_ms, d):
        # signal bar = the most recent realtrace row with the trade's dir, ts < entry, within 3 min
        for off in (60000, 120000, 180000):
            cand = rt_by_ts.get(entry_ms - off, [])
            for r in cand:
                if (d == "L" and r["armed_dir"] == "1") or (d == "S" and r["armed_dir"] == "-1"):
                    return r, entry_ms - off
            if cand:
                return cand[0], entry_ms - off
        return None, None

    buckets = {"unarmed": [], "htf": [], "trend_core": [], "armed_pass": [], "nojoin": []}
    for m in missed:
        ems = ms_of(m["t"]); d = m["dir"]
        r, sts = signal_row(ems, d)
        if r is None:
            buckets["nojoin"].append((m, None, None)); continue
        g = e5g.get((sts, d))
        if g is None:
            buckets["nojoin"].append((m, r, None)); continue
        if g["state"] == "unarmed":
            buckets["unarmed"].append((m, r, sts))
        elif g["label"] in ("htf",):
            buckets["htf"].append((m, r, sts))
        elif g["label"] in ("trend_core", "trendcore", "tc"):
            buckets["trend_core"].append((m, r, sts))
        else:
            buckets["armed_pass"].append((m, r, sts, g["label"]))

    print("\n=== BUCKETS (engine state at the missed trade's signal bar) ===")
    for k, v in buckets.items():
        print(f"  {k:<12} {len(v)}")

    # ---- UNARMED: M1 4-EMA stack value-diff + 1-bar-shift test ----
    print("\n=== UNARMED — M1 ema25: EA vs engine at B-1/B-2/B-3 (shift test) ===")
    print("  dir  sig_dt            EA.ema25   eng.B-1   eng.B-2*  eng.B-3   |best-match bar|  up1/up2")
    shift_vote = {"B-1": 0, "B-2": 0, "B-3": 0}
    for m, r, sts in buckets["unarmed"]:
        v = e5v.get(sts)
        ea25 = fnum(r["ema25"])
        uv = f"{v['up1']}/{v['up2']}" if (v and m["dir"] == "L") else (f"{v['dn1']}/{v['dn2']}" if v else "-")
        if v:
            cand = {"B-1": v["e25_b1"], "B-2": v["ema25"], "B-3": v["e25_b3"]}
            best = min(cand, key=lambda k: abs(cand[k] - ea25))
            shift_vote[best] += 1
            print(f"  {m['dir']}  {m['t']}  {ea25:8.3f}  {v['e25_b1']:8.3f}  {v['ema25']:8.3f}  "
                  f"{v['e25_b3']:8.3f}   {best:5}            {uv}")
        else:
            print(f"  {m['dir']}  {m['t']}  {ea25:8.3f}  (no E5V @ {sts})")
    print(f"\n  SHIFT VOTE (engine bar whose ema25 best matches EA's logged ema25): {shift_vote}")

    # ---- HTF: M5/M15 adx/di value-diff ----
    print("\n=== HTF — M5/M15 adx/di: EA(realtrace) vs engine(E5D closed/forming) ===")
    print("  dir  sig_dt            EA m5(adx,di+,di-) | ENG m5 closed | ENG m5 forming")
    for m, r, sts in buckets["htf"]:
        dd = e5d.get(sts)
        ea = (fnum(r["m5_adx"]), fnum(r["m5_diplus"]), fnum(r["m5_diminus"]))
        if dd:
            print(f"  {m['dir']}  {m['t']}  EA({ea[0]:.1f},{ea[1]:.1f},{ea[2]:.1f}) | "
                  f"clo({dd['m5_adx']:.1f},{dd['m5_diP']:.1f},{dd['m5_diM']:.1f}) | "
                  f"frm({dd['m5_adxF']:.1f},{dd['m5_diPF']:.1f},{dd['m5_diMF']:.1f})")
        else:
            print(f"  {m['dir']}  {m['t']}  EA m5({ea[0]:.1f},{ea[1]:.1f},{ea[2]:.1f})  (no E5D @ {sts})")

    # ---- TREND_CORE: M1 di/adx value-diff ----
    print("\n=== TREND_CORE — M1 di/adx: EA(realtrace) vs engine(E5D closed/forming) ===")
    print("  dir  sig_dt            EA m1(adx,di+,di-) | ENG m1 closed | ENG m1 forming")
    for m, r, sts in buckets["trend_core"]:
        dd = e5d.get(sts)
        ea = (fnum(r["adx_m1"]), fnum(r["m1_diplus"]), fnum(r["m1_diminus"]))
        if dd:
            print(f"  {m['dir']}  {m['t']}  EA({ea[0]:.1f},{ea[1]:.1f},{ea[2]:.1f}) | "
                  f"clo({dd['m1_adx']:.1f},{dd['m1_diP']:.1f},{dd['m1_diM']:.1f}) | "
                  f"frm({dd['m1_adxF']:.1f},{dd['m1_diPF']:.1f},{dd['m1_diMF']:.1f})")
        else:
            print(f"  {m['dir']}  {m['t']}  EA m1({ea[0]:.1f},{ea[1]:.1f},{ea[2]:.1f})  (no E5D @ {sts})")

    if buckets["armed_pass"]:
        print("\n=== ARMED+PASS (engine armed & gate passed — timing/occupancy/execute) ===")
        for m, r, sts, lbl in buckets["armed_pass"]:
            print(f"  {m['dir']}  {m['t']}  engine label={lbl}")


if __name__ == "__main__":
    main()
