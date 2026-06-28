# MasterVP — The 60-Second Case

**An XAUUSD (gold) M5 trend-breakout EA, validated by the math that catches luck.**

---

### The result (real ticks, $10k, 2025-06 → 2026-05)
- **Profit Factor 1.42** · **+$86,034** · **1,423 trades**
- **Both years profitable independently** (2025 PF 1.37 · 2026 PF 1.46)
- Max drawdown **~21–28%** — stated openly, size for a 30–40% peak

### Why it isn't luck
- **Deflated Sharpe Ratio = 1.000** (pass bar is 0.95) — the one statistic built to detect curve-fitting
  and flukes, passed at maximum *after* penalizing for every variation we tried.
- **1,423 trades vs a 192-trade minimum** to be statistically confident — **7× clear of the line.**
- Survived **out-of-sample / walk-forward** and **Monte Carlo** stress — not a single lucky run.

### Why our backtest is trustworthy
- **Never tuned inside the MT5 tester.** Built and validated in Python + C++ on **160M+ real broker ticks.**
- **Proven MT5 byte-parity** — you can reproduce the result in your own terminal.
- **Costs modeled** (spread charged every trade); we treat live as *thinner* than backtest, never richer.

### What we won't hide
One instrument, one strategy type. Real losing streaks (20–30% drawdowns). No guarantees on any single
trade. We **reject far more strategies than we keep** — MasterVP is one of only two that survived everything.

> A modest, repeatable, statistically-validated edge — honest about its risk. That's what real looks like.
> Full evidence dossier: `MASTERVP-EVIDENCE-NOT-LUCK.md`.
