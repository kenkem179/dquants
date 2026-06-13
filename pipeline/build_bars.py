"""Phase 3 (part 1) — Bar Construction.

Aggregate cleaned ticks into M1/M3 OHLC bars via DuckDB ``time_bucket``.

Conventions (see docs/KENKEM_QUANT_OS.md §3):

* **OHLC is built on ``mid`` = (bid+ask)/2** — a broker-neutral fair price. Spread is tracked
  separately (``spread_mean``/``spread_max``) so the execution simulator and the MQL5 EA apply the
  half-spread at fill time. The EA must therefore compute its indicators on mid for signal parity.
* **Sparse bars**: a bar exists only for a minute that had ≥1 tick (matches MT5, which forms a bar
  only when a tick arrives). This naturally skips weekends, the missing 2025 days, and dead minutes.
  Bar index is event-time, not continuous calendar time — indicators operate on the bar *sequence*.
* ``tick_count`` is the per-bar tick tally (real VOLUME is always 0 on this feed) and doubles as the
  weight for the tick-based volume profile in Phase-3 features.

Usage
-----
    python -m pipeline.build_bars --symbol btcusd --all
    python -m pipeline.build_bars --symbol btcusd --years 2025 --timeframes M1 M3 --force
"""
from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

import duckdb

from . import config

log = logging.getLogger("build_bars")

# Supported timeframes -> DuckDB INTERVAL string.
TIMEFRAMES = {"M1": "1 minute", "M3": "3 minutes"}

BAR_COLUMNS = ["ts", "open", "high", "low", "close", "spread_mean", "spread_max", "tick_count"]


def _bars_sql(src_posix: str, interval: str) -> str:
    # time_bucket floors ts to the bucket; default origin (2000-01-01 00:00) keeps M3 aligned to
    # clock minutes (:00,:03,:06,...). OHLC from mid; first/last by ts within the bucket.
    return f"""
        SELECT
            time_bucket(INTERVAL '{interval}', ts)        AS ts,
            first(mid ORDER BY ts)                        AS open,
            max(mid)                                      AS high,
            min(mid)                                      AS low,
            last(mid ORDER BY ts)                         AS close,
            avg(spread)                                   AS spread_mean,
            max(spread)                                   AS spread_max,
            count(*)                                      AS tick_count
        FROM read_parquet('{src_posix}')
        GROUP BY 1
        ORDER BY 1
    """


def build_bars_file(
    src: Path,
    *,
    symbol: str,
    timeframe: str,
    year: int,
    memory_limit: str = "6GB",
    overwrite: bool = False,
) -> dict:
    if timeframe not in TIMEFRAMES:
        raise ValueError(f"unknown timeframe {timeframe!r} (have {list(TIMEFRAMES)})")
    dst = config.bars_path(symbol, timeframe, year)
    if dst.exists() and not overwrite:
        raise FileExistsError(f"{dst} exists (use --force)")
    dst.parent.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect()
    con.execute(f"SET memory_limit='{memory_limit}'")
    sql = _bars_sql(src.as_posix(), TIMEFRAMES[timeframe])

    tmp = dst.with_suffix(".parquet.tmp")
    tmp.unlink(missing_ok=True)
    t0 = time.perf_counter()
    con.execute(
        f"COPY ({sql}) TO '{tmp.as_posix()}' "
        f"(FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 1000000)"
    )

    rel = f"read_parquet('{tmp.as_posix()}')"
    n_bars, ticks_in_bars, ts_min, ts_max = con.sql(
        f"SELECT count(*), sum(tick_count), min(ts)::VARCHAR, max(ts)::VARCHAR FROM {rel}"
    ).fetchone()
    n_ticks_src = con.sql(f"SELECT count(*) FROM read_parquet('{src.as_posix()}')").fetchone()[0]
    # Reconciliation: every clean tick must land in exactly one bar.
    bad_ohlc = con.sql(
        f"SELECT count(*) FROM {rel} WHERE NOT (low <= open AND low <= close "
        f"AND high >= open AND high >= close AND high >= low)"
    ).fetchone()[0]
    elapsed = round(time.perf_counter() - t0, 1)
    con.close()
    tmp.replace(dst)

    stats = dict(
        symbol=symbol, timeframe=timeframe, year=year, n_bars=n_bars,
        ticks_in_bars=int(ticks_in_bars), ticks_src=n_ticks_src,
        reconciled=(int(ticks_in_bars) == n_ticks_src), bad_ohlc=bad_ohlc,
        ts_min=ts_min, ts_max=ts_max, elapsed_s=elapsed,
    )
    flag = "OK" if (stats["reconciled"] and bad_ohlc == 0) else "CHECK"
    log.info("[%s %s %s] %s bars from %s ticks  [%s]  %ss",
             symbol, timeframe, year, f"{n_bars:,}", f"{n_ticks_src:,}", flag, elapsed)
    if not stats["reconciled"]:
        log.warning("  tick reconciliation MISMATCH: in_bars=%s src=%s",
                    f"{int(ticks_in_bars):,}", f"{n_ticks_src:,}")
    if bad_ohlc:
        log.warning("  %s bars with inconsistent OHLC", bad_ohlc)
    return stats


def build_symbol(
    symbol: str,
    years: list[int] | None = None,
    timeframes: list[str] | None = None,
    *,
    overwrite: bool = False,
    memory_limit: str = "6GB",
) -> list[dict]:
    tfs = timeframes or list(TIMEFRAMES)
    available = config.discover_raw_files(symbol)
    target_years = sorted(available) if years is None else sorted(years)
    out: list[dict] = []
    for year in target_years:
        src = config.clean_path(symbol, year)
        if not src.exists():
            log.warning("[%s] no clean ticks for %s (%s) — run /quant-validate-data first",
                        symbol, year, src.name)
            continue
        for tf in tfs:
            dst = config.bars_path(symbol, tf, year)
            if dst.exists() and not overwrite:
                log.info("[%s %s %s] %s exists — skipping (use --force)", symbol, tf, year, dst.name)
                continue
            out.append(build_bars_file(src, symbol=symbol, timeframe=tf, year=year,
                                       overwrite=overwrite, memory_limit=memory_limit))
    return out


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Phase 3 — build M1/M3 bars from clean ticks")
    p.add_argument("--symbol", default="btcusd")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--all", action="store_true")
    g.add_argument("--years", type=int, nargs="+")
    p.add_argument("--timeframes", nargs="+", default=list(TIMEFRAMES), choices=list(TIMEFRAMES))
    p.add_argument("--force", action="store_true")
    p.add_argument("--memory-limit", default="6GB")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args = _parse_args(argv)
    years = None if (args.all or not args.years) else args.years
    res = build_symbol(args.symbol, years, args.timeframes,
                       overwrite=args.force, memory_limit=args.memory_limit)
    if not res:
        log.info("Nothing built.")
        return 0
    log.info("\n=== Summary: %d bar file(s) ===", len(res))
    ok = all(r["reconciled"] and r["bad_ohlc"] == 0 for r in res)
    for r in res:
        log.info("  %s %s %s: %s bars (reconciled=%s)",
                 r["symbol"], r["timeframe"], r["year"], f"{r['n_bars']:,}", r["reconciled"])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
