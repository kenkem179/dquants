---
name: kenkem-executor-parity-gaps
description: "KenKem's C++ tick executor is NOT a faithful port of the KenKem EA TradeManager — concrete trail/BE/anti-churn divergences. The fix is to unify all strategies onto ONE configurable common executor. User directive 2026-06-15."
metadata: 
  node_type: memory
  type: project
  originSessionId: 7a1eb88f-45d3-4c38-a631-c4b3849127c0
---

**User directive (2026-06-15):** "I want parity tick by tick for ALL strategies … just fix the common
module to fix all at once." The parity gap is systemic → fix the SHARED execution layer, not per-strategy
params. See [[bar-engine-systemic-defect]] (use tick engine) and [[kenkem-e5-exit-fix-adopted]] (the E5
sweep was on the divergent executor below — direction holds, exact numbers won't reproduce in MT5 yet).

**Architecture finding:** MasterVP + Monster both run on the shared, MT5-validated
`cpp_core/include/kk/common/position_manager.hpp`. **KenKem is the ONLY strategy that reimplements its own**
`kk/kenkem/trade_manager.hpp` + `engine.hpp` + `exits.hpp` — so every fill bug is replicated and KenKem is
the unvalidated outlier. Indicators are ALREADY shared (`kk::ind` EMA/ATR/ADX/RSI, MT5-validated via
MasterVP); only Ichimoku (E4-only) is KenKem-specific. **The split is execution-only.**

**Concrete divergences: KenKem C++ executor vs the KenKem EA TradeManager.mqh (the real source of truth):**
- **Trail distance.** EA `CalculateTrailingSLForTrade` (TradeManager.mqh:886): dist =
  `|originalTP-entry| × trailingFactor / (tpExtensions+1) × GetVolatilityMultiplier()`, trailed off
  `bestPrice`, with a **1-pip min-change anti-churn** + broker stops-level clamp. C++ (`trade_manager.hpp:87`):
  `best - trailing_factor × risk`, **no** TP-dist base, **no** vol-mult, **no** anti-churn. (Trail base differs
  by ~RR× since TPdist = RR·risk.)
- **BE after partial (E5).** EA (TradeManager.mqh:709-712): `entry ± 2×spread` ("Pine SuperBros parity"),
  fires immediately on partial. C++: `entry + e5_be_buffer × risk` → **the `E5_SL_TO_BREAKEVEN_BUFFER` knob is
  ignored by the real E5 EA.**
- **Partial trigger basis.** EA (TradeManager.mqh:687): `currentPnL ≥ partialTrigger × origTPdist` = FRACTION
  of TP distance (per-entry `GetPartialTPTrigger`, default 0.65). C++ matches (fraction) — GOOD. NOTE the
  common `position_manager` uses an R-MULTIPLE basis → wrong for KenKem, right for MasterVP ⇒ the unified
  module must be CONFIGURABLE per strategy.
- **Each MQL5 EA has its OWN TradeManager** (KenKem's ≠ KK-Common's). So "one common module" = ONE
  *configurable* C++ executor (trail-base mode, vol-mult, BE mode, anti-churn step, partial basis) whose
  config reproduces EACH EA, verified against EACH EA's MT5 reference.

**MT5 reference data:** only MasterVP/Monster have per-trade CSVs
(`kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/KK-MasterVP-Monster/trades_*.csv`). **No KenKem MT5 ref
exists** → KenKem's final tick-parity proof needs one instrumented MT5 run (compile via
[[mql5-compile-workflow]]). Until then KenKem parity = faithful PORT of the EA source, not a measured diff.

**Plan:** (1) parity-diff harness vs the MasterVP/Monster MT5 refs = the oracle + regression guard;
(2) extend `kk::common::PositionManager` with per-strategy config modes (trail base/vol-mult/BE/anti-churn/
partial basis) defaulting to current behavior (MasterVP/Monster untouched); (3) migrate KenKem onto it
(panic/score-drop + multi-entry stay engine-level); (4) verify MasterVP/Monster unchanged vs refs, report
KenKem before/after; (5) generate a KenKem MT5 ref to close the proof. Gap analysis done via Explore agent.
