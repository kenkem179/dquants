# BTC revisit (Monster/BTC) — is ANY BTCUSD edge salvageable? → NO ROBUST EDGE (2026-06-27)

User picked "Monster/BTC revisit" (knowingly lower-EV) after MasterVP XAU converged. Monster = retired
(merged into KK-MasterVP as `InpEnableImpulse`/`InpEnableExtremeReversion`, default OFF). So this is purely
"can BTCUSD breakout be made release-grade on any TF?" Verdict after a full diagnostic: **NO. Close BTC.**

## Prior state (entering the revisit)
- **BTC M3 = DEAD** (H7 dedicated sweep 2026-06-27): train-fittable to PF 1.09 but OOS-catastrophic (PF 0.668,
  81% DD), TRAIN↑⇒OOS↓ anti-correlated; OOS broad scan = ZERO PF>1 at any master/ADX/SL/trail. Pure overfit.
- **BTC M5 = only non-dead TF, NOT release-grade**: engine OOS PF 1.214 but MT5-DISCONFIRMS (engine 1.293 vs
  **MT5 1.058 / +1,761**), tail-skewed (top-10 = 219% of net), full 2025+26 window breakeven (PF 1.013).

## 1. Per-fold WF (the lock, 6-fold `wf_mvp_generic.py --symbol btc --tf m5`, base `kkmastervp_btc_m5_LOCKED.set`)
Pooled n=772 PF **1.108** net +3,671 dd 22.1% — **folds+ 3/6, worstPF 0.743**:
| F1 Jun–Aug25 | F2 Aug–Oct25 | F3 Oct–Dec25 | F4 Dec–Feb26 | F5 Feb–Apr26 | F6 Apr–Jun26 |
|--:|--:|--:|--:|--:|--:|
| PF0.74 **−1,727** | PF1.62 +3,338 | PF0.88 **−674** | PF1.41 +1,960 | PF1.30 +1,865 | PF0.79 **−1,092** |

**Not a clean 2025-loser/2026-winner regime a filter could exploit** — it's ALTERNATING unconditioned variance
(−,+,−,+,+,−), only 3/6 folds positive, and the MOST-RECENT fold (F6) is a LOSER.

## 2. Full-window run (Jan 2025 → Jun 2026, full bars+ticks) = LOSER
1232 trades, final balance **8,107.89 = net −1,892**, peak 10,336. Including 2025H1 (which the WF folds skip),
the BTC M5 lock LOSES money over the full available window. (H1 net −4,822 / H2 net +2,930.)

## 3. Model-free per-trade regime autopsy (`btc_m5_regime_autopsy.py`, n=1232, pre-registered variables)
Looking for an economically-sensible, MONOTONE, time-robust edge concentration (the way the XAU ATR-regime
filter works). Result: **none of the trend/conviction/extension variables delivers one.**
- **adx** (trend strength): NON-monotone — Q3 (33.7–41.9) WORST (−13.6/tr), highest-ADX Q4 not best. "Stronger
  trend ⇒ better breakout" FAILS.
- **diSpread** (directional conviction): non-monotone; H1 negative across ALL four quartiles.
- **brkDistAtr** (anti-chase): FAILS — closest breakouts (Q1) are the WORST (−6.6/tr), farthest (Q4) aren't.
- **spreadAtr** (cost/vol regime): non-monotone.
- **direction**: longs LOSE (−4,873), shorts WIN (+2,981) — but that's the specific 2025–26 BTC down-path;
  "shorts-only" = textbook overfit to one price path, not an economic edge. REJECT.
- Overriding fact: **H1 (2025) is net −4,822 and negative across nearly every cell of every variable** — no
  conditioning signal rescues 2025. The losing periods are unconditioned variance, not a tradeable regime.

## 4. The one flicker — `runwayAtr` (room to next VP node) — and why it does NOT graduate
Only monotone variable: LOW-runway breakouts (≤~4 ATR to next node) beat HIGH-runway. "Skip high-runway":
- WF window pooled net +1,883 → **+2,397**; full window **−1,892 → +3,323** (flips loser positive); worst-fold
  net −1,053 → −195. Looks tempting.
- **But it fails the bar to graduate to a build:** (a) still only **4/6 folds positive** — F3 AND the
  most-recent **F6 stay negative** (−54, −195); (b) it HURTS the 3 genuinely-good folds (F2/F4/F5 lose their
  high-runway winners) — the "gain" is almost entirely rescuing 2025H1; (c) the threshold is a post-hoc median
  fit (a real `InpRunwayMax` sweep = multiple-testing, would need the gate, best cut would be fitted); (d) the
  economics are BACKWARDS for a trend-runner (more room to run should help, not hurt) = strong artifact flag;
  (e) it's on a symbol whose engine P&L MT5-DISCONFIRMS (engine over-credits BTC even more than XAU), so an
  engine-only +514 net is exactly the quantity MT5 erases. Per repo autopsy doctrine, a lever must show a
  ROBUST economically-sensible gradient to earn a build — runwayAtr does not.

## Verdict — CLOSE BTC (no robust, deployable edge on any timeframe)
- M3 dead; M5 = full-window loser, MT5-disconfirms (PF 1.058), fold-unstable (3/6, recent fold negative), and
  NO pre-registered regime variable rescues it. The Exness BTC feed is over-optimistic — even the engine "edge"
  is partly fictional. Every reversion/XRev/impulse/FVG/anti-chase variant was already tested→rejected.
- The BTC M5 lock + A/B presets stay in tree as research history (NOT release-grade — header caveat already
  says so). No code change. The only deploy-time note that survives: IF ever forced to run BTC M5, the ProgTrail
  ladder (B2) was the least-bad MT5 variant (PF 1.070) — but PF ~1.06 is not deployable.
- **▶ No open BTC research lever.** XAU M5 (MasterVP) + XAU M1 (KenKem) remain the only validated edges.

Artifacts: `btc_m5_regime_autopsy.py`, `trades_btc_m5_autopsy.csv` (full-window export, in cpp_core/tools),
per-fold WF reproducible via `wf_mvp_generic.py --symbol btc --tf m5 --grid '{}' --show-folds`.
