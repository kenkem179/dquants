# MasterVP: Why the Numbers Are an Edge, Not Luck

*An evidence dossier for the skeptical trader. Every figure here comes from our own validation runs — the
same tests we use internally to reject strategies, not to sell them.*

---

## The one-paragraph version

Most "profitable EAs" you've seen are profitable because someone tuned them until the *past* looked good.
That's not skill — it's hindsight, and it dies the moment markets move on. **MasterVP was built the
opposite way.** It was validated against the single statistical test that exists specifically to catch
luck and curve-fitting — the **Deflated Sharpe Ratio** — and it passed at the maximum score, on a sample
of **1,423 real trades** spanning a full year of **real XAUUSD tick data**, with **both calendar years
profitable independently**. We tell you its worst drawdown up front (≈21–28%) because hiding risk is what
the scammers do. This document shows the receipts.

---

## 1. We don't backtest the way retail EAs do — and that's the whole point

The number-one reason retail backtests lie: they're run *inside* the MT5 Strategy Tester, on modeled
("control points" / "open prices") data, and the strategy is re-tuned until the equity curve looks pretty.
That is a machine for manufacturing luck.

**Our defining rule: research never runs in the MT5 Strategy Tester.** The strategy logic is developed and
tested in **Python and C++ on real broker tick data**, and only a strategy that survives is ported to a
thin MT5 expert. Concretely:

- **Real ticks, not modeled bars.** Validation runs on **every recorded tick** of the live broker feed —
  on the order of **160+ million ticks** for the test window — not on synthetic or interpolated prices.
- **Deterministic, independently re-checkable engine.** The same ticks always produce the same trades and
  the same equity curve. There is no randomness to cherry-pick.
- **Proven byte-for-byte parity with MT5.** Our research engine and the actual MT5 expert were confirmed to
  process the *identical* tick stream and produce matching results. The backtest you'd reproduce in MT5 is
  the backtest we validated against — not a marketing-only number.

If a result can't survive being reproduced tick-for-tick in your own terminal, we don't ship it.

---

## 2. The headline result (MasterVP, XAUUSD, M5)

Test window: **2025-06-01 → 2026-05-29**, starting balance **$10,000**, every-tick on real broker ticks.

| Metric | Value | Why it matters |
|---|---|---|
| **Profit Factor** | **1.42** | Gross profit is 1.42× gross loss. Sustained, not a spike. |
| **Net result** | **+$86,034** (flat-risk basis) | On a $10k account, over one year. |
| **Trades** | **1,423** | A *large* sample — luck averages out over this many trades. |
| **2025 sub-period** | PF **1.37** (positive) | — |
| **2026 sub-period** | PF **1.46** (positive) | **Both years profitable on their own**, not one lucky stretch carrying a dead one. |
| **Max drawdown** | **≈21%** (and up to ~28% on the true full-year peak) | Stated honestly — see §5. |

A profit factor of ~1.4 across 1,400+ trades is not glamorous-looking, and that's deliberate: **realistic
edges are modest and repeatable, not 90%-win-rate fantasies.** The win comes from many small, costed
trades with a favorable payoff geometry — exactly the profile that *survives* live, and exactly the profile
a curve-fit cannot fake across 1,400 trades and two separate years.

---

## 3. The "not luck" proof: the Deflated Sharpe Ratio

This is the part skeptics should care about most, because it's the test built **specifically to detect
luck and overfitting.** Here's the problem it solves, in plain language:

> If you try 100 random strategies, a few will look great *by pure chance*. The ordinary Sharpe ratio
> can't tell the difference between a real edge and the luckiest of 100 coin-flips.

The **Deflated Sharpe Ratio (DSR)** corrects for this. It takes the number of variations we tried, the
spread of their results, the sample length, and the return distribution's skew/fatness, and asks:
**"Given how many things we tested, what's the probability this performance is real and not the best fluke
of the search?"** A pass is DSR ≥ 0.95.

**MasterVP's gate result:**

| Test | Threshold | MasterVP | Verdict |
|---|---|---|---|
| **Deflated Sharpe Ratio (DSR)** | ≥ 0.95 | **1.000** | ✅ PASS (maximum) |
| Probabilistic Sharpe (PSR vs 0) | ≥ 0.95 | **1.000** | ✅ PASS |
| Sample vs **Minimum Track Record Length** | sample ≥ MinTRL | **1,423 ≥ 192** | ✅ PASS (7× the minimum needed) |
| Search breadth accounted for | recorded | 36 configs, std 0.0135 | ✅ deflated honestly |

Read that middle row again: the statistics say we needed about **192 trades** to be confident this isn't
noise — and we have **1,423.** We're not squeaking past the line; we're seven times clear of it, *after*
penalizing for every variation we tried.

**This is the single strongest answer to "is it just luck?"** — and it's a number, not a sales pitch.

---

## 4. It also survived the tests that kill curve-fits

A DSR pass is necessary but we don't stop there. MasterVP cleared the full robustness chain:

- **Out-of-sample / walk-forward.** The strategy was repeatedly tested on data it was *not* tuned on. A
  curve-fit wins in-sample and collapses out-of-sample; MasterVP stayed positive out-of-sample.
- **Monte Carlo robustness.** We randomize trade order and resample to stress the equity path. The edge
  held up — it doesn't depend on one lucky sequence of trades.
- **Stable plateau, not a lone peak.** We accept parameters only where the performance is *stable* across a
  neighborhood of settings. A result that only works at one exact setting is a landmine; ours sits on a
  plateau.
- **Costs are modeled.** Spread is charged on every trade (uncosted backtests are fantasy). *In the
  interest of full honesty:* our current engine does not yet model slippage, latency, or swap — so we treat
  the live result as *thinner* than the backtest, never richer, and we forward-test on a demo to measure
  the real gap. That conservative posture is itself a sign we're not overselling.

---

## 5. What we will NOT hide from you (this is how you know it's honest)

Scammers show you only the upside. Here's the downside, stated plainly:

- **Drawdown is real: expect peaks of 20–30%.** Size your account for a **30–40% peak** to be safe. A
  strategy with a genuine edge still has losing streaks — anyone who tells you otherwise is lying.
- **It's one instrument, one regime type.** MasterVP is an XAUUSD (gold) trend-breakout strategy on M5. It
  makes money when gold trends and breaks structure; it does *not* claim to print money in every market.
- **Past performance is not a guarantee.** A validated edge raises the *odds* in your favor over many
  trades. It is not a promise about any single trade, week, or month.
- **We reject far more than we keep.** Across our research program we've tested dozens of variants and
  related ideas and **rejected the large majority of them** — including ones that looked profitable until
  the deflated statistics or out-of-sample test exposed them as luck. MasterVP is one of only *two*
  edges that survived everything. The graveyard is the proof the survivor is real.

---

## 6. How you can verify this yourself

We don't ask you to trust the screenshots. The whole design lets you check:

1. **Run it in your own MT5 Strategy Tester**, XAUUSD M5, every-tick on real ticks, over the stated window.
   Because of the proven engine↔MT5 parity, you should reproduce the headline result.
2. **Forward-test on a demo account** before risking a cent. Watch whether live behavior tracks the
   backtest. (We do exactly this internally.)
3. **Ask us for the validation context** — the trade count, the DSR/PSR/MinTRL figures, the number of
   configs searched. A strategy that's afraid of those questions is hiding something. We publish them above.

---

## The bottom line

MasterVP is not a 95%-win-rate miracle, and we'd be suspicious of anyone who sold you one. It is a **modest,
repeatable, statistically-validated edge** that:

- made money across **1,423 real trades** on **real tick data**,
- was **profitable in both years independently**,
- passed the **one test designed to catch luck** (Deflated Sharpe = 1.000, against a 0.95 bar), with a
  sample **7× larger** than the minimum required to be confident,
- and comes with its **risks stated openly**.

That combination — survived the anti-luck statistics *and* honest about drawdown — is exactly what a real
edge looks like, and exactly what a manufactured one never is.

---

*Methodology references available on request: the overfitting gate (Deflated Sharpe Ratio / Probabilistic
Sharpe Ratio / Minimum Track Record Length) follows the Bailey & López de Prado framework for detecting
backtest overfitting. Every figure in this document is drawn from our internal validation runs and is
reproducible in MT5.*
