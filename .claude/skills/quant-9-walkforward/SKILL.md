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

## Acceptance
- Out-of-sample performance holds across windows (no period-mixing, no peeking).
- Monte Carlo drawdown / ruin within risk tolerance.

Next: `/quant-10-promote-mt5`. See `docs/KENKEM_QUANT_OS.md` §7 (Phase 9).
