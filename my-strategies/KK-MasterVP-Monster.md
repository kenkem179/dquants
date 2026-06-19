# KK-MasterVP-Monster — Strategy Description

> Tick-volume-profile scalper for XAUUSD/BTCUSD on M3 (strongest results on BTCUSD so far). Entries fire off a fresh cross of a rolling 150-bar "master" volume-profile level (VAH/VAL/POC), confirmed by multi-timeframe near-price net tick volume (M1/M3/M5, plus M15 for the opt-in HTF gate). Core edge hypothesis: a confirmed break of (or rotation between) master value-area levels with strongly one-sided near-price tick flow continues far enough to pay a 2–3R bracket, while a new impulse-thrust path captures the high-volatility breaks the normal ATR ceiling would otherwise veto.

## 1. Overview

- **Instruments:** XAUUSD and BTCUSD (CFD tick-volume feeds). Best measured results on BTCUSD.
- **Timeframe:** chart/entry TF is M3. `validTf` accepts 30s, M1, M3, M5, M15 only (red background otherwise); everything in the spec assumes M3.
- **Style:** intraday scalper, long and short, stacking allowed (up to 3 concurrent positions per direction; `pyramiding=20` in the declaration but the effective cap is the hidden `maxConcurrentPerDir = 3`). One trade per fresh level cross — the arming cross is consumed on entry.
- **Source file:** `kenkem-pine/kk-vp/KK-MasterVP-Monster.pine` (Pine v6 strategy; ignore `KK-MasterVP-Monster-old.pine`).
- **Relation to KK-MasterVP (base):** the VP engine, node-flow engine, net-tick-volume reads, per-entry registry, visuals and Discord alerts are ported verbatim from `KK-MasterVP.pine`. Monster adds, on top of the base breakout + 4-variant mean-reversion:
  - **Impulse-thrust entry path (kind 4)** that fires only *above* the volatility ceiling the other paths refuse.
  - **Predicted (aged-out) master profile** `pMPoc/pMVah/pMVal` — the master window with the oldest `impulsePredictBars` bars expired — used for the impulse trend gate, impulse anti-chase distance, and the POC-stability gate.
  - **Opt-in gates (all default OFF = byte-identical baseline):** regime (trend/range router), master-POC stability, breakout overhead-supply veto, HTF (M5+M15) net-volume bias.
  - **M1-flush early exit** decoupled from the legacy M1-AND-M3 flush.
  - **Per-strategy TP1 split:** separate TP1 distance and close-% for Breakout/Impulse vs Mean-Reversion.
  - **Decision telemetry** (per-bar veto bitmasks, trade-comment decision vectors, debug tables) — display-only.
- **Backtest properties as declared:** initial capital 10,000 USD, commission `cash_per_order` 0.50, slippage 8 ticks, `calc_on_every_tick=true`, `process_orders_on_close=false`, `use_bar_magnifier=true`. Decision locks on the confirmed bar; orders fill next bar open.
- **MQL5 EA port:** in progress at `kenkem/MQL5/Experts/KK-MasterVP-Monster/` (magic 88260611, v1 single-position), plan in `kenkem/notes/KK-MasterVP-Monster-EA-Port-Plan.md`. Neither MasterVP variant has cleared the deploy gate; promising backtests only.

## 2. Market Context / Regime Detection

### Volume-profile construction (`f_vp`)
- **Local profile:** last `vpLookback` (50) completed bars, `vpBins` (40) price buckets between the window's lowest low and highest high. Each bar contributes its full `volume` to the single bin containing its `hlc3`.
- **Master profile:** same algorithm over `vpLookback * masterMult` = 50 × 3 = **150 bars**.
- **POC** = highest-volume bin (center price). **Value area** = 70% of total volume (`vaPct = 70`), expanded greedily from the POC bin, preferring the higher-volume neighbor (ties go up: `nextH >= nextL`). **VAH** = top of the upper VA bin, **VAL** = bottom of the lower VA bin.

### Predicted / aged-out master POC
`[pMPoc, pMVah, pMVal] = f_vp(150, 40, 70, impulsePredictBars)` — the same master window with the oldest `impulsePredictBars` (10) bars dropped (`useLen = max(bins, len - skipOld)`). Because the master window is rolling, old high-volume nodes expire and POC/VAH/VAL jump; the predicted profile anticipates where the levels migrate next. Used by: the impulse trend gate, the impulse anti-chase distance (measured against `pMVah/pMVal` instead of the stale current edge), and the POC-stability gate. `impulsePredictBars = 0` disables prediction (predicted = current).

### Node-state engine (synthetic order flow)
Per-bin `nodeBuy/nodeSell/nodeTouch` arrays over the master price range (40 bins), updated on confirmed bars only:
- All bins decay by `nodeDecay = 0.94` per bar (~11-bar half-life).
- A bin is "touched" when `|close − binPx| <= max(0.05 × ATR, 2 ticks)` or the bar range spans it. Touched bins accumulate `buyProxy = volume × max((close−open)/range, 0)` and the mirror `sellProxy`, split evenly across the bins the bar spans.
- Node state: `net = (buy − sell) / max(buy + sell, 1)`. **DEAD/absorbed** when `touch >= 4.0` and `|net| <= 0.15`; otherwise BUY if `net > 0.15`, SELL if `net < −0.15`, flat in between. This is a synthetic proxy — no real bid/ask data.

### Multi-TF near-price net tick volume
`f_tfNetNear(50, 1.5)`: over the last 50 bars of a TF, sum `volume × body-direction fraction` into buy/sell totals for bars whose `hlc3` is within ±1.5 × ATR of current price; net = (buy − sell)/total ∈ [−1, +1].
- **M3 (chart TF):** `netM3c` is computed differently — from the *node arrays* (`f_near_net_weighted`), optionally weighting each bin by its VP tier when `useWeightedNet` is ON (input default **true**; tooltip claims OFF — mismatch): HVN (>66% of near-window max) ×1.5, MVN ×1.0, LVN (<33%) ×0.5.
- **M1:** `request.security("1", …)` bundle returning the completed-bar net `v[1]` plus M1-native consecutive-flush counters (for the M1-flush exit). `lookahead_off`.
- **M5 / M15:** `request.security` of the completed-bar net `v[1]`, `lookahead_off`. M15 exists only for the HTF bias gate.

### Fresh-cross arming
Six crosses are tracked on confirmed bars: close × master VAH up (breakout long), VAL down (breakout short), POC up/down (reversion v1 long/short), VAL up / VAH down (reversion v2 long/short). A cross arms its entry while `(bar_index − crossIdx) <= freshBars` (`>` is stale). The index is set to `na` (consumed) when the matching entry fires — one cross, at most one trade.

### Opt-in gates (all default OFF; OFF = exact baseline)
- **Regime gate (`enableRegimeGate`):** `slopeNorm = (mPoc − mPoc[impulseTrendSlopeBars]) / ATR` (10-bar master-POC drift in ATRs, signed). When ON: breakout long requires `slopeNorm >= +regimeTauHigh` (0.5), breakout short `<= −0.5`; all reversion variants require `|slopeNorm| <= regimeTauLow` (0.25). The band between 0.25 and 0.5 trades nothing. Thresholds are placeholders pending `dbgSlopeBins` calibration.
- **Master-POC stability gate (`brkRequirePocStable` / `revRequirePocStable`, per strategy):** POC is "stable" when `|pMPoc − mPoc| <= pocStableMaxAtr (0.2) × ATR`. Fail-open: `na` prediction/POC/ATR ⇒ treated as stable; auto-no-op when `impulsePredictBars = 0`. When the toggle is ON, an unstable POC skips the setup (value is migrating; the referenced level is about to move).
- **Overhead-supply veto (`brkOverheadVeto`, breakout only):** scans the master-VP node band ahead of price — long: `[close, close + brkProjAtr (1.5) × ATR]`, short mirrored below. Veto trips when the band's total node volume `ta.percentrank(…, brkOverheadLook=200) >= brkOverheadHvnPct (70)` (a major node, not a vacuum) **and** the band net opposes the trade: `bandNet <= −brkOverheadNetMax (0.5)` for a long, `>= +0.5` for a short. Raw condition is computed even when OFF so debug markers / the selectivity table can calibrate it.
- **HTF net-volume bias gate (`enableHtfBias`, breakout only):** HTF bias is bullish when **both** `netM5c >= +htfBiasMin (0.5)` and `netM15c >= +0.5`; bearish mirrored; else balanced. Lenient (default): a breakout is blocked only when the bias actively *opposes* it (balanced allowed). Strict (`htfRequireAlign`): the bias must actively *agree* (balanced blocked too). Impulse and reversion are unaffected.

## 3. Entry Logic

All signals evaluate on the confirmed bar (`close` = the spec's "prev close"); fills occur next bar open. Common preconditions for every path: `allowTrading`, valid TF, in an enabled session (or Trade Anytime), `ATR% >= minAtrPct`, session trade count < 50, not in a news window, daily-DD breaker not hit, position-direction compatible (`strategy.position_size >= 0` for longs, `<= 0` for shorts — no hedging), and `openLongs/openShorts < 3`. ATR = `ta.atr(14)` on the chart TF; `ATR% = atr/close × 100`.

**Per-bar arbitration (one entry per direction per bar), `kind` 1=BRK 2=REV1 3=REV2 4=IMP:**
impulse first; else (only when `ATR% <= maxAtrPct`) breakout; else the higher-RR of the two armed reversion variants (v1 wins ties: `rrRevL1 >= rrRevL2`).

### Breakout — kind 1 (`enableBreakout`, default ON)
Long (short is the exact mirror on master VAL / local VAL):
1. Fresh master-VAH upcross: `bar_index − xiUpVah <= brkFreshBars` (7).
2. Local-profile tolerance: `vah <= mVah + brkLocalTolAtr (0.1) × ATR` — the local VAH must not have built too far above the master VAH.
3. Entry buffer: `close >= mVah + brkEntryBufAtr (1.0) × ATR`.
4. Anti-chase: `close <= mVah + brkMaxDistAtr (1.8) × ATR` (skipped if the input is 0).
5. Confirming net: `netM3c >= brkNetMinM3 (0.80)` **or** (`netConfirmM1orM3` ON and `netM1c >= brkNetMin (0.80)`) **or** (`netConfirmM5` ON — default ON — and `netM5c >= brkNetMin`). Defaults: M3-or-M5 confirm.
6. Opposing-net veto: `netM3c > −brkOppMax (0.80)` and `netM5c > −0.80` (M5 leg skipped when `na`).
7. `riskBrkL > 0`, plus the opt-in gates: regime (`gateBrkL`), HTF bias (`gateHtfL`), not overhead-vetoed, POC stable (when toggled).

SL/TP at signal time: `SL = min(mVah − brkSlBufAtr (0.25) × ATR, close − brkSlAtrMult (2.0) × ATR)`; RR is adaptive — `brkRrNear` (2.0) if a same-direction entry occurred within the last `brkRrLookbackBars` (25, hidden), else `brkRrFar` (3.0); `TP2 = close + RR × risk`.

### Mean Reversion — kinds 2 and 3 (`enableReversion`, default OFF)
Four variants off fresh master POC/VAL/VAH crosses, all rotations toward the next level inside the value area. Shared gates: confirming net `>= revNetMin (0.80)` on M3 (or M1/M5 per the confirm toggles), opposing net `< revOppMax (0.80)` on M3 & M5, computed RR `>= revMinRR (1.5)`, regime gate (`gateRev`, range only when ON), POC-stability (when toggled). Freshness window `revFreshBars` = 6 bars. Hidden spec constants: `revAnchorOffAtr = 0.06`, `revPocSlOffAtr = 0.1`.

- **Variant 1 — POC cross, VAH/VAL-family TP.** Long: fresh POC upcross; `close >= max(mPoc + 0.06 × ATR, poc) + revEntryDistAtr (1.0) × ATR`; anti-chase `close <= mPoc + revMaxDistAtr (2.0) × ATR` (0 = off). `SL = min(close − revSlAtrMult (2.0) × ATR, max(mPoc + 0.1 × ATR, poc) − revSlBufAtr (0.2) × ATR)`. `TP2 = (mVah > vah + ATR) ? mVah : max(mVah, vah)`; requires `TP2 > close`. Short mirrors on the POC downcross toward VAL.
- **Variant 2 — VAL/VAH cross, POC-family TP.** Long: fresh VAL upcross; `close >= max(mVal + 0.06 × ATR, val) + 1.0 × ATR`; anti-chase vs `mVal`. `SL = min(close − 2.0 × ATR, max(mVal + 0.06 × ATR, val) − 0.2 × ATR)`. `TP2 = (mPoc > poc + ATR) ? mPoc : max(mPoc, poc)`. Short mirrors on the VAH downcross.

### Impulse Thrust — kind 4 (`enableImpulse`, default ON; bypasses the volatility ceiling)
Active **only** when `maxAtrPct > 0` and `ATR% > maxAtrPct` — exactly the band the other paths refuse, so the two regimes never compete on the same bar. Long conditions (short mirrored on master VAL):
1. Thrust candle: `close > open` and `(high − low) >= impulseCandleAtr (1.7) × ATR` — a single decisive initiative bar.
2. Entry buffer: `close >= mVah + impulseEntryBufAtr (0.4) × ATR`.
3. Anti-chase vs the **predicted** edge: `close <= pMVah + impulseMaxDistAtr (2.5) × ATR` (falls back to `mVah` when prediction is `na`; 0 = off).
4. Trend gate: master-POC slope rising — `mPoc > mPoc[impulseTrendSlopeBars (10)]` — **and** predicted POC confirms: `pMPoc >= mPoc` (mirror `<=` for shorts). Slope-based on purpose so one bounce candle can't flip the trend read.
5. M1 flow: `netM1c >= impulseNetMin (0.95)` (long) / `<= −0.95` (short) — near-total one-sided M1 net.
6. `risk > 0`.

No fresh-cross requirement, no M3/M5 confirming or opposing net gates, and none of the opt-in gates apply (regime/HTF/overhead/POC-stability are not in `sigImp*`). `SL = min(mVah − 0.25 × ATR, close − 2.0 × ATR)` (reuses the breakout SL constants); `TP2 = close + impulseRr (3.0) × risk`.

## 4. Exit & Trade Management

Each entry gets its own registry slot and bracket (`strategy.exit` per entry id) — stacked positions are managed independently.

- **Bracket:** fixed SL + fixed TP2 (RR-based for breakout/impulse, level-based for reversion) placed at entry.
- **TP1 partial (`useTp1Partial`, default ON), per-strategy split:**
  - Breakout & Impulse (kinds 1/4): TP1 at `tp1RrBrk (1.05) × risk`, closing `tp1CloseBrk (10)%` of size.
  - Mean-Reversion (kinds 2/3): TP1 at `tp1RrRev (1.0) × risk`, closing `tp1CloseRev (15)%`.
  - OFF = single clean SL+TP2 bracket; BE and runner-trail then never act.
- **Break-even after TP1 (`enableBeAfterTp1`, default ON):** once the bar's high/low tags TP1, the runner's stop is amended to `entry ± beBufAtr (0.05) × ATR` *in profit*. Monotonic — the stop only ever tightens.
- **Chandelier runner trail:** present in code but **hard-disabled** (`trailRunner = false` as a const; `runnerRr = 10`, `trailAtrMult = 3.6`). When enabled it would override TP2 with a far backstop and ratchet the stop to `peak ∓ 3.6 × ATR`.
- **Early exits (all `strategy.close_all` — they flatten every open position, not just one slot):**
  - **Legacy net-flush exit:** hidden const `enableEarlyExit = false`. Would close longs when (M1 AND M3) or (M3 AND M5) net `<= −0.80`.
  - **M1-flush exit (`enableM1FlushExit`, default OFF):** closes the position when the M1 near-price net has opposed it by `>= m1FlushNetMin (0.80)` for `m1FlushBars (2)` consecutive *M1-native* completed bars, and — with `m1FlushUnderwater` ON (default) — only while `strategy.openprofit < 0`. Built for the "M1 flips fully against the trade ~4 bars before SL while M3 lags" loss pattern.
  - **Overhead-supply exit (`enableOverheadExit`, default OFF):** closes when the path ahead of the open position holds a major opposing node (same raw read and thresholds as the breakout overhead veto), underwater-gated by default (`overheadExitUnderwater = true`).
  - **Session-end / news force-close (`forceCloseSessNews`, default OFF):** flattens when the session ends or a news window opens.
- **WON/LOST labeling** (display only): a trade counts as won if TP1 was tagged (when partials are on), else by close-vs-entry at removal time.

## 5. Risk Management

- **Position sizing:** risk-based, `qty = riskBudgetUSD / (stopDistance × pointvalue)`. Risk budget per `riskUnit`: `% Account Balance` (default) = `riskPerTradeAccPercent (1.6)%` of (initial capital + closed net profit); `USD` = `riskPerTradeUSD (180)`; or min/max of both. If sizing is invalid (`qty = na`) the declaration's fixed default qty (20) silently applies.
- **Daily drawdown breaker (predictive):** `dayStartEquity` snapshots at each UTC day change (`varip`). Blocked when `(dayStartEquity − equity + riskBudgetUSD) / dayStartEquity × 100 >= maxDailyDDPct (5.0)` — i.e. a new entry is refused if its worst-case loss *added to* the day's drop so far would reach the cap. 0 = disabled. Red background when tripped.
- **Concurrency caps:** max 3 concurrent positions per direction (hidden const); no hedging (long entries only when net-flat-or-long, mirror for shorts); hidden loose cap of 50 trades per session/UTC-day.
- **Not present in this Pine** (unlike the KK-MasterVP MQL EA's RiskManager): no peak-DD trailing lockout, no loss-streak cooldown. The EA port adds those server-side; do not assume Pine backtests include them.

## 6. Filters & Sessions

- **Sessions (UTC, configured as `input.session`):** Asia `0000-0600`, London `0700-1100`, NY `1230-1630`. Per-session enable toggles all default OFF, but **`tradeAnytime` defaults ON**, which ignores all session windows; the trade counter then resets per UTC day instead of per session. Hour-blocking string exists but is hardcoded empty.
- **Volatility floor:** new entries require `ATR% >= minAtrPct (0.04)` (0 = no floor). Applies to *all* paths including impulse (it lives in `safetyOk`).
- **Volatility ceiling:** kinds 1–3 require `ATR% <= maxAtrPct (0.2)`; the impulse path requires `ATR% > maxAtrPct` instead — the ceiling is a per-kind regime split, not a global veto. With `maxAtrPct = 0` the ceiling is off and the impulse path can never fire.
- **News avoidance (`avoidNews`, default OFF):** `request.economic()` for US NONFARM, CPI, IR (rate), GDP, JC (jobless claims). Release minutes-of-day are learned at runtime into 5 persistent slots (deduped ±2 min); new entries are blocked `newsMinsBefore (15)` to `newsMinsAfter (15)` minutes around each slot — note the slots repeat *daily* once learned and are never cleared. Open positions keep their brackets unless `forceCloseSessNews` is ON.
- **No spread filter** in the Pine (costs are modeled via commission 0.50/order + 8-tick slippage); the MT5 side must handle real spread.
- **Do-not-trade conditions (summary):** invalid TF, out-of-session (when sessions active), ATR% below floor, news window, daily-DD breaker, direction cap reached, opposite net position open.

## 7. Key Parameters

| Parameter | Default | Mechanism / units |
|---|---|---|
| `maxDailyDDPct` | 5.0 | Predictive daily-DD cap, % of UTC-day starting equity; entry refused if day drop + trade risk budget would reach it. 0 = off. |
| `riskUnit` / `riskPerTradeAccPercent` / `riskPerTradeUSD` | % Acc Bal / 1.6 / 180 | Per-trade risk budget definition; sizing = budget / (stop distance × point value). |
| `minAtrPct` / `maxAtrPct` | 0.04 / 0.2 | Volatility floor/ceiling, ATR as % of price. Ceiling splits regimes: kinds 1–3 below, impulse above. |
| `useTp1Partial` | true | TP1 partial scale-out toggle; BE/trail only act when ON. |
| `tp1RrBrk` / `tp1CloseBrk` | 1.05 / 10 | Breakout+Impulse TP1: distance in R / % of size closed. |
| `tp1RrRev` / `tp1CloseRev` | 1.0 / 15 | Mean-reversion TP1: distance in R / % closed. |
| `enableBeAfterTp1` / `beBufAtr` | true / 0.05 | After TP1, runner stop to entry + 0.05 × ATR in profit (monotonic). |
| `vpLookback` / `vpBins` | 50 / 40 | Local VP window bars / price bins; master window = 50 × 3 = 150 bars (hidden mult). |
| `netConfirmM1orM3` / `netConfirmM5` | false / true | Which TFs may satisfy the confirming-net gate (M3 always counted; M5 default-allowed). |
| `useWeightedNet` | true | Weight chart-TF near-net bins by VP tier (HVN 1.5 / MVN 1.0 / LVN 0.5). |
| `enableBreakout` | true | Breakout path master switch. |
| `brkFreshBars` | 7 | Bars a master VAH/VAL cross stays armed; consumed on entry. |
| `brkEntryBufAtr` | 1.0 | Close must be ≥ this × ATR beyond the master edge. |
| `brkMaxDistAtr` | 1.8 | Anti-chase: skip if close > this × ATR beyond the edge. 0 = off. |
| `brkNetMinM3` / `brkNetMin` | 0.80 / 0.80 | Confirming-net floors (M3 leg / M1+M5 legs). |
| `brkOppMax` | 0.80 | Opposing-net veto threshold on M3 & M5. |
| `brkSlBufAtr` / `brkSlAtrMult` | 0.25 / 2.0 | Breakout SL = min(edge − buf × ATR, close − mult × ATR). Shared by impulse. |
| `brkRrFar` / `brkRrNear` | 3.0 / 2.0 | Breakout RR: far when no same-dir entry in 25 bars, near otherwise. |
| `enableImpulse` | true | Impulse-thrust path (fires only above the vol ceiling). |
| `impulseCandleAtr` | 1.7 | Min trigger-bar range in ATR. |
| `impulseEntryBufAtr` | 0.4 | Min close beyond master edge, in ATR. |
| `impulseNetMin` | 0.95 | Min one-sided M1 near-price net. |
| `impulseMaxDistAtr` | 2.5 | Anti-chase vs the *predicted* edge, in ATR. 0 = off. |
| `impulseRr` | 3.0 | Impulse TP = close ± RR × stop distance. |
| `impulseTrendSlopeBars` | 10 | Master-POC slope lookback for the impulse trend gate and `slopeNorm`. |
| `impulsePredictBars` | 10 | Bars aged out of the master window to build the predicted POC/VAH/VAL. 0 = no prediction (also no-ops the POC-stability gate). |
| `enableReversion` | false | Mean-reversion path master switch. |
| `revFreshBars` / `revEntryDistAtr` / `revMaxDistAtr` | 6 / 1.0 / 2.0 | Reversion cross freshness / entry distance / anti-chase, ATR units. |
| `revNetMin` / `revOppMax` / `revMinRR` | 0.80 / 0.80 / 1.5 | Reversion net gates and minimum computed RR. |
| `enableRegimeGate` / `regimeTauHigh` / `regimeTauLow` | false / 0.5 / 0.25 | Trend/range router on master-POC slope (ATR over 10 bars); brk needs trend, rev needs range; placeholders pending calibration. |
| `brkRequirePocStable` / `revRequirePocStable` / `pocStableMaxAtr` | false / false / 0.2 | POC-stability gate: stable when \|pMPoc − mPoc\| ≤ 0.2 × ATR; fail-open on na. |
| `brkOverheadVeto` / `brkProjAtr` / `brkOverheadLook` / `brkOverheadHvnPct` / `brkOverheadNetMax` | false / 1.5 / 200 / 70 / 0.5 | Block breakouts into a major (≥70th-pct volume over 200 bars) opposing-net (≥0.5) node band within 1.5 × ATR ahead. |
| `enableHtfBias` / `htfBiasMin` / `htfRequireAlign` | false / 0.5 / false | M5+M15 net bias gate, breakout only; lenient blocks opposing bias, strict requires agreement. |
| `enableM1FlushExit` / `m1FlushNetMin` / `m1FlushBars` / `m1FlushUnderwater` | false / 0.80 / 2 / true | M1-only opposing-flush early exit, underwater-gated. |
| `enableOverheadExit` / `overheadExitUnderwater` | false / true | Early exit on a major opposing node ahead of the open position. |
| `tradeAnytime` / `asia` / `ldn` / `ny` | true / 0000-0600 / 0700-1100 / 1230-1630 | Session control, UTC. Trade-anytime ON by default. |
| `avoidNews` / `newsMinsBefore` / `newsMinsAfter` | false / 15 / 15 | Entry pause around high-impact USD releases. |

Hidden consts that matter: `maxConcurrentPerDir = 3`, `brkRrLookbackBars = 25`, `tfNetLook = 50`, `netWinAtr = 1.5`, `nodeDecay = 0.94`, `nodeNeutralBand = 0.15`, `nodeSaturation = 4.0`, `atrLen = 14`, `revAnchorOffAtr = 0.06`, `revPocSlOffAtr = 0.1`, `trailRunner = false`.

## 8. Known Limitations & Notes

- **Synthetic order flow.** "Buy/sell pressure" is `volume × candle-body fraction` — a proxy from tick volume and bar shape, not real bid/ask delta. Node states, net tick volume and the overhead-supply read all inherit this approximation, and tick volume differs materially between TradingView and MT5 feeds (a documented divergence source for the base strategy).
- **Tooltip/code mismatch:** `useWeightedNet` tooltip says "default OFF" but the input default is `true`. Trust the code.
- **Regime-gate thresholds are placeholders** (0.5/0.25) explicitly pending `dbgSlopeBins` calibration; the overhead veto's `brkOverheadNetMax` is flagged as the primary sweep variable. Both ship OFF.
- **Repaint posture:** decisions are confirmed-bar only, `request.security` uses `[1]` + `lookahead_off`, cross indices recorded on confirmed bars — the trading path is repaint-safe by construction. The intrabar (live) components in `f_node_state` and the histogram are display-only. `varip dayStartEquity` makes live equity snapshots differ from a cold recompile.
- **News filter is a runtime-learned approximation:** release minutes fill 5 persistent slots and then block the same minutes *every* day, forever; a 6th distinct release time is ignored. The MQL5 side uses a CSV calendar instead — behavior will differ.
- **`close_all` early exits flatten the entire stack,** not the individual losing slot — with 3 stacked positions an M1 flush on one closes all of them.
- **TP1/BE detection is bar-high/low based** in the registry (touch counts as fill), while actual fills go through `strategy.exit` limits with bar magnifier — the BE amendment can lag the true fill by intrabar sequence.
- **Fallback sizing trap:** if risk sizing yields `na`, `strategy.entry` falls back to the declared fixed qty of 20 — silent, unsized exposure.
- **Impulse path skips all the opt-in gates** (regime/HTF/overhead/POC-stability) and the M3/M5 net gates by design — it is the least-filtered path and trades in the most hostile (above-ceiling) volatility band. Slippage modeling (8 ticks) is optimistic for that regime on BTCUSD illiquid hours.
- **Status:** promising backtests only (best on BTCUSD); has NOT cleared the deploy gate (PF ≥ 1.25 TRAIN / ≥ 1.15 OOS at realistic cost) and is not validated for production. MQL5 EA port in progress at `MQL5/Experts/KK-MasterVP-Monster/` — v1 is single-position, so Pine's stacking (up to 3/direction) will not carry over initially.
