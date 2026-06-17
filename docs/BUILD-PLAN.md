# KenKem Quant OS — Build Plan & Progress Tracker

Living checklist. Source of truth = MQL5 (`kenkem/MQL5/Experts/`) for KenKem; **Pine** for Monster.
Each step: build → `make -C cpp_core test` → commit → push → tick this file. Update `HANDOFF.md` last.
Legend: `[x]` done · `[~]` in progress · `[ ]` todo · 🔒 = hard gate (cannot proceed past until met).

Completed phases archived in `BUILD_PLAN_ARCHIVED.md`.

---

## 🎯 The one goal

**Mode: autopilot.** Make the dquants tick engines reproduce MT5 "every tick" exactly, then run
trustworthy sweeps to rank a production candidate that **beats the user's KenKemExpert 1.8.154** (and
the Monster baseline) on costed, walk-forward-validated metrics — then port the winner back to MQL5.

## 🔒 Locked decisions (2026-06-18)

| # | Decision | Choice |
|---|----------|--------|
| 1 | KenKem parity gate before optimizing | **Exact-bar ≥8/9 on the Feb-2026 anchor FIRST** (+ P&L parity on matched trades). Purist; parity is a hard gate. |
| 2 | Monster ground truth & start point | **Pine is the spec.** Validate/complete the C++ Monster engine against Pine behavior, optimize in C++, port to MQL5 last. |
| 3 | Optimization objective | **Costed PF / expectancy** primary; a candidate is only eligible after the full SOP §7 chain: costs → sensitivity plateau → walk-forward OOS positive → Monte-Carlo 5th-pct positive. |
| 4 | MT5 validation loop | **Fully autonomous in C++**; a single MT5 confirmation run on the *final* winner only. No mid-run MT5 pauses. |

Cost model is mandatory in every backtest (spread, slippage, commission, latency) — uncosted = fantasy.
Prefer plateaus over peaks. OOS stays OOS. Keep the ATR-regime filter (profitability lever) — never delete it.

---

## Phase A 🔒 — KenKem parity to ≥8/9 exact-bar + P&L (the gate to optimization)

Anchor: `KenKemExpert.mq5` v1.8.154 @ defaults · XAUUSD M1 · every-tick · **Feb-2026** · 10000 / 1:500 ·
E1+E2+E4 on, E3+E5 off. Ground truth: `research/kenkem_parity/mt5_runs/RUN_2026-06-17_1.8.154_xau_feb/`.
Current state: **3/9 exact-bar match**, PF 0.49. Remaining wall = detection **timing** (engine fires the
right type/direction 1–11 bars early, consuming the one-cross trigger). Diagnosis docs:
`PARITY_1.8.154_POST_ROUTING_DIAGNOSIS.md`, `CPP_VS_MQL_FAITHFULNESS_AUDIT.md`.

- [ ] **A1 — Trigger timing (B3), the top lever.** Align ichi-cross / EMA75-touch / EMA-cross triggers
  (`triggers.hpp`) to the EA's **forming-bar** evaluation so the cross is detected on the SAME bar as the
  EA, killing the −1/−2 early fires that consume the trigger. Diagnose with the oracle trade list
  (engine 02.17 13:18 S-E4 vs EA 13:20; 02.04 07:44 L-E2 vs 07:45). Re-run, re-diff.
- [ ] **A2 — EMA-stack gate shift (B2).** `emas_ready_entry` reads `align.tf−3`; verified snapshot truth
  is `align.tf−2` near crossovers. Fix and re-diff.
- [~] **A3 — E1 phantom over-detection (3.4×: 624 eng vs 183 MT5).** ROOT CAUSE localized (2026-06-18):
  armed E1 trigger fires LATE within its 80-bar window — `E1_MAX_CROSS_AGE` sweep is the lever (80→576,
  1→154≈MT5). Engine arms ~7289× (cross 3806 + touch 3687) vs MT5 far fewer. RULED OUT: ATR (binds),
  conviction (0% rej in MT5 too), trend-quality, pip_size, AND the B2 EMA-shift (tested align-2 on trigger
  AND gate → worsened match 155→130, reverted). MT5 rejection histogram (tester.log): E1 HTF 58%, MTF/EMA
  31% — but engine HTF is redundant with MTF (insensitive to threshold). **LEAD (trace diff):** engine's
  `trend_core` HARD GATE passes where MT5's fails (over-fire bar 2024-01-15 05:50: `L_tcore` cpp=6 mt5=0,
  `L_pass` cpp=1 mt5=0). Trace shows DI |Δ|~3 but `dmi_adx_mt5` is validated <0.005 vs MT5 — so verify the
  DI trace-column SHIFT before assuming a formula bug; the robust signal is the gate disagreement. MT5's
  trend_core=0 there isn't explained by its own bullish logged DI → find the shift/input. See HANDOFF.md.
- [~] **A4 — Skip-rule fidelity.** Loss cooldowns PORTED (`UpdateLosingStreak`: global escalating +
  per-(kind,dir) 60-min) in `tick_engine.hpp`, behind `ENABLE_LOSS_COOLDOWNS` (default OFF — depends on
  per-trade win/loss; exits not yet faithful (A7), so currently blocks real matches too: 155→137). Re-enable
  after A7. Still TODO: daily-loss + drawdown EOD-block (rarer; DD block triggers at 10.5% from peak).
- [ ] **A5 — Re-check the remaining E4 misses** once phantoms stop occupying slots.
- [ ] 🔒 **A6 — GATE: ≥8/9 exact-bar entry match** on the anchor (`build/kenkem/entry_trace` + `parity_diff.py`).
- [ ] **A7 — Exit / SL-TP / P&L parity.** Re-verify the E1/E2/E4 exit toggles (panic / score-drop /
  session-end — `SPEC_EXITS.md` was mapped for E5, re-map for E1/E2/E4), port managed exits, diff
  `exitPrice` / `realizedUsd` per matched trade with `diff_kenkem_trades.py`.
- [ ] 🔒 **A8 — GATE: aggregate P&L parity** — matched-trade exit price within fill tolerance and engine
  total PF/net within tolerance of MT5. Now the engine's PF is trustworthy to optimize against.
- [ ] **A9 — Regression lock.** Add a `make test` parity regression (anchor must stay ≥8/9) so optimization
  can't silently break faithfulness. Tag baseline commit.

**Exit criteria:** A6 + A8 green, regression locked, baseline 1.8.154 metrics recorded as the bar to beat.

---

## Phase B — KenKem optimization (autopilot sweeps)

Engine now MT5-faithful → sweeps are trustworthy. Tools: `optimize_kenkem.py` (Optuna),
`robustness_kenkem.py`, `report_kenkem.py`. Data: full XAU tick/bar history (re-export missing days per
`XAU_TICK_REFETCH_LIST.md` if needed; Feb anchor is clean).

- [ ] **B1 — Record baseline.** Run 1.8.154 defaults over the full costed history; lock its PF /
  expectancy / maxDD / trade-count / Sharpe as the bar to beat (`reports/` table, 9-col perf format).
- [ ] **B2 — Define search space.** Entry thresholds (conviction/trend-quality per E1/E2/E4), ATR-regime
  band (`MIN_ENTRY_ATR_PERCENTILE`, `ATR_HIGH_BLOCK` — sweep, never delete), SL/TP & trailing, session
  windows, risk/lot caps. Keep params named identically to MQL5 for 1:1 back-port.
- [ ] **B3 — Coarse Optuna sweep** (costed objective = expectancy × PF, penalize maxDD). In-sample only.
- [ ] **B4 — Sensitivity heatmaps** around top configs (`sensitivity_btc.py` pattern adapted) → keep only
  params sitting on a **plateau**, discard lone peaks.
- [ ] 🔒 **B5 — Walk-forward** (`quant-9` / WFA harness): rolling in-sample→OOS, OOS must stay positive.
- [ ] 🔒 **B6 — Monte-Carlo robustness** (`robustness_kenkem.py`): trade-order/bootstrap resample, 5th-pct
  net profit positive.
- [ ] **B7 — Rank candidates** vs the 1.8.154 baseline; lock the top 1–3 as `.set` in
  `kenkem/MQL5/Presets/` (and `research/optimization/`). A candidate is eligible only if it ≥ baseline AND
  passes B5+B6.

**Exit criteria:** ≥1 candidate beats 1.8.154 on costed expectancy/PF and survives WFA + MC.

---

## Phase C — Monster: C++ validation vs Pine, then optimization

Spec: `kenkem-pine/kk-vp/KK-MasterVP-Monster.pine` (1644 lines) + `kenkem/notes/strategies/KK-MasterVP-Monster.md`.
C++ engine exists: `cpp_core/include/kk/monster/` + `tools/monster/monster_backtester.cpp` (147 params).
Optimizer: `optimize_monster.py` / `optimize_monster_real.py` / `eval_monster.py`.

- [ ] **C1 — Behavioral audit C++ vs Pine.** Map each of the 4 entry kinds (breakout / mean-rev v1 / mean-rev
  v2 / impulse-thrust), the rolling 150-bar master profile, multi-TF net-tick-volume confirmation, and the
  gates (regime / HTF-bias / overhead-supply / POC-stability). Flag any divergence (no-repaint, no-lookahead).
- [ ] **C2 — Pine reference capture.** Pull Pine strategy results / signal series via the TradingView MCP
  (`data_get_strategy_results`, `data_get_trades`, `data_get_pine_*`) on a fixed window as the C++ reference.
- [ ] **C3 — Reconcile** the C++ engine to the Pine reference (signal-level first, then trade/P&L) until
  trade timing + aggregate PF agree within tolerance. This is Monster's parity gate (Pine, not MT5).
- [ ] **C4 — Baseline + search space**, then **coarse sweep → sensitivity → WFA → MC** (mirror B3–B7 with
  Monster tools) on XAU and BTC. Lock top 1–3 `.set`.

**Exit criteria:** C++ Monster matches Pine within tolerance; ≥1 optimized candidate beats the Monster
baseline and passes WFA + MC on both symbols (or the agreed subset).

---

## Phase D — Port winners to MQL5 + final MT5 confirmation

- [ ] **D1 — KenKem:** apply the winning params (defaults/`.set`) to `dquants/mql5/experts/KenKem/`
  (the symlinked DEPLOY EA — edit HERE). Logic already faithful from Phase A; this is mostly params.
- [ ] **D2 — Monster:** port the validated C++ logic + winning params into the MQL5 EA
  (`kenkem/MQL5/Experts/KK-MasterVP-Monster/`, currently a 482-line stub) following the existing port plan
  notes. Keep param/function names mirrored 1:1.
- [ ] **D3 — Compile** both via `scripts/compile_mql5.sh`.
- [ ] 🔒 **D4 — SINGLE MT5 confirmation run** on the final winner(s): hand the user a copy-paste run recipe;
  confirm MT5 every-tick results tie out to the C++ engine within fill tolerance. (Only mandatory MT5 step.)
- [ ] **D5 — Production promotion** per `docs/KENKEM_QUANT_OS.md §7` (demo forward-test plan).

---

## 🤖 Autopilot operating rules

- Per step: build → `make -C cpp_core test` → commit → push origin → tick this file. Update `HANDOFF.md`
  whenever pausing/handing off (current goal, what changed + hashes, what's blocked, exact next action).
- **Hard gates (🔒) are non-skippable.** Do not enter Phase B until A6+A8 are green; do not lock a candidate
  that fails WFA or MC. Surface failures honestly (numbers, not vibes).
- Tick engine only for any P&L/parity claim (bar engine has a sign defect).
- Costs modeled in every run. ATR-regime filter stays in (sweep it, never delete).
- No MT5 mid-run; one confirmation at D4. If something genuinely needs the user (e.g. XAU tick re-export,
  the D4 run), note it in `HANDOFF.md` and continue with everything not blocked on it.

## ⚠️ Known traps (carry forward)
- EMA non-series `CopyBuffer` shift = 2 (looks like 1). Ichimoku buffer-swap (var names ≠ buffer order).
- `shift-0` = forming-bar first tick (O=H=L=C=open); model M3/M5 forming bars by aggregating M1 in the
  current bucket — never read the future complete bar.
- XAU tick export is missing whole trading days (`XAU_TICK_REFETCH_LIST.md`); Feb anchor is clean.
- Tester `.set` profile overrides source defaults — pin every behavioral key.
