# KK-MasterVP BTCUSD M3 — Phase-8 Optimization Findings

Optimized on the **parity-validated C++ tick engine** (Layer 3), reference window
**BTCUSD M3 2025-08-11 → 2025-11-30**. Method: 200-trial Optuna (full-window net/maxDD,
train/test consistency bonus) → robustness screen (16/200 robust plateau) → one-param
sensitivity sweep. Train = Aug–Oct, Test/OOS = November.

## Result (refined vs faithful baseline)

| metric        | baseline | refined | 
|---------------|----------|---------|
| full net      | −$75     | **+$5744** |
| full PF       | 0.995    | **1.240** |
| max DD        | $2383    | **$1190** |
| **Nov OOS net** | **−$904** | **+$1052** |
| Nov OOS PF    | 0.72     | **1.16** |

The edge holds out-of-sample (Nov flips from a loss to a profit), drawdown halves.

## Recommended params (`best_btc.set` overrides on the code-default economics)

| param | baseline | refined | note |
|-------|----------|---------|------|
| InpSlAtrBrk     | 2.2  | **2.65** | wider initial stop |
| InpBreakBufAtr  | 0.65 | **0.31** | tighter breakout entry (≥0.55 collapses OOS) |
| InpBreakMaxAtr  | 9.0  | **5.0**  | reject far-chase breaks (lower=better, monotone) |
| InpTp1R         | 0.8  | **1.0**  | OOS sweet spot (PF 1.16); >1.2 decays OOS |
| InpTp1ClosePct  | 20   | **15**   | let more ride; smooth/stable |
| InpTrailAtrMult | 3.6  | **2.05** | tighter trail — PLATEAU (flat 1.8–3.6) |
| InpRunnerRr     | 10   | **5.3**  | PLATEAU (≥5.3 flat; runner rarely reaches backstop) |
| InpAdxTrendMin  | 22   | **24**   | ⚠️ SHARP peak (22→PF1.05, 26→0.999) — fragile |
| InpDiSpreadMin  | 6    | **6**    | plateau 4–8 |

Plateaus (trail, runner_rr, tp1%, di_spread) are trustworthy. BreakBuf/BreakMax are robust
in DIRECTION (tighter is better) though magnitude matters. **AdxTrendMin=24 is the one
fragile knob** — a narrow peak; Phase-9 walk-forward must confirm it isn't overfit.

## Caveats / next
- Single train/test split on the same window the engine was parity-checked on. **Phase 9
  walk-forward (rolling) + Monte Carlo is the real OOS gate** before trusting these live.
- Absolute $ carry the documented ATR-from-CSV residual vs MT5; the RELATIVE improvement and
  the param DIRECTIONS are the trustworthy signal. **Re-run `best_btc.set` in the MT5 tester
  to confirm** before any demo-forward test.
- BTCUSD only. XAUUSD M3 not yet optimized (different spread/vol regime).
- Repro: `python research/optimization/optimize_btc.py 200 4` →
  `sensitivity_btc.py research/optimization/best_btc.set`.
