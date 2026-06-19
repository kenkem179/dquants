# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, C++ tests PASS (28).
Commit `e3b3e70`. **TWO blockers found this session — both need the user. See ⛔ below.**_

## 🎯 Goal: KenKem entry parity engine⇄MT5. NOW ON: E2, then E4, E5.
Ground truth = the canonical EA (`kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5`).

## ⛔ BLOCKER 1 (DATA) — the working XAU data is INCOMPLETE; user must re-export 2025 H2
- `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` on disk = **577,738 bars**
  (regenerated 2026-06-19 10:14), NOT the complete set. There is a **169-day hole: 2025-07-17 → 2025-12-31**
  (all of 2025 H2).
- **The hole is in the raw export itself**, not the import. VERIFIED across EVERY on-disk source:
  `data/xauusd/XAUUSD_ticks_mt5_2025_2026.csv`, `~/Downloads/Exness_XAUUSD_2025.csv`,
  `data/processed/ticks_xauusd_2025.parquet` — ALL jump from `2025.07.16 23:59` straight to `2026.01.01`.
  So the complete 849,963-bar set the *previous* handoff claimed was on disk **does not exist anywhere
  locally and cannot be regenerated**. (The prior "data resolved" note was wrong.)
- The MT5 *terminal* HAD 2025 H2 (the reference backtest traded through it) — only the **exports** lack it.
- **Impact on the E1E2 reference (325 MT5 trades):** 59 (18%) fall in the gap (unscoreable), 16 more are
  beyond the engine data's end (2026-04-06, MT5 run goes to 2026-05-29). Only the **contiguous front
  2024.01 → 2025.07.16 (231 trades, 71%)** is cleanly scoreable. The engine is causal, so front-window
  parity is 100% valid regardless of the gap — do all interim work there (`diff_kk.py --from --to`).
- **USER ACTION:** re-export XAU ticks for **2025-07-17 → 2025-12-31** from the MT5 terminal (MT5
  tab-sep `<DATE> <TIME> <BID> <ASK>…` OR Exness CSV — both parse). Then rebuild via
  `cpp_core/tools/common/build_xau_anchor_2yr.py` (point its `FILES`/`RAW_DIR` at the restored sources).

## ⛔ BLOCKER 2 (INSTRUMENTATION) — E2/E1 gate residual needs an EA per-bar E2 gate trace
The remaining E2 (and E1) divergence is in the HTF-M15 / MTF-EMA / trend-quality gates — a boundary-VALUE
class (which HTF EMA/ADX/DI boundary flips), invisible from the current trace (its `L_*/S_*` columns are a
single generic gate, no E2 breakdown). Same blocker the prior E1 residual hit. **USER ACTION:** one MT5
re-run of canonical KenKemExpert emitting, per evaluated bar, the E2 gate sub-verdicts
(`htf_trend / mtf / price_pos / trend_quality / rsi_div`) + M3 & M5 EMA1..4 values at ENTRY_SHIFT.

## 🔴 HONEST BASELINE (the prior handoff's "E2 95.8% / 136 matched" does NOT reproduce)
Measured 3 ways, none near 95.8%:
- Fresh `KK_E1_FAITHFUL=1` E1E2 run, **clean front window** (2024.01–2025.07.16):
  **E2 matched 42 / missed 61 / overfire 57** (of 103 MT5 E2, ~41% recall);
  **E1 matched 35 / missed 93 / overfire 48** (of 128 MT5 E1, ~27% recall).
- Full-period combined (gap-polluted): E2 47/142, E1 38/183.
- Committed `cpp_trades.csv` (a NON-faithful run, 615 E1 trades): E2 69/142, E1 86/183.
Treat the prior 95.8% as overstated/unreproducible. The 61 missed are real DETECTION divergences
(the 42 matched are all exact-minute; misses/overfires are at different times) — NOT a matching artifact.

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

## 🔁 Repro (front-window, valid despite the gap)
```
cd cpp_core && make test                                   # 28 checks, green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1E2.set --out /tmp/e1e2.csv
M=research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/trades.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e1e2.csv --mt5 $M --kind E2 --from 2024.01.01 --to 2025.07.16
python research/kenkem_parity/diff_kk.py --engine /tmp/e1e2.csv --mt5 $M --kind E1 --from 2024.01.01 --to 2025.07.16
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
