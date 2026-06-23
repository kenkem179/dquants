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

1. Copy `KK-MasterVP.ex5` into your MetaTrader 5 `MQL5/Experts/` folder (or a subfolder you keep EAs in).
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

### VP core — how the structure is measured

- **InpVpLookback** — the length, in bars, of the *local* (recent) volume‑profile window. Larger = a longer, slower picture of recent activity.
- **InpVpBins** — how many price buckets the profile is split into. More bins = finer resolution.
- **InpVaPct** — the percentage of activity that defines the "value area" band around the busiest price (e.g. 70%).
- **InpMasterMult** — the *master* profile window is the local window multiplied by this. With a local window of 120 and a multiplier of 4, the master profile covers 480 bars. The master window is the big‑picture structure the breakout is measured against.
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

The session reference timezone is UTC plus an offset.

- **InpBrokerGMTOffset** — hours added to UTC to reach the session reference timezone. The default (10) matches the calibration used in testing; if your broker's server time differs you may need to adjust this so sessions line up.
- **InpAsiaSess / InpLdnSess / InpNySess** — the Asia, London, and New York session windows, in the reference timezone.
- **InpBlockedHoursStr** — specific low‑liquidity hours to skip, e.g. `"8,16"` or `"9-11"`, in the reference timezone.
- **InpForceCloseSessNews** — force‑close open trades when a session ends. Off by default.

### News avoidance — a live‑safety overlay

- **InpAvoidNews** — when on, block new entries around high‑impact news releases. Off by default.
- **InpNewsMinsBefore / InpNewsMinsAfter** — how many minutes before and after each event to stay out.
- **InpUseEmbeddedNews** — fall back to the calendar compiled into the EA if no custom news file is supplied.

### Misc and parity

- **InpMVPMagic** — the magic number that tags this EA's trades. Give each running instance a unique value if you run more than one.
- **InpExportParity** — a developer/testing switch that writes a trade CSV in the Strategy Tester for validation against the research engine. Leave **off** for live trading.

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

**Sessions or blocked hours seem off.** The session timezone is UTC plus `InpBrokerGMTOffset`. If your broker's server time differs from the calibration, adjust the offset so the windows line up.

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
