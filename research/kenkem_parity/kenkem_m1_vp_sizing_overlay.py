#!/usr/bin/env python3
"""Test KenKem M1 tick-activity VP as a sizing/state overlay.

Codex-Step-7: the previous hard-filter pre-gate was too sample-hungry.  This
script keeps every trade and asks whether VP context can improve the equity
path by sizing down/up in a walk-forward manner.
"""

from __future__ import annotations

import csv
import math
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from statistics import mean


INPUT = Path("research/kenkem_parity/vp_entry_audit/kenkem_m1_d5_e4long_vp_joined.csv")
OUT_DIR = Path("research/kenkem_parity/vp_sizing_overlay")


@dataclass
class Trade:
    ts: datetime
    quarter: str
    entry_type: str
    vp_location: str
    poc_bucket: str
    pnl: float
    mfe_r: float
    mae_r: float


def parse_ts(value: str) -> datetime:
    value = value.strip()
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y.%m.%d %H:%M"):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            pass
    raise ValueError(f"unsupported timestamp: {value}")


def quarter(ts: datetime) -> str:
    q = ((ts.month - 1) // 3) + 1
    return f"{ts.year}Q{q}"


def as_float(value: str) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return 0.0
    return parsed if math.isfinite(parsed) else 0.0


def load_trades(path: Path) -> list[Trade]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        trades: list[Trade] = []
        for row in reader:
            ts = parse_ts(row.get("entry_ts") or row["entryTimeUTC"])
            trades.append(
                Trade(
                    ts=ts,
                    quarter=quarter(ts),
                    entry_type=row["kind"],
                    vp_location=row["vp_location"],
                    poc_bucket=row["poc_bucket"],
                    pnl=as_float(row["realizedUsd"]),
                    mfe_r=as_float(row["mfeR"]),
                    mae_r=as_float(row["maeR"]),
                )
            )
    return sorted(trades, key=lambda trade: trade.ts)


def max_drawdown(pnls: list[float]) -> float:
    equity = 0.0
    peak = 0.0
    worst = 0.0
    for pnl in pnls:
        equity += pnl
        peak = max(peak, equity)
        worst = min(worst, equity - peak)
    return abs(worst)


def profit_factor(pnls: list[float]) -> float:
    wins = sum(pnl for pnl in pnls if pnl > 0)
    losses = -sum(pnl for pnl in pnls if pnl < 0)
    if losses == 0:
        return float("inf") if wins > 0 else 0.0
    return wins / losses


def metrics(pnls: list[float]) -> dict[str, float]:
    return {
        "n": float(len(pnls)),
        "net": sum(pnls),
        "pf": profit_factor(pnls),
        "max_dd": max_drawdown(pnls),
        "avg": mean(pnls) if pnls else 0.0,
        "win_rate": sum(1 for pnl in pnls if pnl > 0) / len(pnls) if pnls else 0.0,
    }


def by_quarter(trades: list[Trade], weighted_pnls: list[float]) -> list[dict[str, str]]:
    grouped: dict[str, list[float]] = defaultdict(list)
    for trade, pnl in zip(trades, weighted_pnls):
        grouped[trade.quarter].append(pnl)
    rows = []
    for q in sorted(grouped):
        m = metrics(grouped[q])
        rows.append(
            {
                "quarter": q,
                "n": f"{m['n']:.0f}",
                "net": f"{m['net']:.2f}",
                "pf": f"{m['pf']:.3f}",
                "max_dd": f"{m['max_dd']:.2f}",
            }
        )
    return rows


def summarize_cells(trades: list[Trade]) -> list[dict[str, str]]:
    grouped: dict[tuple[str, str], list[Trade]] = defaultdict(list)
    for trade in trades:
        grouped[(trade.entry_type, trade.vp_location)].append(trade)
    rows = []
    for (entry_type, vp_location), group in sorted(grouped.items()):
        pnls = [trade.pnl for trade in group]
        rows.append(
            {
                "entry_type": entry_type,
                "vp_location": vp_location,
                "n": str(len(group)),
                "net": f"{sum(pnls):.2f}",
                "pf": f"{profit_factor(pnls):.3f}",
                "avg_pnl": f"{mean(pnls):.2f}",
                "mfe_r_mean": f"{mean([trade.mfe_r for trade in group]):.3f}",
                "mae_r_mean": f"{mean([trade.mae_r for trade in group]):.3f}",
            }
        )
    return rows


def fixed_vp_state_weight(trade: Trade) -> float:
    """Conservative non-filter overlay from prior audit: inside value is chop-prone."""
    if trade.vp_location == "inside_value":
        return 0.50
    return 1.00


def fixed_entry_vp_weight(trade: Trade) -> float:
    """Small in-sample diagnostic policy; not production unless WF agrees."""
    weak_cells = {
        ("E1", "above_value"),
        ("E2", "inside_value"),
        ("E4", "below_value"),
        ("E4", "inside_value"),
    }
    strong_cells = {
        ("E1", "below_value"),
        ("E1", "inside_value"),
        ("E4", "above_value"),
    }
    key = (trade.entry_type, trade.vp_location)
    if key in weak_cells:
        return 0.50
    if key in strong_cells:
        return 1.25
    return 1.00


def learned_cell_weight(history: list[Trade], trade: Trade) -> float:
    cell = [t for t in history if t.entry_type == trade.entry_type and t.vp_location == trade.vp_location]
    if len(cell) < 8:
        return 1.0
    cell_avg = mean(t.pnl for t in cell)
    global_avg = mean(t.pnl for t in history)
    cell_mfe = mean(t.mfe_r for t in cell)
    cell_mae = mean(t.mae_r for t in cell)
    if cell_avg < 0 and cell_mfe <= 0.75:
        return 0.50
    if cell_avg > global_avg and cell_mfe >= 0.75 and cell_mae <= 0.75:
        return 1.25
    return 1.0


def walk_forward_weights(trades: list[Trade]) -> list[float]:
    quarters = sorted({trade.quarter for trade in trades})
    weights_by_index = [1.0 for _ in trades]
    for q in quarters:
        history = [trade for trade in trades if trade.quarter < q]
        if len(history) < 40:
            continue
        for idx, trade in enumerate(trades):
            if trade.quarter == q:
                weights_by_index[idx] = learned_cell_weight(history, trade)
    return weights_by_index


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    if not rows:
        return
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def weighted(trades: list[Trade], weights: list[float]) -> list[float]:
    return [trade.pnl * weight for trade, weight in zip(trades, weights)]


def format_metric_line(name: str, pnls: list[float]) -> str:
    m = metrics(pnls)
    return (
        f"| {name} | {m['n']:.0f} | {m['net']:.2f} | {m['pf']:.3f} | "
        f"{m['max_dd']:.2f} | {m['avg']:.2f} | {m['win_rate']:.3f} |"
    )


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    trades = load_trades(INPUT)

    base_weights = [1.0 for _ in trades]
    state_weights = [fixed_vp_state_weight(trade) for trade in trades]
    cell_weights = [fixed_entry_vp_weight(trade) for trade in trades]
    wf_weights = walk_forward_weights(trades)

    scenarios = {
        "BASE": base_weights,
        "VP_state_inside_0.50": state_weights,
        "EntryVP_diagnostic": cell_weights,
        "WalkForward_cell_sizing": wf_weights,
    }

    summary_rows = []
    for name, weights in scenarios.items():
        pnls = weighted(trades, weights)
        m = metrics(pnls)
        q_rows = by_quarter(trades, pnls)
        summary_rows.append(
            {
                "scenario": name,
                "n": f"{m['n']:.0f}",
                "net": f"{m['net']:.2f}",
                "pf": f"{m['pf']:.3f}",
                "max_dd": f"{m['max_dd']:.2f}",
                "avg": f"{m['avg']:.2f}",
                "win_rate": f"{m['win_rate']:.3f}",
                "positive_quarters": str(sum(1 for row in q_rows if float(row["net"]) > 0)),
                "quarters": str(len(q_rows)),
                "worst_quarter": f"{min(float(row['net']) for row in q_rows):.2f}",
            }
        )
        write_csv(OUT_DIR / f"{name.lower()}_quarter_metrics.csv", q_rows)

    write_csv(OUT_DIR / "vp_cell_summary.csv", summarize_cells(trades))
    write_csv(OUT_DIR / "vp_sizing_overlay_summary.csv", summary_rows)

    base = weighted(trades, base_weights)
    wf = weighted(trades, wf_weights)
    wf_m = metrics(wf)
    base_m = metrics(base)
    wf_q = by_quarter(trades, wf)
    base_q = by_quarter(trades, base)
    wf_positive = sum(1 for row in wf_q if float(row["net"]) > 0)
    base_positive = sum(1 for row in base_q if float(row["net"]) > 0)

    if (
        wf_m["pf"] > base_m["pf"]
        and wf_m["net"] >= base_m["net"]
        and wf_m["max_dd"] <= base_m["max_dd"]
        and wf_positive >= base_positive
    ):
        verdict = "PASS-WARN"
        decision = (
            "Walk-forward VP cell sizing improves headline metrics without deleting trades, but sample size remains "
            "small; promote only as a default-OFF C++ experiment with registry/DSR tracking."
        )
    else:
        verdict = "STOP"
        decision = (
            "Do not implement KenKem VP sizing yet. The walk-forward policy does not improve the full base stream "
            "cleanly enough to justify an EA code change."
        )

    report = [
        "# KenKem M1 VP Sizing Overlay",
        "",
        "## Codex-Step-7 Verdict",
        "",
        f"{verdict}: {decision}",
        "",
        "This test keeps every KenKem trade. VP context may only change risk weight, so it is less sample-hungry than",
        "a hard entry filter. Production promotion still requires C++ implementation, costs, registry row, and DSR/MinTRL.",
        "",
        "## Scenario Metrics",
        "",
        "| Scenario | n | Net | PF | MaxDD | Avg/trade | Win rate |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for name, weights in scenarios.items():
        report.append(format_metric_line(name, weighted(trades, weights)))
    report.extend(
        [
            "",
            "## Robustness Notes",
            "",
            f"- Base positive quarters: {base_positive}/{len(base_q)}.",
            f"- Walk-forward positive quarters: {wf_positive}/{len(wf_q)}.",
            f"- Base worst quarter: {min(float(row['net']) for row in base_q):.2f}.",
            f"- Walk-forward worst quarter: {min(float(row['net']) for row in wf_q):.2f}.",
            "- `EntryVP_diagnostic` is in-sample and is reported only to show possible cell structure; it is not a lock.",
            "- Blank/zero MAE values in the source stream limit path-quality conclusions.",
            "",
            "## Artifacts",
            "",
            "- `vp_sizing_overlay_summary.csv`",
            "- `vp_cell_summary.csv`",
            "- `walkforward_cell_sizing_quarter_metrics.csv`",
            "",
        ]
    )
    (OUT_DIR / "KENKEM_M1_VP_SIZING_OVERLAY.md").write_text("\n".join(report))
    print(OUT_DIR / "KENKEM_M1_VP_SIZING_OVERLAY.md")
    print(f"verdict={verdict}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
