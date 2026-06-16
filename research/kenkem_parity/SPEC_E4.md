# E4 — Ichimoku Cloud Cross Entry: Implementation-Ready Parity Spec

Reverse-engineered from `kenkem/MQL5/Experts/KenKem/` (the symlinked ground-truth EA).
Goal: bit-for-bit trade parity in C++. E4 is the dominant entry (7/9 trades in the reference run).
**All `file:line` refer to the live source unless noted. Read-only — no MQL5 was modified.**

Source map (files cited):
- `KenKemExpert.mq5` — OnTick/DetectNewEntry, UpdateIndicatorCache, conviction dispatch, high-risk path
- `Entries/Entry4.mqh` — E4 detect + E4 gate stack + SL/TP
- `Entries/EntryBase.mqh` — `CheckIchimokuQuality`, `CalculateStopLossWithCustomEMA`
- `Entries/EntryHelpers.mqh` — `CalculateConvictionScore`, `HasRSIDivergenceAgainstTrade`
- `Core/TrendIdentifier.mqh` — `GetTrendQualityScore`, `GetSidewaysScore`, sideway helpers, momentum helpers
- `Core/Indicators/EMAHelpers.mqh` — Ichimoku cloud-cross **trigger** detection (bottom of file)
- `Config/InputParams.mqh` — defaults
- `Config/RuntimeConfig.mqh` — `CFG.*` derived values
- `TradeManagement/RiskManager.mqh` — `GetEntryBlockReason` (global ATR/spread gates)
- `Utils/SessionManager.mqh` — `IsNowInValidSession`

---

## 0. Indexing & cached state conventions (CRITICAL for parity)

- `ENTRY_SHIFT = 1` (`InputParams.mqh:182`). All entry-time indicator reads use **bar shift 1 = last
  CLOSED M1 bar**. Wherever this spec says "shift 1", it means `ENTRY_SHIFT`.
- Timeframe index map: `TF0=M1, TF1=M3, TF2=M5, TF3=M15` (`InputParams.mqh:682-686`). Cache arrays
  `cache.adx[i]`, `cache.diPlus[i]`, `cache.diMinus[i]` are indexed `0=M1,1=M3,2=M5,3=M15`.
- EMA index map: `EMA0=10, EMA1=25, EMA2=71, EMA3=97, EMA4=192` (`InputParams.mqh:688-693`).
  NOTE: the code comments say "75/100/200" but **actual periods are 71/97/192** (and 25, 10). E4 uses
  EMA1(25), EMA2(71), EMA3(97), EMA4(192) — use the real periods.
- `GetEMA(tf, ema, shift)` reads from `emaBuffers` (`EMAHelpers.mqh:45-67`), a 2D buffer filled once per
  tick by `GetEMAValues()` from `CopyBuffer(...,0,0,bufferSize,...)` (index 0 = forming bar, so
  `shift=ENTRY_SHIFT=1` = last closed). EMAs are MT5 `iMA(EMA, PRICE_CLOSE)`.
- `cache.adx[i]/diPlus[i]/diMinus[i] = getADX/DIValue(TF_ARRAY[i], ENTRY_SHIFT)` — **ADX(14) at shift 1**
  on every TF (`KenKemExpert.mq5:692-696`).
- `cache.atrM1`, `cache.atrM3`, `cache.atrM5` = ATR(14) at **shift 0 (forming bar)** —
  `CopyBuffer(handle,0,0,1,...)` (`KenKemExpert.mq5:717-736`). ATR period = `ATR_PERIOD_FOR_SL=14`.
- `cachedATRPercentile = CalculateATRPercentile(cache.atrM1, ATR_PERCENTILE_LOOKBACK=32)`
  (`KenKemExpert.mq5:841-843`).
- `cachedSidewaysScore = GetSidewaysScore(ENTRY_SHIFT)` (0–100), refreshed each bar
  (`TrendIdentifier.mqh:470-475`, `UpdateSidewaysScoreCache`).
- Ichimoku handles: `ichimokuHandles[0]=M1`, `ichimokuHandles[1]=M3`, params Tenkan=9, Kijun=26,
  SenkouB=52 (`InputParams.mqh:132-134`). Buffer map: `0=SpanA, 1=SpanB, 2=Tenkan, 3=Kijun, 4=Chikou`.
  - `cache.ichimokuSpanA_M1_Current / SpanB_M1_Current` = M1 SpanA/B at **shift ENTRY_SHIFT=1**
    (`KenKemExpert.mq5:744-748`).
  - `cache.ichimokuSpanA_M3_Current / SpanB_M3_Current` = M3 SpanA/B at shift 1 (`:757-760`).
  - `cache.ichimokuTenkan_M3 / Kijun_M3 / Chikou_M3` = M3 buffers 2/3/4 at shift 1 (`:771-778`).
  - `cache.priceM3_26BarsAgo = iClose(_Symbol, M3, ENTRY_SHIFT+26)` (`:780`).
  - "Current cloud" = the cloud value plotted at the bar (NOT projected forward). Pine parity uses
    current cloud for E4, not future cloud.
- `pipSize`: auto-detected from symbol `digits` (`KenKemExpert.mq5:127-161`). For **BTCUSD (2-digit)
  `pipSize=0.01`**; fallback also 0.01. (Memory note "BTC pip=1" applies to a different std-dev scaling,
  not this `pipSize`; E4's geometry uses `pipSize` as defined here.)
- `contractSize` auto-detected; `LEVERAGE=500`.

---

## 1. TRIGGER — Ichimoku cloud cross (arming `lastIchiCloudCrossUp/Down`)

Computed in `UpdateEmaTouches()` → "E4: ICHIMOKU CLOUD CROSS DETECTION" block
(`EMAHelpers.mqh:316-366`), only when `ENABLE_E4_ENTRIES` (true). `UpdateEmaTouches()` runs once per
**new M1 bar** in OnTick (`KenKemExpert.mq5:2447`), AFTER `UpdateIndicatorCache()` (`:2437`) and BEFORE
`DetectNewEntry()` (`:2496`). So the cache the trigger reads is the freshly-updated one.

Two global state vars (persist across bars), initialized to -1 (no trigger):
`lastIchiCloudCrossUp`, `lastIchiCloudCrossDown`.

### 1a. Cloud state (per bar)
```
m1CloudBullish_curr = cache.ichimokuSpanA_M1_Current > cache.ichimokuSpanB_M1_Current     // M1 @ shift1
m3CloudBullish_curr = cache.ichimokuSpanA_M3_Current > cache.ichimokuSpanB_M3_Current     // M3 @ shift1

// previous-bar cloud = same "current cloud" buffers read one bar older (shift ENTRY_SHIFT+1 = 2):
spanA_M1_prev = CopyBuffer(ichimokuHandles[0], 0, ENTRY_SHIFT+1, 1)   // EMAHelpers.mqh:335
spanB_M1_prev = CopyBuffer(ichimokuHandles[0], 1, ENTRY_SHIFT+1, 1)   // :336
spanA_M3_prev = CopyBuffer(ichimokuHandles[1], 0, ENTRY_SHIFT+1, 1)   // :338
spanB_M3_prev = CopyBuffer(ichimokuHandles[1], 1, ENTRY_SHIFT+1, 1)   // :339
m1CloudBullish_prev = spanA_M1_prev > spanB_M1_prev
m3CloudBullish_prev = spanA_M3_prev > spanB_M3_prev
```

### 1b. Cross detection (BOTH M1 AND M3 must agree) — `EMAHelpers.mqh:345-352`
```
bothBullish_curr = m1CloudBullish_curr && m3CloudBullish_curr
bothBullish_prev = m1CloudBullish_prev && m3CloudBullish_prev
bothBearish_curr = !m1CloudBullish_curr && !m3CloudBullish_curr
bothBearish_prev = !m1CloudBullish_prev && !m3CloudBullish_prev

ichiJustCrossedUp   = bothBullish_curr && !bothBullish_prev     // just turned green on BOTH TFs
ichiJustCrossedDown = bothBearish_curr && !bothBearish_prev     // just turned red on BOTH TFs
```

### 1c. Arming (one-shot, mutually exclusive) — `EMAHelpers.mqh:355-365`
```
if (ichiJustCrossedUp && lastIchiCloudCrossUp == -1):
    lastIchiCloudCrossUp = currentBar;  lastIchiCloudCrossDown = -1
if (ichiJustCrossedDown && lastIchiCloudCrossDown == -1):
    lastIchiCloudCrossDown = currentBar; lastIchiCloudCrossUp = -1
```
`currentBar = Bars(_Symbol, M1) - 1` (`KenKemExpert.mq5:2427`). A new UP cross zeroes the DOWN flag and
vice-versa — only one direction can be armed at a time.

### 1d. Expiry (max age) — checked at detection time, `Entry4.mqh:106-109 / 158-161`
```
crossAge = currentBar - lastIchiCloudCrossUp   (or ...Down)
if crossAge > E4_MAX_CROSS_AGE (=20):  reset that flag to -1, no trade this bar
```
So a trigger is valid for bars `[crossBar, crossBar+20]` inclusive. Bar 21+ → expired.

### 1e. Trigger consumption — `Entry4.mqh:117 / 169`
The armed flag is set back to -1 **only after the full gate stack passes** (i.e. when a detection fires).
If gates fail, the flag stays armed and is retried on the next bar (until it expires). Also auto-reset to
-1 on expiry.

---

## 2. ENTRY DISPATCH & GLOBAL GATES (run before/around E4 detection)

E4 detection only happens inside `DetectNewEntry()`, called **once per M1 bar**
(`KenKemExpert.mq5:2494-2497`). Order of relevant guards:

**OnTick-level (block detection entirely / set signalOnlyMode):** `KenKemExpert.mq5:2469-2484`
1. `IsWithinDailyLossLimit()` false → signalOnly (or `return` if `SIGNAL_ONLY_DURING_PROTECTION=false`).
2. `IsDrawdownBlocked()` → signalOnly.
3. `IsWithinDrawdownLimit()` false → signalOnly.

**DetectNewEntry pre-conditions (ALL must hold to attempt any entry):** `KenKemExpert.mq5:2153,2172-2177`
```
inValidSession   = IsNowInValidSession() || IGNORE_VALID_SESSIONS
isInExtremeSidewayRange = (cachedSidewaysScore >= SIDEWAYS_BLOCK_THRESHOLD=53)   // TrendIdentifier.mqh:485
drawdownCheck    = signalOnlyMode ? true : !IsDrawdownBlocked()
GUARD: inValidSession && !isInExtremeSidewayRange && !IsBlockedByLosingStreak()
       && drawdownCheck && totalBars >= ENTRY_SHIFT+2
```
`IsNowInValidSession()` (`SessionManager.mqh:118`): false during 21:20–21:45 JST news window (when
`AVOID_NEWS_TRADING=true`) and outside Japan(900–1230)/London(1400–1830)/NY(2100–2400) JST windows.

**E4-specific dispatch guard** (`KenKemExpert.mq5:2282-2294`):
- Only run if `detectedTrade.type == ""` (E1, E2, E3 get first crack — E4 is checked 4th, E5 5th).
- `BLOCK_E4_WHEN_E1_ACTIVE = false` (default) → the same-direction-E1 block is **inactive**.
- Calls `entry4.Detect()`.

**Post-detection gates (after E4 fires, in OnTick):** `KenKemExpert.mq5:2336-2376`
- If `signalOnlyMode`: signal only, no execution.
- Else compute `potentialLossUSD = |SL-entry| * lot * contractSize`; if `>= getMaxLossUSD(E4)` →
  `HandleHighRiskEntry()` (section 7). Otherwise:
  - `HasOpposingDirectionPosition(isLong)` → block (hedge guard, `BLOCK_OPPOSITE_DIRECTION_ENTRIES=true`).
  - `IsEntryTypeBlocked("L-E4"/"S-E4")` (consecutive-loss block) → block.
  - `GetEntryBlockReason()` (RiskManager.mqh:241) — global filters, returns non-"" to block:
    black-swan cooldown; spread (`MAX_SPREAD_PIPS=0`→off); spread/ATR (`MAX_SPREAD_ATR_RATIO=0.30`);
    **ATR percentile band**: `ATR_PERCENTILE_LOW=20` (low block, with `ENABLE_BLACK_SWAN_PROTECTION=true`),
    `ENABLE_ATR_HIGH_BLOCK=true` + `ATR_PERCENTILE_HIGH=90` (high block), and
    **`MIN_ENTRY_ATR_PERCENTILE=65` → block if `cachedATRPercentile < 65`** (RiskManager.mqh:305).
    These ATR gates apply to E4 **at execution**, after detection passes.

> Parity note: the ATR-percentile regime gate (`MIN_ENTRY_ATR_PERCENTILE=65`) is a hard execution
> filter on E4 even though it is not inside `Entry4.Detect()`.

---

## 3. E4 DETECTION — `Entry4::Detect()` (`Entry4.mqh:77-207`)

Pre-gate hard stops (return no-detection):
- `sessionLossCount >= MAX_SESSION_LOSSES (=4)` → `Entry4.mqh:84`.
- `tradeSLTPCountInSession > MAX_SLTP_COUNT_PER_SESSION (=7)` → `:90`.

`currentPrice = iClose(_Symbol, M1, ENTRY_SHIFT)` (`:96`). (Note `TriggerPrice()` returns the same;
`USE_LIVE_PRICE...=false`.)

`CheckOpenPositions(...)` fills `checkOpenLE4/checkOpenSE4` (index of an open E4 in that direction, or -1).

### LONG path (`Entry4.mqh:104-153`)
```
if lastIchiCloudCrossUp != -1 AND checkOpenLE4 == -1:
    crossAge = currentBar - lastIchiCloudCrossUp
    if crossAge > E4_MAX_CROSS_AGE(20): lastIchiCloudCrossUp = -1   // expire, skip
    else if CheckE4EntryConditions_Internal(isLong=true, currentPrice, "L-E4", ...) == true:
        lastIchiCloudCrossUp = -1                    // consume trigger
        result.detected = true; isLong = true; entryPrice = currentPrice
        ...compute SL/TP (section 6)...
```
SHORT path is the mirror (`:156-204`) and runs **only if LONG didn't detect** (`!result.detected`).

`result.trendQualityScore` is set to the score returned by the gate stack (used later by conviction
dispatch for recovery-boost; does NOT re-gate).

---

## 4. E4 GATE STACK — `CheckE4EntryConditions_Internal()` (`Entry4.mqh:217-379`)

Evaluated in EXACTLY this order; first failure returns false (no trade). Every gate uses cached
shift-1 values unless noted.

**STEP 0 — Ichimoku Quality** (`Entry4.mqh:224-229` → `EntryBase.mqh:457-510`,
params `E4_MIN_CLOUD_THICKNESS_ATR_MULT=0.11`, `E4_REQUIRE_TENKAN_KIJUN_ALIGN=true`,
`E4_REQUIRE_CHIKOU_CLEAR=false`). All checks on **M3**:
- Cloud thickness (only if mult>0):
  `thickness = max(SpanA_M3,SpanB_M3) - min(SpanA_M3,SpanB_M3)`;
  `minThickness = cache.atrM3 * 0.11`; **block if `thickness < minThickness`**.
- Tenkan/Kijun (since require=true): block unless
  `isLong ? Tenkan_M3 > Kijun_M3 : Tenkan_M3 < Kijun_M3`.
- Chikou: **disabled** (`E4_REQUIRE_CHIKOU_CLEAR=false`) — skipped.

**STEP 0.1 — E4 sideway block** (`Entry4.mqh:232-235`):
`if cachedSidewaysScore > E4_MAX_SIDEWAY_SCORE(40): block`. (Stricter than global 53.)

**STEP 0.5 — HTF Trend Direction Filter** (`Entry4.mqh:239-293`), mode
`E4_HTF_TREND_FILTER = HTF_M5_OR_M15 (=4)`, thresholds `E4_HTF_MIN_ADX=20.5`,
`E4_HTF_MIN_DI_SPREAD=6.0`. Uses cached M5 (idx2) / M15 (idx3):
```
m5Valid  = cache.adx[2] >= 20.5 && |diPlus[2]-diMinus[2]| >= 6.0;  m5Bullish = diPlus[2] > diMinus[2]
m15Valid = cache.adx[3] >= 20.5 && |diPlus[3]-diMinus[3]| >= 6.0;  m15Bullish= diPlus[3] > diMinus[3]
// HTF_M5_OR_M15 (most aggressive — EITHER opposing valid TF blocks):
blockLong  = (m5Valid && !m5Bullish) || (m15Valid && !m15Bullish)
blockShort = (m5Valid &&  m5Bullish) || (m15Valid &&  m15Bullish)
if (isLong && blockLong) block;  if (!isLong && blockShort) block
```
(An invalid/ranging HTF does not block.)

**STEP 1 — M5 DI Alignment** (`E4_REQUIRE_M5_DI_ALIGN=true`, `Entry4.mqh:296` → `:384-411`):
```
adxM5 = cache.adx[2]; if adxM5 < ADX_LOW_THRESHOLD(14.5): PASS (M5 ranging, allow)
LONG:  block if diPlus[2] <= diMinus[2]   (M5 must be bullish)
SHORT: block if diMinus[2] <= diPlus[2]   (M5 must be bearish)
```

**STEP 2 — EMA alignment (M1 ALWAYS, M3 with momentum bypass)** (`Entry4.mqh:300-331`):
```
m1Aligned = CheckE4EMAAlignmentM1(isLong)   // EMA1(25),EMA2(71),EMA3(97) @ shift1 on M1
            LONG: 25>71>97 ; SHORT: 25<71<97        (Entry4.mqh:414-424)
m3Aligned = CheckE4EMAAlignmentM3(isLong)   // same stack on M3                (:427-437)
if !m1Aligned: block "ema_m1"                              // M1 ALWAYS required
// E4_MOMENTUM_BYPASS_LEVEL=1 (not 0) → M3 may be bypassed by extreme momentum:
extremeMomentum = isLong ? (diPlus[0]-diMinus[0]) >= EXTREME_DI_SPREAD_THRESHOLD(16.0)
                         : (diMinus[0]-diPlus[0]) >= 16.0
emasOK = m1Aligned && (m3Aligned || extremeMomentum)
if !emasOK: block "ema_alignment"
```
(NOTE: EMA stack here is only 25/71/97 — EMA4/192 is NOT in the E4 alignment check.)

**STEP 3 — Price position vs EMA25 & cloud, with 5-pip tolerance** (`Entry4.mqh:333-352`):
```
e4Tolerance = 5.0 * pipSize
ema25     = GetEMA(M1, EMA1, ENTRY_SHIFT)
cloudTop  = max(SpanA_M1_Current, SpanB_M1_Current)
cloudBot  = min(SpanA_M1_Current, SpanB_M1_Current)
LONG:  block if currentPrice <= (ema25 - tol)  OR  currentPrice <= (cloudTop - tol)
SHORT: block if currentPrice >= (ema25 + tol)  OR  currentPrice >= (cloudBot + tol)
```

**STEP 4 — Minimum momentum ADX (M1)** (`Entry4.mqh:354-360`):
`if cache.adx[0] < E4_MIN_MOMENTUM_ADX(19.75): block "momentum"`.

**STEP 5 — Trend Quality HARD BLOCK** (`Entry4.mqh:362-370`):
```
requiredTrend = isLong ? TREND_BULL : TREND_BEAR
trendQuality  = GetTrendQualityScore(requiredTrend, entryNum=4)        // section 5
if trendQuality < MIN_TREND_QUALITY_E4(9): block "trend_quality"       // HARD BLOCK
```

**STEP 6 — RSI Divergence Veto (M3)** (`Entry4.mqh:372-376` → `EntryHelpers.mqh:298-...`):
`if HasRSIDivergenceAgainstTrade(isLong, "E4"): block "rsi_div"`. Logic
(`ENABLE_RSI_DIVERGENCE_VETO=true`, `RSI_DIV_LOOKBACK=16`, half=8):
- M3 highs/lows over 16 bars from shift `ENTRY_SHIFT`; M3 RSI(14) over same 16 bars.
- LONG (bearish div): recent-window [0..7] highest high vs older-window [8..15] highest high;
  `priceDiffPips=(recentHH-olderHH)/pipSize`, `rsiDiff = rsi[older]-rsi[recent]`.
  Block if `priceDiffPips >= RSI_DIV_MIN_PRICE_DIFF_PIPS(60) && rsiDiff >= RSI_DIV_MIN_RSI_DIFF(6.5)`.
- SHORT (bullish div): mirror with lowest lows; block on symmetric condition.

If all 6 steps pass → return true (E4 detected). `trendQualityOut` returned for downstream use.

---

## 5. TREND QUALITY SCORE — `GetTrendQualityScore(trendState, entryNum=4)` (`TrendIdentifier.mqh:127-254`)

0–11 scale for E4 (`USE_ICHIMOKU_E4=false` → no Ichimoku bonus; max would be 13 with it).
Order matters because of the mid-function GATE.

```
adx = cache.adx[0]   // M1 ADX(14) @ shift1
// C1 ADX strength (0-2):
adxPoints = adx >= ADX_HIGH_THRESHOLD(25.0) ? 2 : adx >= MIN_MOMENTUM_ADX_REQUIRED(19.7) ? 1 : 0
// C2 DI spread (0-2):  spread = BULL? diPlus[0]-diMinus[0] : diMinus[0]-diPlus[0]
spreadPoints = spread >= 3.0 ? 2 : spread >= 1.0 ? 1 : 0
// C3 M1 acceleration (0-2), USE_ACCELERATION_BONUS=true:
accel5 = HasTrendAcceleration(M1, trend, 5); accel3 = HasTrendAcceleration(M1, trend, 3)
accelPoints = accel5 ? 2 : accel3 ? 1 : 0
// C4 MTF alignment (0-2): count of {M1,M3,M5} DI agreeing with trend (cache idx 0,1,2)
alignedCount = (diAligned M1)+(diAligned M3)+(diAligned M5)
mtfPoints = alignedCount==3 ? 2 : alignedCount>=2 ? 1 : 0

// ===== HARD GATE (ENABLE_TREND_QUALITY_GATES=true, entryNum!=5): =====
if (adxPoints==0 || spreadPoints==0 || mtfPoints==0): return 0   // TrendIdentifier.mqh:200-208

// C5 Price action (0-1): HasStrongTrendingPriceActions(trend, M1, 5, ENTRY_SHIFT)  -> 1/0
// C6 M3 acceleration (0-1): HasTrendAcceleration(M3, trend, 3) -> 1/0
// C7 Ichimoku bonus (0-2): CheckIchimokuCloudAlignment(...) — for E4 returns 0 (USE_ICHIMOKU_E4=false)
//    (entryNum=4 with USE_ICHIMOKU_E4=false ⇒ no points added)
// C8 ATR health (0-1): cachedATRPercentile >= ATR_PERCENTILE_LOW(20.0) ? 1 : 0
score = adxPoints+spreadPoints+accelPoints+mtfPoints + paPoints + m3AccelPoints + 0(ichi) + atrPoints
return score   // E4 max 11
```
For E4 the effective max without Ichimoku is **2+2+2+2+1+1+1 = 11**, and `MIN_TREND_QUALITY_E4=9`.
The gate means weak ADX, weak DI, or <2/3 MTF alignment → score 0 → immediate block.

`HasTrendAcceleration` and `CheckIchimokuCloudAlignment` are in TrendIdentifier.mqh; their exact internals
matter for the 9/11 threshold — port them faithfully. `cachedATRPercentile` uses ATR(14) shift-0 vs a
32-bar window (`ATR_PERCENTILE_LOOKBACK=32`).

---

## 6. STOP-LOSS & TAKE-PROFIT (`Entry4.mqh:124-146` LONG / `:176-196` SHORT)

### 6.1 Structure inputs
```
recentHigh = iHigh(M1, iHighest(M1, MODE_HIGH, RANGE_HI_LOW_LOOK_BACK_BARS=18, ENTRY_SHIFT))
recentLow  = iLow (M1, iLowest (M1, MODE_LOW,  18,                       ENTRY_SHIFT))
ema100 = GetEMA(M1, EMA3, ENTRY_SHIFT)   // EMA3 = period 97
ema200 = GetEMA(M1, EMA4, ENTRY_SHIFT)   // EMA4 = period 192
emaDistance = |ema100 - ema200|
LONG : e4SLLevel = ema100 - emaDistance*0.75
SHORT: e4SLLevel = ema100 + emaDistance*0.75
```

### 6.2 SL = `CalculateStopLossWithCustomEMA(isLong, price, recentHigh, recentLow, e4SLLevel, "E4", entryType=4, ...)`
(`EntryBase.mqh:637-691`):
```
baseSL        = isLong ? min(recentLow, e4SLLevel) : max(recentHigh, e4SLLevel)
structuredStop= isLong ? baseSL - SL_EMA_DISTANCE(27)*pipSize
                       : baseSL + SL_EMA_DISTANCE(27)*pipSize

// ===== ATR ARBITRATION — PARITY TRAP (EntryBase.mqh:648-650): =====
// The function selects settings by `entryType==1 ? E1.. : E2..`. There is NO entryType==4 branch,
// so E4 (entryType=4) FALLS THROUGH TO THE E2 SETTINGS:
useAtrArbitration = E2_USE_ATR_SL_ARBITRATION (true)
atrCapMult        = E2_ATR_SL_CAP_MULTIPLIER  (3.0)    // NOT E4_ATR_SL_CAP_MULTIPLIER(4.0)
atrFloorMult      = E2_ATR_SL_FLOOR_MULTIPLIER(1.1)    // NOT E4_..._FLOOR(1.25)

if (useAtrArbitration && cache.atrM1 > 0):
    structureDistPips = |price - structuredStop| / pipSize
    atrPips   = cache.atrM1 / pipSize
    atrCapPips= atrPips * 3.0 ; atrFloorPips = atrPips * 1.1
    finalDistPips = structureDistPips
    if finalDistPips > atrCapPips:   finalDistPips = atrCapPips     // CAP
    if finalDistPips < atrFloorPips: finalDistPips = atrFloorPips   // FLOOR
    if finalDistPips != structureDistPips:
        structuredStop = isLong ? price - finalDistPips*pipSize : price + finalDistPips*pipSize

// spread buffer:
finalSL = ApplySpreadBuffer(isLong, price, structuredStop, &rawSLDistPips, &bufferedSLDistPips)
        = CalculateBufferedStopWithSpread(isLong, price, structuredStop,
                                          minSLSpreadMultiplier=MIN_SL_SPREAD_MULT(0.5), ...)
```
> Two parity traps: (a) **E4 uses E2's ATR cap 3.0 / floor 1.1**, not E4's 4.0/1.25 (the E4 cap/floor
> inputs are dead for SL). (b) `e4SLLevel` uses EMA3(97) and EMA4(192) — comment says "100/200".
> Port `CalculateBufferedStopWithSpread` exactly (spread buffer = `minSLSpreadMultiplier * spread`).

### 6.3 TP (`Entry4.mqh:142-145` LONG / `:193-196` SHORT)
```
slDistance = |currentPrice - result.stopLoss|
LONG : e4RR = IsInSidewayRange() ? E4_RR_SIDEWAY(1.15) : CFG.rrLongE4
SHORT: e4RR = IsInSidewayRange() ? E4_RR_SIDEWAY(1.15) : CFG.rrShortE4
LONG : takeProfit = currentPrice + slDistance*e4RR
SHORT: takeProfit = currentPrice - slDistance*e4RR
```
`CFG.rrLongE4  = E4_RR = 2.4` (`RuntimeConfig.mqh:65`).
`CFG.rrShortE4 = E4_RR_SHORT * 0.875 = 1.8 * 0.875 = 1.575` (`RuntimeConfig.mqh:66`).
`IsInSidewayRange()` true iff `SIDEWAYS_WARNING_THRESHOLD(43) <= cachedSidewaysScore < SIDEWAYS_BLOCK_THRESHOLD(53)`
(`TrendIdentifier.mqh:489-492`). (Detection only runs when score<53, so the sideway band that matters is 43–52.)

> Asymmetric RR: longs target 2.4R, shorts 1.575R. If high-risk path is taken (section 7), TP is then
> further scaled by a session multiplier — see below.

---

## 7. CONVICTION & POST-DETECTION (after Detect returns; `ProcessEntryConvictionAndConfidence`, `KenKemExpert.mq5:1750`)

E4: `USE_CONVICTION_SCORING_E4=true`, `CONVICTION_THRESHOLD_E4=9`, `USE_HTF_VETO_E4=false`.
`CalculateConvictionScore(isLong, E4, convEnabled=true, applyTrendVeto=false)` (`EntryHelpers.mqh:11-176`),
**0–12 scale** (note dispatch log says "/10" but max is 12):
- HTF veto branch skipped (`applyTrendVeto=false`).
- C1 M1 DI spread (0-2): `m1_spread = BULL? diPlus[0]-diMinus[0] : diMinus[0]-diPlus[0]`;
  `>=3→2, >=1→1, else 0`.
- C2 EMA stack separation (0-2): `Calculate4EMAStackSeparation(isLong)` over M1 EMA1/2/3/4 @ shift1
  (requires ordering 25>71>97>=192 for long, else 0; normalized avgGap/30pip);
  `sep>=0.8→2, >=0.5→1, else 0`.
- C3 RSI momentum (0-2): RSI(14) M1 @ shift1 & shift1+2 and M3 @ shift1; level vs 50 + velocity>1.5/bar;
  clamped 0–2.
- C4 ADX strength+accel (0-2): `adx_1m=cache.adx[0]`; `>=23→+1, <15→-1`; +1 if ADX accelerating
  (`CopyBuffer(adxHandles[0],0,0,3)` IsAccelerating); clamp 0–2.
- C5 M3+M5 MTF (0-2): `m3Strong=adx[1]>=22 && spread3>=2`, `m5Strong=adx[2]>=22 && spread5>=2`,
  support variants at adx>=16 & spread>0.5; both strong→2, one strong→1, both support→1, else 0.
- C6 Price action (0-2): `CheckBullish/BearishPriceAction(3)` over M1 @ shift1.
- **`convictionScore < 9` → marks setup low-confidence → trade SILENTLY SKIPPED**
  (`KenKemExpert.mq5:1849-1853`; `SEND_LOW_CONFIDENCE_SIGNALS=false` so it is just dropped, type="").

If conviction passes (and `isLowConfidence` still false), trade proceeds to the OnTick execution gates
(section 2 "post-detection").

### High-risk path — `HandleHighRiskEntry` (`KenKemExpert.mq5:2018-2098`)
Triggered when `potentialLossUSD >= getMaxLossUSD(E4)` (E4 `MAX_LOSS_RATIO_E4 = COMMON_MAX_RISK_PER_TRADE*1.02 = 0.0204`).
`ACCEPT_HIGH_RISK_E4_ENTRIES=true`, so allowed; additional gates in order:
- `CanCreateNewEntry()`, opposing-position guard, `highRiskTradesInSession < MAX_HIGH_RISK_TRADES_PER_SESSION(5)`,
  `IsInSidewayRange(10)` → block if true.
- **High-risk momentum check** `HIGH_RISK_E4_MOMENTUM_CHECK = E1_ACCEL_M1_AND_M3 (=11)`:
  requires `HasEarlyTrendMomentumForE1(trend, M1) && HasEarlyTrendMomentumForE1(trend, M3)`
  (`KenKemExpert.mq5:2141-2142`). Each (`TrendIdentifier.mqh`):
  `HasMomentumForTrend(trend, TF, minADX=E1_MIN_MOMENTUM_ADX(19.5), minDISpread=1.75,
  checkAcceleration=true, lookback = M1?5 : M3?3 : 2)` — i.e. ADX@shift1 >= 19.5, ADX rising
  (IsAccelerating over lookback, buffers at shift 0), DI spread >= 1.75 and DI spread widening.
- TP rescale: `takeProfit = entry ± |TP-entry| * GetHighRiskTPMultiplier()` (session-based:
  ASIA/EU `HIGH_RISK_TP_MULTIPLIER_*=0.65`, US `0.70`). Lot resized to `entryMaxLoss*0.98 / (riskDist*contractSize)`.

---

## 8. DEFAULT VALUES — every param E4 touches (`Config/InputParams.mqh` unless noted)

| Param | Default | Line |
|---|---|---|
| ENABLE_E4_ENTRIES | true | 59 |
| ENTRY_SHIFT | 1 | 182 |
| E4_MAX_CROSS_AGE | 20 | 437 |
| E4_MAX_SIDEWAY_SCORE | 40 | 420 |
| E4_REQUIRE_M5_DI_ALIGN | true | 421 |
| E4_HTF_TREND_FILTER | HTF_M5_OR_M15 (4) | 422 |
| E4_HTF_MIN_ADX | 20.5 | 423 |
| E4_HTF_MIN_DI_SPREAD | 6.0 | 424 |
| E4_MIN_MOMENTUM_ADX | 19.75 | 429 |
| E4_MIN_CLOUD_THICKNESS_ATR_MULT | 0.11 | 432 |
| E4_REQUIRE_TENKAN_KIJUN_ALIGN | true | 433 |
| E4_REQUIRE_CHIKOU_CLEAR | false | 434 |
| E4_MOMENTUM_BYPASS_LEVEL | 1 | 436 |
| E4_RR | 2.4 | 438 |
| E4_RR_SHORT | 1.8 | 439 |
| E4_RR_SIDEWAY | 1.15 | 440 |
| CFG.rrLongE4 / rrShortE4 | 2.4 / 1.575 | RuntimeConfig.mqh:65-66 |
| MIN_TREND_QUALITY_E4 | 9 | 127 |
| USE_ICHIMOKU_E4 | false | 128 |
| USE_CONVICTION_SCORING_E4 | true | 117 |
| CONVICTION_THRESHOLD_E4 | 9 | 118 |
| USE_HTF_VETO_E4 | false | 119 |
| ACCEPT_HIGH_RISK_E4_ENTRIES | true | 425 |
| HIGH_RISK_E4_MOMENTUM_CHECK | E1_ACCEL_M1_AND_M3 (11) | 426 |
| E4_HIGH_RISK_MIN_ADX | 20.5 | 427 |
| E4_HIGH_RISK_MIN_DI_SPREAD | 4.0 | 428 |
| MAX_LOSS_RATIO_E4 | COMMON*1.02 = 0.0204 | 68 |
| VOL_LOT_ADJ_E4 | false | 78 |
| SL_EMA_DISTANCE | 27 | 187 |
| MIN_SL_SPREAD_MULT | 0.5 | 188 |
| E4_USE_ATR_SL_ARBITRATION | true (UNUSED for SL*) | 202 |
| E4_ATR_SL_CAP_MULTIPLIER | 4.0 (UNUSED — E2's 3.0 used*) | 203 |
| E4_ATR_SL_FLOOR_MULTIPLIER | 1.25 (UNUSED — E2's 1.1 used*) | 204 |
| E2_USE_ATR_SL_ARBITRATION / CAP / FLOOR (actually used) | true / 3.0 / 1.1 | 194-196 |
| ATR_PERIOD_FOR_SL | 14 | 210 |
| ATR_PERCENTILE_LOOKBACK | 32 | 153 |
| RANGE_HI_LOW_LOOK_BACK_BARS | 18 | 214 |
| EXTREME_DI_SPREAD_THRESHOLD | 16.0 | 233 |
| ADX_LOW_THRESHOLD | 14.5 | 221 |
| ADX_HIGH_THRESHOLD | 25.0 | 222 |
| MIN_MOMENTUM_ADX_REQUIRED | 19.7 | 220 |
| ENABLE_TREND_QUALITY_GATES | true | 122 |
| USE_ACCELERATION_BONUS | true | 131 |
| ATR_PERCENTILE_LOW | 20.0 | 149 |
| ATR_PERCENTILE_HIGH | 90.0 | 150 |
| ENABLE_ATR_HIGH_BLOCK | true | 151 |
| MIN_ENTRY_ATR_PERCENTILE | 65.0 | 152 |
| SIDEWAYS_BLOCK_THRESHOLD | 53 | 142 |
| SIDEWAYS_WARNING_THRESHOLD | 43 | 143 |
| EMA_SPREAD_TIGHT/MODERATE/WIDE_ATR | 1.75 / 3.25 / 4.0 | 146-148 |
| ENABLE_RSI_DIVERGENCE_VETO | true | 227 |
| RSI_DIV_LOOKBACK | 16 | 228 |
| RSI_DIV_MIN_PRICE_DIFF_PIPS | 60 | 229 |
| RSI_DIV_MIN_RSI_DIFF | 6.5 | 230 |
| RSI_LEN / ADX_LEN | 14 / 14 | 544-545 |
| ICHIMOKU_TENKAN/KIJUN/SENKOU | 9 / 26 / 52 | 132-134 |
| EMA periods EMA0..4 | 10/25/71/97/192 | 689-693 |
| TF0..TF4 | M1/M3/M5/M15/H1 | 682-686 |
| MAX_SESSION_LOSSES | 4 | 46 |
| MAX_SLTP_COUNT_PER_SESSION | 7 | 45 |
| MAX_HIGH_RISK_TRADES_PER_SESSION | 5 | 44 |
| MAX_SPREAD_PIPS | 0 (off) | 138 |
| MAX_SPREAD_ATR_RATIO | 0.30 | 140 |
| HIGH_RISK_TP_MULTIPLIER_ASIA/EU/US | 0.65/0.65/0.70 | 299-301 |
| E1_MIN_MOMENTUM_ADX (used by E4 high-risk accel) | 19.5 | 302 |
| BLOCK_E4_WHEN_E1_ACTIVE | false | 419 |
| BLOCK_E1_WHEN_E4_ACTIVE | false | 291 |

\* SL parity trap: `CalculateStopLossWithCustomEMA` only branches `entryType==1?E1:E2`, so E4
(entryType=4) silently uses the **E2** arbitration constants (3.0 / 1.1). The E4_ATR_SL_* inputs do not
affect SL.

---

## 9. Reference order-of-operations per M1 bar (for the C++ replay loop)

1. New M1 bar → `UpdateSessionTracking()`, `UpdateIndicatorCache()` (fills cache @ shifts above,
   `cachedATRPercentile`, `cachedSidewaysScore`).
2. `UpdateEmaTouches()` → **arm/expire `lastIchiCloudCrossUp/Down`** (section 1).
3. OnTick safety (daily-loss/drawdown) may set `signalOnlyMode`.
4. `DetectNewEntry()` once/bar: session+extreme-sideway+losing-streak+drawdown guard (section 2) →
   E1,E2,E3 first; if still none → **E4 `Detect()`** (sections 3–6) → `ProcessEntryConvictionAndConfidence`
   (conviction ≥9, section 7).
5. If a trade survives conviction: high-risk routing or normal routing → opposing-position guard →
   consecutive-loss guard → `GetEntryBlockReason()` (incl. **ATR percentile ≥65**) → execute.
