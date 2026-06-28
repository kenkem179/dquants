"""Ornstein-Uhlenbeck half-life of mean reversion.

Technique source: Ernest Chan, *Quantitative Trading* (2nd ed.), Ch.7
("Stationarity and Cointegration" / Example 7.5). The OU model

    dz = theta * (mu - z) dt + sigma dW

is fit by regressing the one-step change dz_t = z_t - z_{t-1} on the lagged
level z_{t-1}:

    dz_t = beta * z_{t-1} + c + eps      (beta = -theta)

For a mean-reverting series beta < 0, and the half-life of reversion is

    half_life = -ln(2) / beta

i.e. the expected number of bars for a deviation from mu to decay to half.

Why this matters for dquants (READ THIS before using it):
- It gives a *statistically robust* mean-reversion holding period / time-stop
  estimated from the WHOLE series, not from the handful of actual trades
  (which is data-snooping-prone). Use it to bound MasterVP reversion-book
  holding time (BUILD-PLAN M6) and as a regime feature (P1).
- A POSITIVE or insignificant beta means the series is NOT mean-reverting on
  that horizon -> do not impose a reversion time-stop; treat as trending.
- This is a DIAGNOSTIC, not a lock. Half-life drifts across regimes; estimate
  it per-fold/per-quarter and never trust a single full-sample number.

No hard dependencies beyond numpy.
"""
from __future__ import annotations

import numpy as np


def half_life(series, *, min_points: int = 30):
    """Estimate the OU half-life (in bars) of a 1-D series.

    Returns a dict with: beta, half_life, mu, t_stat (of beta), n, and
    is_mean_reverting (beta significantly < 0). half_life is np.inf when the
    series is not mean-reverting (beta >= 0).
    """
    z = np.asarray(series, dtype=float)
    z = z[np.isfinite(z)]
    if z.size < min_points:
        raise ValueError(f"need >= {min_points} finite points, got {z.size}")

    z_lag = z[:-1]
    dz = np.diff(z)

    # OLS dz = beta * z_lag + c
    X = np.column_stack([z_lag, np.ones_like(z_lag)])
    coef, *_ = np.linalg.lstsq(X, dz, rcond=None)
    beta, c = float(coef[0]), float(coef[1])

    # standard error of beta for a t-stat (so we don't trust noise)
    resid = dz - X @ coef
    dof = max(z_lag.size - 2, 1)
    sigma2 = float(resid @ resid) / dof
    xtx_inv = np.linalg.inv(X.T @ X)
    se_beta = float(np.sqrt(sigma2 * xtx_inv[0, 0]))
    t_stat = beta / se_beta if se_beta > 0 else 0.0

    if beta < 0:
        hl = -np.log(2) / beta
        mu = -c / beta
    else:
        hl = np.inf
        mu = float(np.mean(z))

    return {
        "beta": beta,
        "half_life": hl,
        "mu": mu,
        "t_stat": t_stat,
        "n": int(z.size),
        # beta significantly negative (one-sided ~95%)
        "is_mean_reverting": bool(beta < 0 and t_stat < -1.65),
    }


def _is_float(x):
    try:
        float(x)
        return True
    except (TypeError, ValueError):
        return False


def _self_test():
    rng = np.random.default_rng(7)
    # synthetic OU with known half-life: theta=0.05 -> hl = ln2/0.05 ~ 13.86
    theta, mu, sigma, n = 0.05, 100.0, 0.5, 5000
    z = np.empty(n)
    z[0] = mu
    for t in range(1, n):
        z[t] = z[t - 1] + theta * (mu - z[t - 1]) + sigma * rng.standard_normal()
    out = half_life(z)
    expected = np.log(2) / theta
    assert out["is_mean_reverting"], out
    assert abs(out["half_life"] - expected) / expected < 0.20, (out, expected)

    # a pure random walk must NOT read as mean-reverting
    rw = np.cumsum(rng.standard_normal(5000))
    out_rw = half_life(rw)
    assert not out_rw["is_mean_reverting"], out_rw
    print(f"self-test OK: OU hl={out['half_life']:.2f} (expected {expected:.2f}); "
          f"random-walk mean_reverting={out_rw['is_mean_reverting']}")


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description="OU half-life of mean reversion")
    ap.add_argument("--csv", help="CSV file with a numeric column to test")
    ap.add_argument("--col", help="column name (default: first numeric column)")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test or not args.csv:
        _self_test()
    else:
        import csv as _csv

        with open(args.csv) as fh:
            rows = list(_csv.DictReader(fh))
        col = args.col or next(
            k for k in rows[0]
            if _is_float(rows[0][k])
        )
        vals = [float(r[col]) for r in rows if _is_float(r[col])]
        print(half_life(vals))
