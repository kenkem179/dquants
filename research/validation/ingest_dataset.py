#!/usr/bin/env python3
"""Cross-broker dataset ingest (DuckDB) for KenKem Quant OS robustness validation.

Goal: take a raw tick/bar export from ANY broker (OANDA / Exness / Binance / ...) for
BTCUSD or XAUUSD and normalise it — with DuckDB doing the heavy multi-GB read — into the
EXACT artifacts the dependency-free C++ engines already consume:

  <out>/<name>_canonical.parquet     ts(TIMESTAMP, UTC), bid, ask          (the normal form)
  <out>/<name>_m1.csv                ts_ms,open,high,low,close,tick_count  (BID OHLC, M1)
  <out>/<name>_m3.csv                "" M3
  <out>/<name>_m5.csv                "" M5
  <out>/<name>_ticks.csv             ts_ms,bid,ask                          (window-clipped)

Bars are BID OHLC with per-bar tick_count, identical construction to
cpp_core/tools/common/export_bars.py (which matched the MT5 tester) — so an edge proven on
our Exness data can be re-checked byte-for-byte on someone else's feed.

This does NOT need any data to exist yet — it is the ready-to-run pipe. Point it at a
dataset spec (see datasets.example.json) once you drop files in. Supported raw `format`s:

  mt5_tab            tab-separated MT5 tick export: <DATE> <TIME> <BID> <ASK> <LAST> <VOL> <FLAGS>
                     (Exness/most MT5 brokers). DATE=YYYY.MM.DD TIME=HH:MM:SS.mmm
  bidask_csv         generic CSV w/ explicit bid+ask columns (OANDA-style). Configure
                     ts_col / ts_format (or ts_unit=ms|s for epoch), bid_col, ask_col, sep.
  price_csv          generic CSV w/ a single price column + synthetic spread. Configure
                     ts_col/ts_format/ts_unit, price_col, sep, and half_spread (price units)
                     or half_spread_bps. (Binance aggTrades, any last-price tape.)
  binance_aggtrades  Binance aggTrades CSV (no header): aggId,price,qty,firstId,lastId,
                     ts_ms,isBuyerMaker,isBestMatch — price tape; needs half_spread*.
  binance_klines     Binance 1m klines CSV (no header): openTime_ms,o,h,l,c,vol,closeTime,...
                     Already OHLC bars; we use them as the M1 base and synthesise a 4-tick
                     (O->L->H->C) stream per bar with half_spread* for fill timing.

Usage:
  python research/validation/ingest_dataset.py <datasets.json> [name1 name2 ...]
  (no names => ingest every dataset in the spec)
"""
import json
import os
import sys

import duckdb

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Reasonable synthetic half-spread defaults (price units) when a feed has no ask side.
DEFAULT_HALF_SPREAD = {"btc": 1.0, "xau": 0.05}


def _ts_expr(ds):
    """SQL expression yielding a TIMESTAMP from the spec's ts config (for *_csv formats)."""
    col = ds["ts_col"]
    unit = ds.get("ts_unit")  # 'ms' or 's' => epoch; else parse a string
    if unit == "ms":
        return f"make_timestamp(\"{col}\"::BIGINT * 1000)"
    if unit == "s":
        return f"make_timestamp(\"{col}\"::BIGINT * 1000000)"
    fmt = ds.get("ts_format")
    if fmt:
        return f"strptime(\"{col}\"::VARCHAR, '{fmt}')"
    return f"\"{col}\"::TIMESTAMP"


def canonical_select(ds):
    """Return a SQL SELECT producing columns (ts TIMESTAMP, bid DOUBLE, ask DOUBLE).
    Reads the raw file via DuckDB; one branch per supported `format`.
    """
    fmt = ds["format"]
    raw = ds["raw"] if os.path.isabs(ds["raw"]) else os.path.join(ROOT, ds["raw"])
    sym = ds["symbol"]
    hs = ds.get("half_spread")
    if hs is None and ds.get("half_spread_bps") is None:
        hs = DEFAULT_HALF_SPREAD.get(sym, 0.0)

    def with_synth_spread(price_expr, ts_expr):
        if ds.get("half_spread_bps") is not None:
            h = f"({price_expr}) * {float(ds['half_spread_bps'])} / 1e4"
        else:
            h = f"{float(hs)}"
        return (f"select {ts_expr} as ts, ({price_expr}) - ({h}) as bid, "
                f"({price_expr}) + ({h}) as ask")

    if fmt == "mt5_tab":
        # tab-separated; column names from the header line (<DATE> <TIME> <BID> <ASK> ...).
        # all_varchar so DuckDB does NOT auto-parse <DATE> to a DATE (which would drop the
        # dotted format); strptime the dotted DATE + millisecond TIME ourselves.
        return (
            f"select strptime(\"<DATE>\" || ' ' || \"<TIME>\", '%Y.%m.%d %H:%M:%S.%f') as ts, "
            f"\"<BID>\"::DOUBLE as bid, \"<ASK>\"::DOUBLE as ask "
            f"from read_csv_auto('{raw}', delim='\\t', header=true, all_varchar=true) "
            f"where \"<BID>\"::DOUBLE > 0 and \"<ASK>\"::DOUBLE > 0")

    if fmt == "bidask_csv":
        sep = ds.get("sep", ",")
        ts = _ts_expr(ds)
        return (
            f"select {ts} as ts, \"{ds['bid_col']}\"::DOUBLE as bid, "
            f"\"{ds['ask_col']}\"::DOUBLE as ask "
            f"from read_csv_auto('{raw}', delim='{sep}', header=true) "
            f"where \"{ds['bid_col']}\" > 0 and \"{ds['ask_col']}\" > 0")

    if fmt == "price_csv":
        sep = ds.get("sep", ",")
        ts = _ts_expr(ds)
        price = f"\"{ds['price_col']}\"::DOUBLE"
        inner = (f"select * from read_csv_auto('{raw}', delim='{sep}', header=true) "
                 f"where \"{ds['price_col']}\" > 0")
        return with_synth_spread(price, ts).replace("from", f"from ({inner})", 1) + ""

    if fmt == "binance_aggtrades":
        cols = "aggId BIGINT, price DOUBLE, qty DOUBLE, firstId BIGINT, lastId BIGINT, ts_ms BIGINT, isBuyerMaker BOOLEAN, isBestMatch BOOLEAN"
        inner = (f"select * from read_csv('{raw}', header=false, columns={{{_quote_cols(cols)}}}) "
                 f"where price > 0")
        return with_synth_spread("price", "make_timestamp(ts_ms*1000)").replace(
            "from", f"from ({inner})", 1)

    raise SystemExit(f"unsupported format for canonical ticks: {fmt}")


def _quote_cols(spec):
    parts = []
    for c in spec.split(","):
        name, typ = c.strip().split(" ", 1)
        parts.append(f"'{name}': '{typ}'")
    return ", ".join(parts)


def window_clause(ds, tscol="ts"):
    w = ds.get("window")
    if not w:
        return ""
    start, end = w
    return f"where {tscol} >= timestamp '{start}' and {tscol} < timestamp '{end}'"


def emit_bars(con, canonical, out_csv, minutes, window):
    con.sql(f"""
        copy (
          with b as (
            select time_bucket(interval '{minutes} minutes', ts) as bts,
                   epoch_ms(time_bucket(interval '{minutes} minutes', ts)) as ts_ms,
                   arg_min(bid, ts) as open, max(bid) as high,
                   min(bid) as low, arg_max(bid, ts) as close, count(*) as tick_count
            from '{canonical}' {window_clause({'window': window})}
            group by 1
          )
          select ts_ms, open, high, low, close, tick_count from b order by bts
        ) to '{out_csv}' (header, delimiter ',')
    """)


def emit_ticks(con, canonical, out_csv, window):
    con.sql(f"""
        copy (
          select epoch_ms(ts) as ts_ms, bid, ask
          from '{canonical}' {window_clause({'window': window})}
          order by ts
        ) to '{out_csv}' (header, delimiter ',')
    """)


def ingest_one(ds, outdir):
    name = ds["name"]
    os.makedirs(outdir, exist_ok=True)
    con = duckdb.connect()
    canon = os.path.join(outdir, f"{name}_canonical.parquet")

    if ds["format"] == "binance_klines":
        _ingest_klines(ds, con, canon)
    else:
        sel = canonical_select(ds)
        con.sql(f"copy ({sel} order by ts) to '{canon}' (format parquet)")

    window = ds.get("window")
    for m, tf in ((1, "m1"), (3, "m3"), (5, "m5")):
        emit_bars(con, canon, os.path.join(outdir, f"{name}_{tf}.csv"), m, window)
    emit_ticks(con, canon, os.path.join(outdir, f"{name}_ticks.csv"), window)

    info = con.sql(f"select count(*) c, min(ts) lo, max(ts) hi from '{canon}'").fetchone()
    print(f"[ingest] {name}: {info[0]} ticks {info[1]}..{info[2]} -> {outdir}/{name}_*")


def _ingest_klines(ds, con, canon):
    """Binance 1m klines -> synthesise a 4-tick (O->L->H->C) tape per bar so the tick
    engines have fill timing. Half-spread applied symmetrically."""
    raw = ds["raw"] if os.path.isabs(ds["raw"]) else os.path.join(ROOT, ds["raw"])
    sym = ds["symbol"]
    hs = ds.get("half_spread", DEFAULT_HALF_SPREAD.get(sym, 0.0))
    bps = ds.get("half_spread_bps")
    cols = ("openTime BIGINT, o DOUBLE, h DOUBLE, l DOUBLE, c DOUBLE, vol DOUBLE, "
            "closeTime BIGINT, qav DOUBLE, ntrades BIGINT, tbb DOUBLE, tbq DOUBLE, ignore DOUBLE")
    h = f"(mid * {float(bps)} / 1e4)" if bps is not None else f"{float(hs)}"
    # Four synthetic ticks at +0,+15,+30,+45s within each 1m bar, price O,L,H,C.
    con.sql(f"""
        copy (
          with k as (select * from read_csv('{raw}', header=false, columns={{{_quote_cols(cols)}}})),
          t as (
            select openTime + off as ts_ms_raw, px as mid from k,
            (values (0,'o'),(15000,'l'),(30000,'h'),(45000,'c')) as s(off,which)
            cross join lateral (select case s.which when 'o' then k.o when 'l' then k.l
                                            when 'h' then k.h else k.c end as px) p
          )
          select make_timestamp(ts_ms_raw*1000) as ts, mid - {h} as bid, mid + {h} as ask
          from t order by ts_ms_raw
        ) to '{canon}' (format parquet)
    """)


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: ingest_dataset.py <datasets.json> [name ...]")
    spec_path = sys.argv[1]
    spec = json.load(open(spec_path))
    outdir = spec.get("outdir", "data/external/normalized")
    outdir = outdir if os.path.isabs(outdir) else os.path.join(ROOT, outdir)
    wanted = set(sys.argv[2:])
    for ds in spec["datasets"]:
        if wanted and ds["name"] not in wanted:
            continue
        ingest_one(ds, outdir)


if __name__ == "__main__":
    main()
