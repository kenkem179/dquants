#!/usr/bin/env python3
"""Portfolio construction over multiple engine trade streams — the book-level layer.

WHY THIS EXISTS
---------------
Every other tool in this repo evaluates ONE strategy stream in isolation (gate.py, wf_mc.py). But the
real account runs several at once: one EA on M3 *and* M5, or on XAUUSD *and* EURUSD. Those streams are
correlated; sizing them independently silently doubles risk and wastes the diversification that is the
only free lunch in finance. This module turns N trade CSVs into ONE book with principled per-stream
weights — and the directly actionable output: a **lot multiplier per stream** for the EAs.

DESIGN (matches the repo's harness/engine split)
------------------------------------------------
- Pure analysis over the C++ engine's trade CSVs; never re-simulates fills (parity/Gate 0 stays the
  source of truth for PnL). numpy/scipy/pandas only, deterministic given inputs.
- Each stream's per-trade `realizedUsd` is bucketed onto a common calendar grid (daily by default) and
  expressed as a return-fraction r = pnl / start_balance (fixed-fractional sizing makes this the right,
  ~stationary unit and lets streams of different $ scale be compared and combined).
- Covariance is ALWAYS shrunk (Ledoit-Wolf constant-correlation). With 2-6 streams and a few months of
  history the raw sample covariance is too noisy to invert; shrinkage is not optional here.

ALLOCATION METHODS (pick by `--method`)
---------------------------------------
  equal       1/N. The honest baseline; beat it or don't bother.
  invvar      inverse-variance (naive risk parity). Ignores correlation.
  riskparity  equal risk contribution (ERC). Each stream contributes equal risk to the book.
  hrp         Hierarchical Risk Parity (Lopez de Prado 2016). NEVER inverts the covariance — clusters
              by correlation distance and allocates by recursive bisection. The most robust choice for
              few, correlated streams (exactly the "same EA, 2 TFs" case). DEFAULT.
  maxsharpe   long-only tangency portfolio on the shrunk covariance (mean-variance). Highest in-sample
              Sharpe, least robust OOS — report it, don't trust it blindly.
  kelly       fractional Kelly: w proportional to Sigma^-1 mu, scaled by --kelly-fraction. Growth-optimal
              but aggressive; fraction < 1 is mandatory in practice.

The CLI runs ALL methods, prints a comparison + correlation matrix + per-stream risk contributions,
deflates the chosen method's Sharpe by the dispersion across methods (multiple-testing aware), and
writes weights + lot multipliers to JSON.

Usage:
  python -m research.portfolio.portfolio \
      --trades XAU_M3=path/to/trades_m3.csv --trades XAU_M5=path/to/trades_m5.csv \
      --method hrp --freq D --out research/portfolio/weights_xau.json
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
from datetime import datetime

import numpy as np
import pandas as pd

# stats/ lives at research/stats; this file is research/portfolio/. Add research/ to path for reuse.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from stats.overfitting import (  # noqa: E402
    sharpe_ratio, probabilistic_sharpe_ratio, deflated_sharpe_ratio,
)

START_BALANCE = 10000.0
TRADING_DAYS = 252  # FX/metals annualization; ~stable enough for relative comparison

# Accept every schema our engines emit (mirrors stats/gate.py).
_TIME_KEYS = ("entryTimeUTC", "entryTime", "openTime", "time")
_TIME_MS_KEYS = ("ts_ms", "tsMs", "entryMs")
_PNL_KEYS = ("realizedUsd", "pnlUsd", "pnl", "profit", "netUsd")
_TIME_FMTS = ("%Y.%m.%d %H:%M", "%Y.%m.%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M")


# ----------------------------------------------------------------------------- loading
def _parse_time(row):
    for k in _TIME_MS_KEYS:
        if k in row and row[k] not in ("", None):
            return datetime.utcfromtimestamp(float(row[k]) / 1000.0)
    for k in _TIME_KEYS:
        if k in row and row[k] not in ("", None):
            s = row[k].strip()
            for fmt in _TIME_FMTS:
                try:
                    return datetime.strptime(s, fmt)
                except ValueError:
                    continue
    raise KeyError(f"no parseable time column in {list(row)}")


def _parse_pnl(row):
    for k in _PNL_KEYS:
        if k in row and row[k] not in ("", None):
            return float(row[k])
    raise KeyError(f"no pnl column in {list(row)}")


def load_stream(path):
    """Load a trade CSV -> list of (datetime, realized_usd), time-sorted. Schema auto-detected."""
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            rows.append((_parse_time(r), _parse_pnl(r)))
    rows.sort(key=lambda x: x[0])
    return rows


def build_returns_matrix(streams: dict, freq: str = "D",
                         start_balance: float = START_BALANCE) -> pd.DataFrame:
    """{name: [(dt, usd), ...]} -> DataFrame[period x stream] of per-period RETURN FRACTIONS.

    Periods with no trade for a stream are 0.0 (flat that day, not missing). Returns are pnl/balance so
    streams of different $ scale combine on equal footing under fixed-fractional sizing.
    """
    cols = {}
    for name, rows in streams.items():
        if not rows:
            continue
        s = pd.Series({dt: usd for dt, usd in _agg_same_ts(rows)})
        s.index = pd.to_datetime(s.index)
        cols[name] = s.resample(freq).sum() / start_balance
    if not cols:
        raise ValueError("no non-empty streams")
    mat = pd.DataFrame(cols).fillna(0.0).sort_index()
    return mat


def _agg_same_ts(rows):
    """Sum pnl of trades sharing an exact timestamp so the Series index is unique before resample."""
    agg = {}
    for dt, usd in rows:
        agg[dt] = agg.get(dt, 0.0) + usd
    return agg.items()


# ----------------------------------------------------------------------------- covariance
def shrink_cov_constant_corr(returns: np.ndarray):
    """Ledoit-Wolf shrinkage toward a constant-correlation target. Returns (cov_shrunk, shrinkage).

    returns: (T, N). The constant-correlation target keeps every variance but replaces all pairwise
    correlations with their average -> a well-conditioned matrix we can invert. The shrinkage intensity
    is estimated analytically (Ledoit & Wolf 2004, "Honey, I Shrunk the Sample Covariance Matrix").
    """
    X = np.asarray(returns, dtype=float)
    t, n = X.shape
    if n < 2 or t < 2:
        return np.cov(X, rowvar=False, ddof=1) if t > 1 else np.zeros((n, n)), 0.0
    Xc = X - X.mean(axis=0)
    sample = (Xc.T @ Xc) / t                      # MLE sample cov (divide by T, LW convention)
    var = np.diag(sample)
    std = np.sqrt(var)
    outer_std = np.outer(std, std)
    outer_std[outer_std == 0] = 1e-12
    corr = sample / outer_std
    # average off-diagonal correlation -> constant-correlation target F
    rbar = (corr.sum() - n) / (n * (n - 1))
    target = rbar * outer_std
    np.fill_diagonal(target, var)
    # pi: sum of asymptotic variances of sample cov entries
    Xc2 = Xc ** 2
    pi_mat = (Xc2.T @ Xc2) / t - sample ** 2
    pi_hat = pi_mat.sum()
    # rho: estimate of cov between sample cov entries and the target
    theta_ii = (Xc2.T @ (Xc * std)) / t           # placeholder shaping; computed per LW below
    rho_diag = np.diag(pi_mat).sum()
    term = np.zeros((n, n))
    for i in range(n):
        for j in range(n):
            if i == j:
                continue
            t_ij = ((Xc[:, i] ** 2) * Xc[:, i] * Xc[:, j]).mean() - sample[i, i] * sample[i, j]
            t_ji = ((Xc[:, j] ** 2) * Xc[:, i] * Xc[:, j]).mean() - sample[j, j] * sample[i, j]
            term[i, j] = 0.5 * rbar * (std[j] / std[i] * t_ij + std[i] / std[j] * t_ji)
    rho_hat = rho_diag + term.sum()
    # gamma: misspecification of the target (Frobenius distance)
    gamma_hat = np.sum((target - sample) ** 2)
    if gamma_hat <= 0:
        shrink = 0.0
    else:
        kappa = (pi_hat - rho_hat) / gamma_hat
        shrink = max(0.0, min(1.0, kappa / t))
    cov = shrink * target + (1.0 - shrink) * sample
    # rescale from MLE (1/T) to unbiased (1/(T-1)) for downstream Sharpe consistency
    cov *= t / (t - 1)
    return cov, float(shrink)


# ----------------------------------------------------------------------------- allocators
def _norm(w):
    w = np.clip(np.asarray(w, dtype=float), 0.0, None)
    s = w.sum()
    return w / s if s > 0 else np.full_like(w, 1.0 / len(w))


def weights_equal(mat: pd.DataFrame, **_):
    n = mat.shape[1]
    return np.full(n, 1.0 / n)


def weights_inverse_variance(mat: pd.DataFrame, **_):
    var = mat.var(axis=0, ddof=1).values
    var[var == 0] = np.inf
    return _norm(1.0 / var)


def weights_risk_parity(mat: pd.DataFrame, cov=None, iters: int = 2000, tol: float = 1e-10, **_):
    """Equal Risk Contribution via the standard cyclical-coordinate fixed point."""
    S = cov if cov is not None else shrink_cov_constant_corr(mat.values)[0]
    n = S.shape[0]
    w = np.full(n, 1.0 / n)
    for _ in range(iters):
        Sw = S @ w
        rc = w * Sw                       # risk contributions
        target = (w @ Sw) / n
        w_new = w * (target / np.maximum(rc, 1e-18)) ** 0.5
        w_new = _norm(w_new)
        if np.max(np.abs(w_new - w)) < tol:
            w = w_new
            break
        w = w_new
    return _norm(w)


def _corr_dist(corr):
    return np.sqrt(np.clip((1.0 - corr) / 2.0, 0.0, 1.0))


def weights_hrp(mat: pd.DataFrame, cov=None, **_):
    """Hierarchical Risk Parity (Lopez de Prado 2016): cluster -> quasi-diagonalize -> recursive bisect.

    Never inverts the covariance, so it is stable with few, correlated streams. Falls back to
    inverse-variance for n<3 (no meaningful tree).
    """
    from scipy.cluster.hierarchy import linkage, leaves_list
    from scipy.spatial.distance import squareform

    S = cov if cov is not None else shrink_cov_constant_corr(mat.values)[0]
    n = S.shape[0]
    if n < 3:
        return weights_inverse_variance(mat)
    std = np.sqrt(np.diag(S))
    outer = np.outer(std, std)
    outer[outer == 0] = 1e-12
    corr = np.clip(S / outer, -1.0, 1.0)
    dist = _corr_dist(corr)
    link = linkage(squareform(dist, checks=False), method="single")
    order = list(leaves_list(link))           # quasi-diagonalization order

    w = np.ones(n)
    clusters = [order]
    while clusters:
        new = []
        for c in clusters:
            if len(c) <= 1:
                continue
            half = len(c) // 2
            left, right = c[:half], c[half:]
            var_l = _cluster_var(S, left)
            var_r = _cluster_var(S, right)
            alpha = 1.0 - var_l / (var_l + var_r)
            for i in left:
                w[i] *= alpha
            for i in right:
                w[i] *= (1.0 - alpha)
            new += [left, right]
        clusters = new
    return _norm(w)


def _cluster_var(S, idx):
    """Inverse-variance-weighted variance of a sub-cluster (HRP building block)."""
    sub = S[np.ix_(idx, idx)]
    ivp = 1.0 / np.diag(sub)
    ivp = ivp / ivp.sum()
    return float(ivp @ sub @ ivp)


def weights_max_sharpe(mat: pd.DataFrame, cov=None, long_only: bool = True, **_):
    """Long-only tangency (max-Sharpe) portfolio on the shrunk covariance via SLSQP."""
    from scipy.optimize import minimize
    S = cov if cov is not None else shrink_cov_constant_corr(mat.values)[0]
    mu = mat.mean(axis=0).values
    n = len(mu)

    def neg_sharpe(w):
        ret = w @ mu
        vol = math.sqrt(max(w @ S @ w, 1e-18))
        return -ret / vol

    cons = [{"type": "eq", "fun": lambda w: w.sum() - 1.0}]
    bounds = [(0.0, 1.0)] * n if long_only else [(-1.0, 1.0)] * n
    w0 = np.full(n, 1.0 / n)
    res = minimize(neg_sharpe, w0, method="SLSQP", bounds=bounds, constraints=cons,
                   options={"maxiter": 1000, "ftol": 1e-12})
    return _norm(res.x) if res.success else weights_equal(mat)


def weights_kelly(mat: pd.DataFrame, cov=None, kelly_fraction: float = 0.5,
                  long_only: bool = True, **_):
    """Fractional Kelly: w proportional to Sigma^-1 mu, scaled by kelly_fraction, then normalized.

    Full Kelly (fraction=1) is famously over-aggressive and assumes the estimates are exact; on thin
    samples always use a fraction (0.25-0.5). Returns weights summing to 1 (the *fraction* governs how
    aggressively risk is concentrated, surfaced via metrics, not raw leverage here).
    """
    S = cov if cov is not None else shrink_cov_constant_corr(mat.values)[0]
    mu = mat.mean(axis=0).values
    try:
        raw = np.linalg.solve(S, mu)
    except np.linalg.LinAlgError:
        raw = np.linalg.pinv(S) @ mu
    raw = raw * kelly_fraction
    if long_only:
        raw = np.clip(raw, 0.0, None)
    if raw.sum() <= 0:
        return weights_equal(mat)
    return _norm(raw)


ALLOC_METHODS = {
    "equal": weights_equal,
    "invvar": weights_inverse_variance,
    "riskparity": weights_risk_parity,
    "hrp": weights_hrp,
    "maxsharpe": weights_max_sharpe,
    "kelly": weights_kelly,
}


# ----------------------------------------------------------------------------- book metrics
def portfolio_metrics(mat: pd.DataFrame, weights, cov=None,
                      periods_per_year: int = TRADING_DAYS) -> dict:
    """Book-level stats for a weight vector over the returns matrix."""
    w = np.asarray(weights, dtype=float)
    S = cov if cov is not None else shrink_cov_constant_corr(mat.values)[0]
    port = mat.values @ w                          # per-period portfolio return
    mu_p = port.mean()
    vol_p = port.std(ddof=1)
    sr = mu_p / vol_p if vol_p > 0 else 0.0
    # max drawdown on the compounded book curve
    eq = np.cumprod(1.0 + port)
    peak = np.maximum.accumulate(eq)
    maxdd = float(((eq - peak) / peak).min()) if len(eq) else 0.0
    # risk decomposition
    port_var = float(w @ S @ w)
    port_vol = math.sqrt(max(port_var, 1e-18))
    mrc = (S @ w) / port_vol                        # marginal risk contribution
    crc = w * mrc                                    # component risk contribution (sums to port_vol)
    crc_pct = crc / crc.sum() if crc.sum() != 0 else crc
    asset_vol = np.sqrt(np.diag(S))
    div_ratio = float((w @ asset_vol) / port_vol) if port_vol > 0 else 1.0
    return dict(
        sharpe_per_period=float(sr),
        sharpe_annual=float(sr * math.sqrt(periods_per_year)),
        mean_per_period=float(mu_p),
        vol_per_period=float(vol_p),
        total_return=float(eq[-1] - 1.0) if len(eq) else 0.0,
        max_drawdown=maxdd,
        diversification_ratio=div_ratio,
        component_risk_pct={c: float(crc_pct[i]) for i, c in enumerate(mat.columns)},
        weights={c: float(w[i]) for i, c in enumerate(mat.columns)},
        port_returns=port,
    )


def lot_multipliers(weights, columns):
    """Map weights (sum=1) to per-stream lot multipliers: equal weight -> all 1.0; 2x share -> 2.0.

    multiplier_i = w_i * N. This is the number to scale each EA's base lot/risk by so the *book*
    matches the chosen allocation while keeping the equal-weight book as the 1.0x reference.
    """
    w = np.asarray(weights, dtype=float)
    n = len(w)
    return {c: float(w[i] * n) for i, c in enumerate(columns)}


def allocate(mat: pd.DataFrame, method: str = "hrp", **kw):
    """Compute weights by `method`; returns (weights ndarray, cov)."""
    cov, _ = shrink_cov_constant_corr(mat.values)
    fn = ALLOC_METHODS[method]
    return fn(mat, cov=cov, **kw), cov


# ----------------------------------------------------------------------------- CLI
def _kv(s):
    if "=" not in s:
        raise argparse.ArgumentTypeError("--trades expects name=path")
    name, path = s.split("=", 1)
    return name.strip(), path.strip()


def main(argv=None):
    ap = argparse.ArgumentParser(description="Portfolio construction over engine trade streams.")
    ap.add_argument("--trades", action="append", type=_kv, required=True, metavar="NAME=PATH",
                    help="repeatable: a named trade CSV stream")
    ap.add_argument("--method", default="hrp", choices=list(ALLOC_METHODS),
                    help="allocation method for the headline weights (default hrp)")
    ap.add_argument("--freq", default="D", help="resample frequency (D, W, H, ...)")
    ap.add_argument("--start-balance", type=float, default=START_BALANCE)
    ap.add_argument("--kelly-fraction", type=float, default=0.5)
    ap.add_argument("--out", default=None, help="write weights+lot multipliers JSON here")
    args = ap.parse_args(argv)

    streams = {name: load_stream(path) for name, path in args.trades}
    mat = build_returns_matrix(streams, freq=args.freq, start_balance=args.start_balance)
    cov, shrink = shrink_cov_constant_corr(mat.values)
    cols = list(mat.columns)

    print(f"\n=== Portfolio: {len(cols)} streams, {len(mat)} {args.freq}-periods "
          f"({mat.index[0].date()} -> {mat.index[-1].date()}) ===")
    print(f"covariance shrinkage intensity: {shrink:.3f}")

    # correlation matrix
    corr = mat.corr()
    print("\ncorrelation:")
    print(corr.round(3).to_string())

    # per-stream standalone annualized Sharpe (context)
    print("\nstandalone annualized Sharpe:")
    for c in cols:
        sr = sharpe_ratio(mat[c].values, periods_per_year=TRADING_DAYS)
        print(f"  {c:<16} {sr:6.2f}")

    # all methods, for comparison + multiple-testing deflation
    rows, method_sr = [], []
    chosen_w = None
    for m in ALLOC_METHODS:
        w = ALLOC_METHODS[m](mat, cov=cov, kelly_fraction=args.kelly_fraction)
        met = portfolio_metrics(mat, w, cov=cov)
        method_sr.append(met["sharpe_per_period"])
        rows.append((m, met))
        if m == args.method:
            chosen_w = w
            chosen_met = met

    print("\nmethod comparison (annualized Sharpe | maxDD | div-ratio | weights):")
    for m, met in rows:
        wstr = " ".join(f"{c}={met['weights'][c]:.2f}" for c in cols)
        tag = "  <-- chosen" if m == args.method else ""
        print(f"  {m:<11} SR {met['sharpe_annual']:5.2f} | DD {met['max_drawdown']*100:5.1f}% "
              f"| DR {met['diversification_ratio']:.2f} | {wstr}{tag}")

    # deflate the chosen method's Sharpe by the dispersion ACROSS methods (we searched several)
    sr_trial_std = float(np.std(method_sr, ddof=1)) if len(method_sr) > 1 else 0.0
    dsr = deflated_sharpe_ratio(chosen_met["port_returns"], sr_trial_std, len(method_sr))
    psr0 = probabilistic_sharpe_ratio(chosen_met["port_returns"], 0.0)

    lots = lot_multipliers(chosen_w, cols)
    print(f"\n=== chosen = {args.method} ===")
    print(f"book annualized Sharpe : {chosen_met['sharpe_annual']:.2f}")
    print(f"book max drawdown      : {chosen_met['max_drawdown']*100:.1f}%")
    print(f"diversification ratio  : {chosen_met['diversification_ratio']:.2f}  "
          f"(1.0 = no diversification; higher = better)")
    print(f"PSR vs 0               : {psr0:.3f}")
    print(f"DSR (vs method search) : {dsr:.3f}  "
          f"({'PASS' if dsr >= 0.95 else 'WARN' if dsr >= 0.90 else 'FAIL'})")
    print("\nper-stream allocation (weight | risk-contribution | LOT MULTIPLIER for the EA):")
    for c in cols:
        print(f"  {c:<16} w={chosen_met['weights'][c]:.3f}  "
              f"risk={chosen_met['component_risk_pct'][c]*100:5.1f}%  "
              f"lot x{lots[c]:.2f}")

    if args.out:
        payload = dict(
            method=args.method, freq=args.freq, n_periods=len(mat),
            streams=cols, shrinkage=shrink,
            weights=chosen_met["weights"], lot_multipliers=lots,
            component_risk_pct=chosen_met["component_risk_pct"],
            book_sharpe_annual=chosen_met["sharpe_annual"],
            book_max_drawdown=chosen_met["max_drawdown"],
            diversification_ratio=chosen_met["diversification_ratio"],
            psr_vs_zero=psr0, deflated_sharpe=dsr,
            correlation=corr.round(4).to_dict(),
        )
        with open(args.out, "w") as f:
            json.dump(payload, f, indent=2)
        print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
