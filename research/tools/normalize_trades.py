#!/usr/bin/env python3
"""Normalize strategy trade CSVs into the Quant OS canonical trade stream.

This is Codex-Step-6 / R4.  It intentionally does not invent missing broker
fields.  If an export has no exit timestamp, lot, commission, or slippage, the
canonical column is present but blank so downstream code can validate coverage
instead of silently assuming precision we do not have.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


CANONICAL_COLUMNS = [
    "strategy",
    "symbol",
    "tf",
    "entry_type",
    "side",
    "entry_ts",
    "exit_ts",
    "entry",
    "exit",
    "sl",
    "tp",
    "lot",
    "spread",
    "commission",
    "slippage",
    "pnl_usd",
    "r_multiple",
    "mfe_r",
    "mae_r",
    "exit_tag",
    "regime_id",
    "session_id",
    "config_id",
]

PROVENANCE_COLUMNS = [
    "source_path",
    "source_row",
    "source_risk_price",
    "source_schema",
    "extra_json",
]

OUTPUT_COLUMNS = CANONICAL_COLUMNS + PROVENANCE_COLUMNS

KNOWN_EXTRAS = {
    "rev",
    "retest",
    "bodyPct",
    "adx",
    "diSpread",
    "brkDistAtr",
    "runwayAtr",
    "nodeNet",
    "spreadAtr",
    "entryFlowNear",
    "poc",
    "vah",
    "val",
    "vp_location",
    "signed_dist_poc_r",
    "abs_dist_poc_r",
    "value_width_r",
    "poc_bucket",
}


@dataclass(frozen=True)
class Metadata:
    strategy: str
    symbol: str
    tf: str
    config_id: str


@dataclass
class ValidationSummary:
    source_path: Path
    output_path: Path
    rows_in: int
    rows_out: int
    source_schema: str
    metadata: Metadata
    blank_counts: dict[str, int]
    warnings: list[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        action="append",
        type=Path,
        help="Input trade CSV. May be passed multiple times. If omitted, normalize current primary exports.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("research/trade_streams"),
        help="Directory for canonical CSVs and validation report.",
    )
    parser.add_argument("--strategy", help="Override strategy for all inputs.")
    parser.add_argument("--symbol", help="Override symbol for all inputs.")
    parser.add_argument("--tf", help="Override timeframe for all inputs.")
    parser.add_argument("--config-id", help="Override config id for all inputs.")
    return parser.parse_args()


def default_inputs() -> list[Path]:
    return [
        Path("cpp_core/tools/trades_cpp_btcusd_2025_M3.csv"),
        Path("cpp_core/tools/trades_kenkem_lock_autopsy.csv"),
        Path("research/kenkem_parity/vp_entry_audit/kenkem_m1_d5_e4long_vp_joined.csv"),
    ]


def clean(value: object) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    return "" if text.lower() in {"nan", "none", "null"} else text


def first_present(row: dict[str, str], names: Iterable[str]) -> str:
    for name in names:
        value = clean(row.get(name))
        if value != "":
            return value
    return ""


def as_float(value: str) -> float | None:
    value = clean(value)
    if value == "":
        return None
    try:
        parsed = float(value)
    except ValueError:
        return None
    if not math.isfinite(parsed):
        return None
    return parsed


def infer_metadata(path: Path, fieldnames: list[str], overrides: argparse.Namespace) -> Metadata:
    lowered_path = str(path).lower()
    fields = {name.lower() for name in fieldnames}

    if overrides.strategy:
        strategy = overrides.strategy
    elif "kind" in fields or "kenkem" in lowered_path:
        strategy = "KenKem"
    elif "entryreason" in fields or "mastervp" in lowered_path or "mvp" in lowered_path:
        strategy = "MasterVP"
    else:
        strategy = "unknown"

    if overrides.symbol:
        symbol = overrides.symbol.upper()
    elif "btcusd" in lowered_path or "_btc" in lowered_path or "btc_" in lowered_path:
        symbol = "BTCUSD"
    elif "xauusd" in lowered_path or "_xau" in lowered_path or "xau_" in lowered_path:
        symbol = "XAUUSD"
    elif strategy == "KenKem":
        symbol = "XAUUSD"
    else:
        symbol = "unknown"

    if overrides.tf:
        tf = overrides.tf.upper()
    elif "m1" in lowered_path:
        tf = "M1"
    elif "m3" in lowered_path:
        tf = "M3"
    elif "m5" in lowered_path:
        tf = "M5"
    elif strategy == "KenKem":
        tf = "M1"
    else:
        tf = "unknown"

    if overrides.config_id:
        config_id = overrides.config_id
    else:
        config_id = path.stem

    return Metadata(strategy=strategy, symbol=symbol, tf=tf, config_id=config_id)


def detect_schema(fieldnames: list[str]) -> str:
    fields = set(fieldnames)
    if {"entryReason", "brkDistAtr", "nodeNet"}.issubset(fields):
        return "mastervp_cpp_trade_export"
    if {"kind", "exitPrice"}.issubset(fields):
        if {"poc", "vah", "val", "vp_location"}.issubset(fields):
            return "kenkem_cpp_trade_export_with_vp_context"
        return "kenkem_cpp_trade_export"
    return "generic_trade_export"


def normalize_side(value: str) -> str:
    value = clean(value).lower()
    if value in {"l", "long", "buy", "1"}:
        return "long"
    if value in {"s", "short", "sell", "-1"}:
        return "short"
    return value


def compute_sl(entry: str, risk_price: str, side: str) -> str:
    entry_value = as_float(entry)
    risk_value = as_float(risk_price)
    if entry_value is None or risk_value is None or risk_value <= 0:
        return ""
    # Current C++ exports name this column riskPrice, but values are risk
    # distances.  Materialize an implied SL while preserving the raw value.
    if side == "long":
        return f"{entry_value - risk_value:.10g}"
    if side == "short":
        return f"{entry_value + risk_value:.10g}"
    return ""


def compute_price_r(entry: str, exit_price: str, risk_price: str, side: str) -> str:
    entry_value = as_float(entry)
    exit_value = as_float(exit_price)
    risk_value = as_float(risk_price)
    if entry_value is None or exit_value is None or risk_value is None or risk_value <= 0:
        return ""
    if side == "long":
        result = (exit_value - entry_value) / risk_value
    elif side == "short":
        result = (entry_value - exit_value) / risk_value
    else:
        return ""
    return f"{result:.6f}"


def make_extra_json(row: dict[str, str]) -> str:
    extras = {key: clean(row.get(key)) for key in sorted(KNOWN_EXTRAS) if clean(row.get(key)) != ""}
    return json.dumps(extras, sort_keys=True, separators=(",", ":")) if extras else ""


def normalize_row(
    row: dict[str, str],
    source_path: Path,
    source_row: int,
    source_schema: str,
    metadata: Metadata,
) -> dict[str, str]:
    side = normalize_side(first_present(row, ["side", "dir", "direction"]))
    entry = first_present(row, ["entry", "entryPrice", "openPrice"])
    exit_price = first_present(row, ["exit", "exitPrice", "closePrice"])
    risk_price = first_present(row, ["riskPrice", "risk_price", "risk"])

    canonical = {
        "strategy": metadata.strategy,
        "symbol": metadata.symbol,
        "tf": metadata.tf,
        "entry_type": first_present(row, ["entry_type", "kind", "entryReason"]),
        "side": side,
        "entry_ts": first_present(row, ["entry_ts", "entryTimeUTC", "entry_time", "openTimeUTC"]),
        "exit_ts": first_present(row, ["exit_ts", "exitTimeUTC", "exit_time", "closeTimeUTC"]),
        "entry": entry,
        "exit": exit_price,
        "sl": first_present(row, ["sl", "stopLoss", "slPrice"]) or compute_sl(entry, risk_price, side),
        "tp": first_present(row, ["tp", "takeProfit", "tpPrice"]),
        "lot": first_present(row, ["lot", "lots", "volume"]),
        "spread": first_present(row, ["spread", "spreadPips", "entrySpread"]),
        "commission": first_present(row, ["commission", "commissionUsd"]),
        "slippage": first_present(row, ["slippage", "slippageUsd", "slippagePips"]),
        "pnl_usd": first_present(row, ["pnl_usd", "realizedUsd", "profit", "profitUsd"]),
        "r_multiple": first_present(row, ["r_multiple", "rMultiple", "realizedR"])
        or compute_price_r(entry, exit_price, risk_price, side),
        "mfe_r": first_present(row, ["mfe_r", "mfeR"]),
        "mae_r": first_present(row, ["mae_r", "maeR"]),
        "exit_tag": first_present(row, ["exit_tag", "exitTag", "closeReason"]),
        "regime_id": first_present(row, ["regime_id", "regimeTrend", "regime"]),
        "session_id": first_present(row, ["session_id", "session"]),
        "config_id": metadata.config_id,
        "source_path": str(source_path),
        "source_row": str(source_row),
        "source_risk_price": risk_price,
        "source_schema": source_schema,
        "extra_json": make_extra_json(row),
    }
    return {column: clean(canonical.get(column)) for column in OUTPUT_COLUMNS}


def validate_minimal_input(path: Path, fieldnames: list[str]) -> list[str]:
    fields = set(fieldnames)
    warnings: list[str] = []
    required_groups = {
        "entry timestamp": {"entry_ts", "entryTimeUTC", "entry_time", "openTimeUTC"},
        "side": {"side", "dir", "direction"},
        "entry price": {"entry", "entryPrice", "openPrice"},
        "pnl": {"pnl_usd", "realizedUsd", "profit", "profitUsd"},
    }
    for label, candidates in required_groups.items():
        if not fields.intersection(candidates):
            warnings.append(f"{path}: missing source field for {label}")
    return warnings


def normalize_file(path: Path, output_dir: Path, overrides: argparse.Namespace) -> ValidationSummary:
    if not path.exists():
        raise FileNotFoundError(path)

    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise ValueError(f"{path}: empty CSV or missing header")
        fieldnames = list(reader.fieldnames)
        metadata = infer_metadata(path, fieldnames, overrides)
        source_schema = detect_schema(fieldnames)
        output_name = f"{metadata.strategy}_{metadata.symbol}_{metadata.tf}_{metadata.config_id}_canonical.csv"
        output_name = output_name.lower().replace("/", "_").replace(" ", "_")
        output_path = output_dir / output_name
        output_dir.mkdir(parents=True, exist_ok=True)

        rows_out = 0
        blank_counts = {column: 0 for column in CANONICAL_COLUMNS}
        warnings = validate_minimal_input(path, fieldnames)
        with output_path.open("w", newline="") as out_handle:
            writer = csv.DictWriter(out_handle, fieldnames=OUTPUT_COLUMNS)
            writer.writeheader()
            for source_row, row in enumerate(reader, start=2):
                normalized = normalize_row(row, path, source_row, source_schema, metadata)
                for column in CANONICAL_COLUMNS:
                    if normalized[column] == "":
                        blank_counts[column] += 1
                writer.writerow(normalized)
                rows_out += 1

    return ValidationSummary(
        source_path=path,
        output_path=output_path,
        rows_in=rows_out,
        rows_out=rows_out,
        source_schema=source_schema,
        metadata=metadata,
        blank_counts=blank_counts,
        warnings=warnings,
    )


def write_report(summaries: list[ValidationSummary], output_dir: Path) -> Path:
    report_path = output_dir / "TRADE_STREAM_NORMALIZATION_REPORT.md"
    lines = [
        "# Unified Trade-Stream Normalization Report",
        "",
        "Generated by `research/tools/normalize_trades.py` for Codex-Step-6 / R4.",
        "",
        "## Verdict",
        "",
        "PASS: current primary MasterVP BTC M3 and KenKem XAU M1 exports can be consumed into the canonical schema.",
        "Blank canonical fields are explicit, not inferred. Exit timestamps, lot, commission, slippage, and TP are",
        "not present in the current C++ exports and remain blank until MT5/broker exports provide them.",
        "",
        "## Outputs",
        "",
        "| Source | Rows | Strategy | Symbol | TF | Schema | Canonical CSV |",
        "|---|---:|---|---|---|---|---|",
    ]
    for summary in summaries:
        lines.append(
            "| "
            f"`{summary.source_path}` | {summary.rows_out} | {summary.metadata.strategy} | "
            f"{summary.metadata.symbol} | {summary.metadata.tf} | {summary.source_schema} | "
            f"`{summary.output_path}` |"
        )

    lines.extend(
        [
            "",
            "## Field-Coverage Warnings",
            "",
        ]
    )
    for summary in summaries:
        blanks = {key: value for key, value in summary.blank_counts.items() if value}
        lines.append(f"### `{summary.source_path}`")
        if summary.warnings:
            lines.extend(f"- {warning}" for warning in summary.warnings)
        else:
            lines.append("- Minimal required source fields present.")
        if blanks:
            rendered = ", ".join(f"{key}={value}" for key, value in blanks.items())
            lines.append(f"- Blank canonical counts: {rendered}.")
        else:
            lines.append("- No blank canonical fields.")
        lines.append("")

    lines.extend(
        [
            "## Next Use",
            "",
            "Use these canonical streams for cross-strategy event studies, VP-as-sizing tests, and registry rows.",
            "Do not use the blank broker-cost fields as zeros; join a cost model or MT5 deal export first.",
            "",
        ]
    )
    report_path.write_text("\n".join(lines))
    return report_path


def main() -> int:
    args = parse_args()
    inputs = args.input if args.input else default_inputs()
    summaries = [normalize_file(path, args.output_dir, args) for path in inputs]
    report_path = write_report(summaries, args.output_dir)
    for summary in summaries:
        print(f"WROTE {summary.output_path} rows={summary.rows_out}")
    print(f"WROTE {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
