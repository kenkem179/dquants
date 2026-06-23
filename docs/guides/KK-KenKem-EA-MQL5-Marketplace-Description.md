# KK-KenKem — MQL5 Marketplace Product Description

*Copy-paste source for the MQL5 Market product page. Confident, plain-language marketing tone — and deliberately **not** financial advice. No profit is promised anywhere; every default is described as "tuned from backtests," and backtests are stated to not guarantee the future. This copy reflects the **market edition**, whose dialog exposes only the user-adjustable controls — the strategy internals are pre-tuned and hidden. Edit freely to fit the listing.*

---

## KK-KenKem — Multi-Engine Trend EA for Gold (XAUUSD M1)

**A fully-automated, multi-engine trend-following EA for Gold — tuned out of the box, with a deliberately small set of controls so you manage risk while the EA runs the strategy.**

KK-KenKem doesn't rely on a single signal. It runs two complementary trend engines side by side — **trend continuation** and **pullback** — backed by a strict quality filter and a serious risk manager. It reads the trend across multiple timeframes, waits for a high-quality setup, enters, places a measured stop, banks a partial, moves to break-even, and trails the runner. No martingale. No grid. No averaging into losers.

The defaults ship tuned to our validated flagship configuration — **XAUUSD on M1** — so you can attach it and go.

---

### Why traders will like it

- **Genuinely automated.** Attach it, set your risk, enable Algo Trading — it handles entries, stops, partials, break-even and trailing on its own.
- **Two engines, one discipline.** A trend-continuation engine rides fresh, healthy trends; a pullback engine joins established trends on a dip. Both share the same risk and trade management.
- **Quality over quantity.** Every setup is scored for trend strength and conviction, and filtered against multi-timeframe agreement, volatility and spread. Weak setups are simply skipped.
- **You control risk, the EA controls strategy.** The technical engine is pre-set and locked; you only touch the inputs that should be yours — which engines to run, risk per trade, drawdown limits, reward levels, trade frequency, and news/time avoidance.
- **Prop-firm friendly.** Built-in daily-loss cap, drawdown slowdown and soft-block, plus a tighter "prop" preset and a dedicated prop mode, make it straightforward to respect firm limits.
- **No dangerous tricks.** No martingale, no grid, no hidden recovery scheme that risks the account to mask a losing streak.

---

### What it trades

| | |
|---|---|
| **Flagship** | XAUUSD (Gold), M1 — the configuration the defaults are tuned to |
| **Style** | Multi-engine, trend-aligned scalping (continuation + pullback) |
| **Confirmation** | Multi-timeframe (M3 / M5 / M15 / H1) trend agreement |
| **Account type** | Hedging or netting; designed for ECN / low-spread accounts |

---

### Quick start

1. Attach **KK-KenKem** to an **XAUUSD M1** chart.
2. Load the included **`.set`** preset (personal or prop) from the Inputs tab, or just keep the defaults.
3. Set **risk per trade** to a level you are comfortable with.
4. Enable **Algo Trading**. That's it — the EA does the rest.

> Run it on a **demo account first**, long enough to see it trade through different conditions, before committing real capital. Gold spreads and commissions directly affect a scalping strategy — test on the account you intend to run.

---

### The settings you control

KK-KenKem keeps the dialog short on purpose. The strategy's technical engine — the moving averages, momentum filters, volatility bands, stop logic and exit ladders — is pre-tuned and fixed. What you adjust is the part that should be yours:

**Entry engines**
- *Enable E1 — Trend following* — the core engine that detects and rides fresh trends.
- *Enable E2 — Pull back* — joins an established trend on a pullback to value.

**Risk per trade**
- *Standard lot size* — the baseline lot the sizing scales from.
- *Risk per trade (%)* — the fraction of balance put at risk on each trade.

**Reward (take-profit) levels**
- *E1 reward-to-risk* — the profit target for the trend engine, as a multiple of the stop.
- *E2 reward-to-risk* — the same for the pullback engine.

**Account protection / daily drawdown**
- *Max daily loss* — pause new trades once the day's loss reaches this level.
- *Drawdown slowdown* — start reducing risk when overall drawdown reaches this level.
- *Drawdown soft-block* — at this drawdown, keep running but on micro lots.
- *Profit protection* — once the day is meaningfully green, reduce size to protect gains.

**Trade frequency caps**
- *Max high-risk trades per session* — cap on aggressive entries per session.
- *Max SL/TP placements per session* — cap on total trade placements per session.
- *Max losses per session* — block new entries after this many real losses in a session.

**Times to avoid trading**
- *News filter* — pause new entries around economic releases.
- *Avoid high-impact news* — restrict the filter to the biggest events.
- *Minutes before / after* — the size of the news blackout window.
- *Close all at session end* — flatten open trades when the session closes.

**Execution safety**
- *Max spread* — refuse entries when the spread is wider than you allow.

**Mode & display**
- *Made for prop trading* — simplified alerts plus a hard block near maximum drawdown, for funded accounts.
- *Show debug info* — on-chart diagnostics.

*(The trend, momentum, volatility, stop-loss and exit-engine internals are pre-configured and not exposed — so the dialog stays clean and the tested behavior stays intact.)*

---

### Included presets

- **Personal** — the XAUUSD M1 configuration as tuned.
- **Prop** — the same engine with tighter risk (lower daily-loss and drawdown limits) to suit funded-account rules.

Load either from the Inputs tab → **Load**.

---

### Requirements

- MetaTrader 5, with **Algo Trading enabled**.
- A broker offering competitive spreads on Gold (spreads and commissions directly affect a scalping strategy — test on the account you intend to run).
- Recommended: VPS for uninterrupted operation.

---

### An honest word on performance

The default settings were chosen from extensive historical backtesting and walk-forward / robustness checks, and they pass our overfitting gate. That work tells us the strategy has behaved sensibly across many market conditions — but **a backtest is a study of the past, not a prediction of the future.** Live results differ from tests because spread, slippage, latency, news and broker conditions are never identical. Drawdowns are a normal part of any real strategy; size your risk for the deep dips, not the headline numbers. Test on demo, start small, and only ever risk capital you can afford to lose.

---

### Disclaimer

This Expert Advisor is provided for trading-automation and educational purposes. It is **not financial, investment, legal, or tax advice**, and **no profit or outcome is promised or guaranteed**. All settings are derived from historical data; past and tested performance does not indicate future results. Automated trading of leveraged products such as Gold carries a high risk of loss — you may lose some, all, or more than your deposited capital. You are solely responsible for configuring, testing, supervising and using this product, and for all decisions and their consequences. Test on a demo account before trading live, and consider consulting an independent, appropriately licensed professional.

---

*Tags: gold, XAUUSD, scalping, trend, M1, multi-engine, pullback, prop firm, automated, expert advisor, no martingale.*
