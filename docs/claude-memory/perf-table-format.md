---
name: perf-table-format
description: Standing format for EVERY strategy performance-comparison table (9 required columns)
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f545676d-24f2-4e38-ad66-13bea0e20c11
---

When showing any performance-comparison table across strategies/configs, ALWAYS include these 9 columns
(user directive 2026-06-14):

1. Strategy name
2. Settings — the toggle state, spelled out (e.g. "E1 only, Profit Manager: ON, Risk manager: ON, Adaptive: OFF")
3. Symbol, Timeframe (e.g. "BTCUSD M1")
4. Net Profit
5. Profit Factor
6. Recovery Factor (= net / maxDD)
7. Maximum Drawdown
8. Sharpe Ratio
9. Number of trades/day

**Why:** the user reads these like an MT5 report and compares strategies on a fixed scorecard; missing
columns (esp. Recovery Factor, Sharpe, trades/day) make configs non-comparable.

**How to apply:** the base `metrics()` in sweep harnesses only emits n/net/pf/dd. Use the extended
reporting tool (`research/optimization/report_metrics.py` — full_metrics adds recovery, annualized daily
Sharpe, trades/day) when producing comparison tables. Always show both IS (2025) and OOS (2026) where
relevant. Related: [[kenkem-distilled-result]].
