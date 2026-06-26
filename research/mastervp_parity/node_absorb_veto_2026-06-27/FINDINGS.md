# H12c — nodeNet structural-absorption veto → BUILT + ENGINE A/B (2026-06-27)

The session's one autopsy PASS (H12/H12b rejected). `nodeNet` = (buy−sell)/(buy+sell) at the BREAKOUT
PRICE from the decayed master-VP node engine; signed by direction `along = is_long ? ns_vah.net : -ns_val.net`.
Model-free autopsy (2117 calendar-2025+ lock entries): `along<0` (breaking into net-absorption-against) is
worst on every model-free axis (mfeR/reach1R/maeR), robust both years. Build candidate = skip the breakout
when `along < node_absorb_veto_min` (one-sided <0 cut, NOT a band — the ≥0 side is non-monotone = overfit risk).

## Deployability — ✅ SHIPPABLE
The decayed VP node engine is a faithful 1:1 port already LIVE in the MQL EA: `mql5/experts/VP-Common/
NodeEngine.mqh` (included by `Engine.mqh`), driven by the existing `InpNode*` inputs (`InpNodeGateEnabled/
Decay/NeutralBand/Saturation/TouchAtr`); conviction-protect already reads node state engine-side. So
`state_at_price(px).net` is computable live in MT5 → the veto is NOT engine-only; it ports to the EA as a
thin gate. (This was the open caveat from the autopsy; cleared.)

## Build (default OFF, byte-identical — verified)
- `Params::{enable_node_absorb_veto=false, node_absorb_veto_min=0.0}` (config.hpp) + parse keys
  `InpEnableNodeAbsorbVeto` / `InpNodeAbsorbVetoMin`.
- `strategy.hpp`: `brkAbsorbLongOk = !enable || ns_vah.net >= min`; `brkAbsorbShortOk = !enable || -ns_val.net
  >= min`; AND-ed into `longBrk`/`shortBrk` (breakout-only, matching the autopsy population). Reversion path
  untouched (and OFF in all locks).
- Verified default-OFF inert: HEAD-ref vs veto binary on the full XAU M5 lock → trades byte-identical
  (`diff` empty); WF harness BASELINE == `{false}` (n=1400, every fold identical). `make test` 37+240+13 green.

## Engine A/B — 6-fold WF (xau-m5, `wf_mvp_generic.py`, lock base) → DOES NOT CLEAR THE LOCK BAR
| config | pooled PF | net | maxDD | Calmar | worst-fold PF | folds+ | n |
|---|--:|--:|--:|--:|--:|--:|--:|
| BASELINE (veto OFF) | **1.330** | **23,140** | 6.4% | 3,616 | **1.279** | 6/6 | 1400 |
| veto ON (along<0)   | 1.329 | 19,285 | **4.9%** | **3,936** | 1.137 | 6/6 | 1197 |

Per-fold PF (OFF→ON): F1 1.28→1.30 · F2 1.32→**1.23** · F3 1.34→1.33 · F4 1.29→1.39 · F5 1.48→1.55 ·
F6 1.29→**1.14**. The veto removes 203 against-absorption entries.

**Verdict — REJECT for an unconditional lock (engine proxy):** pooled PF is FLAT (1.329 vs 1.330 = no PF
edge), net falls **16.7%**, and worst-fold PF DEGRADES (1.279→1.137; F2 + F6 weaken). By the repo T1 rule
(improve pooled PF AND not degrade worst-fold) it fails. What it DOES do: cut maxDD 6.4→4.9% and lift Calmar
3,616→3,936 — a **DD-reduction dial**, the same profile as the rejected XAU protection levers (better bought
via sizing, e.g. the Conservative `InpRiskAccPct` .set, without forfeiting net + worst-fold robustness).

## The honest tension (why an MT5 A/B is the legitimate tiebreaker, not auto-reject)
The MODEL-FREE autopsy (trustworthy) says these entries ARE worse (lower reach1R, bigger maeR, robust both
years). The engine WF says removing them costs net — but the **engine over-credits runner P&L** (it was
wrong-signed on giveback; [[bar-engine-systemic-defect]], [[mastervp-profit-lock-ladder]]). The net-cost of
removing entries is exactly the runner-P&L quantity the engine mis-prices → on MT5 the net cost could be
smaller (or the DD/Calmar win could dominate). DD 4.9 vs 6.4% and Calmar +8.8% are real even WITH the inflated
net cost. ⇒ Engine alone = no lock; one MT5 A/B settles whether the model-free edge + DD win survive real fills.

## MT5 A/B spec (user action — the only outstanding step)
EA `KK-MasterVP-Debug` · XAUUSD · M5 · every-tick real ticks · 2025.06.01–2026.05.29 · deposit 10k · rank PF.
Two runs off the M5 lock .set: (A) `InpEnableNodeAbsorbVeto=false` (control = the lock); (B)
`InpEnableNodeAbsorbVeto=true` (`InpNodeAbsorbVetoMin=0`). Adopt ONLY if B holds PF (≥ lock) AND improves
DD without worst-period collapse; else infra stays inert default-OFF. Do NOT sweep `InpNodeAbsorbVetoMin`
(tuning the tail = overfit, per autopsy).

Repro: `python3 research/mastervp_parity/wf_mvp_generic.py --symbol xau --tf m5 --grid
'{"InpEnableNodeAbsorbVeto":["false","true"]}' --tag h12c_veto --show-folds`.
