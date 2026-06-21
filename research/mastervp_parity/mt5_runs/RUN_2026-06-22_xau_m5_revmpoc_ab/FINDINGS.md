# KK-MasterVP XAU M5 — RevMpoc A/B (2026-06-22): confirms reversion@mPOC HURTS

A/B vs the XAU M5 base lock. Both real-tick $10k, 2025.01→2026.06.09. Differ ONLY in reversion-exit:
base `InpTrailRev=-1` (inherit → runner-trail) vs RevMpoc `InpTrailRev=0` (bank at mPOC).
Final balance: base **$94,594** vs RevMpoc **$89,086**.

| slice | BASE (runner-trail) | REVMPOC (banked@mPOC) |
|---|---|---|
| FULL | PF 1.341 / +84,663 / dd $11,615 | PF 1.321 / +79,157 / dd $10,795 |
| OOS 2026 | PF 1.393 / +44,589 | PF 1.370 / +40,585 |
| REV-only (n~75) | PF 1.081 / +760 | PF 0.800 / −1,684 (win 65.8%) |

**Verdict — MT5 confirms the engine's negative.** Banking reversion at mPOC costs −$5,506 full / −$4,004
OOS; reversion slice flips +760 → −1,684 (high win%, negative net = caps winners, lets losers run to SL).
Marginal DD trim ($11.6k→10.8k) not worth it. **Base lock stays (TrailRev=-1). RevMpoc rejected.**
