#!/usr/bin/env python3
"""Extended metrics + standardized performance-table reporting (user format 2026-06-14).

The optimizer harness's metrics() only emits n/net/pf/dd. The user requires EVERY strategy comparison
table to carry 9 columns: Strategy, Settings, Symbol+TF, Net, PF, Recovery factor, MaxDD, Sharpe,
trades/day. full_metrics() adds the missing three. Reusable by any engine's reporting.

Sharpe convention: daily-PnL Sharpe annualized by sqrt(ann_days) (365 for 24/7 crypto, 252 for XAU).
It is a PnL-Sharpe (dollars), fine for relative comparison on fixed-fraction $10k sizing.
Recovery factor = net / maxDD. trades/day = n_trades / calendar-span-days of the test window.
"""
import math


def full_metrics(rows, ann_days=365):
    """rows: list of (ts_ms, pnl_usd). Returns the full 9-column metric set."""
    if not rows:
        return dict(n=0, net=0.0, pf=0.0, dd=0.0, recovery=0.0, sharpe=0.0, tpd=0.0)
    rows = sorted(rows)
    pnls = [p for _, p in rows]
    net = sum(pnls)
    gp = sum(p for p in pnls if p > 0)
    gl = -sum(p for p in pnls if p < 0)
    pf = gp / gl if gl > 0 else (9.99 if gp > 0 else 0.0)
    # max drawdown on the per-trade equity curve
    peak = cum = dd = 0.0
    for p in pnls:
        cum += p
        peak = max(peak, cum)
        dd = max(dd, peak - cum)
    recovery = net / dd if dd > 0 else (9.99 if net > 0 else 0.0)
    # span in days
    span_days = max((rows[-1][0] - rows[0][0]) / 86_400_000.0, 1.0 / 24)
    tpd = len(pnls) / span_days
    # daily-PnL Sharpe, annualized
    by_day = {}
    for ts, p in rows:
        by_day[ts // 86_400_000] = by_day.get(ts // 86_400_000, 0.0) + p
    daily = list(by_day.values())
    if len(daily) >= 2:
        mu = sum(daily) / len(daily)
        var = sum((d - mu) ** 2 for d in daily) / (len(daily) - 1)
        sd = math.sqrt(var)
        sharpe = (mu / sd) * math.sqrt(ann_days) if sd > 0 else 0.0
    else:
        sharpe = 0.0
    return dict(n=len(pnls), net=net, pf=pf, dd=dd,
                recovery=recovery, sharpe=sharpe, tpd=tpd)


def fmt_row(strategy, settings, symbol_tf, m):
    """One markdown table row in the standard 9-column order."""
    return (f"| {strategy} | {settings} | {symbol_tf} | "
            f"{m['net']:+,.0f} | {m['pf']:.3f} | {m['recovery']:.2f} | "
            f"{m['dd']:,.0f} | {m['sharpe']:.2f} | {m['tpd']:.1f} |")


HEADER = ("| Strategy | Settings | Symbol, TF | Net Profit | Profit Factor | "
          "Recovery Factor | Max Drawdown | Sharpe | Trades/day |\n"
          "|---|---|---|---|---|---|---|---|---|")
