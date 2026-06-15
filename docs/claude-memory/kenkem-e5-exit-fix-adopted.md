---
name: kenkem-e5-exit-fix-adopted
description: "The adopted KenKem-E5 exit-geometry fix — one consensus config flips E5 loss→profit on the tick engine (BTC PF 1.07, XAU 1.08), DD crushed. Locked into best_kenkem_E5_{btc,xau}.set."
metadata: 
  node_type: memory
  type: project
  originSessionId: 7a1eb88f-45d3-4c38-a631-c4b3849127c0
---

**Fix for [[kenkem-e5-root-cause-exits]], applied & adopted 2026-06-15.** Swept the four ProfitManager
(C5) exit knobs × `E5_MAX_EMA_CROSS_AGE{1,2,3}` on the **canonical TICK engine, 2026 OOS, BTC+XAU**
(`research/optimization/sweep_e5_exits.py`, 324/sym + refinement), ranked by OOS PF. See [[bar-engine-systemic-defect]]
(why tick, not bar) and [[perf-table-format]] (the 9-col table).

**Surface:** `E5_PARTIAL_TP_TRIGGER` is the dominant lever — monotonic PF gain 0.22→0.95 at every maxage
(early partial @0.28R scratched winners; pushing it to ~0.95 ≈ 1.22R lets winners ride to TP). Plateau
pt∈{0.93,0.95,0.97} is flat on both symbols (robust, not a peak); a tiny late partial @0.95 even beats
partial-OFF (same PF, lower DD). **Only maxage=1 clears PF>1** (age 2/3 stay ≤1.0 with ~1.7× DD).
ratio/BE/trail are near-inert once the trigger is late.

**ADOPTED (one consensus config wins both symbols → clean MQL5 port), locked into
`research/optimization/best_kenkem_E5_{btc,xau}.set` (entry params untouched):**
`E5_MAX_EMA_CROSS_AGE=1 · E5_PARTIAL_TP_TRIGGER=0.95 · E5_PARTIAL_TP_RATIO=0.476 ·
E5_SL_TO_BREAKEVEN_BUFFER=0.05 · E5_TRAILING_SL_FACTOR=1.2`

| | Net | PF | Recovery | MaxDD | Sharpe | Tr/day |
|---|--:|--:|--:|--:|--:|--:|
| BTC before | −26,440 | 0.714 | −1.00 | 26,440 | −7.10 | 9.9 |
| BTC after  | +2,637  | 1.074 | 0.75  | 3,531  | +1.12 | 2.2 |
| XAU before | −4,564  | 0.806 | −0.83 | 5,480  | −3.26 | 3.5 |
| XAU after  | +897    | 1.080 | 0.37  | 2,420  | +0.84 | 1.0 |

**Honest read:** PF is now clearly >1 but THIN (~1.07–1.08); the real win is the sign flip + DD crush
(BTC 7.5×, XAU 2.3×) + Sharpe positive. Adoption rule (net UP ∧ DD DOWN) satisfied on both.

**MQL5 fidelity:** all five knobs are real EA inputs. `E5_PARTIAL_TP_TRIGGER` maps 1:1 to the EA's
default-active standard partial path (`partialTPTrigger` / `TakePartialProfitAsNeeded`;
`ENABLE_CONSERVATIVE_TRADE_MGMT=false` so the R-ladder is off). At trigger 0.95 the partial/trail
seldom fire → dquants chandelier-trail vs EA-trail divergence shrinks (path-dependence converges).

**Data regen (gitignored CSVs):** `~/miniforge3/envs/kenkem/bin/python cpp_core/tools/common/export_kenkem_oos.py`
builds M1 BID bars (warmup = 2025+2026 concat) + 2026 tick windows from the Parquet store. Run config:
`--from-ms 1767225600000 --warmup 300`, BTC `bars_btcusd_2025_2026_m1.csv`, XAU `bars_xauusd_2025h2_2026_m1.csv`.
NOTE: XAU 2026 parquet ends Apr 6 (34M ticks) vs the prior re-baseline's May 29 (46.7M) → XAU baseline
reads 0.806 here vs 0.889 there; BTC reproduces exactly (PF 0.714, 1581 tr).

**Remaining for promotion:** (1) the deployed EA `.set` uses `Inp*` names that `load_set` silently ignores
and whose values differ from the validated UPPERCASE set — reconcile before trusting MT5 (see
[[kenkem-config-lie-fixed]]); (2) IS-2025 re-check not yet run (scoped to 2026 OOS). Commit `da6f270`.
