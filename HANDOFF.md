# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, C++ tests PASS (28).
Commit `e3b3e70` (E2 fix) + data rebuilds. **DATA NOW 98.45% COMPLETE (all 3 export holes filled by user).
E2 baseline on near-complete data = ~45% (handoff's 95.8% confirmed WRONG, not a data issue). Pinpointed
culprit = sideways over-block. See ✅/🔬 below.**_

## 🎯 Goal: KenKem entry parity engine⇄MT5. NOW ON: E2, then E4, E5.
Ground truth = the canonical EA (`kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5`).

## ✅ BLOCKER 1 (DATA) — essentially RESOLVED (98.45% of MT5 bars present)
- User supplied all 3 export holes as Exness monthly CSVs `~/Downloads/Exness_XAUUSD_{2024_11,2024_12,
  2025_07..12,2026_04,2026_05}.csv`. **Verified bit-identical to the MT5-tab raws on overlap days** (July +
  Nov-08; same UTC clock, same feed) → merged.
- **Rebuilt** via `cpp_core/tools/common/build_xau_full_2yr.py` (monthly owns the 3 hole windows
  `[2024-11-19,2025-01-01) ∪ [2025-07-17,2026-01-01) ∪ [2026-04-01,2026-06-01)`; tab raws own the rest).
  Now **836,890 bars / 160.55M ticks**, range 2024-01-01 → 2026-05-31.
- **Completeness vs MT5 `trace.csv.gz` (848,532 bars): missing only 13,192 (1.55%)** — scattered single
  trading days in tab-raw months WITHOUT a monthly replacement (2024-05/08/09, 2025-03/04/05/06; some are
  Good-Friday/holiday). 99%+ of MT5 trades now scoreable.
- ✅ **All research parquets refreshed** (naive UTC TIMESTAMP, schema matched):
  `data/processed/ticks_xauusd_{2024,2025,2026}.parquet` → 39.2M / 74.6M / 46.7M rows. XAU sweep unblocked.
- **USER ACTION (optional, for 100%):** export the scattered missing days (months 2024-05/08/09,
  2025-03/04/05/06) if exact full-period counts are ever needed; impact now negligible.

## 🔬 E2 GATE DIAGNOSIS (this session, complete data + trace_dumper vs MT5 trace.csv.gz)
Aligned engine trace to MT5 at **engine ts − 60000 = MT5 ts** (close 100% exact, adx_m1 99.7%).
**ALL observable M1 E2 gate inputs are FAITHFUL (≥98% bit-exact):** close (100%), adx_m1/m3/m5/m15
(97.8–99.7%), diP/diM all-TF (98.2–99.8%), rsi (99.1%), and EMAs 10/25/71/97/192 (98.3–99.7% — note the
trace_dumper dumps EMAs one bar offset from close/adx, so EMAs align at shift 0, everything else at −60000;
a DUMP quirk, not a trading bug). ⇒ the E2 mis-selection is NOT in the M1 inputs.
**The ONE confirmed real divergence = `sideways`** (on near-complete data, 834,624 bars):
engine sideways **biased HIGH: mean/median diff +4.0** vs MT5 (engine mean 37.9 vs MT5 33.9); **engine
over-blocks 8.93% of bars (eng>53 & mt5≤53) vs under-blocks 3.69%** → causes the missed E1/E2 entries.
It's STRUCTURAL, not a constant offset (31.6% of bars >10 high, 7.1% >10 low, only 24% within ±3), so ≥1
of the 5 sub-components systematically over-scores. Shared global pre-gate → fixing it lifts BOTH E1+E2.
Other (un-observable) suspects: M3/M5 EMA *alignment* (MTF gate; M3/M5 EMAs not dumped) + trend-quality 0-11.

### ▶️ NEXT ACTION = fix the sideways over-block (highest-leverage, affects E1+E2)
Audit the engine `GetSidewaysScore` port (`snapshot.hpp` sideways_score) vs EA `TrendIdentifier.mqh:390`.
Prior suspects: EMA-band ATR denominator / which EMAs / averaging shift. Engine over-blocks by ~5pp →
its score is too high. Hard part remains the MT5 sub-component dump (27% reconstruction ceiling), but the
DIRECTION (over-block) is now confirmed, so a port-bug hunt can proceed. **USER (to break the ceiling):**
one MT5 re-run dumping the **5 sideways sub-components** + M3/M5 EMA1..4 at ENTRY_SHIFT.

## 🔴 HONEST BASELINE — re-measured on COMPLETE data; "E2 95.8%" still does NOT reproduce
Engine COUNTS now match the handoff (engine E1 **124**, E2 **145** — handoff said 124/162), confirming the
data is right. But the MATCHING is ~42%, NOT 95.8%:
- Full period, near-complete data (836,890 bars): **E2 matched 64 / missed 78 / overfire 93** (of 142, ~45%);
  **E1 matched 54 / missed 129 / overfire 87** (of 183, ~30%). Engine fires E1 143, E2 160.
- **NOT a timing artifact:** raising the match lag 5→240 min barely moves matched. The engine genuinely
  fires E2 on DIFFERENT bars than MT5 (matched ones are exact-minute). The prior 95.8%/136-matched is WRONG.
- E2 arms **62,422×** → fires 160 ⇒ the bottleneck is the GATE selection, not the trigger.

## ✅ THIS SESSION — verified-correct E2 fix (commit `e3b3e70`), + two INERT negative results
- **E2 EMA75-touch shift FIXED** (`triggers.hpp:142-150`): EA reads ema75 via `GetEMA` (trapped,
  inverted buffer ⇒ B-2) but bar lo/hi/cl via `iLow/iHigh/iClose(1)` (untrapped ⇒ B-1)
  (EMAHelpers.mqh:285-288). Engine read EMA75 at B-1 — the same trap fixed for E1's EMA200 touch but
  missed for E2. Now reads `e2t` (B-2 faithful). Test updated to faithful semantics; 28 checks green.
  ⚠️ **Numerically INERT** on XAU 2yr (EMA75 barely moves bar-to-bar; touch outcome rarely flips). Kept
  for correctness/faithfulness. **E2 arms 42,849× → fires only 113 ⇒ the trigger is NOT the bottleneck.**
- **Conviction-consume divergence — measured INERT.** Audit flagged that the EA consumes the E2 touch
  when non-conviction gates pass then drops on conviction<10 post-detect (Entry2.mqh:136 + post-detect
  `ProcessEntryConvictionAndConfidence`), whereas the engine folds conviction into the gate (no-consume,
  re-arms). REAL divergence, BUT: E2 fires **113 with conviction ON == 113 with `USE_CONVICTION_SCORING_E2=false`**
  → conviction blocks ZERO E2 on this data. Not the cause of the residual. (Also a cross-kind change that
  would risk the E1 baseline — do not attempt blind.)
- **Port audit (data-independent) done** vs `Entry2.mqh`: HTF-M15 filter, MTF-EMA, price-vs-EMA25, RSI-div,
  all e2_* config defaults, trigger age/expiry — **all MATCH**. The one remaining code-level suspect is the
  **trend-quality acceleration approximation** (`scoring.hpp:209-218,234-238` awards 2-or-0, never the EA's
  1-pt accel3-only case; `TrendIdentifier.mqh:48-86` n=5 majority) — can flip the 0-11 score around E2's
  strict cutoff of 9. Unvalidatable without the E2 gate trace (Blocker 2).

## ▶️ NEXT ACTIONS (in order)
1. **[USER]** Provide Blocker-1 data (2025 H2 re-export) → rebuild → re-measure full-period E1/E2.
2. **[USER]** Provide Blocker-2 E2 gate trace → localize the 61-missed/57-overfire E2 to a specific gate.
3. Once #2 lands: fix the divergent gate (leading suspect = trend-quality accel fidelity, `scoring.hpp`);
   validate front-window E2 recall climbs. Only then revisit conviction-consume if still needed.
4. E4 parity is blocked too — there is **no E4-only MT5 reference run committed** (only E1only + E1E2);
   need a user MT5 E4 run before E4 can be measured at all.

## 🔁 Repro (full complete data, ~34s backtest)
```
# (re)build complete data if tools/*.csv missing or stale:
python cpp_core/tools/common/build_xau_full_2yr.py     # 740,572 bars / 142.98M ticks
cd cpp_core && make test                                   # 28 checks, green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1E2.set --out /tmp/e1e2.csv
M=research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/trades.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e1e2.csv --mt5 $M --kind E2   # full period
python research/kenkem_parity/diff_kk.py --engine /tmp/e1e2.csv --mt5 $M --kind E2 --from 2025.01.01 --to 2026.04.06  # gap-free
```

## 📦 Data / instruments
- MT5 ref run (committed) `research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/`:
  `trades.csv` (325, diff target) · `cpp_trades.csv` (a NON-faithful engine dump — do not trust as baseline)
  · `trace.csv.gz` (848,532 bars, full 2yr — MT5 had the data) · `inputs_echo.txt` · `tester.log.gz`.
  Also E1-only run `RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/`.
- E1E2 set `research/kenkem_parity/anchor_E1E2.set` (E1+E2 on; MADE_FOR_PROP_TRADING=false; DD-slowdown 10.5%,
  recovery-trigger 9.45%, daily-loss 7.2%, std-lot 0.15, risk 1%).
- Ground-truth EA = `kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5` (+ `Entries/Entry2.mqh`,
  `Core/Indicators/EMAHelpers.mqh`, `TradeManagement/RiskManager.mqh`).

## 🧱 After E1→E5 parity LOCKED (user's explicit next phase)
Convert pip-denominated params to ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before. [[goal-pip-to-atr-relative]].
