---
name: milestone-production-promotion
description: "End-goal — after KenKem port+optimize, pick the"
metadata: 
  node_type: memory
  type: project
  originSessionId: 67691271-7127-41af-98bb-1c0f44816ec8
---

The user's stated end-goal (2026-06-14): complete the FULL quant pipeline. After the KenKem port +
optimization finishes, **recommend the single #1 candidate across KK-MasterVP / Monster / KenKem** to
promote to production MQL5 — built from this dquants repo using our own infrastructure.

**How to do the promotion (user-authorized):** carefully hand-pick the symlinks/scripts/tooling from the
sibling `../kenkem` repo (his pre-dquants MQL5 codebase, already in this Claude session's working dirs)
for: compiling MQL5, deploying to MT5, reading tester logs/results, and extracting result params. Reuse
what already works rather than reinventing.

**Bar the user set:** "world class MQL5 code with zero mistakes in dealing with brokers, risks and
anything else to be deployed seamlessly to Production on MT5." So the promotion must be broker-spec-exact
(pip/contract/min-lot per symbol), risk-correct, and parity-proven before it ships.

**Why:** this closes Layer 4 of the architecture — the whole point of the C++ work is a thin, correct EA.
**How to apply:** don't start promotion until KenKem is parity-validated + optimized; then compare the
three strategies' optimized OOS results and recommend one with rationale. Relates to [[real-target-kenkem-strategies]]
and [[milestone-mt5-confirmed-optimization]].

**DECIDED (2026-06-14):** recommended **KenKem-distilled E4** as #1 (BTC primary, XAU secondary).
Rationale: most rigorous OOS (full fresh year 2026 H1, PF 1.239 vs others' 1–2 month same-year windows),
best robustness (MC 100% prof, P5 PF 1.164, spread-robust to $6), simplest logic (one Ichimoku TK entry →
cleanest "zero-mistake" code). Runner-up Monster-XAU (higher raw PF 1.276 but softer OOS); MasterVP only
MT5-proven but weakest edge. **Delivered:** production EA `kenkem/MQL5/Experts/KK-KenKemE4/KK-KenKemE4.mq5`
(single-file, CTrade-based) + README. Left UNCOMMITTED in the kenkem production repo for user review.
**UPDATE 2026-06-14 (later):** Built multi-entry `KK-KenKem.mq5` (E1/E2/E4/E5 toggleable; handle creation
guarded by toggles so off-entries cost zero), added the stops/freeze clamp on entry SL/TP + BE/trail
modifies, and **COMPILED IT CLEAN — 0 errors, 0 warnings** (via [[mql5-compile-workflow]] — I can compile
freely now). Robustness on OUR engine (no MT5 needed): BTC E1+E4+E5 6/6 months +ve / MC 100% / PF-P5
1.096; XAU E4+E5 5/5 +ve / MC 99.8%. Every entry +ve OOS; E5 (SuperBros) strongest leg. See
[[kenkem-distilled-result]].

**ARCHITECTURE (user-agreed):** keep strategies as SIBLING EAs (KenKem / KK-MasterVP / KK-Monster); share
reusable modules via ONE FLAT `KK-Common` include lib — partition by MODULE not family (DMI/ADX/ATR/RSI
used by both families; Ichimoku=KenKem-only, VolumeProfile=VP-only). `KK-Common` ALREADY EXISTS in kenkem
repo: Utils/BrokerHelpers, TradeManagement/{RiskManager,TradeManager}, Core/IndicatorCache, SessionManager,
Logging/TradeJournal. Compile-time module exclusion REJECTED as over-engineering (runtime guarded handles
already capture the win). NEXT step (after user OK): refactor KK-KenKem to `#include <KK-Common/...>`
(proof), then move MasterVP/Monster onto it. Final gate stays: demo forward-test.
