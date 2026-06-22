#!/usr/bin/env python3
"""
slice_ticks_by_fold.py — split a big tick CSV into per-fold slices in a SINGLE streaming pass.

Why: the WF harness re-streams the full tick file once per (combo x fold). For XAU that is 2.9 GB
and for BTC the full file is 8 GB — re-reading it ~100x per grid is the bottleneck. Slicing once into
6 small per-fold files turns every later combo run into a cheap read of the relevant slice only.

CORRECTNESS: in the full-file harness a fold run streams ticks to FILE END, so a position opened just
before the fold's trade_to is still managed by later ticks until it closes. KK-MasterVP force-closes
out-of-session (force_close_sess_news=true, sessions end daily), so every position closes within ~1
trading day. Each slice therefore covers [fold_start, fold_end + TAIL_MS] (TAIL default 2 days) so any
late-opened position has the ticks it needs to close exactly as in the full run. trade_to_ms (= fold_end)
still caps NEW opens, so the tail ticks only manage already-open positions. This is verified empirically
(wf_mvp_generic.py --verify-slice) to reproduce the full-file trades byte-for-byte before being trusted.

Usage:
  python3 slice_ticks_by_fold.py --ticks <full.csv> --out-dir <dir> --symbol {xau,btc}
"""
import argparse
from datetime import datetime, timezone
from pathlib import Path


def ms(y, m, d):
    return int(datetime(y, m, d, tzinfo=timezone.utc).timestamp() * 1000)


# Shared 6 disjoint calendar folds inside the XAU tick window (2025-06-19 .. 2026-05-29). BTC ticks
# cover this span too, so both symbols use identical calendar folds -> clean cross-market comparison.
FOLDS = [
    ("F1_2506", ms(2025, 6, 19), ms(2025, 8, 15)),
    ("F2_2508", ms(2025, 8, 15), ms(2025, 10, 15)),
    ("F3_2510", ms(2025, 10, 15), ms(2025, 12, 15)),
    ("F4_2512", ms(2025, 12, 15), ms(2026, 2, 15)),
    ("F5_2602", ms(2026, 2, 15), ms(2026, 4, 15)),
    ("F6_2604", ms(2026, 4, 15), ms(2026, 6, 1)),  # to slightly past XAU/BTC tick end
]
TAIL_MS = 2 * 86400 * 1000  # 2-day management tail so late-opened positions close as in full mode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ticks", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--symbol", required=True, choices=["xau", "btc"])
    a = ap.parse_args()

    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    # open one writer per fold; route each tick to every fold whose [start, end+TAIL) it falls in.
    writers, ranges = {}, []
    for name, frm, to in FOLDS:
        fh = open(out / f"ticks_{a.symbol}_{name}.csv", "w")
        fh.write("ts_ms,bid,ask\n")
        writers[name] = fh
        ranges.append((name, frm, to + TAIL_MS))

    n_in, n_out = 0, 0
    with open(a.ticks, "rb") as fi:
        first = True
        for raw in fi:
            if first:
                first = False
                if not raw[:1].isdigit():
                    continue
            # fast field extract: ts_ms is up to the first comma
            c = raw.find(b",")
            if c < 0:
                continue
            try:
                ts = int(raw[:c])
            except ValueError:
                continue
            n_in += 1
            for name, lo, hi in ranges:
                if lo <= ts < hi:
                    writers[name].write(raw.decode("ascii", "replace"))
                    n_out += 1
                    # folds + tails can overlap at boundaries; a tick may land in 2 slices -> keep going
    for fh in writers.values():
        fh.close()
    print(f"[slice] {a.symbol}: read {n_in:,} ticks -> wrote {n_out:,} slice-rows into {out}")
    for name, _, _ in FOLDS:
        p = out / f"ticks_{a.symbol}_{name}.csv"
        print(f"   {name}: {p.stat().st_size/1e6:.0f} MB")


if __name__ == "__main__":
    main()
