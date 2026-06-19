# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, C++ tests PASS (28).
Commit `e3b3e70` (E2 fix) + data rebuild. **2025 H2 data NOW INTEGRATED; 2 smaller holes remain. E2 baseline
re-measured on complete data = STILL ~42% (handoff's 95.8% is confirmed WRONG). See ⛔/🔴 below.**_

## 🎯 Goal: KenKem entry parity engine⇄MT5. NOW ON: E2, then E4, E5.
Ground truth = the canonical EA (`kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5`).

## ⛔ BLOCKER 1 (DATA) —2025 H2 FIXED; two smaller export holes remain
- User supplied 2025 H2 as Exness monthly CSVs `~/Downloads/Exness_XAUUSD_2025_{07..12}.csv`. **Verified
  bit-identical to the MT5-tab raws on the 2025-07-01..16 overlap** (same UTC clock, same feed) → merged.
- **Rebuilt** via NEW `cpp_core/tools/common/build_xau_full_2yr.py` (2024 + 2025 H1 + 2026 from tab raws,
  2025 H2 from monthlies, partitioned at 2025-07-17). Now **740,572 bars / 142.98M ticks**, range
  2024-01-01 → 2026-04-06. **2025 H2 gap GONE.**
- **Completeness vs the MT5 `trace.csv.gz` (848,532 bars = ground-truth bar set): still missing 109,390
  (12.9%)**, in TWO holes the source exports still lack:
  - **Dec 2024** (`2024-11-19 → 2024-12-31`, ~40k bars) — `data/xauusd/XAUUSD_ticks_mt5_2024.csv` ends
    2024-12-22 with only Sunday-open bars in late Nov/Dec (weekday data missing).
  - **2026-04-07 → 2026-05-29** (~56k bars) — `XAUUSD_ticks_mt5_2025_2026.csv` ends 2026-04-06; the MT5
    run goes to 2026-05-29.
  - (+ small day-holes: 2024-08/09, 2025-04/05/06.)
- **Trade impact now: 293/325 MT5 trades (90%) scoreable** (was 71%). Only 32 in the 2 holes
  (16 Dec-2024, 16 in 2026-04/05). Largest contiguous clean window = **2025-01-01 → 2026-04-06** (gap-free).
- ✅ **Research parquet refreshed:** `data/processed/ticks_xauusd_2025.parquet` regenerated to the FULL year
  (74.59M rows, naive UTC TIMESTAMP, schema matched) — unblocks the XAU sweep window 2025-08→12.
- **USER ACTION (optional, for 100%):** export XAU ticks for **2024-11-19 → 2024-12-31** and
  **2026-04-07 → 2026-05-29**, drop in `~/Downloads/` (Exness CSV or MT5 tab), re-run `build_xau_full_2yr.py`
  (add the files to its source list).

## 🔬 E2 GATE DIAGNOSIS (this session, complete data + trace_dumper vs MT5 trace.csv.gz)
Aligned engine trace to MT5 at **engine ts − 60000 = MT5 ts** (close 100% exact, adx_m1 99.7%).
**ALL observable M1 E2 gate inputs are FAITHFUL (≥98% bit-exact):** close (100%), adx_m1/m3/m5/m15
(97.8–99.7%), diP/diM all-TF (98.2–99.8%), rsi (99.1%), and EMAs 10/25/71/97/192 (98.3–99.7% — note the
trace_dumper dumps EMAs one bar offset from close/adx, so EMAs align at shift 0, everything else at −60000;
a DUMP quirk, not a trading bug). ⇒ the E2 mis-selection is NOT in the M1 inputs.
**The ONE confirmed real divergence = `sideways`:** engine blocks **20.4%** of bars vs MT5 **15.2%**
(disagree on the >53 threshold 12.6% of bars), i.e. engine sideways is biased HIGH → **over-blocks → causes
the missed E1/E2 entries** (E1 134 missed, E2 83 missed). This is a shared global pre-gate, so fixing it
lifts BOTH. Matches the prior "+2.48 HIGH bias" note. Other (un-observable) suspects: M3/M5 EMA *alignment*
(MTF gate; M3/M5 EMAs not dumped) + trend-quality 0-11 composition.

### ▶️ NEXT ACTION = fix the sideways over-block (highest-leverage, affects E1+E2)
Audit the engine `GetSidewaysScore` port (`snapshot.hpp` sideways_score) vs EA `TrendIdentifier.mqh:390`.
Prior suspects: EMA-band ATR denominator / which EMAs / averaging shift. Engine over-blocks by ~5pp →
its score is too high. Hard part remains the MT5 sub-component dump (27% reconstruction ceiling), but the
DIRECTION (over-block) is now confirmed, so a port-bug hunt can proceed. **USER (to break the ceiling):**
one MT5 re-run dumping the **5 sideways sub-components** + M3/M5 EMA1..4 at ENTRY_SHIFT.

## 🔴 HONEST BASELINE — re-measured on COMPLETE data; "E2 95.8%" still does NOT reproduce
Engine COUNTS now match the handoff (engine E1 **124**, E2 **145** — handoff said 124/162), confirming the
data is right. But the MATCHING is ~42%, NOT 95.8%:
- Full period (32 gap trades unscoreable): **E2 matched 59 / missed 83 / overfire 84** (of 142);
  **E1 matched 49 / missed 134 / overfire 73** (of 183).
- Clean window 2025-01-01→2026-04-06 (gap-free): **E2 29/40/45** (of 69, ~42%); **E1 23/59/34** (of 57).
- **NOT a timing artifact:** raising the match lag 5→240 min lifts E2 matched only 59→65. The engine genuinely
  fires E2 on DIFFERENT bars than MT5 (matched ones are exact-minute). The prior 95.8%/136-matched is WRONG.
- E2 arms **55,231×** → fires 145 ⇒ the bottleneck is the GATE selection, not the trigger.

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
