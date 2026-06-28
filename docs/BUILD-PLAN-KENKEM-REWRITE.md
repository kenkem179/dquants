# BUILD PLAN — KK-KenKem clean rewrite (faithful transcription of KenKemExpert)

> Codex continuity note, 2026-06-28: this file is historical/background for the KenKem rewrite. For the active
> queue, read `HANDOFF.md`, `docs/CODEX-MEMORY.md`, and `docs/BUILD-PLAN.md` first. Current operational decision:
> KenKem XAU M1 D5-E4Long is the validated KenKem edge; K1/M3 was tested and rejected; E5 stays off unless
> explicitly reopened. Treat any older "blocked P4" or duplicate K1 text below as superseded unless git/code
> proves otherwise.

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

## Research levers (post-parity — only after P4 confirms M1 parity)

- [x] **K1 — Extend E1/E2/E5 to M3 → TESTED 2026-06-27 → REJECT (XAU).** 3×-clock proxy (M3 base / HTF
  M9/M15/M45). Sample size fine (217 tr ≫ MinTRL); but RR-rescale is the only lever that moves train PF and
  it OVERFITS (OOS PF 0.81–0.88 net-neg at every RR; 2026Q1 −534), worse than M1 on the full window too
  (PF 1.22 vs 1.33, maxDD 1391 vs 512); strict-alignment + gate-recalibration did NOT help. Accept KenKem
  M1-only. Details `research/kenkem_parity/m3_sweep/M3_SWEEP_FINDINGS_2026-06-27.md`,
  [[kenkem-m3-sweep-rejected]]. (Original hypothesis spec retained below for the record.)
- [ ] **K1 (original spec) — Extend E1/E2/E5 to M3 (XAU **and** BTC) via STRICT EMA-alignment + recalibrated trend-quality gate (user idea, 2026-06-27).**
  Hypothesis (user): the KenKem entries (today M1-only, lock = `D3-noE4`) may work *better* on **M3** if we
  (a) require **strict EMA alignment** (all of 10/25/71/97/192 cleanly stacked, no marginal/overlapping
  arming), and (b) **re-tune the entry-quality gate (trend-quality / sideways score) for the M3 bar** so the
  trade count is **not too rare** and the **target RR stays realistic** (M3 ATR is ~√3× the M1 ATR → a
  fixed `E1_RR`/dynamic-RR-scaling that's sane on M1 may demand unreachable absolute targets on M3).
  - **WHY THIS IS PLAUSIBLE, NOT A FISHING TRIP.** The lock edge-autopsy (`LOCK_EDGE_AUTOPSY_2026-06-27.md`)
    found the M1 lock's two leaks (2025Q3 net-loser, the −623 EA-exit drag) share **one root: E2/chop entries
    that never develop**. M3 bars are coarser → fewer micro-chop arming events, and **strict EMA alignment +
    a recalibrated quality gate is exactly a chop filter**. So K1 attacks the *measured* weakness directly,
    rather than adding an unrelated knob. [[kenkem-e1-efficiency-ratio-weak]] (ER chop-filter was weak on M1)
    is a caution, not a veto — the lever here is alignment-strictness + gate recalibration, not Kaufman-ER.
  - 🔒 **PIP-HARDCODE PURGE IS A HARD PREREQUISITE FOR THE BTC ARM (user requirement, 2026-06-27).** The
    user's explicit guarantee ask: **no pip-denominated hardcoded values**, because `pip_size` differs per
    symbol (XAU 0.01/0.001 vs BTC 1.0) and a chart switch silently rescales every pip param → the algo dies.
    This is NOT clean today — `docs/PIP_TO_ATR_INVENTORY.md` catalogs **~12 decision params** (incl. the
    high-impact `EMA_ALIGNMENT_TOLERANCE_PIPS=23`, `RSI_DIV_MIN_PRICE_DIFF_PIPS`, `SL_EMA_DISTANCE`,
    `E5_MIN_SL_PIPS`, TP-extension bounds) **plus bare `N*pip_size` literals** (`entries.hpp:225` `5.0*pip_size`)
    that are pip-scaled. The recurring `pip_size` 0.01-vs-0.001 gold bug ([[kenkem-parity-traps]], 10× wrong EMA
    tolerance) is this exact failure class. **Strict EMA alignment makes it WORSE**, not better: the strictness
    knob *is* `ema_align_tol_pips`, the single most pip-sensitive param — sweeping it on XAU then loading on BTC
    without ATR-normalization produces a meaningless threshold. **So K1-BTC is gated on completing the pip→ATR
    conversion** ([[goal-pip-to-atr-relative]]) for at least every DECISION param the M3 entries read — convert
    `param_pips × pip_size` → `param_atr × ATR`, EA-input ↔ engine-field 1:1 so parity holds by construction.
    Honest sequencing tension (from the inventory doc): **conversion must come AFTER M1 per-entry parity is
    locked** (converting first destroys the parity reference). Net order: **P4 M1 parity ✅ → pip→ATR purge →
    THEN K1-BTC**. **K1-XAU can proceed on the existing pip params** (single symbol, pip_size fixed) and serve
    as the parity anchor while the purge happens. Category-C value-scaling (`pointValue`, lot math) stays
    pip/point-based by design — do NOT convert those.
  - 🔒 **PARITY FIRST (Gate 0, non-negotiable).** M1 parity does NOT transfer to M3 — new bars re-open every
    timeframe-sensitive trap: MTF-EMA read offset ([[kenkem-mtf-ema-off-by-one]]), the E5 onset bar-pairing
    ([[kenkem-e5-onset-trap-fix]], still at the 52.8% recall ceiling), sideways = 5-bar-avg
    ([[kenkem-e1-sideways-avg-and-recall-maxed]]), iATR=SMA-of-TR. Before ANY M3 sweep number is trusted, the
    engine must reproduce an **MT5 M3 reference run** (E1+E2 first; E5 separately) to tolerance via `diff_kk.py`
    — same doctrine as `/quant-0-parity-baseline` and [[parity-is-gate-0]]. Engine ranks ENTRIES; MT5 judges EXITS.
  - 🔒 **SAMPLE-SIZE / MinTRL IS THE BINDING CONSTRAINT — the central risk.** The M1 lock is already
    n=141 / MinTRL≈122 — barely deflatable ([[overfitting-gate-mandatory]]). **M3 ≈ ⅓ the bars → fewer
    candidate entries, and strict EMA alignment cuts further** → realistic risk of n < MinTRL, at which point
    **no M3 config can pass the gate regardless of PF.** The user's "not too rare" tuning of the quality gate
    is precisely the counterweight, but it is in **direct tension** with "strict alignment" — loosen the gate
    to recover n, you re-admit the chop you came to remove. The whole lever lives or dies on resolving that
    tension: target a quality threshold that **keeps n ≥ MinTRL on a multi-year window while net/PF stays
    above the M1 lock**, and report n + MinTRL on EVERY candidate, not just PF. If the alignment-strict
    surface can't clear MinTRL, **K1 is REJECTED — accept M1-only** (don't loosen-to-pass).
  - **BUILD (no MT5 mid-run; engine is the sweep harness):**
    1. Generate **M3 bars for BOTH symbols** (engine currently has only `tools/bars_xauusd_2024_2026_m1.csv`) —
       resample from the same imported ticks so the tick source stays the proven-exact one
       ([[tick-source-parity-proven-exact]]); BTC ticks per [[btcusd-data-quirks]] (flat-spread years, weekend gaps).
    2. Get one **MT5 M3 reference run per symbol** (user-executed, exact ask per
       [[mt5-run-instructions-must-be-exact]]) to satisfy Gate 0 before trusting the engine on M3.
    3. **Surgical sweep only** (NOT a MasterVP-style 40-lever grid — that's an overfitting machine at this n):
       sweep **(i) EMA-alignment strictness**, **(ii) the trend-quality / sideways gate threshold**, and
       **(iii) the RR target / dynamic-RR-scaling** — the three the user named, nothing else held loose.
       Objective = costed PF/expectancy with maxDD penalty (CLAUDE.md), per-quarter decomposition (the M1
       lock was 87% one quarter — do NOT lock a pooled win that hides a dead quarter, cf.
       [[mastervp-m5-gate-sweep-lock]]).
  - **VALIDATE (per symbol, independently — do NOT pool XAU+BTC):** per-quarter + 6-fold WF (do not pool) →
    MC → **overfitting gate with the sweep context** (`research/stats/gate.py`, record `n_trials` +
    `sr_trial_std`) → only a **DSR-PASS + n≥MinTRL** config is a candidate → **single MT5 confirmation run on
    the final winner** before any lock/`.set`. BTC especially **must MT5-confirm** — engine wins on BTC have
    repeatedly proven fictional ([[mastervp-t3-reversion-lock]], the just-closed BTC revisit
    [[btc-no-robust-edge-closed]]); treat a BTC engine win as a hypothesis, not a result. E5 on M3 inherits the
    unresolved onset recall ceiling — **scope K1 to E1+E2 first**, fold E5 in only if/when the onset-latch
    instrumentation (top of HANDOFF) lands and M3 E5 parity is shown.
  - **DECISION RULE (per symbol):** adopt an M3 lock for a symbol only if it **beats that symbol's M1 baseline
    (XAU = `D3-noE4`; BTC has no validated KenKem baseline → must clear standalone PF/robustness bars) on PF AND
    robustness (per-fold, per-quarter) AND clears n≥MinTRL with DSR-PASS AND MT5-confirms**. Symbols are judged
    separately: XAU-M3 can lock while BTC-M3 rejects, or vice-versa. Otherwise M1 stays the XAU KenKem edge and
    the failing arm is logged tested→rejected. ⚠️ **Reality check on BTC:** every BTCUSD edge across MasterVP
    has just been closed for no robust edge on any TF — KenKem-on-BTC starts from that prior; the bar to ship
    BTC is correspondingly high.

- [ ] **K2 — Sweep KenKem (E1/E2/E5) on BTCUSD across M1, M3, M5 (user request, 2026-06-27).** KenKem has only
  ever been run on XAU M1; test whether its EMA-alignment trend entries find any edge on BTC at the three
  scalping timeframes. Per-TF, per-symbol — three independent sweeps (BTC-M1, BTC-M3, BTC-M5), each judged on
  its own merits; success on one TF does not imply the others.
  - 🔒 **PIP-HARDCODE PURGE IS A HARD PREREQUISITE (same gate as K1-BTC).** This is the BTC arm, so the
    pip→ATR conversion ([[goal-pip-to-atr-relative]], `docs/PIP_TO_ATR_INVENTORY.md`) MUST land first — at
    BTC `pip_size=1.0` the XAU-tuned pip params (esp. `EMA_ALIGNMENT_TOLERANCE_PIPS=23`, the alignment
    strictness knob) are meaningless and would silently mis-scale every threshold ([[kenkem-parity-traps]]:
    "BTC pip=1 std×2"). No BTC sweep number is trustworthy until decision params are ATR-relative.
  - 🔒 **PARITY FIRST (Gate 0).** Need one **MT5 BTC reference run per TF** (E1+E2 first; E5 separate) to
    confirm the engine reproduces MT5 on BTC bars before trusting any sweep — same doctrine as [[parity-is-gate-0]].
    BTC engine wins are historically fictional ([[mastervp-t3-reversion-lock]]) → **MT5-confirm or it doesn't count.**
  - 🔒 **MinTRL / sample size.** Report n + MinTRL on every candidate; M3/M5 thin the bar count vs M1 — a
    high-PF config below MinTRL is not lockable ([[overfitting-gate-mandatory]]).
  - **BUILD:** generate **BTC M1/M3/M5 bars** from the proven-exact imported BTC ticks
    ([[tick-source-parity-proven-exact]], [[btcusd-data-quirks]] — flat-spread years, weekend gaps); derive
    BTC's **own** session/blocked-hours and quality-gate thresholds empirically (do NOT inherit XAU's). Sweep
    surgically: EMA-alignment strictness, trend-quality/sideways gate, RR/dynamic-RR (the K1 levers) — **not** a
    40-knob grid. **Model realistic BTC costs** (spread + commission + weekend microstructure, pairs with T5).
  - **VALIDATE:** per-quarter + 6-fold WF (no pooling across TFs) → MC → overfitting gate (record n_trials +
    sr_trial_std) → DSR-PASS + n≥MinTRL → **single MT5 confirmation run on the winning TF/config** before any lock.
  - **DECISION RULE / PRIOR:** BTC has **no validated KenKem baseline**, and every MasterVP BTC edge across all
    TFs was just **CLOSED for no robust edge** ([[btc-no-robust-edge-closed]] — M3 dead/overfit, M5 full-window
    loser + MT5-disconfirm) — and KenKem's own **XAU M3** extension already **REJECTED** (RR-rescale overfit,
    K1 above / [[kenkem-m3-sweep-rejected]]). So the prior is strongly negative; the bar to ship any BTC TF is
    correspondingly high. Adopt a TF only if it clears standalone PF + per-fold/per-quarter robustness +
    DSR-PASS + n≥MinTRL + **MT5-confirms**; otherwise log tested→rejected per TF and keep KenKem XAU-M1-only.

- [ ] **K3 — Give KenKem a Volume-Profile dimension (reuse MasterVP's VP), A/B vs the M1 lock (user, 2026-06-27).**
  KenKem is pure EMA/ADX/RSI today; leverage MasterVP's tick-count VP (VAH/VAL/POC, value-area, node structure)
  to sharpen KenKem's entries/stops. User is open to a deeper rebuild if VP earns it.
  - **WHY THIS IS WELL-GROUNDED (not a fishing trip).** Phase-5 discovery (SHAP) found the playbook thesis
    **"Volume Profile > RSI"** — VP distances are the **dominant** forward-return drivers (`dist_val` #1,
    `dist_poc` #3, `dist_vah` #4), **strongest on M3** ([[discovery-findings]]). KenKem exploits **none** of it,
    so this is real unexploited signal AND qualifies as the **NEW entry geometry** the re-open rule requires.
    (Note: VP-on-M3 is a *different* lever than the rejected K1 EMA-RR-rescale — discovery actively favors VP on M3.)
  - ⚠️ **TERMINOLOGY — "tick volume" here = per-bar TICK COUNT, not traded volume.** This feed reports
    `VOLUME`/`LAST` = 0 (CLAUDE.md, [[btcusd-data-quirks]]); MasterVP's VP bins are built from tick count.
    KenKem must use the **same** measure for parity — do NOT introduce `iVolume` (see the node-net gap below).
  - **REUSE, don't reinvent:** the VP engine is already shared — C++ `cpp_core/include/kk/mastervp/
    {volume_profile,node_engine,regime}.hpp` + MQL `mql5/experts/VP-Common/{VolumeProfile,NodeEngine,
    Regime,Types}.mqh`. Wire these into the KenKem C++ engine (`cpp_core/include/kk/kenkem/`, no VP today) and
    the KK-KenKem EA, keeping the EA↔engine field mapping 1:1 so parity holds by construction.
  - **APPROACH = ADDITIVE + A/B, not a blind ground-up rebuild.** Keep the **MT5-confirmed M1 lock
    (D5-E4Long)** as the control. Add VP as **optional, default-OFF** modules and A/B each against the lock:
    1. **VP-anchored stops/targets** — SL just beyond the nearest VP node / TP at POC/VAH/VAL (structural, cf.
       the H6 FVG-SL idea but VP-based);
    2. **VP entry filter** — only take an EMA-aligned E1/E2/E5 entry that breaks/respects a significant VP level;
    3. **VP-conditioned RR / sizing**. Only if a module decisively beats the lock does it graduate; only if VP
       becomes the *core* thesis do we discuss a distinct VP-native EA (don't discard a validated baseline on spec).
  - 🔒 **NODE-NET MQL↔C++ PARITY GAP IS A HARD PREREQUISITE if any module uses the node-net VALUE.** H12c
    exposed that the EA feeds `iVolume` (MT5 tick-vol) to node bins while the engine uses imported `tick_count`
    → node-net values diverge systematically MQL↔C++ ([[mastervp-h12-entry-flow-veto-rejected]]). VAH/VAL/POC
    *distances* are likely safe; **node-net/absorption is NOT** until per-entry MQL↔C++ node-net parity is proven.
    Pick distance-based VP features first; gate any node-net feature behind that parity proof.
  - 🔒 **DISCOVERY/EDGE-AUTOPSY FIRST, then sweep.** Each VP module is a new entry/exit rule → run
    `/quant-6b-edge-autopsy` (prove conditional edge model-free) BEFORE spending sweep cycles, per
    [[engine-pregate-signal-export]] / CLAUDE.md. The model-free autopsy is the trustworthy gate (the engine
    exit model is suspect [[bar-engine-systemic-defect]]).
  - 🔒 **PARITY (Gate 0) + MinTRL + costs** as for K1/K2: VP changes the trade set → need an MT5 reference run
    to confirm the engine reproduces it; report n + MinTRL on every candidate (KenKem is already near MinTRL —
    a VP filter that thins the count can break the gate); model real spread/commission. BTC arm inherits the
    K2 **pip→ATR purge** prerequisite.
  - **VALIDATE / DECISION RULE:** per-quarter + 6-fold WF (no pooling) → MC → overfitting gate (n_trials +
    sr_trial_std) → DSR-PASS + n≥MinTRL → **single MT5 confirmation run** before any lock. Adopt a VP module
    only if it **beats the D5-E4Long M1 lock on PF AND per-fold/per-quarter robustness AND MT5-confirms**;
    otherwise log tested→rejected and keep the lock. Sequencing: post-P4 research track (parallel to K1/K2),
    does NOT block the existing lock.

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
