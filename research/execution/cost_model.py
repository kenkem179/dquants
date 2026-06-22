#!/usr/bin/env python3
"""Execution cost realism for retail FX — the spread/slippage skepticism, quantified.

WHY THIS EXISTS
---------------
A backtest's costs are an assumption, and on M1/M3 scalping the edge per trade is small enough that a
wrong cost assumption flips the sign. Rather than trust one optimistic number, this module asks the
honest questions a serious desk asks:

  1. BREAKEVEN COST  — what per-trade round-trip cost (in account ccy) zeros the edge? = mean(realizedUsd).
     If your *plausible* real cost (spread x pip-value x lot + commission) is anywhere near it, the
     "edge" is a cost artifact. This single number is the most useful honesty check we have.

  2. COST STRESS     — re-price the whole stream under escalating, realistic cost regimes and watch
     PF/net/Sharpe/maxDD degrade:
        - fixed extra USD per trade, OR pip-based (extra_pips x pip_value x lot) when lot is known
        - SESSION-dependent spread (Asian thin, London/NY tight, rollover blowout) by entry hour (UTC)
        - VOL-SCALED slippage (wider fills when the bar is volatile) via the trade's |MAE|/|MFE| proxy
        - TAIL SPIKE: a random fraction of trades hit a black-swan spread multiple (the event
          KenKemExpert's abnormal-spread filter is designed to dodge) — tests what an UNfiltered run costs.

This is an OFFLINE stress over the C++ engine's trade CSV; it never re-simulates fills. It is a
robustness gate, not a replacement for modelling costs inside the engine (which is still mandatory).

CLI:
  python -m research.execution.cost_model --trades _locked.csv --pip-value 10 --lot 0.1
  python -m research.execution.cost_model --trades _locked.csv --fixed-usd-levels 1,2,3,5
"""
from __future__ import annotations

import argparse
import csv
import math
import os
import sys
from datetime import datetime

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from stats.overfitting import sharpe_ratio  # noqa: E402

START_BALANCE = 10000.0
_TIME_KEYS = ("entryTimeUTC", "entryTime", "openTime", "time")
_TIME_MS_KEYS = ("ts_ms", "tsMs", "entryMs")
_PNL_KEYS = ("realizedUsd", "pnlUsd", "pnl", "profit", "netUsd")
_TIME_FMTS = ("%Y.%m.%d %H:%M", "%Y.%m.%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M")

# Relative spread by FX session (UTC hour). Asian range thin -> wider spread; London/NY overlap tight;
# 21-22 UTC daily rollover = the notorious blowout. Multipliers on a baseline spread.
SESSION_SPREAD_MULT = {
    "asia": 1.4,      # 22:00-07:00 UTC
    "london": 1.0,    # 07:00-12:00 UTC
    "overlap": 0.9,   # 12:00-16:00 UTC (London/NY, tightest)
    "ny": 1.1,        # 16:00-21:00 UTC
    "rollover": 3.0,  # 21:00-22:00 UTC
}


def session_of(dt: datetime) -> str:
    h = dt.hour
    if 21 <= h < 22:
        return "rollover"
    if h >= 22 or h < 7:
        return "asia"
    if 7 <= h < 12:
        return "london"
    if 12 <= h < 16:
        return "overlap"
    return "ny"


def load_trades(path):
    """Return list of dicts: {dt, pnl, lot?, mae_r?, mfe_r?} with schema auto-detected."""
    out = []
    with open(path) as f:
        for r in csv.DictReader(f):
            dt = _parse_time(r)
            pnl = _parse_pnl(r)
            rec = dict(dt=dt, pnl=pnl)
            if "lot" in r and r["lot"] not in ("", None):
                rec["lot"] = float(r["lot"])
            for k in ("maeR", "mae_r"):
                if k in r and r[k] not in ("", None):
                    rec["mae_r"] = abs(float(r[k]))
            for k in ("mfeR", "mfe_r"):
                if k in r and r[k] not in ("", None):
                    rec["mfe_r"] = abs(float(r[k]))
            out.append(rec)
    out.sort(key=lambda x: x["dt"])
    return out


def _parse_time(row):
    for k in _TIME_MS_KEYS:
        if k in row and row[k] not in ("", None):
            return datetime.utcfromtimestamp(float(row[k]) / 1000.0)
    for k in _TIME_KEYS:
        if k in row and row[k] not in ("", None):
            for fmt in _TIME_FMTS:
                try:
                    return datetime.strptime(row[k].strip(), fmt)
                except ValueError:
                    continue
    raise KeyError(f"no time column in {list(row)}")


def _parse_pnl(row):
    for k in _PNL_KEYS:
        if k in row and row[k] not in ("", None):
            return float(row[k])
    raise KeyError(f"no pnl column in {list(row)}")


# ----------------------------------------------------------------------------- metrics
def _stats(pnls):
    p = np.asarray(pnls, dtype=float)
    n = p.size
    wins = p[p > 0].sum()
    losses = -p[p < 0].sum()
    pf = wins / losses if losses > 0 else float("inf")
    # Sharpe on per-trade return fractions (decompounded against a flat start balance)
    sr = sharpe_ratio(p / START_BALANCE)
    eq = START_BALANCE + np.cumsum(p)
    peak = np.maximum.accumulate(eq)
    maxdd = float(((eq - peak) / peak).min()) if n else 0.0
    return dict(n=n, net=float(p.sum()), pf=float(pf), win_pct=float((p > 0).mean()),
                sharpe=float(sr), max_drawdown=maxdd)


def breakeven_cost(trades) -> dict:
    """The per-trade round-trip cost (account ccy) that zeros the edge, vs current avg cost headroom."""
    pnls = np.array([t["pnl"] for t in trades], dtype=float)
    mean_pnl = float(pnls.mean()) if pnls.size else 0.0
    return dict(
        n=int(pnls.size),
        mean_pnl=mean_pnl,
        breakeven_cost_per_trade=mean_pnl,   # subtract this much per trade -> net zero
        median_pnl=float(np.median(pnls)) if pnls.size else 0.0,
    )


# ----------------------------------------------------------------------------- cost application
def apply_cost(trades, extra_pips=0.0, pip_value=0.0, fixed_usd=0.0,
               session_mult=False, vol_slip_pips=0.0, base_spread_pips=0.0,
               tail_frac=0.0, tail_mult=0.0, seed=12345):
    """Return a new pnl array with a cost regime subtracted from each trade.

      extra_pips     : extra spread (each side modelled via round-trip) charged in pips
      pip_value      : account-ccy value of 1 pip per 1.0 lot (e.g. ~10 for EURUSD std lot)
      fixed_usd      : flat round-trip cost per trade in account ccy (used when lot/pip unknown)
      session_mult   : scale spread cost by SESSION_SPREAD_MULT[entry session]
      base_spread_pips: baseline spread that session/tail multipliers act on (for session & tail terms)
      vol_slip_pips  : extra slippage pips scaled by the trade's |MAE| (volatility proxy, in R)
      tail_frac      : fraction of trades that suffer a black-swan spread spike
      tail_mult      : multiplier applied to base spread for those tail trades
    Pip terms require pip_value (and a per-trade lot, defaulting to 1.0 if absent).
    """
    rng = np.random.default_rng(seed)
    out = []
    tail_mask = rng.random(len(trades)) < tail_frac if tail_frac > 0 else np.zeros(len(trades), bool)
    for i, t in enumerate(trades):
        lot = t.get("lot", 1.0)
        cost = fixed_usd
        # explicit extra spread (round-trip ~ charge once on the difference; pips already round-trip)
        cost += extra_pips * pip_value * lot
        # session-scaled baseline spread
        if session_mult and base_spread_pips > 0:
            cost += base_spread_pips * SESSION_SPREAD_MULT[session_of(t["dt"])] * pip_value * lot
        # vol-scaled slippage: more adverse fill on volatile bars
        if vol_slip_pips > 0:
            vol = t.get("mae_r", 1.0)
            cost += vol_slip_pips * min(vol, 5.0) * pip_value * lot
        # tail spike
        if tail_mask[i] and base_spread_pips > 0:
            cost += base_spread_pips * tail_mult * pip_value * lot
        out.append(t["pnl"] - cost)
    return np.array(out, dtype=float)


def cost_stress_sweep(trades, levels, pip_value=0.0, mode="fixed_usd", **kw):
    """Run _stats at each cost level. mode: 'fixed_usd' (levels are USD) or 'extra_pips' (levels=pips)."""
    base = _stats([t["pnl"] for t in trades])
    rows = [("base", 0.0, base)]
    for lv in levels:
        if mode == "fixed_usd":
            pnls = apply_cost(trades, fixed_usd=lv, **kw)
        else:
            pnls = apply_cost(trades, extra_pips=lv, pip_value=pip_value, **kw)
        rows.append((mode, lv, _stats(pnls)))
    return rows


# ----------------------------------------------------------------------------- CLI
def _floats(s):
    return [float(x) for x in s.split(",") if x.strip()]


def main(argv=None):
    ap = argparse.ArgumentParser(description="Execution cost realism / robustness stress.")
    ap.add_argument("--trades", required=True)
    ap.add_argument("--pip-value", type=float, default=0.0, help="account-ccy value of 1 pip / 1.0 lot")
    ap.add_argument("--lot", type=float, default=None, help="override per-trade lot if CSV lacks it")
    ap.add_argument("--base-spread-pips", type=float, default=1.0)
    ap.add_argument("--fixed-usd-levels", type=_floats, default=None,
                    help="comma list of flat USD round-trip costs to stress (e.g. 1,2,3,5)")
    ap.add_argument("--extra-pip-levels", type=_floats, default=None,
                    help="comma list of extra-spread pip levels to stress (needs --pip-value)")
    ap.add_argument("--tail-frac", type=float, default=0.0)
    ap.add_argument("--tail-mult", type=float, default=10.0)
    args = ap.parse_args(argv)

    trades = load_trades(args.trades)
    if args.lot is not None:
        for t in trades:
            t["lot"] = args.lot

    be = breakeven_cost(trades)
    print(f"\n=== {os.path.basename(args.trades)}: {be['n']} trades ===")
    print(f"mean PnL / trade        : {be['mean_pnl']:.3f}")
    print(f"median PnL / trade       : {be['median_pnl']:.3f}")
    print(f"BREAKEVEN cost / trade  : {be['breakeven_cost_per_trade']:.3f}  (account ccy round-trip)")
    print("  -> if plausible real cost (spread*pip_value*lot + commission) is near this, edge is fragile")

    has_lot = any("lot" in t for t in trades)
    print(f"per-trade lot known: {has_lot}  | pip_value={args.pip_value}")

    levels = args.fixed_usd_levels or [0.5, 1.0, 2.0, 3.0, 5.0]
    mode = "fixed_usd"
    if args.extra_pip_levels and args.pip_value > 0:
        levels, mode = args.extra_pip_levels, "extra_pips"

    print(f"\ncost stress ({mode}):")
    print(f"  {'level':>8} | {'net':>10} | {'PF':>5} | {'win%':>5} | {'Sharpe':>7} | {'maxDD%':>7}")
    rows = cost_stress_sweep(trades, levels, pip_value=args.pip_value, mode=mode,
                             base_spread_pips=args.base_spread_pips,
                             session_mult=True, tail_frac=args.tail_frac, tail_mult=args.tail_mult)
    for tag, lv, st in rows:
        lvs = "base" if tag == "base" else f"{lv:g}"
        print(f"  {lvs:>8} | {st['net']:10.1f} | {st['pf']:5.2f} | {st['win_pct']*100:4.1f} "
              f"| {st['sharpe']:7.4f} | {st['max_drawdown']*100:6.1f}")
    print("\n(session spread multipliers applied throughout: "
          + ", ".join(f"{k}x{v}" for k, v in SESSION_SPREAD_MULT.items()) + ")")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
