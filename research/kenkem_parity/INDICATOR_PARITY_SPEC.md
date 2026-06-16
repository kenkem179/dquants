# Stage 1 — KenKem indicator parity (SOLVED) + the reusable methodology

**Result (Feb 2026 XAU M1, joined `cpp_ts−60000 == mt5_ts`):** 5 of 6 indicator families now **bit-exact**
vs the MT5 `trace_XAUUSD-Exness-KK.csv`; ATR is a documented ~2% tick-completeness residual.

| trace col | mean\|Δ\| before | mean\|Δ\| after | status |
|---|---|---|---|
| ema0–4 | 1.27 | **0.00008** | ✅ exact |
| rsi | 2.59 | **0.00046** | ✅ exact |
| high / low | 2.0 | **0.00001** | ✅ exact |
| close | ~0 | 0.00008 | ✅ exact |
| adx_m1/m3/m5/m15, diP/diM | ~0 | ~0 | ✅ exact |
| atr | 0.42 | 0.31 | ⚠️ ~2% residual (tick completeness, NOT formula) |
| atr_pctile | — | 10.9 | ⚠️ follows ATR (rank-sensitive) |

## The bugs (all were "distillation" assumptions; fixed by reading the EA, not guessing)

1. **EMA was 2 bars too fresh.** `GetEMA(...,ENTRY_SHIFT=1)` reads a **non-series** `CopyBuffer(h,0,0,
   ENTRY_SHIFT+3,tmp)` then indexes `tmp[1]` → that is **shift 2**, and the indicator buffer's 1-bar
   recompute lag on a new bar makes the effective value `EMA(close)[i−2]`. Measured purely inside MT5's
   own file: `ema[i] == EMA(close)[i−2]`. **Fix:** `build_snapshot` reads `ema[i1−2]` (2 bars behind
   `close`, which is at `i1`). This lagged EMA is the EA's REAL trading behavior (all entries call
   `GetEMA`), so it must propagate everywhere — it does, because the snapshot is the single source.

2. **RSI was raw, not the 5-bar average.** `r.rsi = GetRSIAverage(TF0, RSI_LEN, 5)` = mean of `iRSI(14)`
   over **shifts 0..4** (forming + 4 closed), counting only values > 0. **Fix:** MT5-faithful Wilder RSI
   (SMA-seeded at index n, exposing avg-gain/avg-loss), one Wilder step for the forming bar, average 5.

3. **shift-0 reads model the FORMING bar at its first tick.** `cache.atrM1`, `cache.high/low`, and the
   shift-0 RSI element are read at shift 0. On the first tick of a new bar O=H=L=C=open (proven: MT5
   trace shows `high==low` ≠ close). **Fix:** `high=low=open_forming`; ATR/RSI take ONE Wilder step using
   the forming TR/gain = `|open_forming − prevClose|`. This is faithful, not lookahead (open is known at
   bar start; the future bar's real high/low/close are never touched).

4. **adxS/diPS/diMS are E5-trace placeholders.** The EA's `Entry5::TraceBar` mirrors M1 ADX(14) into
   these columns (they are not separate-period gate inputs). Confirmed `adxS==adx_m1` exactly in MT5.
   **Fix:** mirror `s.adx[0]` etc. (Do NOT compute ADX(9) for the trace.)

5. **Trace label off-by-one (diagnostic only).** C++ `trace_dumper` labels each row with the FORMING
   bar's open time while filling it with shift-1 data; MT5 labels with the closed bar's own time. So the
   diff must join `cpp_ts − 60000 == mt5_ts`. (Underlying bars are identical; this is not a logic bug.)

## ATR residual — why it's left and why that's correct
Bid/mid/ask bar construction all yield the SAME ~0.306 ATR Δ, so it is not a price-basis bug; the
smoothing (Wilder SMMA) is right (every other indicator built on the same bars is exact). The bar OPENs
match MT5 to 1e-5 (identical first tick) but intra-minute high/low differ → MT5's real-tick stream
contained mid-bar extremes the exported tick set did not. Closing it needs either the full MT5 tick set
or an MT5 export of **closed-bar OHLC**; the user has (reasonably) called a halt on new MT5 runs. ATR
feeds only the ATR-percentile gate and SL distance — re-examine ONLY if trade-level parity shows an
ATR-driven mismatch among the 9 trades.

## THE METHODOLOGY (reuse verbatim for MasterVP, MonsterEdition)
1. **Never assume a formula — read the handle + its read.** For every indicator: find `iXxx(...)` (period,
   applied price) AND the `CopyBuffer(handle, buf, start, count, dest)` that consumes it. The shift the
   logic actually sees = `start` + (dest-array indexing). **Non-series dest arrays invert the index** →
   that is how the EMA "shift 1" became shift 2. This single trap will recur.
2. **shift 0 == forming bar == first-tick open** in a closed-bar replay (O=H=L=C=open). Model it as a
   one-step Wilder/EMA update from the last closed value; never read the future bar's full OHLC.
3. **Some trace columns are placeholders** for the entry the trace belongs to — confirm against the EA
   before trying to match them (adxS here).
4. **Validate on a fixed join, column-by-column, post-warmup**, driving each family to ~0 before touching
   the next layer. A "best-shift per field" heuristic LIES on smooth series (it reported a fake 2-bar EMA
   gap); always confirm with an exact same-bar join.
5. **Localize residuals to formula vs data.** If every indicator on the same bars is exact except one,
   the lone outlier is a data/input problem, not a formula — don't burn cycles "fixing" correct math.

Implementation: `cpp_core/include/kk/mastervp/indicators.hpp` (`rsi_wilder_mt5`, `rsi_wilder_step`),
`cpp_core/include/kk/kenkem/tf_cache.hpp` (rsi_ag/rsi_al), `cpp_core/include/kk/kenkem/snapshot.hpp`
(per-indicator shifts). Re-diff: regenerate `trace_cpp_xau_2026feb.csv`, join `cpp_ts−60000`.
