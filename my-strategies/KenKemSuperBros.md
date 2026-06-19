# KenKem SuperBros — Strategy Description

> M1-focused EMA-stack momentum-continuation scalper for XAUUSD/BTCUSD. A single unified entry fires when all four EMAs (default lengths 24/72/94/194) stack in one direction within 28 bars of the alignment onset and the last completed bar closes on the trend side of the fastest EMA, gated by a 0–11 trend-quality score and a battery of regime/sideways/session/news vetoes. Core edge hypothesis: a fresh 4-EMA stack plus multi-TF DMI conviction marks the start of a tradeable M1 momentum leg; everything else in the script exists to refuse the trade when the regime is chop, panic, or off-session.

## 1. Overview

- **Source file:** `/Users/tokyotechies/Workspace/KEM/kenkem-pine/KenKemIndicator.pine` (Pine v6, ~3075 lines). Script header: `strategy("KK 2.1 Full ", ...)`.
- **Instruments:** XAUUSD primary (pip size hardcoded 0.01, display pip $0.10, contract size 100 oz when ticker contains "XAU", else 1.0 for BTC/ETH). Symbol-agnostic risk sizing.
- **Timeframes:** Entry TF = chart TF, default M1 (`entryTF="1"`; a red overlay warns if the chart TF differs). Mid TF default M3, High TF default M5 — used only for context (sideways scoring, trend quality, DI alignment, HTF conflict veto), not for entry triggers.
- **Style:** Momentum-continuation scalp, single position, pyramiding=0, reversals allowed (a long signal can flip an open short and vice versa). TP1 partial (60%) → optional BE → chandelier trail on the runner.
- **Dual mode:** With `allowTrading=true` it places real `strategy.entry/exit` orders. With `allowTrading=false` it runs as a hint-only indicator and tracks "virtual trades" (price-touch detection of SL/TP1/TP2) for labels, alerts, and session/day statistics. This is the public-tier source: the build pipeline hardcodes `showFullEntryAlerts`/`showPremiumTags`/`showMtfAlignAlert` per tier (Free/Basic/Pro ship as indicators, Premium as strategy).
- **Relation to KenKem classic:** This is the *simplified* variant. Classic KenKem (the MQL EA / `KenKemVisualizer-legacy.pine`) has four distinct entry types (E1 EMA100 bounce, E2 EMA75 pullback, E3 exhaustion reversal, E4 Ichimoku cloud cross) plus an M1/M3/M5 alignment requirement. SuperBros collapses all of that into **one** alignment-continuation entry; EMA lengths are user inputs; there is no requirement that M1/M3/M5 all be aligned (HTFs only veto when *both* lean against the trade). Ichimoku survives only as an optional HTF veto, not an entry. The trade-ID label hardcodes the string "E1" (`dir + "-E1 " + activeMagic`) but this is naming residue — the logic is not classic E1.

## 2. Market Context / Regime Detection

All decision reads are anti-repaint: M1 series use `[1]` (last completed bar), and every `request.security()` call shifts `[1]` *inside* the callback with `lookahead=barmerge.lookahead_off`. Entries are additionally gated to `barstate.isconfirmed`.

**EMA alignment (the regime that arms the signal).**
- Long regime: `ema25[1] > ema75[1] and ema75[1] > ema100[1] and ema100[1] > ema200[1]` (all strict `>`). Short is the exact mirror with `<`.
- A 4-zone classifier (`f_zone`) exists for the HTF: 1 = bullish stack, 3 = bearish stack, 2 = close below the slowest EMA, 4 = mixed above the slowest EMA — computed on the veto HTF but the zone value itself is only returned, not used as an entry gate in this script.

**Multi-TF partial direction (HTF conflict veto).**
`f_tfPartialDirection()` on mid and high TFs returns +1 if `e25[1] > e75[1] > e100[1]`, −1 if fully inverted, else 0 (3-EMA stack — deliberately omits EMA200). Long entries are blocked only when **both** mid and high TF return −1 (`htfConflictBlockLong = midTfLeansBearish and highTfLeansBearish`); mirror for shorts. One disagreeing HTF does not block — this is the "no M1/M3/M5 alignment requirement" simplification.

**Sideways score (0–100, per TF), 5 components:**
1. EMA convergence (0–25): `(maxEMA − minEMA) / ATR(14)` — `< 1.75` → 25 pts, `< 3.25` → 15, `< 4.0` → 8.
2. ADX weakness (0–25, capped): M1 ADX `< 15` → 15, `< 20` → 10, `< 25` → 5; plus M3 ADX `< 18` → 10, `< 22` → 5.
3. DI indecision (0–20): `|DI+ − DI−| < 2.0` → 12, `< 4.0` → 8, `< 6.0` → 4.
4. RSI neutral zone (0–15): RSI in [45,55] → 15, [40,60] → 10, [35,65] → 5.
5. ATR compression (0–15): ATR(14) percentile (over 100 bars) `< 15` → 15, `< 25` → 10, `< 35` → 5.

ADX/RSI inputs are 5-bar SMA-smoothed. A TF is "sideways" when score `>= 50` (`sidewaysBlockThreshold`, hardcoded). **Multi-TF sideways** = at least 2 of {M1, M3, M5} at/above threshold on **either of the last 2 M1 bars**. `sidewayBlocksEntry = multiTfSideway` — blocks new entries (signal is deferred, not consumed; see §3).

**Weak-trend guard (direction-aware, completed bar [1]):**
- `diSpreadBullish = DI+[1] − DI−[1]` (DMI 14,14 on M1).
- If `ADX[1] < 19.0` (`weakTrendADXThreshold`), require spread `>= 3.5` (`weakTrendDISpreadMin`); else require spread `>= 0` (i.e. DI merely on the trade's side). Block fires on `spread < required` (strict `<`).

**Trend Quality Score (0–11) — the per-entry conviction gate**, computed from completed-bar [1] inputs (so internal history refs reach bars [2]..[5]):
1. ADX strength (0–2): M1 ADX `>= 28` → 2 (`adxHighThreshold`), `>= 19.5` → 1 (`minMomentumADX`).
2. DI spread (0–2): directional spread `>= 3.0` → 2, `>= 1.0` → 1.
3. M1 acceleration (0–2, `useAccelerationBonus` hardcoded true): ADX rising 3 bars in a row AND DI spread widening 3 bars AND spread `> 0.5` → 1 pt; the same over 5 bars → 2 pts.
4. Multi-TF DI alignment (0–2): count of {M1, M3, M5} with DI on the trade's side — 3/3 → 2, ≥2 → 1.
5. Price action (0–1): two consecutive closed bars in trade direction (`close[1] > open[1] and close[2] > open[2]` for long).
6. M3 acceleration (0–1): M3 ADX rising 3 bars AND M3 DI spread widening 3 bars AND spread `> 0.5`.
7. ATR health (0–1): ATR percentile `>= 20.0`.

Entry requires score `>= minTrendQualityScore` (default 5; 0 disables the gate).

**ATR percentile regime filter:** present in code (`atrPctl[1]` must be inside [40, 78]) but **hardcoded disabled** (`atrRegimeFilter = false`). The [40, 78] band is still used to classify the vol regime for the optional Volatility-Based RR multipliers and the Premium "Vol band" alert tags.

## 3. Entry Logic

There is exactly **one** entry type, applied symmetrically long/short. Classic E1/E2/E3/E4 do not exist here as separate triggers (Ichimoku appears only as a veto; there is no EMA100-bounce, EMA75-pullback, or exhaustion-reversal logic anywhere in this file).

### E1 (unified) — Fresh EMA-stack alignment continuation

**Signal arming (fresh-cross timer).** When the 4-EMA alignment turns on (`isBullishAligned and not isBullishAligned[1]`), the onset bar index is latched (gated to `barstate.isconfirmed`). The latch is cleared when alignment breaks, and a per-direction `consumed` flag prevents re-arming mid-trade or after an entry has fired off that alignment (one entry per alignment episode).

**Trigger (per closed bar, `barstate.isconfirmed`):**
- Long: `isBullishAligned` AND signal latched AND `(bar_index − lastBullishSignal) <= 28` (`maxCrossAge`, hardcoded) AND `close[1] > ema25[1]` (strict) AND trend quality score `>= 5`.
- Short: mirror with `close[1] < ema25[1]`.

**Hard gates on top of the trigger (`longAllConditions`):** position allows it (flat or opposite — reversal supported), EMAs warmed up, correct chart TF, inside a session, opposite stack not simultaneously true on [1], no SL breach handled this bar, not inside a news window, not a blocked JST hour, HTF Ichimoku future-cloud veto clear (when `useM5IchimokuVeto=true`, default ON: HTF Senkou A[1] `<` Senkou B[1] blocks longs, `>` blocks shorts; HTF selectable M3/M5, default M3), session-VWAP veto clear (when `useVwapVeto=true`, default OFF: long requires HTF `close[1] > vwap[1]`).

**Final entry gate (`enterLong`):** all of the above AND not multi-TF sideways AND weak-trend guard passes AND deferred-entry distance OK AND no HTF conflict AND ATR regime OK (currently always true) AND open-slip OK AND no risk-limit block AND no same-bar action already taken.

**Deferred entry (sideways hold-and-retry):** a valid signal blocked by multi-TF sideways is *not* consumed. Once sideways clears, the entry is allowed only if `|close[1] − ema25[1]| <= 1.0 × ATR(14)[1]` (`deferredEntryMaxATR`, hardcoded 1.0) — i.e. price must still be near the fast EMA, not already extended. The deferral cancels if alignment breaks.

**Open-slip (gap) guard:** entry is deferred (signal stays armed) when `|open − close[1]| > 0.36 × ATR(14)[1]` (`openSlipMaxATR` default 0.36; 0 disables).

**Entry price:** anchored to the trigger bar's `open` (the first tick where [1]-data is valid), so historical and live fills agree.

## 4. Exit & Trade Management

**SL placement (at entry):**
- Raw SL = `ema200[1] − 2 × spreadPrice` for longs (`+` for shorts); `spreadPrice` hardcoded 0.4 price units (40 XAUUSD pips), so the SL sits 2 spreads beyond the slow EMA.
- SL distance floored at `minSLPips = 50` pips (hardcoded; 0.5 price units on XAUUSD).
- ATR cap (`useATRSLCap` default ON): if distance `> 2.8 × ATR(14)[1]` (`atrSLMult`) and that cap is itself `>= ` the 50-pip floor, distance is clamped and SL recomputed from entry.

**Targets:**
- TP1 = entry ± `slDist × 0.82` (`tp1RMult` hardcoded 0.82R). Closes **60%** of the position (`tp1ClosePct` hardcoded).
- TP2 = entry ± `slDist × effectiveRR`. Base `rrRatio = 1.5`; with `enableVolatilityRR=true` (default OFF) it becomes `rrRatio × sessionMul × volMul` — session multipliers Asia 1.0 / London 1.09 / NY 1.16, vol multipliers 0.87 below ATR-pctl 40 / 1.03 above 78 / 1.0 in band. RR is locked at entry. `scaleTP1WithTP2` (default OFF) optionally applies the same multiplier to TP1.

**Break-even after TP1** (`archMoveBEAfterTP1` default ON): when TP1 is touched (wick-touch detection: long `high >= tp1`), SL moves to `entry + 2 × spreadPrice` (long; minus for short).

**Smart SL Trail** (`archEnabled` default ON), all moves routed through a single `moveSL` that only applies if the new SL tightens by `>= 2` pips AND stays at least 1 pip on the safe side of current price:
- **Pre-TP1 profit ratchet** (`archPreTp1Ratchet` default ON, fires once per trade): when max favourable excursion (bar high/low, not close) reaches `0.3R` (`archRatchetTrigR`), SL moves to the *tighter* of (a) structural extreme since entry (lookback `min(barsInTrade, 50)`) ± 1 pip, and (b) `entry ∓ 0.25 × original R`.
- **Pre-TP1 sideway defense:** hardcoded OFF (`archSidewayDefense = false`). When on, multi-TF sideways mid-trade pulls SL to BE+buffer (if at/above entry) or to half the original risk.
- **Post-TP1 trail:** long candidate = `min(HH(22) − mult × ATR(22), DonchianLL(30) + 5 pips)`; short mirrored. `mult` from `archTrailStyle`: Tight = 1.8 (default), Balanced = 2.5, Wide = 3.5. The Donchian(30) floor keeps the stop outside stop-hunt wicks.

**Early exits (each force-closes and finalizes the trade):**
- **Sideways exit** (`ALLOW_SIDEWAY_EARLY_EXIT`, default 0=off): mode 1 closes the trade when multi-TF sideways prints (only after `entryBar + 1`); mode 2 instead tightens SL to `ema75 ∓ 2 × spreadPrice` and recomputes TP1/TP2 from the new distance (loosening auto-rejected by `moveSL`).
- **Extreme momentum exit** (`allowExtremeMomentumExit`, default OFF): opposite-direction extreme = (DI spread[1] `>= 16` AND RSI[1] `>= 71` long / `<= 29` short) OR a bar-by-bar composite over a 3-bar lookback (≥2 of {DI widening, RSI moving, price moving ≥ 0.7×ATR per bar} majorities with DI spread `>= 0`). With `extremeExitOnlyOnLoser=true` (default), it fires only when the trade is not yet in profit (and never after TP1).
- **Session end** (`CLOSE_AT_SESSION_END`, default OFF) and **news-window start** (active whenever `avoidNews=true`) force-close open positions.

**Exit accounting:** SL and TP2 are detected by wick touch (long SL: `low <= sl`; long TP2: `high >= tp`) in addition to broker fills, so indicator-mode virtual trades and odd-fill feeds resolve identically. A trade that hit TP1 and then stops out is counted as a WIN by convention (TP1 leg banked 0.82R on 60%).

## 5. Risk Management

- **Position sizing:** `qty = floor(maxRiskUSD / slDist × 1000) / 1000` base units (oz / coins), min 0.001 — loss at SL ≈ the risk budget regardless of symbol. `maxRiskUSD` comes from `riskMode`: `% Account Balance` (default) → `maxRiskQty`% (default 2.0%) of `initial_capital + closed netprofit` (floored at 0); `USD` → fixed dollars.
- **Master switch `enableExtraRisk` (code default FALSE):** gates all four protective blocks below. Note: the tooltip says "Default ON" but the input is `input.bool(false, ...)` — with defaults, **none of the following four gates is active**.
  - **Daily drawdown breaker** (`maxDailyDDPct` 5.0%): *predictive* — blocks a new entry when `(dayStartEquity − equity + maxRiskUSD) / dayStartEquity × 100 >= 5.0`, so a trade cannot open through the cap. Baseline resets at the trading-day boundary (~04:31 JST; 05:59 under Ignore-Sessions).
  - **Per-session trade cap** (`maxTradesPerSession` 3): blocks when detected entries this session `>= 3`. Counts signal-time entries, not fills.
  - **Consecutive-loss stop** (`maxConsecLoss` 3): blocks for the rest of the trading day after 3 losing closures in a row; the streak spans sessions within the day, resets on any win or at the day boundary.
  - **Post-loss cooldown** (`maxLossCooldownBars` 65): blocks entries for 65 bars (~65 min on M1) after any losing close.
- All risk gates block **new entries only**; open positions run their SL/TP.
- One alignment episode = at most one trade (consumed-signal lock), plus a per-bar action lock (`tradeActionLastBar`) prevents same-bar entry/exit re-fires.

## 6. Filters & Sessions

- **Sessions (configured in JST, inputs as HHMM integers):** Asia 09:00–15:00, London 16:00–20:00, NY 21:30–25:30 (= 01:30 next day; times `<= 06:30` wrap by +2400). Membership tests are inclusive (`>= start and <= end`). Entries only inside a session unless `IGNORE_SESSIONS=true`. The trading "day" for daily stats/breakers runs 08:30 → 28:30 JST.
- **Blocked hours:** `blockedHoursStr` default `"12,15,18-20"` — no new entries during JST hours 12, 15, 18, 19, 20.
- **News filter** (`avoidNews` default ON): `request.economic()` for US NONFARM, CPI, IR (Fed funds), GDP, Jobless Claims. Window = release time −15/+15 minutes (`newsMinsBefore`/`newsMinsAfter`). Inside the window: new entries blocked and open positions force-closed at window start. Release times are cached per day in 5 slots with ±2-minute dedup. Limitation: the window can only be known once TradingView's feed prints the release — the "before" half depends on the calendar feed having marked the slot on a prior occurrence that day.
- **Volatility/gap:** open-slip gap filter 0.36 × ATR (see §3); ATR-percentile regime filter present but hardcoded off.
- **Other do-not-trade conditions:** wrong chart TF, multi-TF sideways, weak trend, HTF Ichimoku future-cloud against the trade (default ON), session VWAP against the trade (default OFF), both HTFs leaning opposite, any active risk-limit block.

## 7. Key Parameters

| Input | Default | What it does |
|---|---|---|
| `rrRatio` | 1.5 | Base R multiple for TP2 (final target). |
| `riskMode` / `maxRiskQty` | "% Account Balance" / 2.0 | Per-trade risk budget: 2% of balance (initial + closed P&L) lost if SL hits; drives lot sizing. |
| `ema25Len/ema75Len/ema100Len/ema200Len` | 24 / 72 / 94 / 194 | The four stack EMAs (names are legacy; lengths are customizable — the SuperBros differentiator). |
| `entryTF` / `midTF` / `highTF` | 1 / 3 / 5 | Chart TF and the two context TFs (minutes). |
| `vetoHTF` | "3" | TF (M3/M5) used by the Ichimoku future-cloud and VWAP vetoes. |
| `useM5IchimokuVeto` | true | HTF future cloud (Senkou A[1] vs B[1]) blocks counter-cloud entries. |
| `useVwapVeto` | false | Session VWAP trend veto (long only above, short only below). |
| `maxCrossAge` | 28 (hardcoded) | Entry must fire within 28 bars of alignment onset. |
| `minTrendQualityScore` | 5 | Minimum 0–11 trend quality score; 0 disables. |
| `minMomentumADX` / `adxHighThreshold` | 19.5 / 28 | ADX bands for quality-score component 1. |
| `weakTrendADXThreshold` / `weakTrendDISpreadMin` | 19.0 / 3.5 | Below ADX 19, require DI spread ≥ 3.5 in trade direction. |
| `sidewaysBlockThreshold` | 50 (hardcoded) | Per-TF sideways score ≥ 50 counts toward the 2-of-3 multi-TF block. |
| `spreadPrice` | 0.4 (hardcoded) | Assumed spread in price units (40 XAUUSD pips); SL/BE buffers = 2×. |
| `minSLPips` | 50 (hardcoded) | SL distance floor in display pips (0.5 price units). |
| `useATRSLCap` / `atrSLMult` | true / 2.8 | Clamp SL distance to 2.8 × ATR(14)[1] when the EMA200 anchor is wider. |
| `tp1RMult` / `tp1ClosePct` | 0.82 / 60 (both hardcoded) | TP1 at 0.82R closing 60% of the position. |
| `openSlipMaxATR` | 0.36 | Skip entry when bar-open gap > 0.36 × ATR; signal stays armed. |
| `blockedHoursStr` | "12,15,18-20" | JST hours with no new entries. |
| `avoidNews` / `newsMinsBefore` / `newsMinsAfter` | true / 15 / 15 | USD high-impact news window: block entries, force-close positions. |
| `enableExtraRisk` | **false** | Master switch for daily-DD / session-cap / loss-streak / cooldown gates. |
| `maxDailyDDPct` / `maxTradesPerSession` / `maxConsecLoss` / `maxLossCooldownBars` | 5.0 / 3 / 3 / 65 | The four protective gates (only active when `enableExtraRisk=true`). |
| `enableVolatilityRR` + session/vol multipliers | false | Opt-in RR scaling by session (Asia 1.0/LDN 1.09/NY 1.16) and ATR-percentile band (0.87/1.03). |
| `archEnabled` / `archPreTp1Ratchet` / `archRatchetTrigR` | true / true / 0.3 | Smart SL trail master, pre-TP1 ratchet, ratchet trigger in R. |
| `archTrailStyle` | "Tight" | Post-TP1 chandelier multiple: Tight 1.8 / Balanced 2.5 / Wide 3.5 × ATR(22). |
| `archMoveBEAfterTP1` | true | SL to entry + 2×spread when TP1 hits. |
| `ALLOW_SIDEWAY_EARLY_EXIT` | 0 | Open-position sideways handling: 0 off, 1 close, 2 tighten SL to EMA75. |
| `CLOSE_AT_SESSION_END` / `IGNORE_SESSIONS` | false / false | Force-close at session end / trade 24-5. |
| `allowTrading` | true | OFF = indicator/hint mode: no orders, virtual-trade tracking only. |

## 8. Known Limitations & Notes

- **One entry type only.** Despite family lore (E1–E4) and the hardcoded "E1" in trade labels, this script implements a single alignment-continuation entry. There is no EMA100-bounce, EMA75-pullback, exhaustion-reversal, or Ichimoku-cross entry.
- **`ALLOW_SIDEWAY_ENTRIES` is a dead input.** Declared (default false) but never read — `sidewayBlocksEntry = multiTfSideway` unconditionally. Toggling it does nothing.
- **`enableExtraRisk` default mismatch.** Code default is `false`; the tooltip claims "Default ON". With factory defaults the daily-DD breaker, session cap, loss-streak stop, and cooldown are all inert.
- **Two divergent trend-quality implementations.** The entry gate uses `getTrendQualityScore` (input-driven thresholds 19.5/28); the status-table "Trend Acceleration" display uses a separate `calcTrendQuality`/`calcConviction` pair with hardcoded thresholds (25.0/19.5, ATR-vs-SMA50 health, different PA test). The dashboard number is not the number that gates entries.
- **Many "parameters" are hardcoded** (commented-out inputs): spread 0.4, TP1 0.82R, TP1 close 60%, min SL 50 pips, maxCrossAge 28, sideways threshold 50, deferred-entry distance 1.0 ATR, extreme-momentum thresholds, ATR regime filter (off). Tuning these requires editing source.
- **News filter is reactive.** `request.economic()` only prints values at release; the −15-minute pre-window protection depends on the release time having been cached, and on TradingView's calendar feed. It is weaker than a true scheduled-calendar filter (the MQL twin uses a CSV).
- **Virtual P&L is pip-distance arithmetic, not fill simulation.** Indicator-mode stats (session/daily/weekly summaries, win counting) sum pip distances per leg with no spread/slippage/qty weighting, and count TP1-then-SL as WON. They are engagement telemetry, not a cost-modeled backtest.
- **Wick-touch exit detection** (`high >= tp` / `low <= sl`) counts any touch as a fill — optimistic versus a real limit/stop fill at the broker, especially on the TP side.
- **Heavy varip scaffolding.** A large fraction of the file is anti-rollback machinery (`vip*` mirrors, per-bar dedup guards) for `calc_on_every_tick=true` realtime correctness; it is repaint-hardened by design (`[1]` reads, `barstate.isconfirmed` triggers, shifts inside `request.security`), but any edit touching trade state must respect the varip mirror/restore pattern or live behavior will diverge from the backtest.
- **Strategy-tester realism:** commission 0.0005% + 10-tick slippage + bar magnifier are configured, but `spreadPrice` (0.4) is a model constant, not live spread; XAUUSD round-trip cost realism still depends on the broker feed used in TV.
