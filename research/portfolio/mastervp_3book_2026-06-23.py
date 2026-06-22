#!/usr/bin/env python3
"""MasterVP 3-instance portfolio study — XAU M5 + BTC M5 + BTC M3 on ONE account.

The user runs MasterVP on three charts at once and asks: how to maximize joint profit WITHOUT
conflicts. "Conflict" on a single prop account = (1) correlated drawdowns eating the 4.4% daily /
9% account caps, (2) one instrument dominating the book's risk, (3) sizing each stream as if it
were alone, which silently sums risk.

This uses the MT5-CONFIRMED trade streams (not the engine — its exit model is flagged directionally
unreliable, especially on BTC). All three are sliced to their COMMON window so correlations are fair.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from portfolio import portfolio as P
import numpy as np, pandas as pd

START = 10000.0
STREAMS = {
    "XAU_M5": "research/mastervp_parity/mt5_runs/RUN_2026-06-20_xau_m5_T2_hourblock/trades_mt5_xau_m5.csv",
    "BTC_M5": "research/mastervp_parity/mt5_runs/RUN_2026-06-22_btc_m5_lock_confirm/trades_mt5_btc_m5.csv",
    "BTC_M3": "research/monster_parity/mt5_runs/RUN_2026-06-20_btc_m3_parity/trades_mt5_btc_m3.csv",
}

raw = {k: P.load_stream(v) for k, v in STREAMS.items()}
# common window = latest start, earliest end across the three streams
lo = max(r[0][0] for r in raw.values())
hi = min(r[-1][0] for r in raw.values())
print(f"common window: {lo.date()} -> {hi.date()}\n")
clipped = {k: [(d, u) for d, u in rows if lo <= d <= hi] for k, rows in raw.items()}

mat = P.build_returns_matrix(clipped, freq="D")          # daily return-fraction per stream
cov, shrink = P.shrink_cov_constant_corr(mat.values)
cols = list(mat.columns)

# ---- standalone economics on the common window
print("standalone (common window, each as if alone on $10k):")
for c in cols:
    pnl = mat[c].values * START
    g, l = pnl[pnl > 0].sum(), -pnl[pnl < 0].sum()
    eq = np.cumprod(1 + mat[c].values); dd = ((eq - np.maximum.accumulate(eq)) / np.maximum.accumulate(eq)).min()
    print(f"  {c:<7} net=${pnl.sum():>8,.0f}  PF={g/l if l else 0:5.3f}  "
          f"ann.Sharpe={P.sharpe_ratio(mat[c].values, periods_per_year=252):5.2f}  maxDD={dd*100:5.1f}%")

print("\ncorrelation (daily return):")
print(mat.corr().round(3).to_string())

# ---- allocation methods
print("\nallocation methods (book annualized Sharpe | book maxDD | div-ratio | weights):")
results = {}
for m in P.ALLOC_METHODS:
    w = P.ALLOC_METHODS[m](mat, cov=cov)
    met = P.portfolio_metrics(mat, w, cov=cov)
    results[m] = (w, met)
    ws = " ".join(f"{c}={met['weights'][c]:.2f}" for c in cols)
    print(f"  {m:<11} SR {met['sharpe_annual']:5.2f} | DD {met['max_drawdown']*100:5.1f}% "
          f"| DR {met['diversification_ratio']:.2f} | {ws}")

# ---- CONFLICT METRICS: equal-size book vs prop caps, and XAU-only baseline
print("\n=== conflict check: combined book vs prop caps (4.4% daily / 9% account) ===")
def book_stats(weights):
    w = np.asarray(weights)
    port = mat.values @ w                       # daily book return fraction
    eq = np.cumprod(1 + port)
    dd = ((eq - np.maximum.accumulate(eq)) / np.maximum.accumulate(eq))
    return dict(net=port.sum()*START, worst_day=port.min(), maxdd=dd.min(),
                days_over_4_4=(port < -0.044).sum(), total=eq[-1]-1)

scenarios = {
    "XAU-only (1.0x)":        np.array([1,0,0.]),
    "equal full-size (1/1/1)": np.array([1,1,1.]),   # each at its own full risk -> book = sum
    "HRP weights x3":          results["hrp"][0]*3,  # weights*N keeps per-stream full-size ref
    "risk-parity x3":          results["riskparity"][0]*3,
}
for name, w in scenarios.items():
    s = book_stats(w)
    print(f"  {name:<24} net=${s['net']:>8,.0f}  worstDay={s['worst_day']*100:6.2f}%  "
          f"maxDD={s['maxdd']*100:5.1f}%  days<-4.4%={s['days_over_4_4']}")

# ---- per-EA lot multipliers under the robust default (HRP)
w_hrp, met_hrp = results["hrp"]
lots = P.lot_multipliers(w_hrp, cols)
print("\n=== recommended (HRP) lot multipliers — scale each EA's base risk by this ===")
for c in cols:
    print(f"  {c:<7} weight={met_hrp['weights'][c]:.3f}  risk-contribution={met_hrp['component_risk_pct'][c]*100:5.1f}%  lot x{lots[c]:.2f}")
