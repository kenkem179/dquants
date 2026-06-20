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

## 🔥 ACTIVE THRUST (2026-06-20) — profitability uplift for MasterVP + Monster

Both EAs are locked & shipped (Monster BTC M3 anti-chase opt PF 1.20; MasterVP XAU M5 PF 1.33). User
asked for the top actionable profitability levers. Ranked plan (Tier 1 = lowest-effort robust wins):

- [x] **T1 — Dormant quality-gate sweep (DONE 2026-06-20, commit ded3e81)** — **MasterVP XAU M5: tested →
  REVERTED.** Gates `BrkVetoSfp`+`MomVeto`+`MtfAgree` improved POOLED 6-fold PF 1.243→1.274 + MC DD
  27.7→23.1% but per-fold + MT5 decomposition showed the gain is from 2025; they HURT the recent 4mo
  (F5 −28%, F6 −43%; 2026 H1 baseline wins every axis). User chose baseline. **MT5 parity CONFIRMED
  faithful** (424/489 matched). **Monster BTC M3: NEGATIVE** — no gate beats baseline, no change. 🔑 LESSON:
  decompose per-fold (recent OOS) before locking a filter. Below = original framing — both editions ship gates off
  that already exist in code but ship OFF: `InpBrkRequireFlow`, `InpBrkVetoSfp`, `InpUseMomVeto`,
  `InpUseMtfAgree` (+ `InpNodeGateEnabled` for MasterVP). 6-fold WF (`wf_monster.py` for Monster BTC M3;
  new `wf_mastervp.py` for MasterVP XAU M5). Adopt only robust improvers (folds-PF>1 ≥ baseline, no
  worst-fold regression). ⚠️ **PORTABILITY:** for the **KK-MasterVP EA** `InpNodeGateEnabled` &
  `InpBrkRequireFlow` are compile-constants (`non_input_keys()` in config.hpp) — MT5 ignores `.set`
  values, so adopting them needs an EA recompile, not just a preset. For **Monster** all 4 are real `input`s.
- [ ] **T2 — Session/hour + ATR-band filter sweep** on the post-T1 base (MasterVP has NO hour filter at all).
- [ ] **T3 — Mean-reversion activation** (kinds 2/3, OFF in both) — the one new-edge lever; own WF+MC. (user's
  flagged next-frontier, AFTER breakout solid)
- [ ] **T4 — Impulse sub-optimization** (Monster only; impulse ≈ 21% of net) + **cross-symbol coverage**
  (Monster on XAU; re-confirm MasterVP M5 XAU edge).
- [ ] **T5 — Cost realism** (add commission + slippage; current BTC commission=0) before any deploy.

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
- [~] **A3 — E1 over-fire (3.4×: 624 eng vs 183 MT5) = an ARMING/FIRING problem, NOT a gate/indicator one.**
  Re-diagnosed 2026-06-18 (corrects the prior "DI/trend_core" lead, which was a MISREAD).
  - **CONFIRMED LEVER (E1-specific, robust):** the `E1_MAX_CROSS_AGE` sweep — 80→576 fires, 20→502, 5→341,
    **1→154 ≈ MT5 183**. So almost all the excess fires happen at trigger age > 1: the engine fires LATE
    within the 80-bar window where MT5 doesn't. Engine arm-counter: ~7289× (cross 3806 + EMA200-touch 3687).
  - **DROPPED — the `trend_core`/DI-drift lead is dead (proven, do not re-chase):** the prior trace diff used
    the **E5** decision trace (`trace_dumper`/`diff_kenkem_trace.py` = "per-bar E5 trace"; cols `e5up_age`,
    `L_inage`, `L_tcore`, `L_pass` are E5-context). E5 deliberately SKIPS the trend-quality hard gate
    (`entryNum != 5`, TrendIdentifier.mqh:200), so cpp logs raw core=6 while MT5 logs `L_tcore`=0 — a KNOWN
    semantic skip, not an E1 bug (it disagrees 466k×). At the cited over-fire bar 2024-01-15 05:50 MT5's DI
    is fat & bullish on ALL 3 TFs (M1 spread **10.47**, M3 13.5, M5 7.6; adx 35.57) → `GetTrendQualityScore`
    MUST return 6, and indeed `L_tqok` (real pass/fail) AGREES on both sides. DI drift (diP_m1 |Δ|~3, real)
    never flips an E1 gate — every E1 bar's spread is far above the 1.0/3.0 thresholds. **STOP investigating
    DI / trend_core / the "hidden shift/input" for the E1 over-fire.** (DI drift logged as a side note: A3b.)
  - **ALSO already RULED OUT:** ATR (binds), conviction (0% rej in MT5 too), pip_size, B2 EMA-shift on the
    GATE (align-2 worsened 155→130). EMA200-touch arming (level-triggered, `==-1` guard) and the expiry
    reset (−1 at age>max, Entry1.mqh:105) both MATCH the EA 1:1 in `triggers.hpp`/`entries.hpp` — not the bug.
  - **TWO LIVE SUB-HYPOTHESES (test with the new E1 instrument below):** (a) **over-arming** — engine
    `emas_ready`/touch arming evaluates TRUE on more bars than the EA's `isEMAsReadyForEntry`, creating more
    armed windows; (b) **late-fire gate leniency** — on age>1 bars the engine's *E1* gates pass where MT5's
    `CheckE1EntryConditions_Internal` rejects. The MT5 "armed 00:07, never re-armed all day → engine fired
    05:50" anecdote favors (a), but is a single day.
  - **GAP to close:** MT5's true full-period E1 arm-count and fire-AGE distribution were never measured (only
    one day). Mine `[E1]` arm/expire/blocked lines from `tester.log.gz` to get both — that alone tells us
    whether the fix target is (a) arm-frequency or (b) per-bar gate leniency. **Do this before any code change.**
- [~] **A3-INSTR — E1 per-fire age + arm-bar mining (DONE 2026-06-18; resolves (a)-vs-(b) → (a)).**
  Built `KK_EMIT_AGE=1` (per-fire `AGEFIRE,ts,dir,kind,age`) + mined MT5 `tester.log.gz` (UTF-16) arm events.
  Findings: (i) over-fire is **NOT late-fire leniency (b)** — MATCHED engine E1 skew HIGH age (median 24),
  OVERFIRE skew LOW age (median 7); MT5 itself fires late (median touch-arm age 40). (ii) It IS an
  **arming/selection desync (a)** — 86 matched / 97 MISSED / 538 OVERFIRE; overfire net-losing (40% win).
  (iii) MT5 arms E1 **~78% via EMA200-TOUCH** (7987 logged, UTC+0), ~22% cross; engine UNDER-touch-arms
  (3687 vs 7987) and over-cross-arms (3806). MT5 touch-arm bars saved → `…/RUN_…/mt5_e1_touch_arms_utc.csv`.
  **NEXT:** tag the engine's touch/cross arm source per bar (consumption-aware) and bar-diff vs the MT5 file;
  prime suspect = EMA200-touch read SHIFT (`triggers.hpp:86–98` reads ema200+low/high at series-shift1; EA
  reads ema200 via `GetEMA` trap=series-shift2). Judge fixes by matched+missed+overfire+pnl, NOT count.
- [x] **A3-AGE — E1_MAX_CROSS_AGE 80→28 (user directive, both codebases).** Set in kenkem_config.hpp:193 +
  anchor.set + original EA InputParams.mqh:303. C++ effect small (E1 624→561; faster expiry re-arms more).
  Reference run is age=80 → STALE; needs fresh MT5 run at 28 to re-validate E1 parity.
- [ ] **A3b — DI drift (side issue, deprioritized).** diP_m1/diM_m1 mean|Δ|~3 vs MT5 (EMAs bit-exact, ADX
  ~exact). Harmless to E1/E2/E4 gates today (spreads clear thresholds), but track it — likely M1 bar
  HIGH/LOW (wick) differences feeding TR, or a 1-bar trace-column shift. Resolve only if a future gate
  proves DI-magnitude-sensitive; do NOT block A3 on it.
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
