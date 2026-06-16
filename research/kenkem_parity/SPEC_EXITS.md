# KenKem — Trade-Management / Exit Parity Spec (post-entry)

Source of truth (READ-ONLY): `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/`
Reference run: 9 trades, E5 entries. Exit-tag tally: EA ×5 (managed close), SL-WIN ×2, SL-LOSS ×1, TP ×1.
All file:line citations are absolute within that source dir.

> Notation: `TF0=M1, TF1=M3, TF2=M5, TF3=M15`. `entry` = `entryPrice`. `R = |entry - SL_initial|`
> in price (`bufferedSLDistancePips * pipSize`). `mid/bid/ask` per side. `pipSize` for XAU = `_Point`
> (gold path, `KenKemExpert.mq5:124-128`), `contractSize` = broker `SYMBOL_TRADE_CONTRACT_SIZE`
> (XAU ≈ 100, `KenKemExpert.mq5:121,128`; default fallback `CONTRACT_SIZE=100`, `InputParams.mqh:49`).

---

## 0. exitTag mapping (TradeJournal.mqh:69-115)

```
last OUT-deal DEAL_REASON ->
  DEAL_REASON_SL     -> "SL"  -> split by realizedUsd sign: >0 "SL-WIN" else "SL-LOSS"  (line 115)
  DEAL_REASON_TP     -> "TP"
  DEAL_REASON_SO     -> "SO"
  DEAL_REASON_EXPERT -> "EA"   <-- ANY EA-initiated SafePositionClose / PositionClose
  DEAL_REASON_CLIENT -> "MAN"
  default            -> "OTH"
```
=> Every managed-close path in §7 (and §8 session/news closes) closes via `SafePositionClose` /
`trade.PositionClose*`, so the broker stamps `DEAL_REASON_EXPERT` => tag "EA". SL/TP that the broker
hits server-side (price touches the resting SL/TP set by `ModifyPositionSLTP`) stamp SL/TP.
A trail/BE that moves SL and is later hit still surfaces as SL (then SL-WIN/SL-LOSS by sign).

---

## 1. Per-tick / per-bar manage sequence — `TradeManager::ProcessAllTrades()` (TradeManager.mqh:76-278)

Called once per tick from `OnTick` AFTER news-close and session-end close, BEFORE entry detection
(`KenKemExpert.mq5:2424,2456,2462,2496`).

```
ProcessAllTrades():
  if ArraySize(trades)==0 return                                   # :78-79
  if no trade.status=="OPEN" return                               # :83-92
  currentPrice=cache.currentPrice; high=cache.high; low=cache.low  # :96-98 (cache set once/tick in OnTick)
  # quality-drop gate fires ONCE PER M1 BAR, not per tick:
  allowQualityDropCheck = (iTime(TF0,0) != m_lastQualityCheckBarTime)  # :101-106

  Pass A (:112-132): drop closed/SKIPPED trades from arrays.
  Pass B (:135-277) per open trade i (reverse order):
    barsSinceEntry = (Bars(TF0)-1) - trades[i].entryBar               # :144
    if barsSinceEntry==0: continue        # TV rule: NO management on entry bar  # :145-146
    # 2A HIGH-RISK TIME EXIT (managed close, tag EA):
    if trades[i].isHighRiskTrade && barsSinceEntry>=HIGH_RISK_MAX_BARS:  # :149
        exitPrice = isLong?BID:ASK; SafePositionClose(...,"HIGH-RISK TIME EXIT"); status=EARLY_EXIT; continue  # :154-174

    needsBrokerCheck logic (:191-219) -> if true CheckTradeStatusOnBrokerBeforeUpdating(trades[i])  # :222-226
        # this is what detects a server-side SL/TP hit and sets status to WON/LOST.
    if status=="OPEN":
        trades[i].bestPrice = isLong?max(bestPrice,high):min(bestPrice,low)   # :231-233
        hitWin  = isLong? high>=TP : low<=TP                                   # :236
        hitLoss = isLong? low<=SL  : high>=SL                                  # :237
        if !hitWin && !hitLoss && barsSinceEntry>0:                            # :239
            currentPnL = isLong?(currentPrice-entry):(entry-currentPrice)      # :240
            ApplyPreBEStructureProtection(i,...)                              # :243  (§4a)
            if ENABLE_CONSERVATIVE_TRADE_MGMT:  ApplyConservativeTradeManagement(i,...)  # :245-247 (§3b/§5b)  [DEFAULT OFF]
            else:
                ApplyRMultipleSLProtection(i,...)        # :250  (§4b)
                ExtendTPAsNeeded(i,...)                  # :251  (§6)
                TakePartialProfitAsNeeded(i,...)         # :252  (§3a + §5a trailing + ladder)
            ExitEarlyAsNeeded(i,..,allowQualityDropCheck,newStatus,brokerCheckWasCalled)  # :256  (§7 ALL EA-tag triggers)
            CheckAndSendPnLZoneUpdate(i,...)            # :259  (diagnostics only, no trade effect)
    if newStatus!="OPEN": if !brokerCheckWasCalled CheckTradeStatusOnBrokerBeforeUpdating; UpdateLosingStreak(...)  # :267-276
```

KEY ORDER for parity: SL/TP placement is RESTING (broker-side). Each manage tick may MOVE SL (BE,
trail, ladder, pre-BE) or TP (extension), or directly CLOSE (§7). The `bestPrice` HWM uses bar
`high/low` (not tick), and `hitWin/hitLoss` use bar `high/low` too (:236-237).

---

## 2. Initial SL/TP placement (reference only; entry agent owns sizing)

E5 (Entry5.mqh:86-93): SL = EMA200-based, ATR-capped (`E5_ATR_SL_CAP_MULTIPLIER`,
`E5_USE_ATR_SL_ARBITRATION`); `minSLSpreadMultiplier=MIN_SL_SPREAD_MULT`. TP from `rewardRatio=E5_RR=1.5`
(`E5_RR_SIDEWAY=1.2` in sideway). `originalTP`,`originalSL` stored at open; `bufferedSLDistancePips`
= initial |entry−SL| in pips = the R unit used by every manage routine below.

---

## 3a. PARTIAL TAKE-PROFIT — STANDARD mode (E5 path) `TakePartialProfitAsNeeded` (TradeManager.mqh:674-815)

Gate: `ALLOW_PARTIAL_TP` (default **true**, InputParams.mqh:247).
`origTPDist = |originalTP - entry|`.
Trigger/ratio come from the entry config (E5): `partialTPTrigger=E5_PARTIAL_TP_TRIGGER=0.54`,
`partialTPRatio=E5_PARTIAL_TP_RATIO=0.50` (Entry5.mqh:95-96; InputParams.mqh:464-465).
High-risk override (only if `isHighRiskTrade && ALLOW_HIGH_RISK_PARTIAL_TP_OVERRIDE`) swaps in
`HIGH_RISK_PARTIAL_TP_TRIGGER/RATIO` (:680-684).

```
# Mark eligible once profit reaches trigger fraction of TP distance:        :687-693
if currentPnL >= partialTrigger*origTPDist && !partialTPEligible:
    partialTPEligible=true; bestPriceSinceEligible=currentPrice

isE5 = entryType in {ENTRY_L_E5,ENTRY_S_E5}                                  :696
# E5 = IMMEDIATE partial at level (NO weakness/retrace gate; Pine SuperBros parity):  :697-739
if isE5 && partialTPEligible && !hasTakenPartialProfit:
    ExecutePartialTakeProfit(i, partialRatio, &execPrice)                    # §9 close 50% of vol
    actualPnL = isLong?(execPrice-entry):(entry-execPrice)
    if actualPnL>0:                                                          # :708
        # E5 BREAK-EVEN move (§4): SL = entry +/- 2*spread
        breakevenBuffer = 2.0 * (SYMBOL_SPREAD * _Point)                     # :710-712
        breakevenSL = isLong? entry+buf : entry-buf
        ModifyPositionSLTP(SL=breakevenSL); slMovedToBreakeven=true          # :715-719
    hasTakenPartialProfit=true                                              # :735

# NON-E5 only (NOT in reference run): wait for IsTrendWeakening OR HasSignificantRetrace(:0.15)  :742-802

if hasTakenPartialProfit: CheckAndApplyLadderStages(i)                       # :806  (§5a-ladder)
if partialTPEligible || hasTakenPartialProfit: CalculateTrailingSLForTrade() # :811-812 (§5a-trail)
```

## 3b. PARTIAL TP — CONSERVATIVE mode (`ENABLE_CONSERVATIVE_TRADE_MGMT`, default **false**, InputParams.mqh:495)
`ApplyConservativeTradeManagement` (:486-601). E5 params: `CONS_INITIAL_PARTIAL_R_E5=0.25`,
`CONS_INITIAL_PARTIAL_RATIO_E5=0.12`, `CONS_POST_PARTIAL_SL_R_E5=0.12`, `CONS_TRAIL_R_INCREMENT_E5=0.10`,
`CONS_TRAIL_SL_STEP_R_E5=0.025` (InputParams.mqh:500-520). Replaces §3a/§4b/§5a/§6 when ON.
Phase1: at `currentR>=0.25` close 12%, move SL to `entry +/- 0.12R` (:505-543). Phase2: every additional
0.10R, shift SL by 0.025R cumulatively (:545-600). **Disabled in baseline — port but gate off.**

---

## 4. BREAK-EVEN move

(a) **Pre-BE structure protection** `ApplyPreBEStructureProtection` (:284-395) —
`ENABLE_PRE_BE_STRUCTURE_PROTECTION=true` (InputParams.mqh:238), `PRE_BE_TRIGGER_R=0.5` (:239).
Skips if `slMovedToBreakeven` or partial taken/eligible (:287-288). Requires `rMultiple>=0.5R`,
optional M3 accel confirm, structure breach of N-bar prior high/low; sets SL to breakout-swing −/+ buffer,
clamped strictly below/above entry (`preBEMargin=0.5 pip`, :345). This stays PRE-BE (never crosses entry).

(b) **R-multiple BE** `ApplyRMultipleSLProtection` (:402-455, STANDARD mode only) —
`R_MULT_BE_TRIGGER=0.87` (InputParams.mqh:245), `R_MULT_BE_BUFFER=0.055` (:246). Once-only
(`rMultipleBEApplied`). When `currentPnL/R >= 0.87`: `newSL = entry +/- (R*0.055)`; apply if improvement;
sets `rMultipleBEApplied=slMovedToBreakeven=true` (:415-433).

(c) **E5 partial BE** — see §3a: on the E5 partial fill, SL jumps to `entry +/- 2*spread` (:710-719).

Note: (a),(b),(c) all move the RESTING SL; if later touched -> tag SL (SL-WIN since SL>entry side).

---

## 5a. TRAILING / LADDERED trailing — STANDARD mode

**Continuous trail** `CalculateTrailingSLForTrade` (:886-964). Active once `partialTPEligible ||
hasTakenPartialProfit` (:811). `trailingFactor=E5_TRAILING_SL_FACTOR=0.38` (Entry5.mqh:102;
InputParams.mqh:467).
```
originalTpDist = |originalTP - entry|
baseTrailingDistance = originalTpDist * trailingFactor / (tpExtensions+1)        :893
adaptiveTrailingDistance = baseTrailingDistance * GetVolatilityMultiplier()      :894
trailingSL = isLong? bestPrice-adaptive : bestPrice+adaptive                     :895
newSL = isLong? max(SL,trailingSL) : min(SL,trailingSL)                          :896
apply only if improvement AND >=1 pip change AND >=2s since last modify          :916-928
respect broker min-stop (STOPS_LEVEL/FREEZE_LEVEL/SPREAD)*_Point (default 10*_Point)  :902-913
on success: slWasTrailed=true; if crosses entry -> slMovedToBreakeven=true        :937-949
```

**Laddered stages** `CheckAndApplyLadderStages` / `ApplyLadderStage` (KenKemExpert.mq5:1658-1745).
Active only if `hasTakenPartialProfit` AND entry `enableLadderedExtensions` (E5:
`E5_ENABLE_LADDERED_EXTENSIONS=true`, InputParams.mqh:471). NO time throttle.
E5 ladder defaults (InputParams.mqh:476-481):
```
profit thresholds (× origTPDist):  S1=1.05  S2=1.11  S3=1.17
trail ratios:                      S1=0.45  S2=0.55  S3=0.65
currentPnL via iClose(TF0,0); advance highest-reached stage only (never regress)   :1675-1687
ApplyLadderStage: newSL = currentPrice -/+ (trailRatio * currentProfit)             :1700-1702
apply only if better than current SL                                                :1705
```
Ladder and continuous-trail both run each tick after partial; the more protective SL wins by the
"improvement only" guards.

## 5b. CONSERVATIVE trailing — see §3b (progressive 0.025R steps). OFF by default.

---

## 6. TP-EXTENSION — `ExtendTPAsNeeded` (:606-669, STANDARD mode only)
Gate `ALLOW_TP_EXTENSION=true` (InputParams.mqh:248) and `tpExtensions < maxExt`
(E5 `maxExt=E5_MAX_TP_EXTENSIONS=10`, Entry5.mqh:99/InputParams.mqh:468).
```
progressPercent over entry->TP; triggerPips = GetTPExtensionTriggerPips(entryType)   :621-623
fire when remainingDistancePips<=triggerPips && remaining>0                           :626
require progressRatio >= MIN_TP_PROGRESS_FOR_EXTENSION=0.92 (InputParams.mqh:249)     :629
skip if IsTrendWeakening(isLong) (let dying trend hit TP)                             :634
extPips = GetTPExtensionPips(entryType); newTP = TP +/- extPips*pipSize              :639-642
ModifyPositionSLTP(TP=newTP); tpExtensions++; then CalculateTrailingSLForTrade()      :647-662
```
Dynamic ext pips via `UpdateDynamicTPExtension` (:1593-1611) when `USE_DYNAMIC_TP_EXTENSION`:
`extPips = clamp(atrPips*ATR_TP_EXTENSION_MULTIPLIER, TP_EXTENSION_MIN_PIPS, TP_EXTENSION_MAX_PIPS)`,
`trigger=2*extPips`. (TP extension delays a TP-tagged close; rarely the cause of an "EA" tag.)

---

## 7. MANAGED-CLOSE ("EA" tag) triggers — `ExitEarlyAsNeeded` (TradeManager.mqh:969-1520)
Evaluated in THIS ORDER each manage tick (after partial/trail/ext). Each closes via
`SafePositionClose` => DEAL_REASON_EXPERT => tag **"EA"**. exitPrice captured BEFORE close as the
realisable side: `isLong?BID:ASK`. Several are gated `allowQualityDropCheck` (once-per-M1-bar).

For E5, the per-entry exit toggles (Entry5.mqh:427-431) resolve to:
```
GetEnableScoreDropExit = ENABLE_SCORE_DROP_EXIT_E5 = false   (InputParams.mqh:271)  -> §7.1 OFF
GetScoreDropThreshold  = SCORE_DROP_THRESHOLD_E5  = 3        (:272)
GetEnableDIFlipExit    = ENABLE_DI_FLIP_FAST_EXIT_E5 = false (:284)                  -> §7.3 OFF
GetExitInIchiCloud     = false (E5 has no Ichimoku)                                  -> §7.6 OFF
GetEnablePanicADXExit  = ENABLE_FAST_ADX_PANIC_EXIT_E5 = true (:261)                 -> §7.7 ON  <== the E5 EA driver
```
So for the baseline E5 run the live EA-tag producers are: **§7.7 panic exit (primary)**,
**§7.4 E5 multi-TF sideway exit**, **§1/2A high-risk time exit**, plus §8 session/news closes.
§7.1 score-drop, §7.2 ADX-drop (`ENABLE_ADX_DROP_BASED_EXIT=false`, :274), §7.3 DI-flip, §7.5 non-E5
sideway (`ENABLE_SIDEWAY_EARLY_EXIT=false`, :144), §7.6 cloud, §7.8 early-cut
(`ENABLE_EARLY_CUT_NEAR_SL=false`, :256) are all OFF at baseline — port them but gate off.

### 7.1 SCORE-DROP exit (:973-1042) — OFF for E5
`enableScoreDrop=GetEnableScoreDropExit`, `threshold=GetScoreDropThreshold` (default 3).
`currentQuality=GetActiveTradeMomentumScore(trend,entryNum)` (0-5, TrendIdentifier.mqh:261). Track
`bestQualityScore`; `qualityDrop=best-current`. If `qualityDrop>=threshold` increment `qualityDropCount`
else reset. Condition `shouldApplyExit = hasTakenPartialProfit || floatingProfitPct<10%` (:1008).
Fire when `qualityDropCount >= SCORE_DROP_CONSECUTIVE_CHECKS=3` (InputParams.mqh:273) AND shouldApplyExit
(:1011) -> close "QUALITY DROP EXIT".

### 7.2 ADX-DROP exit (:1045-1089) — OFF (`ENABLE_ADX_DROP_BASED_EXIT=false`)
`currentAdx=cache.adx[TF0]`. If `currentAdx<lastAdxValue` inc `adxDropCount` else reset; store lastAdx.
Fire when `adxDropCount>=ADX_DROP_EXIT_BARS=3` (:275) AND `currentAdx<minAdxForEntry`
(`GetMinADX`, E5 `minADX` via config) -> close "ADX DROP EXIT".

### 7.3 DI-FLIP fast exit (M1) (:1094-1176) — OFF for E5
`enableDiFlip=GetEnableDIFlipExit`. `diPlus/diMinus/diAdx = cache.*[TF0]`.
`diFlipped = opposing DI leads by >= DI_FLIP_MIN_SPREAD_M1=4.0` (:285),
`adxSufficient = diAdx>=DI_FLIP_MIN_ADX_M1=18.0` (:286). If both, inc `diFlipCount` else reset.
`slUsedRatio = max(0,priceMovedAgainst/totalSLDist)`. Fire when
`diFlipCount>=DI_FLIP_CONSECUTIVE_M1_BARS=2` (:287) AND `slUsedRatio>=DI_FLIP_MIN_SL_USED_RATIO=0.4`
(:288) -> close "DI FLIP EXIT".

### 7.4 E5 MULTI-TF SIDEWAY exit (:1178-1211) — **ON for E5**
Gate `isE5 && E5_ALLOW_SIDEWAY_EARLY_EXIT=true` (InputParams.mqh:475) AND
`currentBar > entryBar+1` (i.e. ≥2 bars held). Fire when
`IsMultiTfSideway(E5_SIDEWAYS_BLOCK_THRESHOLD=50)` true (2/3 TFs sideway, TrendIdentifier.mqh:608;
InputParams.mqh:474) -> close "E5 SIDEWAY EXIT".

### 7.5 NON-E5 SIDEWAY exit (:1213-1269) — OFF (and not E5)
`ENABLE_SIDEWAY_EARLY_EXIT=false`. Counts bars of price-stagnation + rising sideway score;
fire at `sidewayDriftCount>=SIDEWAY_EXIT_CONSECUTIVE_BARS=4` (:145).

### 7.6 ICHIMOKU CLOUD exit (:1271-1349) — OFF for E5 (`GetExitInIchiCloud=false`)
Count consecutive closed bars inside cloud; fire at `insideCloudCount>=ICHI_CLOUD_EXIT_BARS=3` (:487).

### 7.7 PANIC ADX/trend-reversal exit (:1351-1446) — **PRIMARY E5 EA driver**
Gate `enablePanicExit=GetEnablePanicADXExit` (E5 true). `currentPrice=iClose(TF0,0)`;
`floatingPnL=isLong?(price-entry):(entry-price)`.
```
shouldCheckReversal = false
# Scenario A (profit giveback) — only if partial taken AND floatingPnL>0:           :1368-1378
  mfe = isLong?(bestPrice-entry):(entry-bestPrice)
  givebackRatio = (mfe-floatingPnL)/mfe
  if givebackRatio >= PANIC_MIN_PROFIT_GIVEBACK=0.5 (InputParams.mqh:278): shouldCheck=true
# Scenario B (loss) — only if floatingPnL<0:                                         :1383-1392
  usedSLRatio = (-floatingPnL)/|SL-entry|
  panicThreshold = GetPanicMinSLUsedRatio()  # E5 base PANIC_MIN_SL_USED_RATIO=0.6 (:276); E3=0.45
  if usedSLRatio >= panicThreshold: shouldCheck=true
if shouldCheckReversal:                                                              :1395-1414
  reversedDir = isLong?BEAR:BULL
  m1Rev = HasTrendAcceleration(TF0, reversedDir, lookback=4, adxPeriod=9)            # ADXRSIHelpers.mqh:278
  m3Rev = HasTrendAcceleration(TF1, reversedDir, lookback=3, adxPeriod=14)
  fastPanicExit = (m1Rev && m3Rev)        # BOTH M1(ADX9) and M3(ADX14) must confirm
if fastPanicExit: SafePositionClose(...,"PANIC EXIT"); newStatus updated; panicExitHandled=true  :1417-1445
```
`HasTrendAcceleration(tf,dir,n,period)` (ADXRSIHelpers.mqh:278-337): copies n ADX/DI bars from the
matching handle (period 9 -> `adxShortHandle`, else `adxHandles[tfIndex]`); requires
`adxRising = adx[0]>adx[1]>adx[2]`, `spreadAccelerating = spread[0]>spread[1]>spread[2]`,
`spreadPositive = spread[0]>0.5`, where `spread = (dir==BULL? diP-diM : diM-diP)`. Needs ≥3 bars.
**This is the exact gate the C++ engine must reproduce for the 5 EA closes.**

### 7.8 EARLY-CUT-NEAR-SL failsafe (:1448-1519) — OFF (`ENABLE_EARLY_CUT_NEAR_SL=false`, :256)
Runs only if `!panicExitHandled`. Rule1: exit if `HasTrendAcceleration(TF1,reversedDir,3)` (super-strong
opposing). Else if SL reached fraction `>= GetEarlyCutRatio()` (E5 `earlyCutSLRatio=E5_EARLY_CUT_SL_RATIO=0.0`,
:469) AND (`!HasSufficientMomentum` OR `IsTrendWeakening`) -> close "EARLY EXIT".

### §2A HIGH-RISK MAX-BARS time exit (TradeManager.mqh:149-174) — EA tag
`isHighRiskTrade && barsSinceEntry >= HIGH_RISK_MAX_BARS=70` (InputParams.mqh:216) -> SafePositionClose
"HIGH-RISK TIME EXIT", status EARLY_EXIT. (Only for trades flagged high-risk at open.)

### Reverse-signal close
There is NO separate "close on opposite signal" in the open-position manage path. The only
opposite-direction handling is pending-LIMIT-order invalidation (`KenKemExpert.mq5:1199-1207`), which
cancels resting orders, not open positions. Reversal is handled by §7.7 panic + §7.3 DI-flip only.

---

## 8. RiskManager halts & session/news force-closes

### 8a. Halts (RiskManager.mqh / SessionManager.mqh) — BLOCK NEW ENTRIES ONLY, never force-close.
These do NOT close open positions; they gate `DetectNewEntry` (and lot sizing). Confirmed by
`IsWithinDailyLossLimit` (:189-190 "Existing positions will run their course"), `IsWithinDrawdownLimit`
(:598 "NEW ENTRIES BLOCKED"). OnTick checks them AFTER ProcessAllTrades (`KenKemExpert.mq5:2462,2469-2484`).
```
Daily loss limit   IsWithinDailyLossLimit (SessionManager.mqh:152): lossPct from dailyStartBalance
                   >= MAX_DAILY_LOSS_RATIO=0.072 -> dailyLossLimitReached, block until next D1 bar.  (:180)
Max drawdown       IsWithinDrawdownLimit (RiskManager.mqh:440): ddPct from peakAccountBalance.
                   STAGE1 recovery at ddPct >= SLOWDOWN*RECOVERY_TRIGGER (reduced lots);
                   STAGE2 block-until-EOD at ddPct > ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN=0.105 (:571);
                   SOFT block (micro lots) at ddPct >= ACCOUNT_DD_RATIO_TO_SOFT_BLOCK=0.13 (:497);
                   PROP HARD block (zero trading) at same 0.13 if MADE_FOR_PROP_TRADING (:475).
Consecutive losses UpdateLosingStreak (RiskManager.mqh:20): global streak -> time block
                   (losingStreakBlockUntil, :30-34); per-entry-type block after
                   MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE=3 (:174) for ENTRY_BLOCK_AFTER_CONSECUTIVE_LOSS_MINS.
Win-streak cap     after WIN_STREAK_COOLDOWN_TRIGGER=3 wins (:170): lot multiplier reduced N trades
                   (WIN_STREAK_COOLDOWN_LOT_MULT), `ENABLE_WIN_STREAK_COOLDOWN`. No close.
```
For trade-level parity these matter only via lot sizing (entry agent) and which later entries fire —
they never alter an already-open trade's exit. (Matches MEMORY: "risk_manager is FAITHFUL".)

### 8b. SESSION-END close (managed, tag EA) — `CloseAllTradesAtSessionEnd` (SessionManager.mqh:385-401)
Gate `CLOSE_ALL_TRADES_AT_SESSION_END=true` (InputParams.mqh:179). Runs once per NEW M1 BAR
(`KenKemExpert.mq5:2430-2456`), BEFORE ProcessAllTrades. `IsAtSessionEnd()` (SessionManager.mqh:38-46):
`|adjustedNowJST - adjustedNY_END| <= 1` min. Closes ALL open positions via `CloseAllOpenPositions`
(:341-380) -> `SafePositionClose(...,"SESSION CLOSE")` => DEAL_REASON_EXPERT => "EA". exitPrice =
`isLong?BID:ASK` captured pre-close (:348-352).

### 8c. NEWS close (managed, tag EA) — `CloseAllPositionsBeforeHighImpactNews` (NewsCalendar.mqh:208-...)
Runs first each tick (`KenKemExpert.mq5:2424`). If `AVOID_NEWS_TRADING`: close-all when JST in
[2120,2145] (US-news window), throttled (lastNewsClosure 300s, lastCheck 120s) (:213-242). In tester,
`ENABLE_NEWS_FILTER` + local CSV (`ShouldCloseForLocalNews`) can also force a close-all (:246-267).
Both via `CloseAllOpenPositions` => "EA". **Check whether the reference run had AVOID_NEWS_TRADING /
ENABLE_NEWS_FILTER set — if so some of the 5 EA closes may be news/session, not panic.**

---

## 9. Realized P&L computation (TradeJournal.mqh:91-126 + ExecutePartialTakeProfit:1526-1591)

The journal's `realizedUsd` is reconstructed from BROKER deal history, NOT recomputed by the EA:
```
KJRealizedAndExit(posTicket): HistorySelectByPosition(posTicket)                     # :91-107
  realized = SUM over all OUT-deals (DEAL_ENTRY_OUT / OUT_BY) of
             DEAL_PROFIT + DEAL_SWAP + DEAL_COMMISSION                               # :101-103
  exitPrice = DEAL_PRICE of the LAST (latest DEAL_TIME) out-deal                     # :104-105
```
=> Partial-TP and final close are SEPARATE out-deals under the SAME netting position ticket; the partial
does NOT emit a journal row; `realizedUsd` at final close SUMS partial + final (TradeJournal header
comment lines 14-16). So the C++ engine must, per position:
```
realizedUsd = Σ_outdeal [ (exitPx_k - entryPx)*signedVol_k*contractSize  (DEAL_PROFIT)
                          + swap_k + commission_k ]
exitPrice   = last out-deal price (final close px)
```
where for XAU `contractSize ≈ 100` (broker `SYMBOL_TRADE_CONTRACT_SIZE`), profit sign per side
`isLong?(exit-entry):(entry-exit)`. The EA's own per-fill P&L (ExecutePartialTakeProfit:1565-1567)
mirrors this: `pnL = isLong?(execPrice-entry):(entry-execPrice) * volToClose * contractSize`.
**Commission/swap:** there is NO explicit commission input in the EA; realizedUsd inherits whatever the
broker/tester applies (DEAL_COMMISSION + DEAL_SWAP). For parity the C++ ledger must add the SAME
commission/swap model the MT5 tester used in the reference run (likely 0 in tester unless configured) —
verify against the broker deal rows, do not assume 0.

Partial close volume: `volToClose = NormalizeLotSize(vol*ratio)`, floored to `SYMBOL_VOLUME_MIN`
(TradeManager.mqh:1543-1546); remaining `lotSize = vol - volToClose` (:1562). For E5, ratio=0.50.

---

## 10. Parity checklist for the C++ engine
1. Manage only when `barsSinceEntry>=1` (skip entry bar); use bar high/low for HWM & SL/TP-hit (:144,231-237).
2. quality-drop/ADX/DI/cloud/sideway exits evaluate ONCE PER M1 BAR (allowQualityDropCheck), not per tick.
3. SL/TP are resting orders; broker hits => SL/TP tag. EA closes => EA tag. Trail/BE that gets hit => SL tag.
4. E5 baseline EA-tag set: §7.7 panic (ADX9-M1 + ADX14-M3 reversal), §7.4 multi-TF sideway(thr 50, ≥2 bars),
   §2A high-risk time(70 bars), §8b session-end, §8c news. All others OFF — replicate the gates exactly.
5. Partial=50% at 0.54×TP (immediate, E5), then SL->entry+2*spread; trail 0.38 factor; ladder 1.05/1.11/1.17.
6. realizedUsd = Σ out-deal (profit+swap+commission); exitPrice = last out-deal price.
