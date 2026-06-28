"""Empirical, fat-tail-aware Kelly position sizing from a trade stream.

Technique source: Ernest Chan, *Quantitative Trading* (2nd ed.), Ch.6
("Money and Risk Management"). Chan's closed form f = m / s^2 assumes Gaussian
returns. XAU/BTC trade returns are emphatically NOT Gaussian (documented fat
tails -- see memory [[mastervp-profit-lock-ladder]]), so a Gaussian Kelly
OVER-bets the tails. This module therefore computes the *empirical* Kelly by
directly maximizing the historical log-growth over the realized per-trade
R-multiple distribution -- no Gaussian assumption:

    g(f) = (1/N) * sum_i ln(1 + f * R_i)        maximize over f in (0, f_max)

where R_i is the realized profit of trade i in units of risk (R-multiple), and
f is the fraction of equity risked per trade. The maximizer f* is the full
empirical Kelly fraction-of-equity-to-risk-per-trade.

We then report the THREE numbers Chan says actually matter for survival:
  1. full Kelly f*               (growth-optimal, never trade this)
  2. half Kelly f*/2             (Chan's standard safety haircut)
  3. drawdown-capped leverage    = min(half-Kelly, max_tol_dd / worst_loss_R)
     -- the smaller of half-Kelly and the leverage the WORST historical loss
     allows under your max tolerable single-trade drawdown. Chan: "the leverage
     to use is always the smaller of the half-Kelly leverage and the maximum
     leverage obtained using the worst historical loss."

Plus a Monte-Carlo risk-of-ruin at the chosen fraction, because the whole point
of Kelly is to AVOID ruin (ruin => long-term growth is zero, regardless of edge).

CAVEATS (mutual-skepticism contract -- do not skip):
- This is a SIZING DIAGNOSTIC computed on historical trades. It is NOT a lock
  and must be recomputed per-quarter; a fraction optimal on 2025 can ruin you in
  2026 if the edge decays. Pair with the Kelly delever rule: as trailing mean R
  -> 0, f* -> 0 (cut size on a degrading model; never average down).
- Needs R-multiples (risk-normalized). If only pnl_usd exists, we fall back to a
  crude pseudo-R = pnl / mean(|losing pnl|) and LABEL the result approximate.
- Half-Kelly is still aggressive for fat tails; the drawdown cap is the binding
  one in practice and is the recommended number to actually sit behind.

numpy only.
"""
from __future__ import annotations

import numpy as np


def empirical_kelly(r_multiples, *, f_grid=None):
    """Full empirical Kelly fraction maximizing mean log-growth over R-multiples.

    Returns dict: kelly_f, half_kelly_f, g_at_kelly, mean_R, std_R, n,
    win_rate, worst_loss_R, gaussian_kelly (for comparison only).
    """
    R = np.asarray(r_multiples, dtype=float)
    R = R[np.isfinite(R)]
    n = R.size
    if n < 20:
        raise ValueError(f"need >= 20 trades, got {n}")

    # f must keep (1 + f*R) > 0 for every trade, else ln() -> ruin (-inf).
    worst_loss = float(R.min())  # most negative R
    f_cap = 0.999 / abs(worst_loss) if worst_loss < 0 else 10.0

    if f_grid is None:
        f_grid = np.linspace(1e-4, f_cap, 4000)

    def growth(f):
        v = 1.0 + f * R
        if np.any(v <= 0):
            return -np.inf
        return float(np.mean(np.log(v)))

    g = np.array([growth(f) for f in f_grid])
    best = int(np.argmax(g))
    kelly_f = float(f_grid[best])

    mean_R, std_R = float(R.mean()), float(R.std(ddof=1))
    gaussian_kelly = mean_R / (std_R ** 2) if std_R > 0 else float("nan")

    return {
        "kelly_f": kelly_f,
        "half_kelly_f": kelly_f / 2.0,
        "g_at_kelly": float(g[best]),
        "mean_R": mean_R,
        "std_R": std_R,
        "n": n,
        "win_rate": float(np.mean(R > 0)),
        "worst_loss_R": worst_loss,
        "gaussian_kelly": gaussian_kelly,
    }


def drawdown_capped_fraction(stats, max_tol_single_trade_dd=0.20):
    """min(half-Kelly, max_tol_dd / |worst_loss_R|) -- the survival-binding size."""
    worst = abs(stats["worst_loss_R"]) or 1e-9
    dd_cap = max_tol_single_trade_dd / worst
    return min(stats["half_kelly_f"], dd_cap), dd_cap


def risk_of_ruin(r_multiples, f, *, ruin_drawdown=0.5, n_paths=2000,
                 horizon=None, seed=0):
    """Monte-Carlo P(equity draws down >= ruin_drawdown) when risking f per trade,
    bootstrapping from the empirical R distribution."""
    R = np.asarray(r_multiples, dtype=float)
    R = R[np.isfinite(R)]
    horizon = horizon or R.size
    rng = np.random.default_rng(seed)
    ruined = 0
    for _ in range(n_paths):
        draws = rng.choice(R, size=horizon, replace=True)
        eq = 1.0
        peak = 1.0
        hit = False
        for r in draws:
            eq *= (1.0 + f * r)
            if eq <= 0:
                hit = True
                break
            peak = max(peak, eq)
            if (peak - eq) / peak >= ruin_drawdown:
                hit = True
                break
        ruined += int(hit)
    return ruined / n_paths


def _pseudo_R_from_pnl(pnl):
    pnl = np.asarray(pnl, dtype=float)
    losers = pnl[pnl < 0]
    unit = abs(losers.mean()) if losers.size else abs(pnl).mean()
    return pnl / unit if unit else pnl


def analyze_stream(path, *, max_tol_single_trade_dd=0.20):
    """Load a canonical trade-stream CSV and print the sizing recommendation."""
    import csv

    rows = list(csv.DictReader(open(path)))

    def col(name):
        out = []
        for r in rows:
            v = r.get(name, "")
            try:
                out.append(float(v))
            except (TypeError, ValueError):
                out.append(np.nan)
        return np.array(out)

    R = col("r_multiple")
    approx = False
    if np.isfinite(R).sum() < 20:
        R = _pseudo_R_from_pnl(col("pnl_usd"))
        approx = True

    s = empirical_kelly(R)
    capped, dd_cap = drawdown_capped_fraction(s, max_tol_single_trade_dd)
    ror_half = risk_of_ruin(R, s["half_kelly_f"])
    ror_capped = risk_of_ruin(R, capped)

    print(f"\n=== {path}{'  [APPROX pseudo-R from pnl]' if approx else ''} ===")
    print(f"  n={s['n']}  win_rate={s['win_rate']:.1%}  mean_R={s['mean_R']:.3f}  "
          f"std_R={s['std_R']:.3f}  worst_loss_R={s['worst_loss_R']:.3f}")
    print(f"  full Kelly      f*={s['kelly_f']:.3f}   (Gaussian-Kelly would say "
          f"{s['gaussian_kelly']:.3f} -- ignore, assumes no fat tails)")
    print(f"  half Kelly        ={s['half_kelly_f']:.3f}   risk-of-ruin(50%DD)="
          f"{ror_half:.1%}")
    print(f"  DD-capped (<= {max_tol_single_trade_dd:.0%}/trade) ={capped:.3f}   "
          f"(dd_cap={dd_cap:.3f})  risk-of-ruin(50%DD)={ror_capped:.1%}")
    print(f"  -> RECOMMENDED risk-per-trade fraction = {capped:.3f} "
          f"({'half-Kelly binds' if capped == s['half_kelly_f'] else 'drawdown cap binds'})")
    return s


def _self_test():
    rng = np.random.default_rng(1)
    # edge: win +1R at 55%, lose -1R at 45% -> Kelly should be ~ 2p-1 = 0.10
    R = np.where(rng.random(20000) < 0.55, 1.0, -1.0)
    s = empirical_kelly(R)
    assert abs(s["kelly_f"] - 0.10) < 0.02, s
    assert abs(s["half_kelly_f"] - 0.05) < 0.01, s
    # risk-of-ruin must rise with fraction
    lo = risk_of_ruin(R, 0.05, n_paths=400)
    hi = risk_of_ruin(R, 0.30, n_paths=400)
    assert hi >= lo, (lo, hi)
    print(f"self-test OK: 55/45 even-money Kelly f*={s['kelly_f']:.3f} (~0.10); "
          f"RoR 5%->{lo:.1%}, 30%->{hi:.1%}")


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description="Empirical fat-tail-aware Kelly sizing")
    ap.add_argument("--stream", action="append", default=[],
                    help="canonical trade-stream CSV (repeatable)")
    ap.add_argument("--max-dd", type=float, default=0.20,
                    help="max tolerable single-trade drawdown fraction")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test or not args.stream:
        _self_test()
    for p in args.stream:
        analyze_stream(p, max_tol_single_trade_dd=args.max_dd)
