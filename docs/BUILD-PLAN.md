# KenKem Quant OS — Build Plan & Progress Tracker

Executable work only — the things that get *checked off*. Standing doctrine (optimization objective,
hard gates, tick-engine-only, costs, ATR-filter) lives in `CLAUDE.md`; engine/parity traps live in memory
([[engine-port-traps]], [[kenkem-parity-traps]]); completed/rejected items live in
`docs/BUILD-PLAN-ARCHIVED.md` — read it before re-opening any lever.

Each step: build → `make -C cpp_core test` → commit → push → tick this file. Update `HANDOFF.md` last.
Legend: `[x]` done · `[~]` in progress · `[ ]` todo · 🔒 = hard gate (cannot proceed past until met).

---

## 🔓 OPEN research levers (the only MasterVP/Monster work left)

MasterVP's deployed locks stand; every exit/reversion/gate lever has been tested→rejected (see archive).
What remains genuinely open:

> ⚠️ **USER SKEPTICISM ON THE C++ ENGINE EXIT MODEL (2026-06-25) — read before trusting any sweep verdict.**
> The user is **more skeptical than ever** about the recent sweeps. The proof: the **runner-RR / trail lock**
> was wrong, and the user found it **themselves via the MT5 Strategy-Tester optimizer**, NOT the C++ engine —
> the finer-step MT5 opt revealed Trail 2.75 > 2.5 and RR~4.0, which the engine's step-1.0 view and
> directionally-unreliable exit accounting had missed (see [[engine-exit-model-untrusted-use-mt5]] — the
> engine over-credits the trailed runner). **CONSEQUENCE — any EXIT-side lever (laddered/partial TP,
> profit-lock ladder, BE/trail geometry, giveback) must be (re)validated on the MT5 optimizer, NOT the C++
> engine.** The engine is a fast RANKING proxy for ENTRY/detection only; for exits, MT5 is the judge. When an
> exit study's MT5 result disagrees with the engine, **MT5 wins** and the engine verdict is discarded.

- [ ] **H6 — FVG-anchored stop-loss** (structural SL, replaces/augments pure ATR-multiple). Current SL is a
  blind ATR multiple (`strategy.hpp`: long `sl = entry − max(sl_atr_brk·atr1, 8·pip)`). Anchor it just
  **beyond the most significant Fair Value Gap** instead — long → most significant FVG **below VAH**; short
  → FVG **above VAL**. Goal: stopped only when real structure breaks, fewer ATR-noise whipsaws. Expected to
  matter for both M3 and M5, XAU and BTC.
  - **Build:** new `cpp_core/include/kk/mastervp/fvg.hpp` — bullish FVG when `low[i] > high[i−2]`, bearish
    when `high[i] < low[i−2]`; "significant" = largest gap; constrain to value-area side, lookback window,
    no-lookahead. New params `InpUseFvgSl` (default **false** → byte-identical lock), `InpFvgLookback`,
    `InpFvgBufAtr`, `InpFvgMinGapAtr`, fallback to ATR-SL. Golden parity: OFF == current trades exactly.
  - ⚠️ **Confirm geometry with user at impl time** — "FVG below VAH (long) / above VAL (short)" needs one
    worked example to pin the exact side & which FVG edge the SL sits beyond.
  - **Validate:** A/B across all 4 cases → 6-fold WF (`wf_mastervp.py`) → MC → overfitting gate
    (`research/stats/gate.py`, record n_trials + sr_trial_std) before any lock. Port to MQL5 only after DSR-PASS.

- [ ] **H7 — BTC M3 re-sweep (never genuinely swept).** The 2026-06-22 re-sweep loaded the **BTC-M5 LOCKED
  `.set`** verbatim (`resweep_2026-06-22.py:39`) — there is no dedicated BTC-M3 config, so "no edge" is M5
  params on M3 bars. Sweep, in priority: (1) master VP node length (`InpMasterMult`/master bars), (2) RR
  (`InpRunnerRr`, `InpTp1R`), (3) SL ATR (`InpSlAtrBrk`), break buffer/ceiling, reversion on/off. Combine
  with H6 once built (user flags FVG-SL as potentially critical for M3).
  - **Validate:** dedicated BTC-M3 train/OOS split first (cheap rank), then 6-fold WF + MC + gate. BTC/Exness
    feed runs optimistic → **MT5-confirm before trusting** any BTC lock ([[mastervp-t3-reversion-lock]]).
    Ship `kkmastervp_btc_m3_LOCKED.set` + EA preset only on DSR-PASS.

- [ ] **H8 — Drop session windows, trade 24h-minus-blocked (BTC-first).** Hypothesis (user): ignore the
  Asia/London/NY session gating entirely and let entries fire **any hour except `InpBlockedHoursStr`**. Rationale:
  BTCUSD has no session character and runs 24/7, so the session windows may be needlessly throwing away trades.
  - **Build:** mostly a **config ablation** (no code expected) — set session windows to full-day (24h) while
    keeping the blocked-hours list, on a candidate `.set`. ⚠️ **Impl check first:** confirm whether the
    engine/EA currently excludes **weekends** and whether a `weekend-enable` toggle exists; "BTC 24/7" only
    holds if weekend bars are actually tradable in both engine and EA (add a minimal flag if not).
  - **Blocked hours are ALREADY per-symbol** — `InpBlockedHoursStr` is a per-EA-instance input (each chart =
    one symbol = its own `.set`), so there is no shared/global list. The validated `4,16,17` UTC hours are
    **XAU-specific** microstructure (Asian-lunch lull + late-London chop on gold) and must **NOT** be inherited
    by BTC. H8 must **derive BTC's own blocked hours empirically** (per-hour ATR/PF decomp via `hour_atr_decomp.py`;
    candidate causes: low-liquidity windows, the Exness daily break ~UTC 21–22) — independent of gold's.
  - ⚠️ **Cost realism is load-bearing here** — weekend BTC on the Exness feed has wider spreads / thinner
    liquidity / gaps ([[btcusd-data-quirks]]). Test with **realistic weekend spread+commission** (pairs with
    **T5**), else the 24/7 result reads optimistic. An uncosted 24/7 win is not a real win.
  - **Expect XAU to REJECT (control, not target).** XAU's session/hour structure is a *measured* edge — T2
    hour-block lock improved pooled PF ([[mastervp-m5-t2-hour-block-lock]]) and the UTC-21 study showed adding
    blocks helped/widening hurt. Run XAU as a control; the real candidate is BTC (M5 + M3).
  - **Validate:** per-symbol/TF A/B (session-gated vs 24h-minus-blocked) → **per-fold** 6-fold WF
    (decompose, do NOT pool — pooled gains hid recent harm in the T1 gate-sweep [[mastervp-m5-gate-sweep-lock]])
    → MC → overfitting gate. BTC locks MT5-confirm before trust ([[mastervp-t3-reversion-lock]]). Combine with
    **H7** (BTC-M3 re-sweep) — hours are part of that config space.

- [~] **H9 — Re-validate the EXIT cluster on the MT5 optimizer (laddered/partial TP first).** Directly from the
  > **PREPPED 2026-06-26 (autopilot):** internal sweep EA `KK-MasterVP-Debug.mq5` ships (KK_IN macro exposes
  > ALL params; curated EA byte-identical, compiles 0/0). 3 optimizer `.set` ready in `mql5/experts/KK-MasterVP/`
  > (A=partial-TP InpTp1ClosePct×InpTp1R; B=BeBuf×Trail×RR plateau; C=prog-trail ladder, Debug-only) + plan
  > `research/mastervp_parity/H9_MT5_OPTIMIZER_PLAN.md`. ▶ user runs them (A→C→B). True discrete multi-rung TP
  > ladder still needs a default-OFF `pm_ladder` code build (greenlight → Grid D).
  skepticism note above: the prior engine-side rejections of partial/laddered TP ([[mastervp-profit-lock-ladder]],
  TP1-bank, conviction-protect — all "REJECTED" in the archive) were judged by the **C++ exit model the runner-RR
  miss just proved unreliable**. Re-open them, but this time sweep on the **MT5 Strategy-Tester optimizer**, not
  the engine.
  - **Priority:** (1) **laddered TP** — bank fractions at a sequence of R/VP levels and let the rest trail
    (the user's specific call-out); (2) `InpTp1ClosePct` partial-bank revisit; (3) profit-lock ladder
    (`InpPm*` — `ProfitManager.mqh` is built + engine-mirrored but only ever MT5-tested as Ladder on BTC); (4)
    BE buffer × trail interactions around the new RR4.0/Trail2.75 lock.
  - **Method:** these are all **existing EA inputs / built default-OFF infra → `.set`-only, zero parity risk,
    no recompile.** Build the candidate `.set` grids, run MT5 `Every tick based on real ticks` optimizer over
    XAU M5 2025.06.01–2026.05.29 dep 10k, rank by **PF/robustness not peak net** (the RR3.2 trap). Confirm any
    winner beats the **+87,836 / PF 1.413** lock on every quality axis, then overfitting-gate it before locking.
  - ⚠️ Engine WF may still be run as a CHEAP pre-filter to prune the grid, but **its sign is not trusted on
    exits** — no exit lever is locked on an engine number alone. MT5 optimizer result is the verdict.

- [ ] **T4 — Monster impulse sub-optimization** (impulse ≈ 21% of net) + **cross-symbol coverage** (Monster
  on XAU; re-confirm MasterVP M5 XAU edge).

- [ ] **T5 — Cost realism** (add commission + slippage; current BTC commission=0) before any deploy.

- [ ] **C1 — Dead-code cleanup: prune research features never toggled on in the last ~4 locked versions.**
  Years of exploratory research left default-OFF features wired into the engine + EAs that **no shipped lock has
  ever enabled** — they add surface area, slow comprehension, and (worse) are untrustworthy now that the engine
  exit model is suspect. Audit what the last ~4 locks actually use, then remove the rest.
  - **Candidates (verify each is OFF in ALL recent locked `.set` before removing):** node-engine gate
    (`InpNodeGateEnabled`/`InpBrkRequireFlow`/`InpSfpFlowMin`/`InpUsePriorBarVP`), impulse-thrust path
    (`InpEnableImpulse` + all `InpImpulse*`/`InpTfNet*`/`NetVolume.mqh` — the retired Monster delta), extreme
    reversion (`InpEnableExtremeReversion` + `InpXRev*`/`ExtremeReversion.mqh`), base reversion if still unused
    (`InpEnableReversion`/`InpRev*`/`InpRetestAtr`/`InpBodyPctMin`), per-entry-type trail overrides
    (`InpTrailBrk/Rev/Imp/XRev` if always -1), MTF/momentum quality gates (`InpUseMtfAgree`/`InpUseMomVeto`),
    FVG-SL (`fvg_sl.hpp`, already WF-rejected, never ported), Kaufman-ER (KenKem `E1_ER_*`, engine-only),
    and any other default-OFF lab feature.
  - ⚠️ **Method = safety-net deletion:** the C++ side is the source of truth and is **fully tick-tested** —
    delete a feature, `make -C cpp_core test` must stay green AND the golden-parity / locked-`.set` runs must
    stay **byte-identical** (a diff = the feature wasn't truly dead). Mirror the removal in the EA, recompile
    0/0. Do it **one feature per commit** so any parity break is unambiguously attributable. Keep the research
    write-ups in `research/` + memory as history (the lesson, not the code). **Confirm scope with the user
    before deleting reversion** (it's the one with a partial MT5 A/B history) — the rest are clean kills.

---

## 🛰️ DEPLOYMENT & OPS INFRASTRUCTURE (cross-EA, Layer 4 — live MT5 only)

These are **not** strategy-research levers. They live entirely in **Layer 4 (MQL5)** — they touch `AccountInfo*`,
`GlobalVariable*`, `WebRequest`, `FileWrite`, broker equity — none of which exist in the C++ engine. They are
**out of scope for parity/backtest** (the tick engine models one isolated equity stream per run; account-pooling,
notifications and CSV cadence have no engine analog). Build + verify on a **demo account with multiple charts**,
not via `make test`. The *pure math* (day-anchor / floor / breach) should still be factored into a small
header-only helper so it can be unit-tested headlessly.

**Decided context (2026-06-25):** one MT5 terminal per prop account → cross-EA state via **terminal
GlobalVariables**; defaults tuned **generic/conservative (equity-based)** with per-firm settings documented;
trade CSV is **append-immediately on close** (not hourly-batched).

- [x] **D1 — Account Risk Guardian** — DONE 2026-06-25 (`KK-Common/AccountGuardian.mqh`, wired into KK-MasterVP,
  compiles 0/0). Cross-EA via terminal GlobalVariables keyed by login; pure breach/anchor math in unit-testable
  free functions; server-time day boundary; equity-based flatten-before-the-line; deal-history cold-start anchor.
  Inputs `InpGuard*`. Simplified vs this spec (no Equity/Balance-at-reset split, no `InpDayResetHourServer`, no
  `InpDailyLimitBase`) — refine per-firm if the demo needs it. Full record + ▶ user demo-validation step in
  `BUILD-PLAN-ARCHIVED.md`.
- [x] **D2 — Per-EA trade CSV** — DONE 2026-06-25 (`KK-Common/TradeLogger.mqh`). Append-on-close, FileFlush/row,
  live-only, OnDeinit close. Input `InpLiveTradeCsv`. Archived.
- [x] **D3 — Notifications (Discord/Telegram/Email)** — DONE 2026-06-25 (`KK-Common/Notifier.mqh`, standalone,
  ASCII-only). Inputs `InpNotifyChannel{0..7}/InpNotifyMode/InpDiscord*/InpTelegram*`. Plus drag-drop validator
  `KK-Common-Tests/TestDeployOps.mq5` + guide §5 update. Archived.

- [ ] **D4 — Trial-expiry deadline on account-locked marketplace builds.** Every per-account MARKET edition
  ([[ea-marketplace-and-account-builds]] — the hidden `ALLOWED_ACCOUNT_ID`/`ALLOWED_ACCOUNT_SERVER` bake)
  also gets a **free-trial deadline, default 15 days from build time**. After it passes, the EA stops trading
  and shows the alert: **`Free Trial Access Expired. Please purchase the bot from https://kenkem.biz`**.
  - **Mechanism:** the per-account release script bakes a **hidden compile-time constant** (NOT a user input —
    same rationale as the account lock; an input would let the user just extend it), e.g.
    `datetime TRIAL_EXPIRY_TS = <build_time + 15 days>;` next to `ALLOWED_ACCOUNT_ID`. Empty/0 sentinel = **no
    deadline** (the normal, non-trial paid build). The 15-day window is a build-script parameter so a longer/
    shorter trial can be issued per customer without touching code.
  - **Check:** in `OnInit` and once per new bar, `if(TRIAL_EXPIRY_TS>0 && TimeCurrent() > TRIAL_EXPIRY_TS)` →
    fire `Alert(...)` once (de-dupe so it doesn't spam every tick) + **stop opening new trades**. Use
    **`TimeCurrent()` (broker server time)**, not `TimeLocal()` — the broker clock is far harder to spoof by
    rolling back the PC clock. Pairs naturally with the D3 notifier (also DM the expiry once).
  - ⚠️ **Confirm with user at impl time:** behaviour for **already-open positions** at expiry — recommended
    **let existing trades manage out to their own SL/TP, only block new entries** (flattening someone's live
    position on a trial boundary is hostile and can realise a loss); the alert + new-entry block is the lock.
    Also confirm whether expiry should also hard-disable on the *next* `OnInit` (so a restart after expiry won't
    trade at all).
  - **Live-only / safety:** skip the whole check under `MQL_TESTER|MQL_OPTIMIZATION` (don't let a trial deadline
    break the user's own backtests); the deadline only governs the live marketplace build.
