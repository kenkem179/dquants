# KenKem Original — Strategy Description

> KenKem (classic) is an M1-execution scalper for XAUUSD/BTCUSD that trades trend continuation and exhaustion reversal off a multi-timeframe (M1/M3/M5/M15) EMA 10/25/75/100/200 structure, confirmed by DMI/ADX and RSI scoring. The core edge hypothesis: when the EMA stack *freshly* aligns across timeframes (or price pulls back into the stack while aligned) and directional momentum scores clear quantified thresholds, the M1 move continues long enough to clear a 1.5–2.0 R:R bracket; a separate score-based counter-trend path (E3) fades exhausted M3 moves on RSI divergence. Source of truth for current logic: `pineScript/KenKemVisualizer.pine` (header: "KenKem Strategy v1.7.993").

## 1. Overview

- **Instruments:** XAUUSD primary (pip = 0.01, contract 100 oz), BTCUSD secondary. Pip size and contract size are inputs (`PIP_SIZE_INPUT` = 0.01, `CONTRACT_SIZE_INPUT` = 100).
- **Timeframes:** Chart must be **M1** — trade execution is hard-disabled on any other chart timeframe (`if not isM1Chart → entryMadeThisBar := true`). Decision data is pulled via `request.security` from M1, M3, M5, and M15.
- **Style:** Intraday scalper, `pyramiding=0`, but up to 8 concurrent positions are possible (one per entry type per direction: L/S × E1/E2/E3/E4) — duplicate same-type positions are blocked, different types are not.
- **Source file:** `/Users/tokyotechies/Workspace/KEM/kenkem/pineScript/KenKemVisualizer.pine` (~4950 lines). Declared as `strategy(... initial_capital=10000, default_qty_type=strategy.percent_of_equity, default_qty_value=2)`.
- **Dual mode:** `useCSVMode=true` turns the script into a passive visualizer of MQL5 EA trade CSVs (timestamps in UTC); `useCSVMode=false` + `enableLiveStrategy=true` (defaults) runs live entry detection. This doc describes the live strategy.
- **Family:** This Pine file is the benchmarking twin of the MQL5 EA `MQL5/Experts/KenKem/` (the production target — comments throughout reference "MQL5 parity"). The simplified public derivative is SuperBros (`kenkem-pine/KenKemIndicator.pine`). The KK-MasterVP / Monster strategies are a separate volume-profile family and share nothing with this logic.
- **Supersedes:** the Nov-2025 prompt spec (`notes/strategies/KenKem Strategy Original`, extensionless). The old KEM/CHE zone system, fixed-pip SLs, and E1/E2-only design described there no longer exist in code.

## 2. Market Context / Regime Detection

All thresholds below are defaults of named inputs unless marked hardcoded.

### 2.1 EMA alignment (per timeframe)
`isEMAsReadyForEntry(isLong, ..., isStrict)` with tolerance `tol = emaAlignmentTolerance (20 pips) × pipSize`:

- **Strict (4-EMA), long:** `ema25 > ema75 − tol` AND `ema75 > ema100 − tol` AND `ema100 > ema200 − tol`. Short is mirrored with `<` and `+ tol`.
- **Loose (3-EMA):** same but the `ema100` vs `ema200` check is skipped.

Multi-TF combinations:
- **E1 alignment** (`isAllTimeframeEMAsReadyForE1`): M1 strict AND M3 strict AND M5 *directional with NO tolerance*: long `ema25_5m > ema75_5m and ema75_5m > ema100_5m and ema25_5m > ema200_5m`.
- **E2 alignment** (`isAllTimeframeEMAsReadyForE2`): M1, M3, AND M5 all strict (with tolerance).
- **E4 alignment:** 3-stack only, no tolerance: `ema25 > ema75 and ema75 > ema100` on M1 and M3.
- **E3 alignment (counter-trend):** M3 bar[1], strict `<` chain *against* the trade: L-E3 requires `ema10 < ema25 < ema75 < ema100`; S-E3 requires the `>` chain.

### 2.2 Trend Quality score (0–11), `getTrendQualityScore`
Used as the hard gate for E1/E2/E4 (per-entry minimums in §3). Components:
1. M1 ADX: `>= 25.0` (adxHighThreshold) → 2 pts, else `>= 19.5` (minMomentumADX) → 1.
2. M1 DI spread (directional, `DI+ − DI−` for long): `>= 3.0` → 2, `>= 1.0` → 1 (hardcoded).
3. M1 acceleration (if `useAccelerationBonus`, default on): ADX strictly rising AND DI spread strictly widening AND spread `> 0.5` — over 5 bars → 2 pts, over 3 bars → 1.
4. Multi-TF DI alignment (M1/M3/M5 directional DI spread `> 0`... strictly `DI+ > DI−`): all 3 aligned → 2, 2 of 3 → 1.
5. Price action: `close[1] > open[1] and close[2] > open[2]` (long; mirrored short) → 1.
6. M3 acceleration (same 3-bar rule as #3 on M3) → 1.
7. ATR health: M1 ATR(14) percentile `>= 20.0` over 100 bars → 1.

### 2.3 Conviction score (0–12), `calcConvictionGlobal`
Secondary gate, enabled per entry type. Components (each 0–2): M1 DI spread (`>= 3.0`→2 / `>= 1.0`→1); EMA stack separation (mean gap of 25/75, 75/100, 100/200 in pips, normalized by 30 pips: `>= 0.8`→2 / `>= 0.5`→1); RSI vs 50 on M1 and M3 (both on correct side → 2, one → 1); ADX (`>= 23` +1, `< 15` −1, 3-bar acceleration +1, clamped 0–2); M3+M5 confirmation (`ADX >= 22 and spread >= 2` on both → 2, one → 1, both at support level `ADX >= 16 and spread > 0.5` → 1); price action (long: `close > open and close > high[1]` → 2, "not bearish" → 1).

### 2.4 Sideways score (0–100), `getSidewaysScore`
Computed from M1 EMAs, M1 ATR(14), 5-bar SMA of M1/M3 ADX, M1 DI, 5-bar SMA of M1 RSI, ATR percentile:
- EMA convergence (max−min of the 4 EMAs, in ATR units): `< 1.75` → 25, `< 3.25` → 15, `< 4.0` → 8.
- ADX weakness: M1 `< 15`→15 / `< 20`→10 / `< 25`→5, plus M3 `< 18`→+10 / `< 22`→+5, capped at 25.
- DI indecision (`|DI+ − DI−|`): `< 2.0` → 12, `< 4.0` → 8, `< 6.0` → 4.
- RSI neutrality: 45–55 → 15, 40–60 → 10, 35–65 → 5.
- ATR compression (percentile): `< 15` → 15, `< 25` → 10, `< 35` → 5.

`score >= sidewaysBlockThreshold (53)` → **all entries blocked**. `>= sidewaysWarningThreshold (43)` → warning display only.

### 2.5 Extreme momentum bypass, `isExtremeMomentum` (M3 data)
Either method triggers; used to bypass M3/M5 EMA-alignment requirements at bypass level ≥ 1 (M1 alignment is never bypassed for E1/E4):
- **Absolute:** directional M3 DI spread `>= 16.0` (extremeDISpreadThreshold) AND M3 RSI `>= 70.5` (long) / `<= 29.5` (short).
- **Bar-by-bar:** over `extremeM3MomentumLookback (3)` M3 bars, at least 2 of 3 majority votes (DI spread widening, RSI moving directionally, bar close moves `>= 0.5 × ATR(M3)`) AND current DI spread `>= 0`.

### 2.6 Anti-repaint discipline
M3/M5/M15 DMI, M3 RSI, and M3 ATR are fetched with `[1]` **inside** the `request.security` callback (last closed HTF bar); M1 series are unshifted (chart is M1). Entries evaluate at bar close (`isNewM1Bar`) and fill at next bar open.

## 3. Entry Logic

Global pre-conditions for **every** entry (checked once per closed M1 bar):
- In a valid session (§6), `sidewaysScore < 53`, no entry already taken this bar, and `>= 60` seconds since the last entry (hardcoded `MIN_SECONDS_BETWEEN_ENTRIES = 60`; a nearby comment says 120 — the code says 60).
- No open position of the *same* type/direction (scans the last 10 recorded trades).
- One entry max per bar; within-bar priority order is **E1 → E4 (incl. E4-channel) → E2 → E3**.
- Entry price = current bar close; brackets placed via `strategy.exit(stop, limit)`.

### E1 — Fresh EMA-alignment cross / EMA200 pullback (primary continuation)
**Trigger (armed state `lastEMACrossingUp/Down`):**
- Set when alignment "just became true" on ANY of M1/M3/M5 (`not aligned at bar[1] AND aligned at bar[0]`; M1/M3 strict, M5 loose), provided the bypass-dependent alignment check passes — default `e1MomentumBypassLevel = 1`: M1 strict AND (M3 strict OR extreme momentum).
- Also re-armed when price **touches EMA200 on M1** (`low <= ema200 and high >= ema200`) with the same alignment check — this is the pullback re-entry path in established trends.
- Trigger expires after `e1MaxCrossAge = 80` M1 bars (cleared to −1); an opposite trigger clears it.

**Entry conditions (long; short mirrored):**
1. Trigger fresh: `bar_index − lastEMACrossingUp <= 80`.
2. Alignment: level 0 → full E1 MTF alignment; level 1/2 (default 1) → M1 strict AND (full MTF alignment OR extreme momentum).
3. `close_1m > ema25_1m` (strict `>`).
4. Trend quality `>= minTrendQualityE1 (6)`.
5. Conviction `>= convictionThresholdE1 (7)` (on by default).
6. RSI-divergence veto passes (veto disabled by default, §6).

**SL/TP:** `eSLLevel = ema100 − 0.75 × |ema100 − ema200|` (M1); `baseSL = min(lowest low of last 18 M1 bars, eSLLevel)`; `structureSL = baseSL − 40 pips` (`slEMADistance`). Distance is then ATR-arbitrated: capped at `4.0 × ATR14(M1)` (e1ATRCapMult), floored at `1.2 × ATR` (e1ATRFloorMult), then a spread buffer of `>= 0.5 ×` estimated spread (TV estimate: 3 ticks). TP = SL distance × `e1RR = 1.7` (long) / `e1RRShort = 1.7`.

### E2 — EMA75 pullback touch (stricter continuation)
**Trigger:** price touches EMA75 on M1 (`low <= ema75 and high >= ema75`); direction assigned by `ema25 > ema75` (bull) / `<` (bear). Expires after `e2MaxTouchAge = 36` bars.

**Entry conditions (long):** trigger fresh; **all of M1+M3+M5 strict 4-EMA aligned** (tolerance 20 pips); `close_1m > ema25_1m`; trend quality `>= minTrendQualityE2 (9)` — the strictest gate of the four; conviction `>= convictionThresholdE2 (8)`; RSI-div veto.

**SL/TP:** `baseSL = min(lowest low 18 bars, ema100)`, minus 40 pips, ATR cap `3.0×` / floor `1.1×`, spread buffer. TP = SL distance × `e2RR = 1.5` (both directions).

### E3 — Exhaustion reversal (score-based, counter-trend)
Evaluated **only when an M3 bar closes** (`m3BarChanged`) and only if `e3UseExhaustionScoring = true` (turning that input off silently disables all E3 entries).

**Core requirement — M3 RSI divergence** (`detectRSIDivergence`, M3 bars 1–4): long needs price lower-low (`min(low1,low2) < min(low3,low4)`), RSI higher-low at those lows, and RSI `< 40` on at least one of bars 1–4; short mirrored with higher-high, RSI lower-high, RSI `> 60`.

**Exhaustion score (0–12)** on M3, components 0–3 each: RSI pattern (was oversold `< 30` recently / crossed-above or above its 5-bar mean / spread `> 2.0`); ADX decline (1 bar / 2 bars / was `> 25` recently — only counted if ADX `> 14.0` adxLowThreshold); DI reversal (DI+ rising & DI− falling with spread improving → 2, +1 if ADX `>= 19.5`); wick rejection (lower/upper wick `>= 40%` of range on any of M3 bars 1–3, graduated).

**Two paths (long; short mirrored):**
- *Standard:* no open L-E3 + divergence + confirmation candle on M3 bar[0] (`close > open` OR higher low OR `close > close[1]`) + counter-trend EMA alignment (M3 `ema10 < ema25 < ema75 < ema100`; at `e3MomentumBypassLevel >= 1` (default 1) extreme momentum substitutes) + exhaustion `>= e3MinExhaustionScore (6)` + HTF alignment + regime gate + M1 rotation.
- *Instant:* same minus the confirmation candle, requiring high exhaustion — `>= 8` for long, `>= 7` for short (both hardcoded, asymmetric).

**Sub-gates:**
- *HTF trend alignment* (`e3RequireHTFTrendAlign = true`): hard-blocked if `e3BlockStrongTrend` and M15 ADX `>= 32.0`; otherwise needs DI direction agreeing with the trade (long: `DI+ > DI−`) on M5 OR M15 (`e3HTFAlignMode = 1`); a timeframe with ADX `< 14.0` counts as aligned. Note: this makes L-E3 a "buy the dip in an HTF uptrend" trade despite the M3 counter-trend EMA requirement.
- *Regime gate* (`e3EnableRegimeGate = false` — **off by default**): fatigue (M3 ADX rollover or DI-spread compression) and optional stretch from EMAs.
- *M1 rotation* (`e3M1RequireRotation = false` — **off by default**): M1 DI spread `>= 2.0` plus ADX uptick `>= 16.0`.

**SL/TP:** SL below the lowest low of the last `e3ExtremeLookback (9)` M3 bars minus `3.0 × ATR14(M1)` (`e3UseATRSL = true`; fallback fixed `e3SLBuffer = 20` pips), plus spread buffer. RR base `e3RR = 1.5`, score-adjusted (`e3ScoreRRAdjustEnabled = true`): score `< 9` → ×0.9; score `>= 12` → ×1.1.

### E4 — Ichimoku cloud cross (early trend)
Ichimoku computed from 9/26/52 highest/lowest midpoints; cloud color = `leadLine1 > leadLine2` (green) / `<` (red). The lead lines are used **without** the standard +26 displacement.

**Trigger:** cloud just turned green on **both M1 AND M3** (`green on both at bar[1] AND not both at bar[2]`); mirrored for red. Expires after `e4MaxCrossAge = 28` bars.

**Entry conditions (long; short mirrored):**
1. Trigger fresh.
2. EMA 3-stack `25 > 75 > 100` on M1, and on M3 (or extreme momentum at `e4MomentumBypassLevel >= 1`, default 1; M1 stack always required).
3. Price above both EMA25 and cloud top with 5-pip tolerance (hardcoded): `close_1m > ema25 − 5p and close_1m > cloudTop − 5p`.
4. Trend quality `>= minTrendQualityE4 (7)`.
5. E4-specific sideways cap: score `<= e4MaxSidewayScore (44)` (stricter than the global 53 block).
6. HTF trend filter `e4HTFTrendFilterMode = 4` (M15 only): block long if M15 is a *valid* opposing trend (ADX `>= 20.0` AND `|DI spread| >= 6.0` AND bearish).
7. M1 ADX `>= e4MinMomentumADX (20.0)`.
8. M5 DI alignment (`e4RequireM5DIAlign = false` — off by default) and conviction (`useConvictionScoringE4 = false` — off by default).
9. RSI-div veto.

**SL/TP:** same structure formula as E1 with cap `4.25×` / floor `1.25×` ATR; RR `e4RR = 2.0` long / `e4RRShort = 1.85`.

**E4-Channel sub-entry** (`enableE4ChannelEntry = true`): a linear-regression channel/wedge detector (swing highs/lows over a 50-back + 50-forward bar window, min 2 touches per edge, quality score `>= channelMinQuality (5)` out of 10, channel length `>= 30` bars hardcoded, recomputed every 5 bars). Long triggers: **false breakout at the lower edge** (broke below, closed back inside, rejection wick `>= 0.35` of range) or **breakout+retest at the upper edge**; shorts mirrored. Trend-quality requirement is reduced by 2 points (hardcoded → effective `>= 5`). SL: edge ∓ `1.5 × ATR(M1)` (FBO) or edge ∓ 30% of channel width (BO+, hardcoded); RR fixed `e4ChannelRR = 3.0`. Note: channel entries **skip** the sideways-44 cap, HTF filter, ADX minimum, and conviction gates — only the global gate + trend quality apply.

## 4. Exit & Trade Management

All management runs per bar on OPEN trades, mirroring MQL5 `TradeManager`. `progressRatio` = current PnL / distance to the **original** TP.

1. **Bracket:** stop + limit via `strategy.exit`. TP hit = `high >= tp` (long); SL hit = `low <= sl`. If SL was moved into profit, an SL hit is labeled WON.
2. **TP extension** (`ALLOW_TP_EXTENSION = true`): when remaining distance to TP `<= 25` pips (`TP_EXTENSION_TRIGGER_PIPS`), `> 0`, and `progressRatio >= 0.92` (hardcoded), extend TP by `10` pips (`TP_EXTENSION_PIPS`), up to per-type caps: E1 30, E2 20, E3 15, E4 30 extensions.
3. **Pre-BE structure protection** (`ENABLE_PRE_BE_STRUCTURE_PROTECTION = true`): before breakeven/partial, once profit `>= 0.45R` (`PRE_BE_TRIGGER_R`) and — if `PRE_BE_REQUIRE_M3_ACCEL_CONFIRM = true` — M3 shows 3-bar ADX rise + DI-spread widening + spread `> 0.5`, and close breaks the prior 5-bar high (long) by `> 1.0` pip buffer: SL is raised to current bar low − `8.0` pips, capped at entry − 0.5 pip, only if it improves the SL by `>= 2.0` pips.
4. **R-multiple breakeven** (`ENABLE_R_MULTIPLE_SL_PROTECTION = true`): at profit `>= 1.0R` (`R_MULT_BE_TRIGGER`, R measured against the original SL), SL moves to entry ± `2%` of original risk (`R_MULT_BE_BUFFER = 0.02`).
5. **Partial TP / breakeven** (`ALLOW_PARTIAL_TP = true`): triggers at `progressRatio >=` E1 `0.90`, E2 `0.80`, E3 `0.60`, E4 `0.80`. Pine cannot partially close, so the partial ratios (E1 0.20, E2 0.25, E3 0.30, E4 0.25) are tracked only; the actual effect is moving SL to entry ± `breakevenBuffer × origTPDist` (E1/E2/E4 `0.07`, E3 `0.03`).
6. **Trailing SL** (`ENABLE_TRAILING_SL = true`): active once the partial trigger has been reached. `trailDist = origTPDist × factor / (tpExtensions + 1)` from the best price; factors E1 `0.40`, E2 `0.45`, E3 `0.40`, E4 `0.50`. Only tightens.
7. **Early cut near SL** (`ENABLE_EARLY_CUT = true`): if adverse move has consumed `>=` E1 `0.89`, E2 `0.88`, E3 `0.82`, E4 `0.90` of the SL distance AND (multi-TF momentum check fails OR M3 trend is weakening — ADX declining 2 bars or DI spread narrowing 2 bars), close at market before the SL prints.
8. **Momentum reversal exit** (`ENABLE_MOMENTUM_EARLY_EXIT = false` — off by default): exit if opposite extreme momentum, or M3 DI just crossed against the position with 3-bar accelerating adverse spread `>= 2.0`, but only while progress toward TP `< 20%` (hardcoded).
9. **Session end:** any trade still open when the session becomes invalid is closed at market (`strategy.close`, comment "Session End") and labeled WON/LOST by realized sign.

## 5. Risk Management

Thin by design — the heavyweight risk engine (daily DD, peak-DD trail, loss-streak cooldown, dynamic lots) lives in the MQL5 EA, not in this Pine twin:

- **Position sizing:** fixed `2%` of equity per trade (`default_qty_value=2`, `strategy.percent_of_equity`). No per-trade max-loss USD check (the old spec's "Max Loss 4% of balance" gate was removed).
- **Trade pacing:** max 1 entry per M1 bar; `>= 60 s` between entries; one open position per type/direction (up to 8 concurrent worst case).
- **Sideways circuit breaker:** sideways score `>= 53` blocks all new entries (open trades keep managing).
- **Black Swan protection** (`enableBlackSwanProtection = true`): ATR percentile `> 95.0` over 100 bars arms a 15-bar cooldown flag `isBlackSwanBlocked` — **but this flag is never checked in the entry gate**; it only drives a chart marker. In this Pine file the protection is display-only (the enforcement is in MQL5 `RiskManager`).
- `IGNORE_ALL_RISK_LIMITS` input exists but is referenced nowhere — dead input in the Pine twin.

## 6. Filters & Sessions

- **Sessions (configured in JST, input as HHMM integers; chart time converted via `hour(time, "GMT+9")`):**
  - Tokyo `0850–1200`, London `1300–2030`, NY `2100–2730` (27:30 = 03:30 JST next day; times `<= 0630` are wrapped by +2400 to match the MQL5 cutoff).
  - Bounds are **inclusive** on both ends (`>= start and <= end`).
  - Outside all three windows: no new entries, open trades are force-closed, chart is grayed. `IGNORE_VALID_SESSIONS` (default false) trades 24/7.
- **Day-of-week:** no explicit weekday filter in code (old spec's Mon–Sat rule dropped; weekends are dead market anyway).
- **Sideways filter:** global block `>= 53`; E4 additionally requires `<= 44`.
- **RSI divergence veto** (`enableRSIDivVeto = false` — **off by default**): when on, blocks E1/E2/E4 longs on M3 bearish divergence (split-window: most recent high in M3 bars 1..5 vs bars 6..10, price diff `>= 3.0` pips and RSI diff `>= 3.0` points), and shorts on bullish divergence.
- **Spread:** no live spread feed in TV; SL distances get a buffer of `minSLSpreadMult (0.5) ×` an estimated spread of `3 × syminfo.mintick`. Real spread modeling happens MQL5-side.
- **News filter:** none in this Pine file (MQL5 EA uses the CSV-driven `NewsFilter`). TV backtests of this script include news bars.

## 7. Key Parameters

| Input | Default | What it does |
|---|---|---|
| `minMomentumADX` | 19.5 | M1/M3(/M5) ADX floor used in momentum check and trend-quality pt 1 |
| `requireADXConfluence` | true | Adds M5 to the ADX/DI momentum confluence check (used by early-cut) |
| `emaAlignmentTolerance` | 20.0 pips | Slack on every strict/loose EMA-order comparison |
| `slEMADistance` | 40 pips | Buffer subtracted below/above structure level for E1/E2/E4 SL |
| `sidewaysBlockThreshold` | 53 | Sideways score (0–100) at/above which ALL entries are blocked |
| `e1MomentumBypassLevel` | 1 | 0 = full M1+M3+M5 alignment; 1 = M1 required, M3/M5 bypassable by extreme momentum; 2 = aggressive |
| `minTrendQualityE1 / E2 / E4` | 6 / 9 / 7 | Per-entry trend-quality (0–11) floors |
| `convictionThresholdE1 / E2 / E4` | 7 / 8 / 8 | Conviction (0–12) floors; E1/E2 enforcement on, E4 off |
| `e1MaxCrossAge` | 80 bars | EMA-cross trigger lifetime for E1 |
| `e2MaxTouchAge` | 36 bars | EMA75-touch trigger lifetime for E2 |
| `e4MaxCrossAge` | 28 bars | Ichimoku cloud-cross trigger lifetime for E4 |
| `e1RR / e1RRShort` | 1.7 / 1.7 | E1 take-profit as multiple of SL distance |
| `e2RR / e2RRShort` | 1.5 / 1.5 | E2 R:R |
| `e3RR` | 1.5 | E3 base R:R (×0.9 if score < 9, ×1.1 if score ≥ 12) |
| `e4RR / e4RRShort` | 2.0 / 1.85 | E4 R:R |
| `e1ATRCapMult / e1ATRFloorMult` | 4.0 / 1.2 | E1 SL distance clamp in ATR14(M1) multiples (E2: 3.0/1.1, E4: 4.25/1.25) |
| `e3MinExhaustionScore` | 6 | E3 standard-path exhaustion floor (instant path: 8 long / 7 short, hardcoded) |
| `e3ATRMultiplier` | 3.0 | E3 SL = M3 swing extreme ± this × ATR14(M1) |
| `e3ExtremeLookback` | 9 M3 bars | Window for the E3 swing extreme |
| `e3HTFAlignMode` | 1 | E3 HTF DI alignment: 0=M5, 1=M5 OR M15, 2=M5 AND M15 |
| `e3StrongTrendADX` | 32.0 | M15 ADX at/above which E3 is hard-blocked |
| `e4MaxSidewayScore` | 44 | E4-specific sideways cap (stricter than global) |
| `e4MinMomentumADX` | 20.0 | M1 ADX floor for E4 |
| `e4HTFTrendFilterMode` | 4 | E4 HTF veto: 0=off, 1=M5, 2=M5 AND M15, 3=M5 OR M15, 4=M15 only |
| `e4ChannelRR` / `channelMinQuality` | 3.0 / 5 | Channel-entry R:R and minimum channel quality (0–10) |
| `extremeDISpreadThreshold` | 16.0 | M3 DI spread for the absolute extreme-momentum trigger |
| `extremeRSIThresholdHigh / Low` | 70.5 / 29.5 | M3 RSI extremes for the same trigger |
| `E1..E4_PARTIAL_TP_TRIGGER` | 0.90 / 0.80 / 0.60 / 0.80 | Progress fraction of original TP that arms BE + trailing |
| `E1..E4_TRAILING_FACTOR` | 0.40 / 0.45 / 0.40 / 0.50 | Trail distance as fraction of original TP distance |
| `E1..E4_EARLY_CUT_RATIO` | 0.89 / 0.88 / 0.82 / 0.90 | Fraction of SL distance consumed before momentum-conditional early exit |
| `PRE_BE_TRIGGER_R` | 0.45 | R-multiple that arms pre-BE structure protection |
| `R_MULT_BE_TRIGGER` | 1.0 | R-multiple at which SL moves to entry + 2% of risk |
| `TP_EXTENSION_TRIGGER_PIPS / TP_EXTENSION_PIPS` | 25 / 10 | TP-extension proximity trigger and step |
| `JAPAN/LONDON/NY_START/_END` | 0850–1200 / 1300–2030 / 2100–2730 | Session windows, JST |
| `adxLength / rsiLength` | 14 / 14 | DMI and RSI periods (ATR period 14 is hardcoded) |

## 8. Known Limitations & Notes

- **Black Swan block is not enforced.** `isBlackSwanBlocked` is computed (ATR pctl > 95, 15-bar cooldown) but never appears in any entry condition — chart marker only. Pine results therefore include extreme-volatility entries that the MQL5 EA would block.
- **Early-cut ID bug:** early cut closes via `tradeID4 = _tradeType + " #" + str.tostring(i + 1)` — rebuilt from the *array index*, while real IDs use the global `tradeCounter`. With mixed entry types these diverge, so `strategy.close` can target a nonexistent ID and the early cut silently fails in the strategy engine (the internal status array still flips to `LOST_EARLY`, desynchronizing label stats from strategy results). The momentum exit and session close use the stored `tradeIDs` correctly.
- **Sideway RR inputs are dead.** `e1/e2/e3RRSideway` are never referenced; `e4RRSideway` is referenced only under `sidewaysScore >= 53`, which is unreachable because that score blocks all entries upstream. Same for `IGNORE_ALL_RISK_LIMITS`, the `highConviction*` flags, and `nearEMA75*` (computed, never used — leftovers of an earlier "instant entry" design).
- **No partial closes in Pine.** Partial-TP ratios are bookkeeping only; TV equity will differ from MT5 where real partials execute.
- **No spread/commission realism.** SL spread buffer uses a 3-tick estimate; on XAUUSD real round-trip cost is 30–60 pips. TV PF overstates the deployable edge.
- **Counter-trend exposure (E3):** with regime gate and M1 rotation off by default, E3 is gated only by divergence + exhaustion + HTF DI direction. Long/short instant thresholds are asymmetric (8 vs 7) — intentional per code, but undocumented.
- **E4 channel entries bypass most E4 gates** (sideways-44, HTF veto, ADX floor, conviction) and use hardcoded SL geometry; they also rely on a channel fitted with a 50-bar lookforward window — non-repainting in the strict sense (all data historical at decision time), but the channel only exists ~50 bars after its center, so visual channels appear "back-dated."
- **Ichimoku without displacement:** E4's cloud color/levels use current-bar lead lines, not the +26-shifted cloud plotted by standard Ichimoku — comparisons against a chart Ichimoku overlay will look off by 26 bars.
- **Quirk:** `rsi_3m_bar0` and `rsi_3m_bar1` are both fetched as `ta.rsi(close,14)[1]` (identical values) — a deliberate anti-repaint patch; E3's RSI "bar0 vs EMA" logic therefore effectively compares the same closed bar twice in two slots.
- **Non-M1 charts:** detection/visuals run but all execution is suppressed; the status table prints a warning.
- **Old-spec drift:** the KEM/CHE zone system, Zone-1/3 labels, fixed 5/7-pip SLs, max-loss USD gate, and 09:00/14:00/21:00 session opens from the Nov-2025 spec are all gone. The extensionless file is historical background only.
