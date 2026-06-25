# KenKem Quant OS — Build Plan ARCHIVE (completed / closed items)

Items moved out of `BUILD-PLAN.md` once DONE or definitively REJECTED. Kept for the record so
levers don't get re-chased. Newest first.

---

## 🛰️ DEPLOYMENT & OPS — D1/D2/D3 BUILT + compile 0/0 (2026-06-25) — awaiting user demo validation

Cross-EA Layer-4 (live MT5) infra. Pure additions — all default OFF/empty so KK-MasterVP stays
**byte-identical to the validated lock** (compiles 0/0; engine + `make test` untouched, no C++ analog).
Shared headers in `mql5/experts/KK-Common/`, wired into KK-MasterVP `Engine.mqh`/`Inputs.mqh`.

- **D1 — `AccountGuardian.mqh`** (cross-EA prop guardian). Pure math = free functions `KKG_TriggerLoss/
  KKG_DailyBreached/KKG_OverallBreached/KKG_DayKey` (no MT5 API → unit-testable). Stateful `KKAccountGuardian`:
  shared anchors in terminal **GlobalVariables keyed by login** (`KKG.<login>.{dayKey,dayStart,peak,staticBal,
  latch}`), atomic day-roll via `GlobalVariableSetOnCondition`, `GlobalVariablesFlush`. Equity-based, day
  boundary = **broker server time** (`TimeTradeServer`), flatten-before-the-line via buffer, mid-day cold-start
  anchor reconstructed from deal history (`HistorySelect` + Σ deals since server-midnight). Inputs:
  `InpGuardEnable/DailyLossPct(4)/OverallDDPct(8)/BufferPct(0.5)/DDAnchor(0=peak,1=static)/ManualDayAnchor/
  Flatten`. Wired: OnTick `Update()`→flatten+alert-once; OnNewBar entry gate `Halted()`→block new.
  - **Simplified vs the full plan spec:** implemented the core; did NOT split EquityAtReset-vs-BalanceAtReset
    anchor modes, `InpDayResetHourServer` (fixed at server-midnight = the default-0 case), or `InpDailyLimitBase`
    {InitialDeposit vs StartOfDay}. Refine knobs per-firm later if the demo shows it's needed.
- **D2 — `TradeLogger.mqh`** (live per-EA CSV). `KKTradeLogger` appends one row the instant a trade closes
  (`FileFlush` per row), `KKTrades_MasterVP_<symbol>_<login>.csv` in MQL5/Files, header once, `OnDeinit`
  flush/close, **live-only** (skips `MQL_TESTER|MQL_OPTIMIZATION`). Input `InpLiveTradeCsv`. Wired in
  `OnTradeTransaction` (DEAL_ENTRY_OUT), kept separate from the tester-only `InpExportParity`.
- **D3 — `Notifier.mqh`** (Discord/Telegram/Email). Standalone (NOT a copy of KenKem's 5 Trade-coupled files);
  reuses the proven `WebRequest` shapes, ASCII-only (NON_LATIN-safe). `KKNotifier` routes per
  `InpNotifyChannel` {0..7} + `InpNotifyMode` {Full, Simplified-prop}; inputs `InpDiscordWebhookUrl/
  TelegramBotToken/TelegramChatId`. Sends startup + per-trade open/close + guardian-HALT alert; tester-guarded.
- **Test EA — `KK-Common-Tests/TestDeployOps.mq5`** (drag-and-drop, like the KenKem Discord validator). Runs
  the D1 math asserts (PASS/FAIL to Experts log), sends a REAL test message to each configured channel,
  writes a sample CSV row, then `ExpertRemove()`. Visible in MT5 via the `dq` symlink:
  `Experts\dq\KK-Common-Tests\TestDeployOps.ex5`. Both EAs compile 0/0.
- **Guide:** `docs/guides/KK-MasterVP-EA-User-Guide.md` §5 gained Account-Guardian / Live-CSV / Notifications
  subsections + the validator-EA step (English, plain-language).
- **▶ User validation (live, can't be done headlessly):** drag `TestDeployOps` on a demo chart, paste
  webhook/token, confirm messages arrive + PASS summary; then demo-run KK-MasterVP with `InpGuardEnable=true`
  on 2 charts (ideally + KenKem) to confirm shared anchor/peak + joint flatten. THEN release/bump is unblocked.

---

## MasterVP profitability thrust (2026-06-20 → 2026-06-23) — all levers CLOSED

Both EAs were locked & shipped before this thrust (Monster BTC M3 anti-chase PF 1.20; MasterVP XAU M5
PF 1.33). Every research lever below was tested; the breakout trend-runner is the edge and the deployed
locks stand. **No open MasterVP research action remains** — VP-length, FVG-SL(¹), TP1-partial, move-SL,
conviction-protect, flow-exit, and local-reversion all tested→rejected. (¹ FVG-SL re-opened as H6 below.)

### USER ASSUMPTION — reversion fade LOCAL vs MASTER VP — TESTED 2026-06-23 (assumption RIGHT, REJECT for lock)
- **User's assumption:** mean-reversion only works fading a **LOCAL VP node** edge, not the master VP.
- **Verdict: directionally CORRECT but reversion still loses → keep OFF.** Study:
  `research/mastervp_parity/REVERSION_LOCAL_VP_STUDY_2026-06-23.md`; memory [[reversion-local-vp-assumption]].
- BUILT default-OFF switches `InpRevEntryLocal`/`InpRevTpLocal` (`config.hpp`+`strategy.hpp`; golden parity
  green, base byte-identical). XAU M3 6-fold WF: local-fade beats master-fade on every axis (net
  $6,998→$9,280, dd 31.6→22.4%, folds+ 4→5) BUT reversion is negative-expectancy in all 5 forms (revNet
  −431..−1,189) and baseline breakout-only beats them all on net ($11,642) AND PF (1.108). Prior
  "rev @ mPOC trims DD 17.5→13.5%" master candidate was survivorship. No gate run (loses to baseline).

### T1 — Dormant quality-gate sweep — TESTED → REVERTED (2026-06-20, commit ded3e81)
- **MasterVP XAU M5:** gates `BrkVetoSfp`+`MomVeto`+`MtfAgree` improved POOLED 6-fold PF 1.243→1.274 + MC
  DD 27.7→23.1% BUT per-fold + MT5 decomposition showed the gain is all from 2025; they HURT the recent 4mo
  (F5 −28%, F6 −43%). User chose baseline. MT5 parity CONFIRMED faithful (424/489 matched).
- **Monster BTC M3:** NEGATIVE — no gate beats baseline, no change.
- 🔑 **LESSON:** decompose per-fold (recent OOS) before locking a filter. ⚠️ for the KK-MasterVP EA
  `InpNodeGateEnabled` & `InpBrkRequireFlow` are compile-constants (`non_input_keys()` in config.hpp) —
  adopting them needs an EA recompile, not just a preset. For Monster all 4 are real `input`s.

### T2 — Session/hour + ATR-band filter sweep — WIN, LOCKED (2026-06-20)
- **MasterVP XAU M5: LOCKED `InpBlockedHoursStr=2,3,14`** (later migrated to true-UTC `4,16,17`; see HANDOFF
  UTC note). Block UTC04 Asian-lunch lull + UTC16,17 late-London chop. Pooled PF 1.243→1.296, net +16.6%,
  maxDD 12.5→10.0%, worst-fold 1.102→1.196; 5/6 folds improve, both recent folds rise. MC: P(profit) 99.9%,
  PF5th 1.158. REJECTED: news hr0, Asia hr10/hr18, ATR upper-band (curve-fit). Diag `hour_atr_decomp.py`.
- **Monster BTC M3: NO CHANGE** — the better-pooled candidate (`8,9,10,11,16`) is a T1 trap.

### T3 — Mean-reversion activation — 2 WINS / 2 REJECTS (2026-06-20)
- Harness `wf_t3.py` (enable→retest→body→sl, 6-fold WF + MC). Reversion fires only in the balance regime.
- **BTC M5 (MasterVP): WIN, LOCKED** `EnableReversion=true, Retest 0.1, Body 0.4, SlRev 1.2`. Pooled PF
  1.217→1.308, net +62%, maxDD 16.8→7.7%, 6/6 folds. ⚠️ MT5 later DISCONFIRMED the BTC engine rev win as
  fictional (revNet −76); reversion OFF on BTC everywhere (memory [[mastervp-t3-reversion-lock]]).
- **XAU M5 (MasterVP): WIN, LOCKED** `EnableReversion=true` at default rev params: PF 1.335→1.344,
  maxDD 9.2→7.8%, 6/6 folds. MC: P(profit) 100%, PF5th 1.198.
- **XAU M3: REJECT** (revNet ~0, maxDD deepens). **Monster BTC M3: REJECT** (folds 6/6→4/6).

### H8 — Volume-flow CONDITIONED exit (bank only when delta reverses) — TESTED → REJECTED (2026-06-23)
- **Hypothesis:** a *conditioned* exit that banks only when Profiler net delta shows the move reversing might
  flip the sign where unconditional locks failed. Genuine gap (everything else was price/R-mechanical).
- **Method (unbiased):** `backtester --flow-path-out` dumps per-bar {unreal_r, mfe_r, net_flow, node_net} +
  true intrabar `exit_r`; `flow_separation_2026-06-23.py` measures in pure R-geometry. Reproduces the 46.8%
  giveback baseline AND the MT5 Ladder −27% (geometry == live).
- **Result: REJECT — structural, not tuning.** Both signal forms (against-flow + divergence), every tuning:
  runner-cost > round-trip-rescue. Pullbacks and reversals look the same in flow. The round-trip (47% of ≥1R
  winners) is opportunity cost, NOT capital risk (BE arm @0.8R protects → they exit ~0R). Write-up:
  `research/mastervp_parity/FLOW_EXIT_SEPARATION_STUDY_2026-06-23.md`; memory [[mastervp-flow-exit-rejected]].
  **Do not re-chase a single-pass flow exit.** BTC M5 Ladder remains the one place protection helps (MT5
  +51%, tail fictional).

---

## KenKem Phase A — closed diagnostic sub-steps (forensic record; do not re-chase)

The open Phase A items stay in `BUILD-PLAN.md`. These sub-steps are settled.

### A3-AGE — E1_MAX_CROSS_AGE 80→28 (user directive, both codebases) — DONE
Set in kenkem_config.hpp:193 + anchor.set + original EA InputParams.mqh:303. C++ effect small (E1 624→561).
Reference run was age=80 → became STALE; needs a fresh MT5 run at 28 to re-validate E1 parity.

### A3-INSTR — E1 per-fire age + arm-bar mining — DONE 2026-06-18 (resolved (a)-vs-(b) → (a))
Built `KK_EMIT_AGE=1` + mined MT5 `tester.log.gz` arm events. Findings: (i) over-fire is NOT late-fire
leniency — MATCHED E1 skews HIGH age (median 24), OVERFIRE skews LOW age (median 7). (ii) It IS an
arming/selection desync — 86 matched / 97 missed / 538 overfire; overfire net-losing (40% win). (iii) MT5
arms E1 ~78% via EMA200-TOUCH (7987 logged) vs ~22% cross; engine UNDER-touch-arms (3687) and over-cross-arms
(3806). MT5 touch-arm bars saved → `…/RUN_…/mt5_e1_touch_arms_utc.csv`. Prime suspect carried into open A3 =
EMA200-touch read SHIFT.

### A3 dead-ends — PROVEN, do NOT re-investigate
- **`trend_core`/DI-drift lead is dead:** the trace diff used the E5 decision trace; E5 deliberately SKIPS
  the trend-quality hard gate (`entryNum != 5`), so cpp logs raw core=6 while MT5 logs `L_tcore`=0 — a known
  semantic skip, not an E1 bug. At the cited over-fire bar DI is fat & bullish on all 3 TFs → score MUST be 6
  and `L_tqok` AGREES both sides. **STOP investigating DI / trend_core / "hidden shift" for the E1 over-fire.**
- **Also ruled out:** ATR (binds), conviction (0% rej in MT5 too), pip_size, B2 EMA-shift on the GATE
  (align-2 worsened 155→130). EMA200-touch arming and the expiry reset both MATCH the EA 1:1.
