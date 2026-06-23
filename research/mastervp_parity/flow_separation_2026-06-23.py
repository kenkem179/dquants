#!/usr/bin/env python3
"""
Step-0 measurement (2026-06-23): does the per-bar net-flow signal SEPARATE winners that
round-trip to BE from genuine runners?  Unbiased — uses only price/flow PATH GEOMETRY
(unrealized-R per closed bar), never net P&L (which the engine over-credits on runners).

Input: flowpath CSV from `backtester --flow-path-out` (one row per open-trade per closed bar):
       entry_ts_ms,bar_ts_ms,dir,unreal_r,mfe_r,net_flow,node_net

Two questions:
  (Q1) Baseline giveback: among trades reaching peak >= 1R, what % end <= 0.15R? (matches the
       45.3% study figure -> sanity check that this path data is representative).
  (Q2) Actionable value: a "net-flow flip" exit (arm at mfe>=arm_r, fire when net_flow is
       against the position for K consecutive closed bars) -> compare the R it BANKS vs the R
       the trade ACTUALLY ended at. On round-trippers it should rescue a lot; on runners it
       should sacrifice little. Net geometry gain = sum(banked_r - final_r) over armed trades.
       > 0  => the signal has real, exploitable structure (engine net-P&L rejection was bias).
       <= 0 => dead signal; stop chasing it. Either answer is decisive.
"""
import csv, sys, itertools
from collections import defaultdict

def load(path):
    trades = defaultdict(list)      # tid -> list of per-bar (bar_ts,dir,unreal_r,mfe_r,net_flow)
    exitr  = {}                     # tid -> TRUE exit R (from the bar_ts=-1 summary row)
    peakr  = {}                     # tid -> peak mfe_r (from summary)
    with open(path) as f:
        for r in csv.DictReader(f):
            bt = int(r["bar_ts_ms"])
            if bt == -1:                                   # summary row: true exit geometry
                exitr[r["entry_ts_ms"]] = float(r["unreal_r"])   # exit_r is in the unreal_r column
                peakr[r["entry_ts_ms"]] = float(r["mfe_r"])
                continue
            trades[r["entry_ts_ms"]].append(
                (bt, r["dir"], float(r["unreal_r"]), float(r["mfe_r"]), float(r["net_flow"])))
    for k in trades: trades[k].sort(key=lambda x: x[0])
    return trades, exitr, peakr

def simulate(loaded, arm_r, K, minv):
    trades, exitr, peakr = loaded
    n_arm = n_rt = 0
    base_giveback = 0          # peak>=1R trades ending <=0.15R
    n_peak1 = 0
    banked_sum = final_sum = 0.0
    rt_bank = rt_final = 0.0    # round-trippers
    run_bank = run_final = 0.0  # runners (end >= 1R)
    for tid, path_rows in trades.items():
        is_long = path_rows[0][1] == "L"
        peak = peakr.get(tid, max(p[3] for p in path_rows))   # TRUE peak R (summary mfe_r)
        final = exitr.get(tid, path_rows[-1][2])               # TRUE exit R (intrabar-accurate)
        if peak >= 1.0:
            n_peak1 += 1
            if final <= 0.15: base_giveback += 1
        # delta-exit: arm once mfe>=arm_r, fire on first K-consecutive against-flow run
        armed = False; fired = False; banked = None
        against_streak = 0
        for (_, _, rr, mfe, nf) in path_rows:
            if not armed and mfe >= arm_r: armed = True
            if armed:
                against = (nf <= -minv) if is_long else (nf >= minv)
                against_streak = against_streak + 1 if against else 0
                if against_streak >= K:
                    fired = True; banked = rr; break
        if not armed:
            continue
        n_arm += 1
        # if it never fired, the "rule" lets it ride to the actual end
        b = banked if fired else final
        banked_sum += b; final_sum += final
        is_rt = (peak >= 1.0 and final <= 0.15)
        if is_rt:
            n_rt += 1; rt_bank += b; rt_final += final
        elif final >= 1.0:
            run_bank += b; run_final += final
    return dict(n_arm=n_arm, n_peak1=n_peak1, base_giveback=base_giveback,
                base_gb_pct=100*base_giveback/max(n_peak1,1),
                banked_sum=banked_sum, final_sum=final_sum, gain=banked_sum-final_sum,
                n_rt=n_rt, rt_bank=rt_bank, rt_final=rt_final,
                run_bank=run_bank, run_final=run_final)

def simulate_div(loaded, arm_r, margin):
    """DIVERGENCE form: arm at mfe>=arm_r; track the net_flow recorded at each NEW mfe-high bar;
    fire when a new price-high prints but its net_flow is >= `margin` BELOW the prior high's flow
    (bearish divergence for a long). More selective than raw against-flow. Pure R-geometry value."""
    trades, exitr, peakr = loaded
    banked_sum = final_sum = 0.0
    rt_bank = rt_final = run_bank = run_final = 0.0
    n_arm = n_rt = 0
    for tid, path_rows in trades.items():
        is_long = path_rows[0][1] == "L"
        peak = peakr.get(tid, max(p[3] for p in path_rows))
        final = exitr.get(tid, path_rows[-1][2])
        armed = False; fired = False; banked = None
        best_r = -1e9; prev_high_flow = None
        for (_, _, rr, mfe, nf) in path_rows:
            if not armed and mfe >= arm_r: armed = True
            if rr > best_r:                                   # new favorable extreme
                best_r = rr
                f = nf if is_long else -nf                    # flow in trade direction
                if armed and prev_high_flow is not None and f <= prev_high_flow - margin:
                    fired = True; banked = rr; break
                prev_high_flow = f
        if not armed: continue
        n_arm += 1
        b = banked if fired else final
        banked_sum += b; final_sum += final
        if peak >= 1.0 and final <= 0.15:
            n_rt += 1; rt_bank += b; rt_final += final
        elif final >= 1.0:
            run_bank += b; run_final += final
    return dict(n_arm=n_arm, n_rt=n_rt, gain=banked_sum-final_sum,
                rt_rescue=rt_bank-rt_final, run_cost=run_bank-run_final)

if __name__ == "__main__":
    path = sys.argv[1]
    loaded = load(path)
    # sanity: baseline giveback rate (config-independent)
    s0 = simulate(loaded, arm_r=1.0, K=99, minv=0.0)   # K=99 => never fires => pure baseline
    print(f"== BASELINE (path geometry) ==")
    print(f"trades reaching peak>=1R : {s0['n_peak1']}")
    print(f"  ... ending <=0.15R     : {s0['base_giveback']}  ({s0['base_gb_pct']:.1f}%)   "
          f"[study said 45.3%]")
    print()
    print(f"== NET-FLOW FLIP EXIT — pure R-geometry value (banked vs actual end) ==")
    print(f"{'arm_r':>5} {'K':>2} {'minv':>4} | {'#armed':>6} {'#RT':>4} | "
          f"{'gain_R':>8} | {'RT rescue':>10} {'run cost':>9}")
    best = None
    for arm_r, K, minv in itertools.product([0.8,1.0,1.5,2.0],[1,2,3],[0.3,0.6,1.0]):
        s = simulate(loaded, arm_r, K, minv)
        gain = s["gain"]
        rt_rescue = s["rt_bank"] - s["rt_final"]      # R rescued on round-trippers (want >>0)
        run_cost  = s["run_bank"] - s["run_final"]    # R sacrificed on runners (want ~0, <0)
        print(f"{arm_r:>5} {K:>2} {minv:>4} | {s['n_arm']:>6} {s['n_rt']:>4} | "
              f"{gain:>+8.1f} | {rt_rescue:>+10.1f} {run_cost:>+9.1f}")
        if best is None or gain > best[0]: best = (gain, arm_r, K, minv, rt_rescue, run_cost)
    print()
    g, ar, k, mv, rr, rc = best
    print(f"BEST against-flow: arm_r={ar} K={k} minv={mv} -> gain {g:+.1f}R "
          f"(rescue {rr:+.1f}R RTs, cost {rc:+.1f}R runners)")
    print()
    print(f"== DIVERGENCE EXIT — price new-high but flow lower-high (more selective) ==")
    print(f"{'arm_r':>5} {'margin':>6} | {'#armed':>6} {'#RT':>4} | {'gain_R':>8} | "
          f"{'RT rescue':>10} {'run cost':>9}")
    dbest = None
    for arm_r, margin in itertools.product([0.8,1.0,1.5,2.0],[0.5,1.0,1.5,2.0]):
        s = simulate_div(loaded, arm_r, margin)
        print(f"{arm_r:>5} {margin:>6} | {s['n_arm']:>6} {s['n_rt']:>4} | {s['gain']:>+8.1f} | "
              f"{s['rt_rescue']:>+10.1f} {s['run_cost']:>+9.1f}")
        if dbest is None or s['gain'] > dbest['gain']: dbest = s | dict(arm_r=arm_r, margin=margin)
    print()
    print(f"BEST divergence: arm_r={dbest['arm_r']} margin={dbest['margin']} -> "
          f"gain {dbest['gain']:+.1f}R (rescue {dbest['rt_rescue']:+.1f}R RTs, "
          f"cost {dbest['run_cost']:+.1f}R runners)")
    print()
    print("READ: a usable signal needs LARGE +RT-rescue with NEAR-ZERO runner cost. Small gains that")
    print("require offsetting big rescue against big runner-cost = the signal fires on both = NOT separable.")
