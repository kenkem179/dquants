# KenKem Exit-Parity Port Spec — ground truth = canonical `KenKemExpert.mq5` (v1.8.154)

_Built 2026-06-18 by reading the canonical EA only (per user: ignore all `1.8.x`-suffixed files).
Goal: make the C++ tick engine's per-tick exit management byte-faithful to the EA so matched-trade
exits (exitTag + ΔpnlUSD + Δrisk) → ~0 and the engine entry-count collapses 142→78 (occupancy aligns)._

## 0. Why this exists — the C++ models the WRONG manager
The reference MT5 run (78 entries / 96 closing deals / `EMAs=[25,75,100,200]`) was produced by
`kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5`. Its tick management is a **9-mechanism pipeline**
(`TradeManager::ProcessAllTrades`, TradeManager.mqh:76). The C++ `trade_manager.hpp` deliberately
distilled it to **partial → BE → single chandelier trail** (see its own header comment line 7) and
dropped the rest. Proof it's the wrong model: exit-tag mix engine vs MT5 → **SL-WIN 7% vs 35%**
(ladder books profit-locked stops the chandelier never reaches).

## 1. OnTick order (KenKemExpert.mq5:2393)
1. News close (`CloseAllPositionsBeforeHighImpactNews`) — likely inert in tester.
2. **New-bar block** (`currentBar != lastBarIndex`): `UpdateIndicatorCache()` (refreshes `cache.currentPrice/high/low` — **once per bar**), then **`CloseAllTradesAtSessionEnd()`** (per bar).
3. **`tradeManager.ProcessAllTrades()` — EVERY tick.** Manages all open trades (the pipeline below).
4. Safety checks (block NEW entries only).
5. Entry detection / execution.

⚠️ **Price resolution is mixed and load-bearing:**
- BE / partial / TP-extend / pre-BE read `cache.currentPrice/high/low` = **per-bar** (TradeManager.mqh:96-98).
- Ladder reads **live `iClose(_Symbol,TF0,0)`** every tick (KenKemExpert.mq5:1668).
- High-risk time-exit + partial execution read **live bid/ask** (`SymbolInfoDouble`, TradeManager.mqh:155, 901).
- Actual SL/TP **fills are broker-level** (tester triggers the attached SL/TP order tick-accurately);
  the EA only polls via `CheckTradeStatusOnBrokerBeforeUpdating` when `low<=SL || high>=TP` (bar h/l) or before a modify.

## 2. The per-tick pipeline (STANDARD mode — `.set ENABLE_CONSERVATIVE_TRADE_MGMT=false`)
For each OPEN real trade, skipping the entry bar (`barsSinceEntry==0`, TM:122):

| # | mechanism | fn (TradeManager.mqh) | trigger | action | .set (2yr) |
|---|---|---|---|---|---|
| A | High-risk time exit | TM:~140 | `isHighRiskTrade` & bars≥`HIGH_RISK_MAX_BARS` | market close, tag EARLY_EXIT | `HIGH_RISK_MAX_BARS=70` |
| B | SL/TP hit | TM:193-237 | bar `low<=SL`/`high>=TP` → broker poll | broker fills at SL/TP level | (broker) |
| C | Pre-BE structure protect | `ApplyPreBEStructureProtection` TM:284 | `R≥PRE_BE_TRIGGER_R` & M3 accel & BOS breach (lookback) | tighten SL to structure | `ENABLE_PRE_BE_STRUCTURE_PROTECTION=true, PRE_BE_TRIGGER_R=0.5, …` |
| D | R-multiple SL→BE | `ApplyRMultipleSLProtection` TM:402 | `currentPnL/origRisk ≥ R_MULT_BE_TRIGGER` | `SL=entry±origRisk*R_MULT_BE_BUFFER` (improve-only); sets slMovedToBE | `R_MULT_BE_TRIGGER=0.87, R_MULT_BE_BUFFER=0.055` |
| E | TP extension | `ExtendTPAsNeeded` TM:606 | (read pending) | extend TP, `tpExtensions++` | `ALLOW_TP_EXTENSION=true` |
| F | Smart partial (TP1) | `TakePartialProfitAsNeeded` TM:674 | eligible at `pnl≥trig*origTPDist`; **execute only on trendWeakening OR retrace≥`PARTIAL_TP_RETRACE_RATIO`** (E5: immediate) | close `partialRatio` at **current price**; BE=`entry±origTPDist*GetBreakevenBuffer(0.02)` (E5: entry+2*spread) | `ALLOW_PARTIAL_TP=true, PARTIAL_TP_RETRACE_RATIO=0.15, E1_PARTIAL_TP_TRIGGER=0.9, E1_PARTIAL_TP_RATIO=0.2` |
| G | Ladder trail (3 stages) | `CheckAndApplyLadderStages`/`ApplyLadderStage` (KenKemExpert.mq5:1658/1690) | only if `hasTakenPartialProfit`; `currentPnL ≥ StageN_Mult*origTPDist` (N=3,2,1 high→low) | `SL = curPrice − StageN_TrailRatio*curProfit` (improve-only) | `E1_ENABLE_LADDERED_EXTENSIONS=true` |
| H | Early exit (quality/DI) | `ExitEarlyAsNeeded` TM:969 | quality-drop (bar-gated), etc. | market close | `ENABLE_EARLY_CUT_NEAR_SL=false` |
| I | Session-end close | `CloseAllTradesAtSessionEnd` (per bar) | outside session window | market close all → **"EA" exitTag** | (session params) |

## 3. Confirmed formulas (verbatim from canonical)
- **R-mult BE (D):** `R=currentPnL/originalRisk; if R≥0.87: newSL=entry±originalRisk*0.055` (improve-only). `originalRisk=bufferedSLDistancePips*pipSize`. (TM:402-455)
- **Smart partial (F):** eligible when `currentPnL≥trig*origTPDist`; track `bestPriceSinceEligible`; execute when `IsTrendWeakening || HasSignificantRetrace(0.15)`; BE after = `entry±origTPDist*0.02`. **Partial fills at live price, not the trigger level.** (TM:674-807)
- **Ladder (G):** `currentProfit=curPrice−entry; newSL=curPrice−trailRatio*currentProfit` (long), improve-only, normalized; 3 discrete stages keyed off `StageN_Multiplier*origTPDist`; never regress. (KenKemExpert.mq5:1658-1745)
- `origTPDist = |originalTP − entry|` used by F & G.

## 4. C++ deltas (what's wrong today, trade_manager.hpp)
1. **Trail:** chandelier `best−trailF*risk` ⇒ must become 3-stage ladder `curPrice−StageN_ratio*curProfit`.
2. **Partial:** fires immediately at trigger level ⇒ must become eligible→(weakening|retrace 0.15)→fill at live price.
3. **BE after partial:** `entry+be_buffer*risk` ⇒ must become `entry±origTPDist*0.02` (+ separate R-mult BE at 0.87R).
4. **Missing entirely:** R-mult BE (D), TP-extension (E), pre-BE structure (C), high-risk time-exit (A), early-exit (H), session-end close (I).
5. **Price resolution:** must replicate per-bar `cache` vs live `iClose(0)` vs bid/ask split (§1).
6. The trail-live-risk fix (commit, `KK_TRAIL_LIVE_RISK`) is moot once the ladder replaces the chandelier — keep or drop with the rewrite.

## 5. Still to read before/while implementing (not yet fully verified)
- `ExtendTPAsNeeded` (E) full formula + `GetMaxTPExtensions`.
- `ApplyPreBEStructureProtection` BOS/structure detail past TM:309 + `HasTrendAcceleration`.
- `ExitEarlyAsNeeded` (H) exact conditions (quality-drop, DI-flip).
- `CloseAllTradesAtSessionEnd` window + how it tags/export ("EA").
- `IsTrendWeakening` / `HasSignificantRetrace` (gate partial execution).
- `cache.currentPrice/high/low` exact values from `UpdateIndicatorCache`.
- Per-entry getters: `GetPartialTPTrigger/Ratio/BreakevenBuffer/LadderStageN_Multiplier/TrailRatio` defaults vs `.set`.

## 6. Suggested phased port (each phase: implement → re-run 2yr E1 diff → measure exitTag+Δpnl)
- **P1** Ladder trail (G) replacing chandelier + smart-partial (F) + correct BE → biggest SL-WIN parity gain.
- **P2** R-mult BE (D) + session-end close (I) → recovers the "EA"-tag exits + early BE behavior.
- **P3** TP-extension (E) + high-risk time-exit (A).
- **P4** Pre-BE structure (C) + early-exit (H) — need structure/trend indicators in the engine.
Measure after each; some need indicators the engine may not yet compute (flag as sub-scope).
