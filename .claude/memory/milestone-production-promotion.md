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
