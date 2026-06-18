#!/usr/bin/env python3
"""parity_diff.py — trade-level engine-vs-MT5 parity gate (PIPELINE-CONTRACT §4).

The missing link that made the old pipeline lie: "validated" meant the C++ engine
liked a config, never that MT5 reproduced it. This tool aligns an engine
`trades_*.csv` against an MT5 `trades_mt5.csv` (same .ex5 + .set + ticks + window)
and reports whether they agree *trade by trade*, then emits a PASS/FAIL verdict
against the contract tolerances.

Both files share the header exported by ParityExport.mqh / the C++ ledger:
    entryTimeUTC,dir,rev,retest,regimeTrend,session,entry,riskPrice,mfeR,maeR,
    realizedUsd,entryReason,brkDistAtr,bodyPct,adx,diSpread,runwayAtr,nodeNet,
    spreadPips,spreadAtr,exitTag

Matching is greedy nearest-time within the SAME direction, bounded by --lag-bars.
Engine runs are often wider than the MT5 window, so we window-filter the engine
side to the MT5 entry-time span (or an explicit --from/--to) before matching.

stdlib only — runs under any python3 (no numpy/pandas), so it can gate from CI or
a bare shell. Usage:

    python3 parity_diff.py \
        --engine validation/mt5_parity_runs/RUN_2026-06_btc_m3/cpp_out/trades_cpp_ema.csv \
        --mt5    validation/mt5_parity_runs/RUN_2026-06_btc_m3/mt5_ref/trades_mt5.csv \
        --bar-seconds 180 --label "MasterVP BTC M3 2026-06"
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta

TIME_FMT = "%Y.%m.%d %H:%M"


def parse_time(s: str) -> datetime:
    return datetime.strptime(s.strip(), TIME_FMT)


@dataclass
class Trade:
    t: datetime
    dir: str
    entry: float
    risk: float
    pnl: float
    exit_tag: str
    row: dict = field(repr=False)


def load_trades(path: str) -> list[Trade]:
    out: list[Trade] = []
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            ts = (r.get("entryTimeUTC") or "").strip()
            if not ts:
                continue
            try:
                t = parse_time(ts)
            except ValueError:
                continue

            def num(key: str) -> float:
                try:
                    return float(r.get(key) or 0.0)
                except ValueError:
                    return 0.0

            out.append(
                Trade(
                    t=t,
                    dir=(r.get("dir") or "").strip(),
                    entry=num("entry"),
                    risk=num("riskPrice"),
                    pnl=num("realizedUsd"),
                    exit_tag=(r.get("exitTag") or "").strip(),
                    row=r,
                )
            )
    out.sort(key=lambda x: x.t)
    return out


def profit_factor(trades: list[Trade]) -> float:
    gross_win = sum(t.pnl for t in trades if t.pnl > 0)
    gross_loss = -sum(t.pnl for t in trades if t.pnl < 0)
    if gross_loss == 0:
        return float("inf") if gross_win > 0 else 0.0
    return gross_win / gross_loss


def match(
    engine: list[Trade], mt5: list[Trade], lag: timedelta
) -> tuple[list[tuple[Trade, Trade]], list[Trade], list[Trade]]:
    """Greedy nearest-time matching within same direction, within lag window."""
    used_eng: set[int] = set()
    pairs: list[tuple[Trade, Trade]] = []
    for m in mt5:
        best_i, best_dt = -1, None
        for i, e in enumerate(engine):
            if i in used_eng or e.dir != m.dir:
                continue
            dt = abs(e.t - m.t)
            if dt <= lag and (best_dt is None or dt < best_dt):
                best_i, best_dt = i, dt
        if best_i >= 0:
            used_eng.add(best_i)
            pairs.append((engine[best_i], m))
    unmatched_mt5 = [m for m in mt5 if all(m is not p[1] for p in pairs)]
    unmatched_eng = [e for i, e in enumerate(engine) if i not in used_eng]
    pairs.sort(key=lambda p: p[1].t)
    return pairs, unmatched_eng, unmatched_mt5


def window_filter(
    trades: list[Trade], lo: datetime | None, hi: datetime | None
) -> list[Trade]:
    return [t for t in trades if (lo is None or t.t >= lo) and (hi is None or t.t <= hi)]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--engine", required=True, help="engine trades_*.csv")
    ap.add_argument("--mt5", required=True, help="MT5 trades_mt5.csv")
    ap.add_argument("--bar-seconds", type=int, default=180, help="bar size (M1=60, M3=180)")
    ap.add_argument("--lag-bars", type=float, default=1.0, help="max entry-time lag, in bars")
    ap.add_argument("--from", dest="frm", default=None, help="window start 'YYYY.MM.DD HH:MM' (default: MT5 span)")
    ap.add_argument("--to", dest="to", default=None, help="window end (default: MT5 span)")
    ap.add_argument("--tol-pnl-pct", type=float, default=1.0, help="net P&L Δ%% PASS tolerance")
    ap.add_argument("--lag-frac", type=float, default=0.05, help="max fraction of trades allowed to lag")
    ap.add_argument("--label", default="", help="run label for the report header")
    ap.add_argument("--json", dest="json_out", default=None, help="write machine-readable verdict here")
    args = ap.parse_args()

    engine_all = load_trades(args.engine)
    mt5 = load_trades(args.mt5)
    if not mt5:
        print("FAIL: MT5 trade list is empty — nothing to diff.", file=sys.stderr)
        return 2

    lo = parse_time(args.frm) if args.frm else min(m.t for m in mt5)
    hi = parse_time(args.to) if args.to else max(m.t for m in mt5)
    engine = window_filter(engine_all, lo, hi)
    mt5 = window_filter(mt5, lo, hi)

    lag = timedelta(seconds=args.bar_seconds * args.lag_bars)
    pairs, un_eng, un_mt5 = match(engine, mt5, lag)

    # aggregates
    eng_net = sum(t.pnl for t in engine)
    mt5_net = sum(t.pnl for t in mt5)
    eng_pf, mt5_pf = profit_factor(engine), profit_factor(mt5)
    net_delta_pct = (
        abs(eng_net - mt5_net) / abs(mt5_net) * 100.0 if mt5_net else float("inf")
    )
    lagged = sum(1 for e, m in pairs if e.t != m.t)
    dir_mismatch = sum(1 for e, m in pairs if e.dir != m.dir)  # 0 by construction
    exit_mismatch = sum(1 for e, m in pairs if e.exit_tag != m.exit_tag)
    lag_frac = lagged / len(mt5) if mt5 else 0.0

    bar = "=" * 72
    print(bar)
    print(f"PARITY DIFF — {args.label or 'engine vs MT5'}")
    print(bar)
    print(f"window           : {lo:%Y.%m.%d %H:%M} → {hi:%Y.%m.%d %H:%M}")
    print(f"engine trades    : {len(engine)}  (file had {len(engine_all)} before window-filter)")
    print(f"MT5 trades       : {len(mt5)}")
    print(f"matched pairs    : {len(pairs)}")
    print(f"unmatched engine : {len(un_eng)}   unmatched MT5 : {len(un_mt5)}")
    print(f"lag (>0 bars)    : {lagged}/{len(mt5)} = {lag_frac:.1%}  (tol ≤ {args.lag_frac:.0%})")
    print(f"exit-tag mismatch: {exit_mismatch}/{len(pairs)}")
    print(bar)
    print(f"{'net P&L USD':<18}{'engine':>14}{'MT5':>14}{'Δ%':>10}")
    print(f"{'':<18}{eng_net:>14.2f}{mt5_net:>14.2f}{net_delta_pct:>9.2f}%")
    print(f"{'profit factor':<18}{eng_pf:>14.3f}{mt5_pf:>14.3f}")
    print(bar)

    if pairs:
        print("per-matched-trade:")
        print(f"  {'mt5 time':<17}{'dir':>4}{'lagB':>6}{'entryΔ':>12}{'slΔ':>10}"
              f"{'exit(e/m)':>16}{'pnlΔ':>10}")
        for e, m in pairs:
            lag_b = (e.t - m.t).total_seconds() / args.bar_seconds
            exit_s = f"{e.exit_tag}/{m.exit_tag}"
            flag = "" if e.exit_tag == m.exit_tag else "  <-exit"
            print(f"  {m.t:%Y.%m.%d %H:%M} {m.dir:>4}{lag_b:>6.0f}"
                  f"{e.entry - m.entry:>12.3f}{e.risk - m.risk:>10.3f}"
                  f"{exit_s:>16}{e.pnl - m.pnl:>10.2f}{flag}")
    if un_mt5:
        print(f"\nMT5 trades with NO engine match ({len(un_mt5)}):")
        for m in un_mt5:
            print(f"  {m.t:%Y.%m.%d %H:%M} {m.dir} entry={m.entry:.3f} pnl={m.pnl:.2f} exit={m.exit_tag}")
    if un_eng:
        print(f"\nengine trades with NO MT5 match ({len(un_eng)}):")
        for e in un_eng:
            print(f"  {e.t:%Y.%m.%d %H:%M} {e.dir} entry={e.entry:.3f} pnl={e.pnl:.2f} exit={e.exit_tag}")

    # verdict per contract §4
    structural_ok = (
        len(un_eng) == 0
        and len(un_mt5) == 0
        and dir_mismatch == 0
        and exit_mismatch == 0
    )
    pnl_ok = net_delta_pct <= args.tol_pnl_pct
    lag_ok = lag_frac <= args.lag_frac
    verdict = "PASS" if (structural_ok and pnl_ok and lag_ok) else "FAIL"

    print(bar)
    reasons = []
    if not structural_ok:
        if un_eng or un_mt5:
            reasons.append(f"trade-count mismatch ({len(un_eng)} engine-only, {len(un_mt5)} MT5-only)")
        if exit_mismatch:
            reasons.append(f"{exit_mismatch} exit-reason mismatches")
    if not pnl_ok:
        reasons.append(f"net P&L Δ {net_delta_pct:.2f}% > {args.tol_pnl_pct}%")
    if not lag_ok:
        reasons.append(f"entry lag on {lag_frac:.0%} > {args.lag_frac:.0%} of trades")
    print(f"VERDICT: {verdict}" + (("  — " + "; ".join(reasons)) if reasons else "  — all tolerances met"))
    if verdict == "FAIL":
        print("→ This is an engine-fidelity bug. Fix the engine to match MT5; do NOT promote.")
    print(bar)

    if args.json_out:
        with open(args.json_out, "w") as fh:
            json.dump(
                {
                    "label": args.label,
                    "window": [lo.strftime(TIME_FMT), hi.strftime(TIME_FMT)],
                    "engine_trades": len(engine),
                    "mt5_trades": len(mt5),
                    "matched": len(pairs),
                    "unmatched_engine": len(un_eng),
                    "unmatched_mt5": len(un_mt5),
                    "lagged": lagged,
                    "exit_mismatch": exit_mismatch,
                    "engine_net": round(eng_net, 2),
                    "mt5_net": round(mt5_net, 2),
                    "net_delta_pct": round(net_delta_pct, 4),
                    "engine_pf": round(eng_pf, 4) if eng_pf != float("inf") else None,
                    "mt5_pf": round(mt5_pf, 4) if mt5_pf != float("inf") else None,
                    "verdict": verdict,
                    "reasons": reasons,
                },
                fh,
                indent=2,
            )
        print(f"wrote {args.json_out}")

    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
