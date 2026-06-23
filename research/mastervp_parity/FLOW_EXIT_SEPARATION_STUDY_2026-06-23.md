# Volume-flow conditioned exit — separation study (Step 0, 2026-06-23)

**User challenge:** the unconditional profit-locks (Ladder/Floor/trail/partial) all lost in MT5 because
they tax every winner. A *conditioned* exit — bank only when volume-delta shows the move is reversing —
is a different category and might flip the sign. The Profiler's net delta (`tickCount × (c−o)/(h−l)`)
is the proposed signal. **Question: does net-flow actually SEPARATE winners that round-trip to BE from
genuine runners?** If yes, the prior WF rejection was an engine-net-P&L-bias artifact and we have an edge.
If no, the signal is dead and we stop.

## Method — unbiased path geometry (not net P&L)

New engine instrumentation `backtester --flow-path-out` (commit pending): one row per open-trade per
closed bar = {unreal_r, mfe_r, net_flow, node_net} + a per-trade summary row with the TRUE intrabar exit_r
(`PositionManager::exit_r`, added because last-closed-bar R misses the intrabar BE/trail giveback).
Analysis `flow_separation_2026-06-23.py` measures, in **pure R units** (no net-P&L, so no runner
over-crediting bias): for a flip/divergence exit rule, the R it BANKS vs the R the trade actually ended at,
split into round-trippers (peak≥1R, end≤0.15R) and runners (end≥1R).

**Validity checks (both pass):**
- Baseline giveback reproduces the study: **46.8%** of ≥1R winners end ≤0.15R (prior figure 45.3%). ✓
- The aggressive flip rule's geometry (rescue +93R / cost −207R → net −45R) **matches the MT5 Ladder
  result (−27% net)** — the unbiased geometry independently reproduces live MT5. ✓ The method is sound.

## Result — the signal does NOT separate (XAU M5, deployed lock, full year, 1350 trades)

Two signal forms tested: (A) **against-flow** — net_flow against the position for K consecutive closed
bars; (B) **divergence** — price new-high but net_flow lower-high. Both swept over arm-R / sensitivity.

| Form | Sensitive setting | Conservative setting |
|---|---|---|
| Against-flow | rescue **+93R** / cost **−207R** → net **−50R** | rescue **+2R** / cost ~0 → net **+7R** (noise) |
| Divergence | rescue **+41R** / cost **−137R** → net **−52R** | rescue **+0R** / fires on nothing |

**The iron asymmetry: across BOTH signals and EVERY tuning, runner-cost > round-trip-rescue.** To catch
the round-trippers you must fire sensitively — but then you cut the runners 2–3× harder. To protect the
runners you fire conservatively — but then you catch almost no round-trippers (the giveback already
happened). The only "positive" cells (+4 to +8R over 583 winners ≈ 0.01R/winner) are noise cherry-picked
across 36–16 combos and would be annihilated by the overfitting gate.

## Why (the structural reason)

A healthy continuation pullback and a terminal reversal **look the same in volume flow** — both print
against-direction bars as price pulls back. net_flow is not specific to reversals, so any threshold that
fires on round-trippers also fires on the temporary dips inside genuine runners. The strategy's edge *is*
the fat tail; round-trippers are indistinguishable from runners at the moment of the pullback — by price
(MT5 A/B proved it) AND by flow (this study proves it). This is consistent with the prior WF rejection of
`enable_conviction_protect` / `enable_net_flip_exit`, but now established on UNBIASED geometry, not the
engine's runner-over-crediting net P&L.

## Verdict & implication

**REJECT the volume-flow conditioned exit.** Not a tuning miss — structural. The round-trip-to-BE is real
(47%) but it is **opportunity cost, not capital risk**: the BE stop (armed at 0.8R) already protects the
account; the round-trippers exit at ~0R, not at −1R. Account *safety* is handled by the BE arm; what the
giveback costs is unrealized profit, and every method tried (mechanical AND flow-conditioned) costs more
net than it saves on XAU. The one place protection helps is BTC M5 (tail is fictional on the noisy feed) —
already captured (MT5 Ladder +51%, [[mastervp-profit-lock-ladder]]).

**Limitation (stated honestly):** this falsifies single-pass flip/divergence rules on net_flow and node_net
(the signals the user pointed at). A richer multi-feature classifier *might* separate — but that is exactly
the overfitting surface the gate punishes, the prior node_net classifier already failed WF, and the
rescue<cost asymmetry holds across all tunings, so the structural read is the honest one.

## Repro
- `make -C cpp_core backtester`
- `cpp_core/build/backtester --bars …m5.csv --ticks ticks_xau_full.csv --set-all …xau_m5_LOCKED.set
  --symbol-xau --out trades.csv --flow-path-out flowpath.csv`
- `python3 research/mastervp_parity/flow_separation_2026-06-23.py flowpath_xau_m5.csv`
- Raw: `research/mastervp_parity/flow_study_2026-06-23/`
