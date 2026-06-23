# Reversion: fade LOCAL VP vs MASTER VP — WF study (2026-06-23)

**User's standing assumption** (open in HANDOFF/BUILD-PLAN as the last untested MasterVP lever): mean-
reversion is a *tactical* fade in a balance regime, so it should reference the **near-term LOCAL value
area**, not the slow 480-bar **MASTER** VP. The code faded master on both the entry trigger (touch of
master VAH/VAL) and the mPOC target (`master_cur.poc`).

## What was built (engine, default-OFF, base byte-identical)

Two separable switches in `kk::Params` (`config.hpp`), parsed as `InpRevEntryLocal` / `InpRevTpLocal`,
wired in `strategy.hpp`:
- `rev_entry_local` — the reversion touch trigger keys off **local** VP edges (`local_cur.val/vah`,
  the `vp_lookback`-bar window = 120 bars on XAU M3) instead of the master edges.
- `rev_tp_local` — the `rev_tp_mpoc` magnet targets the **local** POC instead of the master POC.

Both default `false` ⇒ they collapse to the master values ⇒ byte-identical. `make test` 37/37 incl.
golden parity; baseline WF row shows `rev=0` (reversion OFF = the deployed lock).

## Result — XAU M3, 6-fold walk-forward (reversion lives only on XAU M3)

Baseline = the lock, reversion OFF: **PF 1.108 / net $11,642 / dd 24.6% / 4-of-6 folds+ / worstPF 0.861.**

| Reversion form (rev ON, TpMpoc, TrailRev=0) | rev tr | revNet | PF | net | dd | folds+ | worstPF |
|---|---|---|---|---|---|---|---|
| master edge + master POC *(prior candidate)* | 107 | −465 | 1.065 | 6,998 | 31.6% | 4/6 | 0.793 |
| master edge + local POC | 106 | −558 | 1.084 | 8,849 | 24.6% | 4/6 | 0.790 |
| local edge + master POC | 266 | −1,189 | 1.061 | 6,829 | 25.2% | 4/6 | 0.871 |
| **local edge + local POC** *(user's full idea)* | 270 | **−431** | 1.083 | 9,280 | **22.4%** | **5/6** | 0.860 |

## Two findings

1. **The user's assumption is DIRECTIONALLY CORRECT.** Fading the local value beats fading the master
   on every robustness axis: the full-local variant improves the prior master-fade candidate's net
   $6,998→$9,280, dd 31.6%→**22.4%**, folds+ 4→**5/6**, worstPF 0.793→0.860, and is the least-negative
   reversion sub-book (revNet −465→−431). Local edges are touched far more often (107→270 rev trades) and
   the local POC is a nearer, more-reachable magnet (the humble-bank effect that trims DD). **If reversion
   is ever enabled on MasterVP, the local form is the right one — not the master form the prior
   "rev @ mPOC trims DD 17.5→13.5%" single-window candidate used.**

2. **But reversion still does NOT earn its place — REJECT for lock.** In EVERY form the reversion
   sub-book is *negative-expectancy* (revNet −431 to −1,189): the reversion trades themselves lose money.
   Baseline (breakout-only) beats all five variants on net ($11,642 vs best $9,280, −20%) and pooled PF
   (1.108 vs 1.083). The best variant's only edge is a 2.2pp dd trim (24.6→22.4%) + one extra positive
   fold — but you get a bigger dd cut for free by simply sizing the baseline down, while keeping the
   net. The prior single-window "rev @ mPOC trims DD 17.5→13.5%" was survivorship: under 6-fold WF the
   **master**-POC reversion is actively net-harmful (dd 31.6% — WORSE than baseline). Only the LOCAL
   form even recovers the DD benefit, and it still costs 20% of net.

## Verdict

**Keep reversion OFF on MasterVP (all markets).** The local-VP switches ship as tested default-OFF infra.
No lock, so no overfitting-gate run (a config that loses to baseline on net+PF cannot be a lock). This
**closes the last open MasterVP research lever** — VP-length, FVG-SL, TP1-partial, move-SL, conviction-
protect, flow-conditioned exit, and now local-vs-master reversion have all been tested and rejected.
The breakout trend-runner is the edge; every overlay that taxes or dilutes it has come up empty.

## Repro
- `make -C cpp_core test && make -C cpp_core backtester`
- `python3 research/mastervp_parity/wf_t3.py --config xau_m3 --tag revlocal --show-folds \
   --grid '{"InpEnableReversion":["true"],"InpRevTpMpoc":["true"],"InpTrailRev":["0"],"InpRevEntryLocal":["false","true"],"InpRevTpLocal":["false","true"]}'`
