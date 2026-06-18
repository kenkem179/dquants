# 04 — Trade Manager + Risk/Sizing Port Notes (byte-level parity)

Source of truth (kenkem repo, all paths absolute):
- `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/TradeManagement/TradeManager.mqh` (1614 lines)
- `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/TradeManagement/RiskManager.mqh` (706 lines)
- `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5` (setMaxTPForTrade, sizing, ladder)
- `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/Core/GlobalState.mqh` (getMaxLossUSD, getScaledLotSize, recovery ladder)
- `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/Utils/Helpers.mqh` (GetMaxLotSize)
- `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/Utils/BrokerHelpers.mqh` (NormalizeLotSize, session-loss counter)
- `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/Utils/SessionManager.mqh` (JST sessions, daily loss)
- `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/Config/InputParams.mqh` (constants)
- `/Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/Config/RuntimeConfig.mqh` (per-side RR init, E4_RR_SHORT)

> Context that governs everything below: **entry detection is once-per-new-M1-bar (ENTRY_SHIFT=1)**, but **trade management in `ProcessAllTrades()` runs every tick**. A subset of exits (quality drop, ADX drop, DI flip, Ichimoku cloud) are additionally **bar-gated** via `allowQualityDropCheck` (fires only on the first tick of a new M1 bar — `TradeManager.mqh:101-106`). Get that gate wrong and you double-count drop counters.

---

## 1. `setMaxTPForTrade` — dynamic-RR take-profit

`KenKemExpert.mq5:1524-1586`. TP is derived from the **risk distance** (entry→SL), an RR ratio, a dynamic multiplier, and an optional aggressive boost.

```cpp
1529 double risk = MathAbs(newTrade.entryPrice - newTrade.stopLoss);
1532 double rrRatio = 1.0;
1533 bool isInSidewayMarket = IsInSidewayRange();
1534 bool useDetectionRR = false;

// E3 only: preserve the RR the detector already baked into takeProfit
1537 if (IsE3Entry(newTrade.entryType) && newTrade.takeProfit > 0 && risk > 0) {
1538     double detectionRR = MathAbs(newTrade.takeProfit - newTrade.entryPrice) / risk;
1539     if (detectionRR > 0.0) { rrRatio = detectionRR; useDetectionRR = true; }
1540 }

// All other entries: prefer adaptive per-entry reward ratio
1546 if (!useDetectionRR) {
1547     EntryBase* entryForRR = GetEntryForType(newTrade.entryType);
1548     if (entryForRR != NULL) {
1549         rrRatio = entryForRR.GetRewardRatio();          // = m_config.rewardRatio (set per side at init)
1550     } else {                                            // legacy static fallback
1552         if (IsE1Entry) rrRatio = isInSidewayMarket ? E1_RR_SIDEWAY : E1_RR;
1554         else if (IsE2Entry) rrRatio = isInSidewayMarket ? E2_RR_SIDEWAY : E2_RR;
1556         else if (IsE3Entry) rrRatio = isInSidewayMarket ? E3_RR_SIDEWAY : E3_RR;
1558         else if (IsE4Entry) rrRatio = isInSidewayMarket ? E4_RR_SIDEWAY : E4_RR;
1560         else if (IsE5Entry) rrRatio = isInSidewayMarket ? E5_RR_SIDEWAY : E5_RR;
1563     }
1564 }

1567 rrRatio *= GetDynamicRRMultiplier();                   // ATR-percentile + session scaling

1570 double finalRR = rrRatio;
1571 if (isAgressiveFlag) {                                  // boost when aggressive flag set
1573     double boostMult = (entry != NULL) ? entry.GetRRBoostMultiplier() : 1.02;
1574     finalRR = rrRatio * boostMult;
1575 }

1578 if (useDetectionRR)                                     // clamp only for E3 detection RR
1579     finalRR = MathMax(ADAPTIVE_RR_ABSOLUTE_MIN, MathMin(ADAPTIVE_RR_ABSOLUTE_MAX, finalRR));

1583 newTrade.takeProfit = isLong ? (entryPrice + finalRR * risk)
1585                              : (entryPrice - finalRR * risk);
```

### RR per entry & per side — `RuntimeConfig.mqh:55-69`
`GetRewardRatio()` returns `m_config.rewardRatio`, which is set per **side** at init. The asymmetric short factors:

```cpp
56 CFG.rrLongE1 = E1_RR;            CFG.rrShortE1 = E1_RR * 0.875;     // E1: short 12.5% lower
59 CFG.rrLongE2 = E2_RR;            CFG.rrShortE2 = E2_RR * 0.867;     // E2: short 13.3% lower
62 CFG.rrLongE3 = E3_RR;            CFG.rrShortE3 = E3_RR * 0.778;     // E3: short 22.2% lower
65 CFG.rrLongE4 = E4_RR;            CFG.rrShortE4 = E4_RR_SHORT * 0.875;  // ** E4 short = E4_RR_SHORT*0.875 **
68 CFG.rrLongE5 = E5_RR;            CFG.rrShortE5 = E5_RR;             // E5: symmetric (Pine parity)
```

**Critical E4 detail:** E4 long uses `E4_RR` (2.4). E4 short does **not** scale the long value — it uses a *separate input* `E4_RR_SHORT` (1.8) times 0.875 ⇒ **1.575**. Do not derive E4 short from E4 long.

RR input defaults (`InputParams.mqh`): `E1_RR=1.9` / `E1_RR_SIDEWAY=1.2`; `E2_RR=1.575` / `1.1`; `E3_RR=2.3` / `1.3`; `E4_RR=2.4`, `E4_RR_SHORT=1.8`, `E4_RR_SIDEWAY=1.15`; `E5_RR=1.5` / `1.2`. RR clamp: `ADAPTIVE_RR_ABSOLUTE_MIN=1.1`, `ADAPTIVE_RR_ABSOLUTE_MAX=2.5`. Aggressive boost `GetRRBoostMultiplier()` default `1.02`.

> Port watch-outs: (a) `GetDynamicRRMultiplier()` (line 1567) and `IsInSidewayRange()` (1533) must be ported exactly — they alter TP for every trade. (b) The clamp at 1579 only applies to E3 detection-RR, **not** to the others. (c) RR is chosen by `m_config.rewardRatio` (per-side), so the long/short asymmetry lives at init, not in `setMaxTPForTrade`.

---

## 2. Position sizing (risk$ → lots)

There is **no single `CalculateLotSize`**. The chain is: `getMaxLossUSD(entryType)` → risk-budget$ → divide by per-pip value → cap by margin → cap by `getScaledLotSize` → `NormalizeLotSize`.

### 2a. Per-entry risk ratios — `InputParams.mqh:62,65-69` (plain doubles, not `input`)
```cpp
62 input double COMMON_MAX_RISK_PER_TRADE = 0.02;
65 double MAX_LOSS_RATIO_E1 = COMMON_MAX_RISK_PER_TRADE * 1.05;   // 0.0210
66 double MAX_LOSS_RATIO_E2 = COMMON_MAX_RISK_PER_TRADE * 1;      // 0.0200
67 double MAX_LOSS_RATIO_E3 = COMMON_MAX_RISK_PER_TRADE * 0.97;   // 0.0194
68 double MAX_LOSS_RATIO_E4 = COMMON_MAX_RISK_PER_TRADE * 1.02;   // 0.0204
69 double MAX_LOSS_RATIO_E5 = COMMON_MAX_RISK_PER_TRADE * 1.0;    // 0.0200
82 double MAX_AGGREGATE_RISK_RATIO = MAX_LOSS_RATIO_E1 * 4;       // 0.084 (open-risk cap)
```
Dispatch `GetEntrySpecificRiskRatio` — `GlobalState.mqh:633-643` (E1..E5 → ratio above; unknown → E2).

### 2b. Risk-budget dollars `getMaxLossUSD(entryType)` — `GlobalState.mqh:716-763`
```cpp
718 double riskRatio = (entryType==ENTRY_UNKNOWN) ? MAX_LOSS_RATIO_E2 : GetEntrySpecificRiskRatio(entryType);
// profit-scaled budget when flat & in profit, else min(bal,initial)*ratio
722 if (consecutiveLosses<=0 && accountBalance>INITIAL_ACCOUNT_BALANCE && INCREASE_LOT_SIZE_BASED_ON_PROFIT) {
723     double scaledBalance = accountBalance*PROFIT_SCALING_WEIGHT_CURRENT + INITIAL_ACCOUNT_BALANCE*PROFIT_SCALING_WEIGHT_INITIAL;
724     entryMaxLoss = scaledBalance * riskRatio;
725 } else { entryMaxLoss = MathMin(accountBalance*riskRatio, INITIAL_ACCOUNT_BALANCE*riskRatio); }
// then capped by remaining daily-loss room and remaining drawdown room (using worst-case open loss):
734 maxPotentialLoss = GetTotalMaxPotentialLoss();
737 dailyRoomLeft    = dailyStartBalance*MAX_DAILY_LOSS_RATIO - (dailyStartBalance-currentBalance) - maxPotentialLoss;
742 drawdownRoomLeft = peakAccountBalance*ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN - (peakAccountBalance-currentBalance) - maxPotentialLoss;
747 cappedMaxLoss = MathMin(entryMaxLoss, MathMin(dailyRoomLeft, drawdownRoomLeft));
750 cappedMaxLoss = MathMax(cappedMaxLoss, accountBalance*MIN_RISK_FLOOR_RATIO);   // floor 0.5%
762 return cappedMaxLoss;
```

### 2c. The actual lot recompute (entry path) — `KenKemExpert.mq5:1804-1813`
```cpp
1804 double pointValue        = contractSize * pipSize;             // per-PIP value of 1 lot
1805 double maxLotsBasedOnRisk = entrySpecificMaxLoss / pointValue; // entrySpecificMaxLoss = getMaxLossUSD(entryType)
1806 double marginPerLot      = contractSize * currentPrice / LEVERAGE;
1807 double maxUsedMargin     = accountBalance / (MARGIN_LEVEL_PERCENT/100.0);
1808 double maxLotsMargin     = maxUsedMargin / marginPerLot;
1809 double adjustedLotSize   = MathMin(maxLotsBasedOnRisk, maxLotsMargin);
1810 adjustedLotSize = MathMin(adjustedLotSize, getScaledLotSize(entryTypeEnum, entry.GetLotMultiplier(), entry.GetVolLotAdjEnabled()));
1813 detectedTrade.lotSize = NormalizeLotSize(adjustedLotSize);
```

> **PARITY-CRITICAL SIZING SUBTLETY:** `maxLotsBasedOnRisk = riskUSD / (contractSize*pipSize)` divides by the **per-pip value**, *not* by the SL distance. So it caps the lot to "how many pips of risk the budget buys", and the SL distance enters only through `entrySpecificMaxLoss` (a dollar budget) and downstream caps. This is NOT the textbook `lot = risk$ / (SL_dist * value_per_price)`. Replicate the per-pip form exactly. `getScaledLotSize` is taken as a hard `MathMin` cap on top (recovery/profit/win-streak/vol multipliers applied to `myStandardLotSize`, `GlobalState.mqh:561-630`). `feeFactor` in the sibling `GetMaxLotSize` (`Helpers.mqh:121`) is computed but **unused** — ignore it.

Broker specs for the port: BTCUSD `pipSize=0.1, contractSize=1`; XAUUSD `pipSize=10^-digits (0.01), contractSize=100`; `minLot=0.01`; deposit $10k, leverage 1:200. **`pipSize`/`contractSize`/`myStandardLotSize` are mutated in OnInit by symbol auto-detection** (`KenKemExpert.mq5 ~125-161`, BTC branch multiplies `myStandardLotSize*=10`). Use the post-detection values.

### 2d. `NormalizeLotSize` — `BrokerHelpers.mqh:144-162` (the min-lot floor-up)
```cpp
145 minLot=SYMBOL_VOLUME_MIN; maxLot=SYMBOL_VOLUME_MAX; lotStep=SYMBOL_VOLUME_STEP;
150 if(lotSize < minLot) lotSize = minLot;          // floor-up BEFORE rounding
151 if(lotSize > maxLot) lotSize = maxLot;
155 if(lotStep>0) lotSize = MathRound(lotSize/lotStep)*lotStep;   // NEAREST, not floor
159 if(lotSize < minLot) lotSize = minLot;          // floor-up AGAIN after rounding
162 return lotSize;
```
> **"flooredUp min-lot" bug source:** any sub-min risk-derived lot is bumped **up** to `minLot` (lines 150 & 159). Rounding is `MathRound` (nearest), NOT `MathFloor`. (Contrast `GetMaxLotSize` `Helpers.mqh:134` which rounds **down** with `MathFloor`.) A prior port floored-up incorrectly — match: clamp→nearest-round→clamp.

---

## 3. PER-TICK MANAGEMENT — exact ordered sequence

`ProcessAllTrades()` (`TradeManager.mqh:76-278`). Per open trade, oldest-to-newest is iterated newest-first (`for i = size-1 .. 0`). For each `i`:

**Pre-checks (in order):**
1. Skip `SKIPPED*` virtual trades (`:118,141`).
2. `barsSinceEntry == 0` → **continue** (no management on entry bar — TV rule) (`:122,145`).
3. **High-risk time exit** (`:149`): if `trades[i].isHighRiskTrade && barsSinceEntry >= HIGH_RISK_MAX_BARS` (default **70**) → close, status `EARLY_EXIT`, `continue`.
4. Smart broker check (`:190-227`): calls `CheckTradeStatusOnBrokerBeforeUpdating` when price touched SL/TP, about to modify, or every 20th tick.
5. Update `bestPrice` (`:232`); compute `hitWin`/`hitLoss` (`:236-237`).

**Then, only if `!hitWin && !hitLoss && barsSinceEntry > 0` (`:239`):** `currentPnL = isLong ? (price-entry) : (entry-price)`, then in EXACT order:

| # | Function (`:line`) | Trigger condition | Action |
|---|---|---|---|
| A | `ApplyPreBEStructureProtection` (`:243,284`) | `ENABLE_PRE_BE_STRUCTURE_PROTECTION` && not BE && not partial-eligible && `rMultiple = currentPnL/originalRisk >= PRE_BE_TRIGGER_R`; optional M3-accel confirm; price breaches prior swing (lookback `PRE_BE_BOS_LOOKBACK_BARS`) by `PRE_BE_BOS_BREACH_BUFFER_PIPS` | tighten SL toward breakout extreme ± `PRE_BE_SWING_BUFFER_PIPS`, kept strictly **pre-entry** (margin `0.5*pip`); only if improvement ≥ `PRE_BE_MIN_SL_IMPROVEMENT_PIPS` |

Then **mode branch** (`:245-253`):

- **If `ENABLE_CONSERVATIVE_TRADE_MGMT`:** B = `ApplyConservativeTradeManagement` (`:247,486`) — see §4.
- **Else (standard mode), in order:**
  - B1 `ApplyRMultipleSLProtection` (`:250,402`)
  - B2 `ExtendTPAsNeeded` (`:251,606`)
  - B3 `TakePartialProfitAsNeeded` (`:252,674`) — which itself runs, in order: mark eligible → E5 immediate partial+BE → non-E5 best-price track → non-E5 partial on weaken/retrace+BE → `CheckAndApplyLadderStages` (if partial taken) → `CalculateTrailingSLForTrade` (if eligible or partial taken).

Then **early-exit block** `ExitEarlyAsNeeded` (`:256,969`), checked in this EXACT order:

| # | Exit (`:line`) | Bar-gated? | Trigger | Input vars |
|---|---|---|---|---|
| E1 | **Quality/score-drop exit** (`:973`) | yes (`allowQualityDropCheck`) | per-entry `GetEnableScoreDropExit()`; `qualityDrop = bestQualityScore - currentQuality >= threshold` (per-entry `GetScoreDropThreshold()`, default 3) for `qualityDropCount >= SCORE_DROP_CONSECUTIVE_CHECKS` (**3**) AND (`hasTakenPartialProfit` OR floating profit `< 10%` of TP) | `SCORE_DROP_CONSECUTIVE_CHECKS` |
| E2 | **ADX-drop exit** (`:1045`) | yes | `ENABLE_ADX_DROP_BASED_EXIT`; ADX `cache.adx[TF0]` declines `adxDropCount >= ADX_DROP_EXIT_BARS` (**3**) consecutive bars AND `currentAdx < entry.GetMinADX()` | `ADX_DROP_EXIT_BARS` |
| E3 | **DI-flip fast exit (M1)** (`:1094`) | yes | per-entry `GetEnableDIFlipExit()`; opposing DI crosses with spread `>= DI_FLIP_MIN_SPREAD_M1` (**4.0**) AND `adx >= DI_FLIP_MIN_ADX_M1` (**18.0**) for `diFlipCount >= DI_FLIP_CONSECUTIVE_M1_BARS` (**2**) AND `slUsedRatio >= DI_FLIP_MIN_SL_USED_RATIO` (**0.4**) | listed |
| E4 | **E5 multi-TF sideway exit** (`:1180`) | no (`currentBar > entryBar+1`) | E5 only && `E5_ALLOW_SIDEWAY_EARLY_EXIT` && `IsMultiTfSideway(E5_SIDEWAYS_BLOCK_THRESHOLD)` (2/3 TFs) | `E5_SIDEWAYS_BLOCK_THRESHOLD` |
| E5 | **Sideway exit (non-E5)** (`:1214`) | no | `ENABLE_SIDEWAY_EARLY_EXIT`; price stagnating (no new extreme over `SIDEWAY_EXIT_CONSECUTIVE_BARS`) AND sideway score rising, for `sidewayDriftCount >= SIDEWAY_EXIT_CONSECUTIVE_BARS` | `SIDEWAY_EXIT_CONSECUTIVE_BARS` |
| E6 | **Ichimoku cloud exit** (`:1272`) | yes | per-entry `GetExitInIchiCloud()`; long close `< cloudTop` / short close `> cloudBottom` for `insideCloudCount >= ICHI_CLOUD_EXIT_BARS` | `ICHI_CLOUD_EXIT_BARS` |
| E7 | **Panic exit (ADX reversal)** (`:1351`) | no | per-entry `GetEnablePanicADXExit()` (default true). Scenario A (`hasTakenPartialProfit && floatingPnL>0`): profit giveback `(mfe-floatingPnL)/mfe >= PANIC_MIN_PROFIT_GIVEBACK` (**0.5**). Scenario B (`floatingPnL<0`): `usedSLRatio = -floatingPnL/slDist >= entry.GetPanicMinSLUsedRatio()` (default `PANIC_MIN_SL_USED_RATIO`=**0.6**, E3=**0.45**). Then needs **both** `HasTrendAcceleration(M1,reversed,4,9)` AND `HasTrendAcceleration(M3,reversed,3,14)` | `PANIC_MIN_PROFIT_GIVEBACK`, `PANIC_MIN_SL_USED_RATIO`, `PANIC_MIN_SL_USED_RATIO_E3` |
| E8 | **Early-cut near SL** (`:1449`) | no | `!panicExitHandled && ENABLE_EARLY_CUT_NEAR_SL`. Rule 1: super-strong opposing `HasTrendAcceleration(M3,reversed,3)`. Else: SL reached `>= entry.GetEarlyCutRatio()` (default 0.88) AND (`!HasSufficientMomentum` OR `IsTrendWeakening`) | `ENABLE_EARLY_CUT_NEAR_SL` |

After early-exit block: `CheckAndSendPnLZoneUpdate` (`:259`, alerts only — no trade effect, skip for parity).

> **Parity must preserve this order:** Pre-BE → (conservative | RMult-BE → TP-ext → Partial[→ladder→trail]) → E1 score-drop → E2 ADX-drop → E3 DI-flip → E4 E5-sideway → E5 sideway → E6 cloud → E7 panic → E8 early-cut. First exit that closes the position sets `newStatus != OPEN`; later checks are gated by `newStatus == "OPEN"` so they no-op. A single reordering changes which exit fires first → different exit price → trade-level mismatch.

---

## 4. Partial closes ↔ SL/BE interaction

Partial TP **moves SL to breakeven+buffer**, but the buffer and timing differ per mode. SL is moved **only after** the partial fill is confirmed profitable (`actualPnL > 0`); on a loss-side partial, SL is **left unchanged** (`:790-794`, `:730-733`).

- **Standard non-E5** (`TakePartialProfitAsNeeded :674`):
  - Eligible when `currentPnL >= partialTrigger * origTPDist` (per-entry `GetPartialTPTrigger()` default 0.65; high-risk override `HIGH_RISK_PARTIAL_TP_TRIGGER`). Marks `partialTPEligible`, records `bestPriceSinceEligible` (`:687-693`).
  - Executes partial only when **eligible AND (trend weakening OR significant retrace)**, retrace ratio `PARTIAL_TP_RETRACE_RATIO` (**0.15**) of gained vs peak (`HasSignificantRetrace :30-36`, `:752`). Ratio `GetPartialTPRatio()` default 0.5.
  - On profitable partial → SL to `entry ± origTPDist * GetBreakevenBuffer()` (default 0.02) (`:769-777`); sets `slMovedToBreakeven`, `hasTakenPartialProfit`.
- **E5** (`:696-739`): partial executes **immediately at level** (no weaken/retrace gate). BE buffer = `2 * spread` (Pine SuperBros parity).
- **Conservative mode** (`ApplyConservativeTradeManagement :486`): PHASE 1 fires once at `currentR >= GetConsInitialPartialR(entry)` (E1..E5 defaults 0.30) → partial `GetConsInitialPartialRatio` (default 0.10) → SL to `entry ± GetConsPostPartialSLR(entry)*originalRisk` (default 0.15R). Sets `slMovedToBreakeven`, `rMultipleBEApplied`. PHASE 2 trails: every `GetConsTrailRIncrement` (0.10R) of new R, shift cumulative SL by `GetConsTrailSLStepR` (0.025R), `newSL = entry ± cumShift*originalRisk` (`:545-600`).
- **Independent R-multiple BE** (standard, before partial): `ApplyRMultipleSLProtection :402` moves SL to `entry ± originalRisk*R_MULT_BE_BUFFER` when `rMultiple >= R_MULT_BE_TRIGGER`. Defaults **`R_MULT_BE_TRIGGER=0.87`**, **`R_MULT_BE_BUFFER=0.055`**. Guarded by `rMultipleBEApplied`/`slMovedToBreakeven` so it fires at most once and not after partial-BE.

> So: **the first partial does move SL to BE+buffer**, at the per-mode R-multiple/buffer above — but `ApplyRMultipleSLProtection` can move SL to BE *earlier* (at 0.87R) independent of any partial. `originalRisk = bufferedSLDistancePips * pipSize` (stored at trade creation) is the R denominator throughout — port it as a fixed per-trade value, not recomputed from current SL.

### Laddered exits — `CheckAndApplyLadderStages` / `ApplyLadderStage` (`KenKemExpert.mq5:1651-1738`)
Only runs after `hasTakenPartialProfit` and per-entry `GetEnableLadderedExtensions()`. Stages checked **highest-first, advance-only**:
```cpp
1669 if (ladderStageReached<3 && currentPnL >= GetLadderStage3Multiplier()*origTPDist) ApplyLadderStage(3, GetLadderStage3TrailRatio());
1673 else if (ladderStageReached<2 && currentPnL >= GetLadderStage2Multiplier()*origTPDist) ApplyLadderStage(2, ...);
1677 else if (ladderStageReached<1 && currentPnL >= GetLadderStage1Multiplier()*origTPDist) ApplyLadderStage(1, ...);
```
`ApplyLadderStage`: `newSL = price ∓ trailRatio*currentProfit`, applied only if improvement (`:1693-1700`). Stage multipliers/trail-ratios are per-entry virtuals — fetch numeric defaults from each `Entry*.mqh` for the port.

---

## 5. Per-tick recompute of indicator-derived exit signals — lookahead audit

These exits read **live indicator values** on management ticks, NOT the ENTRY_SHIFT=1 cached values:

- **Score-drop (E1):** `GetActiveTradeMomentumScore(trend, entryNum)` recomputed each gated bar; `currentPriceChk = iClose(_Symbol,TF0,0)` (`:998`) — **current/forming bar close**. Bar-gated, so it reads the forming bar once per new M1 bar.
- **ADX-drop (E2):** `cache.adx[TF0]` (`:1046`). `cache` ADX uses the cache's shift; bar-gated.
- **DI-flip (E3):** `cache.diPlus[TF0]/diMinus[TF0]/adx[TF0]` (`:1100-1102`). Bar-gated.
- **Ichimoku cloud (E6):** explicitly reads **bar 0** Senkou A/B via `CopyBuffer(handle,2/3,0,1,...)` and `iClose(_Symbol,TF0,0)` (`:1287-1292`). Comment at `:1278` notes it intentionally bypasses ENTRY_SHIFT cache to test the last/forming bar.
- **Panic (E7):** `currentPrice = iClose(_Symbol,TF0,0)` (`:1358`) and `HasTrendAcceleration(...)` on M1/M3.
- **Sideway (E5):** `iHigh/iLow ... iHighest/iLowest(...,lookback,0)` includes bar 0 (`:1219-1221`).

> **Lookahead risk for the tick-replay engine:** MT5 live uses the *forming* bar's running close at tick time — that is legitimate (no future data). But a naive Parquet replay that hands the exit functions the **completed** bar-0 OHLC would leak the bar's final high/low/close before they occur. To preserve parity AND avoid lookahead, feed these `iClose/iHigh/iLow(...,0)` reads the **running** values as of the current tick (tick price for close; running max/min for high/low), not the sealed bar. The bar-gate (`allowQualityDropCheck`, first tick of new M1 bar) means E1/E2/E3/E6 evaluate on the *first tick* of the new bar — at that instant bar-0 has essentially just opened, so `iClose(...,0)` ≈ open; replicate that timing exactly.

---

## 6. Session/time gates affecting management & new entries

### JST sessions — `SessionManager.mqh`
`ToJST(utc) = utc + 9*3600` (`:13-17`). `IsNowInValidSession()` (`:118-147`): blocks if `AVOID_NEWS_TRADING && 2120 <= JST <= 2145` or `IsNearImportantNews()`; else allows inside Japan/London/NY windows. After-midnight times `<= 630` get `+2400` (`:30-31`).

Session inputs — `InputParams.mqh:558-564`:
```cpp
559 JAPAN_START=900   560 JAPAN_END=1230   561 LONDON_START=1400   562 LONDON_END=1830
563 NY_START=2100     564 NY_END=2400      558 AVOID_NEWS_TRADING=true
179 CLOSE_ALL_TRADES_AT_SESSION_END = true
```
(Note: `GetCurrentSession()` `:61-73` uses different boundary constants `JAPAN_START..NY_END` named identically; the `IsNowInValidSession` path is the gating one.)

### Daily loss limit — `SessionManager.mqh:152-201` (checked in `GetEntryBlockReason` P0 Check 1)
```cpp
153 today = iTime(_Symbol, PERIOD_D1, 0);          // reset on new D1 bar
156 if(today != currentDate){ currentDate=today; dailyStartBalance=AccountInfoDouble(ACCOUNT_BALANCE); dailyLossLimitReached=false; }
171 if(dailyLossLimitReached) return false;
177 dailyLoss = dailyStartBalance - currentBalance;
178 lossPercent = dailyLoss / dailyStartBalance;
180 if(lossPercent >= MAX_DAILY_LOSS_RATIO) { dailyLossLimitReached=true; return false; }   // MAX_DAILY_LOSS_RATIO=0.072
201 return true;
```

### Max session losses (hard stop on new entries) — per Entry*.mqh gate
`Entry1.mqh:83-87` (identical in E2:81, E3:171, E4:84, E5:115):
```cpp
84 if (sessionLossCount >= MAX_SESSION_LOSSES) return result;     // MAX_SESSION_LOSSES = 4
```
Counter increment — `BrokerHelpers.mqh:277-286`: a loss that is **not** a partial-protected breakeven increments `sessionLossCount`; BE increments `sessionBreakEvenCount`; win increments `sessionWinCount`.

```cpp
277 bool isBreakEven = (slMovedToBreakeven && hitSL && !hasTakenPartialProfit);
279 if (isLoss && !isBreakEven) sessionLossCount++;
281 else if (isBreakEven) sessionBreakEvenCount++;
283 else sessionWinCount++;
```

### Other entry gates — `GetEntryBlockReason` (`RiskManager.mqh:241-339`) order
Black-swan cooldown → spread (`MAX_SPREAD_PIPS` over `SPREAD_BLOCK_CONSECUTIVE_BARS`) → spread/ATR (`MAX_SPREAD_ATR_RATIO`) → ATR percentile (`ATR_PERCENTILE_LOW/HIGH`) → vol regime (`MIN_ENTRY_ATR_PERCENTILE`) → daily loss (P0-1) → max positions (P0-2) → aggregate risk `>= MAX_AGGREGATE_RISK_RATIO` (P0-3) → `MIN_SECONDS_BETWEEN_ENTRIES` cooldown (P0-4).

### Drawdown / recovery (affects sizing every tick) — `RiskManager.mqh:440-615`
`IsWithinDrawdownLimit` drives mode flags read by `getScaledLotSize`/`GetRecoveryModeLotMultiplier`. Thresholds: `ACCOUNT_DD_RATIO_TO_SOFT_BLOCK=0.13` (soft block → `SOFT_BLOCK_LOT_MULTIPLIER=0.3`), `ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN=0.105` (block until EoD), recovery trigger `*RECOVERY_MODE_TRIGGER_RATIO=0.9`, exit `*RECOVERY_MODE_EXIT_RATIO=0.95`, `RECOVERY_MODE_LOT_MULTIPLIER=0.6`. Recovery ladder (E3 only enabled by default): step 0.10, min 0.30, max 1.00 (`GlobalState.mqh:483-557`).

Other constants: `HIGH_RISK_MAX_BARS=70`, `MIN_RISK_FLOOR_RATIO=0.005`, `PROFIT_PROTECTION_LOT_MULTIPLIER=0.75`, `WIN_STREAK_COOLDOWN_LOT_MULT=0.60`.
