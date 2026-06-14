# KenKem Expert — C++ Port & Optimization SPEC

**Status:** Phase 13 (migration in progress). **Source of truth:** `kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5`
(the no-suffix latest, v1.8.15x) + its `Core/`, `Entries/`, `Config/`, `TradeManagement/`, `Utils/` modules.
**Authoritative params:** `Config/InputParams.mqh` (values below are read directly from it — they override any
contradicting code comments). **Do NOT read/cite Pine.**

This is the multi-entry "original" KenKem scalping EA (XAUUSD / BTCUSD, **M1 entry TF**, M3/M5/M15 confirms).
It is ~8k LOC of active signal + trade-management code — the largest port in this repo (cf. KK-MasterVP, Monster).

---

## 0. Port scope (what we port vs skip)

The EA ships with a large optional surface that is **OFF by default**. We port the default-config path only;
everything below is gated off in `InputParams.mqh` and is therefore OUT of the v1 port:

| Feature | Default | Port? |
|---|---|---|
| **E3** (counter-trend reversal) | `ENABLE_E3_ENTRIES=false` | ❌ skip (schema room kept) |
| **E5** (SuperBros EMA align) | `ENABLE_E5_ENTRIES=false` | ❌ skip — user: "SuperBros ≈ E5, ignore" |
| Adaptive learning (coord-descent) | `ENABLE_ADAPTIVE_E*=false` | ❌ skip → use **static input params** |
| News filter | `ENABLE_NEWS_FILTER=false` | ❌ skip |
| Limit orders | `ENABLE_LIMIT_ORDERS=false` | ❌ skip → pure market exec |
| Conservative trade mgmt | `ENABLE_CONSERVATIVE_TRADE_MGMT=false` | ❌ skip → standard partial/trail path |
| Black-swan / peak-decay | cosmetic / rare | ⚠️ defer (note in code) |

**IN scope (v1):** E1, E2, E4 detection + all their gates; the shared trend-quality / momentum / EMA-alignment /
sideways / conviction / RSI-divergence gates; the EMA-cross / EMA75-touch / Ichimoku-cloud-cross triggers; the
indicator cache; risk-based lot sizing; dynamic-RR TP; and the standard tick-fill trade manager (SL/TP, partial
TP, breakeven, trailing, TP extension, laddered extension, panic/score-drop/DI-flip exits, session close).

**Engine:** new `kk::kenkem` namespace under `cpp_core/`, reusing `common/` EMA/ADX/DI/ATR/RSI/Ichimoku math
(the same primitives the mastervp & monster engines share). KK-MasterVP / Monster engines are untouched.

**Determinism & no-lookahead:** every signal reads bar `[ENTRY_SHIFT]` (=`[1]`, the last *closed* bar). Entry
detection fires **once per new M1 bar**. Trade management runs **per tick**. This is the exact discipline that
caught the Monster lookahead bug — replicate the `[1]`-read everywhere and advance the bar with `<` not `<=`.

---

## 1. Timeframes, EMAs, indicator handles

```
TF0=M1  TF1=M3  TF2=M5  TF3=M15  TF4=H1(reserved)   (INPUT_TF0..4; NUM_TF=4, NUM_EMA=5)
EMA0=10 EMA1=25 EMA2=71 EMA3=97 EMA4=192  ← LIVE values (NOT 10/25/75/100/200; enum LABELS are stale)
ENTRY_SHIFT = 1   pipSize: BTCUSD=1.0 (contract=1, std-lot ×2)  XAUUSD=0.01 (contract=100)  ← per-symbol OnInit override
ADX_LEN=14  RSI_LEN=14     ATR_PERIOD_FOR_SL=14
Ichimoku: Tenkan=9 Kijun=26 SenkouB=52  (buffers: 0=SpanA 1=SpanB 2=Tenkan 3=Kijun 4=Chikou; future = shift −26)
```

> **Parity traps locked from real source (see research/hypotheses/kenkem-portnotes/):**
> 1. EMAs are **10/25/71/97/192** — porting 75/100/200 silently diverges.
> 2. **ATR cache reads shift 0** (forming bar) while ADX/DI/RSI/EMA/Ichimoku read shift 1 — replicate the mismatch.
> 3. **BTC pip=1, contract=1, std-lot ×2**; gold pip=10⁻ᵈⁱᵍⁱᵗˢ — sizing breaks otherwise.
> 4. Management early-exits read **forming-bar `iClose/iHigh/iLow(…,0)`** → the tick replay must feed *running* per-bar values, not sealed OHLC, or it leaks the bar outcome.
> 5. **E4-short uses E4_RR_SHORT(1.8)×0.875**, E4-sideway uses E4_RR_SIDEWAY(1.15) — not E4_RR(2.4).

### Indicator cache (rebuilt once per new M1 bar — `UpdateIndicatorCache`)
All reads at `ENTRY_SHIFT=1` unless noted. Field → source:
- `adx[4], diPlus[4], diMinus[4]` — ADX(14)/DI on M1,M3,M5,M15.
- `atrM1, atrM3, atrM5` — ATR(14) on M1/M3/M5 (current bar, shift 0 in MQL but use closed-bar value for parity).
- `ichimokuSpanA/B_M1_Current`, `..._M3_Current` — current cloud (shift 1).
- `ichimokuSpanA/B_M1_Future`, `..._M3_Future` — future cloud (shift −26) — used by trend-quality Ichimoku.
- `ichimokuTenkan_M3, ichimokuKijun_M3, ichimokuChikou_M3, priceM3_26BarsAgo` — E4 quality.
- `hasSufficientBullMomentum / …Bear` — cached `CalculateMomentum` result (see §3.2).
- `currentPrice=close[1]`, `high[1]`, `low[1]`.
- `cachedSidewaysScore` (§3.4), `cachedATRPercentile` (ATR percentile over `ATR_PERCENTILE_LOOKBACK=32`).

---

## 2. Per-bar trigger detection (`UpdateEmaTouches`, once per new M1 bar)

State vars (bar index = `Bars(M1)-1`; `-1` = inactive):
`lastEMACrossingUp/Down` (E1), `lastEma75TouchUp/Down` (E2), `lastIchiCloudCrossUp/Down` (E4).

**E1 — EMA stack cross.** Set `lastEMACrossingUp=currentBar` when a *fresh* bullish alignment appears, i.e. NOT
aligned at shift 2 but aligned at shift 1, on M1 OR M3 OR M5, AND (M1 & M3 both aligned at shift 1). Uses
`isEMAsReadyForEntry` (strict 25>75>100>200 with tolerance, §3.3). Bearish symmetric. Opposite trigger reset to −1.
Plus an **EMA200-touch bonus**: if `low[1] ≤ EMA200 ≤ high[1]` and M1&M3 aligned → arm the same trigger.

**E2 — EMA75 touch.** `ema75=EMA(M1,75,1)`; if `low[1] ≤ ema75 ≤ high[1]`: if `close[1] > ema75` →
`lastEma75TouchUp=currentBar` (reset Down), elif `close[1] < ema75` → `lastEma75TouchDown=currentBar`.

**E4 — Ichimoku cloud cross.** `m1Bull = SpanA_M1 > SpanB_M1`, `m3Bull = SpanA_M3 > SpanB_M3` (cur vs prev bar).
`bothBull = m1Bull && m3Bull`. `crossUp = bothBull_cur && !bothBull_prev` → `lastIchiCloudCrossUp=currentBar`.
Bearish symmetric (`bothBear`). Opposite reset.

Triggers **expire** by age in each entry's `Detect()` (E1 `E1_MAX_CROSS_AGE=80`, E2 `E2_MAX_TOUCH_AGE=36`,
E4 `E4_MAX_CROSS_AGE=20`) and are **consumed** (set −1) on a confirmed detection.

---

## 3. Shared gates

### 3.1 Trend-quality score `GetTrendQualityScore(trend, entryNum)` → 0–11 (+1 ATR), `Core/TrendIdentifier.mqh`
Components (M1 `cache.*[0]` unless noted):
1. **ADX strength** 0–2: `≥25`→2, `≥MIN_MOMENTUM_ADX_REQUIRED(19.7)`→1, else 0.
2. **DI spread** 0–2: dir spread = (BULL: DI+−DI−, BEAR: DI−−DI+); `≥3.0`→2, `≥1.0`→1, else 0.
3. **M1 acceleration** 0–2 (gated by `USE_ACCELERATION_BONUS=true`): 5-bar sustained accel→2, 3-bar→1 (rising ADX + widening DI).
4. **MTF alignment** 0–2: DI direction agreement across M1/M3/M5 — 3/3→2, 2/3→1.
5. **Price action** 0–1: strong trending candle pattern (`HasStrongTrendingPriceActions(trend,M1,5,1)`).
6. **M3 acceleration** 0–1.
7. **Ichimoku** 0–2 — only if `USE_ICHIMOKU_E{n}` (E1=true, E2=false, E4=false): M1 future-cloud color match +
   price vs current cloud + M3 future cloud.
8. **ATR health** 0–1: `cachedATRPercentile ≥ ATR_PERCENTILE_LOW(20.0)`.

**Hard gate (all entries except E5):** if `ENABLE_TREND_QUALITY_GATES=true` and any of {ADX pts, DI pts, MTF pts}
== 0 → return 0 (so a sub-threshold core component blocks the entry).
**Thresholds:** `MIN_TREND_QUALITY_E1=6`, `E2=9`, `E4=9`.

### 3.2 Momentum `HasSufficientMomentum(trend)` → cached `CalculateMomentum` (M1/M3[/M5])
`hasStrength` = ADX≥`E2_MIN_MOMENTUM_ADX(20.0)` on M1 AND M3 (AND M5 if `REQUIRE_ADX_CONFLUENCE=true`).
`directionAligned` = dir DI spread > 0.1 on M1 AND M3 (AND M5 if confluence). Return `strength && aligned`.
- E1 calls it (after its own `cache.adx[0] ≥ E1_MIN_MOMENTUM_ADX(19.5)` pre-check).
- **E2 deliberately does NOT** call it (pullbacks flip M1 DI); gated by trend-quality 9 + HTF + MTF instead.
- E4 uses its own `cache.adx[0] ≥ E4_MIN_MOMENTUM_ADX(19.75)` check, not this.

### 3.3 EMA alignment `isAllTimeframeEMAsReadyForEntry(entry,isLong,shift)`
Base `isEMAsReadyForEntry(isLong,tf,shift,strict)`: with `tol=EMA_ALIGNMENT_TOLERANCE_PIPS(23.0)*pipSize`,
LONG = `e25>e75−tol && e75>e100−tol && (!strict || e100>e200−tol)`; SHORT symmetric.
- **E1:** `m1_strict && m3_strict && m5_directional`, with **momentum bypass** by `E1_MOMENTUM_BYPASS_LEVEL=1`:
  L1 = `m1 && ((m3 && m5) || extremeMom)`, where `extremeMom` = dir DI spread ≥ `EXTREME_DI_SPREAD_THRESHOLD(16.0)`.
- **E2/E4 path:** `m1 && m3 && m5` all strict (E4 additionally has its own explicit 3-stack M1+M3 checks, below).

### 3.4 Sideways `GetSidewaysScore()` → 0–100 (`cachedSidewaysScore`), block if `≥ SIDEWAYS_BLOCK_THRESHOLD(53)`
Components: EMA convergence (≤25, via `EMA_SPREAD_TIGHT/MODERATE/WIDE_ATR` = 1.75/3.25/4.0 ×ATR), ADX weakness
(≤25), DI indecision (≤20), RSI neutral (≤15), ATR compression (≤15). `IsInExtremeSidewayRange()` =
`score ≥ 53`; `IsInSidewayRange()` = `43 ≤ score < 53` (selects sideway RR).

### 3.5 RSI divergence veto `HasRSIDivergenceAgainstTrade` (`ENABLE_RSI_DIVERGENCE_VETO=true`)
M3, `RSI_DIV_LOOKBACK=16`, split-window peak/trough. LONG blocked if price HH ≥ `RSI_DIV_MIN_PRICE_DIFF_PIPS(60)`
while RSI LH ≥ `RSI_DIV_MIN_RSI_DIFF(6.5)`. SHORT symmetric (LL / HL).

### 3.6 Conviction `CalculateConvictionScore(isLong,type,enabled,htfVeto)` → 0–12 (`Entries/EntryHelpers.mqh`)
Only applied when `USE_CONVICTION_SCORING_E{n}` (E1=T thr 7, E2=T thr 10, E4=T thr 9). HTF veto (if enabled,
all OFF by default) returns −999 if confirmation-TF EMA75 vs EMA100 opposes trade. Six 0–2 components:
M1 DI spread (≥3→2,≥1→1); EMA stack separation (`Calculate4EMAStackSeparation`: avg gap/30 pips, ordered else 0;
≥0.8→2,≥0.5→1); RSI quality (M1/M3 vs 50 + velocity>1.5); ADX (≥23→+1,<15→−1; accel→+1; clamp 0–2);
M3+M5 confluence (strong=ADX≥22&spread≥2, support=ADX≥16&spread>0.5); price-action (2/3 bars). Below threshold →
low-confidence → skipped (unless `SEND_LOW_CONFIDENCE_SIGNALS`).

---

## 4. Entry detection (dispatch order E1 → E2 → E4, first match wins, mutually exclusive)

Pre-entry global gates (ALL must pass, else no detection this bar): `inValidSession`,
`!IsInExtremeSidewayRange`, `!IsBlockedByLosingStreak`, drawdown not blocked, `bars ≥ ENTRY_SHIFT+2`.
Per-entry guard: `sessionLossCount < MAX_SESSION_LOSSES(4)` and `tradeSLTPCountInSession ≤ MAX_SLTP_COUNT_PER_SESSION(7)`.
`currentPrice = close[1]`. `recentHigh/Low` = Hi/Lo over `RANGE_HI_LOW_LOOK_BACK_BARS(18)` from shift 1.

### E1 — Trend continuation (EMA stack cross)
Trigger active (`lastEMACrossingUp/Down`, age ≤ 80) AND no open L/S-E1. Conditions:
1. `cache.adx[0] ≥ E1_MIN_MOMENTUM_ADX(19.5)`.
2. HTF filter `E1_HTF_TREND_FILTER=HTF_M5_ONLY` (min ADX 18.5, min DI spread 4.0): block long if M5 bearish (valid), etc.
3. `isAllTimeframeEMAsReadyForEntry("E1",…)` (§3.3, with bypass).
4. Price vs EMA25: long needs `close[1] > EMA(M1,25,1)`.
5. `GetTrendQualityScore(trend,1) ≥ 6` (hard block).
6. `HasSufficientMomentum(trend)` (hard block).
7. `!HasRSIDivergenceAgainstTrade`.
**SL:** `e1SLLevel = EMA100 ∓ 0.75·|EMA100−EMA200|` (long −, short +); `CalculateStopLossWithCustomEMA` →
`base = min(recentLow, e1SLLevel)` (long); `structuredStop = base − SL_EMA_DISTANCE(27)·pip`; **ATR arbitration**
(`E1_USE_ATR_SL_ARBITRATION=true`): clamp |entry−SL| in pips to `[ATR·1.2, ATR·4.0]`; then spread buffer
(`MIN_SL_SPREAD_MULT=0.5`). **TP:** `entry ± slDist·rr` with rr from setMaxTPForTrade (§5).

### E2 — Pullback (EMA75 touch)
Trigger `lastEma75Touch*` (age ≤ 36) AND no open L/S-E2. Conditions:
1. HTF filter `E2_HTF_TREND_FILTER=HTF_M15_ONLY` (min ADX 23.0, min DI spread 3.0) — **requires** aligned strong
   HTF (blocks weak too, unlike E1).
2. `isAllTimeframeEMAsReadyForEntry("E2",…)` (all-TF strict).
3. Price vs EMA25.
4. `GetTrendQualityScore(trend,2) ≥ 9` (hard block). (No `HasSufficientMomentum` — see §3.2.)
5. `!HasRSIDivergenceAgainstTrade`.
**SL:** `CalculateStopLoss(…, EMA3=EMA100, "E2", 2)` → base = min(recentLow, EMA100); −27pip; ATR arbitration
`[ATR·1.1, ATR·3.0]`; spread buffer. **TP** as §5.

### E4 — Ichimoku cloud cross (early trend)
Trigger `lastIchiCloudCross*` (age ≤ 20) AND no open L/S-E4. Conditions:
1. `CheckIchimokuQuality`: cloud thickness ≥ `E4_MIN_CLOUD_THICKNESS_ATR_MULT(0.11)·atrM3`; Tenkan/Kijun aligned
   (`E4_REQUIRE_TENKAN_KIJUN_ALIGN=true`); Chikou clear (`E4_REQUIRE_CHIKOU_CLEAR=false` → skip).
2. `cachedSidewaysScore ≤ E4_MAX_SIDEWAY_SCORE(40)` (stricter than global 53).
3. HTF filter `E4_HTF_TREND_FILTER=HTF_M5_OR_M15` (min ADX 20.5, min DI spread 6.0).
4. `E4_REQUIRE_M5_DI_ALIGN=true`: M5 DI must match dir (unless M5 ADX < `ADX_LOW_THRESHOLD(14.5)`).
5. M1 3-stack `25>75>100`; M3 3-stack `25>75>100` OR extreme momentum (`E4_MOMENTUM_BYPASS_LEVEL=1`).
6. Price vs EMA25 **and** cloud top/bottom, with 5-pip tolerance.
7. `cache.adx[0] ≥ E4_MIN_MOMENTUM_ADX(19.75)`.
8. `GetTrendQualityScore(trend,4) ≥ 9` (hard block).
9. `!HasRSIDivergenceAgainstTrade`.
**SL:** identical to E1 (EMA100 ∓0.75·gap; ATR arbitration `[ATR·1.25, ATR·4.0]`). **TP:** uses `E4_RR_SIDEWAY(1.15)`
if `IsInSidewayRange` else dynamic-RR(§5) on `E4_RR(2.4)`.

---

## 5. TP / dynamic-RR / sizing

**`setMaxTPForTrade(trade, aggressive)`** (final TP): `risk=|entry−SL|`. Base `rr` = per-entry RR
(E1=1.9 / sideway 1.2; E2=1.575 / 1.1; E4=2.4 / sideway 1.15) — sideway when `IsInSidewayRange()`.
`rr *= GetDynamicRRMultiplier()` (`USE_DYNAMIC_RR_SCALING=true`): session × ATR-pctile, clamped [0.70,1.30]
(Asia 0.95, EU 1.0, US 1.15; ATR-pctile ≥75→×1.12, ≤25→×0.88). `aggressive` (US session & M3 ADX≥30) ×
per-entry `GetRRBoostMultiplier` (E1 1.08, E2 1.04, E4 1.02). `TP = entry ± rr·risk`.

**Lot sizing** (`getMaxLossUSD` × `getScaledLotSize`): per-entry risk ratio (E1 2.1%, E2 2.0%, E4 2.04% of
balance; `COMMON_MAX_RISK_PER_TRADE=0.02`) → `maxLossUSD`, capped by daily-loss-room & DD-room, floored at
`MIN_RISK_FLOOR_RATIO(0.5%)`. `lots = min(maxLossUSD/(slDist·contractSize), marginCap, scaledLot)`. Profit
scaling (`INCREASE_LOT_SIZE_BASED_ON_PROFIT=true`, weights 0.65/0.35) grows base lot when balance > initial.
`MY_STANDARD_LOT_SIZE=0.15`, `contractSize=100`. **Port note:** model risk-based lot + profit scaling
(materially affects $PnL); the recovery/soft-block/profit-protection lot *multipliers* are second-order (rare) —
include as flags, default inactive.

---

## 6. Trade management (per tick, `ProcessAllTrades`) — standard path

Order per open trade (skip entry bar): broker-fill check → **SL/TP fill** → pre-BE structure protection →
partial-TP → R-multiple BE → TP extension → trailing → laddered → early-cut / panic / score-drop / DI-flip exits.
**Fill prices (backtest):** SL hit when LONG `low ≤ SL` / SHORT `high ≥ SL`; TP hit when LONG `high ≥ TP` /
SHORT `low ≤ TP`. Exit price = the level (model spread on exit; commission per side).

- **Partial TP** (`ALLOW_PARTIAL_TP=true`): eligible when profit ≥ `partialTPTrigger·(TP−entry)` (E1 .90/E2 .70/
  E4 .70). Non-E5 requires trend-weakening OR retrace ≥ `PARTIAL_TP_RETRACE_RATIO(0.15)` from best. Close
  `partialTPRatio` (E1 .20/E2 .25/E4 .20). After: SL → entry ± `breakevenBuffer·(TP−entry)` (E* `SL_TO_BREAKEVEN_BUFFER`=.07).
- **R-multiple BE** (`R_MULT_BE_TRIGGER=0.87`): at profit ≥ 0.87·risk, SL → entry ± `R_MULT_BE_BUFFER(0.055)·risk` (once).
- **TP extension** (`ALLOW_TP_EXTENSION=true`): when within trigger pips of TP and progress ≥
  `MIN_TP_PROGRESS_FOR_EXTENSION(0.92)` and trend not weakening: `extPips = clamp(atrM1·ATR_TP_EXTENSION_MULTIPLIER(0.035),
  7, 60)`; `trigger = 2·extPips`; extend TP by extPips up to `maxTPExtensions` (E1 40/E2 30/E4 30); re-trail.
- **Trailing** (after partial-eligible): `dist = (TP−entry)·trailingFactor/(tpExt+1)·volMult`;
  `SL = best ∓ dist` (only tighten). `trailingFactor` E1 .40/E2 .45/E4 .50.
- **Laddered** (`E*_ENABLE_LADDERED_EXTENSIONS=true`, after partial): stage targets ×{E1 1.05/1.11/1.17,
  E2 1.04/1.09/1.14, E4 1.10/1.18/1.27}; trail ratios per stage. (Impl partial in EA — model as documented.)
- **Panic ADX exit** (`ENABLE_FAST_ADX_PANIC_EXIT_E{1,2,4}=true`): if (post-partial profit giveback ≥
  `PANIC_MIN_PROFIT_GIVEBACK(0.5)`) OR (loss with SL-used ≥ `PANIC_MIN_SL_USED_RATIO(0.6)`), AND M1+M3 both
  show accelerating *reversed* trend → close.
- **Score-drop exit** (`ENABLE_SCORE_DROP_EXIT`: E1 off / E2 on thr 2 / E4 on thr 3): momentum score drops ≥ thr
  for `SCORE_DROP_CONSECUTIVE_CHECKS(3)` bars, when post-partial or floating < 10% → close.
- **DI-flip exit** (all OFF default) and **ADX-drop exit** (OFF) and **early-cut** (`ENABLE_EARLY_CUT_NEAR_SL=false`) → skip.
- **Session close** (`CLOSE_ALL_TRADES_AT_SESSION_END=true`): close all at NY session end window.

---

## 7. Sessions (JST server time, from InputParams)
`JAPAN 900–1230`, `LONDON 1400–1830`, `NY 2100–2400`. Valid-session gate uses these (unless
`IGNORE_VALID_SESSIONS`). Dynamic-RR session classification (Asia/EU/US) and session-close use the same windows.
**Confirm the broker server↔JST offset against the imported tick timestamps before trusting session gates.**

---

## 8. Backtest engine plan (`cpp_core/include/kk/kenkem/`, `tools/kenkem/`, `tests/kenkem/`)
1. `kenkem_config.hpp` — full input schema (defaults above) + `.set` loader (InpXxx names).
2. `indicator_cache.hpp` — per-bar M1/M3/M5/M15 ADX/DI/ATR/RSI/Ichimoku + sideways + ATR-pctile, `[1]` reads.
3. `triggers.hpp` — EMA-cross / EMA75-touch / Ichi-cloud-cross state machine (§2).
4. `gates.hpp` — trend-quality, momentum, EMA-align, conviction, RSI-div, HTF filters (§3).
5. `entries.hpp` — E1/E2/E4 `Detect()` + SL formulas (§4).
6. `trade_manager.hpp` — tick-fill + partial/BE/trail/ext/ladder/panic/score-drop (§6).
7. `kenkem_engine.hpp` — interleaved OnTick integrator (new-bar detect + per-tick manage), risk-based sizing (§5).
8. `kenkem_backtester.cpp` + `test_kenkem_*` — unit tests per indicator/gate/entry + **lookahead audit**.

**Parity is a HARD GATE before optimization** (same standard as KK-MasterVP / Monster). KenKem ships no `Parity/`
module yet, so we ADD one — mirroring `KK-MasterVP/Parity/{ParityExport,TradeJournal}.mqh`: a new
`KenKem/Parity/` subdir + ~6 `InpExportParity`-gated (default-OFF) hooks in `KenKemExpert.mq5` (OnInit init,
per-bar `WriteParityRow` after `UpdateIndicatorCache`, OnDeinit close, trade-close → journal). This is
**additive, read-only instrumentation** (no trading-logic change, no clobber) — distinct from the "never rewrite
the EA's logic / deliver `.set` only" rule. Parity CSV (per-bar) columns mirror the C++ engine's surface:
`barTimeUTC, adxM1/M3/M5/M15, diPlusM1.., diMinusM1.., atrM1/M3/M5, ichiSpanA/B_M1/M3, tenkanM3, kijunM3,
sideways, trendQ_E1/E2/E4, trigE1/E2/E4(state), e{1,2,4}Detected, isLong, entry, sl, tp`. Trade journal mirrors
per-trade entry/exit/PnL.
**Workflow:** (1) build C++ engine + a `tools/kenkem/parity_driver.cpp` emitting the same CSV format; (2) user
compiles + runs KenKem in MT5 Strategy Tester (`InpExportParity=true`) → reference CSVs land in
`kenkem/Tester/.../MQL5/Files/KenKem/`; (3) diff bar-level (indicators/scores) then trade-level until parity
(MasterVP reached 377/473 exact); (4) only THEN baseline + optimize. Deliver winning configs as non-destructive
`.set` files in `kenkem/MQL5/Experts/KenKem/Config/`. MT5 demo forward-test remains the final live gate.

## 9. Optimization plan (Phase 13, after engine + tests + baseline)
Optuna joint search over the high-leverage knobs per symbol (BTC, XAU): per-entry RR + sideway RR, trend-quality
mins (E1/E2/E4), `E*_MIN_MOMENTUM_ADX`, HTF filter thresholds, SL ATR cap/floor, `SL_EMA_DISTANCE`,
partial-TP trigger/ratio, trailing factor, `R_MULT_BE_TRIGGER`, sideways block threshold, `MIN_ENTRY_ATR_PERCENTILE`,
entry enable toggles. Refine from strong-OOS **sub-cluster median** (plateau, not lone peak); MC + rolling
robustness per symbol; write `best_kenkem_{btc,xau}.set`. Same protocol as MONSTER-FINDINGS.
