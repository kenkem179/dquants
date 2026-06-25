# KK‑MasterVP — Expert Advisor User Guide

A practical, plain‑language guide to running the&nbsp;KK‑MasterVP&nbsp;Expert Advisor on MetaTrader 5. Built and tested on major instruments such as XAUUSD (Gold) and BTCUSD, on the M3 and M5 timeframes. In our own testing, M5 has been the most consistent timeframe to run it on.

**Important — please read first.** This document is educational and informational only. It is not financial advice, not an investment recommendation, and not a solicitation to buy or sell anything. KK‑MasterVP is an automated trading program: when you enable it, it can open, modify, and close real positions on your account according to its rules. That makes it your responsibility to understand what it does, to test it yourself, and to size it sensibly. Every default value in this product was chosen from historical backtests. **A backtest is a study of the past. It does not predict, promise, or guarantee future results.** Markets change, brokers differ, and live conditions (spread, slippage, latency, gaps) are never identical to a test. Trading leveraged products carries a high risk of loss, including the loss of your entire capital — you may lose more than you deposit. You alone are responsible for your decisions and their consequences. If in doubt, test on a demo account first and consult an independent, appropriately licensed professional.

## 1. What KK‑MasterVP is (in one minute)

KK‑MasterVP is a volume‑profile breakout strategy. It continuously builds a picture of *where price has spent its time and activity* — the busy shelves and the quiet edges — and looks for moments when price breaks decisively out of that structure with the trend behind it. When its conditions line up, it opens a position, manages the stop, takes partial profit, and trails the remainder.

In one breath, the cycle is:

- **Map the structure.** Build a "master" volume profile over a long window and a "local" profile over a recent window. These give a Point of Control (the busiest price) and a value area (the band that holds most activity).
- **Check the regime.** Confirm the broader trend with moving averages and a trend‑strength reading (ADX) so it isn't fighting a flat or hostile market.
- **Wait for the break.** When price pushes beyond the value‑area edge by a meaningful distance, and the filters agree, it enters.
- **Manage the trade.** Place a stop a measured distance away, bank a partial at the first target, move the stop toward break‑even, then trail the rest to let a winner run.

It also ships with several **optional** entry styles (reversion, impulse‑thrust, extreme‑reversion) that are **switched off by default**. The product runs as a clean breakout system out of the box; the extras are there for users who want to experiment after their own testing.

**What it is not:** it is not a guaranteed income system, not a "set and forget" money printer, and not a substitute for your own risk judgement. It is a rule‑based tool that does exactly what its settings tell it to — no more, no less.

## 2. Before you start

- **The defaults are a tested starting point, not a recommendation.** Out of the box, KK‑MasterVP is configured to the values that performed best in our historical XAUUSD M5 study. They are compiled in, so the EA runs tuned immediately. That is where our testing landed — it is **not** a claim about what will happen next on your broker or in the future.
- **M5 has been our most consistent timeframe.** It works on M3 as well, and the same logic generalizes to other liquid instruments, but M5 is where the behaviour has been steadiest in testing. Treat anything outside the tested combinations as something *you* need to validate.
- **It trades a real account.** Always run it on a **demo account first**, for long enough to see how it behaves through different market conditions, before you consider any live capital.
- **Costs matter enormously for a strategy like this.** Spread, commission, and slippage come straight out of every trade. A broker with wide or unstable spreads on Gold or Bitcoin can turn a tested edge into a loss. Test on the account you actually intend to run.

## 3. Installing and attaching

1. Copy `KK-MasterVP.ex5` into your MetaTrader 5 `MQL5/Experts/` folder (or a subfolder you keep EAs in). If you plan to use the live notifications or the account guardian (§5), also copy the small `TestDeployOps.ex5` validator so you can confirm those work before deploying.
2. Restart MetaTrader 5, or right‑click the Navigator → Expert Advisors list and choose **Refresh**.
3. Open a chart for the instrument and timeframe you want — for the intended setup, **XAUUSD, M5**.
4. Drag **KK‑MasterVP** from the Navigator onto the chart, or double‑click it.
5. In the settings window, **Common** tab, tick **Allow Algo Trading**. In the **Inputs** tab you can leave the defaults as they are, or click **Load** and pick one of the shipped `.set` presets (see §5).
6. Make sure the global **Algo Trading** button in the MetaTrader toolbar is enabled. A small smiling face in the top‑right of the chart means the EA is live.

To test before going live, open **View → Strategy Tester**, pick the EA, the symbol, the timeframe, your date range, and **Every tick based on real ticks** for the most realistic modelling, then run it. **Backtest results are historical and do not guarantee future performance** — they are for understanding behaviour, not for predicting profit.

## 4. The shipped presets

Several ready‑made `.set` files ship alongside the EA so you don't have to type values by hand. In the Inputs tab click **Load** and pick the one that matches your chart:

- **`KK-MasterVP-XAUUSD-M5.set`** — the primary, most‑tested configuration (Gold, M5).
- **`KK-MasterVP-XAUUSD-M3-BASE.set`** — the Gold M3 configuration.
- **`KK-MasterVP-BTCUSD-M5.set`** — a Bitcoin M5 configuration.
- Additional A/B presets (different trail and partial‑profit choices) are included for users who want to compare variations themselves.

Each preset simply fills in the inputs below. They reflect where our testing landed for that instrument and timeframe — nothing more. Load one, read the disclaimer again, and demo‑test before trusting it.

## 5. Settings, in plain language

The inputs are grouped exactly as they appear in the settings window. You do **not** need to change most of them; the defaults are the tested configuration. The notes below explain what each one does so you can make informed choices, **not** so that any value is recommended over another. Two conventions used throughout:

- **R** ("risk units") means a multiple of the distance from entry to the stop. A target at 1.8R sits 1.8× the stop distance away from entry.
- **ATR** is a standard measure of how much price typically moves. Many distances are expressed as a multiple of ATR so the strategy adapts sensibly whether the market is quiet or busy.

### Quick reference — example values for the settings you'll actually touch

These are the inputs most people adjust, with their shipped **default** and a few **example values** to show what changing them does. The examples are illustrative to explain the meaning of each setting — **they are not recommendations**, and the defaults are simply where our XAUUSD M5 testing landed. Everything below this table is a deeper explanation of the same settings, group by group.

**Core trading & risk**

| Setting (input) | Default | Example values — what they mean |
|---|---|---|
| Risk basis (`InpRiskUnit`) | `0` (% of balance) | `0` size by % of balance · `1` fixed cash amount · `2`/`3` broker min/max lot |
| Risk per trade % (`InpRiskAccPct`) | `1.0` | `0.5` = risk 0.5% of balance per trade (calmer) · `1.0` = the tested level · `2.0` = roughly double the swings |
| Fixed risk cash (`InpRiskUsd`) | `180` | only used when Risk basis = `1`; e.g. `100` risks $100 per trade |
| Max lot (`InpMaxLot`) | `0` (broker max) | `0.50` caps every position at 0.5 lots |
| First target (`InpTp1R`) | `0.8` | secure/partial at 0.8× the stop distance · `1.0` = one full R out |
| Bank at first target (`InpTp1ClosePct`) | `0` (keep full runner) | `25` = close 25% at the first target and trail the rest · `0` lets the whole position run |
| Break-even after TP1 (`InpBeAfterTp1`) | `true` | `true` moves the stop to ~entry after TP1 · `false` keeps the original stop |
| Break-even buffer (`InpBeBufAtr`) | `0.02` | small cushion past entry, in ATR · `0.10` = a little more breathing room |
| Runner cap (`InpRunnerRr`) | `4.0` | far take-profit at 4× risk; in practice the trail exits first |
| Trail distance (`InpTrailAtrMult`) | `2.75` | `2.0` = tighter trail (exits sooner, protects more) · `3.5` = looser (more room to run) |
| Daily drawdown pause (`InpMaxDailyDDPct`) | `10` | `4.4` to respect a typical prop daily-loss rule · `0` = off |
| Daily cooldown hrs (`InpDailyDDCooldownHrs`) | `12` | hours paused after a daily-loss hit |
| Max total drawdown halt (`InpMaxPeakDDPct`) | `0` (off) | `9` halts trading at 9% account drawdown |
| Max trades/session (`InpMaxTradesPerSession`) | `4` | `2` = at most two new trades per session |
| Max spread (`InpMaxSpreadPips`) | `0` (off) | `30` = skip entries when the spread is wider than 30 points (worth setting on Gold/BTC) |
| Blocked hours, UTC (`InpBlockedHoursStr`) | `4,16,17` | `"9-11"` skips 09:00–11:00 UTC · empty = trade every hour |
| Magic number (`InpMVPMagic`) | `5252510` | give each instance a unique number if you run several |

**Account guardian, logging & notifications** (live only; all off by default)

| Setting (input) | Default | Example values — what they mean |
|---|---|---|
| Enable guardian (`InpGuardEnable`) | `false` | `true` turns on the cross-EA account safety layer |
| Daily loss limit % (`InpGuardDailyLossPct`) | `4.0` | the equity drop that stops trading; e.g. `5.0` for a 5%-daily firm |
| Max drawdown limit % (`InpGuardOverallDDPct`) | `8.0` | e.g. `10.0` for a 10%-max-drawdown firm |
| Safety buffer % (`InpGuardBufferPct`) | `0.5` | act 0.5% *before* each line · `1.0` = stop even earlier |
| Max-DD anchor (`InpGuardDDAnchor`) | `0` (trailing peak) | `0` measure drawdown from the equity high · `1` from the starting balance |
| On breach (`InpGuardFlatten`) | `true` (close all) | `true` closes open trades at the line · `false` only blocks new entries |
| Log trades to CSV (`InpLiveTradeCsv`) | `false` | `true` writes every closed trade to a CSV file in MQL5/Files |
| Notification channel (`InpNotifyChannel`) | `0` (none) | `2` Discord · `3` Telegram · `4` Email+Discord · `7` all three |
| Notification detail (`InpNotifyMode`) | `2` (Simplified) | `2` Simplified — symbol + action + size + magic + strategy + event, **no exact prices** · `1` Full adds the exact entry/stop/target for your own records |

### VP core — how the structure is measured

- **InpVpLookback** — the length, in bars, of the *local* (recent) volume‑profile window. Larger = a longer, slower picture of recent activity.
- **InpVpBins** — how many price buckets the profile is split into. More bins = finer resolution.
- **InpVaPct** — the percentage of activity that defines the "value area" band around the busiest price (e.g. 70%).
- **InpMasterMult** — the *master* profile window is the local window multiplied by this. With the tested local window of 108 and a multiplier of 4, the master profile covers 432 bars. The master window is the big‑picture structure the breakout is measured against.
- **InpAtrLen** — the lookback length for the ATR volatility measure.
- **InpAtrMt5Mode** — selects how ATR is averaged. Off uses the textbook (Wilder/RMA) method; on uses MetaTrader's built‑in smoothing. Off is the tested default.

### Node engine — fine structure inside the profile

These control an optional inner layer that reads buying/selling pressure at specific price nodes. They are tuned conservatively and most users never touch them.

- **InpNodeTouchAtr** — how close (in ATR) price must come to a node to count as a touch.
- **InpNodeDecay** — how quickly older node activity fades.
- **InpNodeNeutralBand** — the dead‑zone around neutral where a node is treated as balanced.
- **InpNodeSaturation** — a cap on how strong a single node's reading can get.
- **InpNodeGateEnabled** — master switch for using the node engine as an entry gate. Off by default (the clean, baseline behaviour).
- **InpUsePriorBarVP** — measures against the prior bar's profile instead of the forming one. Off by default.
- **InpBrkRequireFlow** — require supportive order‑flow at the node before a breakout. Off by default.
- **InpSfpFlowMin** — the minimum flow reading used when the flow filter is on.

### Regime — the trend filter

- **InpEmaFast / InpEmaSlow** — the fast and slow moving‑average lengths that define trend direction.
- **InpAdxLen** — the lookback for the ADX trend‑strength reading.
- **InpAdxTrendMin** — the minimum ADX value required to consider the market "trending enough" to trade.
- **InpDiSpreadMin** — the minimum separation between the directional components, another trend‑quality check.
- **InpEmaSepAtr** — how far apart (in ATR) the moving averages must be before the trend counts as clean.

### Breakout — the active entry path

This is the strategy's main engine and is **on** by default.

- **InpEnableBreakout** — master switch for the breakout entries. On by default.
- **InpBreakBufAtr** — how far beyond the value‑area edge (in ATR) price must close to trigger a breakout. Larger = more selective.
- **InpBreakMaxAtr** — an optional "anti‑chase" ceiling: skip breakouts that have already run more than this far. Effectively off by default (a very large number), because capping it hurt results on the tested feed.
- **InpRrBrk** — the reward‑to‑risk target multiple for breakout trades.
- **InpSlAtrBrk** — the stop‑loss distance for breakouts, in ATR.
- **InpBrkVetoSfp** — veto a breakout if it looks like a failed/exhaustion move. Off by default.

### Reversion (optional, off by default)

A mean‑reversion entry that fades moves back toward structure. Switched **off** by default; the defaults below apply only if you enable it after your own testing.

- **InpEnableReversion** — master switch (off).
- **InpRetestAtr** — how close price must retest a level (in ATR) to qualify.
- **InpBodyPctMin** — the minimum candle‑body fraction for a valid signal.
- **InpRrRev / InpSlAtrRev** — the reward‑to‑risk target and stop distance (ATR) for reversion trades.

### Impulse‑thrust (optional, off by default)

An entry for a single decisive thrust candle, designed to fire only in the high‑volatility band the normal strategy avoids. Switched **off** by default. It needs M1 history available. The defaults below come from a Bitcoin M3 study and apply only if you enable it.

- **InpEnableImpulse** — master switch (off).
- **InpImpulseCandleAtr** — the minimum thrust‑bar range (high−low) in ATR.
- **InpImpulseEntryBufAtr** — the minimum close beyond the master value‑area edge in ATR.
- **InpImpulseNetMin** — the minimum one‑sided near‑price order‑flow required.
- **InpImpulseMaxDistAtr** — an anti‑chase distance versus the predicted edge (0 = off).
- **InpImpulseRr** — the target reward‑to‑risk (inactive while the trailing stop is on).
- **InpImpulseTrendSlopeBars** — lookback for the master‑POC slope (trend direction of the structure).
- **InpImpulsePredictBars** — how many bars ahead the predicted profile is projected.
- **InpTfNetLook / InpTfNetWinAtr** — the window (bars and ATR half‑width) used to read near‑price flow.

### Extreme reversion / XRev (optional, off by default)

A failed‑breakout, liquidity‑sweep reversal: price pokes beyond an edge, sweeps a recent swing, then snaps back. Rare and switched **off** by default; these apply only if enabled.

- **InpEnableExtremeReversion** — master switch (off).
- **InpXRevHHLookback** — swing high/low lookback for the sweep level.
- **InpXRevFailLookback** — the window over which "failed acceptance" is counted.
- **InpXRevMinClosesBeyond / InpXRevMaxClosesBeyond** — the band of closes beyond the edge that defines trapped positioning (max 0 = off).
- **InpXRevMinAgeBars** — minimum bars since the opposite edge was crossed (an aged round‑trip).
- **InpXRevBigCandleAtr** — the rejection candle's minimum range in ATR.
- **InpXRevBodyPctMin** — the minimum body fraction of the rejection candle.
- **InpXRevWickFrac** — the sweep‑tail wick size relative to the body (the strongest filter for this setup).
- **InpXRevNetDeltaMin** — the minimum near‑price flow imbalance.
- **InpXRevUseNodeGate** — require absorption/selling at the edge.
- **InpXRevSlAtr** — the stop distance above the swept high, in ATR.
- **InpXRevRrMin** — the minimum reward‑to‑risk to accept the trade.
- **InpXRevTpMpoc** — take profit at the master POC (full bank) instead of the far edge.

### Reversion TP at master POC (optional, off by default)

- **InpRevTpMpoc** — when on, the base reversion trade targets the master POC for a full exit instead of a fixed reward multiple. Off by default.

### Exit — how trades are managed

- **InpTp1R** — the first partial‑profit target, in R.
- **InpTp1ClosePct** — the percentage of the position banked at the first target.
- **InpBeAfterTp1** — move the stop to break‑even after the first target is hit. On by default.
- **InpBeBufAtr** — a small buffer (in ATR) added to the break‑even stop.
- **InpTrailRunner** — trail the remaining position with an ATR "chandelier" trail. On by default (this is what lets a winner run).
- **InpRunnerRr** — a far reward cap on the runner; in practice the trail decides the exit.
- **InpTrailAtrMult** — the trailing distance, in ATR. Larger = looser trail (more room, later exit); smaller = tighter.
- **InpTrailBrk / InpTrailRev / InpTrailImp / InpTrailXRev** — per‑entry‑type trail overrides. `-1` inherits the global setting, `0` uses a fixed take‑profit (no trail), `1` forces a trail. All `-1` by default, so each path follows the global flag.

### Risk sizing — how big each trade is

This group decides position size and is the **most important thing for you to set deliberately**.

- **InpRiskUnit** — how risk is expressed: `0` = percent of account (default), `1` = fixed USD, `2` = minimum lot, `3` = maximum lot.
- **InpRiskAccPct** — the percent of balance risked per trade when in percent mode. The default reflects the lower‑drawdown plateau from testing; choose a figure you are genuinely comfortable losing on a single trade.
- **InpRiskUsd** — the fixed dollar risk per trade, used only when the unit is not percent.
- **InpMaxLot** — a hard cap on lot size (0 = use the broker's maximum).
- **InpDeviationPoints** — the maximum price slippage allowed when entering, in points.
- **InpSkipIfMinLotOverRisk** — skip a trade if the broker's minimum lot would exceed your risk budget, rather than over‑risking. Off by default.

### Risk‑management limiters — circuit breakers

- **InpMaxDailyDDPct** — a daily drawdown cap; new entries pause if the day's loss reaches this percent. The default sits on a tested plateau.
- **InpDailyDDCooldownHrs** — how long to stay paused after a daily‑drawdown breach.
- **InpMaxPeakDDPct** — an overall peak‑drawdown halt. Off by default (it tended to curve‑fit the test peak).
- **InpSoftBlockDDPct / InpSoftBlockLotMult** — an optional softer response that shrinks size as drawdown grows. Off by default.
- **InpLossStreakCount / InpLossStreakCooldownHrs** — pause after a run of losing trades. Off by default (it hurt results in testing).

### Safety / volatility — condition filters

- **InpMinAtrPct / InpMaxAtrPct** — only trade when ATR (as a percent of price) is inside a band. Both off by default.
- **InpMinAtrTicks** — a floor on absolute volatility (ATR in ticks) below which it won't trade.
- **InpMaxTradesPerSession** — a cap on how many trades may be opened per session.
- **InpMaxSpreadPips** — refuse to enter when the spread is wider than this (0 = off). Worth setting on instruments with variable spreads.
- **InpMaxSpreadTp1Frac** — an optional check that the spread isn't eating too much of the first target. Off by default.

### Quality gates — extra confirmation filters

These add confirmation the original study did not have. They are off by default; turning them on makes entries more selective.

- **InpUseMtfAgree** — require a higher‑timeframe moving‑average agreement before entering. Off by default.
- **InpMtfHardVeto** — whether that agreement is a hard veto (relevant only when the gate above is on).
- **InpUseMomVeto** — veto entries that disagree with an RSI momentum reading. Off by default.
- **InpRsiMidline / InpRsiLen** — the midline and length used by the momentum filter.

### Sessions — when it is allowed to trade

- **InpAsiaSess / InpLdnSess / InpNySess** — the Asia, London, and New York session windows, expressed in UTC.
- **InpBlockedHoursStr** — specific low‑liquidity hours to skip, e.g. `"8,16"` or `"9-11"`, expressed in UTC.
- **InpForceCloseSessNews** — force‑close open trades when a session ends. Off by default.

### News avoidance — a live‑safety overlay

- **InpAvoidNews** — when on, block new entries around high‑impact news releases. Off by default.
- **InpNewsMinsBefore / InpNewsMinsAfter** — how many minutes before and after each event to stay out.
- **InpUseEmbeddedNews** — fall back to the calendar compiled into the EA if no custom news file is supplied.

### Misc and parity

- **InpMVPMagic** — the magic number that tags this EA's trades. Give each running instance a unique value if you run more than one.
- **InpExportParity** — a developer/testing switch that writes a trade CSV in the Strategy Tester for validation against the research engine. Leave **off** for live trading.

### Account Risk Guardian (live only, off by default)

A separate safety layer for funded / prop‑firm accounts. It watches your **account equity** against a daily‑loss line and an overall‑drawdown line and steps in *before* either is breached, so an automated strategy can't quietly trade you past a firm's limit. It is built to be **shared across every KK EA on the same terminal** — if you also run KK‑KenKem on the account, they read one common set of day‑start and peak figures (kept in terminal global variables, keyed by your login), so they agree on where the lines are instead of each guessing. It measures the trading day on your **broker's server time**, which is deliberately independent of the strategy's UTC session windows. It has **no effect in the Strategy Tester** (there is no real account to protect) and is **off by default** — turning it on never changes how the strategy itself trades, only when it is allowed to.

- **InpGuardEnable** — master switch for the guardian. Off by default.
- **InpGuardDailyLossPct** — the daily‑loss limit, as a percent of the day's starting equity (e.g. 4%).
- **InpGuardOverallDDPct** — the maximum overall drawdown limit, as a percent (e.g. 8%).
- **InpGuardBufferPct** — a safety margin: act this many percent *before* each line, so you stop short of the hard limit rather than on it.
- **InpGuardDDAnchor** — what the overall drawdown is measured from: `0` = the running equity peak (trailing, the stricter choice most firms use), `1` = the initial account balance (static).
- **InpGuardManualDayAnchor** — optionally pin the day's starting equity by hand (0 = work it out automatically, including reconstructing it from your closed‑trade history on a mid‑day restart).
- **InpGuardFlatten** — what to do when a line is reached: `true` closes all of this EA's open positions immediately; `false` simply blocks new entries and lets existing trades manage themselves out.

> Set the percentages to match **your** firm's actual rules, and always confirm the behaviour on a demo account first. The defaults (4% / 8%) are generic, conservative placeholders — not a claim about any specific firm.

### Live trade CSV log (live only, off by default)

- **InpLiveTradeCsv** — when on, every time a trade closes the EA appends one row to a plain CSV file in your terminal's `MQL5/Files` folder, named `KKTrades_MasterVP_<symbol>_<login>.csv`. Each row records the close time, volume, price, profit, swap, commission, net result, comment, and resulting balance — handy for your own record‑keeping or a spreadsheet. The row is written the instant the trade closes, so a crash never loses a completed trade. This is **separate** from `InpExportParity` (which is a tester‑only developer file) and is **skipped in the Strategy Tester**.

### Notifications (live only, off by default)

Optional trade alerts to Discord, Telegram, and/or Email. Off by default; **skipped in the Strategy Tester** so backtests never send anything.

- **InpNotifyChannel** — where alerts go: `0` none, `1` Email, `2` Discord, `3` Telegram, `4` Email + Discord, `5` Email + Telegram, `6` Discord + Telegram, `7` all three.
- **InpNotifyMode** — `2` Simplified (default) or `1` Full. Simplified is a privacy‑conscious format that omits exact prices (see below); Full adds the entry/stop/target for your own records.
- **InpDiscordWebhookUrl** — your Discord channel webhook URL (Discord → channel settings → Integrations → Webhooks).
- **InpTelegramBotToken** — your Telegram bot token (from @BotFather).
- **InpTelegramChatId** — the Telegram chat or group ID to send to (group IDs are negative numbers).

#### What the alerts look like

The EA notifies you across a trade's whole life: when it **opens**, when **TP1** is reached, when the stop moves to **break‑even**, when the stop **trails**, and when the trade **closes** (at a loss, at break‑even+, or at full take‑profit). Each message ends with the strategy that fired it — one of **MasterVP‑BreakOut**, **MasterVP‑MeanReversion**, **MasterVP‑Impulse**, or **MasterVP‑XReversion** — and the position's magic number (`#…`), so you can match it to the exact trade in your terminal.

**Simplified mode (the default)** — symbol, side, lot size, magic number, the event, and the strategy. It deliberately **does not include the entry price, stop‑loss, or take‑profit**:

```
XAUUSD BUY 0.10 lots #14111850 | Strategy: MasterVP-BreakOut      <- trade opened
XAUUSD BUY #14111850 | TP1 hit | Strategy: MasterVP-BreakOut       <- first target reached, partial banked
XAUUSD BUY #14111850 | SL to BE | Strategy: MasterVP-BreakOut      <- stop moved to ~entry (risk removed)
XAUUSD BUY #14111850 | SL trailed | Strategy: MasterVP-BreakOut    <- stop tightened behind price
XAUUSD BUY #14111850 | TP2 (full TP) | Strategy: MasterVP-BreakOut <- closed at the full target (win)
XAUUSD SELL #14111850 | SL+ (BE hit) | Strategy: MasterVP-MeanReversion <- closed at break-even+ (tiny win/scratch)
XAUUSD SELL #14111850 | SL hit (loss) | Strategy: MasterVP-MeanReversion <- closed at the stop (loss)
```

Event meanings at a glance: **TP1 hit** = the first profit target was reached and a partial was taken; **SL to BE** = your risk on the trade is now removed (stop at entry); **SL trailed** = the stop is following price to lock in gains; **SL+ (BE hit)** = the break‑even stop was hit, so the trade closed flat or with a tiny gain; **SL hit (loss)** = the original stop was hit; **TP2 (full TP)** = the full take‑profit was reached.

> ⚠️ **Simplified alerts intentionally omit the exact entry, stop, and target prices.** They tell you *that* something happened and *which* trade, not the precise levels. **Always confirm the actual entry price, stop‑loss, take‑profit, and current P&L directly in your MT5 terminal** (the Trade / Toolbox tab), matching by the magic number shown. Treat the alerts as a heads‑up, not as the source of truth.

**Full mode** adds the exact levels and the closed net result for your own records, e.g.
`XAUUSD BUY 0.10 lots #14111850 | Entry: 1234.56 | SL: 1230.00 | TP1: 1250.00 | TP2: 1270.00 | Strategy: MasterVP-BreakOut`.

> For Discord/Telegram to work you must allow web requests: **Tools → Options → Expert Advisors → Allow WebRequest for listed URL**, and add `https://discord.com` and `https://api.telegram.org`. For Email, set your SMTP details under **Tools → Options → Email**. Test all of this with the validator EA below *before* you rely on it.

### Validating notifications and the guardian before you deploy

A small helper EA, **`TestDeployOps`**, ships alongside KK‑MasterVP for exactly this. **Double‑click it in the Navigator** (or drag it onto any demo chart) so the inputs dialog opens, paste in the same Discord webhook / Telegram token / chat ID you intend to use, and it will: run the guardian's internal maths checks, create a sample trade‑CSV row, and send **real** showcase messages covering **every strategy and every event in both Full and Simplified mode** — so you can see exactly how each alert reads before you rely on it. It prints a `PASS`/`FAIL` summary to the **Experts** log and then removes itself. If a channel shows `FAIL` or nothing arrives, fix the WebRequest/SMTP settings above before going live. Running this once is the recommended last step before deployment.

> If you drag the EA on and it finishes instantly with no dialog, your terminal auto‑confirmed it with empty inputs (so nothing was sent). It removes itself on finish, so there's nothing to right‑click — **double‑click it from the Navigator** to get the inputs dialog and fill in your webhook/token there.

## 6. A calm way to run it

None of the following is advice — it is simply how the EA is designed to be used responsibly:

1. **Demo first, for a while.** Run it on a demo account that matches your intended broker and instrument, long enough to see it trade through quiet and busy conditions.
2. **Backtest to understand, not to predict.** Use the Strategy Tester with real ticks to learn how it behaves — where it wins, where it loses, how deep the drawdowns get. **A good backtest is not a forecast.**
3. **Size for the drawdown, not the headline.** Decide your per‑trade risk and your maximum acceptable drawdown *before* going live, and set the risk inputs accordingly. The strategy can and will have losing streaks.
4. **Mind your costs.** Check your broker's typical spread and commission on the instrument. For Gold and Bitcoin especially, costs and slippage make a real difference.
5. **Keep an eye on it.** Automated does not mean unattended forever. Markets and broker conditions change; review how it is performing periodically.

The goal is clarity and discipline, never urgency. A tool like this is most useful when it enforces a tested process patiently — not when it tempts you to over‑size or chase.

## 7. Troubleshooting & FAQ

**The EA isn't trading.** Check that *Allow Algo Trading* is ticked in the EA settings, the global *Algo Trading* toolbar button is on, and a smiling face shows on the chart. Also confirm your account allows automated trading and the market is open.

**It trades far less than I expected.** That is normal — it waits for its conditions. Selective filters, blocked hours, session windows, and volatility floors all reduce the number of trades on purpose.

**Position sizes look wrong.** Review the Risk sizing group: confirm `InpRiskUnit` and `InpRiskAccPct` (or `InpRiskUsd`) are what you intend, and check the broker's minimum lot and your account currency.

**Sessions or blocked hours seem off.** Check the configured UTC windows and blocked UTC hours directly. The EA evaluates them in fixed UTC, not broker time.

**Results differ from the backtest, or from another broker.** Expected. Spread, commission, slippage, feed quality, and server time all vary between brokers, and live differs from any test. **Past and tested results do not guarantee future or live results.**

**Does it guarantee profit?** No. Nothing here is a guarantee. It is a rule‑based strategy whose defaults come from historical study, and historical study does not predict the future.

## 8. Glossary

- **Volume profile** — a view of how much activity occurred at each price level.
- **POC (Point of Control)** — the single most‑active price level.
- **Value area (VAH / VAL)** — the band holding the bulk of activity; VAH is the upper edge, VAL the lower.
- **Master / local profile** — the long‑window (big‑picture) and short‑window (recent) profiles.
- **ATR** — Average True Range, a measure of typical price movement, used to size distances.
- **R (risk unit)** — a multiple of the entry‑to‑stop distance; targets and trails are often expressed in R or ATR.
- **Trailing stop** — a stop that follows a winning trade to lock in progress and let it run.
- **Drawdown** — the drop from an equity peak to a trough; the key measure of pain and the thing to size against.

## 9. Full disclaimer

This Expert Advisor and this guide are provided "as is," for educational and informational purposes only, with no warranty of any kind. They do not constitute financial, investment, legal, or tax advice and must not be relied upon as such. All default settings were derived from historical backtests; **a backtest is a study of past data and is not indicative of, and does not guarantee, future results.** No profit, performance, or outcome is promised or guaranteed. Automated trading of leveraged products such as Gold and cryptocurrencies carries a high risk of loss and is not suitable for everyone; you may lose some, all, or more than your deposited capital. You are solely responsible for configuring, testing, supervising, and using this software, and for all decisions and consequences that result. Always test on a demo account before risking real funds, and consider seeking advice from an independent, appropriately licensed professional. By using this Expert Advisor you accept that the authors and distributors accept no liability for any loss or damage arising from its use.
