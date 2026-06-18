#!/usr/bin/env python3
"""
Verify TICK-SOURCE PARITY between the C++ engine input and what the MT5 Strategy
Tester actually modeled — WITHOUT the (Windows-only) MetaTrader5 Python SDK.

Rationale (read before "improving" this):
  - The MT5 tester runs in "real ticks" mode, replaying the terminal's tick history
    base. The MetaTrader5 SDK's copy_ticks_range() reads that SAME base, so it can
    only RE-PULL the source the engine CSV was already exported from — it cannot show
    "the exact ticks the tester consumed". The tester.log's own modelling summary is
    the AUTHORITATIVE record of what the tester replayed.
  - This script compares that authoritative count (and bar count) against the engine's
    tick CSV, restricted to the EA-active window (MT5 shifts EA start forward for
    warmup, and counts modeled ticks/bars only from there).

Result on RUN_2026-06-18 (XAU 2yr E1E2): engine == MT5 to the TICK (162,657,649) and
to the BAR (848,532). Tick source is NOT a parity blocker; divergence is in EA logic.

Usage:
  ~/miniforge3/envs/kenkem/bin/python research/kenkem_parity/verify_tick_source_parity.py \
      --log  research/kenkem_parity/mt5_runs/<RUN>/tester.log.gz \
      --ticks cpp_core/tools/ticks_xauusd_2024_2026.csv
"""
import argparse, gzip, re, sys, datetime as dt
import duckdb


def parse_mt5_log(path):
    """Return (modeled_ticks, generated_bars, ea_start_ms) from the tester.log.gz."""
    txt = gzip.open(path, "rb").read().decode("utf-16", errors="replace")
    lines = txt.splitlines()

    ticks = bars = None
    m = None
    for l in lines:
        # "...,M1: 162657649 ticks, 848532 bars generated. Environment synchronized..."
        mm = re.search(r":\s*([\d]+)\s+ticks,\s*([\d]+)\s+bars generated", l)
        if mm:
            ticks, bars = int(mm.group(1)), int(mm.group(2))
            break

    ea_start_ms = None
    for l in lines:
        # "...start time changed to 2024.01.03 00:00 to provide data at beginning"
        mm = re.search(r"start time changed to (\d{4})\.(\d{2})\.(\d{2})\s+(\d{2}):(\d{2})", l)
        if mm:
            y, mo, d, hh, mm_ = map(int, mm.groups())
            ea_start_ms = int(dt.datetime(y, mo, d, hh, mm_, tzinfo=dt.timezone.utc).timestamp() * 1000)
            break

    if ticks is None:
        sys.exit("Could not find MT5 modelling summary ('N ticks, M bars generated') in log.")
    if ea_start_ms is None:
        sys.exit("Could not find EA start-time line ('start time changed to ...') in log.")
    return ticks, bars, ea_start_ms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True, help="MT5 tester.log.gz (UTF-16)")
    ap.add_argument("--ticks", required=True, help="engine tick CSV (ts_ms,bid,ask)")
    ap.add_argument("--bars", help="optional engine M1 bar CSV to cross-check bar count")
    args = ap.parse_args()

    mt5_ticks, mt5_bars, ea_start_ms = parse_mt5_log(args.log)
    print(f"MT5 tester (authoritative):  {mt5_ticks:,} ticks, {mt5_bars:,} bars")
    print(f"MT5 EA-start (UTC ms):       {ea_start_ms}  "
          f"({dt.datetime.fromtimestamp(ea_start_ms/1000, dt.timezone.utc)})")

    c = duckdb.connect()
    q = f"""
      SELECT
        count(*) FILTER (WHERE ts_ms <  {ea_start_ms}) AS warmup,
        count(*) FILTER (WHERE ts_ms >= {ea_start_ms}) AS active,
        count(*)                                        AS total
      FROM read_csv_auto('{args.ticks}')
    """
    warmup, active, total = c.execute(q).fetchone()
    print(f"\nengine ticks total:          {total:,}")
    print(f"engine ticks (warmup<start): {warmup:,}  (not modeled by MT5)")
    print(f"engine ticks (>= EA-start):  {active:,}")

    delta = active - mt5_ticks
    verdict = "EXACT ✅" if delta == 0 else f"MISMATCH ({delta:+,}) ❌"
    print(f"\nTICK PARITY (active window): {verdict}")

    if args.bars:
        nbars = sum(1 for _ in open(args.bars)) - 1  # minus header
        # MT5 counts bars from EA-start; engine includes warmup bars.
        print(f"\nengine M1 bars (file):       {nbars:,}")
        print(f"MT5 bars generated:          {mt5_bars:,}")
        print(f"engine - MT5 bar delta:      {nbars - mt5_bars:+,} "
              f"(expected = warmup bars before EA-start)")

    sys.exit(0 if delta == 0 else 1)


if __name__ == "__main__":
    main()
