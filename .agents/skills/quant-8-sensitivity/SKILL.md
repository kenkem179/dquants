---
name: quant-8-sensitivity
description: Phase 8 of the KenKem Quant OS SOP — parameter sensitivity heatmaps + Bayesian (Optuna) optimization to find stable plateaus, not lone peaks. Use after a strategy backtests positively.
---

# Phase 8 — Sensitivity & Optimization

A backtest that only works at one parameter value is curve-fit. Find robust plateaus.

## Input
A backtesting strategy + its parameter ranges.

## Output
`reports/`: parameter heatmaps (e.g. ADX threshold × ATR threshold) + an Optuna study summary.

## How
- **Stay inside the parity envelope** (`/quant-0-parity-baseline`): a swept value that activates an
  unverified code path/regime re-opens parity — re-confirm before trusting that region. Don't promote
  a peak the engine was never validated to model.
- Sweep parameter **pairs** and plot heatmaps of expectancy / Sharpe / profit factor.
- Use **Optuna** (Bayesian) rather than brute force for higher-dimensional search.
- Look for **stable plateaus** — broad regions that all work. Reject tiny isolated peaks.
- Consider regime-specific parameters where justified by discovery.

## Acceptance
- Chosen parameters sit on a plateau, robust to ± perturbation.
- No single-point magic value relied upon.

Next: `/quant-9-walkforward`. See `docs/KENKEM_QUANT_OS.md` §7 (Phase 8).
