---
name: kenkem-distilled-result
description: KenKem was distilled to E4-only (Ichimoku TK cross); validated edge BTC OOS PF 1.24 / XAU 1.08
metadata: 
  node_type: memory
  type: project
  originSessionId: 67691271-7127-41af-98bb-1c0f44816ec8
---

KenKem port pivoted (user directive 2026-06-14): distill the bloated ~9.7k-LOC EA to its essential
winning core rather than byte-reproduce it. Built `kk::kenkem` C++ engine (config→tf_cache→triggers→
snapshot→gates→entries→trade_manager→engine, 8 unit tests / 131 checks) + `tools/kenkem/backtester.cpp`
+ `optimize_kenkem.py`. Validation = quant SOP (NOT MT5 byte-parity, which the distillation makes moot).

**Key finding:** Optuna disabled E1 (EMA-stack cross) and E2 (EMA75 pullback) — they added drawdown
without edge. **The robust strategy is E4 ONLY: the Ichimoku Tenkan/Kijun cross**, gated by high ADX
momentum (~26) + MTF DI alignment + sideways block + M5/M15 HTF filter; tight ATR-capped structure SL,
RR ~1.7, partial-TP ~53% then 0.27 chandelier trail. Note: the EA reads iIchimoku buffers 0/1 as the
"cloud" = actually Tenkan/Kijun (mislabel), so E4's trigger is a TK cross. See [[kenkem-parity-traps]].

**Validated numbers** (fixed-fraction sizing $10k, costs modelled):
- BTC: 2025 PF 1.270 (test-split 1.201) → **2026 true-OOS PF 1.239** net +$61k DD $8.6k win 57%.
  MC 5000 bootstraps 100% profitable, PF-P5 1.164. Spread-robust to $6 (PF 1.173).
- XAU: 2025 PF 1.207 → **2026 OOS PF 1.083** net +$14k.

Artifacts: `research/optimization/best_kenkem_{btc,xau}.set`, `KENKEM-RESULTS.md`, bars
`cpp_core/tools/bars_*_{2025,2026}_m1.csv`. Engine on branch 1-reorganize-code.

**Next:** compare vs Monster + MasterVP OOS → pick #1 → promote to production MQL5 (the user's end-goal,
see [[milestone-production-promotion]]). KenKem-distilled deploy = a NEW thin EA matching this engine's
E4 logic + sizing (the existing EA differs).
