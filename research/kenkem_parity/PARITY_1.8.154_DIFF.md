# 1.8.154 re-anchor — first C++ engine vs MT5 trace diff

_2026-06-17. Ground truth: `mt5_runs/RUN_2026-06-17_1.8.154_xau_feb/{parity_trace,trades}.csv`
(KenKemExpert v1.8.154, XAUUSD M1 every-tick, 2026.02.01–28, default config, 27,379 bars / 108 trade rows
incl. skipped-signal diagnostics). Symbol `XAUUSD-Exness-2426-Good`._

## Bars are PERFECT on this anchor too (the candle question is closed)
dquants M1 bars vs the fresh trace (join `my_open == trace_ts−60000`): **high/low max|Δ| 0.000000**,
close exact except **23 bars** off ≤0.226 (which tick is *last* in the minute — negligible tick-stream
micro-noise). C++ engine vs trace (same-ts): **close 99.9% exact, adx_m1 99.9%, adx_m3 100%** → bars +
ADX bit-exact. M3 Ichimoku values match (column-swapped, see below).

## What still differs = C++ engine 1.8.15→1.8.154 PORTING (not data)
Steady-state bar 2026-02-12 12:00 (engine | MT5):
| col | engine | MT5 | issue |
|---|---|---|---|
| close / adx_m1 | 5064.259 / 22.877 | 5064.259 / 22.877 | ✅ exact |
| ema0..4 | 5064.719.. | 5064.415.. | EMA read shift differs (~0.1–0.3); re-derive GetEMA(ENTRY_SHIFT) for 1.8.154 |
| tenkan, senkouA_m3 | 5065.002, 5067.441 | 5067.441, 5065.002 | **same values, swapped columns** — fix the engine trace label mapping (buffer-swap trap, version-specific) |
| sideways | 53 | 33 | GetSidewaysScore computation/shift changed |
| atr_pctile | 84.38 | 78.13 | follows atr + percentile reference (snapshot.hpp:172) |
| atr | 1.490 | 1.528 | engine forming model vs cache.atrM1; small steady-state, large at weekend-gap opens |
| rsi | 45.49 | **0.0** | the EA's `GetRSIAverage(...)` writes 0 in 1.8.154 → RSI likely renamed/unused in this trace; confirm in source before matching |

high/low columns differ wholesale because the engine trace emits the FORMING bar (O=H=L) while the EA
trace emits the CLOSED bar (shift 1) OHLC — a column-semantics difference, not a bar error (bars proven
exact via close+adx).

## Next (porting order, easiest signal first)
1. Ichimoku column-label swap in `trace_dumper`/snapshot so tenkan/kijun/senkouA/B line up → confirms M3 exact.
2. EMA shift: sweep i1, i1-1, i1-2 vs trace ema0 → pick the one matching 1.8.154 (the old i1-2 trap may have changed).
3. `rsi` column: read 1.8.154 GetRSIAverage — is it 0 by design? adjust the trace expectation.
4. sideways + atr_pctile: port GetSidewaysScore + the percentile reference to 1.8.154; re-diff.
5. Then config: the engine fired 0 signals (default xau specs ≠ 1.8.154 inputs) — align inputs, then trade-level diff vs `trades.csv` (47-col schema → adapt `diff_kenkem_trades.py`).

---
## Progress (2026-06-17, committed): indicator fixes + over-fire localized
**FIXED (committed `d1f0129`):**
- **EMA bit-exact** — `GetEMA(...,1)` = series-shift 2 = `i1-1` (was `i1-2`). All 5 EMAs now 0.00000
  vs trace (periods 10/25/71/97/192). This was a real engine bug affecting every EMA-based gate.
- **ATR-percentile reference** = forming `s.atrM1` (EA `cache.atrM1` shift-0), not closed. atr_pctile
  mean|Δ| 12.8→10.8.

**Indicator status vs trace:** close/ema0-4/adx_m1/adx_m3 **bit-exact**. atr forming residual ~0.19
(2%) = MT5 `cache.atrM1` is an INTRA-BAR read unreachable from M1 bars (engine Wilder is provably exact
vs Python, 0.00000) → atr_pctile inherits ~rank noise. The real, now-understood ATR-percentile wall.
RSI trace col = 0 on 99.6% of bars (EA `GetRSIAverage` lazy-handle bug in tester) → sideways RSI
component is effectively 0 in the EA; engine must mirror that.

**Engine TRADES fine** (not 0 — trace_dumper's "signal-fires" counter is unwired): Feb-2026 default
config = **45 trades, PF 1.225** (E1 18, E2 13, E4 14). EA executed ~15-20 (E1/E4 only; ALL E2 SKIPPED).

**OVER-FIRE localized (the next lever):** of 45 engine trades only **6 match an EA signal** (same
min+dir); **39 are engine-only** — gates passing where the EA's don't. Biggest chunk: engine fires
**13 E2 trades but the EA executes ZERO E2** (all 20 E2 signals SKIPPED by risk/limiter). So:
1. Engine E2 gate too loose AND/OR missing the limiter that skips every E2.
2. Engine lacks faithful downstream limiters (MAX_SESSION_LOSSES=4, MAX_SLTP_COUNT_PER_SESSION=7,
   MAX_HIGH_RISK_TRADES_PER_SESSION=5, one-entry-per-bar, min-seconds, max_concurrent, day cap).
3. Engine also MISSES most EA entries (only 6 overlap) → E1/E4 gate thresholds differ too.

**Next:** port the 1.8.154 Entry1/Entry2/Entry4 gate conditions + RiskManager skip rules verbatim;
diff engine trades vs the EA signal list (trades.csv incl. SKIPPED) until entry selection matches,
then limiters, then geometry/exits. The trades.csv carries per-signal indicator values to localize each.
