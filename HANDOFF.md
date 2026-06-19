# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, 29 C++ checks PASS._

## 🎯 Goal: KenKem **E1 perfect parity** (then E2, E4, E5), engine ⇄ MT5. Ground truth = the canonical EA.

## ✅ THIS SESSION — SL/TP LEVEL GAP **CLOSED** (the entry-side ATR root cause, FIXED)
The handoff's #1 NEXT ACTION is DONE. Root cause was the **forming-bar ATR shrink** feeding the binding
4.0× ATR-SL cap. Fix (1 commit, see below): `compute_sl` now arbitrates against the **last-closed-bar**
Wilder ATR (`snap.atrM1_sl`) instead of the forming `snap.atrM1`.

### The mechanism (empirically proven, not theorized)
- Engine `s.atrM1` = forming Wilder step `(ATR*13 + |open−prevClose|)/14`. On continuous XAU ticks the
  bar-open gap ≈ 0, so this mechanically **shrinks ATR by ~1/14 ≈ 7%** (13/14 = 0.9286).
- Measured at the 78 MT5 E1 entry bars (engine `trace_dumper` `atr` vs `trace.csv` `atr`, joined on
  `engine.ts_ms − 60000 = mt5.ts_ms`, 99.98% close-match): forming ATR ratio **0.933** (92% below MT5);
  **last-closed-bar Wilder ATR ratio 1.003** (balanced, |log| 0.048 — best fit). MT5's `cache.atrM1=iATR(0)`
  is read on the first tick *after* the bar boundary, when the forming bar already carries real range — so
  it tracks the closed value, NOT the engine's degenerate first-tick gap.
- The **4.0× ATR-SL CAP binds** on most E1 trades (risk/atr clusters at ~4.0; the 1.2× floor never binds),
  so the 7% ATR shrink fed a ~7% TIGHT SL directly.
- Note: across ALL 848k bars the forming model fits better (1.014) than closed (1.089) — the relationship
  FLIPS at entry bars (a volatile, biased subset). So the fix is scoped to `compute_sl` ONLY; `atrM1`
  (forming) is unchanged for sideways-spread + atr_pctile (both still validated against the trace).

### Result (full 2yr E1, `anchor_E1_only_trace.set`)
- **Matched risk ratio (eng/mt5): 0.949 → 1.0000** (median); |Δrisk| **0.248 → 0.080**; frac eng<mt5 0.78→0.39.
- **Matched SL-LOSS exits now agree 11/11 exactly**; matched tag-agreement **67%**.
- Net 1456.63 → **1786.48**, PF 1.374, 149 trades.

## 🧱 RESIDUAL (smaller now) — trail doesn't catch on ~5 matched trades; entry-count still off
Levels match but SL-WIN exit-tag is still low. On the 46 matched pairs, of MT5's **14 SL-WIN** trades the
engine reproduces **6 SL-WIN**, but **5 ride to TP** (trail not catching the retrace), 2→EA, 1→SL-LOSS.
Matched net eng **280.6** vs mt5 **885.0** — so the handoff's "levels were the dominant lever for SL-WIN"
is now **partly disproven**: levels are fixed yet the TRAILING SL still overshoots on a handful. This is the
next exit-mechanics target (not levels). Entry-count gap UNCHANGED (matched 46 / missed 32 / overfire 96).

## 🔬 Standing evidence (still valid) — MT5 `tester.log.gz` (RUN 1.8.154, 78 trades)
Mechanism fire counts: **TRAILING SL 290** · PARTIAL 93 · PANIC 24 · R-MULT BE 20 · BE 18 · SIDEWAY 15 ·
EARLY 9 · PRE-BE 6 · TP-EXT 1 · LADDER 0. Ladder + TP-ext are INERT in MT5 (ports correctly near-inert).
volMult=0.70 confirmed; bar-frozen `bestPrice==marketPrice` model confirmed.

## ▶️ NEXT ACTION — chase the residual TRAILING-SL overshoot, then entry-count
1. Take the **5 matched "engine-TP vs MT5-SL-WIN"** trades (ad-hoc python below reproduces the match set).
   For each, trace the engine trail vs the MT5 `tester.log.gz` `TRAILING SL` lines for that ticket: is the
   engine arming the trail LATE (0.90 partial-eligibility timing) or trailing too LOOSE (`0.40*origTPDist`
   distance / volMult)? Now that levels match, origTPDist is correct, so suspect partial/best-price timing
   or the live volMult per-tick (forming-bar range / atr14 clamp 0.7–1.5).
2. THEN re-enable `ENABLE_LOSS_COOLDOWNS=true` (occupancy/limiters) to collapse the 96 overfire / 32 missed
   (entry-count, unchanged). See [[atr-percentile-parity-wall]]: over-fire = unmodeled account limiters.

## 🔁 Repro (full 2yr, ~23s)
```
cd cpp_core && make test                       # 29 checks, green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/e.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
# ATR-at-entry-bar diagnostic (proves the closed-ATR fit): engine bar-level trace via
#   ./build/kenkem/trace_dumper --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --symbol-xau \
#     --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/engine_trace.csv
#   then join engine.ts_ms-60000 == mt5 trace.csv ts_ms, compare `atr` at the 78 entry bars.
# matched exit-tag crosstab + risk-ratio: ad-hoc python in this session's transcript.
```
Current diff: matched 46 / missed 32 / overfire 96; |Δrisk| **0.080**; matched tag-agree **67%**; exit-tag
(all trades) engine SL-WIN 9% TP 32% SL-LOSS 35% EA 24%  vs  MT5 SL-WIN 35% TP 21% SL-LOSS 28% EA 17%
(engine dist confounded by the 96 overfire — use the MATCHED crosstab, where SL-LOSS=11/11).

## 📦 Data / instruments
- Full 2yr XAU: `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv (5.17GB)}`
  (gitignored — too large; regenerate via the import pipeline if missing).
- **MT5 ref run NOW COMMITTED TO GIT** (verified internally consistent: 78 trades, 848,532 bars, one run,
  EA=canonical KenKemExpert, XAU 2024.01.01→2026.06.01) at
  `research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/`:
  - `trades.csv` (78 trades — the diff target) · `kke1gate.csv` (55,748 gate rows) · `tester.log.gz`
    (mechanism fire counts + `TRAILING SL` lines for the residual work).
  - `trace.csv.gz` (67MB; the 278MB per-bar trace, has the `atr` col) — **gunzip before use**:
    `gunzip -k research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trace.csv.gz`.
    These four `.csv` are force-added (the repo `.gitignore` excludes `*.csv`).
- Ground-truth EA = `kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5` (+ `TradeManagement/TradeManager.mqh`,
  `Entries/EntryBase.mqh`). NOTE: dquants `mql5/experts/KenKem/` is the THIN KK-rewrite (Engine.mqh), NOT
  this EA — do not confuse them. Exit port spec: `research/hypotheses/KENKEM-EXIT-PARITY-SPEC.md`
  (its P1/P3 emphasis is now superseded by the log evidence above — TRAILING SL + SL-levels are the levers).

## 🧱 After E1→E5 parity LOCKED (user's explicit next phase)
Convert pip-denominated params to ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before — parity is
ground truth. See [[goal-pip-to-atr-relative]].
