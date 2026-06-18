# SPEC: KenKem E1 / E2 Entry Trigger + Gate Stack (C++ parity)

Ground-truth source: `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/`
All citations are `file:line`. Read-only reverse-engineering; no MQL5 edits.

> **Why the reference run fired only 1 E1 + 1 E2** — the live trigger (`UpdateEmaTouches`)
> RE-ARMS the latch on (almost) every bar, so the trigger is NOT the limiter. The limiter
> is the **gate stack run inside `Detect()` plus the post-detection
> `ProcessEntryConvictionAndConfidence` conviction check**. The gates that kill ~all candidates
> (see §6 "SUPPRESSION SUMMARY"): the **per-component trend-quality hard gate**
> (`ADX>=1pt AND DI>=1pt AND MTF>=1pt`, else score forced to 0) combined with very high score
> minimums (`MIN_TREND_QUALITY_E1=6`, `E2=9` out of 11/13), the strict **multi-TF EMA alignment**
> (E1 M1+M3+M5, E2 M1 AND M3 AND M5), the **HTF filter** (E1 blocks counter-M5; E2 REQUIRES a
> strong aligned M15), and finally the **conviction threshold** (E1>=7, E2>=10 out of 12). A C++
> port that fires E1 ~17x / E2 ~16x is missing one or more of these — most likely the
> trend-quality per-component gate and/or the conviction post-check.

---

## 0. Shared constants / indicator conventions

| Symbol | Value | Source |
|---|---|---|
| `ENTRY_SHIFT` | `1` (detection reads the PREVIOUS/closed bar) | InputParams.mqh:182 |
| EMA index map | `EMA1=25, EMA2=75, EMA3=100, EMA4=200` (EMA0=10 unused here) | GlobalState.mqh:173,185 |
| TF map | `TF0=M1, TF1=M3, TF2=M5, TF3=M15` | InputParams.mqh:682-685 |
| cache.adx/diPlus/diMinus index | `[0]=M1 [1]=M3 [2]=M5 [3]=M15`, read at shift implied by cache (built per closed bar) | TrendIdentifier.mqh:45,59,147-149 |
| `pipSize` | symbol pip (XAU=0.1 typical; BTC per memory) | — |
| RSI_LEN | `14` | InputParams.mqh:544 |

**Indicator shift note:** EMAs/price in the gates are read at `ENTRY_SHIFT` (=1) via `GetEMA(...,ENTRY_SHIFT)` and `iClose(...,ENTRY_SHIFT)`. ADX/DI come from `cache.*` (computed once per closed bar in `UpdateIndicatorCache`, effectively the closed bar). `GetTrendQualityScore` reads `cache.adx[0]` (no shift arg). `HasRSIDivergenceAgainstTrade` copies M3 buffers from `ENTRY_SHIFT`. So: **everything is shift=1 / closed-bar based**, NOT shift 0.

---

## 1. TRIGGER (arming / re-arm / expiry)

All trigger state is set ONCE PER NEW BAR in `UpdateEmaTouches()` (EMAHelpers.mqh:223), called from `OnTick` only on bar change (KenKemExpert.mq5:2430-2447). State vars: `lastEMACrossingUp/Down` (E1), `lastEma75TouchUp/Down` (E2). One-time history seed: `InitializeEMAFlagsFromHistory()` (EMAHelpers.mqh:131) runs once on first bar.

### E1 trigger — `lastEMACrossingUp` / `lastEMACrossingDown`
Armed by EITHER of two mechanisms (whichever sets first; both clear the opposite):

**(a) EMA alignment crossing** (EMAHelpers.mqh:229-257):
```
m1JustCrossedUp = !isEMAsReadyForEntry(LONG,M1,shift=2,strict) && isEMAsReadyForEntry(LONG,M1,shift=1,strict)
m3JustCrossedUp = same on M3
m5JustCrossedUp = same on M5 (strict=false)
if (lastEMACrossingUp == -1
    && (m1JustCrossedUp || m3JustCrossedUp || m5JustCrossedUp)
    && isEMAsReadyForEntry(LONG,M1,1,strict) && isEMAsReadyForEntry(LONG,M3,1,strict)):
        lastEMACrossingUp = currentBar;  lastEMACrossingDown = -1
# DOWN symmetric, EMAHelpers.mqh:244-257
```
`isEMAsReadyForEntry(isLong,tf,shift,strict)` = EMA stack ordering with tolerance (KenKemExpert.mq5:1919):
```
tol = EMA_ALIGNMENT_TOLERANCE_PIPS * pipSize        # 23.0 pips, InputParams.mqh:224
LONG  : (e25 > e75-tol) && (e75 > e100-tol) && (strict ? e100 > e200-tol : true)
SHORT : (e25 < e75+tol) && (e75 < e100+tol) && (strict ? e100 < e200+tol : true)
```

**(b) EMA200 touch** (EMAHelpers.mqh:259-283): if bar[shift=1] low<=EMA200<=high AND all-4-EMA aligned on M1(strict)&M3(strict) → set `lastEMACrossingUp=currentBar` (or Down). Same latch.

**E1 expiry** (inside `Detect`, Entry1.mqh:103-110):
```
if lastEMACrossingUp != -1 && (currentBar - lastEMACrossingUp) > E1_MAX_CROSS_AGE: reset to -1
# E1_MAX_CROSS_AGE = 80 bars (InputParams.mqh:303); same for Down
```
**E1 reset-on-fire:** on a successful detection the used latch is reset to -1 (Entry1.mqh:152,197), so it must be re-armed by a new cross before E1 can fire again.

### E2 trigger — `lastEma75TouchUp` / `lastEma75TouchDown`
Armed by EMA75 touch (EMAHelpers.mqh:285-314), direction by CLOSE position (NOT alignment):
```
ema75 = GetEMA(M1,EMA2,ENTRY_SHIFT); low/high/close at ENTRY_SHIFT
if low <= ema75 <= high:
    if close > ema75: lastEma75TouchUp   = Bars(M1)-1; lastEma75TouchDown = -1
    elif close < ema75: lastEma75TouchDown = Bars(M1)-1; lastEma75TouchUp = -1
```
NOTE: touch stores `Bars(_Symbol,M1)-1` (absolute newest index), whereas E1 stores `currentBar`. Age math in `Detect` uses `barIndex = Bars(M1)-1` (Entry2.mqh:101).

**E2 expiry** (Entry2.mqh:102-105, 145-148):
```
if lastEma75TouchUp != -1 && (barIndex - lastEma75TouchUp) > E2_MAX_TOUCH_AGE: reset -1
# E2_MAX_TOUCH_AGE = 36 bars (InputParams.mqh:327); same for Down
```
**E2 reset-on-fire:** used latch reset to -1 on detection (Entry2.mqh:136,179).

> Because the latch re-arms almost every bar (any new touch / any fresh alignment), a naive C++
> port that simply "fires when latch set" will over-fire. Fidelity requires the FULL gate stack below.

---

## 2 & 3. GATE STACK (exact order) + CONVICTION

`Detect()` runs the entry-internal gates; if it returns `detected`, the dispatcher
(`DetectNewEntry`, KenKemExpert.mq5:2189-2241) then calls `ProcessEntryConvictionAndConfidence`
(KenKemExpert.mq5:1750) which applies the conviction gate, then risk/high-risk/session gates.
A LONG is attempted first; SHORT only if LONG not detected (Entry1.mqh:160 / Entry2.mqh:149).

### --- E1 GATE STACK ---

**Pre-Detect dispatcher gates (apply to BOTH E1 & E2, KenKemExpert.mq5:2153-2177):**
```
G0a inValidSession = IsNowInValidSession() || IGNORE_VALID_SESSIONS
G0b !IsInExtremeSidewayRange()      # cachedSidewaysScore >= SIDEWAYS_BLOCK_THRESHOLD(53) blocks ALL
G0c !IsBlockedByLosingStreak()
G0d !IsDrawdownBlocked()            # (signalOnly bypasses)
G0e totalBars >= ENTRY_SHIFT+2
G0f (E1 only) BLOCK_E1_WHEN_E4_ACTIVE && same-dir E4 open  -> skip  (default false → no-op)
```
`IsInExtremeSidewayRange` uses `cachedSidewaysScore` (0-100, TrendIdentifier.mqh:390-466), threshold `SIDEWAYS_BLOCK_THRESHOLD=53` (InputParams.mqh:142). Score computed at `ENTRY_SHIFT`.

**Inside `Entry1::Detect` (Entry1.mqh:84-...):**
```
E1.1 sessionLossCount >= MAX_SESSION_LOSSES(4)  -> return none        # :84
E1.2 tradeSLTPCountInSession > MAX_SLTP_COUNT_PER_SESSION(7) -> none  # :90
E1.3 latch expiry (E1_MAX_CROSS_AGE=80)                               # :103
E1.4 require latch set AND no open same-side E1 (checkOpenLE1==-1)    # :113
```
Then `CheckE1EntryConditions_Internal` (Entry1.mqh:215), IN ORDER:
```
E1.5  ADX floor:  cache.adx[0] < E1_MIN_MOMENTUM_ADX(19.5)  -> reject       # :222
E1.6  HTF filter (E1_HTF_TREND_FILTER = HTF_M5_ONLY):                       # :231-280
        m5 valid iff cache.adx[2] >= E1_HTF_MIN_ADX(18.5)
                   && |diPlus[2]-diMinus[2]| >= E1_HTF_MIN_DI_SPREAD(4.0)
        if m5Valid: blockLong = m5Bearish ; blockShort = m5Bullish
        (counter-trend block only; if m5 invalid → no block)
E1.7  MTF EMA alignment isAllTimeframeEMAsReadyForEntry("E1",isLong,1):     # :283
        m1_ready & m3_ready = strict stack(M1,1) & strict stack(M3,1)
        m5_directional = (e25>e75>e100 && e25>e200) [LONG] (mirror SHORT)
        extremeMomentum = |diPlus[0]-diMinus[0]| >= EXTREME_DI_SPREAD_THRESHOLD(16.0)
        E1_MOMENTUM_BYPASS_LEVEL = 1:
            pass = m1_ready && ((m3_ready && m5_directional) || extremeMomentum)
E1.8  price vs EMA25: (LONG && price<=ema25) || (SHORT && price>=ema25) -> reject  # :290
        price = iClose(M1,ENTRY_SHIFT); ema25 = GetEMA(M1,EMA1,ENTRY_SHIFT)
E1.9  trendQuality = GetTrendQualityScore(BULL/BEAR, entryNum=1)            # :297
        if trendQuality < MIN_TREND_QUALITY_E1(6) -> reject  (HARD BLOCK, latch kept)
E1.10 HasSufficientMomentum(trend) == false -> reject  (HARD BLOCK)        # :303
        = cache.hasSufficientBull/BearMomentum (precomputed via CalculateMomentum)
E1.11 HasRSIDivergenceAgainstTrade(isLong) == true -> reject              # :309
return true
```
**On pass:** compute SL/TP (§4), set `result.detected`, RESET latch (Entry1.mqh:152/197).

**Post-detect conviction (ProcessEntryConvictionAndConfidence, KenKemExpert.mq5:1828-1854):**
```
useConviction = USE_CONVICTION_SCORING_E1 = true
threshold = CONVICTION_THRESHOLD_E1 = 7
score = CalculateConvictionScore(isLong, E1, true, useHTFVeto=USE_HTF_VETO_E1=false)   # 0..12
if score < 7: isLowConfidence=true -> (SEND_LOW_CONFIDENCE_SIGNALS=false) -> trade.type="" (SKIPPED)
```

**Post-detect risk / high-risk gates (KenKemExpert.mq5:2346-2374):**
```
riskDistance = |SL-entry|; potentialLossUSD = riskDistance * lot * contractSize
if potentialLossUSD >= getMaxLossUSD(E1):  HandleHighRiskEntry()             # :2351
     - ACCEPT_HIGH_RISK_E1_ENTRIES must be true (it is)                      # :2034
     - highRiskTradesInSession < MAX_HIGH_RISK_TRADES_PER_SESSION(5)         # :2040
     - !IsInSidewayRange(10)                                                 # :2044
     - CheckMomentumForLevel(HIGH_RISK_E1_MOMENTUM_CHECK=M1_AND_M3, ...)     # :2055
       -> HasStrictMomentumForHighRisk on M1 AND M3 with
          adx>=E1_HIGH_RISK_MIN_ADX(19.5), DIspread>=E1_HIGH_RISK_MIN_DI_SPREAD(4.0)
else: HasOpposingDirectionPosition -> block; IsEntryTypeBlocked -> block; GetEntryBlockReason
```
`MAX_LOSS_RATIO_E1 = COMMON_MAX_RISK_PER_TRADE(0.02) * 1.05 = 0.021` (InputParams.mqh:62,65).

### --- E2 GATE STACK ---

Pre-Detect dispatcher gates G0a-G0e identical (E2 has no E4-block; runs only if `detectedTrade.type==""` i.e. E1 didn't fire — KenKemExpert.mq5:2222).

**Inside `Entry2::Detect` (Entry2.mqh:74-...):**
```
E2.1 sessionLossCount >= MAX_SESSION_LOSSES(4) -> none                      # :81
E2.2 tradeSLTPCountInSession > MAX_SLTP_COUNT_PER_SESSION(7) -> none        # :87
E2.3 barIndex = Bars(M1)-1; touch expiry (E2_MAX_TOUCH_AGE=36)             # :102
E2.4 require touch latch set AND no open same-side E2 (checkOpenLE2==-1)    # :106
```
Then `CheckE2EntryConditions_Internal` (Entry2.mqh:192), IN ORDER:
```
E2.5  HTF filter (E2_HTF_TREND_FILTER = HTF_M15_ONLY) — REQUIRES STRONG ALIGNED:  # :202-239
        m15Aligned iff cache.adx[3] >= E2_HTF_MIN_ADX(23.0)
                    && |diPlus[3]-diMinus[3]| >= E2_HTF_MIN_DI_SPREAD(3.0)
                    && (DI direction matches trade direction)
        htfOK = m15Aligned ; if !htfOK -> reject
        *** This is STRICTER than E1: E2 blocks on WEAK macro trend, not just counter-trend ***
E2.6  MTF EMA alignment isAllTimeframeEMAsReadyForEntry("E2",isLong,1):     # :243
        E2/E3 branch: m1_ready && m3_ready && m5_ready  (ALL THREE strict stacks, tol=23p)
        (no momentum bypass for E2)
E2.7  price vs EMA25 (same as E1.8)                                         # :249
E2.8  trendQuality = GetTrendQualityScore(BULL/BEAR, entryNum=2)            # :257
        if trendQuality < MIN_TREND_QUALITY_E2(9) -> reject (HARD BLOCK)
E2.9  (HasSufficientMomentum DELIBERATELY OMITTED for E2 — Entry2.mqh:263-266)
E2.10 HasRSIDivergenceAgainstTrade(isLong) == true -> reject              # :269
return true
```
**Post-detect conviction (KenKemExpert.mq5:1844-1854):**
```
useConviction = USE_CONVICTION_SCORING_E2 = true
threshold = CONVICTION_THRESHOLD_E2 = 10                                    # very high
score = CalculateConvictionScore(isLong, E2, true, USE_HTF_VETO_E2=false)  # 0..12
if score < 10: SKIP
```
**Post-detect risk gates:** same path; high-risk uses `HIGH_RISK_E2_MOMENTUM_CHECK=M1_AND_M3`,
`E2_HIGH_RISK_MIN_ADX=21.5`, `E2_HIGH_RISK_MIN_DI_SPREAD=5.0`. `MAX_LOSS_RATIO_E2 = 0.02*1 = 0.02`.

---

## 3b. CONVICTION FORMULA (CalculateConvictionScore, EntryHelpers.mqh:11-176)
Shared by E1 & E2; all reads at `ENTRY_SHIFT`. Returns 0..12. (`return 999` if conviction disabled.)
```
if applyTrendVeto(false here): HTF veto via confirmationTFIndex(=TF2=M5) EMA75 vs EMA100 -> -999  # :18-43 (inactive, veto off)

C1 M1_DI (0-2):   spread=isLong? diP[0]-diM[0] : diM[0]-diP[0]
                  >=3.0 ->2 ; >=1.0 ->1 ; else 0                            # :47-52
C2 EMA_SEP (0-2): sep = Calculate4EMAStackSeparation(isLong)               # :58 / :220-240
                  (avg of |25-75|,|75-100|,|100-200| in pips /30, 0 if not ordered)
                  >=0.8 ->2 ; >=0.5 ->1 ; else 0
C3 RSI (0-2):     rsi_m1=RSI(M1,14,shift1), rsi_m1_prev=RSI(M1,14,shift3), rsi_m3=RSI(M3,14,shift1)  # :69-103
                  LONG: (m1>50 & m3>50)->+2 elif (m1>50||m3>50)->+1 ; +1 if velocity>1.5 & m1>50 ; clamp[0,2]
                  SHORT mirror (<50, falling)
C4 ADX (0-2):    adx=cache.adx[0]; >=23 ->+1 ; <15 ->-1 ; +1 if IsAccelerating(adx,3); clamp[0,2]  # :108-126
C5 MTF (0-2):    m3Strong=(adx[1]>=22 & spread3>=2); m5Strong=(adx[2]>=22 & spread5>=2)              # :130-157
                  m3Support=(adx[1]>=16 & spread3>0.5); m5Support=(adx[2]>=16 & spread5>0.5)
                  both strong ->2 ; one strong ->1 ; both support ->1 ; else 0
C6 PA (0-2):     bullPA=CheckBullishPriceAction(3) (>=2/3 bull bars); bearPA=CheckBearishPriceAction(3)  # :160-173
                  LONG&bull ->2 ; LONG&!bear ->1 ; (mirror SHORT) ; else 0
score = C1+C2+C3+C4+C5+C6   (max 12)
PASS E1 iff score>=7 ; PASS E2 iff score>=10
```

---

## 3c. TREND-QUALITY SCORE (the primary suppressor) — GetTrendQualityScore (TrendIdentifier.mqh:130-254)
Reads `cache.*` (closed bar). `entryNum`=1 for E1, =2 for E2.
```
COMP1 ADX (0-2): adx=cache.adx[0]; >=ADX_HIGH_THRESHOLD(25)->2 ; >=MIN_MOMENTUM_ADX_REQUIRED(19.7)->1 ; else0  # :136-139
COMP2 DI  (0-2): spread=isBull? diP[0]-diM[0] : diM[0]-diP[0]; >=3.0->2 ; >=1.0->1 ; else0                     # :147-153
COMP3 M1Accel (0-2): if USE_ACCELERATION_BONUS(true): accel5->2 elif accel3->1 (HasTrendAcceleration M1)        # :158-168
COMP4 MTF (0-2): count of {M1,M3,M5} DI-direction-agree; ==3->2 ; >=2->1 ; else0                                # :173-191

*** HARD GATE (TrendIdentifier.mqh:200-208) ***
if entryNum!=5 && ENABLE_TREND_QUALITY_GATES(true) && (COMP1==0 || COMP2==0 || COMP4==0):
     return 0     # <-- forces score to ZERO, guaranteeing < MIN_TREND_QUALITY -> REJECT

COMP5 PA (0-1):  HasStrongTrendingPriceActions(trend,M1,5,ENTRY_SHIFT)                                          # :213
COMP6 M3Accel (0-1): HasTrendAcceleration(M3,trend,3)                                                           # :221
COMP7 Ichimoku (0-2): CheckIchimokuCloudAlignment — E1 uses it (USE_ICHIMOKU_E1=true), E2 does NOT (E2=false)   # :229
COMP8 ATR (0-1): (cachedATRPercentile >= ATR_PERCENTILE_LOW(20.0)) ?1:0                                         # :238
return score   # E1 max 13 (with Ichimoku), E2 max 11
```
Minimums: `MIN_TREND_QUALITY_E1 = 6`, `MIN_TREND_QUALITY_E2 = 9` (InputParams.mqh:123,125).
**E2 needs 9/11 with NO Ichimoku bonus available → extremely strict.**

`HasSufficientMomentum` (E1 only): `cache.hasSufficientBull/BearMomentum`, derived from
`CalculateMomentum` (TrendIdentifier.mqh:721-737):
```
REQUIRE_ADX_CONFLUENCE(true): adx[0]>=E2_MIN_MOMENTUM_ADX(20) && adx[1]>=20 && adx[2]>=20
direction: (diP-diM>0.1) on M1 AND M3 AND M5     # all-3 alignment
```

`HasRSIDivergenceAgainstTrade` (E1 & E2, EntryHelpers.mqh:298): `ENABLE_RSI_DIVERGENCE_VETO=true`,
`RSI_DIV_LOOKBACK=16` M3 bars (from ENTRY_SHIFT), split-window peak/trough; blocks if
priceDiff>=`RSI_DIV_MIN_PRICE_DIFF_PIPS(60)` AND rsiDiff>=`RSI_DIV_MIN_RSI_DIFF(6.5)`.

---

## 4. SL / TP

### E1 SL (Entry1.mqh:124-144) — custom EMA level
```
recentHigh = iHigh(highest over RANGE_HI_LOW_LOOK_BACK_BARS=18 from ENTRY_SHIFT)
recentLow  = iLow (lowest  over 18 from ENTRY_SHIFT)
ema100 = GetEMA(M1,EMA3,1); ema200 = GetEMA(M1,EMA4,1); emaDist=|ema100-ema200|
LONG  e1SLLevel = ema100 - emaDist*0.75
SHORT e1SLLevel = ema100 + emaDist*0.75
SL = CalculateStopLossWithCustomEMA(isLong, price, recentHigh, recentLow, e1SLLevel, "E1", 1, ...)
TP = LONG ? price + slDist*CFG.rrLongE1 : price - slDist*CFG.rrShortE1
     slDist = |price - SL|
```

### E2 SL (Entry2.mqh:117-129) — EMA100 reference (period EMA3)
```
recentHigh/recentLow as above (18 bars from ENTRY_SHIFT)
SL = CalculateStopLoss(isLong, price, recentHigh, recentLow, emaReference=EMA3(=100), "E2", 2, ...)
     -> emaValue = GetEMA(M1,EMA3,ENTRY_SHIFT) then same custom-EMA routine
TP = LONG ? price + slDist*CFG.rrLongE2 : price - slDist*CFG.rrShortE2
```

### CalculateStopLossWithCustomEMA (EntryBase.mqh:637-691)
```
baseSL = LONG ? min(recentLow, emaLevel) : max(recentHigh, emaLevel)
structuredStop = LONG ? baseSL - SL_EMA_DISTANCE(27)*pip : baseSL + 27*pip
# ATR arbitration (E1_USE_ATR_SL_ARBITRATION=true / E2=true), cache.atrM1>0:
structDistPips = |price-structuredStop|/pip ; atrPips = atrM1/pip
capPips   = atrPips * (E1:4.0 / E2:3.0)         # E1_ATR_SL_CAP_MULTIPLIER / E2
floorPips = atrPips * (E1:1.2 / E2:1.1)         # E1_ATR_SL_FLOOR_MULTIPLIER / E2
final = structDistPips ; if final>capPips: final=capPips ; if final<floorPips: final=floorPips
if final != structDistPips: structuredStop = price -/+ final*pip
# spread buffer:
return CalculateBufferedStopWithSpread(isLong, price, structuredStop, minSLSpreadMultiplier=MIN_SL_SPREAD_MULT(0.5), ...)
```
`SL_EMA_DISTANCE=27` (InputParams.mqh:187), `MIN_SL_SPREAD_MULT=0.5` (:188).

### RR plumbing (RuntimeConfig.mqh:56-60)
```
CFG.rrLongE1 = E1_RR(1.9)         CFG.rrShortE1 = E1_RR*0.875 = 1.6625
CFG.rrLongE2 = E2_RR(1.575)       CFG.rrShortE2 = E2_RR*0.867 ≈ 1.3655
```
(Sideway RR `E1_RR_SIDEWAY=1.2`, `E2_RR_SIDEWAY=1.1` applied elsewhere via `IsInSidewayRange`,
KenKemExpert.mq5:1540-1568 — used in TP-extension/RR-adjust path, not the base Detect TP above.)

---

## 5. DEFAULTS (every param E1/E2 touch) — InputParams.mqh / RuntimeConfig.mqh

| Param | Default | Line |
|---|---|---|
| ENABLE_E1_ENTRIES / E2 | true / true | 56,57 |
| ENABLE_ADAPTIVE_E1 / E2 | false / false | 567,568 |
| SEND_LOW_CONFIDENCE_SIGNALS | false | 589 |
| ENTRY_SHIFT | 1 | 182 |
| RANGE_HI_LOW_LOOK_BACK_BARS | 18 | 214 |
| MAX_SESSION_LOSSES | 4 | 46 |
| MAX_SLTP_COUNT_PER_SESSION | 7 | 45 |
| MAX_HIGH_RISK_TRADES_PER_SESSION | 5 | 44 |
| **E1_MAX_CROSS_AGE** | **80** | 303 |
| **E2_MAX_TOUCH_AGE** | **36** | 327 |
| EMA_ALIGNMENT_TOLERANCE_PIPS | 23.0 | 224 |
| EXTREME_DI_SPREAD_THRESHOLD | 16.0 | 233 |
| E1_MOMENTUM_BYPASS_LEVEL | 1 | 304 |
| BLOCK_E1_WHEN_E4_ACTIVE | false | 291 |
| E1_MIN_MOMENTUM_ADX | 19.5 | 302 |
| E2_MIN_MOMENTUM_ADX | 20.0 | 326 |
| E1_HTF_TREND_FILTER | HTF_M5_ONLY | 292 |
| E1_HTF_MIN_ADX / DI_SPREAD | 18.5 / 4.0 | 293,294 |
| E2_HTF_TREND_FILTER | HTF_M15_ONLY | 328 |
| E2_HTF_MIN_ADX / DI_SPREAD | 23.0 / 3.0 | 329,330 |
| **MIN_TREND_QUALITY_E1** | **6** | 123 |
| **MIN_TREND_QUALITY_E2** | **9** | 125 |
| ENABLE_TREND_QUALITY_GATES | true | 122 |
| USE_ACCELERATION_BONUS | true | 131 |
| ADX_HIGH_THRESHOLD | 25.0 | 222 |
| MIN_MOMENTUM_ADX_REQUIRED | 19.7 | 220 |
| REQUIRE_ADX_CONFLUENCE | true | 223 |
| ATR_PERCENTILE_LOW | 20.0 | 149 |
| USE_ICHIMOKU_E1 / E2 | true / false | 124,126 |
| **USE_CONVICTION_SCORING_E1 / E2** | **true / true** | 107,109 |
| **CONVICTION_THRESHOLD_E1 / E2** | **7 / 10** | 108,110 |
| USE_HTF_VETO_E1 / E2 | false / false | 114,115 |
| ENABLE_RSI_DIVERGENCE_VETO | true | 227 |
| RSI_DIV_LOOKBACK | 16 | 228 |
| RSI_DIV_MIN_PRICE_DIFF_PIPS | 60 | 229 |
| RSI_DIV_MIN_RSI_DIFF | 6.5 | 230 |
| SIDEWAYS_BLOCK_THRESHOLD | 53 | 142 |
| SIDEWAYS_WARNING_THRESHOLD | 43 | 143 |
| EMA_SPREAD_TIGHT/MODERATE/WIDE_ATR | 1.75 / 3.25 / 4.0 | 146-148 |
| ACCEPT_HIGH_RISK_E1 / E2 | true / true | 295,322 |
| HIGH_RISK_E1 / E2_MOMENTUM_CHECK | M1_AND_M3 / M1_AND_M3 | 296,323 |
| E1_HIGH_RISK_MIN_ADX / DI | 19.5 / 4.0 | 297,298 |
| E2_HIGH_RISK_MIN_ADX / DI | 21.5 / 5.0 | 324,325 |
| MAX_LOSS_RATIO_E1 / E2 | 0.021 / 0.02 | 65,66 |
| COMMON_MAX_RISK_PER_TRADE | 0.02 | 62 |
| SL_EMA_DISTANCE | 27 | 187 |
| MIN_SL_SPREAD_MULT | 0.5 | 188 |
| E1_ATR_SL_ARBITRATION/CAP/FLOOR | true / 4.0 / 1.2 | 191-193 |
| E2_ATR_SL_ARBITRATION/CAP/FLOOR | true / 3.0 / 1.1 | 194-196 |
| E1_RR / E1_RR_SIDEWAY | 1.9 / 1.2 | 305,306 |
| E2_RR / E2_RR_SIDEWAY | 1.575 / 1.1 | 331,332 |
| RSI_LEN / RSI_BULL / RSI_BEAR | 14 / 70 / 30 | 544,546,547 |
| CFG.confirmationTFIndex | TF2 (M5; useS30=false) | RuntimeConfig 47-53 |

> ⚠ The `.set` actually loaded in the reference MT5 run can override ANY of these. Pin every
> behavioral key from the run's `.set`; these are CODE defaults only. (Per project memory: the
> `baseline.set` differs from code defaults — confirm against the real tester `.set`.)

---

## 6. SUPPRESSION SUMMARY (why 1 E1 + 1 E2)

Ranked by expected kill-rate; a C++ port over-firing must be missing these:

1. **Trend-quality per-component HARD GATE** (TrendIdentifier.mqh:200): if ADX-pts OR DI-pts OR
   MTF-pts == 0, score is FORCED to 0 → always rejected. Most "armed" bars die here.
2. **High score minimums**: E1 needs >=6, **E2 needs >=9/11 with no Ichimoku** — a brutal cut.
3. **Conviction post-gate** (E1>=7, E2>=10 of 12; EntryHelpers.mqh:11): even after Detect passes,
   most setups score <7/<10 and are silently skipped (`SEND_LOW_CONFIDENCE_SIGNALS=false`).
4. **Strict multi-TF EMA alignment** with tol=23p: E1=M1&M3&M5(or extreme-DI bypass);
   E2 = M1 AND M3 AND M5 all strict (no bypass).
5. **HTF filter**: E1 blocks counter-M5; **E2 REQUIRES a strong, aligned M15** (adx>=23 & DI>=3 &
   correct direction) — rejects whenever macro is weak/flat.
6. **ADX floor** (E1 adx[0]>=19.5) + **HasSufficientMomentum** (E1: ADX>=20 confluence on M1&M3&M5
   AND DI direction on all three).
7. **RSI-divergence veto** (M3, 16-bar) + **price-vs-EMA25** + **sideways block (score>=53)**.
8. **Single-fire reset**: latch reset on fire + "no open same-side Ex" check → at most one open
   E1 and one open E2 at a time; further fires need full re-arm + re-pass of all gates.

Net effect: the trigger arms often, but the conjunction of (per-component gate × high score min ×
conviction × strict MTF × HTF) lets through ~1 qualifying setup each in the reference window.
A C++ port firing 17/16 is almost certainly skipping #1 (per-component zero-gate) and/or #3
(conviction) and/or applying loose EMA tolerance / missing the E2 M15-required HTF rule.
