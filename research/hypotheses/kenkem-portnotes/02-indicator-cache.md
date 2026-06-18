# KenKem Port Notes — 02: Indicator Cache & Indicator Math

**Scope:** byte-level parity mapping of the MQL5 indicator cache (`CachedIndicators`) and every indicator
buffer read for porting to `cpp_core`. Source repo: `kenkem`. Reading mode: `ENTRY_SHIFT = 1` (last
closed bar). Multi-TF: `TF0=M1, TF1=M3, TF2=M5, TF3=M15, TF4=H1` (H1 reserved/inactive; `NUM_TF=4`).

> **#1 risk = shift indices.** This doc quotes every CopyBuffer shift verbatim. The two genuinely
> dangerous spots are: (a) **all cache ADX/DI/ATR/superTrend/momentum reads use shift=`ENTRY_SHIFT`(=1)
> EXCEPT the ATR CopyBuffers which use shift=0**, and (b) **Ichimoku "Future cloud" reads use
> `CopyBuffer(..., -26, ...)`** — a negative shift that reads cloud values plotted 26 bars into the
> future. See LOOKAHEAD AUDIT.

---

## 0. Source files & key params

| Param | Value | Source |
|---|---|---|
| `ENTRY_SHIFT` | `1` | `Config/InputParams.mqh:182` |
| `ADX_LEN` | `14` | `Config/InputParams.mqh:545` |
| `RSI_LEN` | `14` | `Config/InputParams.mqh:544` |
| ADX-short period | `9` (hardcoded literal) | `KenKemExpert.mq5:302` |
| `ICHIMOKU_TENKAN` | `9` | `Config/InputParams.mqh:132` |
| `ICHIMOKU_KIJUN` | `26` | `Config/InputParams.mqh:133` |
| `ICHIMOKU_SENKOU` (Span B) | `52` | `Config/InputParams.mqh:134` |
| ATR period (all TFs) | `14` (hardcoded literal) | `KenKemExpert.mq5:315,321,327` |
| `ATR_PERCENTILE_LOOKBACK` | `32` | `Config/InputParams.mqh:153` |
| `SIDEWAYS_BLOCK_THRESHOLD` | `53` | `Config/InputParams.mqh:142` |
| `SIDEWAYS_WARNING_THRESHOLD` | `43` | `Config/InputParams.mqh:143` |
| `EMA_SPREAD_TIGHT_ATR` | `1.75` | `Config/InputParams.mqh:146` |
| `EMA_SPREAD_MODERATE_ATR` | `3.25` | `Config/InputParams.mqh:147` |
| `EMA_SPREAD_WIDE_ATR` | `4.0` | `Config/InputParams.mqh:148` |

### EMA periods — ENUM NAMES LIE, USE THE INPUT DEFAULTS

The enum/constants (`GlobalState.mqh:173,185-189`) are named `EMA_10/25/75/100/200`, but the **actual
periods used** come from `EMA_PERIOD_ARRAY[]`, populated in OnInit from these inputs:

| Slot | Constant name suggests | **Actual default period** | Source |
|---|---|---|---|
| EMA0 (fast) | 10 | **10** | `InputParams.mqh:689` `INPUT_EMA0_PERIOD = 10` |
| EMA1 (signal) | 25 | **25** | `InputParams.mqh:690` `INPUT_EMA1_PERIOD = 25` |
| EMA2 (pullback) | 75 | **71** | `InputParams.mqh:691` `INPUT_EMA2_PERIOD = 71` |
| EMA3 (bounce) | 100 | **97** | `InputParams.mqh:692` `INPUT_EMA3_PERIOD = 97` |
| EMA4 (anchor) | 200 | **192** | `InputParams.mqh:693` `INPUT_EMA4_PERIOD = 192` |

**Parity warning:** porting with 75/100/200 will diverge. Use **10/25/71/97/192** unless the `.set`
file overrides these. (The historical-scan helper `InitializeEMAFlagsFromHistory` in `EMAHelpers.mqh`
hardcodes `EMA_25/EMA_75/EMA_100/EMA_200` enum *indices* — those are array indices, not periods.)

---

## 1. The `CachedIndicators` struct (verbatim fields)

Defined in `Core/GlobalState.mqh:281-328`. Global instance `cache` at `GlobalState.mqh:329`.

```
struct CachedIndicators {
    // ADX(14) values [M1, M3, M5, M15]
    double adx[4];          // GlobalState.mqh:283
    double diPlus[4];       // :284
    double diMinus[4];      // :285
    // ADX(9) values for micro-trend detection (M1 only)
    double adxShort;        // :287
    double diPlusShort;     // :288
    double diMinusShort;    // :289
    // M3 historical data for E3 exhaustion (updated once per M3 bar)
    double rsiM3[6];        // :291  [0]=current ... [5]=oldest
    double adxM3[6];        // :292
    double diPlusM3[6];     // :293
    double diMinusM3[6];    // :294
    bool   m3HistoryValid;  // :295
    // Common price points
    double currentPrice;    // :297
    double prevPrice;       // :298
    double high;            // :299
    double low;             // :300
    // Momentum results
    bool hasSufficientBullMomentum;  // :302
    bool hasSufficientBearMomentum;  // :303
    TREND_STATE superTrendE1;        // :304
    TREND_STATE superTrendE2;        // :305
    // Ichimoku Cloud values (M1 and M3)
    double ichimokuSpanA_M1_Current; // :307
    double ichimokuSpanB_M1_Current; // :308
    double ichimokuSpanA_M1_Future;  // :309
    double ichimokuSpanB_M1_Future;  // :310
    double ichimokuSpanA_M3_Current; // :311
    double ichimokuSpanB_M3_Current; // :312
    double ichimokuSpanA_M3_Future;  // :313
    double ichimokuSpanB_M3_Future;  // :314
    // E4 quality filters (M3 only)
    double ichimokuTenkan_M3;        // :316
    double ichimokuKijun_M3;         // :317
    double ichimokuChikou_M3;        // :318
    double priceM3_26BarsAgo;        // :319
    // ATR values (period 14)
    double atrM1;                    // :321
    double atrM3;                    // :322  (E4 cloud + E5 multi-TF sideway)
    double atrM5;                    // :323  (E5 multi-TF sideway)
    // Trend weakening detection
    bool isTrendWeakeningBull;       // :325
    bool isTrendWeakeningBear;       // :326
    bool valid;                      // :327
};
```

Module-level (not in struct) but cache-adjacent:
- `double cachedATRPercentile = 50.0;` — `GlobalState.mqh:467`
- `int cachedSidewaysScore = 0;` — `Core/TrendIdentifier.mqh:470`

---

## 2. Indicator HANDLES (creation, OnInit) — `KenKemExpert.mq5`

```
:292  emaHandles[tf][ema] = iMA(_Symbol, TF_ARRAY[tf], EMA_PERIOD_ARRAY[ema], 0, MODE_EMA, PRICE_CLOSE);
:298  adxHandles[tf]      = iADX(_Symbol, TF_ARRAY[tf], ADX_LEN);            // ADX_LEN=14, tf=0..3
:302  adxShortHandle      = iADX(_Symbol, TF_ARRAY[TF0], 9);                // M1 ADX(9)
:305  rsiHandle           = iRSI(_Symbol, TF_ARRAY[TF0], RSI_LEN, PRICE_CLOSE);  // M1 RSI(14)
:310  ichimokuHandles[0]  = iIchimoku(_Symbol, TF_ARRAY[TF0], 9, 26, 52);   // M1
:311  ichimokuHandles[1]  = iIchimoku(_Symbol, TF_ARRAY[TF1], 9, 26, 52);   // M3
:315  g_atrM1Handle       = iATR(_Symbol, TF_ARRAY[TF0], 14);
:321  g_atrM3Handle       = iATR(_Symbol, TF_ARRAY[TF1], 14);
:327  g_atrM5Handle       = iATR(_Symbol, TF_ARRAY[TF2], 14);
```

- **EMA** = `MODE_EMA`, `PRICE_CLOSE`, shift param `0` (no built-in shift). → C++ `kk::ind::ema(close, period)`.
- **ADX/DI** = MT5 `iADX` (Wilder-smoothed-but-MT5-variant). → C++ **`dmi_adx_mt5`**, NOT textbook `dmi_adx`.
- **RSI** = `iRSI`, `PRICE_CLOSE`. → `kk::ind::rsi`.
- **ATR** = `iATR(...,14)` = Wilder RMA of true range. → `kk::ind::atr` (period 14).
- **Ichimoku** = `iIchimoku(9,26,52)`.

MT5 `iADX` / `iIchimoku` / `iATR` buffer index conventions (load-bearing for CopyBuffer below):
- **iADX buffers:** `0 = MAIN (ADX)`, `1 = +DI (PLUSDI_LINE)`, `2 = -DI (MINUSDI_LINE)`.
- **iIchimoku buffers:** `0 = TENKANSEN`, `1 = KIJUNSEN`, `2 = SENKOUSPANA`, `3 = SENKOUSPANB`, `4 = CHIKOUSPAN`.
  > **NOTE the offset in this code:** for the *cache* fields, the code reads Ichimoku buffer `0` as
  > SpanA and buffer `1` as SpanB (see §5) — i.e. it treats buffer 0/1 as the cloud spans, NOT as
  > Tenkan/Kijun. This is non-standard relative to the MT5 buffer table above and MUST be replicated
  > exactly. For Tenkan/Kijun/Chikou it reads buffers `2/3/4`. Treat the buffer→meaning mapping below
  > as the source of truth; do not "correct" it to the MT5 docs.

---

## 3. CACHE POPULATION — `UpdateIndicatorCache()` (`KenKemExpert.mq5:669-843`)

Guard: `if (lastCachedBar == currentBar && cache.valid) return;` (`:672`). `currentBar = Bars(M1)-1` (`:671`).

### 3a. Price (shift 0 = CURRENT/forming bar)
```
:677  cache.currentPrice = iClose(_Symbol, TF_ARRAY[TF0], 0);   // forming bar
:678  cache.prevPrice    = iClose(_Symbol, TF_ARRAY[TF0], 1);
:679  cache.high         = iHigh (_Symbol, TF_ARRAY[TF0], 0);   // forming bar
:680  cache.low          = iLow  (_Symbol, TF_ARRAY[TF0], 0);   // forming bar
```

### 3b. ADX(14) + DI per TF — shift = ENTRY_SHIFT (=1)
```
:685  for (int i = 0; i < NUM_TF; i++) {
:686      cache.adx[i]     = getADXValue(TF_ARRAY[i], ENTRY_SHIFT);
:687      cache.diPlus[i]  = getDIPlus  (TF_ARRAY[i], ENTRY_SHIFT);
:688      cache.diMinus[i] = getDIMinus (TF_ARRAY[i], ENTRY_SHIFT);
:689  }
```
Underlying reads (`ADXRSIHelpers.mqh`), all `ArraySetAsSeries(buf,true)`, count=1:
```
:28   CopyBuffer(adxHandles[arrayIndex], 0, shift, 1, adxBuffer)     // getADXValue  -> buffer 0 = ADX
:48   CopyBuffer(adxHandles[arrayIndex], 1, shift, 1, diPlusBuffer)  // getDIPlus    -> buffer 1 = +DI
:68   CopyBuffer(adxHandles[arrayIndex], 2, shift, 1, diMinusBuffer) // getDIMinus   -> buffer 2 = -DI
```

### 3c. ADX(9) short — shift = ENTRY_SHIFT (=1)
```
:692  cache.adxShort      = getADXValueByPeriod(TF_ARRAY[TF0], 9, ENTRY_SHIFT);
:693  cache.diPlusShort   = getDIPlusByPeriod  (TF_ARRAY[TF0], 9, ENTRY_SHIFT);
:694  cache.diMinusShort  = getDIMinusByPeriod (TF_ARRAY[TF0], 9, ENTRY_SHIFT);
```
`getADXValueByPeriod` with period 9 → `handle = adxShortHandle`; CopyBuffer buffers 0/1/2 at `shift`
(`ADXRSIHelpers.mqh:494,513,532`).

### 3d. ATR — **shift = 0** (count=1) — DIVERGES from ENTRY_SHIFT
```
:711  CopyBuffer(g_atrM1Handle, 0, 0, 1, atrBuffer) -> cache.atrM1
:718  CopyBuffer(g_atrM3Handle, 0, 0, 1, atrBuffer) -> cache.atrM3
:725  CopyBuffer(g_atrM5Handle, 0, 0, 1, atrBuffer) -> cache.atrM5
```
> ⚠ **ATR cache reads shift 0 (forming bar), not ENTRY_SHIFT.** ATR(14)=Wilder RMA, so the forming
> bar's ATR updates intra-bar with the live high/low/close. For deterministic backtest parity the C++
> engine must replicate "ATR at shift 0 = ATR including the current forming bar's range so far." If the
> C++ engine only steps bar-by-bar on closes, atrM1 should be the ATR of the *current* (not previous)
> bar. This is the single biggest non-ENTRY_SHIFT read in the cache. See LOOKAHEAD AUDIT.

### 3e. Momentum / weakening / supertrend (computed, not raw CopyBuffer)
```
:697  cache.hasSufficientBullMomentum = CalculateMomentum(TREND_BULL);
:698  cache.hasSufficientBearMomentum = CalculateMomentum(TREND_BEAR);
:702  cache.isTrendWeakeningBull = CalculateTrendWeakening(TREND_BULL);
:703  cache.isTrendWeakeningBear = CalculateTrendWeakening(TREND_BEAR);
:706  cache.superTrendE1 = CalculateSuperTrendForEntry("E1");
:707  cache.superTrendE2 = CalculateSuperTrendForEntry("E2");
```
(Bodies live in `TrendIdentifier.mqh`/entry helpers — out of scope for this doc; they consume the
ADX/DI/RSI reads above. Map separately in port notes 03.)

### 3f. M3 history for E3 (once per M3 bar) — **shift 0, count=6**
Gated `ENABLE_E3_ENTRIES && currentM3Bar != lastCachedM3Bar`, `currentM3Bar = currentBar/3` (`:778`).
```
:785  rsiHandlesTF[1] = iRSI(_Symbol, TF_ARRAY[TF1], 14, PRICE_CLOSE);   // M3 RSI(14)
:793  CopyBuffer(rsiHandlesTF[1], 0, 0, 6, rsiBuffer)   -> cache.rsiM3[0..5]
:806  CopyBuffer(adxHandles[1],   0, 0, 6, adxBuffer)    -> cache.adxM3[0..5]
:807  CopyBuffer(adxHandles[1],   1, 0, 6, diPlusBuffer) -> cache.diPlusM3[0..5]
:808  CopyBuffer(adxHandles[1],   2, 0, 6, diMinusBuffer)-> cache.diMinusM3[0..5]
```
All `ArraySetAsSeries(...,true)`; `[0]`=latest (forming M3 bar), `[5]`=oldest. **Read at shift 0**, so
index `[0]` includes the forming M3 bar.

### 3g. Derived caches at end
```
:835  cachedATRPercentile = CalculateATRPercentile(cache.atrM1, ATR_PERCENTILE_LOOKBACK);  // lookback 32
:839  UpdateSidewaysScoreCache();   // -> cachedSidewaysScore = GetSidewaysScore(ENTRY_SHIFT)
:841  cache.valid = true;  :842 lastCachedBar = currentBar;
```

---

## 4. ADX / RSI helper confirmation (`ADXRSIHelpers.mqh`)

- **ADX is MT5 `iADX`** (handle from `iADX(...,14)` / `iADX(...,9)`), NOT a custom Wilder DMI. Buffer
  indices: **ADX=0, +DI=1, -DI=2** (confirmed at lines 28/48/68, 184-186, 364-365, 447/460/473,
  591-593). → C++ `dmi_adx_mt5`.
- **RSI** = `iRSI(_Symbol, tf, period, PRICE_CLOSE)` (`:138,254,341,785`); buffer `0`. Default period
  `RSI_LEN=14`; multi-period RSI confluence (`HasRSIConfluence`) can request other periods via cached
  per-TF handles `rsiHandlesTF[]`.
- DI buffer reads for confluence/acceleration use the same `1`=+DI / `2`=-DI convention with
  `count=lookbackBars` at `shift=entryShift` (e.g. `:591-593` `HasADXConfluence`,
  `:364-365` `HasDISpreadDeceleration` at **shift 0**, `:302-305` `HasTrendAcceleration` at **shift 0**).

---

## 5. ICHIMOKU reads — `UpdateIndicatorCache` (`KenKemExpert.mq5:731-775`)

Gated `if (USE_ICHIMOKU_E1 || USE_ICHIMOKU_E2 || ENABLE_E4_ENTRIES)`. `tempBuffer` dynamic,
`ArraySetAsSeries(true)`, count=1. **Buffer 0 is read as Span A, buffer 1 as Span B** (see §2 caveat).

| Cache field | Handle | Buffer | Shift | Line |
|---|---|---|---|---|
| `ichimokuSpanA_M1_Current` | `ichimokuHandles[0]` (M1) | 0 | `ENTRY_SHIFT` (1) | `:738` |
| `ichimokuSpanB_M1_Current` | `ichimokuHandles[0]` | 1 | `ENTRY_SHIFT` (1) | `:740` |
| `ichimokuSpanA_M1_Future`  | `ichimokuHandles[0]` | 0 | **`-26`** | `:744` |
| `ichimokuSpanB_M1_Future`  | `ichimokuHandles[0]` | 1 | **`-26`** | `:746` |
| `ichimokuSpanA_M3_Current` | `ichimokuHandles[1]` (M3) | 0 | `ENTRY_SHIFT` (1) | `:750` |
| `ichimokuSpanB_M3_Current` | `ichimokuHandles[1]` | 1 | `ENTRY_SHIFT` (1) | `:752` |
| `ichimokuSpanA_M3_Future`  | `ichimokuHandles[1]` | 0 | **`-26`** | `:756` |
| `ichimokuSpanB_M3_Future`  | `ichimokuHandles[1]` | 1 | **`-26`** | `:758` |
| `ichimokuTenkan_M3` | `ichimokuHandles[1]` | 2 | `ENTRY_SHIFT` (1) | `:764` (gated `ENABLE_E4_ENTRIES`) |
| `ichimokuKijun_M3`  | `ichimokuHandles[1]` | 3 | `ENTRY_SHIFT` (1) | `:767` |
| `ichimokuChikou_M3` | `ichimokuHandles[1]` | 4 | `ENTRY_SHIFT` (1) | `:770` |
| `priceM3_26BarsAgo` | — | `iClose(_Symbol, TF1, ENTRY_SHIFT+26)` = shift **27** | `:773` |

**Current cloud vs Future cloud distinction (parity-critical):**
- **Current cloud** = `CopyBuffer(handle, 0/1, ENTRY_SHIFT, 1, ...)` → shift `+1`, the Senkou spans as
  plotted at the last closed bar (these are values the indicator computed `kijun=26` bars ago and
  projected forward to "now"). Used by E4 cross detection for Pine parity.
- **Future cloud** = `CopyBuffer(handle, 0/1, -26, 1, ...)` → **negative shift** reads the spans plotted
  26 bars ahead of the current bar (the leading edge of the cloud). In MT5 the Senkou buffers are
  forward-shifted by `kijun_period`, so shift `-26` is a *legitimate* read of already-computed values
  (no raw future price), used for trend-quality scoring. **Do not** interpret `-26` as a price lookahead;
  it is the projected cloud. The C++ Ichimoku must expose both "current/plotted-now" and
  "leading-span (+26)" outputs and the port must map `-26` → leading span at bar `t`.

Previous-bar cloud reads for E4 cross detection live in `EMAHelpers.mqh:335-339` (current-cloud,
buffers 0/1, shift `ENTRY_SHIFT+1` = 2). All M1 and M3 prev-cloud reads use **current** cloud (buffers
0/1 at shift 2), per Pine parity comment at `:337`.

---

## 6. SIDEWAYS SCORE (0-100) & ATR PERCENTILE — verbatim

### 6a. ATR percentile (`TradeManagement/RiskManager.mqh:215-235`)
```
double CalculateATRPercentile(double currentATR, int lookback) {       // lookback = ATR_PERCENTILE_LOOKBACK = 32
    if (lookback <= 0 || currentATR <= 0) return 50.0;
    if (g_atrM1Handle == INVALID_HANDLE) return 50.0;
    double atrValues[]; ArraySetAsSeries(atrValues, true);
    if (CopyBuffer(g_atrM1Handle, 0, 1, lookback, atrValues) <= 0) return 50.0;   // shift 1, count=lookback
    int countBelow = 0; int copied = ArraySize(atrValues);
    for (int i = 0; i < copied; i++) { if (atrValues[i] < currentATR) countBelow++; }
    return (double)countBelow / (double)copied * 100.0;
}
```
- Window = **last 32 closed bars starting at shift 1** (`CopyBuffer(...,0,1,32,...)`), M1 ATR(14).
- `currentATR` passed in = `cache.atrM1` (the **shift-0** ATR from §3d) — so percentile compares the
  forming-bar ATR against the prior 32 closed-bar ATRs. **Mixed shift (0 vs 1) — replicate exactly.**

### 6b. Sideways score (`Core/TrendIdentifier.mqh:390-467`, called via `GetSidewaysScore(ENTRY_SHIFT)`)
Components: **EMA Convergence(0-25) + ADX Weakness(0-25) + DI Indecision(0-20) + RSI Neutral(0-15) +
ATR Compression(0-15)**. Inputs:
- EMAs at `barShift` (=ENTRY_SHIFT=1): `GetEMA(TF0, EMA1/EMA2/EMA3/EMA4, barShift)` (`:394-397`).
- `atr = cache.atrM1` (`:400`); `adx_m1 = GetADXAverage(M1, avgBars=5)`, `adx_m3 = GetADXAverage(M3,5)`
  (`:401-402`, averages over 5 bars from **shift 0**, see `ADXRSIHelpers.mqh:235` `CopyBuffer(...,0,0,lastBars,...)`).
- `diplus = cache.diPlus[0]`, `diminus = cache.diMinus[0]` (M1, shift-1 values) (`:403-404`).
- `rsi = GetRSIAverage(M1, RSI_LEN=14, avgBars=5)` (`:407`, avg over 5 bars from shift 0).
- `atrPctl = cachedATRPercentile` (`:458`).

```
// COMPONENT 1: EMA Convergence (0-25)
maxEMA = max(ema25,ema75,ema100,ema200); minEMA = min(...);
emaSpread = (atr>0) ? (maxEMA-minEMA)/atr : 999.0;
if (emaSpread < 1.75) score += 25;          // EMA_SPREAD_TIGHT_ATR
else if (emaSpread < 3.25) score += 15;     // EMA_SPREAD_MODERATE_ATR
else if (emaSpread < 4.0)  score += 8;      // EMA_SPREAD_WIDE_ATR
// COMPONENT 2: ADX Weakness (0-25)
adxScore=0;
if (adx_m1 < 15) adxScore+=15; else if (adx_m1 < 20) adxScore+=10; else if (adx_m1 < 25) adxScore+=5;
if (adx_m3 < 18) adxScore+=10; else if (adx_m3 < 22) adxScore+=5;
score += min(25, adxScore);
// COMPONENT 3: DI Indecision (0-20)
diSpread = |diplus - diminus|;
if (diSpread < 2.0) score+=12; else if (diSpread < 4.0) score+=8; else if (diSpread < 6.0) score+=4;
// COMPONENT 4: RSI Neutral (0-15)
if (rsi>=45 && rsi<=55) score+=15; else if (rsi>=40 && rsi<=60) score+=10; else if (rsi>=35 && rsi<=65) score+=5;
// COMPONENT 5: ATR Compression (0-15)
if (atrPctl < 15) score+=15; else if (atrPctl < 25) score+=10; else if (atrPctl < 35) score+=5;
return score;  // max 25+25+20+15+15 = 100
```
Thresholds: block `>= 53` (`IsInExtremeSidewayRange`), warning `>= 43 && < 53` (`IsInSidewayRange`)
(`:485,491`).

> Note the inconsistency to preserve: Component-2/RSI use 5-bar **averages from shift 0**, but
> Component-3 uses **shift-1 single-bar** DI (`cache.diPlus[0]`), and Component-1 EMAs are at shift 1.
> These mixed shifts are intentional in the source — replicate verbatim.

### 6c. Per-TF sideways (E5, `GetSidewaysScoreForTF`, `:503-604`)
Same 5 components but per-TF. Differences to note: EMAs at `barShift`; ATR from `cache.atrM1/M3/M5`;
**both** ADX slots use the *same* TF ADX average (`:579-585`, "Pine f_tfSidewayScore passes _adxA twice");
DI = avg over `avgBars` from `barShift` via `CopyBuffer(adxHandles[tfIdx],1/2,barShift,avgBars,...)`
(`:532-533`); ATR percentile computed inline with **lookback=100** from `barShift` (`:552-561`, divisor
`lookback-1`). `IsMultiTfSideway` checks M1 shift1 / M3 shift0 / M5 shift0 and M1 shift2 / M3 shift1 /
M5 shift1, needs ≥2 of 3 ≥ threshold (`E5_SIDEWAYS_BLOCK_THRESHOLD=50`) on either bar set (`:606-625`).

---

## 7. LOOKAHEAD AUDIT

### Reads at shift 0 (current / FORMING bar — intra-bar mutable)
| What | Line | Risk |
|---|---|---|
| `cache.currentPrice/high/low` = iClose/iHigh/iLow(M1, **0**) | `:677,679,680` | Forming-bar OHLC. Used by entry/SL logic. C++ must define whether "bar t" = closed bar; if engine reads forming bar these update tick-by-tick. **Expected (entry uses ENTRY_SHIFT elsewhere), but high/low at 0 can leak the bar's eventual extreme if engine evaluates after bar close.** |
| `cache.atrM1/atrM3/atrM5` = CopyBuffer(atr,0,**0**,1) | `:711,718,725` | ATR includes forming bar. Feeds SL sizing, vol-lot, ATR-percentile, sideways. **Must match: ATR(14) RMA evaluated on the bar being decided.** Biggest parity hazard. |
| `cache.rsiM3/adxM3/diM3[0..5]` = CopyBuffer(...,**0**,6) | `:793,806-808` | `[0]` = forming M3 bar RSI/ADX/DI. E3 exhaustion sees live forming-bar values. |
| `GetADXAverage`/`GetRSIAverage` (sideways comp 2 & 4) = CopyBuffer(...,**0**,5) | `ADXRSIHelpers.mqh:235,263` | 5-bar avg starting at forming bar. |
| `HasTrendAcceleration`, `HasDISpreadDeceleration` = CopyBuffer(...,**0**,lookback) | `ADXRSIHelpers.mqh:302-305,364-365` | Forming-bar ADX/DI in momentum/reversal checks. |
| `isEMA25LeadingAllTimeFrames` = `GetEMA(...,0)` | `EMAHelpers.mqh:377-388` | Forming-bar EMA (EMA at shift 0). |

### Reads at shift ≥ 1 (closed bars — safe)
- All `cache.adx/diPlus/diMinus[i]` and `adxShort/diShort` at **shift 1** (`:686-694`).
- All Ichimoku **Current** cloud + Tenkan/Kijun/Chikou at **shift 1** (`:738-770`).
- `priceM3_26BarsAgo` at shift **27** (`:773`).
- Sideways-score EMAs + DI at shift 1; ATR-percentile window at shift 1 (`RiskManager.mqh:223`).

### Negative shift (FUTURE-projected, flag explicitly)
| What | Line | Verdict |
|---|---|---|
| `ichimokuSpanA/B_M1_Future` = CopyBuffer(ichi[0], 0/1, **-26**, 1) | `:744,746` | **Not raw price lookahead.** MT5 Senkou buffers are forward-shifted by `kijun=26`; shift `-26` reads the *leading span* (cloud edge plotted ahead). Values are computed from data ≤ t. **BUT** porting must ensure the C++ Ichimoku's leading span at bar t uses only inputs through t. If the C++ `ichimoku` instead samples future price to build the +26 cloud, that WOULD be lookahead. Verify `kk::ind::ichimoku` builds Senkou A/B from current Tenkan/Kijun (no forward price). |
| `ichimokuSpanA/B_M3_Future` = CopyBuffer(ichi[1], 0/1, **-26**, 1) | `:756,758` | Same as above (M3). |

### Net assessment
No raw future-price leak in the cache *as written* (negative shifts read MT5's projected Senkou
buffers, which are deterministic from past data). The genuine parity traps are **shift mismatches**, not
leaks: (1) ATR cache + M3 history + sideways averages read **shift 0** while ADX/DI/Ichimoku-current
read **shift 1**; (2) ATR-percentile mixes shift-0 `currentATR` against a shift-1 window; (3) EMA
periods are **10/25/71/97/192**, not the names' 75/100/200. Replicate all three exactly for byte parity.
