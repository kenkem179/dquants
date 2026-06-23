# KK‑MasterVP — MQL5 Marketplace Product Description

*Copy‑paste source for the MQL5 Market product page. Confident, plain‑language marketing tone — and deliberately **not** financial advice. No profit is promised anywhere; every default is described as “tuned from backtests,” and backtests are stated to not guarantee the future. Edit freely to fit the listing.*

---

## KK‑MasterVP — Volume‑Profile Breakout EA for Gold, Bitcoin & more

**A clean, fully‑automated volume‑profile breakout strategy — tuned out of the box, with a deliberately small set of controls so you manage risk while the EA handles the strategy.**

KK‑MasterVP maps where the market has actually traded — the busy price shelves and the quiet edges — and acts when price breaks decisively out of that structure with the trend behind it. It enters, places a measured stop, optionally banks a partial, moves to break‑even, and trails the runner. No martingale. No grid. No averaging into losers. Just one disciplined, rule‑based engine doing the same thing every time.

The defaults ship tuned to our flagship configuration — **XAUUSD on M5** — so you can attach it and go. It also runs on **BTCUSD and other liquid symbols on M3 and M5**; in our own testing **M5 has been the most consistent timeframe**.

---

### Why traders will like it

- **Genuinely automated.** Attach it, set your risk, enable Algo Trading — it manages entries, stops, partials, break‑even and trailing on its own.
- **Tuned out of the box.** Default settings reflect the configuration that performed best across our extensive historical testing on XAUUSD M5. Nothing to optimize before you start.
- **Built around volume‑profile structure.** Decisions are anchored to where real activity has concentrated — not a stack of lagging oscillators.
- **You control risk, the EA controls strategy.** The complex internals are pre‑set and locked; you only touch the handful of inputs that should be yours — risk per trade, profit‑taking, trading hours, news, and execution safety.
- **Prop‑firm friendly.** Built‑in daily‑loss and total‑drawdown caps with cooldowns, plus a tighter “prop” preset, make it straightforward to respect firm limits.
- **No dangerous tricks.** No martingale, no grid, no hidden recovery mode that blows the account to hide a losing streak.

---

### What it trades

| | |
|---|---|
| **Flagship** | XAUUSD (Gold), M5 — the configuration the defaults are tuned to |
| **Also runs on** | BTCUSD and other liquid symbols, on M3 and M5 |
| **Best timeframe (in our testing)** | **M5** |
| **Style** | Volume‑profile breakout, trend‑aligned, single‑position |
| **Account type** | Hedging or netting; designed for ECN/low‑spread accounts |

---

### Quick start

1. Attach **KK‑MasterVP** to an **XAUUSD M5** chart.
2. Load the included **`.set`** preset (personal or prop) from the Inputs tab, or just keep the defaults.
3. Set **risk per trade** to a level you are comfortable with.
4. Enable **Algo Trading**. That’s it — the EA does the rest.

> Run it on a **demo account first**, long enough to see it trade through different conditions, before committing real capital.

---

### The settings you control

KK‑MasterVP keeps the dialog short on purpose. The strategy’s technical engine is pre‑tuned and fixed; what you adjust is the part that should be yours:

**Risk per trade**
- *Risk basis* — size by % of balance or a fixed amount.
- *Risk per trade (%)* — the percentage of balance put at risk on each trade.
- *Fixed risk (currency)* — used when sizing by a fixed amount.
- *Max lot* — a hard ceiling on position size.
- *Skip if min‑lot over risk* — refuse a trade rather than over‑risk when the broker’s minimum lot is too large.
- *Max slippage (points)* — the most slippage you’ll accept on entry.

**Account protection**
- *Max daily drawdown (%)* — pause new trades once the day’s loss hits this level.
- *Daily cooldown (hours)* — how long to stay paused after a daily‑loss breach.
- *Max total drawdown (%)* — halt trading if overall drawdown reaches this level.

**Profit taking**
- *TP1 close (%)* — how much of the position to bank at the first target (set 0 to let the full runner work).
- *Break‑even after TP1* — move the stop to break‑even once the first target is reached.

**Trading hours to avoid**
- *Broker GMT offset* — align the EA’s clock with your broker’s server time.
- *Blocked hours* — skip specific low‑liquidity hours (e.g. `2,3,14` or `9‑11`).

**News filter**
- *Avoid news* — pause new entries around high‑impact releases.
- *Minutes before / after* — the size of the news blackout window.
- *Use built‑in calendar* — fall back to the embedded calendar when no custom file is provided.

**Execution safety**
- *Max spread* — refuse entries when the spread is wider than you allow.
- *Max trades per session* — cap how many new trades open per session.

**Misc**
- *Magic number* — set a unique value if you run more than one instance.

*(The volume‑profile, trend, and exit‑engine internals are pre‑configured and not exposed — so the dialog stays clean and the tested behavior stays intact.)*

---

### Included presets

- **Personal** — the XAUUSD M5 configuration as tuned.
- **Prop** — the same engine with tighter risk (lower per‑trade risk and firm daily‑loss / drawdown caps) to suit funded‑account rules.

Load either from the Inputs tab → **Load**.

---

### Requirements

- MetaTrader 5, with **Algo Trading enabled**.
- A broker offering competitive spreads on your chosen symbol (Gold/Bitcoin spreads and commissions directly affect a breakout strategy — test on the account you intend to run).
- Recommended: VPS for uninterrupted operation.

---

### An honest word on performance

The default settings were chosen from extensive historical backtesting and walk‑forward / Monte‑Carlo robustness checks. That work tells us the strategy has behaved sensibly across many market conditions — but **a backtest is a study of the past, not a prediction of the future.** Live results differ from tests because spread, slippage, latency, news and broker conditions are never identical. Drawdowns are a normal part of any real strategy; size your risk for the deep dips, not the headline numbers. Test on demo, start small, and only ever risk capital you can afford to lose.

---

### Disclaimer

This Expert Advisor is provided for trading‑automation and educational purposes. It is **not financial, investment, legal, or tax advice**, and **no profit or outcome is promised or guaranteed**. All settings are derived from historical data; past and tested performance does not indicate future results. Automated trading of leveraged products such as Gold and cryptocurrencies carries a high risk of loss — you may lose some, all, or more than your deposited capital. You are solely responsible for configuring, testing, supervising and using this product, and for all decisions and their consequences. Test on a demo account before trading live, and consider consulting an independent, appropriately licensed professional.

---

*Tags: volume profile, breakout, XAUUSD, gold, BTCUSD, bitcoin, scalping, M5, trend, prop firm, automated, expert advisor.*
