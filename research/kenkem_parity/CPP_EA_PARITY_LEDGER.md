# C++ ⇄ EA PARITY LEDGER — KenKem (the zero-surprise contract)

_Authored 2026-06-16. Companion to `PIPELINE-CONTRACT.md` §4 and `PARAM_SURFACE_AUDIT.md`._

## Why this file exists
The user's hard requirement: **a config swept in the C++ engine must reproduce in the deployed EA
trade-for-trade — no surprises, not even a tiny mismatch.** That can only be true if the C++ engine
(the SOURCE OF TRUTH) and the EA we actually deploy compute the **same decisions on the same data**.

This ledger enumerates **every** point where the two diverge today, with file:line on both sides, so the
fear ("what could surprise me?") becomes a finite, checkable list. Close every (F)/(P) row → the engine's
PF becomes a reliable predictor of the MT5 PF.

## The two artifacts
| Role | Artifact | Files |
|---|---|---|
| **SOURCE OF TRUTH** (research/sweep engine) | `kk::kenkem` tick engine | `cpp_core/include/kk/kenkem/{tick_engine,entries,gates,scoring,exits,trade_manager,engine}.hpp` |
| **DEPLOY VEHICLE** (what actually trades in MT5) | `KK-KenKem.ex5` | `kenkem/.../KK-Common/KenKem/{Engine,Inputs}.mqh` (18-line `KK-KenKemE4/KK-KenKem.mq5` just includes them) |

**⚠️ The EA header lies.** `KK-Common/KenKem/Engine.mqh:4` claims the EA is a "Faithful transcription of
the validated dquants kk::kenkem engine (the SINGLE SOURCE OF TRUTH)." It is **not** — it is the *distilled
subset*. The list below is exactly what was dropped. Until these are closed, the engine and the EA are two
different strategies wearing the same name, and any sweep result is unsafe to deploy.

## Severity legend
- **(F) FORMULA** — same feature, different math. Silent P&L drift on every affected trade. Must eliminate.
- **(P) PORT** — present in the engine, **absent** in the EA (Path-B work: add as an EA `input`, default
  OFF so `all-OFF == today's EA`, then turn on to inherit the engine's edge). Each needs **one MT5 run** to validate.
- **(M) BROKER-MODELABLE** — a real broker constraint the EA honors but the engine ignores. Model it in C++.
- **(I) IRREDUCIBLE** — tick-fill timing; accept within the §4 tolerance (≤0.5–1% net P&L).

---

## A. ENTRY GATES — engine is a strict SUPERSET of the EA
The engine's `entry_gate_ok` (`entries.hpp:116-167`) applies filters the EA's `GateOk`
(`Engine.mqh:213-238`) never received. **Same params ⇒ the EA fires MORE trades** (over-trades chop). This
is the documented "engine more selective / KK-KenKem over-distilled & losing" fork.

| # | Filter | Engine (truth) | EA (deploy) | Sev | Reconciliation |
|---|---|---|---|---|---|
| A1 | **Valid-session entry gate** (UTC Japan/London/NY) | `tick_engine.hpp:149` `in_valid_session` blocks off-session entries | **absent** — EA trades 24h (`Engine.mqh` has no session code) | **P** | port `in_valid_session` + JAPAN/LONDON/NY windows + `CLOSE_ALL_TRADES_AT_SESSION_END`; this alone is a large trade-count gap |
| A2 | **ATR-percentile floor** `MIN_ENTRY_ATR_PERCENTILE` | `entries.hpp:123` blocks if `atr_pctile < thr` | absent | **P** | add `InpMinEntryAtrPctile` (default 0 = off) + `atr_pctile` calc (EA already has `AtrPct`, `Engine.mqh:82`) |
| A3 | **ATR-high black-swan block** `ENABLE_ATR_HIGH_BLOCK`/`ATR_PERCENTILE_HIGH` | `entries.hpp:127` blocks if `atr_pctile > high` | absent | **P** | add `InpEnableAtrHighBlock`+`InpAtrPctileHigh` |
| A4 | **Full 0–11 trend-quality min** `MIN_TREND_QUALITY_E{1,2,4,5}` | `entries.hpp:140,147` → `scoring.hpp:167-203` (`trend_quality_score`) | EA only has the **0–6 hard core** (`TrendCore`, `Engine.mqh:109`) — no accel/PA/M3-accel/ichimoku/ATR-health bonus, no min threshold | **P** | port `trend_quality_score` + per-entry `InpMinTqE*` |
| A5 | **Conviction score + threshold** `USE_CONVICTION_SCORING_E*`/`CONVICTION_THRESHOLD_E*` (E2 thr=10!) | `entries.hpp:147` → `scoring.hpp:77-139` (`conviction_score`, 0–12) | absent | **P** | port `conviction_score` + `InpUseConvE*`/`InpConvThrE*` |
| A6 | **RSI-divergence veto** `ENABLE_RSI_DIVERGENCE_VETO` (M3 RSI 14) | `entries.hpp:147` → `scoring.hpp:208-233` (`rsi_divergence_veto`) | absent | **P** | port `rsi_divergence_veto` + 4 inputs |
| A7 | **E5 trend-quality min** `MIN_TREND_QUALITY_E5` | `entries.hpp:140` | EA E5 gate (`Engine.mqh:216-220`) checks only price>EMA25 + ADX floor + HTF | **P** | add `InpMinTqE5` + `InpE5RequireTrendCore` |
| A8 | E1/E2 EMA-alignment, E4 cloud agreement, sideways block, HTF filter, trend-core hard gate | `entries.hpp:143,148-164`, `gates.hpp` | **MATCH** (`Engine.mqh:213-238`) | — | already faithful — keep |

> Note A8 is why the like-for-like vs the *original KenKemExpert* showed faithful entries. The divergence
> is purely vs the **distilled KK-KenKem EA**, which is what we deploy.

## B. EXITS — engine has three paths, the EA has one
Engine: `manage_tick` (per-tick) **plus** `per_bar_exits_` (per-bar). EA: `Manage()` (per-tick) only.

| # | Exit | Engine (truth) | EA (deploy) | Sev | Reconciliation |
|---|---|---|---|---|---|
| B1 | partial-TP → BE → chandelier trail | `trade_manager.hpp:64-130` | **MATCH** (`Engine.mqh:333-354`) — same `entry+trig*(tp-entry)`, `entry+be*risk`, `best-trail*risk` | — | faithful — see C for the residual formula nits |
| B2 | **session-end close** `CLOSE_ALL_TRADES_AT_SESSION_END` | `tick_engine.hpp:114` (tag `'E'`) | absent | **P** | port with A1's session code |
| B3 | **fast-ADX panic exit** `ENABLE_FAST_ADX_PANIC_EXIT_E*` | `tick_engine.hpp:116` → `exits.hpp:73-96` | absent | **P** | port `panic_exit_triggers` + `InpPanicE*`/`InpPanicMinSlUsed`/`InpPanicGiveback` |
| B4 | **score-drop exit** `ENABLE_SCORE_DROP_EXIT_E*` | `tick_engine.hpp:118` → `exits.hpp:100-114` | absent | **P** | port `score_drop_triggers` + `InpScoreDropE*`/`InpScoreDropThrE*`/`InpScoreDropConsec` |

## C. MANAGEMENT FORMULA — same shape, small but real differences
| # | Detail | Engine | EA | Sev | Fix |
|---|---|---|---|---|---|
| C1 | **partial lot rounding** | `trade_manager.hpp:79` used raw `init_lot*ratio` (no step round) | `Engine.mqh:337-338` floors to broker volume step `MathFloor(q/step)*step` and requires `q>=min_lot` | **F** | ✅ **FIXED this session** — engine now floors to `lot_step` + requires `>=min_lot` (mirrors EA exactly); `partial_done` still latches even if the slice is sub-min |
| C2 | **broker min stop distance** on BE/trail SL moves | none (always moves) | `Engine.mqh:343-344,351-352` refuses a move within `max(STOPS_LEVEL,FREEZE_LEVEL)*_Point` of price | **M** | ✅ **MODELED this session** — added `stops_level_price` (default 0 = Exness ⇒ inert); engine now applies the same `okDist` clamp |
| C3 | full SL/TP realization | synthetic close at `sl`/`tp` inside `manage_tick` | broker resting SL/TP order | **I** | prices identical; per-tick only one side can cross (engine feeds exit-side bid/ask). Faithful on the **tick** path; the bar engine is quarantined |
| C4 | best-price seed | `open_position` seeds `best=entry` | `Engine.mqh:331` seeds `st_best=entry` on first manage | — | equivalent |

## D. PORTFOLIO / RISK GUARDS — engine has them, the EA has almost none
| # | Guard | Engine | EA | Sev | Reconciliation |
|---|---|---|---|---|---|
| D1 | max concurrent / block-opposite | `tick_engine.hpp:146,159` | **MATCH** `InpMaxConcurrent`/`InpBlockOpposite` (`Engine.mqh:294,270`) | — | faithful |
| D2 | occupancy (block kind+dir while open) | `tick_engine.hpp:155-156` | **MATCH** (`Engine.mqh:270` block-opposite + first-match) — verify per-kind occupancy | (P?) | confirm EA blocks same-kind same-dir re-entry while open |
| D3 | **max entries/day** `MAX_ENTRIES_PER_DAY` | `tick_engine.hpp:142-145` | absent | **P** | add `InpMaxEntriesPerDay` (default 0=off) |
| D4 | **daily-loss / peak-DD / soft-block / recovery halts** | config present (`kenkem_config.hpp:46-50`); **NOT yet enforced in tick_engine** — see note | absent | **P** | ⚠️ also a C++ TODO (BUILD-PLAN C2: KenKem has ZERO DD breakers). Build in engine first, then port |
| D5 | **min-seconds-between / consec-loss cooldown / session-loss caps** | config present (`:51-55`); enforcement TBD in tick engine | absent | **P** | engine-first, then port |

> D4/D5 are the only rows where the **engine itself** is also incomplete. They are tracked in
> BUILD-PLAN as **C2 (safety gap)** — do not return-optimize them.

## E. SIZING
| # | Detail | Engine | EA | Sev |
|---|---|---|---|---|
| E1 | risk-correct lot `bal*risk/(riskPx*vppl)` | `trade_manager.hpp:26-31` | **MATCH** `PositionSize` (`Engine.mqh:241-247`) | — |
| E2 | per-entry risk ratio (E1×1.05 etc.) | `risk_ratio_for` (`trade_manager.hpp:18`) | EA uses one `InpRiskPerTrade` for all entries | **F (minor)** | EA flattens the per-entry multiplier → slightly different lots. Decide: add per-entry risk to EA, or drop the multiplier in the engine. Low P&L impact; **resolve before deploy.** |
| E3 | BTC std-lot ×2, pip/contract per symbol | `kenkem_config.hpp:283-288` | EA `Engine.mqh:62-66` derives pip/vppl from broker | verify equal on the live symbol spec |

---

## The reconciliation plan (EA → engine; Path B, user-endorsed)
Bring the **EA up to the engine** (never dumb the engine down — that throws away the edge). Each step adds
EA `input`s **defaulting to today's behavior (OFF)**, so `all-OFF` reproduces the current EA exactly, then
flips ON to match the engine. Validate each with **one MT5 run** against the engine export via `parity_diff.py`.

1. **Sessions (A1+B2)** — biggest trade-count lever; add session windows + valid-session entry gate + session-end close.
2. **Quality suite (A4+A5+A6+A7)** — `trend_quality_score`, `conviction_score`, `rsi_divergence_veto`, E5 TQ.
3. **ATR regime (A2+A3)** — entry ATR-percentile floor + high block.
4. **Adaptive exits (B3+B4)** — panic + score-drop.
5. **Guards (D3; then D4/D5 after the engine grows them)** — per-day cap, then DD breakers.
6. **Sizing reconcile (E2)** — pick one risk model for both sides.

After each: engine export + MT5 run + `parity_diff.py` must show entries 1:1 (≤1-bar lag on ≤5%), exit
reasons match, net P&L Δ ≤ ~1%. Only then is that feature "parity-locked."

## Closed this session (C++ side, headless-testable)
- **C1** partial-lot step-rounding + min-lot guard in `manage_tick` (now byte-equal to the EA's `MathFloor(q/step)*step; q>=min`).
- **C2** broker `stops_level_price` modeled on BE/trail SL moves (default 0 ⇒ inert for Exness; faithful for any nonzero-stops broker).
- Regression test `test_kenkem_trade_manager.cpp` extended to lock both.

## Status board (update as rows close)
| Group | Rows | State |
|---|---|---|
| A entry gates | A1–A7 | OPEN (P) — A8 faithful |
| B exits | B2–B4 | OPEN (P) — B1 faithful |
| C mgmt formula | C1, C2 | ✅ CLOSED this session · C3/C4 faithful |
| D guards | D3 | OPEN (P) · D4/D5 blocked on engine-side C2 |
| E sizing | E2 | OPEN (F-minor) · E1/E3 faithful |
