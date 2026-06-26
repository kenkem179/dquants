# H12 — Entry-flow exhaustion veto (near-price net delta) → AUTOPSY VERDICT (2026-06-27)

**User's idea:** after enough breakout trades push beyond master VAH/VAL, order flow exhausts. So a
candidate entry can be valid by price geometry (beyond mVAH/mVAL by the required ATR) yet be a trap — and
the tell is the **near-price net volume delta within ±2.4×ATR of current price**: if it's *against* the
candidate direction, skip the entry.

**Verdict: the literal mechanism does NOT validate. Built default-OFF (byte-identical), NOT swept** (per
CLAUDE.md, the edge autopsy gates the sweep, and there is no conditional edge to sweep). The infra + the
journaled `entryFlowNear` diagnostic stay in the tree for reproducibility + future structural tests.

## Method
Built the EXACT measure: `near_price_net_at()` (tf_net.hpp) = `(buy−sell)/(buy+sell)` of the `entry_flow_look`
(=50) bars whose hlc3 sits within `entry_flow_veto_atr`(=2.4)×ATR of the signal-bar close, in [−1,+1],
no-lookahead. Computed + journaled on every entry (`entryFlowNear` column). Veto (`enable_entry_flow_veto`,
default OFF) skips when net is against the trade beyond `entry_flow_veto_min`. Autopsy = the 2117 lock entries
(XAU M5, full 2025–2026, `kkmastervp_xau_m5_LOCKED.set`), bucketed by `along = efn·dir` using **model-free**
outcomes (`mfeR`, `reach1R`=P(mfeR≥1), `maeR`) — the suspect exit model is NOT trusted for the verdict.

## Result — against-flow entries are EQUAL or BETTER, not traps
Distribution of `along`: p10 ≈ 0.00, median +0.28, p90 +0.92 → near-price flow is **overwhelmingly WITH** the
breakout (the breakout bar itself dominates the 2.4×ATR window). Only ~10% of entries have any against-flow.

| bucket (thr 0) | n | mfeR | reach1R | maeR | usd/tr |
|---|--:|--:|--:|--:|--:|
| flow AGAINST | 212 | **1.306** | **46.2%** | **0.639** | +14.9 |
| flow WITH | 1903 | 1.272 | 41.8% | 0.673 | +7.1 |

Against-flow entries reach 1R favorable MORE often and have SMALLER adverse excursion. A veto removes
slightly-above-average trades. Holds at every threshold (0.05/0.1); only the |0.2| tail (n=31, 1.5%) dips on
mfeR and even there usd/tr stays positive.

**Interaction with "lateness"** (the precondition): on EXTENDED breakouts (top-quartile brkDistAtr — the late,
over-extended entries the hypothesis targets), against-flow STILL wins model-free: mfeR 1.245 vs 1.213,
reach1R 45.0% vs 41.3%. The lone "against is worse" number (extended-against usd/tr −22 on 40 trades) is the
**exit-model-dependent** realizedUsd, which contradicts the model-free geometry → not trusted.

## Why the intuition didn't map to this measure
When recent near-price flow IS against a breakout, it marks a favorable **pullback entry** (price dipped back
into the band on down-flow, then the setup fired), not exhaustion. The "volume dies out" intuition is about
the VP **structure** / participation, which the recent-2.4×ATR-flow direction doesn't capture.

## Where the exhaustion intuition DOES flicker (different quantities — NOT this veto)
1. **`nodeNet` (VP-node decayed buy/sell at the exact breakout price)** — a DIFFERENT measure (historical
   absorption at that price level, not recent flow). Proxy autopsy: mild node-net-against entries (n=257) were
   net money-losers (−26/tr) with lower mfeR (1.137 vs 1.309). Weak + NON-MONOTONE (the strong-against tail
   n=11 reversed to great). This is "breaking into a price level that historically net-sold," i.e. structural
   resistance — a separate hypothesis worth its own autopsy if pursued.
2. **Fading ABSOLUTE volume** (declining tick_count / participation) — the literal reading of "volume dies
   out" is a MAGNITUDE veto (no fuel), not a net-delta DIRECTION veto. Untested here.

## H12b follow-up — FADING-VOLUME (magnitude) veto → ALSO REJECT (2026-06-27)
The literal reading of "volume dies out" = a MAGNITUDE veto (skip a breakout with low/declining participation),
not a direction veto. Tested pure-Python (no engine change) by joining the lock's 2117 trades (entryTimeUTC ==
signal-bar open) to the M5 bars' `tick_count`, model-free mfeR/reach1R. Three measures, quartiled low→high:

| measure | Q1 LOWEST (dying) | Q4 HIGHEST | hypothesis |
|---|---|---|---|
| breakout-bar rel volume | mfeR 1.278 / +13.2 usd/tr | mfeR 1.284 / −7.1 | low=worse → **NO** |
| participation slope (rec3/avg50) | mfeR 1.301 / +20.2 | mfeR 1.225 / −11.8 | low=worse → **NO** |
| near-price partic. frac (±2.4ATR) | mfeR 1.376 / +19.2 | mfeR 1.255 / +1.3 | low=worse → **NO** |

**Low/dying-volume breakouts are EQUAL-or-BETTER, not traps** (model-free confirmed). Faint INVERSE hint:
*surging/high*-volume breakouts are the weaker ones (climactic exhaustion blow-offs that reverse) — consistent
with XAU's quiet-trend-runner character, but weak and exit-model-tinged; not the user's hypothesis, not chased.
Repro: `fading_volume_autopsy.py`. ⇒ Both the DIRECTION veto (H12) and the MAGNITUDE veto (H12b) reject; the
entry-exhaustion intuition has no near-price-volume expression that flags an XAU breakout entry as a trap.

## Infra (default-OFF, byte-identical — verified)
`Params::{enable_entry_flow_veto, entry_flow_veto_atr=2.4, entry_flow_veto_min, entry_flow_look=50}`;
`near_price_net_at()` (tf_net.hpp); engine computes `efn` at the gate, journals `Signal::f_entry_flow_near`
→ `TradeRecord::entry_flow_near` → `entryFlowNear` CSV column; veto sits after net-persist. OFF → trades
byte-identical to the lock (behavioral trade-diff vs HEAD empty; same 2117 trades / balance). `make test` green.
</content>
