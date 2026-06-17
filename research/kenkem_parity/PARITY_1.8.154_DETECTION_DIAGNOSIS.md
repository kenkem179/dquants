# 1.8.154 parity — CORRECTED diagnosis: it's DETECTION, not limiters

_2026-06-17 (Opus 4.8). Supersedes the "over-fire / port limiters first" framing in HANDOFF + the
trade-level section of `PARITY_1.8.154_DIFF.md`. Ground truth = the EA's own 1.8.154 anchor run
(`mt5_runs/RUN_2026-06-17_1.8.154_xau_feb/{parity_trace,trades}.csv`, XAUUSD M1 every-tick, Feb-2026)._

## TL;DR
The C++ engine does **not over-fire a correct signal set** — it fires a **largely different** signal
set. With the exact 1.8.154 config (`anchor_1.8.154.set`, 173 keys applied) the engine produces **45
trades; only 1 is an exact-bar match to an EA-executed trade.** Limiters only *remove* engine trades —
they cannot recover the 8 EA trades the engine never detects. **Detection parity must come before
limiter parity.**

## How the EA actually behaved on this anchor (from the run log + trades.csv)
- **108 signal rows** logged (incl. SKIPPED diagnostics). After de-dup: **106 distinct signals**.
- **9 distinct EXECUTED trades** (`isEntering=true` in the log): E1×3 (2L/1S), E4×6 (3L/3S). **ZERO E2
  executed** — all 20 E2 signals SKIPPED.
- Dominant skip reasons (log): **ATR/volatility-percentile gates** ("Low volatility regime" =
  `MIN_ENTRY_ATR_PERCENTILE`, "too low/high" = `ATR_PERCENTILE_LOW/HIGH`) and **high-risk routing**
  (every E2 routes through `HandleHighRiskEntry`; blocked by risk-limits / weak-trend momentum).
- Config (logged inputs, saved to `anchor_1.8.154.set`): E1/E2/E4 on; CONV E1=7/E2=10/E4=9;
  TQ E1=6/E2=9/E4=9; `MIN_ENTRY_ATR_PERCENTILE=65`, `ATR_PERCENTILE_LOW=20/HIGH=90`,
  `ENABLE_ATR_HIGH_BLOCK=true`, `ATR_PERCENTILE_LOOKBACK=32`; `MIN_SECONDS_BETWEEN_ENTRIES=60`;
  `MAX_CONCURRENT_POSITIONS_ALLOWED=2`; `MAX_SESSION_LOSSES=4`; `MAX_SLTP_COUNT_PER_SESSION=7`;
  `MAX_HIGH_RISK_TRADES_PER_SESSION=5`; ACCEPT_HIGH_RISK E1/E2/E4=true; `E2_HTF_TREND_FILTER=3`
  (=M5_AND_M15), `E2_HTF_MIN_ADX=23`, `E2_HTF_MIN_DI_SPREAD=3`, `E2_MAX_TOUCH_AGE=36`.

## The hard numbers (reproduce: `tick_backtester ... --set anchor_1.8.154.set`, Feb window)
| run | engine trades | exact-bar match to EA's 9 executed |
|---|---|---|
| ATR gates ON (faithful) | 45 (E1 18 / E2 13 / E4 14) | **1 / 9** |
| ATR gates OFF | 133 | 3 / 9 (within 3 min; not exact-bar) |

Of the 45 engine trades, only **6** land on the same ts+type as *any* EA signal (5 of those the EA
SKIPPED); **39 are engine-only**. Many engine E1 fires have **no EA E1 signal within 15 min** at all.

## Why each of the 9 EA-executed trades is missed (engine entry-trace at those bars)
| EA bar | type | engine verdict | bucket |
|---|---|---|---|
| 02.04 07:45 | L-E1 | atr_pctile too low (eng 46.9) | **ATR wall** |
| 02.06 12:07 | L-E4 | atr_pctile too low (eng 62.5) | **ATR wall** |
| 02.09 14:32 | L-E1 | atr_pctile too high (eng 96.9 vs EA ~50) | **ATR wall** |
| 02.16 09:02 | L-E4 | atr_pctile too low (eng 21.9) | **ATR wall** |
| 02.16 13:29 | S-E1 | gate PASS but engine armed/fired 11 min early | timing |
| 02.17 03:28 | S-E4 | trend-quality 8 vs needed 9 | **TQ 1-pt gap** |
| 02.17 13:20 | S-E4 | **PASS → the 1 exact match** ✓ | — |
| 02.18 02:10 | L-E4 | engine takes a phantom **L-E2** here (priority) → suppresses the L-E4 | **E2 over-detect** |
| 02.23 07:38 | S-E4 | trend-quality 8 vs needed 9 | **TQ 1-pt gap** |

Buckets: **4 ATR-percentile wall · 2 trend-quality 1-pt gap · 2 E2-over-detection/timing · 1 match.**

## Root cause #1 — ATR-percentile wall (gates 4/9). PARTIALLY irreducible.
- Engine `atr_pctile` vs EA: **median |Δ| 6.25 pt, only 30% exact** (27,356 joined bars).
- The percentile recipe is correctly ported (ref = forming `cache.atrM1` = shift-0; distribution =
  closed ATR shifts 1..32; strict `<`; ×100/32). Confirmed: no window off-by-one fixes it.
- TWO error sources:
  1. **Forming reference** `s.atrM1` is ~7% off MT5's `cache.atrM1` (median 6.81%, mean 8.54%).
     Swapping in the EA's exact `cache.atrM1` only lifts exact-match 30%→34% → minor.
  2. **Closed-ATR rank order** differs by ~2/32 even with the EA's exact reference (median |Δ| stays
     6.25). Almost certainly **engine builds bars on MID, MT5 iATR uses BID** → ATR rank noise within
     the 32-window. This is the real floor. Only a true fix is rebuilding M1 ATR on **bid** bars.
- ⇒ The handoff's "irreducible ATR wall" conclusion is essentially correct, with the added detail that
  the *bid-vs-mid ATR series* (not just tick fidelity) is the likely lever, and the forming-reference
  error is a small separate contributor.

## Root cause #2 — E2 over-detection (gates ≥1 E4 via priority; biggest phantom source)
- Engine detects **49 E2** (ATR off) vs the EA's **20**. The EMA75-touch trigger is **byte-identical**
  (triggers.hpp:100-108 == EMAHelpers.mqh:285-313) and clustering shows they are mostly **distinct
  touch-windows**, so the looseness is in `CheckE2EntryConditions_Internal` (Entry2.mqh:192-295), NOT
  the touch arming or a re-fire bug.
- Engine HTF filter (HTF_M5_AND_M15) and ADX-confluence are present; the divergent sub-check is still
  unisolated — **next: line-by-line diff `CheckE2EntryConditions_Internal` vs entries.hpp E2 path.**
- Why it matters even though EA executes 0 E2: in `DetectNewEntry` a **detected** E2 sets
  `detectedTrade.type` and SKIPS the E4 block (priority E1→E2→E4). So a phantom engine E2 *suppresses*
  the real E4 the EA takes (e.g. 02.18 02:10). Tightening E2 detection both kills phantom E2 trades and
  un-suppresses real E4 entries.

## Root cause #3 — trend-quality 1-pt gap (gates 2/9)
- At 02.17 03:28 and 02.23 07:38 the engine's `tqS_e4 = 8`, need 9. The missing point is the
  acceleration bonus: the EA reads `HasTrendAcceleration`/`IsAccelerating` at **shift-0 (forming)**;
  the engine reads the closed window ending at i1 (scoring.hpp PORT CONVENTION). Reading forming was
  tried before and **net-hurt** parity → needs the proper forming-HTF-ADX model (aggregate M1 bars in
  the current M3/M5 bucket up to decision time), per HANDOFF NEXT-action #2. Non-trivial.

## Recommended order (revised)
1. **E2 detection fidelity** — highest leverage, no ATR dependency. Diff `CheckE2EntryConditions_Internal`
   1:1; fix the loose sub-check. Removes phantom E2 *and* recovers suppressed E4. Verify: engine E2
   count → ~20, and the 02.18 02:10 L-E4 reappears.
2. **Trend-quality forming-HTF-ADX** — recovers 2 E4 (03:28, 07:38). Build forming M3/M5 ADX from M1
   aggregation; feed {forming,closed,closed-1} to accel helpers.
3. **ATR wall** — only attempt if 1+2 don't get parity close enough: rebuild M1 ATR on **bid** bars and
   re-measure `atr_pctile` median|Δ| (target ≤1 pt). Until then this gates ~4 EA trades irreducibly.
4. THEN limiters (the original handoff list) to trim residual over-fire, then SL/TP/exits.

## Artifacts
- `anchor_1.8.154.set` — engine config from the exact logged inputs (use for every parity run).
- `/tmp/eng_trades_1.8.154.csv` (45, ATR on), `/tmp/eng_trades_noatr.csv` (133, ATR off).
- `build/kenkem/entry_trace` — per-bar gate localizer (built manually: `clang++ -std=c++20 -O2 -Iinclude
  tools/kenkem/entry_trace_dumper.cpp -o build/kenkem/entry_trace`; NOT in the Makefile — add a target).
