---
name: phase14-profitmanager-and-todos
description: NEXT WORK — build common toggleable ProfitManager module + sweep-validate; plus the Phase-14 risk/exit audit todos (C1-C7, incl. C7 AdaptiveState/self-tuning verdict)
metadata: 
  node_type: memory
  type: project
  originSessionId: 35fbde55-89b4-4144-9fa7-95c311572ed0
---

## ⭐ START HERE (2026-06-15, fresh AUTOPILOT session) → execute `docs/BUILD-PLAN.md` § C8
**C5 ProfitManager is DONE** (built, wired, round-1 SL sweep — only MasterVP-BTC giveback adopted). **KenKem-E5
PROMOTED to production MQL5** (`mql5/experts/KK-KenKem/`, locked `best_kenkem_{btc,xau}.set`, see
[[kenkem-distilled-result]]). **NEW APPROVED WORK = C8** (committed `bb2b560`; full plan
`~/.claude/plans/deep-jingling-fountain.md`): missing-sweep program — staged build, all phases approved at max
scope. Order: **C8.1** sweep never-tested tunables (⭐ ATR length on Monster `InpAtrLen` 5–16 + KenKem
`ATR_PERIOD_FOR_SL` 5–16 — textbook-14 never challenged; Monster net thresholds + `enable_net_persist`; KenKem
Ichimoku/lookbacks; MasterVP adx/rsi len) → **C8.2** promote hardcoded constants (Monster `node_decay`/
`net_win_atr`/`tf_net_look`…) to params + sweep → **C8.3** news avoidance (build C++ `news_active_`, `--news`
flag, port 2025 CSV + source 2026, sweep ON/OFF × combos) → **C8.4** Monster tick-rule volume reliability
(`tr_net`+`tr_reliab` from raw ticks, default inert, sweep) → **C8.5** verify + cross-engine bake-off. Every
new param defaults OFF/current (parity unit test); adopt to locked `.set` only if **net↑ AND DD↓**; rank on
**2026 OOS**; report the **9-column table** ([[perf-table-format]]). Autopilot = run end-to-end, commit/push
each step, revert on breakage ([[autopilot-mode]]). Below = the older C5/Phase-14 brief (C5 now done).

**User directive (2026-06-14, to start in a FRESH session — context was full):** FIRST implement a common
`ProfitManager` module in the dquants codebase, THEN run a few rounds of sweeps to see if it actually helps
BTC & XAU. Standard rule still applies: **adopt a toggle into a locked `.set` ONLY if net↑ AND drawdown↓**
(risk-adjusted); otherwise keep the code inert (default OFF) and leave `.set` files unchanged. Full detailed
checklist lives in `docs/BUILD-PLAN.md` → **Phase 14** (committed `0638cba`). This memory = the resume brief.

## IMMEDIATE NEXT ACTION — C5: common ProfitManager module (top priority, supersedes "adaptive trailing")
Extract the proven (but never-validated) profit-mgmt toolkit from `../kenkem` KenKemExpert into ONE shared
toggleable module. Two layers (mirror the four-layer architecture):
- **`kk::common::ProfitManager` (C++, PURE = validation source of truth)** — input: TradeState {entry, sl, tp,
  is_long, best_price(MFE), current_price, original_risk, atr, bars_held, + optional structure_level, +
  optional trend_weakening} + toggle config → output actions {new_sl, new_tp, partial_frac}. No broker calls.
- **`KK-Common/ProfitManager.mqh` (MQL5, thin)** — ports 1:1, does PositionModify/partial + stops/freeze clamp.

Six INDEPENDENT ON/OFF toggles (each ported from a KenKemExpert function — see source line refs below):
1. `be_protect` — at N×R → SL to entry+buffer. PURE. (`ApplyRMultipleSLProtection` ~L402)
2. `progressive_trail` — R-milestone stepped SL tightening = accelerating trail. PURE. (`ApplyConservativeTradeManagement` ~L486, `ApplyLadderStage` in EA ~L1684)
3. `giveback_cap` — once peak MFE ≥ thresh, stop can't retreat >X% of peak. PURE. **Most direct fix for the observed 3R→gave-back-2R.** (`HasSignificantRetrace` ~L30)
4. `tp_extension` — push TP further while trend persists, capped. Needs a `trend_weakening` bool from engine (falling ADX / flat EMA-slope). (`ExtendTPAsNeeded` ~L606)
5. `pre_be_structure` — tighten to BOS/swing before BE. Needs a prior-swing structure level from engine. (`ApplyPreBEStructureProtection` ~L284)
6. `partial_tp` — R-trigger partial. PURE. (`TakePartialProfitAsNeeded` ~L674)
Source file: `../kenkem/MQL5/Experts/KenKem/TradeManagement/TradeManager.mqh` (pipeline = `ProcessAllTrades` ~L76).
Wire ProfitManager into all 3 C++ engines, REPLACING their duplicated BE/trail/partial; **default = current
behavior (inert)** so baselines reproduce. Files to touch: `cpp_core/include/kk/common/position_manager.hpp`
(MasterVP fixed chandelier trail ~L155), `kk/monster/monster_engine.hpp` (trail ~L271, OFF by default),
`kk/kenkem/trade_manager.hpp` (chandelier `best - trailing_factor*risk` ~L85).

**Recommended sweep order:** start with `giveback_cap` + `progressive_trail` (both PURE, highest EV), on the VP
engines first (MasterVP + Monster), BTC & XAU. Reuse the sweep pattern: `research/optimization/sweep_*_f2.py`
style + `eval_mastervp.py` / `eval_monster.py`. **Env: run with `~/miniforge3/envs/kenkem/bin/python`** (NOT
`conda activate` — see [[python-env-kenkem]]). Backtester binaries: `make -C cpp_core backtester monster kenkem`.

## OTHER PHASE-14 TODOS (priority order after C5)
- **C2 (high, safety):** KenKem (production pick #1) has ZERO drawdown breakers. Wire a unified risk controller
  (softblock micro-lot, daily/peak-DD halt, loss-streak + wait-hours cooldown) into `kk::kenkem`. MasterVP &
  Monster already have it but UNTUNED. Instrument backtests to COUNT activations (confirm they fire). Tune limits
  on a SECONDARY objective (min tail-DD / max Calmar) with a net guardrail — **do NOT return-optimize risk limits.**
- **C1 (cheap):** blocked-hours are a past-biased hardcode (MasterVP "8,10,11,16"), never tuned; kill-switch already
  exists (empty `InpBlockedHoursStr`). Add hour-of-day expectancy report on latest data; sweep {none/empirical/current}.
- **C4 (small):** fold the adopted Monster-BTC `stp2_*` (+enable) into `optimize_monster_real.py` SPACE so re-opts
  co-tune them (currently only in the one-off F2 sweep). Trailing-TP2 is delivered by C5's `tp_extension` toggle.
- **C6 (big; also Phase 9):** walk-forward harness — optimize [t−N,t] → freeze → trade OOS [t,t+M] → stitch OOS
  curve; metric = Walk-Forward Efficiency (OOS/IS; >~0.5–0.6 = not overfit). This is the principled answer to the
  user's "adaptive params" wish: NOT online alpha self-tuning (that broke half-baked KenKemExpert), but offline
  rolling re-opt writing a guarded dynamic `.set` the EA loads from `MQL5/Files/`. Online updates only for slow
  descriptive stats (vol bands, session profile, spread). Regime-conditioned param sets = middle-ground fallback.
- **C7 (NEW, user concern 2026-06-14 — "should EAs do adaptive learning/ML to self-tune & persist?"):** VERDICT =
  yes but REFRAMED. "EA learns its own alpha online" is REJECTED — structurally unvalidatable (= the dead
  KenKemExpert path the user already switched off; his overfitting instinct was correct, not lack of knowledge).
  Deliver adaptiveness as a THIRD common toggleable module `kk::common::AdaptiveState` (+ thin `KK-Common/
  AdaptiveState.mqh`), SAME pattern as ProfitManager: PURE Layer-2, default OFF/inert, adopt only if net↑ &
  drawdown↓. THREE TIERS, lowest-risk first: **Tier 0** vol-normalisation (SL/TP/trail/size as ATR/EWMA-vol
  multiples — a units fix, highest EV, mostly already in engines); **Tier 1** regime-conditioned FROZEN param sets
  (small regime buckets ATR%×session×ADX, walk-forward-optimised offline, EA selects pre-validated set by rule —
  the "smart" feel, still deterministic/parity-able); **Tier 2** true online learning (bandits/RL) = explicitly
  DEFERRED, overkill. PERSISTENCE: persist slow ESTIMATORS (EWMA vol, spread, session profile) NOT opaque tuned
  params, to `MQL5/Files/` versioned JSON; max-staleness guard; missing/corrupt/stale → cold-start validated
  default (OFF path stays byte-identical). VALIDATION (the user's old blocker): validate the MECHANISM not the
  moving params — A/B static vs adaptive on identical ticks in the C++ engine, OOS PF/Calmar/MaxDD + Monte Carlo,
  BTC & XAU, standard risk-adjusted gate. Full spec: `docs/BUILD-PLAN.md` → Phase 14 → **C7**.
- **C3: DONE** — TP1 level + percentile already tuned in all three (no action).

## CROSS-BROKER DATA (open thread, see [[cross-dataset-harness]])
User wants real-tick validation across OANDA/Exness/Binance. Harness is built & ready. Honest sourcing reality:
**I can fetch real Binance BTCUSDT public history myself** (`data.binance.vision`, no auth — BTC only, no XAU,
USDT-margined so costs differ). **Exness/OANDA + all XAU need the user's terminal exports** (I can't auth). Decision
pending: pull free Binance BTC now as a first cross-check, or wait for user exports. Run via the DuckDB harness.

## R&D SO FAR (context): only adopted win = Monster-BTC structural-TP2 (F2). F1/F2/DeferredEntry otherwise
marginal/engine-specific or risk-adjusted-worse — see [[rnd-volume-features]]. End goal unchanged: promote #1
strategy (KenKem-E4) to production MQL5 — see [[milestone-production-promotion]]. Standing workflow
[[workflow-commit-and-plan]]: test→commit→push→tick BUILD-PLAN after each step.
