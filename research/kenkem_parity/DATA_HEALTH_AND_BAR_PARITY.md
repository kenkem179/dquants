# Bar parity is SOLVED — the "ATR doesn't match" was a join bug + missing tick days

_2026-06-17, Claude (Opus 4.8). Supersedes the "~2% tick-completeness ATR residual" conclusion in
INDICATOR_PARITY_SPEC.md §"ATR residual" and the HANDOFF "THE WALL" section._

## TL;DR
1. **The bars are bit-exact.** M1 BID OHLC built from the exported ticks matches the MT5 EA per-bar
   trace to **0.000000** (high/low/close, 82,048 XAU bars, 2025-03..05). M3/M5/M15 are exact by
   construction (deterministic max/min/last aggregation of bit-exact M1 — the same way MT5 builds HTF).
2. **Wilder ATR(14) matches to median |Δ| = 3e-6.** Not 2%. The earlier "0.31 / 2% residual" was a
   **measurement artifact**: the diagnostic joined on the wrong key. The correct join is
   `my_bar_open == trace_ts − 60000` (the EA trace labels each row with the bar's CLOSE time; a
   DuckDB/C++ bar is keyed by its OPEN time). At any other offset close is off by ~0.5 (one bar of
   drift) while ATR still looks ~right because ATR is smooth across adjacent bars — exactly the trap
   that produced a fake residual.
3. **The only real ATR error is data, not math.** Every ATR |Δ| spike sits on the first bars AFTER a
   multi-day hole in the exported ticks (price gapped over days the export lacks → one giant TR →
   Wilder carries it for ~28 bars). Example: XAU 2025-05-01 00:01 traceATR 1.64 vs myATR 4.71, decaying
   13/14 per bar — injected by the 2025-04-28..30 hole.

## The real defect: the exported XAU tick CSVs are MISSING whole trading days MT5's tester HAS
Proven: the MT5 trace contains continuous bars on 2025-04-28..30 (Mon-Wed, not holidays); the raw
export `data/xauusd/XAUUSD_ticks_mt5_2025_2026.csv` has **0 ticks** on those dates. The hole is in the
RAW source the user provided, faithfully carried through parquet → window CSV → bars (our pipeline adds
no loss). BTC (24/7) is essentially complete; XAU has holes:

| sym/year | missing weekdays (0 ticks) | notes |
|---|---|---|
| XAU 2025 | 04-18; **04-28..30 (3d)**; 05-16; 06-03; 06-30 | 04-18 = Good Friday (real holiday, OK). The rest look like export gaps. 04-28..30 PROVEN a hole. |
| XAU 2024 | 03-29; 08-12; 09-12; 09-30; **11-19..12-20 (≈5 wks, near-total)** | 03-29 = Good Friday (OK). The Nov-Dec block makes any 2024 XAU run unusable. |
| XAU 2026 | 04-01..03 | at the data cutoff (Apr 6); irrelevant to Feb-2026 anchor. |
| BTC all | none (2025-03-31 only) | usable as-is. |

**The Feb-2026 KenKem anchor window is CLEAN** (no missing weekdays; only normal 64-min daily Exness
breaks + US-holiday short sessions, which MT5 shares). So anchor parity needs **no new tick data**.

## Tools (reusable)
- `cpp_core/tools/common/build_bars.py` — ticks parquet → M1/M3/M5/M15 bid OHLC CSVs (HTF aggregated
  from M1, MT5-faithful) + a "MISSING weekdays" health report. `--sym --year --from --to --tfs --tag`.
- `cpp_core/tools/common/verify_bars_vs_trace.py` — proves a bars-M1 CSV is bit-exact vs an EA trace
  (the `−60000` join) and reports ATR |Δ|, pointing each spike at its data hole. A regression gate.

## What this changes
- The HANDOFF "ATR-percentile parity wall" was **half right** (data, not formula) but **mislocated**:
  it is not irreducible ±0.2/bar tick noise — it is concrete missing DAYS. Inside clean windows the
  ATR-percentile gate has no data excuse; any remaining mismatch is engine logic (forming-bar model),
  not bars.
- Action split: (a) verify the C++ pipeline on the CLEAN Feb-2026 anchor (needs the deleted MT5
  trace/trades re-exported); (b) for non-Feb windows, refetch the missing XAU tick days from MT5.
