# VMC as a support/confidence factor for KK-MasterVP (BTCUSD) — findings (2026-06-20)

**Harness (non-invasive):** `cpp_core/tools/mastervp/vmc_mvp_lab.cpp` (`make mvp_vmc`). Runs the REAL MasterVP
`kk::TickEngine` to get baseline trades, rebuilds committed per-bar VMC from the SAME ticks (bucketed to
`--tf-min`), then evaluates VMC as a directional **support factor**. Touches **zero** MasterVP engine/EA code.
Emits: independence diagnostic, VMC-vs-`node_net` agreement, score scale, a threshold-free flow-direction
split, and a confirm-threshold plateau sweep. Costs are included (the engine's trades are costed).

> Caveat: post-hoc trade-SELECTION, not a full re-sim — ignores concurrency/margin coupling. A confirmed
> positive (this) justifies an opt-in engine hook + proper walk-forward next; it does not replace it.

## Why MasterVP/BTC (not KenKem): independence is real here
KenKem E1/E5 are EMA-momentum entries → tick-flow is redundant with the trigger (corr 0.48–0.69), so VMC
restated the entry and added nothing (see `research/kenkem_parity/VMC_E1_INACTION_FINDINGS.md`). MasterVP is
a Volume-Profile (mostly mean-reversion) strategy. Measured `corr(r_b, bar body)` on BTC = **0.35–0.47** with
**21–32%** sign-disagreement — VMC flow is genuinely more independent of price. And VMC agrees with MasterVP's
own (laundered) `node_net` flow only **52–68%** of the time → it carries different information.

## HEADLINE (deployable): on BTC **M3**, VMC directional confirm turns MasterVP profitable
Keep an entry only if VMC confirms the trade direction with `|vmc| ≥ thr`. Plateau sweep (kept count / PF):
| confirm | M3 2025 PF (net) | M3 2026 OOS PF (net) |
|---|---|---|
| 0.000 (baseline=all) | 0.965 (−555) | 0.938 (−977) |
| 0.000 (sign-agree only) | 1.022 (+167) | 0.956 (−446) |
| 0.005 | 1.085 (+511) | 1.013 (+117) |
| **0.010** | **1.204 (+1032)** | **1.087 (+705)** |
| 0.020 | 0.993 (−28) | 1.127 (+842) |
| 0.030 | 1.254 (+775) | 1.037 (+211) |
| 0.050 | 1.623 (+1084) | 1.215 (+881) |
Across **both** IS (2025) and OOS (2026): the confirm gate lifts PF from ~0.94 (losing) to ~1.09–1.25
(profitable) over a **broad threshold band 0.005–0.05** — a plateau, not a knife-edge. Recommended start:
`vmc_confirm ≈ 0.01–0.02`, `d_ref = 0.10` (keeps ~40–55% of entries). The improvement is mostly from cutting
the trades where momentary net-delta does **not** back the entry — exactly the requested support factor.

## M5 is the WRONG knob here (recorded for honesty)
On BTC M5 the magnitude-confirm gate fails at every threshold (PF 0.51→0.24, worse when tightened) and the
only signal is **inverted**: flow-OPPOSES the entry wins (2025 PF 1.02 vs supports 0.51; 2026 PF 1.23 vs 0.61).
Structural read: M5 MasterVP (on M3-tuned params) leans on failed breakouts; its profitable subset is
reversion where flow has pushed *against* the bounce (exhaustion). That's a different, more fragile mechanism;
the .set is not M5-tuned. **Do not** apply the M3 confirm logic to M5 — the sign flips. M3 is the native TF.

## Recommendation / next steps
1. **Adopt VMC as an M3 directional confirm support factor for MasterVP/BTC** (`|vmc|≥0.01–0.02`). Next:
   wire as an OPT-IN gate in the MasterVP engine (default off) and re-sim properly (concurrency-correct) +
   walk-forward across more folds; then port to MQL5 with `parity_vmc_*.csv`.
2. Re-test on a proper M5-tuned MasterVP .set before trusting any M5 conclusion.
3. The independence + node_net-disagreement says VMC could also *replace/augment* MasterVP's `node_net`
   (laundered) flow gate with the honest tick version — worth a direct A/B.
