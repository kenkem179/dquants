# D4-E5 — adding E5 to the E1+E2 lock (XAU M1, MT5, 2025.03–2026.05)

**Date:** 2026-06-21. **Verdict: ⚠️ E5 ≈ statistical noise. DO NOT ship E5. Keep D3-noE4 (E1+E2) as the lock.**

E5 doubles raw net but at near-breakeven per-trade quality; the full-stream gate "passes" ONLY because
258 marginal trades inflate the sample count. The honest read = E5 dilutes edge quality.

## Run
- EA `dquants\KK-KenKem\KK-KenKem`, XAUUSD M1, 2025.03.02–2026.05.29, every-tick.
- Preset `KK-KenKem-XAUUSD-M1-D4-E5.set` (D4 filters + `ENABLE_E5=true`). Output from Agent-3000.
- Baseline = D3-noE4 (`2026-06-21_D3-noE4_clone/`, +1048.88/PF1.389/102tr, exact-parity).

## Result — by entry kind
| kind | net | PF | n | win% |
|---|---|---|---|---|
| E1 | +935.68 | 1.772 | 51 | 59% |
| E2 | +672.73 | 1.810 | 47 | 55% |
| **E5** | **+503.91** | **1.082** | **258** | **46%** |
| **pooled (E1+E2+E5)** | **+2112.32** | **1.258** | **356** | 49% |

## Result — by period
| period | D3-noE4 (lock) | D4-E5 | read |
|---|---|---|---|
| Pooled | +1048.88 / 1.389 / 102 | +2112.32 / 1.258 / 356 | E5 +net, −PF |
| 2025 (train) | +722.02 / 1.360 | +1596.99 / 1.294 | +net, −PF |
| **2026 (OOS)** | **+326.86 / 1.475 / 24** | +515.33 / 1.188 / 102 | +net but **PF craters 1.475→1.188** |

## Overfitting gate (research/stats/gate.py) — the decisive evidence
| stream | per-trade Sharpe | PSR vs 0 | MinTRL | verdict |
|---|---|---|---|---|
| D3-noE4 (E1+E2, 102 tr) | 0.138 | 0.922 | 136 > 102 | WARN, under-powered |
| **E5 alone (258 tr)** | **0.036** | **0.718** | **2095 ≫ 258** | **FAIL — noise** |
| D4-E5 full (356 tr) | 0.096 | 0.966 | 287 < 356 | "PASS" — but see below |

**The full-stream PASS is an artifact, not an edge.** PSR clears 0.95 only because N jumped to 356;
the *quality* (per-trade Sharpe) FELL 0.138→0.096 vs the E1+E2 lock. E5 alone needs 2095 trades to
prove a Sharpe-0.036 edge and has 258 → it is indistinguishable from a coin flip. Pooling noise with
signal to win a sample-count test is gaming the gate, exactly what the multiple-testing mandate forbids.

## Interpretation
- E5's +503.91 is real MT5 money, but PF 1.082 / 46% win is the thinnest possible positive edge, and it
  collapses the blended OOS PF from 1.475 to 1.188. (Consistent with the engine's known E5 ~53% recall +
  exit optimism — the standalone family was never robust.)
- The E1+E2 subset INSIDE this run is actually PF 1.788/98tr (E5-on cannibalizes ~14 E1/E2 entries via
  the one-position limit, and the dropped ones were net losers) — i.e. E1+E2 remain the quality core.

## Decision
- **KEEP D3-noE4 (E1+E2) as the lock. Reject E5.** The right way to clear the gate is MORE E1+E2 history
  (longer sample), not diluting with a noise family.
- E5 stays OFF in the deploy preset. (Revisit only if a future E5 rework lifts its standalone PF well
  above ~1.2 with its own sufficient MinTRL.)
