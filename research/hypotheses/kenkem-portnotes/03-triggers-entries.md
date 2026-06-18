# KenKem Triggers & Entries — Port Notes (E1, E2, E4)

Parity map of entry triggers, shared gates, entry-detection order, and SL formulas for porting the
KenKem MQL5 EA to a byte-compatible C++ engine. Scope: **E1, E2, E4 only** (E3/E5 skipped).

All references are to `MQL5/Experts/KenKem/` in the `kenkem` repo. `ENTRY_SHIFT = 1` (entries evaluate
the **closed** bar). All EMA/indicator reads use `[ENTRY_SHIFT]`.

EMA period mapping (from `GetEMA(tf, EMAn, shift)`): `EMA1=25, EMA2=75, EMA3=100, EMA4=200`.
Timeframe index mapping: `TF0=M1, TF1=M3, TF2=M5, TF3=M15`. Cache arrays are indexed
`[0]=M1, [1]=M3, [2]=M5, [3]=M15`.

---

## 1. TRIGGER STATE MACHINES

All three triggers are **global int state variables** set in `Core/Indicators/EMAHelpers.mqh`
(`UpdateEmaTouches()`), consumed in `Detect()`, and reset by setting back to `-1`. A value of `-1`
means "no armed trigger". The stored value is a **bar index** (the bar at which the trigger fired);
"age" = `currentBar - storedValue` (E1/E4) or `barIndex - storedValue` (E2). Setting one direction
also clears the opposite direction (mutual exclusion).

### E1 — EMA-stack crossing (`lastEMACrossingUp` / `lastEMACrossingDown`)

**SET** — `EMAHelpers.mqh:229-257`. A "just crossed" event on ANY of M1/M3/M5, AND M1+M3 currently
aligned:
```mql5
bool m1JustCrossedUp = !isEMAsReadyForEntry(true, TF0, 2, true) && isEMAsReadyForEntry(true, TF0, 1, true);
bool m3JustCrossedUp = !isEMAsReadyForEntry(true, TF1, 2, true) && isEMAsReadyForEntry(true, TF1, 1, true);
bool m5JustCrossedUp = !isEMAsReadyForEntry(true, TF2, 2, false) && isEMAsReadyForEntry(true, TF2, 1, false);

if (lastEMACrossingUp == -1 &&
    (m1JustCrossedUp || m3JustCrossedUp || m5JustCrossedUp) &&
    isEMAsReadyForEntry(true, TF0, 1, true) &&
    isEMAsReadyForEntry(true, TF1, 1, true)) {
    lastEMACrossingUp = currentBar;
    lastEMACrossingDown = -1;          // clears opposite
    ...
}
```
Note "just crossed" = NOT-ready on bar 2 AND ready on bar 1 (a transition between the closed bar and
the prior bar). M5 uses `isStrict=false` (skips the 100>200 leg). DOWN mirror at `:244-257`.

**Secondary SET — EMA200 touch** (`EMAHelpers.mqh:261-283`): if the closed bar's `[low,high]`
straddles EMA200 (`barLow <= ema200 && barHigh >= ema200`) and all-4 EMAs aligned on M1+M3, it ALSO
arms `lastEMACrossingUp/Down = currentBar`. This is an additional way E1 arms — must be ported.

**AGE / EXPIRY** — `Entry1.mqh:103-110`, constant `E1_MAX_CROSS_AGE = 80` (`InputParams.mqh:303`).
Strictly greater-than expires:
```mql5
if (lastEMACrossingUp != -1 && (currentBar - lastEMACrossingUp) > E1_MAX_CROSS_AGE) lastEMACrossingUp = -1;
```

**CONSUME / RESET** — On successful detect, trigger is reset AFTER building the result:
`lastEMACrossingUp = -1;` (`Entry1.mqh:152`), short at `:197`. If gates FAIL, the trigger is **NOT**
reset (hard-block comments: "preserves trigger for re-check next bar"), so it can fire again on a later
bar until it expires.

### E2 — EMA75 touch (`lastEma75TouchUp` / `lastEma75TouchDown`)

**SET** — `EMAHelpers.mqh:290-314`. Closed bar straddles EMA75, direction by CLOSE vs EMA75 (NOT
alignment):
```mql5
if (barLow75 <= ema75 && barHigh75 >= ema75) {
    if (barClose75 > ema75) { lastEma75TouchUp = Bars(_Symbol, TF_ARRAY[TF0]) - 1; lastEma75TouchDown = -1; }
    else if (barClose75 < ema75) { lastEma75TouchDown = Bars(_Symbol, TF_ARRAY[TF0]) - 1; lastEma75TouchUp = -1; }
}
```
**Important:** the stored value is `Bars(_Symbol, TF_ARRAY[TF0]) - 1` (total-bar index), NOT
`currentBar`. Age in `Detect()` uses the same `barIndex = Bars(...) - 1` basis.

**AGE / EXPIRY** — `Entry2.mqh:101-105` (long), `:145-148` (short). Constant
`E2_MAX_TOUCH_AGE = 36` (`InputParams.mqh:327`):
```mql5
int barIndex = Bars(_Symbol, TF_ARRAY[TF0]) - 1;
if (lastEma75TouchUp != -1 && (barIndex - lastEma75TouchUp) > E2_MAX_TOUCH_AGE) lastEma75TouchUp = -1;
```

**CONSUME / RESET** — reset on success only: `lastEma75TouchUp = -1;` (`Entry2.mqh:136`), short `:179`.
Failed gates preserve the trigger.

### E4 — Ichimoku cloud cross (`lastIchiCloudCrossUp` / `lastIchiCloudCrossDown`)

**SET** — `EMAHelpers.mqh:320-366` (only when `ENABLE_E4_ENTRIES`). Requires BOTH M1 and M3 current
clouds to flip to the same color between prev bar and current bar:
```mql5
bool m1CloudBullish_curr = (cache.ichimokuSpanA_M1_Current > cache.ichimokuSpanB_M1_Current);
bool m3CloudBullish_curr = (cache.ichimokuSpanA_M3_Current > cache.ichimokuSpanB_M3_Current);
// prev-bar spans read from ichimokuHandles via CopyBuffer at ENTRY_SHIFT+1
bool bothBullish_curr = m1CloudBullish_curr && m3CloudBullish_curr;
bool bothBullish_prev = m1CloudBullish_prev && m3CloudBullish_prev;
bool ichiJustCrossedUp   = bothBullish_curr && !bothBullish_prev;
bool ichiJustCrossedDown = bothBearish_curr && !bothBearish_prev;   // bothBearish = !m1 && !m3
if (ichiJustCrossedUp && lastIchiCloudCrossUp == -1) { lastIchiCloudCrossUp = currentBar; lastIchiCloudCrossDown = -1; }
if (ichiJustCrossedDown && lastIchiCloudCrossDown == -1) { lastIchiCloudCrossDown = currentBar; lastIchiCloudCrossUp = -1; }
```
Prev cloud uses **current** Senkou spans at `ENTRY_SHIFT+1` (NOT future/shifted cloud — "Pine parity:
NOT future cloud"), buffer 0 = SpanA, buffer 1 = SpanB.

**AGE / EXPIRY** — `Entry4.mqh:107-109` (long), `:159-161` (short). Constant
`E4_MAX_CROSS_AGE = 20` (`InputParams.mqh:437`). Expiry is checked INSIDE the `!= -1` branch
(structure differs from E1):
```mql5
int crossAge = currentBar - lastIchiCloudCrossUp;
if (crossAge > E4_MAX_CROSS_AGE) { lastIchiCloudCrossUp = -1; } else { ...run conditions... }
```

**CONSUME / RESET** — E4 consumes the trigger when conditions PASS, BEFORE building the result
(`Entry4.mqh:117` long, `:169` short): `lastIchiCloudCrossUp = -1;`. Failed gates preserve it.

**Comparison operators recap:** all expiries use strict `>` (`age > MAX`). All trigger-armed checks use
`!= -1`. Cloud color uses strict `>` between spans (equal spans = bearish/non-bullish).

---

## 2. GetTrendQualityScore — `Core/TrendIdentifier.mqh:130-254`

Signature: `int GetTrendQualityScore(TREND_STATE trendState, int entryNum = 0)`. Called with
`entryNum=1` (E1), `2` (E2), `4` (E4). `trendState = isLong ? TREND_BULL : TREND_BEAR`. Score range
**0–11** (no Ichimoku) or **0–13** (with Ichimoku component). Components are summed in this exact order,
with a HARD GATE between component 4 and 5.

| # | Component | Points | Exact thresholds (`TrendIdentifier.mqh`) |
|---|-----------|--------|-------------------------------------------|
| 1 | M1 ADX strength | 0–2 | `adx=cache.adx[0]`; `>=ADX_HIGH_THRESHOLD(25.0)`→2; else `>=MIN_MOMENTUM_ADX_REQUIRED(19.7)`→1; else 0 (`:136-140`) |
| 2 | M1 DI spread (dir.) | 0–2 | `spread = BULL? diPlus[0]-diMinus[0] : diMinus[0]-diPlus[0]`; `>=3.0`→2; `>=1.0`→1; else 0 (`:147-153`) |
| 3 | M1 acceleration | 0–2 | only if `USE_ACCELERATION_BONUS`; `accel5`→2; else `accel3`→1; else 0. `accelN=HasTrendAcceleration(M1,trend,N)` for N=5,3 (`:160-168`) |
| 4 | MTF DI alignment | 0–2 | `alignedCount` = # of M1,M3,M5 where dir-DI agrees (`diPlus>diMinus` for BULL); `==3`→2; `>=2`→1; else 0 (`:175-189`) |
| **GATE** | **HARD GATE** | **return 0** | `if (entryNum != 5 && ENABLE_TREND_QUALITY_GATES && (adxPoints==0 \|\| spreadPoints==0 \|\| mtfPoints==0)) return 0;` (`:200-208`) |
| 5 | Price action | 0–1 | `HasStrongTrendingPriceActions(trend, M1, 5, ENTRY_SHIFT)` → 1 else 0 (`:213-214`) |
| 6 | M3 acceleration | 0–1 | `HasTrendAcceleration(M3, trend, 3)` → 1 else 0 (`:221-222`) |
| 7 | Ichimoku alignment | 0–2 | `CheckIchimokuCloudAlignment(BULL?, entryNum)`; added only `if > 0` (`:229-233`) |
| 8 | ATR health | 0–1 | `cachedATRPercentile >= ATR_PERCENTILE_LOW` → 1 else 0 (`:238`) |

Hard-gate quote (`:200-208`):
```mql5
if (entryNum != 5 && ENABLE_TREND_QUALITY_GATES && (adxPoints == 0 || spreadPoints == 0 || mtfPoints == 0)) {
    ...log...
    return 0;
}
```
**Parity note:** the gate fires when ADX-component OR DI-component OR MTF-component is exactly 0 — it
short-circuits the whole function to `0` (which then fails any `MIN_TREND_QUALITY_E*` threshold). The
Ichimoku (comp 7) only ever adds when positive (never subtracts). Max realistic without Ichimoku = 11,
with = 13.

Per-entry thresholds (`Config/InputParams.mqh:123-127`), score must be `>= MIN`:
- `MIN_TREND_QUALITY_E1 = 6`
- `MIN_TREND_QUALITY_E2 = 9`
- `MIN_TREND_QUALITY_E4 = 9`

Below-threshold = hard block that **preserves the trigger** (re-check next bar).

---

## 3. SHARED GATE FUNCTIONS

### 3.1 HasSufficientMomentum — `TrendIdentifier.mqh:684-687` + `CalculateMomentum :721-737`
`HasSufficientMomentum` just returns the cached value:
```mql5
bool HasSufficientMomentum(TREND_STATE trendState) {
    return (trendState == TREND_BULL) ? cache.hasSufficientBullMomentum : cache.hasSufficientBearMomentum;
}
```
Cache populated each bar (`KenKemExpert.mq5:697-698`) from `CalculateMomentum`:
```mql5
if (REQUIRE_ADX_CONFLUENCE)
    hasStrength = (adx[0]>=E2_MIN_MOMENTUM_ADX) && (adx[1]>=E2_MIN_MOMENTUM_ADX) && (adx[2]>=E2_MIN_MOMENTUM_ADX);
else
    hasStrength = (adx[0]>=E2_MIN_MOMENTUM_ADX) && (adx[1]>=E2_MIN_MOMENTUM_ADX);
double delta = 0.1;
dirOK1 = BULL? (diPlus[0]-diMinus[0] > 0.1) : (diMinus[0]-diPlus[0] > 0.1);   // M1
dirOK3 = ... [1] ...                                                          // M3
dirOK5 = ... [2] ...                                                          // M5
directionAligned = REQUIRE_ADX_CONFLUENCE ? (dirOK1 && dirOK3 && dirOK5) : (dirOK1 && dirOK3);
return hasStrength && directionAligned;
```
Inputs: `E2_MIN_MOMENTUM_ADX = 20.0`, `REQUIRE_ADX_CONFLUENCE = true` (so M1+M3+M5 ADX≥20.0 AND
DI-dir aligned on all three, delta `0.1`). **E1 calls this** (`Entry1.mqh:303`). **E2 deliberately
does NOT** call it (`Entry2.mqh:263-266` — pullbacks flip M1 DI). E4 has its own ADX check instead.

### 3.2 isAllTimeframeEMAsReadyForEntry — `KenKemExpert.mq5:1939-2000`
Branches on entry type. Base alignment via `isEMAsReadyForEntry` (`:1912-1937`) with tolerance
`EMA_ALIGNMENT_TOLERANCE_PIPS = 23.0` pips:
```mql5
// LONG strict: (ema25>ema75-tol) && (ema75>ema100-tol) && (ema100>ema200-tol)
// isStrict=false drops the 100>200 leg.
```
- **E1 branch** (`:1942-1987`): `m1_ready=ready(M1,strict)`, `m3_ready=ready(M3,strict)`,
  `m5_directional = (ema25>ema75 && ema75>ema100 && ema25>ema200)` (no tolerance, M5).
  `extremeMomentum = (BULL? diPlus[0]-diMinus[0] : diMinus[0]-diPlus[0]) >= EXTREME_DI_SPREAD_THRESHOLD(16.0)`.
  Then by `E1_MOMENTUM_BYPASS_LEVEL` (=1):
  - L0: `m1 && m3 && m5_directional`
  - **L1 (active):** `m1_ready && ((m3_ready && m5_directional) || extremeMomentum)`
  - L2: `m1_ready || extremeMomentum`
- **E2/E3 branch** (`:1989-1998`): `m1_ready && m3_ready && m5_ready` (all strict, with tolerance).

E1 calls it with `barShift=ENTRY_SHIFT` (`Entry1.mqh:283`); E2 calls it with `barShift=1`
(`Entry2.mqh:243`) — same value. **E4 does NOT call this**; E4 uses its own `CheckE4EMAAlignmentM1/M3`
(3-stack 25>75>100, no tolerance) — see §4.

### 3.3 Sideways block — `TrendIdentifier.mqh:469-492`
Cached `cachedSidewaysScore` (0–100), updated by `UpdateSidewaysScoreCache()`.
- **Global hard block** (`IsInExtremeSidewayRange`, `:483-486`): `cachedSidewaysScore >= SIDEWAYS_BLOCK_THRESHOLD(53)`.
  Checked once in dispatch (`KenKemExpert.mq5:2165,2170`) — blocks ALL entries that bar.
- **Warning level** (`IsInSidewayRange`, `:489-492`): `>= SIDEWAYS_WARNING_THRESHOLD(43) && < 53`.
  Used by E4 to pick `E4_RR_SIDEWAY` instead of normal RR (`Entry4.mqh:144,195`).
- **E4-specific stricter gate** (`Entry4.mqh:232-235`): `if (cachedSidewaysScore > E4_MAX_SIDEWAY_SCORE(40)) return false;`

### 3.4 RSI divergence veto — `EntryHelpers.mqh:298-372` (`HasRSIDivergenceAgainstTrade`)
Returns true = **block**. Disabled unless `ENABLE_RSI_DIVERGENCE_VETO = true`. Uses M3 (`TF1`) high/low
+ M3 RSI(14), `lookback = RSI_DIV_LOOKBACK(16)`, `halfLB = lookback/2`. Split-window peak/trough:
- LONG (bearish div): find highest-high in recent `[0..halfLB-1]` and older `[halfLB..lookback-1]`;
  `priceDiffPips = (high_recent - high_older)/pipSize`, `rsiDiff = rsi_older - rsi_recent`. Block if
  `priceDiffPips >= RSI_DIV_MIN_PRICE_DIFF_PIPS(60) && rsiDiff >= RSI_DIV_MIN_RSI_DIFF(6.5)`.
- SHORT (bullish div): mirror on lows. Called by all three: E1 `:309`, E2 `:269`, E4 `:373`.

### 3.5 Conviction score — `EntryHelpers.mqh:11-176` (`CalculateConvictionScore`) + HTF veto `:185-214`
`CalculateConvictionScore(isLong, entryType, convictionEnabled, applyTrendVeto)`: returns `999` if
`!convictionEnabled` (bypass). HTF veto (when `applyTrendVeto`): uses confirmation-TF EMA75 vs EMA100
(`emaBuffers[GetEMABufferIndex(CFG.confirmationTFIndex, EMA2 vs EMA3)]`); returns `-999` (hard block) if
LONG & EMA75<EMA100, or SHORT & EMA75>EMA100. Otherwise sums 6 components (each 0–2, **max 12**):
1. M1 DI spread: `>=3.0`→2, `>=1.0`→1 (`:50-51`)
2. EMA stack separation `Calculate4EMAStackSeparation`: `>=0.8`→2, `>=0.5`→1 (`:60-61`)
3. RSI quality (M1+M3 vs 50 + velocity>1.5), clamp 0–2 (`:73-103`)
4. ADX level+accel: `>=23.0`→+1, `<15.0`→−1, accel→+1, clamp 0–2 (`:118-126`)
5. M3+M5 MTF: `m3Strong=(adx>=22 && spread>=2.0)`, `m3Support=(adx>=16 && spread>0.5)`; both strong→2,
   one strong→1, both support→1 (`:144-155`)
6. Price-action structure (`CheckBullish/BearishPriceAction(3)`): aligned→2, neutral→1 (`:160-173`)

Per-entry: gated by `GetUseConvictionScoring()` (`USE_CONVICTION_SCORING_E1/E2/E4`), threshold
`CONVICTION_THRESHOLD_E1/E2/E4`, HTF veto `USE_HTF_VETO_E1/E2/E4`. Note these are applied downstream in
`ProcessEntryConvictionAndConfidence` (KenKemExpert.mq5), NOT inside `CheckE*EntryConditions_Internal`.

---

## 4. ENTRY DETECTION ORDER (DISPATCH) — `KenKemExpert.mq5:2182-2326`

**First-match-wins**, fixed order **E1 → E2 → E3 → E4 → E5**. Each block after E1 is guarded by
`detectedTrade.type == ""` (skip if a prior entry already detected). Dispatch quote (E3/E5 elided):
```mql5
if (ENABLE_E1_ENTRIES) {
    ... PeekDirection() conflict check (BLOCK_E1_WHEN_E4_ACTIVE) ...
    if (!hasActiveE4SameDirection && entry1 != NULL) { entry1Result = entry1.Detect(); ... }
}
if (ENABLE_E2_ENTRIES && detectedTrade.type == "") { entry2Result = entry2.Detect(); ... }
if (ENABLE_E3_ENTRIES && detectedTrade.type == "") { ... }   // out of scope
if (ENABLE_E4_ENTRIES && detectedTrade.type == "") {
    ... PeekDirection() conflict check (BLOCK_E4_WHEN_E1_ACTIVE) ...
    if (!hasActiveE1SameDirection && entry4 != NULL) { entry4Result = entry4.Detect(); ... }
}
if (ENABLE_E5_ENTRIES && detectedTrade.type == "") { ... }   // out of scope
```
Whole dispatch is wrapped (`:2170`) in:
```mql5
if (inValidSession && !isInExtremeSidewayRange && !IsBlockedByLosingStreak() && drawdownCheck && totalBars >= minBarsRequired)
```
Inside each `Detect()`, **long is evaluated first, then short only if `!result.detected`** (e.g.
`Entry1.mqh:113` long, `:160` `if (!result.detected && lastEMACrossingDown != -1 ...)` short).

**Conflict pre-checks (PeekDirection):** before E1 `Detect()`, if `BLOCK_E1_WHEN_E4_ACTIVE`, scan open
`trades[]` for an E4 in the same direction as `entry1.PeekDirection()` → skip E1. Symmetric for E4 vs
E1 (`BLOCK_E4_WHEN_E1_ACTIVE`). `PeekDirection` uses armed-trigger direction, else price-vs-EMA75 (E1,
`Entry1.mqh:321-334`) / price-vs-cloud-top (E4, `Entry4.mqh:442-456`).

**Gate-call order inside each `CheckE*EntryConditions_Internal` (exact):**
- **E1** (`Entry1.mqh:215-315`): (1) `cache.adx[0] < E1_MIN_MOMENTUM_ADX(19.5)` block →
  (2) HTF trend filter `E1_HTF_TREND_FILTER(HTF_M5_ONLY)` → (3) `isAllTimeframeEMAsReadyForEntry("E1")`
  → (4) price vs EMA25 (`currentPrice<=ema25` block long) → (5) `GetTrendQualityScore(.,1) <
  MIN_TREND_QUALITY_E1` hard-block → (6) `HasSufficientMomentum` hard-block → (7) RSI divergence veto.
- **E2** (`Entry2.mqh:192-275`): (1) HTF *strength+direction* filter `E2_HTF_TREND_FILTER(HTF_M15_ONLY)`
  (requires aligned, blocks weak too) → (2) `isAllTimeframeEMAsReadyForEntry("E2")` → (3) price vs
  EMA25 → (4) `GetTrendQualityScore(.,2) < MIN_TREND_QUALITY_E2(9)` hard-block → (no momentum check) →
  (5) RSI divergence veto.
- **E4** (`Entry4.mqh:217-379`): (0) `CheckIchimokuQuality` (cloud thickness/Tenkan-Kijun/Chikou) →
  (0.1) `cachedSidewaysScore > E4_MAX_SIDEWAY_SCORE(40)` → (0.5) HTF filter
  `E4_HTF_TREND_FILTER(HTF_M5_OR_M15)` → (1) `CheckM5DIAlignment` (if `E4_REQUIRE_M5_DI_ALIGN`) →
  (2) `CheckE4EMAAlignmentM1` (ALWAYS required) + M3 align/momentum-bypass
  (`E4_MOMENTUM_BYPASS_LEVEL=1`, bypass if M1-DI spread `>= EXTREME_DI_SPREAD_THRESHOLD(16.0)`) →
  (3) price vs EMA25 AND cloud (5-pip tolerance) → (4) `cache.adx[0] < E4_MIN_MOMENTUM_ADX(19.75)` →
  (5) `GetTrendQualityScore(.,4) < MIN_TREND_QUALITY_E4(9)` hard-block → (6) RSI divergence veto.

HTF filter modes enum: `HTF_DISABLED, HTF_M5_ONLY, HTF_M15_ONLY, HTF_M5_AND_M15, HTF_M5_OR_M15`. Logic
in `Entry1/2/4.mqh` and in `EntryBase::CheckHTFTrendAlignment`. A timeframe is "valid" only if
`adx >= E*_HTF_MIN_ADX && diSpread >= E*_HTF_MIN_DI_SPREAD`; an invalid TF does not block (E1/E4) or
does not count as aligned (E2).

---

## 5. SL FORMULA per entry

Common buffer: `CalculateStopLossWithCustomEMA` (`EntryBase.mqh:637-691`):
`baseSL = isLong? min(recentLow, customEMA) : max(recentHigh, customEMA)`;
`structuredStop = baseSL ∓ SL_EMA_DISTANCE(27)*pipSize`. Optional ATR arbitration (CAP/FLOOR by
`E*_ATR_SL_CAP/FLOOR_MULTIPLIER`, gated by `E*_USE_ATR_SL_ARBITRATION`) on `cache.atrM1`. Then spread
buffer `ApplySpreadBuffer` (min distance = `MIN_SL_SPREAD_MULT(0.5) * spreadPoints * _Point`).
`recentHigh/Low` = `iHighest/iLowest` over `RANGE_HI_LOW_LOOK_BACK_BARS(18)` from `ENTRY_SHIFT`.

- **E1** (`Entry1.mqh:128-138` long, `:174-184` short): custom EMA level =
  `ema100 ∓ 0.75 * |ema100 - ema200|` (long: minus; short: plus). `entryType=1`. Then common pipeline.
  `slDistance = |entry - SL|`; `TP = entry + slDistance*CFG.rrLongE1` (long) / `entry -
  slDistance*CFG.rrShortE1` (short).
- **E2** (`Entry2.mqh:122-129` long, `:165-172` short): uses `CalculateStopLoss(..., EMA3, "E2", 2)`
  → custom EMA = **EMA100 value** (`GetEMA(TF0, EMA3, ENTRY_SHIFT)`), `entryType=2`. Same common
  pipeline. `TP = entry ± slDistance * CFG.rrLongE2/rrShortE2`.
- **E4** (`Entry4.mqh:128-145` long, `:179-196` short): **identical to E1** custom level
  `ema100 ∓ 0.75*|ema100-ema200|`, `entryType=4`. TP uses sideway-aware RR:
  `e4RR = IsInSidewayRange() ? E4_RR_SIDEWAY : CFG.rrLongE4 (long) / CFG.rrShortE4 (short)`.

### RR resolution — `Config/RuntimeConfig.mqh:56-66`
```mql5
CFG.rrLongE1 = E1_RR(1.9);        CFG.rrShortE1 = E1_RR * 0.875;       // 1.6625
CFG.rrLongE2 = E2_RR(1.575);      CFG.rrShortE2 = E2_RR * 0.867;       // 1.3655
CFG.rrLongE4 = E4_RR(2.4);        CFG.rrShortE4 = E4_RR_SHORT(1.8) * 0.875;  // 1.575
```
**Parity trap:** E1/E2 short RR = `*_RR * factor`; E4 short RR = `E4_RR_SHORT * 0.875` (uses a SEPARATE
input `E4_RR_SHORT`, not `E4_RR`). E4 also overrides to `E4_RR_SIDEWAY(1.15)` whenever
`IsInSidewayRange()` (warning band 43–52). `E1_RR_SIDEWAY=1.2`, `E2_RR_SIDEWAY=1.1` exist but E1/E2
`Detect()` use only `CFG.rr*` (sideway RR is applied elsewhere, not in the per-entry TP line shown).

---

## 6. EXACT INPUT VARIABLE NAMES (gates per entry)

Trend-quality min: `MIN_TREND_QUALITY_E1=6`, `MIN_TREND_QUALITY_E2=9`, `MIN_TREND_QUALITY_E4=9`.
RR: `E1_RR=1.9`, `E1_RR_SIDEWAY=1.2`; `E2_RR=1.575`, `E2_RR_SIDEWAY=1.1`; `E4_RR=2.4`,
`E4_RR_SHORT=1.8`, `E4_RR_SIDEWAY=1.15`. Short factors: E1 `*0.875`, E2 `*0.867`, E4 `*0.875`.

Per-entry momentum ADX: `E1_MIN_MOMENTUM_ADX=19.5`, `E2_MIN_MOMENTUM_ADX=20.0`,
`E4_MIN_MOMENTUM_ADX=19.75`. HTF filters: `E1_HTF_TREND_FILTER=HTF_M5_ONLY`
(`E1_HTF_MIN_ADX=18.5`, `E1_HTF_MIN_DI_SPREAD=4.0`); `E2_HTF_TREND_FILTER=HTF_M15_ONLY`
(`E2_HTF_MIN_ADX=23.0`, `E2_HTF_MIN_DI_SPREAD=3.0`); `E4_HTF_TREND_FILTER=HTF_M5_OR_M15`
(`E4_HTF_MIN_ADX=20.5`, `E4_HTF_MIN_DI_SPREAD=6.0`).

Momentum bypass: `E1_MOMENTUM_BYPASS_LEVEL=1`, `E4_MOMENTUM_BYPASS_LEVEL=1`,
`EXTREME_DI_SPREAD_THRESHOLD=16.0`. EMA alignment tol: `EMA_ALIGNMENT_TOLERANCE_PIPS=23.0`.

Trigger ages: `E1_MAX_CROSS_AGE=80`, `E2_MAX_TOUCH_AGE=36`, `E4_MAX_CROSS_AGE=20`.

Shared scoring inputs: `ADX_HIGH_THRESHOLD=25.0`, `MIN_MOMENTUM_ADX_REQUIRED=19.7`,
`REQUIRE_ADX_CONFLUENCE=true`, `ENABLE_TREND_QUALITY_GATES`, `USE_ACCELERATION_BONUS`,
`ATR_PERCENTILE_LOW`. Sideways: `SIDEWAYS_BLOCK_THRESHOLD=53`, `SIDEWAYS_WARNING_THRESHOLD=43`,
`E4_MAX_SIDEWAY_SCORE=40`. RSI div: `ENABLE_RSI_DIVERGENCE_VETO=true`, `RSI_DIV_LOOKBACK=16`,
`RSI_DIV_MIN_PRICE_DIFF_PIPS=60`, `RSI_DIV_MIN_RSI_DIFF=6.5`.

SL: `SL_EMA_DISTANCE=27`, `MIN_SL_SPREAD_MULT=0.5`, `RANGE_HI_LOW_LOOK_BACK_BARS=18`;
`E*_USE_ATR_SL_ARBITRATION`, `E*_ATR_SL_CAP_MULTIPLIER`, `E*_ATR_SL_FLOOR_MULTIPLIER`.

E4 Ichimoku quality: `E4_MIN_CLOUD_THICKNESS_ATR_MULT=0.11`, `E4_REQUIRE_TENKAN_KIJUN_ALIGN=true`,
`E4_REQUIRE_CHIKOU_CLEAR=false`, `E4_REQUIRE_M5_DI_ALIGN=true`, `ADX_LOW_THRESHOLD=14.5`.

Conviction (applied downstream): `USE_CONVICTION_SCORING_E1/E2/E4`, `CONVICTION_THRESHOLD_E1/E2/E4`,
`USE_HTF_VETO_E1/E2/E4`.
