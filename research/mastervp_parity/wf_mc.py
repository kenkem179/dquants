#!/usr/bin/env python3
"""
wf_mc.py — Walk-forward stability + Monte-Carlo robustness for a locked KK-MasterVP trade stream.

Input: a trades CSV emitted by the C++ backtester (entryTimeUTC, realizedUsd, exitTag, ...).
The stream is the LOCKED config replayed over the full window (train+OOS merged), so this hardens
the *already-chosen* config against (a) time-period dependence and (b) trade-sequence luck.

Two analyses:
  1) Walk-forward STABILITY — partition the stream into sequential calendar-month folds and equal-N
     folds; report per-fold n / win% / PF / net% / maxDD% (recompounded inside the fold). A robust
     edge is consistently >1 PF across folds, not carried by one period.
  2) MONTE-CARLO — de-compound each trade to a return-fraction r_i = realizedUsd_i / balance_before_i
     (fixed-fractional 1% sizing makes r_i ~stationary), then:
       - bootstrap (resample N trades WITH replacement) -> distribution of terminal-equity multiple,
         maxDD%, PF, CAGR. Tests "what if the trade MIX had been different".
       - order-shuffle (same trades, permuted order) -> maxDD% distribution. Tests path/sequence risk.
     Reports percentiles, P(profit), P(maxDD>thresholds), and risk-of-ruin (P(equity ever <= floor)).

Usage:
  python3 research/mastervp_parity/wf_mc.py --trades research/mastervp_parity/_wf_full_trades.csv \
      --label "XAU M5 LOCKED" --iters 20000 --seed 12345
"""
import argparse, csv, math, random
from collections import OrderedDict
from datetime import datetime

START_BAL = 10000.0


def load(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            t = datetime.strptime(r["entryTimeUTC"], "%Y.%m.%d %H:%M")
            rows.append((t, float(r["realizedUsd"]), r["exitTag"]))
    rows.sort(key=lambda x: x[0])
    return rows


def decompound(rows):
    """Replay realizedUsd from START_BAL; return per-trade return-fraction r_i = pnl_i / bal_before_i."""
    bal = START_BAL
    out = []
    for t, pnl, tag in rows:
        out.append((t, pnl, pnl / bal, tag))   # (time, usd, r_frac, tag)
        bal += pnl
    return out


def curve_stats(rfracs):
    """Recompound a list of return-fractions from 1.0; return (final_mult, maxdd_pct, pf, win%, n)."""
    eq, peak, maxdd = 1.0, 1.0, 0.0
    gw = gl = 0.0
    wins = 0
    for r in rfracs:
        if r > 0:
            gw += r; wins += 1
        else:
            gl += -r
        eq *= (1.0 + r)
        peak = max(peak, eq)
        maxdd = max(maxdd, (peak - eq) / peak)
    n = len(rfracs)
    pf = (gw / gl) if gl > 1e-12 else float("inf")
    return eq, 100 * maxdd, pf, (100 * wins / n if n else 0), n


def fold_report(title, folds):
    """folds: list of (label, [r_fracs]). Print the 9-ish-col scorecard per fold."""
    print(f"\n## {title}")
    print(f"{'fold':<18} {'n':>5} {'win%':>6} {'PF':>6} {'net%':>8} {'maxDD%':>7} {'recov':>6}")
    print("-" * 60)
    pf_list, net_list = [], []
    for lbl, rs in folds:
        if not rs:
            print(f"{lbl:<18} {'0':>5}  (no trades)")
            continue
        fin, dd, pf, win, n = curve_stats(rs)
        net = 100 * (fin - 1.0)
        recov = (net / dd) if dd > 1e-9 else float("inf")
        pf_list.append(pf); net_list.append(net)
        pfs = f"{pf:6.3f}" if math.isfinite(pf) else "  inf "
        rcs = f"{recov:6.2f}" if math.isfinite(recov) else "  inf "
        print(f"{lbl:<18} {n:>5} {win:>6.1f} {pfs} {net:>+8.1f} {dd:>7.1f} {rcs}")
    if pf_list:
        pos = sum(1 for p in pf_list if p > 1.0)
        print("-" * 60)
        print(f"{'folds PF>1':<18} {pos}/{len(pf_list)}   median PF {sorted(pf_list)[len(pf_list)//2]:.3f}"
              f"   worst PF {min(pf_list):.3f}   median net% {sorted(net_list)[len(net_list)//2]:+.1f}")
    return pf_list


def pctile(sorted_xs, q):
    if not sorted_xs:
        return float("nan")
    i = q * (len(sorted_xs) - 1)
    lo, hi = int(math.floor(i)), int(math.ceil(i))
    if lo == hi:
        return sorted_xs[lo]
    return sorted_xs[lo] + (sorted_xs[hi] - sorted_xs[lo]) * (i - lo)


def montecarlo(rfracs, iters, seed, ruin_floors=(0.50, 0.65, 0.80)):
    """Bootstrap (resample w/ replacement) and order-shuffle MC over return-fractions."""
    rng = random.Random(seed)
    n = len(rfracs)
    boot_fin, boot_dd, boot_pf = [], [], []
    ruin_hit = {f: 0 for f in ruin_floors}   # equity ever <= floor (fraction of START)
    for _ in range(iters):
        sample = [rfracs[rng.randrange(n)] for _ in range(n)]
        eq, peak, maxdd = 1.0, 1.0, 0.0
        gw = gl = 0.0
        floor_hit = {f: False for f in ruin_floors}
        for r in sample:
            if r > 0: gw += r
            else: gl += -r
            eq *= (1.0 + r)
            peak = max(peak, eq)
            maxdd = max(maxdd, (peak - eq) / peak)
            for f in ruin_floors:
                if eq <= f:
                    floor_hit[f] = True
        boot_fin.append(eq); boot_dd.append(100 * maxdd)
        boot_pf.append((gw / gl) if gl > 1e-12 else float("inf"))
        for f in ruin_floors:
            if floor_hit[f]:
                ruin_hit[f] += 1

    # order-shuffle: same multiset, permuted order -> isolates SEQUENCE risk on maxDD
    shuf_dd = []
    base = list(rfracs)
    for _ in range(iters):
        rng.shuffle(base)
        eq, peak, maxdd = 1.0, 1.0, 0.0
        for r in base:
            eq *= (1.0 + r); peak = max(peak, eq); maxdd = max(maxdd, (peak - eq) / peak)
        shuf_dd.append(100 * maxdd)

    return dict(fin=sorted(boot_fin), dd=sorted(boot_dd),
                pf=sorted(p for p in boot_pf if math.isfinite(p)),
                shuf_dd=sorted(shuf_dd), ruin={f: ruin_hit[f] / iters for f in ruin_floors})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trades", required=True)
    ap.add_argument("--label", default="LOCKED")
    ap.add_argument("--iters", type=int, default=20000)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--equal-folds", type=int, default=8)
    a = ap.parse_args()

    rows = load(a.trades)
    dec = decompound(rows)
    rfracs = [d[2] for d in dec]
    span = f"{rows[0][0]:%Y-%m-%d} -> {rows[-1][0]:%Y-%m-%d}"

    fin, dd, pf, win, n = curve_stats(rfracs)
    print(f"==== Walk-forward + Monte-Carlo :: {a.label} ====")
    print(f"trades {n} | span {span}")
    print(f"FULL-STREAM (recompounded 1%): final x{fin:.3f}  net {100*(fin-1):+.1f}%  "
          f"PF {pf:.3f}  win {win:.1f}%  maxDD {dd:.1f}%  recov {100*(fin-1)/dd:.2f}")

    # ---- 1) Walk-forward stability: calendar months ----
    months = OrderedDict()
    for t, pnl, r, tag in dec:
        months.setdefault(f"{t:%Y-%m}", []).append(r)
    pf_m = fold_report("Walk-forward STABILITY — calendar months", list(months.items()))

    # ---- 1b) equal-N sequential folds ----
    k = a.equal_folds
    sz = n // k
    eq_folds = []
    for i in range(k):
        lo = i * sz
        hi = n if i == k - 1 else (i + 1) * sz
        seg = dec[lo:hi]
        lbl = f"F{i+1} {seg[0][0]:%y-%m-%d}"
        eq_folds.append((lbl, [d[2] for d in seg]))
    pf_e = fold_report(f"Walk-forward STABILITY — {k} equal-N folds", eq_folds)

    # ---- 2) Monte-Carlo ----
    mc = montecarlo(rfracs, a.iters, a.seed)
    print(f"\n## MONTE-CARLO ({a.iters:,} iters, seed {a.seed}) — bootstrap resample of {n} trades")
    qs = [0.01, 0.05, 0.25, 0.50, 0.75, 0.95, 0.99]
    print("           " + "".join(f"{int(q*100):>8}%" for q in qs))
    print("net%      " + "".join(f"{100*(pctile(mc['fin'],q)-1):>+8.1f}" for q in qs))
    print("maxDD%    " + "".join(f"{pctile(mc['dd'],q):>8.1f}" for q in qs))
    print("PF        " + "".join(f"{pctile(mc['pf'],q):>8.3f}" for q in qs))
    p_profit = sum(1 for x in mc['fin'] if x > 1.0) / len(mc['fin'])
    print(f"\nP(profit)            = {100*p_profit:.1f}%")
    print(f"P(maxDD > 15%)       = {100*sum(1 for x in mc['dd'] if x>15)/len(mc['dd']):.1f}%")
    print(f"P(maxDD > 20%)       = {100*sum(1 for x in mc['dd'] if x>20)/len(mc['dd']):.1f}%")
    print(f"P(maxDD > 30%)       = {100*sum(1 for x in mc['dd'] if x>30)/len(mc['dd']):.1f}%")
    print("Risk-of-ruin (equity ever falls to):")
    for f, p in mc['ruin'].items():
        print(f"   <= {int(f*100)}% of start  : {100*p:.2f}%")
    print(f"\n## ORDER-SHUFFLE (sequence risk) maxDD% percentiles")
    print("           " + "".join(f"{int(q*100):>8}%" for q in qs))
    print("maxDD%    " + "".join(f"{pctile(mc['shuf_dd'],q):>8.1f}" for q in qs))
    print(f"shuffle worst-case maxDD (max over {a.iters:,}): {mc['shuf_dd'][-1]:.1f}%")


if __name__ == "__main__":
    main()
