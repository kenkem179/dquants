---
name: rnd-volume-features
description: "Results of the 'volume never lies' R&D features (F1 net-volume persistence, F2 node-structure SL/TP) per engine"
metadata: 
  node_type: memory
  type: project
  originSessionId: 35fbde55-89b4-4144-9fa7-95c311572ed0
---

R&D track on the dquants C++ engines (user: "volume never lies"; test on VP engines first, then port to
KenKem). **Adoption rule (user, autopilot): only commit results that BEAT the feature-OFF baseline — never
let a worse `.set` into production.** Inert default-OFF engine code is fine to commit (foundation); only the
locked `.set` toggles flip ON when a sweep strictly wins (PF↑ AND net↑, DD not materially worse, OOS not
degraded). Sweep tooling: `research/optimization/sweep_{mastervp_f1,monster_f2}.py` + `eval_{mastervp,monster}.py`.

**Feature #1 — multi-bar net-volume persistence-entry + N-bar flip-exit:**
- Monster (prior session): persistence-entry HELPED BTC **PF 1.299→1.618**, XAU restored, flip-exit OFF. Committed.
- MasterVP (2026-06-14): implemented inert in `kk::vp` TickEngine (`311b09e`), then **sweep REJECTED both
  symbols.** BTC marginal PF 1.204→1.239 but net flat (+$22), DD +32%, OOS PF 1.044→1.016, best params
  degenerate (persist bars=1/min≈0 = inert gate) = noise. XAU strictly worse **PF 1.737→1.520, net halved**.
  → **F1 is ENGINE-SPECIFIC** (helps Monster-BTC, hurts MasterVP). MasterVP `.set` left unchanged; code kept
  inert for a possible cross-broker revisit. KenKem port now speculative (test-only, adopt only if it helps).

**Feature #2 — volume-node STRUCTURE SL/TP (HVN/LVN shelves vs blind ATR-SL / RR-TP):** net **1 win / 4 combos.**
- **Monster BTC → ADOPT** (the one win): structural-TP2 ON (hvn_sl OFF) improved EVERY metric — PF 1.617→1.645,
  net 2740→2901, DD 293→270 (better), OOS PF 1.676→1.720 (better). Params HvnFrac 0.637/EdgeOff 0.125/
  MinRr 1.10/MaxRr 2.51. Applied to `best_monster_real_btc.set` (`1135fd8`). HVN-shelf SL underperformed.
- **Monster XAU → REJECT** (PF 1.321→1.284), **MasterVP BTC → REJECT** (1.204→1.201 flat), **MasterVP XAU →
  REJECT** (1.737→1.551). Added `kk::vp` NodeEngine::structural_tp inert (`67a470b`) for the MasterVP test;
  MasterVP's chandelier trail already exits well so a fixed structural TP cuts winners short. `.set` unchanged.
- KenKem node-structure TP **skipped** (1/4 hit rate → low EV on a trend strategy).

**DeferredEntry (pullback/limit entry) — REJECT both:** ported `KK-Common/DeferredEntry.mqh` → C++ `kk::vp`
TickEngine (arm virtual limit at entry∓pullback*ATR, fill within defer_bars per tick, else expire), inert
default OFF (`ec44fd4`). Sweep (`sweep_mastervp_defer.py`): **BTC** net +38% ($4325→$5984) & OOS better BUT
**DD +62%** (1119→1809) ⇒ risk-adjusted net/DD 3.86→3.31 WORSE (gain is inflated lot size from the
keep-SL-price design, not a cleaner edge). **XAU** outright worse (PF 1.737→1.667). Rejected on the
"never ship a worse risk profile" bar. **Possible refinement:** a keep-RISK-constant variant (move SL with
entry) = better R without size inflation — not pursued.

**FINAL R&D SCORECARD (2026-06-14):** of F1 / F2 / DeferredEntry across BTC+XAU on MasterVP+Monster, the only
clean adopted win is **Monster-BTC structural-TP2** (F2). Everything else marginal/engine-specific or
risk-adjusted-worse → `.set` files unchanged except `best_monster_real_btc.set`. All 3 features live as inert,
tunable, tested toggles for a future cross-broker revisit ([[cross-dataset-harness]]). The takeaway: the VP
engines' existing exits (chandelier trail) + edges are hard to beat with these micro-features. **F1/F2-KenKem
skipped** (1-of-5 / 1-of-4 hit rates → low EV on a trend strategy). Sweep tooling: `sweep_{mastervp_f1,
mastervp_f2,mastervp_defer,monster_f2}.py` + `eval_{mastervp,monster}.py`. Verdict criteria in scripts are
LOOSE (PF↑/net↑ only) — apply risk-adjusted judgment (net/DD, OOS, DD) manually, as done here.
See [[milestone-production-promotion]] for the R&D plan and [[cross-dataset-harness]] for broker-robustness
validation of any adopted feature.
