# KenKem EA — Shared Decision Pipeline Spec (for C++ parity)

Source of truth: `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/`
All citations are `file:line` against the **non-versioned** files (`KenKemExpert.mq5`, not the `*-dev.mq5` snapshots).
Broker feed = UTC+0. EA derives JST as `UTC + 9h` (TimeGMT-based).

Timeframe map (`Config/InputParams.mqh:682-686`, `Core/GlobalState.mqh:177,193`):
`TF0=M1, TF1=M3, TF2=M5, TF3=M15, TF4=H1`. `NUM_TF` loop covers M1/M3/M5/M15.
`ENTRY_SHIFT = 1` (`InputParams.mqh:182`) → almost every indicator read is on the **last CLOSED bar**, not the forming bar. Exceptions noted inline.

---

## 1. OnTick — ORDER OF OPERATIONS

`OnTick()` @ `KenKemExpert.mq5:2393`. Pseudocode (exact order):

```
OnTick():
  if eaStartTime==0: eaStartTime = TimeCurrent()                      # 2395
  if !TERMINAL_CONNECTED:    return                                   # 2407  (grace 30s)
  if !TERMINAL_TRADE_ALLOWED: return                                  # 2415
  CloseAllPositionsBeforeHighImpactNews()                             # 2424

  currentBar = Bars(_Symbol, M1) - 1                                  # 2427

  # ---- NEW BAR BLOCK (runs once per closed M1 bar) ----            # 2430
  if currentBar != lastBarIndex:
      lastBarIndex = currentBar
      UpdateSessionTracking()        # session rollover + counter reset  # 2434
      UpdateIndicatorCache()         # ALL heavy indicator reads        # 2437
      (BarTrace export)                                                 # 2440
      UpdateEmaTouches()             # E2 EMA75-touch state machine      # 2447
      if !emaHistoryInitialized: InitializeEMAFlagsFromHistory()        # 2450
      CloseAllTradesAtSessionEnd()                                      # 2456

  # ---- EVERY TICK ----
  if tradeManager != NULL: tradeManager.ProcessAllTrades()  # MANAGE OPEN TRADES FIRST  # 2461
                                                            # (TP/SL/partial/trail/exits)

  signalOnlyMode = false                                              # 2467
  if !IsWithinDailyLossLimit():  signalOnlyMode=true (or return)      # 2469
  if IsDrawdownBlocked():        signalOnlyMode=true (or return)      # 2475
  if !IsWithinDrawdownLimit():   signalOnlyMode=true (or return)      # 2481
      # "or return" only when SIGNAL_ONLY_DURING_PROTECTION==false (default TRUE → set flag)

  if ENABLE_LIMIT_ORDERS: ManagePendingOrders()                      # 2491 (limit orders OFF by default)

  # ---- ENTRY DETECTION: ONCE PER BAR ----                          # 2494
  if currentBar != lastEntryBarIndex:
      lastEntryBarIndex = currentBar
      DetectNewEntry(signalOnlyMode)

  (TradeJournal poll LAST)                                            # 2501
```

Key parity facts:
- **ProcessAllTrades runs BEFORE DetectNewEntry**, every tick (`2461` < `2496`). Exits on a tick are seen before that tick's entry attempt.
- `UpdateIndicatorCache` is **idempotent per bar**: `if lastCachedBar==currentBar && cache.valid: return` (`KenKemExpert.mq5:679`).
- **Entry detection is gated to once per bar** by `lastEntryBarIndex` (`2494`). At most ONE entry per M1 bar can be created — `DetectNewEntry` fills a single `detectedTrade` and stops at the first hit.

### Entry detection order inside `DetectNewEntry` (`2149`)
One shared `detectedTrade`; each block runs only if `detectedTrade.type == ""` (i.e. nothing detected yet) → **strict precedence, first match wins**:

```
order: E1 (2189) → E2 (2222) → E3 (2242) → E4 (2282) → E5 (2315)
each guarded by ENABLE_Ex && detectedTrade.type==""    # except E1 has no =="" guard (runs first)
```
Default enables (`InputParams.mqh:56-60`): **E1=on, E2=on, E3=OFF, E4=on, E5=OFF**. So live order is **E1 → E2 → E4**.

Per-entry cross-blocks evaluated before calling `entryN.Detect()`:
- E1: skip if `BLOCK_E1_WHEN_E4_ACTIVE` and a same-direction E4 is open (`2192-2202`). Default `BLOCK_E1_WHEN_E4_ACTIVE=false` (`InputParams.mqh:291`) → never skips.
- E3: `E3_BLOCK_WHEN_TREND_ACTIVE` opposite-trend block + `entry3.ShouldCheckE3()` pre-gate (`2244-2261`).
- E4: skip if `BLOCK_E4_WHEN_E1_ACTIVE` and same-direction E1 open (`2284-2293`). Default false (`InputParams.mqh:419`).

### Post-detection dispatch (`2335-2376`) — the SHARED gate funnel
```
if detectedTrade.type != "":
  entryDetectedCount++
  if signalOnlyMode:
      EnterOrSkipTrade(false, "SIGNAL ONLY ...")                 # never executes
  else:
      riskDistance = |SL - entry|
      potentialLossUSD = riskDistance * lot * contractSize
      entryMaxLoss = getMaxLossUSD(entryType)
      if potentialLossUSD >= entryMaxLoss:
          HandleHighRiskEntry(...)                               # 2018 separate gate chain
      else:
          if HasOpposingDirectionPosition(isLong):  skip         # 2356
          elif IsEntryTypeBlocked(type):            skip         # 2361 per-type consec-loss block
          else:
              blockReason = GetEntryBlockReason()                # 2366 → RiskManager.mqh:241
              if blockReason != "": skip
              else: EnterOrSkipTrade(true, "Good Setup!")        # 2371 EXECUTE
```

### Outer gate around the whole detection (`DetectNewEntry`, `2153-2177`)
```
inValidSession = IsNowInValidSession() || IGNORE_VALID_SESSIONS   # 2153
isInExtremeSidewayRange = IsInExtremeSidewayRange()               # 2172  (sideways score >= 53)
drawdownCheck = signalOnlyMode ? true : !IsDrawdownBlocked()
if (inValidSession && !isInExtremeSidewayRange
    && !IsBlockedByLosingStreak()                                 # 2177 global loss-streak timer
    && drawdownCheck && totalBars >= ENTRY_SHIFT+2):
    ... run E1..E5 ...
```

**Conviction/quality filtering** happens inside each `entryN.Detect()` and inside `ProcessEntryConvictionAndConfidence` (`1750`), which can null `detectedTrade.type` (set `""`) to suppress a low-confidence setup (`1873,1876`) BEFORE the dispatch funnel above.

---

## 2. CONCURRENCY & COOLDOWN  (what enforces ~1 trade/day)

All defaults from `Config/InputParams.mqh`.

| Mechanism | Param / default | Where enforced |
|---|---|---|
| One entry per **bar** | `lastEntryBarIndex` | `KenKemExpert.mq5:2494` |
| One entry per **DetectNewEntry call** (first match) | `detectedTrade.type==""` chain | `2189-2333` |
| Max simultaneous positions | `MAX_CONCURRENT_POSITIONS_ALLOWED = 2` (`:177`) | `IsWithinPositionLimit()` counts trades whose `POSITION_COMMENT` contains `"KenKemST"`, `SessionManager.mqh:248-264`; called in `GetEntryBlockReason` `RiskManager.mqh:319` |
| Min seconds between ANY entries | `MIN_SECONDS_BETWEEN_ENTRIES = 60` (`:215`) | `RiskManager.mqh:334`: `if lastEntryTime>0 && (now-lastEntryTime) < 60 → block`. `lastEntryTime=TimeCurrent()` set ONLY on successful execution (`KenKemExpert.mq5:613`) |
| Block opposite-direction entries | `BLOCK_OPPOSITE_DIRECTION_ENTRIES = true` (`:178`) | `HasOpposingDirectionPosition()` `SessionManager.mqh:271-292`; called `KenKemExpert.mq5:2356` + high-risk `2026` |
| Aggregate open risk cap | `MAX_AGGREGATE_RISK_RATIO = MAX_LOSS_RATIO_E1*4 = (0.02*1.05)*4 = 0.084` (`:82`,`:65`) | `CalculateTotalRiskExposure()` (SL-distance based) vs cap, `RiskManager.mqh:323-331` |
| Max **real losses** per session | `MAX_SESSION_LOSSES = 4` (`:46`) | each entry's `Detect()`: `if sessionLossCount >= 4: return` (E2 `Entry2.mqh:81`, E4 `Entry4.mqh:84`, E5 `Entry5.mqh:131`, E3 `Entry3.mqh:171`) |
| Max SLTP closes per session (legacy brake) | `MAX_SLTP_COUNT_PER_SESSION = 7` (`:45`) | `if tradeSLTPCountInSession > 7: return` (same Entry files) |
| Max high-risk trades per session | `MAX_HIGH_RISK_TRADES_PER_SESSION = 5` (`:44`) | `HandleHighRiskEntry` `KenKemExpert.mq5:2040` |
| Per-entry-type consecutive-loss block | `MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE = 3` (`:174`), block `ENTRY_BLOCK_AFTER_CONSECUTIVE_LOSS_MINS = 60` min (`:175`) | `IsEntryTypeBlocked()` `RiskManager.mqh:133-161` |
| Global losing-streak time block | escalation `LOSING_STREAK_ESCALATION_THRESHOLD = 2` (`:176`) | `RiskManager.mqh:30-34`: `losingStreakBlockUntil = now + floor(consecutiveLosses * mult * 60)`, `mult = (consecutiveLosses>=2 ? 2 : 1.5)`, ×1.2 if DD; checked `IsBlockedByLosingStreak()` `:120` |
| Win-streak cooldown (lot only, not block) | `WIN_STREAK_COOLDOWN_TRIGGER = 3`, `..._TRADES = 2`, `..._LOT_MULT = 0.60` (`:170-172`) | `RiskManager.mqh:79-99` |

Session counters reset on **session change** in `UpdateSessionTracking()` (`SessionManager.mqh:317-336`): `tradeSLTPCountInSession, sessionLossCount, sessionWinCount, sessionBreakEvenCount, highRiskTradesInSession = 0`. Counters increment on trade CLOSE in `BrokerHelpers.mqh:279-286` (loss→`sessionLossCount++` unless break-even; every close→`tradeSLTPCountInSession++`).

**What produces ~1 trade/day** (compounding, not one single gate):
1. **Session windows** (§3) admit entries only ~3 windows/day, and each window's `Detect()` only fires on a fresh trigger.
2. **`MIN_SECONDS_BETWEEN_ENTRIES=60`** + **one-entry-per-bar** (M1) cap throughput.
3. **`MAX_CONCURRENT_POSITIONS_ALLOWED=2`** + **`BLOCK_OPPOSITE_DIRECTION_ENTRIES`** + **aggregate-risk cap 8.4%** (each trade risks ~2% so ~4 trades of headroom) keep concurrency low.
4. **`MAX_SESSION_LOSSES=4`** halts a session after 4 real losses.
5. **High quality bars**: `MIN_ENTRY_ATR_PERCENTILE=65` regime gate (§7) + per-entry trend-quality minimums 6/9 (§4) + conviction 7/10/9 (§5) reject the vast majority of triggers.

> Likely C++ over-fire causes to check first: (a) NOT enforcing the once-per-bar `lastEntryBarIndex`; (b) NOT enforcing `MIN_SECONDS_BETWEEN_ENTRIES` keyed off **last successful** entry; (c) missing the `MIN_ENTRY_ATR_PERCENTILE=65` regime gate; (d) missing per-entry trend-quality/conviction minimums; (e) session windows not in JST or not applying the post-midnight `+2400` adjustment.

---

## 3. SESSION / TIME GATING (JST)

Local time derivation (`Utils/SessionManager.mqh`):
```
ToJST(utc)            = utc + 9*3600                              # :15
GetCurrentTimeJST_HHMM = struct(ToJST(TimeGMT())).hour*100 + min  # :19   (TimeGMT, NOT TimeCurrent)
```
Broker = UTC+0 → JST = broker_time + 9h. Use **GMT** wall clock, add 9h, take HH*100+MM.

Post-midnight wrap (`:26-33`):
```
IsTimeInValidSession(t):           # misnamed: it ADJUSTS, doesn't test
    if t <= 630: return t + 2400   # 00:00–06:30 JST → 2400..3030
    else:        return t
```
Apply this adjustment to BOTH `currentJST` and each session bound before comparing.

Session bounds (JST, `InputParams.mqh:559-564`):
```
JAPAN_START=900   JAPAN_END=1230        # Asia  09:00–12:30 JST
LONDON_START=1400 LONDON_END=1830       # EU    14:00–18:30 JST
NY_START=2100     NY_END=2400           # US    21:00–24:00 JST
```

`IsNowInValidSession()` (`:118-147`) — the gate used at entry time:
```
if IGNORE_VALID_SESSIONS: return true                            # default false
jst = GetCurrentTimeJST_HHMM()
if AVOID_NEWS_TRADING && 2120 <= jst <= 2145: return false       # :125  US-news blackout (AVOID_NEWS_TRADING default true, :558)
if IsNearImportantNews(): return false                           # ENABLE_NEWS_FILTER default false → no-op
a = adjust(jst)
return  (JAPAN_START <= a <= JAPAN_END)                          # Asia
     || (LONDON_START <= a <= LONDON_END)                        # EU
     || (NY_START <= a <= NY_END)                                # US
```
All three sessions allow entries. Gap windows (no entries): 12:30–14:00, 18:30–21:00, 24:00–next 09:00 JST.

`GetCurrentSession()` (`:61-73`) returns "ASIA"/"EU"/"US"/"NONE" using the same adjusted compare — drives session-specific TP/RR multipliers, not gating.

Session END close (`:38-46`, `:385-401`): `CLOSE_ALL_TRADES_AT_SESSION_END=true` (`:179`); at `|adjusted(jst) - adjusted(NY_END)| <= 1` (i.e. ~24:00 JST) all open positions are force-closed. `IsInLastFiveMinutesOfUSSession()` blocks entries in last 5 min (`:52-57`). Weekend block `IsInHealthCheckWeekendBlock()` (`:208-243`) is for health-checks, not entries.

---

## 4. TREND-QUALITY SCORE (0-13)  `Core/TrendIdentifier.mqh:130 GetTrendQualityScore(trendState, entryNum)`

Reads M1/M3/M5 ADX/DI from `cache` (filled at `ENTRY_SHIFT=1`, i.e. last closed bar; `UpdateIndicatorCache:693-695`). `cachedATRPercentile` from forming-bar ATR (see §7 caveat).

```
score = 0
# C1 ADX strength (0-2), M1 ADX = cache.adx[0]
  adxPoints = (adx >= ADX_HIGH_THRESHOLD(25.0))            ? 2     # :138
            : (adx >= MIN_MOMENTUM_ADX_REQUIRED(19.7))     ? 1 : 0 # :139 (param :220)
# C2 DI spread (0-2): spread = BULL? dip0-dim0 : dim0-dip0
  spreadPoints = (spread>=3.0)?2 : (spread>=1.0)?1 : 0              # :151-152
# C3 M1 acceleration (0-2), only if USE_ACCELERATION_BONUS(true,:131)
  accel5 = HasTrendAcceleration(M1,trend,5); accel3 = ...(M1,trend,3)
  accelPoints = accel5?2 : accel3?1 : 0                            # :162-167
# C4 MTF alignment (0-2): count of M1/M3/M5 DI agreeing with trend
  alignedCount in {0..3}; mtfPoints = (==3)?2 : (>=2)?1 : 0        # :185-188

# ---- HARD GATE (entryNum != 5) ----                              # :200
  if ENABLE_TREND_QUALITY_GATES(true,:122) && entryNum!=5
     && (adxPoints==0 || spreadPoints==0 || mtfPoints==0):
        return 0     # weak core → score 0 (fails every per-entry min)
  # E5 SKIPS this gate (Pine parity; E5 has own ADX gate Entry5.mqh:122)

# C5 Price action (0-1): HasStrongTrendingPriceActions(trend,M1,5,ENTRY_SHIFT)  # :213
  paPoints = strongPA ? 1 : 0
# C6 M3 acceleration (0-1): HasTrendAcceleration(M3,trend,3)        # :221
# C7 Ichimoku (0-2): CheckIchimokuCloudAlignment(isLong,entryNum)   # :229
  # only if USE_ICHIMOKU_Ex; M1 future-cloud color match + price outside cloud (+1),
  # M3 future-cloud color match (+1). E4 passes entryNum=4 but USE_ICHIMOKU_E4=false → 0.
# C8 ATR health (0-1): (cachedATRPercentile >= ATR_PERCENTILE_LOW(20.0)) ? 1 : 0  # :238 (param :149)
return score   # max 13 (with Ichimoku) else 11
```

Ichimoku component reads cache slots filled at `ENTRY_SHIFT` for current cloud and at **shift = -26** for future cloud (`UpdateIndicatorCache:751-766`).

**Per-entry minimums** (`InputParams.mqh`), checked inside each entry's condition function (e.g. E2 `KenKemExpert.mq5:1909`):
```
MIN_TREND_QUALITY_E1 = 6   (:123)   USE_ICHIMOKU_E1 = true  → 0-13 scale
MIN_TREND_QUALITY_E2 = 9   (:125)   USE_ICHIMOKU_E2 = false → 0-11
MIN_TREND_QUALITY_E4 = 9   (:127)   USE_ICHIMOKU_E4 = false → 0-11 (HARD BLOCK)
MIN_TREND_QUALITY_E5 = 5   (:129)   no Ichimoku, no hard gate → 0-11
```
If `trendQuality < min` the entry is flagged low-confidence (suppressed unless `SEND_LOW_CONFIDENCE_SIGNALS`).

---

## 5. CONVICTION SCORE (0-12, "x/10" in logs)  `Entries/EntryHelpers.mqh:11 CalculateConvictionScore(isLong,entryType,convictionEnabled,applyTrendVeto)`

Called from `ProcessEntryConvictionAndConfidence` (`KenKemExpert.mq5:1848`) only if `entry.GetUseConvictionScoring()`.
```
if !convictionEnabled: return 999   # bypass (always passes)               # :12

# ---- HTF VETO (hard block) if applyTrendVeto ----                        # :18-43
  conf_fast = EMA75 of confirmationTF (ENTRY_SHIFT); conf_slow = EMA100
  if isLong  && conf_fast < conf_slow: return -999   # against HTF → block
  if !isLong && conf_fast > conf_slow: return -999
  # NOTE default USE_HTF_VETO_E1/E2/E4 = false (:114-119) → veto skipped

score = 0
# C1 M1 DI spread (0-2):  spread>=3 →2 ; >=1 →1 ; else 0                    # :47-51
# C2 EMA stack separation (0-2): Calculate4EMAStackSeparation(isLong)       # :58
#    avgGap(pips of 25/71/97/192 stack)/30 normalized; >=0.8 →2 ; >=0.5 →1  # :60-61
#    (returns 0.0 if stack not ordered → 0 pts)                              :220-240
# C3 RSI momentum (0-2, clamped): rsi_m1,rsi_m3 = GetRSIValue(.,14,ENTRY_SHIFT) # :69-71
#    long: (m1>50 && m3>50)→+2 ; (m1>50||m3>50)→+1 ; +1 if accel(velocity>1.5/bar & m1>50)
#    velocity = (rsi_m1 - rsi_m1@ENTRY_SHIFT+2)/2 ; short = mirror (<50)      # :74-103
# C4 ADX strength+accel (0-2, clamped): adx=cache.adx[0]                     # :108-126
#    +1 if adx>=23 ; -1 if adx<15 ; +1 if IsAccelerating(adx,3) ; clamp 0..2
# C5 M3+M5 MTF confirm (0-2):                                               # :130-157
#    m3Strong=(adx3>=22 && spread3>=2); m5Strong=(adx5>=22 && spread5>=2)
#    m3Support=(adx3>=16 && spread3>0.5); m5Support=(adx5>=16 && spread5>0.5)
#    both strong→2 ; one strong→1 ; both support→1 ; else 0
# C6 Price action (0-2): CheckBullish/BearishPriceAction(3) (>=2/3 bars)     # :160-173
#    aligned PA→2 ; neutral (no opposite PA)→1 ; conflicting→0
return score   # max 12
```
Per-entry: `convictionEnabled` and threshold come from each `EntryBase`:
```
USE_CONVICTION_SCORING_E1=true, CONVICTION_THRESHOLD_E1 = 7   (InputParams.mqh:107-108)
USE_CONVICTION_SCORING_E2=true, CONVICTION_THRESHOLD_E2 = 10  (:109-110)
USE_CONVICTION_SCORING_E4=true, CONVICTION_THRESHOLD_E4 = 9   (:117-118)
(E3 conviction off :112; HTF vetos all false :114-119)
```
`if convictionScore < threshold` → low-confidence, suppressed (`KenKemExpert.mq5:1849-1853`). HTF-veto return `-999 < threshold` ⇒ also blocks.

---

## 6. RSI-DIVERGENCE VETO  `Entries/EntryHelpers.mqh:298 HasRSIDivergenceAgainstTrade(isLong,label)`

Called inside E1/E2/E4 detect (`Entry1.mqh:309`, `Entry2.mqh:269`, `Entry4.mqh:373`). True ⇒ block entry.
Params (`InputParams.mqh:226-230`): `ENABLE_RSI_DIVERGENCE_VETO=true`, `RSI_DIV_LOOKBACK=16`, `RSI_DIV_MIN_PRICE_DIFF_PIPS=60`, `RSI_DIV_MIN_RSI_DIFF=6.5`. All on **M3 (TF1)**, RSI(14), reads at `ENTRY_SHIFT`.
```
lookback=16 ; halfLB=8 ; if halfLB<2: return false
highs/lows = CopyHigh/Low(M3, ENTRY_SHIFT, 16)   # series-indexed (0=most recent closed M3)
rsi        = CopyBuffer(RSI14_M3, ENTRY_SHIFT, 16)

if isLong:   # bearish divergence blocks longs
    recentBar = argmax(highs[0..7]) ; olderBar = argmax(highs[8..15])
    priceDiffPips = (highs[recentBar]-highs[olderBar]) / pipSize     # higher-high?
    rsiDiff       = rsi[olderBar] - rsi[recentBar]                   # lower-high RSI?
    block if (priceDiffPips >= 60 && rsiDiff >= 6.5)
else:        # bullish divergence blocks shorts
    recentBar = argmin(lows[0..7]) ; olderBar = argmin(lows[8..15])
    priceDiffPips = (lows[olderBar]-lows[recentBar]) / pipSize       # lower-low?
    rsiDiff       = rsi[recentBar] - rsi[olderBar]                   # higher-low RSI?
    block if (priceDiffPips >= 60 && rsiDiff >= 6.5)
return false
```
Note `pipSize`: BTC pip handling per project memory (pip=1, std×2) — confirm against `getMaxLossUSD`/`pipSize` init when porting.

---

## 7. ATR-PERCENTILE GATE  `TradeManagement/RiskManager.mqh:215 CalculateATRPercentile(currentATR,lookback)`

```
if lookback<=0 || currentATR<=0: return 50.0
atrValues = CopyBuffer(g_atrM1Handle, buf0, start=1, count=lookback)   # shifts 1..lookback (closed bars)
countBelow = count(atrValues[i] < currentATR)
return countBelow / copied * 100.0          # 0..100, strict-less-than, no interpolation
```
`currentATR = cache.atrM1` which is copied at **shift 0 (forming bar)** (`UpdateIndicatorCache:717-719`), compared against shifts **1..lookback**. So the percentile mixes a forming-bar numerator with closed-bar history — replicate exactly.
`ATR_PERCENTILE_LOOKBACK = 32` (`InputParams.mqh:153`). Cached once/bar at `UpdateIndicatorCache:842`.

Gate thresholds, all in `GetEntryBlockReason()` (`RiskManager.mqh:284-311`) — uses `cachedATRPercentile`:
```
if ENABLE_BLACK_SWAN_PROTECTION(true,:154):
   if ATR_PERCENTILE_LOW(20.0,:149) > 0 && pctile < 20.0:  block "vol too low"
   if ENABLE_ATR_HIGH_BLOCK(true,:151) && ATR_PERCENTILE_HIGH(90.0,:150)>0 && pctile > 90.0:
        set blackSwanBlockedUntil = now + BLACKSWAN_BLOCK_COOLDOWN_MINS(10,:155)*60 ; block "vol too high"
if MIN_ENTRY_ATR_PERCENTILE(65.0,:152) > 0 && pctile < 65.0:  block "Low volatility regime"   # :305
```
The **`MIN_ENTRY_ATR_PERCENTILE=65` gate is the dominant volatility filter** — entries require ATR in the top ~35% of the last 32 M1 bars. (Effective admissible band ≈ [65, 90].) ATR health also feeds trend-quality C8 (≥20 → +1) and sideways C5 (§ TrendIdentifier:457-464).

Spread gates (same function, default-inert): `MAX_SPREAD_PIPS=0` disables consecutive-spread block (`:253`); `MAX_SPREAD_ATR_RATIO=0.30` active if `cache.atrM1>0` (`:266-280`), blocks when `lastSpreadPips/atrPips > 0.30`.

---

## 8. RISK GUARDS  `TradeManagement/RiskManager.mqh` (+ `Utils/SessionManager.mqh`)

### Daily loss  `IsWithinDailyLossLimit()` `SessionManager.mqh:152-201`
```
today = iTime(_Symbol, D1, 0)
if today != currentDate:   # new day
    currentDate=today; dailyStartBalance=AccountBalance; dailyLossLimitReached=false
if dailyLossLimitReached: return false
lossPercent = (dailyStartBalance - AccountBalance) / dailyStartBalance
if lossPercent >= MAX_DAILY_LOSS_RATIO(0.072,:52): dailyLossLimitReached=true; return false
return true
```
Latches for the rest of the **broker day** (peak balance NOT reset daily).

### Drawdown ladder  `IsWithinDrawdownLimit()` `:440-615`  (peak = lifetime high, never reset down)
```
ddPct = (peakAccountBalance - balance) / peakAccountBalance
# Prop hard block (MADE_FOR_PROP_TRADING) at ACCOUNT_DD_RATIO_TO_SOFT_BLOCK → return false   :475
# SOFT BLOCK   ddPct >= ACCOUNT_DD_RATIO_TO_SOFT_BLOCK(0.13,:54):
#     inSoftBlockMode=inRecoveryMode=true ; trade with SOFT_BLOCK_LOT_MULTIPLIER(0.3,:55) ; return true  :497
# RECOVERY (stage1) trigger = ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN(0.105,:53) * RECOVERY_MODE_TRIGGER_RATIO(0.9,:83)
#     = 0.0945:  inRecoveryMode=true, lots ×RECOVERY_MODE_LOT_MULTIPLIER(0.6,:85)             :547
#     exit when ddPct < trigger*RECOVERY_MODE_EXIT_RATIO(0.95,:84)                            :530
# HARD DD BLOCK (stage2)  ddPct > 0.105 && !inRecoveryMode:
#     drawdownTriggered=true; drawdownBlockedUntil = today 23:59:59; return false             :571
```
`IsDrawdownBlocked()` (`:619`) returns true while `drawdownTriggered` and `now <= drawdownBlockedUntil` (until end of day, then auto-clears). In `OnTick`, any of daily-loss / DD-block / DD-limit sets `signalOnlyMode` (entries suppressed) when `SIGNAL_ONLY_DURING_PROTECTION=true` (`:87`).

### Loss-streak / win-streak  `UpdateLosingStreak()` `:20-115`
```
on LOSS:
   consecutiveLosses++
   mult = (consecutiveLosses >= LOSING_STREAK_ESCALATION_THRESHOLD(2,:176)) ? 2 : 1.5
   if !IsWithinDrawdownLimit(): mult *= 1.2
   losingStreakBlockUntil = now + floor(consecutiveLosses * mult * MIN_SECONDS_BETWEEN_ENTRIES(60))   # :33
   per-type: consecutiveLosses_{LE1..SE3}++ ; if >= MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE(3):
        blockedUntil_X = now + ENTRY_BLOCK_AFTER_CONSECUTIVE_LOSS_MINS(60)*60                          # :46-57
on WIN:
   consecutiveLosses = max(0, consecutiveLosses-1); losingStreakBlockUntil=0
   reset OPPOSITE-direction per-type loss counters/blocks                                              # :66-76
   consecutiveWins++ ; if >= WIN_STREAK_COOLDOWN_TRIGGER(3,:170): inWinStreakCooldown for WIN_STREAK_COOLDOWN_TRADES(2,:172) trades, lot ×0.60(:171)
on LOSS: consecutiveWins=0, cancel win cooldown                                                        # :103-110
```
`IsBlockedByLosingStreak()` (`:120`): true while `now < losingStreakBlockUntil` → suppresses ALL entries (outer gate `KenKemExpert.mq5:2177`). `IsEntryTypeBlocked(type)` (`:133`) suppresses only that type (`2361`).

### Profit protection (lot only)  `CheckProfitProtection()` `:347-389`
`ENABLE_PROFIT_PROTECTION=true`(:163); when balance dips below a floor (`1 - PROFIT_PROTECTION_TRIGGER_RATIO(0.3)` of gains, min gain `MIN_PROFIT_TO_PROTECT_RATIO(0.05)`), lot ×`PROFIT_PROTECTION_LOT_MULTIPLIER(0.75)`. Does not block entries.

Lot multipliers combine as the MIN of soft-block / recovery / profit-protection / win-streak (`GetRecoveryModeLotMultiplier()` `:645-675`; prop hard-block → 0).

---

## Indicator-shift cheat-sheet (port these exactly)
- `ENTRY_SHIFT=1` → ADX/DI/RSI/EMA/Ichimoku-current/price-action reads on **last closed bar**.
- ATR for percentile **numerator**: shift 0 (forming) via `cache.atrM1`; **history**: shifts 1..32. (`RiskManager.mqh:215`, cache `UpdateIndicatorCache:717`.)
- Ichimoku future cloud: shift **-26**; current cloud: shift `ENTRY_SHIFT`. (`UpdateIndicatorCache:745-766`.)
- HTF cache (`adx[1..3]`) read at `ENTRY_SHIFT` = latest closed bar of that HTF.
- Trigger/entry price = `iClose(M1, ENTRY_SHIFT)` (`TriggerPrice()` `KenKemExpert.mq5:2015`).
- Session time uses **TimeGMT()+9h**, with `t<=630 → t+2400` adjustment on every compared value.
