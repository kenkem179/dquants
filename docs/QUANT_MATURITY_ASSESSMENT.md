# Quant maturity assessment + the "missing-muscles" toolkit (internal dev note)

> Audience: the developer (you / future agents). Not user-facing marketing. Brutally honest by request.
> Date: 2026-06-22. Author: Claude (Opus 4.8). Scope: dquants pipeline, retail FX high-liquidity context.

## 1. Honest verdict

**Retail/prop systematic trader & engineer** — yes, defensibly, and in the *top decile of that
population* on methodology hygiene. What earns that: the research/execution firewall (no research in
the Strategy Tester), the engine↔MT5 parity gate (Gate 0), deflated-Sharpe / MinTRL / PBO lock
discipline (`research/stats/`), no-lookahead enforcement, and — most importantly — a demonstrated
willingness to kill our own conclusions when MT5 disconfirms the engine (E4 fictional exits, BTC
reversion). That self-correction loop is the actual job and it's real here.

**"Top 1% quant developer at Citadel"** — no, and not because the engineering is weak. It's a
different game:
- *Quant developer* at that tier = elite systems engineer (low-latency C++, kdb+/q, FIX, distributed
  backtest grids, millions of msgs/sec). Our C++ is a single-threaded deterministic backtester —
  clean, correct, but *strategy logic*, not *trading infrastructure*.
- We trade CFDs vs a broker's synthetic feed: no real order book, no real fills, no queue position, no
  market impact, no capacity question. Citadel trades the actual exchange.
- Alpha is hand-crafted TA (EMA/VP/FVG/ER) — *signal craftsmanship*, not universe-scale statistical
  alpha (cross-sectional ranking, factor neutralization, alpha blending, signal-decay/IR).
- Stats are good (DSR/PSR/PBO) but stop at walk-forward; no CPCV/embargo/meta-labeling, and no
  program-wide multiple-testing deflation. Samples are thin, single-venue, single-regime.

The "AI era" premise ("nobody hand-writes the code anymore") is half a trap: implementation was never
the moat. The moat is **judgment under ambiguity**, which we have — but it's currently applied to a
retail problem space, not the institutional one.

## 2. The missing muscles (and which we can build in our retail FX context)

| Muscle | Institutional form | Our retail-FX-feasible form | Status |
|---|---|---|---|
| Portfolio construction | universe-scale risk budgeting | combine N trade streams (EA×symbol×TF) → weights/lot multipliers | **BUILT** `research/portfolio/` |
| Statistical depth | CPCV, embargo, meta-labeling | CPCV + purge + embargo + OOS-path PBO | **BUILT** `research/stats/cpcv.py` |
| Microstructure cost | impact/queue/Almgren-Chriss | breakeven-cost-per-trade + vol/session/tail-spike stress | **BUILT** `research/execution/` |
| Capacity | $AUM capacity curves | N/A at retail size, but cost-stress is the proxy | partial (cost model) |
| Real fills / order book | L2/L3, FIX | not possible vs CFD feed — acknowledge & stress instead | out of scope |
| Live audited track record | the certifier | demo→live forward test (existing SOP §7 tail) | process, not code |

## 3. What was built in this pass

### 3.1 Portfolio layer — `research/portfolio/portfolio.py`
The thing you explicitly asked for: you can run one EA on 2 timeframes, or 2 symbols, and need a
*world-class* way to size them together. This module:
- loads any number of engine trade streams (auto-detects the `entryTimeUTC`/`realizedUsd`/`pnlUsd`
  schema variants, same as `stats/gate.py`),
- aligns them to a common calendar grid (daily by default) → a returns matrix,
- estimates covariance with **Ledoit-Wolf constant-correlation shrinkage** (raw sample covariance is
  garbage with few streams / short history),
- computes allocation weights by: equal, inverse-variance, **equal-risk-contribution (risk parity)**,
  **Hierarchical Risk Parity (HRP, López de Prado)**, max-Sharpe (tangency, long-only), and
  **fractional Kelly**,
- reports book-level metrics: portfolio Sharpe, maxDD, vol, **per-stream marginal/component risk
  contribution**, diversification ratio, and the correlation matrix,
- emits **lot multipliers** per stream (weights normalized to a base) — the directly actionable output
  for the EAs,
- feeds the *combined* portfolio return series back through the overfitting gate (PSR/DSR), and can run
  CPCV across the allocation methods so the choice of weighting scheme is itself multiple-testing-aware.

Why HRP specifically: with 2–6 correlated streams and short history, mean-variance inverts a noisy
covariance and produces extreme, unstable weights. HRP never inverts the matrix (clusters by
correlation distance, allocates by recursive bisection) → far more stable OOS. This is the
single most important upgrade for the "same EA on 2 TFs" case, where the two streams are highly
correlated and naive weighting silently doubles risk.

### 3.2 CPCV — `research/stats/cpcv.py`
Walk-forward gives *one* OOS path. CPCV gives *many* (φ = C(N,k)·k/N paths) by training on every
combination of N−k groups and testing on the held-out k, **purging** train rows whose window overlaps
test and **embargoing** rows just after test (kills serial-correlation leakage). Outputs a
*distribution* of OOS Sharpe/PF/maxDD and an embargo-aware PBO. This is the AFML-grade answer to "is
the OOS number luck of where the fold boundary fell?".

### 3.3 Execution cost realism — `research/execution/cost_model.py`
Directly answers the spread/slippage skepticism (cf. KenKemExpert's abnormal-spread/black-swan
avoidance). Instead of trusting one cost assumption it asks the honest questions:
- **Breakeven cost per trade** = mean(realizedUsd): the per-trade round-trip cost (in account ccy)
  that zeros the edge. Compare to plausible real cost (spread×pip_value×lot + commission). If the
  margin is thin, the "edge" is a cost artifact.
- **Cost stress sweep**: re-price the stream under escalating per-trade costs (fixed USD or
  pip-based when lot is present), session-dependent spread multipliers, vol-scaled slippage, and a
  **tail-spike** model (random subset of trades hit a black-swan spread blowout). Report PF/net/DSR at
  each level and the cost level at which the edge dies.

## 4. How to use (quickstart)

```bash
conda activate kenkem
# Portfolio: same EA, two timeframes
python -m research.portfolio.portfolio \
  --trades XAU_M3=research/.../trades_xau_m3.csv \
  --trades XAU_M5=research/.../trades_xau_m5.csv \
  --method hrp --freq D --out research/portfolio/weights_xau.json

# CPCV PBO on a swept config-return matrix
python research/stats/cpcv.py --matrix research/.../trial_returns.csv --groups 8 --test 2 --embargo 0.01

# Cost stress on a locked stream
python -m research.execution.cost_model --trades research/.../_locked.csv --pip-value 10 --lot 0.1
```

## 5. The roadmap to actually close the gap (priority order)

1. **Live audited track record** — nothing substitutes. Even small/prop-funded, 12+ months.
2. **Portfolio layer in production** — wire the lot multipliers from §3.1 into the EA set; track
   book-level DD, not per-strategy DD. (Tooling now exists; the discipline is the work.)
3. **Move research to exchange-traded data** (CME FX futures / 6E,6B,6J) even read-only — learn real
   order books, real fills, capacity. Drop the CFD-feed conceptual dependency.
4. **CPCV + meta-labeling into the gate** — §3.2 is the splitter; add meta-labeling (a secondary model
   that sizes/filters the primary signal) next.
5. **If "developer" specifically** — build something latency/throughput-real (tick-handling, kdb+/q, a
   FIX simulator). Current C++ doesn't exercise those muscles.

## 6. Standing caveats for future agents
- These are *harness* tools (Python). The C++ engine remains the truth for fills/PnL; the portfolio &
  cost tools consume its trade CSVs and never replace parity (Gate 0).
- Thin samples mean every portfolio weight is itself an estimate — always run the allocation through
  CPCV/gate before trusting it. Prefer HRP/risk-parity over max-Sharpe on this data.
- Correlation between "same EA different TF" streams is high; the diversification benefit is smaller
  than it looks. The tool will tell you the real number — believe it.
