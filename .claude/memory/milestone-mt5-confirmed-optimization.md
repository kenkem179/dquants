---
name: milestone-mt5-confirmed-optimization
description: KK-MasterVP optimization loop closed — refined params confirmed PF>1 in the live MT5 tester
metadata: 
  node_type: memory
  type: project
  originSessionId: 5080b780-c6e1-43c1-b5c8-28268f43d81e
---

**2026-06-14: the full KK-MasterVP loop is closed and externally validated.** The Phase-8
optimized config (`research/optimization/best_btc.set`, BTCUSD M3) was re-run by the user in the
**MT5 Strategy Tester and confirmed PF > 1** — i.e. the improvement found on the C++ tick engine
**transfers to the real MQL5 EA**, despite the documented ATR-from-CSV residual. This proves the
end-to-end pipeline works: research → C++ Layer-2/3 port → MT5 parity ([[parity-findings-trade-level]])
→ Optuna optimize → MT5 confirm.

Refined config beat the faithful baseline on the C++ engine: full net −$75/PF 0.995 → **+$5744/PF
1.240**, DD halved, **Nov OOS −$904→+$1052 (PF 1.16)**. Param directions that mattered: tighter
breakout (BreakBufAtr 0.65→0.31), wider stop (SlAtrBrk 2.2→2.65), tighter trail + lower runner
target (TrailAtrMult 3.6→2.05, RunnerRr 10→5.3), more selective trend (AdxTrendMin 22→24, this one
FRAGILE), Tp1R 0.8→1.0. Details in `research/optimization/FINDINGS.md`.

**Still open:** Phase-9 walk-forward + Monte Carlo robustness (esp. the fragile adx knob); XAUUSD M3
optimization; a Level-2 parity re-check of the OPTIMIZED params would tighten confidence (would need
the user to export the MT5 trades CSV from this `best_btc.set` run). See
[[real-target-kenkem-strategies]] and [[workflow-commit-and-plan]].
