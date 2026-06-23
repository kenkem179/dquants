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

## ✅ USER ASSUMPTION — reversion fade LOCAL vs MASTER VP — TESTED 2026-06-23 (assumption RIGHT, but REJECT for lock)

**User's assumption:** Mean-Reversion only works well fading a **LOCAL VP node** edge, NOT the master VP.
**Verdict: directionally CORRECT but reversion still loses → keep OFF.** Full study:
`research/mastervp_parity/REVERSION_LOCAL_VP_STUDY_2026-06-23.md`.

- **BUILT (default-OFF, base byte-identical):** separable switches `rev_entry_local` / `rev_tp_local`
  (`InpRevEntryLocal`/`InpRevTpLocal`) in `config.hpp` + `strategy.hpp` — local edge trigger + local-POC
  magnet. `make test` 37/37 incl. golden parity; baseline WF row `rev=0` = the lock.
- **XAU M3 6-fold WF (reversion's only home):** local-fade beats master-fade on EVERY axis (net
  $6,998→$9,280, dd 31.6→**22.4%**, folds+ 4→5, least-negative revNet) → **assumption confirmed.** BUT the
  reversion sub-book is negative-expectancy in all 5 forms (revNet −431 to −1,189), and baseline
  (breakout-only) beats them all on net ($11,642) AND pooled PF (1.108). The prior "rev @ mPOC trims DD
  17.5→13.5%" master-POC candidate was survivorship — under WF the master form is net-HARMFUL (dd 31.6%).
- **Decision:** keep reversion OFF on all markets; switches ship as tested default-OFF infra; no gate run
  (loses to baseline → cannot be a lock). **This closes the last open MasterVP research lever** — VP-length,
  FVG-SL, TP1-partial, move-SL, conviction-protect, flow-exit, and now local-reversion all tested→rejected.

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
- [x] **T2 — Session/hour + ATR-band filter sweep (DONE 2026-06-20)** — **MasterVP XAU M5: WIN, LOCKED
  `InpBlockedHoursStr=2,3,14`** (block UTC04 Asian-lunch lull + UTC16,17 late-London chop). Pooled PF
  1.243→**1.296**, net +16.6%, maxDD 12.5→**10.0%**, worst-fold 1.102→**1.196**; 5/6 folds improve, BOTH
  recent folds rise → passes recent-regime check. MC: P(profit)99.9%, PF5th 1.158. REJECTED: news hr0
  (net-harmful), Asia hr10/hr18 (over-block), ATR upper-band (non-monotonic curve-fit). Ships via `.set`
  (real EA input, same UTC+10 frame), no recompile. ⏳ needs 1 MT5 confirmation run. **Monster BTC M3:
  NO CHANGE** — hours already cluster-optimized in lock; the one better-pooled candidate (`8,9,10,11,16`)
  is another T1 trap (helps 2025, hurts recent F5/F6). New diag `hour_atr_decomp.py`.
- [x] **T3 — Mean-reversion activation (DONE 2026-06-20)** — generalized 4-config WF harness `wf_t3.py`
  (enable→retest→body→sl, 6-fold WF + MC, per-fold recent-regime discipline). Reversion fires only in the
  balance (non-trend) regime = complement of breakout → additive. **2 WINS / 2 REJECTS:**
  - **BTC M5 (KK-MasterVP): WIN, LOCKED** `EnableReversion=true, Retest 0.1, Body 0.6→0.4, SlRev 1.5→1.2`.
    Pooled PF 1.217→**1.308**, net **+62%**, maxDD 16.8→**7.7%**, worst-fold 0.904→**1.056**, folds 5/6→**6/6**;
    revNet +5,158 (strong standalone). MC: P(profit) 98.8%, PF5th 1.101, 8/8 folds. rr_rev INERT; sl flat plateau.
  - **XAU M5 (KK-MasterVP): WIN, LOCKED** `EnableReversion=true` at default rev params (on TP1=0 base):
    PF 1.335→**1.344**, maxDD 9.2→**7.8%**, 6/6 folds, worst-fold 1.219→**1.223**. MC: P(profit) 100%, PF5th 1.198.
  - **XAU M3: REJECT** (revNet ~0, maxDD 14.2→15.9%, worst-fold deepens). **Monster BTC M3: REJECT** (folds 6/6→4/6).
  Both wins ship via `.set` (real EA inputs, no recompile); presets redeployed. ⏳ needs MT5 re-run.
- [ ] **T4 — Impulse sub-optimization** (Monster only; impulse ≈ 21% of net) + **cross-symbol coverage**
  (Monster on XAU; re-confirm MasterVP M5 XAU edge).
- [ ] **T5 — Cost realism** (add commission + slippage; current BTC commission=0) before any deploy.

### 🆕 User-raised hypotheses (2026-06-22) — to implement & validate next

- [ ] **H6 — FVG-anchored stop-loss (structural SL, replaces/augments pure ATR-multiple).**
  **Hypothesis (user):** the current SL is a blind ATR multiple (`strategy.hpp`: long `sl = entry −
  max(sl_atr_brk·atr1, 8·pip)`, short symmetric; reversion only clamps to local VP hi/lo). It ignores
  market structure. Anchor the SL just **beyond the most significant Fair Value Gap (FVG / 3-bar price
  imbalance)** instead — for a **LONG**, the most significant FVG **below VAH**; for a **SHORT**, the
  most significant FVG **above VAL**. Rationale: you only get stopped when real structure breaks, not on
  ATR noise → fewer SL-LOSS whipsaws, better risk geometry. Expected to matter for **both M3 and M5,
  XAU and BTC**.
  **Build:**
  1. Add FVG detection to the engine (new `cpp_core/include/kk/mastervp/fvg.hpp`): bullish FVG when
     `low[i] > high[i−2]` (gap = `low[i] − high[i−2]`), bearish when `high[i] < low[i−2]`. "Most
     significant" = largest gap (candidate: volume/tick-weighted). Constrain to the value-area side
     (long→FVGs below VAH; short→FVGs above VAL), within a lookback window. No-lookahead: only bars ≤ t.
  2. New params: `InpUseFvgSl` (default **false** → byte-identical to current lock), `InpFvgLookback`,
     `InpFvgBufAtr` (buffer beyond the FVG edge), `InpFvgMinGapAtr` (significance floor), fallback to
     ATR-SL when no qualifying FVG. Golden parity test: OFF == current trades exactly.
  3. ⚠️ **Confirm geometry with user at impl time** — the "FVG below VAH (long) / above VAL (short)"
     wording needs one concrete worked example to pin the exact side & which FVG edge the SL sits beyond.
  **Validate:** A/B vs ATR-SL across all 4 cases (XAU/BTC × M3/M5) → 6-fold WF (`wf_mastervp.py`) →
  Monte-Carlo → overfitting gate (`research/stats/gate.py`, record n_trials + sr_trial_std) before any
  lock. Port to MQL5 (`Strategy.mqh` SL block + new FVG helper) only after a DSR-PASS.

- [ ] **H7 — BTC M3 was NEVER genuinely swept → re-open it (user disputes "no edge").**
  **Finding that backs the user:** the 2026-06-22 re-sweep's BTC-M3 case loaded the **BTC-M5 LOCKED
  `.set`** verbatim (`resweep_2026-06-22.py:39 base="…btc_m5_LOCKED.set"`) — there is **no dedicated
  BTC-M3 config**. So "no edge / OOS collapses" is *M5 params on M3 bars*, not an optimized M3 verdict.
  **Hypothesis (user):** a proper structural sweep makes BTC M3 viable. Sweep, in priority order:
  (1) **master VP node length** (`InpMasterMult` / master bars — the dominant lever on every other
  case), (2) **RR** (`InpRunnerRr`, `InpTp1R`), (3) SL ATR (`InpSlAtrBrk`), break buffer/ceiling
  (`InpBreakBufAtr`, `InpBreakMaxAtr`), reversion on/off. Combine with **H6 (FVG-SL)** once built —
  the user flags FVG-SL as potentially critical for M3 specifically.
  **Validate:** dedicated BTC-M3 train/OOS split first (cheap rank), then 6-fold WF + MC + gate. Lock
  only on DSR-PASS; remember BTC/Exness feed runs optimistic → **MT5-confirm before trusting** any BTC
  lock (per [[mastervp-t3-reversion-lock]]). Ship `kkmastervp_btc_m3_LOCKED.set` + EA preset if it clears.

- [x] **H8 — Volume-flow CONDITIONED exit (bank only when delta reverses) → TESTED → REJECTED (2026-06-23).**
  **Hypothesis (user):** the unconditional profit-locks (Ladder/Floor/trail/partial) all lost in MT5
  because they tax every winner; a *conditioned* exit that banks only when the Profiler's net delta
  (`tickCount×(c−o)/(h−l)`) shows the move reversing is a different category and might flip the sign.
  **This was the genuine GAP** — every other exit mechanism in the plan is price/R-mechanical and
  unconditional; nothing used information to condition the bank. (The mechanism partly existed already:
  engine `enable_net_flip_exit` + `enable_conviction_protect`, WF-rejected on net P&L — the biased metric.)
  **Method (Step 0, unbiased):** new `backtester --flow-path-out` dumps per-bar {unreal_r, mfe_r, net_flow,
  node_net} + true intrabar `exit_r`; `flow_separation_2026-06-23.py` measures, in pure R-geometry (no
  net-P&L bias), whether a flip/divergence exit banks more R than it sacrifices, split round-trippers vs
  runners. Validity: reproduces the 46.8% giveback baseline AND the MT5 Ladder −27% (geometry == live).
  **Result: REJECT — structural, not tuning.** Both signal forms (against-flow + divergence), every
  tuning: runner-cost > round-trip-rescue. Continuation pullbacks and reversals look the same in flow, so
  any threshold catching round-trippers also cuts runners 2–3× harder. The round-trip (47% of ≥1R winners)
  is opportunity cost, NOT capital risk (BE arm @0.8R already protects → they exit ~0R, not −1R). Full
  write-up: `research/mastervp_parity/FLOW_EXIT_SEPARATION_STUDY_2026-06-23.md`. **Do not re-chase a
  single-pass flow exit.** BTC M5 Ladder remains the one place protection helps (MT5 +51%, tail fictional).

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
