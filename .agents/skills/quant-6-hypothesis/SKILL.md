---
name: quant-6-hypothesis
description: Phase 6 of the KenKem Quant OS SOP — turn discovery findings into explicit, testable trading hypotheses with measured expectancy. Use after discovery.
---

# Phase 6 — Hypothesis Generator

Convert statistical findings into explicit entry/exit rules with measured edge.

## Input
`research/discovery/` reports (drivers + regimes).

## Output
`research/hypotheses/H<NN>_<slug>.md`, one per hypothesis, each containing:
- Rule, e.g. *Long if `ADX>23` AND `ATR_pct>70` AND `price>POC`*.
- Regime it applies to.
- Measured win rate, profit factor, **expectancy (in R)**, and **sample size**.
- Failure modes / when it breaks.

## How
- Prefer simple, economically-sensible rules over many-condition fits.
- Measure on in-sample data only here; real validation is later phases.
- Reject anything with tiny sample size or expectancy indistinguishable from noise.

## Acceptance
- Each hypothesis is falsifiable, has a concrete rule, and reports expectancy + n.
- No rule depends on lookahead or survivorship.

Next: `/quant-7-backtest`. See `docs/KENKEM_QUANT_OS.md` §7 (Phase 6).
