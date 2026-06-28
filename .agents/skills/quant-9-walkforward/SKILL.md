---
name: quant-9-walkforward
description: Phase 9 of the KenKem Quant OS SOP — walk-forward validation + Monte Carlo robustness. Use to confirm out-of-sample performance before considering MT5 deployment.
---

# Phase 9 — Walk-Forward + Monte Carlo

The gate between "looks good in-sample" and "deploy". Out-of-sample must hold.

## Input
A strategy with chosen (plateau) parameters.

## Output
`reports/`: rolling walk-forward report + Monte Carlo robustness report.

## How
- **Walk-forward:** rolling train(2y) / validate(6m) / test(6m). **Never mix periods** — OOS stays OOS.
- Report OOS metrics per window and aggregated; watch for decay.
- **Monte Carlo:** randomize trade order, slippage, and execution to estimate the distribution of
  outcomes (drawdown, terminal equity). Estimate probability of ruin.
- **Overfitting gate (mandatory):** the chosen config was picked by searching N candidates, so its
  Sharpe is selection-inflated. Deflate it: run the locked trade stream through the strategy-agnostic
  gate, passing the search context from your sweep.
  ```
  conda run -n kenkem python research/stats/gate.py \
      --trades <locked trades.csv> --n-trials <N configs swept> --sr-trial-std <std of per-trade Sharpe across trials>
  ```
  Reports Deflated Sharpe (DSR), Probabilistic Sharpe, Min Track Record Length. (PBO/CSCV available
  in `research/stats/overfitting.py` when you have the full sweep return-matrix.) See `research/stats/README.md`.

## Acceptance
- Out-of-sample performance holds across windows (no period-mixing, no peeking).
- Monte Carlo drawdown / ruin within risk tolerance.
- **Overfitting gate: DSR ≥ 0.95 with sample ≥ Min Track Record Length** (DSR 0.90–0.95 = WARN, state
  it explicitly; DSR < 0.90 = FAIL, do not promote). A config that fails the gate is curve-fit — back
  to Phase 8, not Phase 10.

Next: `/quant-10-promote-mt5`. See `docs/KENKEM_QUANT_OS.md` §7 (Phase 9).
