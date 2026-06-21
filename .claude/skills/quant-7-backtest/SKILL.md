---
name: quant-7-backtest
description: Phase 7 of the KenKem Quant OS SOP — backtest a hypothesis with realistic costs, first vectorized (vectorbt) then on the C++ tick engine. Use after a hypothesis is defined.
---

# Phase 7 — Backtest

Two-stage: fast vectorized screen, then truth on real ticks via the C++ TickEngine.

## Input
A hypothesis from `research/hypotheses/` + bars/ticks Parquet.

## Output
`backtests/results/<strategy>/`: equity curve, trade log, metrics (CAGR, Max DD, Sharpe, Sortino,
Profit Factor).

## How
0a. **Parity gate first (`/quant-0-parity-baseline`)** — the engine must reproduce the MT5 reference to
   tolerance before any engine number is trusted (or be N/A if no reference exists → results UNVALIDATED).
   Sweep only INSIDE the parity-validated envelope.
0b. **Edge gate (`/quant-6b-edge-autopsy`)** — prove the raw signal has positive conditional expectancy
   (net of costs) on the `--signals-out` stream. If the autopsy fails, kill the idea; do not sweep.
1. **Vectorized screen** with `vectorbt` for fast iteration.
2. **C++ TickEngine** (`cpp_core/backtester/`) on real ticks for the authoritative result — this is the
   true tester, not MT5.
3. **Always model costs**: spread, slippage, commission, latency. Uncosted scalping results are fantasy.
4. Keep the C++ strategy logic in `cpp_core/` (Layer 2) pure and deterministic so the same code feeds
   the backtester and later the MQL5 EA.

## Acceptance
- Costs explicitly modeled and documented.
- Vectorized and tick-engine results are directionally consistent.
- Trade log reproducible (deterministic); metrics committed.

Next: `/quant-8-sensitivity`. See `docs/KENKEM_QUANT_OS.md` §5, §7 (Phase 7).
