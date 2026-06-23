#!/usr/bin/env python3
"""Cross-strategy portfolio — MasterVP (XAU M5 + BTC M5) + KenKem (XAU M1) on ONE account.

Follow-up to mastervp_3book: drop BTC M3 (redundant w/ BTC M5), add KenKem D5-E4Long as a
genuinely different strategy (Ichimoku/EMA entries) on XAU M1 — the candidate uncorrelated leg.
MT5-confirmed streams only. Common window = overlap of all three.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from portfolio import portfolio as P
import numpy as np

START = 10000.0
STREAMS = {
    # full ~17mo MT5 lock-confirm run (1958 trades) to maximize overlap with KenKem
    "XAU_M5_MVP": "research/mastervp_parity/mt5_runs/RUN_2026-06-22_xau_m5_lock_confirm/trades_mt5_xau_m5.csv",
    "BTC_M5_MVP": "research/mastervp_parity/mt5_runs/RUN_2026-06-22_btc_m5_lock_confirm/trades_mt5_btc_m5.csv",
    "KENKEM_M1":  "research/kenkem_parity/mt5_runs/2026-06-22_D5-E4Long/trades_XAUUSD-Exness-KK.csv",
}

raw = {k: P.load_stream(v) for k, v in STREAMS.items()}
lo = max(r[0][0] for r in raw.values())
hi = min(r[-1][0] for r in raw.values())
print(f"common window: {lo.date()} -> {hi.date()}\n")
clip = {k: [(d, u) for d, u in rows if lo <= d <= hi] for k, rows in raw.items()}

mat = P.build_returns_matrix(clip, freq="D")
cov, shrink = P.shrink_cov_constant_corr(mat.values)
cols = list(mat.columns)

print("standalone (common window, each as if alone on $10k):")
for c in cols:
    pnl = mat[c].values * START
    g, l = pnl[pnl > 0].sum(), -pnl[pnl < 0].sum()
    eq = np.cumprod(1 + mat[c].values); dd = ((eq - np.maximum.accumulate(eq)) / np.maximum.accumulate(eq)).min()
    ntr = len(clip[c])
    print(f"  {c:<11} n={ntr:<5} net=${pnl.sum():>8,.0f}  PF={g/l if l else 0:5.3f}  "
          f"ann.Sharpe={P.sharpe_ratio(mat[c].values, periods_per_year=252):5.2f}  maxDD={dd*100:5.1f}%")

print("\ncorrelation (daily return):")
print(mat.corr().round(3).to_string())

print("\nallocation methods (book ann.Sharpe | book maxDD | div-ratio | weights):")
results = {}
for m in P.ALLOC_METHODS:
    w = P.ALLOC_METHODS[m](mat, cov=cov)
    met = P.portfolio_metrics(mat, w, cov=cov)
    results[m] = (w, met)
    ws = " ".join(f"{c}={met['weights'][c]:.2f}" for c in cols)
    print(f"  {m:<11} SR {met['sharpe_annual']:5.2f} | DD {met['max_drawdown']*100:5.1f}% "
          f"| DR {met['diversification_ratio']:.2f} | {ws}")

def book_stats(weights):
    w = np.asarray(weights, float); port = mat.values @ w; eq = np.cumprod(1 + port)
    dd = ((eq - np.maximum.accumulate(eq)) / np.maximum.accumulate(eq))
    return port.sum()*START, port.min(), dd.min(), (port < -0.044).sum()

print("\n=== conflict check vs prop caps (4.4% daily / 9% account) ===")
for name, w in {
    "XAU_M5 only":              [1, 0, 0],
    "XAU_M5 + KenKem":          [1, 0, 1],
    "all three full-size":      [1, 1, 1],
    "maxsharpe x3":             results["maxsharpe"][0]*3,
}.items():
    net, wd, dd, brk = book_stats(w)
    print(f"  {name:<22} net=${net:>8,.0f}  worstDay={wd*100:6.2f}%  maxDD={dd*100:5.1f}%  days<-4.4%={brk}")

print("\n=== prop-cap-aware sizing (scale so combined worst-day = -4.4%) ===")
for name, w in {
    "XAU_M5 only":             [1, 0, 0],
    "XAU_M5 + KenKem":         [1, 0, 1],
    "XAU_M5 + KenKem + BTC_M5(0.5)": [1, 0.5, 1],
}.items():
    w = np.array(w, float); _, wd, _, _ = book_stats(w); s = 0.044/abs(wd) if wd < 0 else 1
    net, wd2, dd2, _ = book_stats(w*s)
    print(f"  {name:<32} scale x{s:.2f} -> net=${net:>8,.0f}  maxDD={dd2*100:5.1f}%")

w_ms, met_ms = results["maxsharpe"]
lots = P.lot_multipliers(w_ms, cols)
print("\n=== edge-aware (max-Sharpe) lot multipliers — scale each EA's base risk ===")
for c in cols:
    print(f"  {c:<11} weight={met_ms['weights'][c]:.3f}  risk-contrib={met_ms['component_risk_pct'][c]*100:5.1f}%  lot x{lots[c]:.2f}")
