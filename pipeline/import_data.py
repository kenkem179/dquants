"""Phase 1 — Import Data.

Stream raw MT5 tab-separated tick CSVs into typed, compressed Parquet, deriving a single UTC
timestamp plus ``mid`` and ``spread``. Designed for files far larger than RAM (2025 ≈ 7.2 GB /
148 M rows): DuckDB streams CSV → Parquet in a single pass, so memory stays bounded.

This is *import only*. Cleaning/validation (dedup, impossible prices, negative spread) is Phase 2
(``/quant-validate-data``); here we faithfully convert the raw feed and merely *report* anomalies.

Usage
-----
    python -m pipeline.import_data --symbol btcusd --all
    python -m pipeline.import_data --symbol btcusd --years 2024 2025
    python -m pipeline.import_data --symbol btcusd --years 2026 --force

Output: ``data/processed/ticks_<symbol>_<year>.parquet`` with columns
``ts, bid, ask, mid, spread, flags`` (LAST/VOLUME dropped — always 0 on this feed).
"""
from __future__ import annotations

import argparse
import logging
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path

import duckdb

from . import config

log = logging.getLogger("import_data")

# Read DATE/TIME as VARCHAR and parse explicitly: this does NOT depend on DuckDB's auto-type
# sampler inferring DATE/TIME correctly for every file, and the %f fraction is verified to map
# '.830' -> 830000 microseconds (0.830 s), not 830 us. See docs/KENKEM_QUANT_OS.md §3.
_RAW_COLUMN_TYPES = {
    "<DATE>": "VARCHAR",
    "<TIME>": "VARCHAR",
    "<BID>": "DOUBLE",
    "<ASK>": "DOUBLE",
    "<LAST>": "DOUBLE",
    "<VOLUME>": "BIGINT",
    "<FLAGS>": "INTEGER",
}

_SELECT_SQL = """
    SELECT
        strptime("<DATE>" || ' ' || "<TIME>", '%Y.%m.%d %H:%M:%S.%f') AS ts,
        "<BID>"                          AS bid,
        "<ASK>"                          AS ask,
        ("<BID>" + "<ASK>") / 2.0        AS mid,
        ("<ASK>" - "<BID>")              AS spread,
        "<FLAGS>"                        AS flags
    FROM read_csv(
        ?,
        delim = '\t',
        header = true,
        columns = {columns}
    )
"""


@dataclass
class ImportStats:
    symbol: str
    year: int
    src: str
    dst: str
    rows: int
    raw_lines: int | None      # source data lines (excl. header), None if not checked
    null_ts: int               # rows whose timestamp failed to parse
    negative_spread: int       # reported, NOT removed (Phase 2 cleans)
    ts_min: str
    ts_max: str
    monotonic: bool            # is ts non-decreasing across the file?
    elapsed_s: float

    def matches_source(self) -> bool:
        return self.raw_lines is None or self.rows == self.raw_lines


def _columns_struct() -> str:
    inner = ", ".join(f"'{k}': '{v}'" for k, v in _RAW_COLUMN_TYPES.items())
    return "{" + inner + "}"


def _count_raw_lines(path: Path) -> int | None:
    """Independent cross-check of source data rows (excl. header). None on failure.

    ``wc -l`` counts newline characters, so a file whose final row lacks a trailing newline
    undercounts by one. We correct for that by inspecting the last byte.
    """
    try:
        out = subprocess.run(
            ["wc", "-l", str(path)], capture_output=True, text=True, check=True
        ).stdout
        n = int(out.strip().split()[0])
        if path.stat().st_size > 0:
            with open(path, "rb") as fh:
                fh.seek(-1, 2)
                if fh.read(1) != b"\n":
                    n += 1  # last line not newline-terminated
        return n - 1  # subtract header line
    except Exception as exc:  # noqa: BLE001 - cross-check is best-effort
        log.warning("wc -l failed for %s (%s); skipping line cross-check", path.name, exc)
        return None


def import_file(
    src: Path,
    dst: Path,
    *,
    symbol: str,
    year: int,
    memory_limit: str = "6GB",
    threads: int | None = None,
    row_group_size: int = 1_000_000,
    check_lines: bool = True,
    overwrite: bool = False,
) -> ImportStats:
    """Convert one raw MT5 tick CSV to processed Parquet and return verification stats."""
    if dst.exists() and not overwrite:
        raise FileExistsError(f"{dst} exists (use --force to overwrite)")
    dst.parent.mkdir(parents=True, exist_ok=True)

    raw_lines = _count_raw_lines(src) if check_lines else None
    tmp = dst.with_suffix(".parquet.tmp")
    tmp.unlink(missing_ok=True)

    con = duckdb.connect()
    con.execute(f"SET memory_limit='{memory_limit}'")
    con.execute("SET preserve_insertion_order=true")  # keep ticks chronological
    if threads:
        con.execute(f"SET threads={threads}")

    select_sql = _SELECT_SQL.format(columns=_columns_struct())
    copy_sql = (
        f"COPY ({select_sql}) TO '{tmp.as_posix()}' "
        f"(FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE {row_group_size})"
    )

    log.info("[%s %s] %s -> %s", symbol, year, src.name, dst.name)
    t0 = time.perf_counter()
    con.execute(copy_sql, [src.as_posix()])

    # Verify against what was actually written.
    rel = f"'{tmp.as_posix()}'"
    rows = con.sql(f"SELECT count(*) FROM read_parquet({rel})").fetchone()[0]
    null_ts = con.sql(f"SELECT count(*) FROM read_parquet({rel}) WHERE ts IS NULL").fetchone()[0]
    neg = con.sql(f"SELECT count(*) FROM read_parquet({rel}) WHERE spread < 0").fetchone()[0]
    ts_min, ts_max = con.sql(
        f"SELECT min(ts), max(ts) FROM read_parquet({rel})"
    ).fetchone()
    # Monotonic check: any row where ts < previous ts?
    out_of_order = con.sql(
        f"SELECT count(*) FROM ("
        f"  SELECT ts, lag(ts) OVER () AS prev FROM read_parquet({rel})"
        f") WHERE prev IS NOT NULL AND ts < prev"
    ).fetchone()[0]
    elapsed = time.perf_counter() - t0
    con.close()

    tmp.replace(dst)  # atomic swap only after verification reads succeeded

    stats = ImportStats(
        symbol=symbol,
        year=year,
        src=str(src),
        dst=str(dst),
        rows=rows,
        raw_lines=raw_lines,
        null_ts=null_ts,
        negative_spread=neg,
        ts_min=str(ts_min),
        ts_max=str(ts_max),
        monotonic=(out_of_order == 0),
        elapsed_s=round(elapsed, 1),
    )
    _log_stats(stats)
    return stats


def _log_stats(s: ImportStats) -> None:
    log.info("  rows written : %s", f"{s.rows:,}")
    if s.raw_lines is not None:
        ok = "OK" if s.matches_source() else f"MISMATCH (source={s.raw_lines:,})"
        log.info("  source lines : %s  [%s]", f"{s.raw_lines:,}", ok)
    log.info("  ts range     : %s -> %s", s.ts_min, s.ts_max)
    log.info("  monotonic ts : %s", s.monotonic)
    if s.null_ts:
        log.warning("  UNPARSED ts  : %s rows (investigate before Phase 2)", f"{s.null_ts:,}")
    if s.negative_spread:
        log.warning("  negative spread: %s rows (Phase 2 will clean)", f"{s.negative_spread:,}")
    log.info("  elapsed      : %ss", s.elapsed_s)


def import_symbol(
    symbol: str,
    years: list[int] | None = None,
    *,
    overwrite: bool = False,
    check_lines: bool = True,
    memory_limit: str = "6GB",
) -> list[ImportStats]:
    """Import all (or selected) years for a symbol. Skips already-present years unless overwrite."""
    available = config.discover_raw_files(symbol)
    if not available:
        raise FileNotFoundError(f"No raw tick CSVs found in {config.symbol_dir(symbol)}")

    targets = sorted(available) if years is None else sorted(years)
    results: list[ImportStats] = []
    for year in targets:
        src = available.get(year)
        if src is None:
            log.warning("[%s] no raw file for %s — skipping", symbol, year)
            continue
        dst = config.processed_path(symbol, year)
        if dst.exists() and not overwrite:
            log.info("[%s %s] %s already exists — skipping (use --force)", symbol, year, dst.name)
            continue
        results.append(
            import_file(
                src, dst, symbol=symbol, year=year,
                memory_limit=memory_limit, check_lines=check_lines, overwrite=overwrite,
            )
        )
    return results


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Phase 1 — import MT5 tick CSVs to Parquet")
    p.add_argument("--symbol", default="btcusd", help="symbol/dir under data/ (default: btcusd)")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--all", action="store_true", help="import every year found")
    g.add_argument("--years", type=int, nargs="+", help="specific year(s) to import")
    p.add_argument("--force", action="store_true", help="overwrite existing Parquet")
    p.add_argument("--no-line-check", action="store_true", help="skip the wc -l cross-check")
    p.add_argument("--memory-limit", default="6GB", help="DuckDB memory limit (default: 6GB)")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args = _parse_args(argv)
    years = None if (args.all or not args.years) else args.years
    try:
        results = import_symbol(
            args.symbol, years,
            overwrite=args.force,
            check_lines=not args.no_line_check,
            memory_limit=args.memory_limit,
        )
    except (FileNotFoundError, FileExistsError) as exc:
        log.error("%s", exc)
        return 1

    if not results:
        log.info("Nothing imported.")
        return 0

    failures = [r for r in results if not r.matches_source() or r.null_ts > 0]
    log.info("\n=== Summary: %d file(s) imported ===", len(results))
    for r in results:
        flag = "" if (r.matches_source() and r.null_ts == 0) else "  <-- CHECK"
        log.info("  %s %s: %s rows in %ss%s", r.symbol, r.year, f"{r.rows:,}", r.elapsed_s, flag)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
