# HANDOFF — read me first, update me last

_Last updated: 2026-06-17 by Claude (Opus 4.8) — **CORRECTED DIAGNOSIS: it's DETECTION, not limiters.**
Branch `parity-trace-1.8.154`. Build GREEN, 28 checks pass. Full writeup:
`research/kenkem_parity/PARITY_1.8.154_DETECTION_DIAGNOSIS.md`._

## ⭐ ORACLE-VALIDATED diagnosis (2026-06-17) — over-fire/selection, NOT ATR, NOT broken detection
Full writeup: `research/kenkem_parity/PARITY_1.8.154_DETECTION_DIAGNOSIS.md`. Reconciled with the
parallel session's oracle. Hard numbers (config = `anchor_1.8.154.set`, Feb window):
- baseline (ATR on): **45 trades, 1/9** exact-bar match to the EA's 9 executed.
- `--pctile-oracle` (MT5's EXACT atr_pctile): **47 trades, 0/9** → **ATR-percentile is NOT the blocker**
  (confirms the parallel session). My first draft's "4/9 ATR wall" was WRONG — an entry_trace
  short-circuit artifact (ATR checked early masks downstream gates). Deprioritize ATR.
- entry_trace with ATR OFF at the 9 EA bars: **detection PASSES at 6/9.** Detection is largely faithful.
  Only 3 fail detection: 02.09 14:32 L-E1 (`e1_mtf`), 02.17 03:28 + 02.23 07:38 S-E4 (`tq`=8 vs 9).
- ⇒ The gap to the EA's 9 = **over-fire + selection**: engine fires 45-47 vs EA 9; phantom trades
  (esp. **E2: 49 detected vs EA 20**) crowd out/suppress the real entries via priority (E1→E2→E4),
  occupancy, min-seconds, max-concurrent + unmodeled account limiters.

### 📋 FULL C++↔MQL FAITHFULNESS AUDIT (2026-06-17) — `research/kenkem_parity/CPP_VS_MQL_FAITHFULNESS_AUDIT.md`
Module-by-module 1:1 audit (8 parallel agents + manual verification). VERDICT: NOT 1:1. Detection is
mostly faithful; the **risk/limiter back-half, exit management, and dynamic lot-sizing are largely
UN-PORTED**, plus 3 confirmed detection bugs. That doc is the authoritative punch list — the NEXT ACTIONS
below are its top items. Biggest over-fire lever = **high-risk routing is not modeled at all** (every EA
E2 routed through HandleHighRiskEntry and was skipped; C++ opens them) + **ATR gate applied at detection
not execute-stage** (changes E1→E2→E4 priority/suppression). Confirmed detection bugs: EMA-stack gate
reads `align-3` not `align-2` (one bar too old vs the verified snapshot); accel/ADX read closed not
forming bars (the tq=8-vs-9 gap). I/O modules (alerts/CSV) are cleanly separable — correctly omitted.

### ▶️ NEXT ACTIONS (resume here)
1. **E2 detection-input fidelity** (highest leverage). EMA75-touch trigger + gate ORDER are faithful →
   diff the gate INPUTS (HTF M5/M15 ADX/DI, emas_ready, trend-quality) vs EA `trades.csv` per-signal
   cols at the ~29 engine-only E2 bars. Drives E2→~20 and un-suppresses real E4 (e.g. 02.18 02:10).
   Tool: `make kenkem_entry` then run with the ATR-OFF set so the TRUE blocker shows (not `atr_lo`).
2. **Finish the account-limiter port** (parallel session did MAX_SESSION_LOSSES/MAX_SLTP — those didn't
   bite in Feb): add consec-loss block, losing-streak cooldown, daily-loss, drawdown EOD-block, and the
   **high-risk routing** (every E2 routes through HandleHighRiskEntry → weak-trend/momentum skip).
3. **Trend-quality forming-HTF-ADX** (recovers the 2 S-E4). Build forming M3/M5 ADX from M1 aggregation.
4. **E1 MTF** at 02.09 14:32 — diff `isAllTimeframeEMAsReadyForEntry` vs engine `emas_ready_entry`.
5. ATR-percentile: DEPRIORITIZED (oracle-disproven).

### Tooling / repro
- `cd cpp_core && make kenkem_tick kenkem_entry` · run: `./build/kenkem/tick_backtester --bars-m1
  tools/bars_xauusd_2026_m1.csv --ticks tools/ticks_xauusd_2026_window.csv --symbol-xau --set
  ../research/kenkem_parity/anchor_1.8.154.set --from-ms 1769889600000 --to-ms 1772337600000 --out <o>`
  (add `--pctile-oracle <ts_ms,atr_pctile.csv>` for the oracle test).
- Ground truth: `research/kenkem_parity/mt5_runs/RUN_2026-06-17_1.8.154_xau_feb/{parity_trace,trades}.csv`
  (9 executed: E1×3,E4×6; 20 E2 all SKIPPED). Run log: `kenkem/Tester/Agent-127.0.0.1-3000/logs/20260617.log`.

---
_(below = prior handoff; bar-parity facts hold; the trade-level plan is superseded above)_

## 🚨 bars are bit-exact (still true)

## ➕ ADDENDUM (2026-06-17, parallel session, now rebased in) — limiter port STARTED + oracle tool
A second agent (working off a stale checkout) independently corroborated this handoff's conclusions
(ATR is NOT the wall; over-fire = unmodeled account limiters) and landed two things on the NEXT list:
- ✅ **`MAX_SESSION_LOSSES=4` + `MAX_SLTP_COUNT_PER_SESSION=7` caps PORTED** into `tick_engine.hpp`
  (commit `144d6af`): per-named-session counters (ASIA/EU/US), reset via UpdateSessionTracking,
  increment on every close via the EA's HandleClosedTrade loss/BE classification. Item (b) partially done.
- ✅ **New diagnostic `tick_backtester --pctile-oracle <csv>`** (commit `80852f5`): feeds MT5's per-bar
  `atr_pctile` (joined offset 0) into the engine — used to PROVE the percentile is not the blocker.
- ⚠️ That agent's numbers (old 9-trade Feb anchor) are STALE — trust THIS handoff's 1.8.154 ground truth.
  Still-TODO limiters: consec-loss block, losing-streak cooldown, daily-loss, drawdown EOD-block, E2-skip.

## 🚨 SUPERSEDES "THE WALL": bars are bit-exact; the ATR mismatch was NOT tick-fidelity
The prior "~2% / 0.31 ATR tick-completeness residual" conclusion was WRONG. Proof + tools committed:
`research/kenkem_parity/DATA_HEALTH_AND_BAR_PARITY.md`, `cpp_core/tools/common/{build_bars,verify_bars_vs_trace}.py`.
- M1 BID OHLC matches the MT5 trace to **0.000000** (82,048 bars) at the join `my_open == trace_ts−60000`.
  The old residual came from joining at the wrong offset (ATR is smooth → fake "right" while close drifts).
- ATR(14) median|Δ| = **3e-6**. The only ATR spikes are the first ~28 bars after a **multi-day hole in
  the exported XAU ticks** (price gaps the missing days → one huge TR Wilder carries). Data, not formula.
- **XAU tick export is missing whole trading days MT5 has**: 2025-04-28..30 (PROVEN via trace), 05-16,
  06-03, 06-30; 2024 near-total Nov-19..Dec-20; plus Good-Friday holidays (legit). BTC is complete.
- **Feb-2026 anchor window is CLEAN** → anchor parity needs NO new ticks. M3/M5/M15 = exact aggregation
  of bit-exact M1 (MT5-faithful). `verify_bars_vs_trace.py` is the regression gate.

### ⏳ AWAITING USER (decisions taken 2026-06-17): re-anchor on EA 1.8.154 + re-export XAU ticks
The old Feb-2026 anchor CSVs were DELETED and the EA advanced 1.8.15→1.8.154. User chose: **re-anchor
on 1.8.154**, **I re-add the trace hook**, **user re-exports complete XAU ticks**. Status of each:

1. ✅ **EA instrumented.** kenkem branch **`parity-trace-1.8.154`** (commits `3e8d12f`,`0e12256`,
   compiles `✓ OK`): additive per-bar parity trace (`input InpExportParityTrace`) emitting the C++
   trace schema from the cache, + `ENABLE_CSV_EXPORT` promoted to an input for the trade ledger.
   **Run recipe: `research/kenkem_parity/RUN_ANCHOR_1.8.154.md`** (XAUUSD M1, every-tick, Feb-2026,
   both toggles on). `fire_dir` is a TODO (always 0); wire a global in DetectNewEntry if needed.
2. ✅ **User ran it (2026-06-17).** Ground truth captured: `research/kenkem_parity/mt5_runs/
   RUN_2026-06-17_1.8.154_xau_feb/{parity_trace,trades}.csv` (27,379 bars, 108 trade rows). Gotcha
   that cost 3 reruns: the Strategy Tester profile `kenkem/MQL5/Profiles/Tester/KenKemExpert.set`
   OVERRIDES source defaults — the export toggles must be `true` THERE (now patched). ⚠️ The 1.8.154
   trade CSV is a **47-col analytics schema** (Timestamp,EntryType,Status,EntryPrice,SL,TP,... incl.
   SKIPPED rows) → `diff_kenkem_trades.py` needs an adapter.

   **DIFF + FIXES DONE** (`PARITY_1.8.154_DIFF.md`, commits `d1f0129`,`e87d15b`). Bars PERFECT (close/
   ema/adx bit-exact). Engine indicator FIXES shipped: **EMA now bit-exact** (GetEMA shift = `i1-1`,
   not `i1-2`; this was a real bug on every EMA gate); **atr_pctile ref = forming s.atrM1**. Residuals:
   atr forming ~0.19 (MT5 cache.atrM1 is intra-bar, unreachable from M1 bars — the true ATR-pctile
   wall); RSI trace col = 0 (EA GetRSIAverage lazy-handle bug → sideways RSI comp ≈0, engine must mirror).

   **Engine TRADES** (Feb-2026 default cfg via `tick_backtester`): **45 trades PF 1.225** (E1 18,E2 13,
   E4 14). EA executed ~15-20 (E1/E4 only; **ALL E2 SKIPPED** by RiskManager). Over-fire localized:
   only **6/45 engine trades match an EA signal**, 39 engine-only. ⏭️ **NEXT = trade-level gate port**:
   (a) E2 RiskManager skip rule (EA skips every E2 → engine must too), (b) faithful limiters
   (MAX_SESSION_LOSSES=4, MAX_SLTP_COUNT=7, MAX_HIGH_RISK_TRADES=5, 1-entry/bar, min-sec, max_concurrent,
   day cap), (c) E1/E4 gate thresholds (engine misses most EA entries). Config in the 14:01 run log
   (CONVICTION_THRESHOLD_E2=10, MIN_TREND_QUALITY_E2=9, E2_HTF_*, etc.). Read Entry1/2/4.mqh + RiskManager.
3. ⏳ **User re-exports XAU ticks** — missing whole trading days; ranges in
   `research/kenkem_parity/XAU_TICK_REFETCH_LIST.md` (Feb-2026 anchor is clean, so not blocking it).

**When CSVs land:** diff C++ engine trace vs `parity_trace_XAUUSD.csv` (same-ts join), port 1.8.15→
1.8.154 logic deltas, then trades. NOTE the snapshot.hpp:172-177 atr_pctile reference (forming vs
closed / first-tick vs mid-bar) is the prime suspect for entry-gate wobble — resolve it against the
fresh `atr_pctile` column. The intact `trace_xau_paritywin.csv` (2025-H1 E5) stays usable for clean-bar
indicator checks.

_(below = prior handoff, still valid for the entry-layer/over-fire work once ground truth is back)_


## 🎯 Goal (CLEAN-SLATE RESET — autopilot, 3 strategies)
User was "super disappointed" by the distilled KK-KenKem and ordered a faithful rewrite, then expanded
to autopilot across THREE strategies. The arc: **C++ reproduces the original EA EXACTLY → use C++ for
fast param sweeps → port the tuned logic BACK to MQL5.** Order: **KenKem → MasterVP → MonsterEdition**
(for Monster, read the Pine code properly — user named it). Acceptance: C++ trades == MT5 trades within
tick-fill tolerance, then regenerate the EA from the same logic so it ties out at baseline.

**Ground truth = the original EA source** (read it, never guess). For KenKem:
`kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5` + its `Core/`,`Entries/`,`TradeManagement/`,`Utils/` mqh.

## ✅ Anchor LOCKED · ✅ Stage 1 DONE (indicators bit-exact)
Anchor: latest `KenKemExpert.mq5` @ defaults · XAUUSD M1 · every-tick real ticks · **Feb 2026** ·
deposit 10000 / 1:500 · config E1+E2+E4 on, E3+E5 off.
MT5 ground truth: `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/KenKem/{trades,trace}_XAUUSD-Exness-KK.csv`
(9 trades: E4×7,E1×1,E2×1; 27379-row bar trace).

**Stage 1 (commit `680e55d`): 5/6 indicator families now bit-exact** vs the MT5 trace (joined
`cpp_ts−60000 == mt5_ts`): ema0-4 Δ0.00008, rsi Δ0.00046, high/low Δ0.00001, close/adx ~0. ATR Δ0.31 is
a documented ~2% tick-completeness residual (NOT formula — bid/mid/ask all give 0.306). Full write-up +
THE REUSABLE METHODOLOGY: **`research/kenkem_parity/INDICATOR_PARITY_SPEC.md`**. Fixes were in
`indicators.hpp` (rsi_wilder_mt5/step), `tf_cache.hpp` (rsi_ag/al), `snapshot.hpp` (per-indicator shifts:
EMA i1-2, ATR/RSI/high-low forming-bar-first-tick). The EMA "shift 1" is really shift 2 — non-series
`CopyBuffer` index inversion. This trap WILL recur in MasterVP/Monster.

## 🔄 Stage 2-4 IN PROGRESS — CURRENT: validation config (ATR gate off) = **4/9 matched, 129 trades** (commit `26955b5`)
Build GREEN, all C++ tests pass. The faithful entry layer is now ported (E1/E2/E4 gates, scoring, RSI-div);
**4 EA specs** in `research/kenkem_parity/` (`SPEC_E4/E1_E2/PIPELINE/EXITS.md`, file:line). Two gaps remain:
the **over-fire** (downstream limiters — the big lever) and a **1-point acceleration gap** (5 trades). See
▶️ NEXT ACTIONS below. History of how we got here (durable traps worth keeping):

- Config audit: C++ defaults already faithful (sessions UTC 0-330/500-930/1200-1500 = JST windows,
  ATR-pctile 65, conviction 7/10/9, tq 6/9/9, RSI-div). Over-fire is gate COMPUTATION + limiters, not config.
- RSI raw-vs-avg conflation fixed (conviction/sideways use RAW shift-1 `rsiM1`; trace uses `rsiM1_avg5`).
- **Faithful E4 gate (SPEC_E4 §4 Steps 0-4) → FIRST exact trade match**: C++ `02.17 13:20 S 4913.004`
  == MT5 to the cent. Added snapshot `tenkanM3/kijunM3/atrM3`.
- 🪤 **Ichimoku buffer-swap trap (CRITICAL, reusable):** MT5 iIchimoku buffers are 0=Tenkan,1=Kijun,
  2=SenkouA,3=SenkouB,4=Chikou, but the EA's var NAMES are swapped: `ichimokuSpanA/B_M3`=buf0/1=REAL
  Tenkan/Kijun; `ichimokuTenkan/Kijun_M3`=buf2/3=REAL Senkou A/B. So E4 cloud THICKNESS uses real
  Tenkan/Kijun (snapshot.tenkanM3/kijunM3) × atrM3; the "TK-align" check is real SenkouA>SenkouB
  (snapshot.senkouA/B_M3). Verify the same swap in MasterVP/Monster.

### ✅ DONE (commits `2d7117a`, `45d0722`)
- **Faithful E1/E2 gates** ported 1:1 from `Entry1.mqh`/`Entry2.mqh` (ADX floor, HTF block-counter for
  E1 / require-aligned for E2, MTF m1&((m3&m5dir)||extremeDI), price-vs-EMA25, HasSufficientMomentum).
  **Gate EMA reads now use the GetEMA(...,1) non-series entry shift `align.tf-3`** (was raw shift-1 →
  off by 2). New helpers in `gates.hpp` (incl. `#include triggers.hpp` for `emas_ready`).
- **ATR-percentile recipe** fixed: distribution = closed ATR shifts **1..32** (was off-by-one), ref =
  **closed-bar ATR** (= MT5 `cache.atrM1`, proven by trace; first-tick forming model was ~7% low).
- **New tool `tools/kenkem/entry_trace_dumper.cpp`** (`build/kenkem/entry_trace`) — per-bar E1/E2/E4
  gate-decision trace (first failing gate + tq component breakdown). The localizer that cracked this.

### 🧱 THE WALL (RESOLVED — tick-fidelity-limited, decision ratified below)
`detect_entry` runs **once per bar at the new-bar's first tick** (KenKemExpert.mq5:2494). The dominant
entry filter is **MIN_ENTRY_ATR_PERCENTILE=65 + ATR_HIGH_BLOCK>90** (RiskManager.mqh:284-308, under
`ENABLE_BLACK_SWAN_PROTECTION=true`). At all 9 MT5 entries the MT5 percentile sits 68-88 (passes); mine
swings wildly and wrongly blocks ~3. **Root cause:** percentile *ranking* is hypersensitive to the
irreducible ±0.2/bar ATR noise between the exported ticks and MT5's internal tick stream. My M1 bars are
ALREADY tick-accurate (tick-built ATR == my bar ATR to 4 dp) → **NOT fixable by rebuilding**. Proof:
disabling the 2 ATR gates lifts matched pairs **1→4** (engine 47→129 trades).

### ✅ DECISION RATIFIED (user, 2026-06-17): disable MIN_ENTRY_ATR_PERCENTILE + ATR_HIGH for the parity
diff ONLY. ⚠️ User says this ATR-regime filter is a PROFITABILITY lever for MasterVP/Monster — never
delete it; keep + sweep once parity holds. Validation set: `/tmp/noatr.set` (MIN_ENTRY_ATR_PERCENTILE=0,
ENABLE_ATR_HIGH_BLOCK=false). See [[atr-percentile-parity-wall]].

### ▶️ NEXT ACTIONS (resume here) — commit `45d0722`, build GREEN, validation config = **4/9 matched, 129 trades**
The 5 still-missed MT5 trades (ATR off) are ALL a **1-point acceleration gap**: 3 E4 trend-quality 8-vs-9,
1 E2 conviction 9-vs-10. Cause = EA reads iADX **shift-0 (forming)** in HasTrendAcceleration; first-tick
model is right for M1 but wrong for M3/M5 (partial bar) and HURT parity → reverted to closed-bar window.
1. **OVER-FIRE is the big lever** (129→9): downstream limiters not faithfully modeled — verify in
   `engine.hpp`/`tick_engine.hpp`: **MAX_SESSION_LOSSES=4**, one-entry-per-bar (`lastEntryBarIndex`),
   min-seconds-off-last-SUCCESSFUL-entry, block-opposite, max_concurrent=2, day cap, MAX_SLTP_COUNT=7.
   Use `build/kenkem/entry_trace` at the 103 engine-only bars to see which limiter SHOULD block.
2. **Acceleration gap** (optional, for the last ~4 trades): model M3/M5 forming bars by aggregating M1
   bars in the current HTF bucket up to decision time (reuse `kk::ind::dmi_adx_mt5_form`), then feed
   {forming,closed,closed-1} to `kk_trend_accel`/`kk_adx_accel`. Non-trivial; do AFTER over-fire.
3. Then SL/TP + managed exits ("EA" tag) → exitPrice/realizedUsd. Re-diff each step. Target 9/9.
4. Then **Stage 5** KK-KenKem regen; then **MasterVP**, then **MonsterEdition** (read Pine).

**Tooling:** `cpp_core/tools/kenkem/entry_trace_dumper.cpp` (`build/kenkem/entry_trace`) — per-bar
E1/E2/E4 first-failing-gate + tq component breakdown (stderr in `--only` mode). The Stage-2 localizer.

⚠️ EXITS caveat: `SPEC_EXITS.md` was mapped for the E5 path; our config is E1/E2/E4 — re-verify the
E1/E2/E4 exit toggles (panic/score-drop/session-end) before porting exits.

## 🔑 Key facts / gotchas
- Rebuild + run: `cd cpp_core && make kenkem_tick kenkem_trace && make test`. Binaries in `build/kenkem/`.
- Trade diff window-aligns automatically. Trace diff MUST join `cpp_ts−60000 == mt5_ts`.
- **Tick engine only** for P&L ([[bar-engine-systemic-defect]]). EMA non-series shift-2 trap. shift-0 =
  forming bar first-tick (O=H=L=C=open), model as one Wilder step — never read the future bar's OHLC.
- Edit the DEPLOY EA at `dquants/mql5/experts/KenKem/` ([[deploy-ea-is-dquants-mql5-symlinked]]).
- Python: `~/miniforge3/envs/kenkem/bin/python`. Per-step: test→commit→push→tick docs.
- Staged data: `cpp_core/tools/{ticks_xauusd_2026feb.csv, bars_xauusd_2025h2_2026_m1.csv}`.

## 📚 Durable refs
`research/kenkem_parity/INDICATOR_PARITY_SPEC.md` (Stage 1 + methodology) · `ANCHOR1_FINDINGS_2026-02.md` ·
`REFERENCE_RUN_RECIPE.md` · `research/validation/parity_diff.py` · `docs/KENKEM_QUANT_OS.md` ·
`~/.claude/.../memory/MEMORY.md` ([[kenkem-clean-rewrite-2026-06]]).
