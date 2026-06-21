# BUILD PLAN — KK-KenKem clean rewrite (faithful transcription of KenKemExpert)

_Created 2026-06-21. Branch `reliableBaseline`. Supersedes the dead distillation EA (killed this session)._

## Goal
A clean, dquants-native MQL5 EA that **faithfully reproduces** the profitable original
**KenKemExpert** (`../kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5`, v1.8.154) for entries
**E1 + E2 + E5** (E4 excluded — confirmed MT5 net-loser). Source of truth = KenKemExpert's own
MQL5 (transcribe, do NOT port the C++ engine — it has E4-exit/E5-recall gaps).

## Non-negotiables
- **Transcribe KenKemExpert input NAMES verbatim** (`ENABLE_E1_ENTRIES`, `E1_RR`, `E1_ATR_SL_CAP_MULTIPLIER`,
  …) for the E1/E2/E5 + shared + exit subset, so the existing MT5-confirmed
  `research/kenkem_parity/KK-KenKem-XAUUSD-M1-D3-noE4.set` loads **directly** → parity = same-`.set` diff.
- Clean module layout mirroring **KK-MasterVP** (Inputs / State / Indicators / Snapshot / Strategy
  (entries) / Exits / Risk / Engine / Parity) + reuse **KK-Common** (Sizing, PositionManager, Indicators)
  where it doesn't compromise fidelity.
- Live entry path is **OOP** in KenKemExpert (Entry1/2/5 classes, first-match E1→E2→E5). Transcribe the
  *live* path only; skip Alerts/Discord/Telegram, adaptive-learning/coordinate-descent, StatePersistence,
  E3/E4, conviction-as-learning. KEEP the full exit engine (it carries the edge).
- `.set` flush-left (MT5 Load rejects indent). Compile via `scripts/compile_mql5.sh` (wine+MetaEditor).

## Validation (each phase)
Trade-for-trade vs MT5 logs in `research/kenkem_parity/mt5_runs/`:
- **E1+E2** → `2026-06-20_D3-noE4/trades_XAUUSD-Exness-KK.csv` (the +1049/PF1.39 lock) via `diff_kk.py`.
- **E5** → `RUN_2026-06-19_..._E5only_cd120/` + `..._E5only_realtrace_v2cols/`.
The new EA exports trades via its own `Parity.mqh` (toggle `InpExportParity`/TradeJournal-compatible 10-col).
**MT5 runs are user-executed** (I can't run MT5 headless) — each phase ends with an exact MT5 run ask.

## Phases
- **P0 — kill + scaffold** ✅ killed old EA. Scaffold new `mql5/experts/KK-KenKem/` skeleton + this plan.
- **P1 — Foundation (compiles green, no trades):** `Inputs.mqh` (real-name subset), `State.mqh`
  (CTrade, handles, cache struct), `Indicators.mqh` (EMA/ADX/RSI/ATR handles on M1/M3/M5/M15 +
  accessors), `Snapshot.mqh`/cache fill (incl. sideways score + ATR percentile, ATR=SMA-of-TR not
  Wilder per [[kenkem-atr-is-sma-not-wilder]]), thin shell + empty `OnTick`. Compile 0/0.
- **P2 — E1+E2 entries:** transcribe `UpdateEmaTouches` arming, `isEMAsReadyForEntry`,
  `Entry1/Entry2 Detect` + gate chains (ADX/HTF/MTF-EMA/trend-quality/RSI-veto), `CalculateStopLoss…`
  (EMA-distance + ATR cap/floor + spread buffer), final TP via `ProcessEntryConvictionAndConfidence`
  (RR boost + sideway RR). Risk gates (`GetEntryBlockReason`, lot sizing, max-loss route, consec-loss).
- **P3 — Exit engine:** transcribe `TradeManager::ProcessAllTrades` per-tick sequence (pre-BE → R-mult
  BE → TP-ext → partial(+E5 immediate) → ladder → trailing → early-exits a–h → panic → session/news
  close). Per-entry mgmt getters (trail factor, partial trigger, BE buffer).
- **P4 — E1+E2 parity:** user MT5 run with `D3-noE4.set` → diff vs the lock log → close gaps to
  match +1049/PF1.39 / 102 tr. **This is the profit-confirmed milestone.**
- **P5 — E5:** transcribe `Entry5` onset latch (incl. `m_prevBull/BearAligned` + consumed-lock +
  deferred-by-sideway), E5 SL (EMA200 ±2·spread, ATR cap), E5 immediate-partial + sideway exit.
  Parity vs E5 logs (expect ~53% recall ceiling per [[kenkem-e5-2026-selection-break]] unless latch
  internals fully reproduced).
- **P6 — release:** version + `release.conf` + `make release STRATEGY=KK-KenKem` (auto-bump), update
  best-experts table [[best-experts-release-table]].

## Execution-ready facts (resolved 2026-06-21 — removes the unknowns before P1)
- **OPEN QUESTION RESOLVED — live entry path = the OOP classes.** `OnTick` (KenKemExpert.mq5:2432)
  → `DetectNewEntry()` (:2152) instantiates `entry1..entry5` (:397) and calls `entryN.Detect()` in
  **first-match-wins priority E1→E2→E3→E4→E5**, each gated by `detectedTrade.type==""` (:2192/2225/
  2285/2318). E3 is skipped in our scope. So transcribe the **Entry1/2/4/5 classes' `Detect()`**, not
  the procedural code. Each fills a `DetectionResult` (struct at EntryBase.mqh:20), then
  `ProcessEntryConvictionAndConfidence` sets the final TP. **Skip** the EntryBase adaptive-learning
  fields (baseline*/adjustmentCycle/coordinate-descent) — dead weight, build-plan-excluded.
- **Source files (kenkem/MQL5/Experts/KenKem/):** `Config/InputParams.mqh` (449 inputs, self-contained
  enums `HTF_TREND_MODE` @36, `HIGH_RISK_MOMENTUM_LEVEL` @19), `Entries/{EntryBase(1554),Entry1(371),
  Entry2(295),Entry4(476),Entry5(675),EntryHelpers(374),EntryConditions(175)}.mqh`,
  `TradeManagement/{TradeManager,RiskManager}.mqh`, `Core/Indicators/{EMAHelpers,ADXRSIHelpers}.mqh`,
  `Core/{GlobalState,MarketCondition,TrendIdentifier}.mqh`, `Utils/SessionManager.mqh`. **~8k LOC** of
  faithful transcription — a focused multi-pass job, MT5-parity-gated. Do NOT rush it (rushing = the
  old "trash" outcome).
- **Inputs.mqh = verbatim ALL_CAPS names** (NOT `Inp*`) so the D-series `.set` Load directly. Defaults
  = KenKemExpert's own defaults (e.g. `E1_MIN_MOMENTUM_ADX=19.5`, `E1_ATR_SL_CAP_MULTIPLIER=4.0`,
  `E2_MAX_TOUCH_AGE=36`, `USE_DYNAMIC_RR_SCALING=true`); the lock is applied via `.set`, not by changing
  defaults. Lowest-risk faithful path for P1: **copy `Config/InputParams.mqh` verbatim** (self-contained,
  compiles standalone) and trim only after P2/P3 prove which inputs the live path reads.
- **Lock = `.set` presets (already exist, flush-left, in `research/kenkem_parity/`):** D3-noE4
  (MT5-confirmed +1049/PF1.39), D4 (engine-best E1+E2), D4-E5, D4-E4. P4/P5 parity diff against
  `mt5_runs/2026-06-20_D3-noE4/` (E1+E2) and the E5 runs.
- **Engine cross-check facts to honor (from the validated C++ port):** ATR = SMA-of-TR not Wilder
  ([[kenkem-atr-is-sma-not-wilder]]); MTF EMA read at `align_tf-2` (last-closed via non-series CopyBuffer
  reversal, [[kenkem-mtf-ema-off-by-one]]); sideways = 5-bar avg of ADX/RSI shifts 0..4
  ([[kenkem-e1-sideways-avg-and-recall-maxed]]); E4 SL cap falls through to E2 bounds (`E4_ATR_SL_*`
  keys are DEAD, [[kenkem-e4-sl-cap-is-e2-not-e4]]); E5 onset reads B-2 faithfully (B-1 regresses).

## Status
- **P0: ✅** (old killed; plan written; committed `9de0342`).
- **APPROACH PIVOT → FAITHFUL FULL CLONE (supersedes the surgical-module plan above).** Reason: Alerts
  are woven into the trading files (EntryBase/RiskManager/TradeManager/EMAHelpers all call alert funcs),
  so excising them surgically risks parity. Safer methodology: **clone faithfully (parity by
  construction) → confirm parity in MT5 (P4) → THEN prune cosmetics with a known-good safety net.** A
  parity failure after pruning is then unambiguously the prune, not a port bug. The phase plan above
  (P1 foundation → P2 entries → P3 exits) is collapsed by the clone; it remains the map for the P5 prune.
- **P1–P3: ✅ DONE — faithful clone compiles 0/0.** `mql5/experts/KK-KenKem/` = clone of
  `KenKemExpert.mq5` v1.8.154: all 31 `.mqh` + Data CSV + the `.mq5` (header → `version "1.0"`).
  Compiles **0 errors / 0 warnings**. All 412 keys of D3-noE4/D4/D4-E5/D4-E2RR14 `.set` resolve;
  parity export built in. Excluded subsystems present-but-inert (gated off; E4 off via `.set`).
  Deployed: MT5-visible via `Experts\dquants` symlink; presets synced. EA uses `iATR` → ATR faithful
  by construction (SMA-not-Wilder was a C++-engine-only concern).
- **P4: ⏳ BLOCKED ON USER — the review point.** MT5 parity run (D3-noE4, XAU M1, 2025.03.02–2026.05.29,
  every-tick, `InpExportTradeJournal=true`) → `diff_kk.py` vs `mt5_runs/2026-06-20_D3-noE4/`. Expect
  near-exact (clone of the producing EA). Confirms dquants EA == legacy.
- **P5 (post-parity): prune cosmetics + re-verify + release.** Remove Alerts/CSV/adaptive/persistence/
  E3/E4, re-running the same parity diff after each removal to prove zero behavior change; then
  `make release STRATEGY=KK-KenKem` + update [[best-experts-release-table]].
