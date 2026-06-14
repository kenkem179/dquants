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

**Entries are a toggleable MENU** (user corrected my over-pruning — E5/SuperBros belongs in KenKem and
was wrongly skipped; it's the BEST standalone). Standalone BTC-2025 PF: E5 1.147 / E4 1.090 / E1 1.064 /
E2 1.036 — all profitable. E5 = fresh STRICT M1 4-EMA alignment onset + price>EMA25, sideways+HTF only
(no hard gate), SL at EMA200. E4 = Ichimoku Tenkan/Kijun cross (the EA mislabels iIchimoku buffers 0/1
as "cloud" = really TK lines; see [[kenkem-parity-traps]]).
Optimized COMBINATIONS (2026 true OOS): BTC E4-only PF 1.239 (max PF) OR E1+E4+E5 PF 1.145/+$79k (max
net); XAU E4+E5 PF 1.132 (beats E4-only on both PF & net — E5 helps XAU). E2 rarely makes the cut.

**Validated numbers** (fixed-fraction sizing $10k, costs modelled):
- BTC: 2025 PF 1.270 (test-split 1.201) → **2026 true-OOS PF 1.239** net +$61k DD $8.6k win 57%.
  MC 5000 bootstraps 100% profitable, PF-P5 1.164. Spread-robust to $6 (PF 1.173).
- XAU: 2025 PF 1.207 → **2026 OOS PF 1.083** net +$14k.

Artifacts: `research/optimization/best_kenkem_{btc,xau}.set`, `KENKEM-RESULTS.md`, bars
`cpp_core/tools/bars_*_{2025,2026}_m1.csv`. Engine on branch 1-reorganize-code.

**Next:** compare vs Monster + MasterVP OOS → pick #1 → promote to production MQL5 (the user's end-goal,
see [[milestone-production-promotion]]). KenKem-distilled deploy = a NEW thin EA matching this engine's
E4 logic + sizing (the existing EA differs).
