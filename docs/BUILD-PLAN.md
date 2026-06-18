# KenKem Quant OS — Build Plan & Progress Tracker

Living checklist. Source of truth = MQL5 (`kenkem/MQL5/Experts/`). Pipeline rules = `research/PIPELINE-CONTRACT.md`.
Each step: build → `make -C cpp_core test` → commit → push. Legend: `[x]` done · `[~]` in progress · `[ ]` todo.

> **Completed phases are archived** in [`BUILD_PLAN_ARCHIVED.md`](BUILD_PLAN_ARCHIVED.md): data pipeline (Phase
> 1–5), Phase 6, Phase 7 (MasterVP tick engine + parity), Phase 8 (optimization), Phase 9 (light WFA/MC),
> Phase 11 (MasterVP-Monster), Phase 12 (real-Monster engine), Phase 13 (KenKem engine), R&D F1/F2/DeferredEntry,
> ProfitManager round-1. This file tracks only **live + deferred** work.

---

## 🎯 The one goal
Make the **dquants tick engines reproduce MT5 "every tick" exactly**, then run **trustworthy sweeps** to rank a
production candidate that ≥ the user's profitable original `KenKemExpert`. Mode: autopilot, commit as you go,
revert bad code, **don't lie** (every PF names the engine+binary that produced it).

## 🚨 Trust state (2026-06-16) — READ FIRST
- **None of the 3 dquants ports (MasterVP/Monster/KenKem) is MT5-profit-validated.** The user ran all three in
  MT5; all bad. Only the ORIGINAL `KenKemExpert` (E1+E2, PF 1.62) works. See `research/optimization/HONEST-AUDIT-2026-06-16.md`.
- **Root cause found & FIXED this session — systemic param contamination:** the engines exposed `.set` keys the
  EAs *hardcode* (not `input`s); MT5 silently ignored them, so any sweep that moved one produced a config MT5
  can't reproduce → it lost when deployed. Engines now **structurally refuse** EA-locked keys (`is_ea_locked_key`
  / `monster_non_input_keys`; tests `test_ea_locked_keys_ignored`, `test_monster_locked_keys_ignored`). Audit:
  `research/kenkem_parity/PARAM_SURFACE_AUDIT.md`. Commits `82fb4b9`, `ece8f2b`, `6c4ad18`.
- **Consequence:** every existing `best_*.set` was swept under contamination and/or on the bar engine → **all
  untrusted, must be regenerated** by a clean tick-engine sweep over Class-A (honorable `input`) params only.

---

## 🔴 LIVE WORK (in priority order)

### L1 — Re-validate MasterVP + Monster on the cleaned tick engine
- [ ] Regenerate data (`bars_xauusd_2425_*.csv` + `ticks_xauusd_2425_window.csv`, see `MASTERVP_MONSTER_PARITY.md`).
- [ ] Re-run both on the tick engine post-contamination-fix; confirm no regression vs their MT5 oracles, confirm
      profitable. MasterVP signal-logic is already MT5-validated ([[mastervp-tick-engine-mt5-validated]]) — verify
      the `InpAtrLen` leak closure didn't move it.

### L2 — Build a TICK-ENGINE sweep harness + regenerate `best_*` honestly
- [ ] Replace the bar-engine `optimize_kenkem.py` BIN (or new script) so all sweeps run on the tick engine
      ([[bar-engine-systemic-defect]]: the bar engine disagrees with MT5 on the **sign** of P&L).
- [ ] Regenerate the `best_*` candidates over Class-A params only (`optimize_kenkem.py` already strips locked keys
      from its search space, `6c4ad18`; do the same for MasterVP/Monster sweeps).
- [ ] Produce the standard **9-column** comparison table ([[perf-table-format]]) → top production pick.

### L3 — Monster economics divergence (engine PF ~1.23 vs MT5 ~18% TP loss)
- [ ] Signal-firing is NOT the bug (engine fires 2,576 entries, not 0). Costs are NOT the bug (Exness Pro is
      **commission-free**; engine models $0 commission + real spread from ticks; commission now importable anyway
      via `CommissionPerLot`/`InpCommissionPerLot`, config.hpp:324). **Suspect = exit geometry OR a spread mismatch
      between the engine's tick feed and MT5's modeled spread.**
- [ ] Build `research/validation/parity_diff.py` to turn the manual MT5 run into a real gate, then run the first
      Monster trade-level engine-vs-MT5 diff to pinpoint exit-geometry vs spread.

### L4 — Close KenKem tick-parity residuals (refinements, NOT sign inversions)
State after the RSI/ADX_LEN lock: XAU E5 150→139 trades (MT5 136), net +559/PF 1.10 (MT5 +995/1.23), verdict
un-inverted, geometry mean|Δ|=0.03. Evidence: `cpp_trades_xau_locked.csv`, `research/kenkem_parity/PARITY_RESULT_XAU.md`.

> **⭐ NEW critical-path artifact (2026-06-16): `research/kenkem_parity/CPP_EA_PARITY_LEDGER.md`.** Full
> line-by-line C++ engine (truth) ⇄ deployed **KK-KenKem EA** divergence map. The EA is the *distilled
> subset*, not the "faithful transcription" its header claims — it dropped the session gate, ATR-percentile/
> quality/conviction/RSI-div entry filters, panic + score-drop exits, session-end close, and DD guards.
> Reconciliation = Path B (bring the EA UP to the engine, each row default-OFF then ON, one MT5 run each).
- [x] **C++ manage_tick ⇄ EA `Manage()` byte-parity (C1+C2, done 2026-06-16):** partial slice now floors to
      the broker volume step + requires ≥min_lot (mirrors EA `MathFloor(q/step)*step`); broker
      `stops_level_price` modeled on BE/trail SL moves (default 0 = inert for Exness). +3 regression tests.
- [ ] **Ledger reconciliation (EA → engine):** sessions (A1/B2) → quality suite (A4–A7) → ATR regime (A2/A3)
      → panic/score-drop (B3/B4) → guards (D3) → sizing (E2). Each: port into KK-KenKem default-OFF, MT5 run,
      `parity_diff.py` PASS. **Sessions first — biggest trade-count lever** (engine trades JP/LN/NY only; EA 24h).
- [ ] **Entry lag (~3–6 min):** M1 indicator micro-drift flips the strict `25>75>100>200` onset, worst at
      weekly-open bar seams (close max|Δ|=42 at a Sun 22:09 bar). Chase tick→M1 bucketing across daily gaps.
- [ ] **Exit geometry:** dquants closes via tight `SL-WIN` trail; MT5 closes via EA-managed exits → win% 77.7 vs
      52, PF 1.10 vs 1.23. Reconcile the E5 exit path ([[kenkem-e5-root-cause-exits]]). (KenKem manage_tick↔EA
      now byte-equal post-C1/C2; residual is the dropped panic/score-drop/session exits — ledger B2–B4.)
- [ ] **E3 coverage:** C++ covers E1/E2/E4/E5 but NOT E3; traces are E5-only. Add E3; per-entry parity.
      Harness is built and waiting on a user MT5 run ([[kenkem-parity-harness-built]]).

---

## 🟡 DEFERRED BACKLOG — unlock ONLY after L1–L4 (engines reproduce MT5)
These are real, still-open concerns, but they are **premature**: a sweep is meaningless until the engine it runs
on reproduces MT5. Standing rules when they unlock: new param/feature defaults to current value or OFF (parity-safe
+ all-OFF==prior unit test); adopt into a locked `.set` only if **net↑ AND DD↓**; sweep 2025, rank on 2026 OOS;
prefer plateaus; report the 9-column table. Full C8 plan: `~/.claude/plans/deep-jingling-fountain.md`.

- [ ] **C2 — KenKem drawdown breakers (SAFETY GAP, highest priority of this group):** the production pick #1 has
      ZERO DD breakers. Add a unified risk controller (softblock micro-lot, daily/peak-DD halt, loss-streak +
      wait-hours cooldown) to `kk::kenkem`; instrument backtests to COUNT activations; tune on a secondary
      objective (min tail-DD / max Calmar) with a net-drop guardrail. **Do NOT return-optimize risk limits.**
- [ ] **C1 — Blocked-hours retune:** MasterVP `InpBlockedHoursStr` is baked from 2025, never tuned. Add an
      hour-of-day expectancy report over the latest data; sweep {none / empirical / current} per symbol.
- [ ] **C4 — TP2 / trailing-TP2:** fold Monster's `stp2_*` (the F2-adopted params) into the MAIN optimizer space
      so re-opts co-tune them. Trailing TP2 comes from C5's `tp_extension`.
- [ ] **C5 — ProfitManager round-2:** sweep `be_protect` / `partial_tp` (PURE) on the round-1 rejects; then
      `tp_extension` / `pre_be_structure` once a trend-weakening + prior-swing feed is wired from each engine.
      Then port adopted toggles to MQL5 `KK-Common/ProfitManager.mqh`. (Round-1: only MasterVP-BTC giveback adopted.)
- [ ] **C6 — Walk-forward harness:** optimize `[t−N,t]` → freeze → trade OOS `[t,t+M]` → roll → stitch; metric =
      Walk-Forward Efficiency (>~0.5–0.6 = not overfit). Compare WFA-OOS vs static `.set` OOS. If it passes:
      scheduled offline re-opt → guarded dynamic `.set` the EA loads from `MQL5/Files/`.
- [ ] **C7 — AdaptiveState module (the "self-tuning EA" ask, done safely):** PURE Layer-2 `kk::common::AdaptiveState`
      + thin MQL5 adapter, default OFF. Tier 0 vol-normalisation (units fix, mostly done) → Tier 1 regime-conditioned
      FROZEN param sets (offline-validated lookup table) → **Tier 2 online learning DEFERRED/out-of-scope** (the dead
      KenKemExpert self-tuning path — unvalidatable). Persist *estimators*, never opaque tuned params; stale/corrupt
      → cold-start default. Validate the MECHANISM (A/B static vs adaptive on identical ticks), not moving params.
- [ ] **C8 — Missing-sweep program** (only ALREADY-tunable, then promote constants, then build):
  - [ ] C8.1 Sweep never-tested tunables: Monster `InpAtrLen`(5–16) + net-verdict thresholds + persistence;
        KenKem `ATR_PERIOD_FOR_SL`/Ichimoku/lookbacks; MasterVP `adx_len`/`rsi_len`. (ATR=14 textbook daily never swept.)
  - [ ] C8.2 Promote high-value hardcoded constants to params (Monster `node_decay`/`net_win_atr`/`tf_net_look`;
        MasterVP VP-node knobs), each with a default-reproduces-prior unit test, then extend the sweeps.
  - [ ] C8.3 **News avoidance** (not implemented in ANY C++ engine → never sweepable): port 2025
        `HighImpactNews_USD.csv` + source 2026; shared `kk::common::news.hpp`; `--news` backtester flag; sweep ON/OFF.
  - [ ] C8.4 Monster near-price volume RELIABILITY: tick-rule signed-volume `tr_net` + intra-bar stability
        `tr_reliab` from raw ticks (richer bar export); gate `use_tr_verdict`; sweep for fewer/higher-quality entries.

## ⏸️ Awaiting user input (not blocked on us)
- [ ] **Cross-dataset robustness:** harness is BUILT ([[cross-dataset-harness]], `research/validation/`). Drop broker
      files under `data/external/<broker>/`, copy spec to `datasets.json`, run `ingest` + `cross_validate` to confirm
      each locked edge holds broker-to-broker. **AWAITING USER DATA.**
- [ ] **MT5 confirmation:** any regenerated config must be run in the MT5 tester on the recent OOS window before it
      is trusted (the tick engine is necessary but the MT5 tester is the gate — PIPELINE-CONTRACT VALIDATE gate).
