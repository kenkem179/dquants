"""Phase 2 — Validate & Clean Data.

Validate imported tick Parquet and write a cleaned variant plus a human-readable report. Bad ticks
are the #1 source of fake edges, so this is a hard gate before bar/feature construction.

Design choices (see docs/KENKEM_QUANT_OS.md §3):

* **Non-destructive.** Cleaning writes ``ticks_<symbol>_<year>_clean.parquet`` and never mutates the
  Phase-1 import — the raw→processed flow stays one-directional and auditable.
* **Drop** (clearly bad): non-positive prices, negative (crossed) spread, *exact-duplicate rows*
  (same ts AND bid AND ask as the previous tick — a double-export artifact), and *round-trip price
  spikes* (a single tick that jumps beyond a threshold and immediately reverts — maintenance glitch).
* **Keep + report** (legitimate but noteworthy): *timestamp collisions* (distinct ticks sharing one
  millisecond — real sub-ms ticks, NOT duplicates), zero spreads, unusually wide spreads, and time
  gaps. These are flagged in the report so a human can judge, never silently deleted.

Window functions use ``OVER ()`` (no ORDER BY) and rely on the Parquet being ts-ordered, which the
Phase-1 importer guarantees and verifies (monotonic check) — this keeps the pass streaming and cheap.

Usage
-----
    python -m pipeline.validate_data --symbol btcusd --all
    python -m pipeline.validate_data --symbol btcusd --years 2025 --force
"""
from __future__ import annotations

import argparse
import dataclasses
import json
import logging
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import duckdb

from . import config

log = logging.getLogger("validate_data")

# Defaults
SPIKE_THRESHOLD = 0.01      # round-trip single-tick move (1%) flagged as a spike
WIDE_SPREAD_MULT = 5.0      # spread > this * median is "wide" (flag only)
GAP_BUCKETS_S = [1, 10, 60, 300, 3600]
LOW_DAY_FRACTION = 0.25     # a day with < this * median ticks is "low coverage" (flag only)


def clean_path(symbol: str, year: int | str) -> Path:
    return config.PROCESSED_DIR / f"ticks_{symbol.lower()}_{year}_clean.parquet"


def report_path(symbol: str, year: int | str, ext: str) -> Path:
    return config.REPORTS_DIR / f"validation_{symbol.lower()}_{year}.{ext}"


@dataclass
class ValidationReport:
    symbol: str
    year: int
    src: str
    clean_dst: str
    total_in: int
    total_kept: int
    dropped: dict = field(default_factory=dict)      # reason -> count (rows removed)
    flagged: dict = field(default_factory=dict)      # reason -> count (kept but noted)
    spread: dict = field(default_factory=dict)
    gaps: dict = field(default_factory=dict)
    coverage: dict = field(default_factory=dict)
    residual: dict = field(default_factory=dict)     # post-clean leftovers (drop reasons -> count)
    passed: bool = False
    elapsed_s: float = 0.0

    @property
    def total_dropped(self) -> int:
        return self.total_in - self.total_kept


# ----- core SQL -----

def _flagged_cte(src_posix: str, spike_threshold: float) -> str:
    """A CTE 'flagged' classifying every row; reused for counting and for the clean COPY."""
    return f"""
    WITH ordered AS (
        SELECT ts, bid, ask, mid, spread, flags,
               lag(ts)  OVER () AS prev_ts,
               lag(bid) OVER () AS prev_bid,
               lag(ask) OVER () AS prev_ask,
               lag(mid) OVER () AS prev_mid,
               lead(mid) OVER () AS next_mid
        FROM read_parquet('{src_posix}')
    ),
    flagged AS (
        SELECT ts, bid, ask, mid, spread, flags,
            (bid <= 0 OR ask <= 0)                                   AS bad_px,
            (spread < 0)                                             AS neg_spread,
            (prev_ts IS NOT NULL AND ts = prev_ts
                AND bid = prev_bid AND ask = prev_ask)               AS exact_dup,
            (prev_ts IS NOT NULL AND ts = prev_ts
                AND NOT (bid = prev_bid AND ask = prev_ask))         AS ts_collision,
            (prev_mid IS NOT NULL AND next_mid IS NOT NULL AND prev_mid > 0
                AND abs(mid - prev_mid) / prev_mid > {spike_threshold}
                AND abs(next_mid - prev_mid) / prev_mid < {spike_threshold} / 2.0) AS spike,
            (spread = 0)                                             AS zero_spread
        FROM ordered
    )
    """


_KEEP = "NOT bad_px AND NOT neg_spread AND NOT exact_dup AND NOT spike"


def _connect(memory_limit: str) -> duckdb.DuckDBPyConnection:
    con = duckdb.connect()
    con.execute(f"SET memory_limit='{memory_limit}'")
    con.execute("SET preserve_insertion_order=true")
    return con


def validate_file(
    src: Path,
    *,
    symbol: str,
    year: int,
    spike_threshold: float = SPIKE_THRESHOLD,
    memory_limit: str = "6GB",
    overwrite: bool = False,
    write_report: bool = True,
) -> ValidationReport:
    dst = clean_path(symbol, year)
    if dst.exists() and not overwrite:
        raise FileExistsError(f"{dst} exists (use --force to overwrite)")
    dst.parent.mkdir(parents=True, exist_ok=True)
    config.REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    con = _connect(memory_limit)
    cte = _flagged_cte(src.as_posix(), spike_threshold)
    t0 = time.perf_counter()

    # 1. Classification counts (single streaming pass).
    counts = con.sql(f"""
        {cte}
        SELECT
            count(*) AS total_in,
            count(*) FILTER (WHERE bad_px)       AS bad_px,
            count(*) FILTER (WHERE neg_spread)   AS neg_spread,
            count(*) FILTER (WHERE exact_dup)    AS exact_dup,
            count(*) FILTER (WHERE spike)        AS spike,
            count(*) FILTER (WHERE ts_collision) AS ts_collision,
            count(*) FILTER (WHERE zero_spread)  AS zero_spread,
            count(*) FILTER (WHERE {_KEEP})      AS kept
        FROM flagged
    """).fetchone()
    (total_in, bad_px, neg_spread, exact_dup, spike, ts_collision, zero_spread, kept) = counts

    # 2. Write cleaned Parquet (recompute the CTE; OVER() pass is cheap/streaming).
    tmp = dst.with_suffix(".parquet.tmp")
    tmp.unlink(missing_ok=True)
    con.execute(f"""
        COPY (
            {cte}
            SELECT ts, bid, ask, mid, spread, flags FROM flagged WHERE {_KEEP}
        )
        TO '{tmp.as_posix()}' (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 1000000)
    """)

    # 3. Stats on the CLEAN output.
    rel = f"read_parquet('{tmp.as_posix()}')"
    s = con.sql(f"""
        SELECT round(avg(spread),4) mean, round(median(spread),4) med,
               round(quantile_cont(spread,0.95),4) p95, round(quantile_cont(spread,0.99),4) p99,
               round(min(spread),4) mn, round(max(spread),4) mx
        FROM {rel}
    """).fetchone()
    spread = dict(mean=s[0], median=s[1], p95=s[2], p99=s[3], min=s[4], max=s[5])
    wide_spread = con.sql(
        f"SELECT count(*) FROM {rel} WHERE spread > {WIDE_SPREAD_MULT} * {spread['median']}"
    ).fetchone()[0]

    # gaps
    gap_sql = ", ".join(
        f"count(*) FILTER (WHERE gs > {b}) AS gt_{b}s" for b in GAP_BUCKETS_S
    )
    grow = con.sql(f"""
        WITH g AS (SELECT date_part('epoch', ts - lag(ts) OVER ()) AS gs FROM {rel})
        SELECT {gap_sql}, round(max(gs),1) AS max_gap_s FROM g
    """).fetchone()
    gaps = {f"gt_{b}s": grow[i] for i, b in enumerate(GAP_BUCKETS_S)}
    gaps["max_gap_s"] = grow[-1]
    top_gaps = con.sql(f"""
        WITH g AS (SELECT ts, lag(ts) OVER () AS pts,
                          date_part('epoch', ts - lag(ts) OVER ()) AS gs FROM {rel})
        SELECT pts::VARCHAR, ts::VARCHAR, round(gs,1) FROM g
        WHERE gs IS NOT NULL ORDER BY gs DESC LIMIT 5
    """).fetchall()
    gaps["top"] = [{"start": a, "end": b, "gap_s": c} for a, b, c in top_gaps]

    # coverage
    cov = con.sql(f"""
        WITH d AS (SELECT ts::DATE AS day, count(*) AS c FROM {rel} GROUP BY 1)
        SELECT count(*) AS n_days, min(c) AS min_day,
               round(median(c)) AS med_day, max(c) AS max_day,
               min(day)::VARCHAR AS first_day, max(day)::VARCHAR AS last_day FROM d
    """).fetchone()
    coverage = dict(n_days=cov[0], min_day=cov[1], med_day=cov[2], max_day=cov[3],
                    first_day=cov[4], last_day=cov[5])
    low_days = con.sql(f"""
        WITH d AS (SELECT ts::DATE AS day, count(*) AS c FROM {rel} GROUP BY 1)
        SELECT day::VARCHAR, c FROM d
        WHERE c < {LOW_DAY_FRACTION} * (SELECT median(c) FROM d) ORDER BY c LIMIT 10
    """).fetchall()
    coverage["low_days"] = [{"day": d, "ticks": c} for d, c in low_days]
    present_hours = {r[0] for r in con.sql(
        f"SELECT DISTINCT date_part('hour', ts)::INT FROM {rel}"
    ).fetchall()}
    coverage["missing_hours"] = sorted(set(range(24)) - present_hours)

    # 4. Residual check on the clean output (drop reasons must be gone).
    res = con.sql(f"""
        WITH ordered AS (SELECT ts,bid,ask,spread, lag(ts) OVER () pts,
                                lag(bid) OVER () pb, lag(ask) OVER () pa FROM {rel})
        SELECT count(*) FILTER (WHERE bid<=0 OR ask<=0) bad_px,
               count(*) FILTER (WHERE spread<0) neg_spread,
               count(*) FILTER (WHERE pts IS NOT NULL AND ts=pts AND bid=pb AND ask=pa) exact_dup
        FROM ordered
    """).fetchone()
    residual = dict(bad_px=res[0], neg_spread=res[1], exact_dup=res[2])
    elapsed = round(time.perf_counter() - t0, 1)
    con.close()

    tmp.replace(dst)

    rep = ValidationReport(
        symbol=symbol, year=year, src=str(src), clean_dst=str(dst),
        total_in=total_in, total_kept=kept,
        dropped=dict(bad_px=bad_px, neg_spread=neg_spread, exact_dup=exact_dup, spike=spike),
        flagged=dict(ts_collision=ts_collision, zero_spread=zero_spread, wide_spread=wide_spread),
        spread=spread, gaps=gaps, coverage=coverage, residual=residual,
        passed=all(v == 0 for v in residual.values()),
        elapsed_s=elapsed,
    )
    _log_report(rep)
    if write_report:
        report_path(symbol, year, "json").write_text(json.dumps(dataclasses.asdict(rep), indent=2))
        report_path(symbol, year, "md").write_text(render_markdown(rep))
        log.info("  report -> %s", report_path(symbol, year, "md"))
    return rep


def _log_report(r: ValidationReport) -> None:
    log.info("[%s %s] %s rows -> %s kept (%s dropped)", r.symbol, r.year,
             f"{r.total_in:,}", f"{r.total_kept:,}", f"{r.total_dropped:,}")
    for k, v in r.dropped.items():
        if v:
            log.info("  drop %-12s %s", k, f"{v:,}")
    for k, v in r.flagged.items():
        if v:
            log.info("  flag %-12s %s", k, f"{v:,}")
    log.info("  spread median=%s p99=%s max=%s", r.spread["median"], r.spread["p99"], r.spread["max"])
    log.info("  coverage %s days (%s..%s), max gap %ss",
             r.coverage["n_days"], r.coverage["first_day"], r.coverage["last_day"],
             r.gaps["max_gap_s"])
    log.info("  residual %s -> %s", r.residual, "PASS" if r.passed else "FAIL")


def render_markdown(r: ValidationReport) -> str:
    pct = lambda n: f"{100*n/r.total_in:.3f}%" if r.total_in else "—"
    L = [
        f"# Validation Report — {r.symbol.upper()} {r.year}",
        "",
        f"- Source: `{Path(r.src).name}`",
        f"- Clean output: `{Path(r.clean_dst).name}`",
        f"- Status: **{'PASS' if r.passed else 'FAIL'}**  ·  validated in {r.elapsed_s}s",
        "",
        "## Row accounting",
        "",
        "| Metric | Rows | % |",
        "|---|---:|---:|",
        f"| Input | {r.total_in:,} | 100% |",
        f"| Kept (clean) | {r.total_kept:,} | {pct(r.total_kept)} |",
        f"| Dropped | {r.total_dropped:,} | {pct(r.total_dropped)} |",
        "",
        "### Dropped (removed — clearly bad)",
        "",
        "| Reason | Rows | % |",
        "|---|---:|---:|",
    ]
    L += [f"| {k} | {v:,} | {pct(v)} |" for k, v in r.dropped.items()]
    L += [
        "",
        "### Flagged (kept — noted for review)",
        "",
        "| Reason | Rows | Note |",
        "|---|---:|---|",
        f"| ts_collision | {r.flagged['ts_collision']:,} | distinct ticks sharing one ms — legitimate |",
        f"| zero_spread | {r.flagged['zero_spread']:,} | bid == ask |",
        f"| wide_spread | {r.flagged['wide_spread']:,} | spread > {WIDE_SPREAD_MULT}× median |",
        "",
        "## Spread distribution (clean)",
        "",
        "| mean | median | p95 | p99 | min | max |",
        "|---:|---:|---:|---:|---:|---:|",
        f"| {r.spread['mean']} | {r.spread['median']} | {r.spread['p95']} | {r.spread['p99']} "
        f"| {r.spread['min']} | {r.spread['max']} |",
        "",
        "## Time gaps (clean)",
        "",
        "| > 1s | > 10s | > 60s | > 5m | > 1h | max gap |",
        "|---:|---:|---:|---:|---:|---:|",
        f"| {r.gaps['gt_1s']:,} | {r.gaps['gt_10s']:,} | {r.gaps['gt_60s']:,} "
        f"| {r.gaps['gt_300s']:,} | {r.gaps['gt_3600s']:,} | {r.gaps['max_gap_s']}s |",
        "",
        "Largest gaps:",
        "",
        "| start | end | gap (s) |",
        "|---|---|---:|",
    ]
    L += [f"| {g['start']} | {g['end']} | {g['gap_s']} |" for g in r.gaps["top"]]
    cov = r.coverage
    L += [
        "",
        "## Coverage (clean)",
        "",
        f"- Days with data: **{cov['n_days']}** ({cov['first_day']} → {cov['last_day']})",
        f"- Ticks/day: min {cov['min_day']:,} · median {int(cov['med_day']):,} · max {cov['max_day']:,}",
        f"- Missing hours-of-day (across whole year): "
        f"{cov['missing_hours'] if cov['missing_hours'] else 'none'}",
    ]
    if cov["low_days"]:
        L += ["", "Low-coverage days (< 25% of median):", "",
              "| day | ticks |", "|---|---:|"]
        L += [f"| {d['day']} | {d['ticks']:,} |" for d in cov["low_days"]]
    L += [
        "",
        "## Residual check (post-clean — must all be 0)",
        "",
        "| bad_px | neg_spread | exact_dup |",
        "|---:|---:|---:|",
        f"| {r.residual['bad_px']} | {r.residual['neg_spread']} | {r.residual['exact_dup']} |",
        "",
    ]
    return "\n".join(L)


def validate_symbol(
    symbol: str, years: list[int] | None = None, *,
    overwrite: bool = False, memory_limit: str = "6GB",
) -> list[ValidationReport]:
    available = config.discover_raw_files(symbol)  # discover by year via raw files
    targets = sorted(available) if years is None else sorted(years)
    out: list[ValidationReport] = []
    for year in targets:
        src = config.processed_path(symbol, year)
        if not src.exists():
            log.warning("[%s] no imported Parquet for %s (%s) — run /quant-import-data first",
                        symbol, year, src.name)
            continue
        dst = clean_path(symbol, year)
        if dst.exists() and not overwrite:
            log.info("[%s %s] %s exists — skipping (use --force)", symbol, year, dst.name)
            continue
        out.append(validate_file(src, symbol=symbol, year=year,
                                 overwrite=overwrite, memory_limit=memory_limit))
    return out


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Phase 2 — validate & clean tick Parquet")
    p.add_argument("--symbol", default="btcusd")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--all", action="store_true")
    g.add_argument("--years", type=int, nargs="+")
    p.add_argument("--force", action="store_true", help="overwrite existing clean Parquet")
    p.add_argument("--memory-limit", default="6GB")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args = _parse_args(argv)
    years = None if (args.all or not args.years) else args.years
    reports = validate_symbol(args.symbol, years, overwrite=args.force,
                              memory_limit=args.memory_limit)
    if not reports:
        log.info("Nothing validated.")
        return 0
    log.info("\n=== Summary: %d file(s) validated ===", len(reports))
    for r in reports:
        log.info("  %s %s: kept %s / %s (%s dropped) — %s",
                 r.symbol, r.year, f"{r.total_kept:,}", f"{r.total_in:,}",
                 f"{r.total_dropped:,}", "PASS" if r.passed else "FAIL")
    return 0 if all(r.passed for r in reports) else 1


if __name__ == "__main__":
    sys.exit(main())
