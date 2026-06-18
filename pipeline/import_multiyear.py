"""Phase 1 helper — import a *multi-year* MT5 tick CSV, split by year into per-year Parquet.

Some MT5/Exness exports ship more than one calendar year in a single file (e.g.
``XAUUSD_ticks_mt5_2025_2026.csv``). The standard per-year importer (``pipeline.import_data``)
keys off a single 4-digit year in the filename, so it cannot route such a file. This helper streams
the file once per requested year, filtering on ``year(ts)``, and writes the *same* schema and
derivations as ``pipeline.import_data`` (it reuses that module's column spec and SELECT), so the
output is byte-for-byte compatible with files produced by the normal path.

Like the normal importer this is *import only* — Phase 2 (``pipeline.validate_data``) still cleans.

Usage
-----
    python -m pipeline.import_multiyear \
        --src data/xauusd/XAUUSD_ticks_mt5_2025_2026.csv \
        --symbol xauusd --years 2025 2026

Output: ``data/processed/ticks_<symbol>_<year>.parquet`` (cols ts, bid, ask, mid, spread, flags).
"""
from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

import duckdb

from . import config
from .import_data import _SELECT_SQL, _columns_struct

log = logging.getLogger("import_multiyear")


def import_year_from(
    src: Path,
    *,
    symbol: str,
    year: int,
    memory_limit: str = "6GB",
    row_group_size: int = 1_000_000,
    overwrite: bool = False,
) -> dict:
    """Extract a single calendar ``year`` from a multi-year CSV into processed Parquet."""
    dst = config.processed_path(symbol, year)
    if dst.exists() and not overwrite:
        raise FileExistsError(f"{dst} exists (use --force to overwrite)")
    dst.parent.mkdir(parents=True, exist_ok=True)

    tmp = dst.with_suffix(".parquet.tmp")
    tmp.unlink(missing_ok=True)

    con = duckdb.connect()
    con.execute(f"SET memory_limit='{memory_limit}'")
    con.execute("SET preserve_insertion_order=true")  # keep ticks chronological

    select_sql = _SELECT_SQL.format(columns=_columns_struct())
    # Wrap the shared SELECT and filter to one calendar year on the derived ts.
    year_sql = f"SELECT * FROM ({select_sql}) WHERE year(ts) = {int(year)}"
    copy_sql = (
        f"COPY ({year_sql}) TO '{tmp.as_posix()}' "
        f"(FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE {row_group_size})"
    )

    log.info("[%s %s] %s -> %s", symbol, year, src.name, dst.name)
    t0 = time.perf_counter()
    con.execute(copy_sql, [src.as_posix()])

    rel = f"'{tmp.as_posix()}'"
    rows = con.sql(f"SELECT count(*) FROM read_parquet({rel})").fetchone()[0]
    null_ts = con.sql(f"SELECT count(*) FROM read_parquet({rel}) WHERE ts IS NULL").fetchone()[0]
    neg = con.sql(f"SELECT count(*) FROM read_parquet({rel}) WHERE spread < 0").fetchone()[0]
    ts_min, ts_max = con.sql(f"SELECT min(ts), max(ts) FROM read_parquet({rel})").fetchone()
    out_of_order = con.sql(
        f"SELECT count(*) FROM ("
        f"  SELECT ts, lag(ts) OVER () AS prev FROM read_parquet({rel})"
        f") WHERE prev IS NOT NULL AND ts < prev"
    ).fetchone()[0]
    elapsed = round(time.perf_counter() - t0, 1)
    con.close()

    if rows == 0:
        tmp.unlink(missing_ok=True)
        raise ValueError(f"year {year} produced 0 rows from {src.name} — wrong year requested?")

    tmp.replace(dst)  # atomic swap only after verification reads succeeded

    stats = {
        "symbol": symbol, "year": year, "dst": str(dst), "rows": rows,
        "null_ts": null_ts, "negative_spread": neg,
        "ts_min": str(ts_min), "ts_max": str(ts_max),
        "monotonic": out_of_order == 0, "elapsed_s": elapsed,
    }
    log.info("  rows written : %s", f"{rows:,}")
    log.info("  ts range     : %s -> %s", ts_min, ts_max)
    log.info("  monotonic ts : %s", out_of_order == 0)
    if null_ts:
        log.warning("  UNPARSED ts  : %s rows (investigate before Phase 2)", f"{null_ts:,}")
    if neg:
        log.warning("  negative spread: %s rows (Phase 2 will clean)", f"{neg:,}")
    log.info("  elapsed      : %ss", elapsed)
    return stats


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Phase 1 — split a multi-year MT5 tick CSV into per-year Parquet")
    p.add_argument("--src", required=True, help="path to the multi-year raw CSV")
    p.add_argument("--symbol", required=True, help="symbol, e.g. xauusd")
    p.add_argument("--years", type=int, nargs="+", required=True, help="calendar years to extract")
    p.add_argument("--force", action="store_true", help="overwrite existing Parquet")
    p.add_argument("--memory-limit", default="6GB", help="DuckDB memory limit (default: 6GB)")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args = _parse_args(argv)
    src = Path(args.src)
    if not src.exists():
        log.error("source not found: %s", src)
        return 1

    results = []
    for year in sorted(args.years):
        try:
            results.append(import_year_from(
                src, symbol=args.symbol, year=year,
                memory_limit=args.memory_limit, overwrite=args.force,
            ))
        except FileExistsError as exc:
            log.info("%s — skipping (use --force)", exc)
        except ValueError as exc:
            log.error("%s", exc)
            return 1

    log.info("\n=== Summary: %d year(s) written ===", len(results))
    for r in results:
        flag = "" if (r["null_ts"] == 0 and r["monotonic"]) else "  <-- CHECK"
        log.info("  %s %s: %s rows in %ss%s", r["symbol"], r["year"], f"{r['rows']:,}", r["elapsed_s"], flag)
    return 0


if __name__ == "__main__":
    sys.exit(main())
