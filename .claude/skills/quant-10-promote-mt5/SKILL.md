---
name: quant-10-promote-mt5
description: Phase 10 of the KenKem Quant OS SOP — promote a validated C++ strategy core into a thin MQL5 Expert Advisor with forward-test plan. Use only after walk-forward + Monte Carlo pass.
---

# Phase 10 — Promote to MT5

The final step. Only run after a strategy passes the full validation chain (§7 of the master plan).

## Input
A validated strategy whose logic lives in `cpp_core/` (Layer 2, pure C++20).

## Output
- A `Strategy` subclass in `cpp_core/` with deterministic unit tests (`cpp_core/tests/`).
- A thin MQL5 EA in `mql5/experts/` + shared `mql5/include/`.
- A forward-test plan (demo/VPS) in `docs/`.

## How
- Keep all decision logic in C++ (Layer 2). Port only the **pure functions** —
  `LongSignal/ShortSignal/CalculateSL/CalculateTP` — into MQL5; they translate ~1:1.
- The EA is thin: `OnTick() → Strategy.Update() → if LongSignal() OrderSend(...)`. MT5-specific calls
  (`OrderSend/PositionSelect/CopyRates/iATR`) live **only** here (Layer 4).
- **Verify parity:** the MQL5 EA must produce the same signals as the C++ core on the same ticks before
  it is trusted.

## Acceptance
- C++ unit tests + tick backtest pass deterministically.
- MQL5 EA reproduces C++ signals on identical tick data (parity check).
- Risk controls + logging present; demo forward-test plan written.
- MT5 Strategy Tester used only as a final sanity check, never as the source of truth.

See `docs/KENKEM_QUANT_OS.md` §1, §5, §7 (Phase 10).
