#!/usr/bin/env python3
"""Build the data-source evidence ledger for the XAU/BTC strategy program.

The output is intentionally conservative: MT5/Exness tick counts are quote
activity, not traded volume. The report records what each local data source can
support and where it is insufficient for production claims.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import duckdb
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "research" / "data_quality" / "EVIDENCE_TIERS.md"


@dataclass
class SourceRow:
    source: str
    files: str
    rows_or_size: str
    time_span: str
    bid_ask: str
    last_real_volume: str
    role: str
    evidence_tier: str
    caveat: str


def fmt_int(n: int | None) -> str:
    return "n/a" if n is None else f"{n:,}"


def file_size(paths: Iterable[Path]) -> str:
    total = sum(p.stat().st_size for p in paths if p.exists())
    if total >= 1024**3:
        return f"{total / 1024**3:.2f} GB"
    if total >= 1024**2:
        return f"{total / 1024**2:.1f} MB"
    return f"{total:,} bytes"


def raw_sample(symbol: str) -> dict[str, str]:
    paths = sorted((ROOT / "data" / symbol.lower()).glob(f"{symbol.upper()}_ticks_mt5_*.csv"))
    if not paths:
        return {"files": "0", "size": "missing", "span": "missing", "last_volume": "missing"}
    sample_path = paths[-1]
    df = pd.read_csv(sample_path, sep="\t", nrows=20000)
    cols = set(df.columns)
    last_zero = "n/a"
    volume_zero = "n/a"
    if "<LAST>" in cols:
        last_zero = f"{(df['<LAST>'].fillna(0) == 0).mean() * 100:.1f}% zero in sample"
    if "<VOLUME>" in cols:
        volume_zero = f"{(df['<VOLUME>'].fillna(0) == 0).mean() * 100:.1f}% zero in sample"
    return {
        "files": str(len(paths)),
        "size": file_size(paths),
        "span": ", ".join(p.stem.rsplit("_", 1)[-1] for p in paths),
        "last_volume": f"LAST {last_zero}; VOLUME {volume_zero}",
    }


def parquet_stats(pattern: str, ts_col: str = "ts") -> dict[str, str]:
    paths = sorted(ROOT.glob(pattern))
    if not paths:
        return {"files": "0", "rows": "missing", "span": "missing", "cols": "missing"}
    con = duckdb.connect()
    rel = ", ".join("'" + str(p) + "'" for p in paths)
    desc = con.execute(f"DESCRIBE SELECT * FROM read_parquet([{rel}])").fetchdf()
    cols = list(desc["column_name"])
    if ts_col not in cols:
        ts_col = "timestamp" if "timestamp" in cols else cols[0]
    row = con.execute(
        f"SELECT count(*) n, min({ts_col}) min_ts, max({ts_col}) max_ts FROM read_parquet([{rel}])"
    ).fetchone()
    con.close()
    return {
        "files": str(len(paths)),
        "rows": fmt_int(int(row[0])),
        "span": f"{row[1]} -> {row[2]}",
        "cols": ", ".join(cols[:8]) + ("..." if len(cols) > 8 else ""),
    }


def csv_stats(path: Path, ts_col: str = "ts_ms") -> dict[str, str]:
    if not path.exists():
        return {"files": "0", "rows": "missing", "span": "missing", "cols": "missing"}
    with path.open(newline="") as fh:
        reader = csv.reader(fh)
        cols = next(reader)
    con = duckdb.connect()
    row = con.execute(
        f"""
        SELECT count(*) n, min({ts_col}) min_ts, max({ts_col}) max_ts
        FROM read_csv_auto('{path}', header=true)
        """
    ).fetchone()
    con.close()
    span = f"{pd.to_datetime(row[1], unit='ms', utc=True)} -> {pd.to_datetime(row[2], unit='ms', utc=True)}"
    return {
        "files": "1",
        "rows": fmt_int(int(row[0])),
        "span": span,
        "cols": ", ".join(cols[:8]) + ("..." if len(cols) > 8 else ""),
    }


def table(rows: list[SourceRow]) -> str:
    headers = [
        "Source",
        "Files",
        "Rows/Size",
        "Time span",
        "Bid/Ask",
        "Last/real volume",
        "Use",
        "Tier",
        "Caveat",
    ]
    lines = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(headers)) + "|"]
    for r in rows:
        vals = [
            r.source,
            r.files,
            r.rows_or_size,
            r.time_span,
            r.bid_ask,
            r.last_real_volume,
            r.role,
            r.evidence_tier,
            r.caveat,
        ]
        lines.append("| " + " | ".join(v.replace("\n", " ") for v in vals) + " |")
    return "\n".join(lines)


def main() -> None:
    rows: list[SourceRow] = []

    for symbol in ["BTCUSD", "XAUUSD"]:
        raw = raw_sample(symbol)
        rows.append(
            SourceRow(
                f"MT5 raw tick CSV ({symbol}, Exness)",
                raw["files"],
                raw["size"],
                raw["span"],
                "Yes: BID/ASK quote stream",
                raw["last_volume"],
                "Entry timing, spread, quote-activity VP only",
                "Tier A for quote/fill timing; Tier C for volume",
                "No exchange traded volume; tick count is quote activity.",
            )
        )

    for symbol in ["btcusd", "xauusd"]:
        stats = parquet_stats(f"data/processed/ticks_{symbol}_*.parquet")
        rows.append(
            SourceRow(
                f"Processed tick parquet ({symbol.upper()})",
                stats["files"],
                stats["rows"],
                stats["span"],
                "Yes if bid/ask columns present",
                "No trusted real volume in current feed",
                "Fast research queries and tick-engine input",
                "Tier A for local backtest timing",
                "Still inherits MT5/Exness single-feed limitations.",
            )
        )

    for path, label in [
        (ROOT / "cpp_core/tools/bars_btcusd_2025_2026_m3.csv", "BTCUSD M3 bars for MasterVP focus"),
        (ROOT / "cpp_core/tools/bars_xauusd_2024_2026_m1.csv", "XAUUSD M1 bars for KenKem focus"),
    ]:
        stats = csv_stats(path)
        rows.append(
            SourceRow(
                label,
                stats["files"],
                stats["rows"],
                stats["span"],
                "No: aggregated OHLC only",
                "`tick_count` only",
                "Feature and profile construction",
                "Tier B for state features",
                "Cannot validate real volume; must be cross-checked against ticks/MT5.",
            )
        )

    rows.append(
        SourceRow(
            "MT5 Strategy Tester reports/trade CSVs",
            "many",
            "per run",
            "run-specific",
            "Broker tester model",
            "Tester-dependent",
            "Final exit/P&L confirmation",
            "Tier A for MT5 behavior",
            "Cannot be used as discovery environment; final judge only.",
        )
    )
    rows.append(
        SourceRow(
            "Second broker / exchange proxy",
            "0 local",
            "missing",
            "missing",
            "unknown",
            "needed for real/cross-feed volume validation",
            "Robustness confirmation",
            "Blocked",
            "Required before claiming traded-volume VP or BTC deployability.",
        )
    )

    md = f"""# Evidence Tiers - XAUUSD/BTCUSD Data Truth

Generated by `research/data_quality/build_evidence_tiers.py`.

## Codex-Step-1 Verdict

The local pipeline is strong enough for **quote-timing, spread, tick-engine replay, and MT5 parity work**.
It is **not** sufficient to claim real traded-volume profile alpha. MasterVP's current VP must be labeled
**quote-activity VP** until a second broker or exchange-volume proxy confirms that the relevant POC/VAH/VAL
structures are stable outside the Exness MT5 feed.

KenKem's EMA/RSI/DMI inputs are likewise not evidence by themselves; they need lag/redundancy and incremental
value audits before being promoted beyond state filters.

## Evidence Matrix

{table(rows)}

## Immediate Consequences

1. **MasterVP BTC M3:** do not run another profitability sweep first. Validate the BTC M3 tick-count VP proxy
   under perturbation and session anchoring, then decide whether BTC M3 deserves new strategy work.
2. **KenKem M1 + VP:** use VP as an added structural context only after causal VP levels are joined to the
   D5-E4Long trade stream and show conditional MFE/MAE information.
3. **Production claims:** quote-activity VP can still be useful, but the product description and research notes
   must not imply exchange traded volume.

## Self-Validation

- Raw MT5 CSV samples were inspected for LAST/VOLUME usability.
- Processed Parquet row counts and spans were read through DuckDB.
- Focus bar CSV row counts and spans were checked from local files.
- No external broker/exchange proxy is present locally, so cross-feed validation is a blocker for traded-volume
  claims and a future robustness upgrade.
"""
    OUT.write_text(md)
    print(OUT)


if __name__ == "__main__":
    main()
