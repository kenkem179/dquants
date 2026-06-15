---
name: bar-engine-systemic-defect
description: dquants BAR engine disagrees with MT5 on the SIGN of P&L; use the TICK engine for any MT5-faithful number
metadata: 
  node_type: memory
  type: project
  originSessionId: 0ac8cf33-ad05-46e6-b035-547b59950dbe
---

**The dquants C++ BAR engine is a systemic measurement defect** — the likely main reason ports looked like
they underperformed their MT5 originals. Proven 2026-06-15: SAME KenKem config + window, BAR engine
(`run_backtest`, synthetic 4-point OHLC walk open→low→high→close) gave net **-2369 / PF 0.89 / win 40.2%**;
the TICK engine (`TickEngine`, real bid/ask) gave net **+5047 / PF 1.12 / win 46.9%** — opposite sign of
profitability. The tick win% matched the MT5 ground-truth 45.95%; the bar engine did not. The bar engine's
walk mis-resolves path-dependent exits (partial→BE→chandelier) and SL-vs-TP ordering. The engine header
already warned of this, yet much validation used it. **Always validate on `kenkem_tick_backtester` (needs a
`ts_ms,bid,ask` ticks CSV); treat all bar-engine numbers as research-only.** A "NOT MT5-faithful" banner was
added to the bar backtester (commit eb5897b). Re-baseline KenKem/MasterVP/Monster on ticks.

**2026-OOS confirmation (2026-06-15, commit 1f19520):** built the missing 2026 tick CSVs (BTC 15.0M / XAU
46.7M from `data/processed/ticks_*_2026.parquet`) and re-ran the locked KenKem-E5 sets through BOTH engines
on the SAME 2026-OOS window. BTC: bar PF 1.339 (+$12.9k) vs tick PF 0.718 (−$25.9k); XAU: bar PF 1.445
(+$6.5k) vs tick PF 0.889 (−$4.3k). Sign flip reproduced on the PRODUCTION config → the KenKem-E5 production
promotion is built on invalidated bar numbers (see [[kenkem-distilled-result]] correction banner). MasterVP/
Monster tick re-baseline still TODO (neither has a standalone tick engine yet — only KenKem does).

Other systemic checks (research/kenkem_parity/SYSTEMIC.md): MID-vs-BID bar basis RULED OUT (PF 1.123 vs
1.132); HTF M1→floor aggregation RULED OUT (whole-hour GMT+9 offset is bucket-invariant). The residual
**~11× over-firing** (tick full-window 1692 vs MT5's 156; right days, only 24% exact-trade overlap) is NOT
score inflation (conviction 15% of bars ≥10, TQ 6% ≥9), NOT gate leniency (max thresholds still 6×), and the
trigger is a faithful port of the EA's `UpdateEmaTouches`. It needs a **golden per-bar diff vs an
instrumented MT5 run** (dump EMAs/ADX/ATR/RSI/Ichimoku + trigger state + conviction/TQ scores for ~1 week,
diff to the first diverging bar) to localize indicator-drift vs gate-decision. /codex was auth-dead
(`refresh_token_reused` — needs `codex login`); /gemini stood in. Relates to [[kenkem-config-lie-fixed]].
