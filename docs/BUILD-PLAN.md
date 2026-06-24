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

- [ ] **T4 — Monster impulse sub-optimization** (impulse ≈ 21% of net) + **cross-symbol coverage** (Monster
  on XAU; re-confirm MasterVP M5 XAU edge).

- [ ] **T5 — Cost realism** (add commission + slippage; current BTC commission=0) before any deploy.

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

- [ ] **D1 — Account Risk Guardian (broker-agnostic, cross-EA, shared via GlobalVariables).**
  - **The insight that reframes this:** `AccountInfoDouble(ACCOUNT_BALANCE|ACCOUNT_EQUITY)` is **already
    account-wide** — every EA on the account reads the *same* live balance/equity instantly. So the live numbers
    need no sharing. What is NOT shared and what each EA would otherwise recompute (and disagree on) across
    restarts is the **derived anchors**: *start-of-day equity/balance* (daily-DD reference) and *running peak*
    (max-DD reference). **That** is the gap.
  - **Mechanism:** one shared `AccountGuardian.mqh` (put in `KK-Common`, included by every EA). State held in
    **terminal GlobalVariables keyed by account login**, e.g. `KKACC.<login>.dayStartEq`, `.dayStartBal`,
    `.dayKey`, `.peakEq`, `.peakBal`. First EA to cross a new day **atomically claims** the anchor via
    `GlobalVariableSetOnCondition` (compare-and-set → no multi-EA race); the rest read it. `GlobalVariablesFlush()`
    so anchors survive a crash/restart. (Multi-terminal-per-account is out of scope now → note FILE_COMMON+lock
    as the future fallback.)
  - **Mid-day cold-start anchor reconstruction (no API gives "balance at reset" directly).** When the *first*
    EA of the day launches after the broker already reset (and manual trades happened since), reconstruct from
    deal history: `balance_at_reset = ACCOUNT_BALANCE − Σ(DEAL_PROFIT+DEAL_SWAP+DEAL_COMMISSION)` over every
    deal with `DEAL_TIME ≥ reset_time` (`HistorySelect(reset_time, TimeCurrent())`). Exact for the balance
    anchor (FTMO). For the **equity** anchor, `equity_at_reset = balance_at_reset + floating_at_reset` —
    floating is 0 unless a position spans the boundary (`POSITION_TIME < reset_time`); common case is flat →
    `equity_at_reset == balance_at_reset`. Spanning + exactness needed → `InpManualDayStartAnchor` override
    (paste the firm-dashboard figure once). This path runs **only** on the day's first cold start — otherwise
    the anchor is already in the shared GlobalVariable and is just read. Seed the max-DD peak conservatively on
    cold start: `max(equity, balance, initial)`, then ratchet live.
  - **Day boundary = BROKER SERVER TIME (`TimeCurrent`), not UTC.** Prop firms reset daily DD on *their* server
    clock, and the MT5 terminal runs on that same broker server, so server time auto-tracks the firm's DST
    (FTMO 00:00 CE(S)T = GMT+1/+2; FundedNext 00:00 = GMT+2/+3). **This is deliberately separate from the
    strategy's UTC session/blocked-hour logic** ([[that recent UTC migration]] stays UTC; the Guardian's reset
    is server-time). Knob: `InpDayResetHourServer` (default 0).
  - **Equity-based, intraday.** Daily DD must include floating P/L + swaps + commission (both firms measure on
    equity). So the Guardian checks `equity` every tick and **flattens + blocks new entries at a safety buffer
    BEFORE the line** (closing-order slippage eats the rest). Knob `InpDailyStopBufferPct` (e.g. flatten at 85%
    of the limit).
  - **Configurable knobs (inputs), conservative/generic defaults:**
    `InpDailyLimitPct` (5.0), `InpDailyAnchor` {EquityAtReset *(default, strict — FundedNext)*, BalanceAtReset
    *(FTMO)*}, `InpDailyLimitBase` {InitialDeposit *(both firms size the % off initial)*, StartOfDay},
    `InpMaxDDPct` (10.0), `InpMaxDDMode` {StaticFromInitial *(FTMO)*, TrailingFromPeak, TrailingPeakEOD
    *(FundedNext trailing)*}, `InpDailyStopBufferPct`, `InpDayResetHourServer`, and an
    `InpAccountGuardEnabled` master switch (default ON for prop, can be OFF for personal accounts).
  - **Per-firm doc:** add an "FTMO vs FundedNext exact settings" table to
    `docs/guides/KK-MasterVP-EA-User-Guide.md` (and KenKem guide) so the user flips knobs per account, not code.
  - **Validate:** factor the floor/breach math into a testable header → unit test it headlessly; then demo-run
    **2+ EAs on one account**, confirm they converge on one shared anchor/peak and all flatten together when the
    shared-equity floor is hit. ⚠️ **Confirm with user**: exact flatten policy at reset (flatten-all vs
    block-new-only) and whether a position open *across* the reset boundary keeps or loses its floating P/L in
    the anchor (FTMO balance-anchor drops it; equity-anchor keeps it).

- [ ] **D2 — Per-EA trade CSV log (append-immediately on close).**
  - Each EA/chart writes **its own** file (no shared writer): key by symbol + account login (+ magic/timeframe
    if a symbol runs on two charts), e.g. `KKTrades_<EA>_<SYMBOL>_<login>.csv` in the per-terminal Files folder.
  - **Write each closed trade the instant it closes** (open `FILE_READ|FILE_WRITE`, seek-to-end, append one row,
    close — or keep a handle and `FileFlush` per row). Cost is microseconds; it does **not** bother tick/entry
    logic (the hourly-batch idea was rejected — it only risks losing up to an hour of trades on a hard crash for
    no measurable I/O win). Write the header once if the file is new. **Mandatory `OnDeinit` flush/close.**
  - **Live-only:** skip writes under `MQLInfoInteger(MQL_TESTER|MQL_OPTIMIZATION)` (engine emits its own
    `trades_*.csv` for parity — keep the two separate).

- [ ] **D3 — Minimal notifications for KK-MasterVP (and KK-Monster).**
  - ⚠️ **KK-KenKem already has the full suite** (ported from KenKemExpert — `Alerts/{Common,Discord,Telegram}Alerts.mqh`,
    enum `NOTIFICATION_MODE`, `MADE_FOR_PROP_TRADING`). **Do not touch / regress it.** The real gap is
    **KK-MasterVP** (zero notification code today) and KK-Monster.
  - **Build a small shared `Notifier.mqh` in `KK-Common`** (don't copy-paste KenKem's 5 files) that MasterVP /
    Monster include. Reuse the proven `WebRequest` call shapes from KenKem's Discord/Telegram senders.
  - **Inputs (bare-minimum, user's spec + additions):**
    - `InpNotifyChannel` enum {0 None, 1 Email, 2 Discord, 3 Telegram, 4 Email+Discord, 5 Email+Telegram,
      6 Discord+Telegram, **7 All three**} — *added 7 for completeness*.
    - `InpNotifyMode` enum {1 Full, 2 Simplified-for-prop} — simplified = symbol + action + result only, no
      entry/SL/TP details (matches KenKem's `MADE_FOR_PROP_TRADING`).
    - `InpDiscordWebhookUrl` (string), `InpTelegramBotToken` + `InpTelegramChatId` (string; group IDs are
      negative). Email uses MT5 `SendMail()`.
  - **Operational notes (put in the user guide):** (1) WebRequest needs `api.telegram.org` and
    `discord.com`/`discordapp.com` whitelisted in *Tools → Options → Expert Advisors → Allow WebRequest*; (2)
    Email needs SMTP set in *Tools → Options → Email*; (3) `WebRequest`/`SendMail` are **blocked in
    Tester/Optimization** — guard with `MQL_TESTER` so backtests don't spam (and don't stall).

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
