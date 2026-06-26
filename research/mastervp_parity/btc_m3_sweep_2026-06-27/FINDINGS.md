# H7 — BTC M3 dedicated sweep → VERDICT: NO ROBUST EDGE (overfit, OOS-catastrophic) — 2026-06-27

The old "BTC M3 no edge" (2026-06-22) loaded the **BTC-M5 LOCKED .set on M3 bars** — never a real M3 sweep.
This is the genuine one: master length, ADX trend filter, trail, and SL all swept on actual M3 bars.
TRAIN = ticks_btcusd_2025_window.csv (Aug 11–Nov 30 2025, ~3.5mo); OOS = ticks_btcusd_2026_oos.csv
(Jan 1–Jun 8 2026, ~5mo); bars = bars_btcusd_2025_2026_m3.csv; base = `m3_base_btc.set`; harness `sweep.py`.

## Result — train-tunable, OOS-catastrophic, ANTI-CORRELATED
- **Baseline `m3_base_btc.set`:** TRAIN PF 0.753 / −7,107 / DD 71.4%; OOS PF 0.825 / −7,221 / DD 82.2%. The
  "locked" comments in that file were XAU-transplanted, never real for BTC.
- **S1 master×ADX (16 combos, train):** ALL PF<1. Best region = master **6 (720 bars/36h)** + ADX≥26–30
  (PF ~0.96). `tp2≈1%` → the RunnerRr=10 fixed target essentially never hits; the trail governs the runner.
- **S2 exit (master6/ADX30, trail×SL, train):** crosses PF>1 only with a VERY WIDE trail — best
  **trail 8 / SL 1.5 → PF 1.090 / net +2,300 / DD 18.3% / n557**. Monotone in trail (8>6>3>2). trail=8 sits
  near the grid edge (overfit flag); trail 10/12 fall off (PF 1.083→1.032).
- **🧨 OOS validation of the train-best region — COLLAPSE.** master6/ADX30/SL1.5, trail {6,8,10,12}:
  OOS PF **0.668–0.722**, net **−7,500…−7,980**, DD **78–81%**. The train PF 1.090 winner → **OOS PF 0.668**.
  Train↑ ⇒ OOS↓ (anti-correlated) = pure overfit, exactly the 2026-06-22 hint, now proven on real M3 params.
- **OOS-direct broad scan (master{4,6,8}×ADX{22,30}×trail{3,6,10}×SL{1,2}, 12 combos): ZERO are PF>1 on OOS.**
  It's not "we picked the wrong region" — the entire OOS surface is sub-1.

## Verdict
**REJECT. BTC M3 has no genuine, generalizing edge.** Do NOT ship a BTC-M3 lock. The 3.5-mo train period can
be curve-fit to PF~1.09 but it inverts OOS (PF 0.67, ~80% DD). Consistent with the portfolio study (BTC M3 PF
1.031 marginal, redundant w/ BTC M5) and the original collapse finding. BTC's only non-dead MasterVP timeframe
remains **M5** (breakeven-to-marginal, tail-skewed — [[mastervp-btc-sweep]]); XAU M5 is the sole validated edge.
H7 closed. No code change (sweep only). Next: the nodeNet structural-absorption veto (H12c, the session's one
autopsy PASS) is the highest-value open lever.
