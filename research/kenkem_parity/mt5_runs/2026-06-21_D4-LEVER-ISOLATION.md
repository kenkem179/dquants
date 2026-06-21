# D4 lever isolation — final verdict (XAU M1, E1+E2, 2025.03–2026.05)

**Date:** 2026-06-21. **Verdict: ✅ KEEP D3-noE4. D4 and both isolated levers fail the recent-OOS bar.**

All runs MT5, every-tick, via KK-KenKem clone (exact-parity to legacy). Baseline = D3-noE4 (+1048.88/1.389).

| variant | Pooled | 2025 (train) | **2026 (OOS)** |
|---|---|---|---|
| **D3-noE4 (lock)** | +1048.88 / 1.389 / 102 | +722.02 / 1.360 | **+326.86 / 1.475 / 24** |
| D4 (ADX23 + touch60) | +1382.27 / 1.489 / 112 | +1108.48 / 1.537 | +273.79 / 1.359 / 25 |
| D4-ADXonly (ADX23) | +1121.31 / 1.407 / 103 | +845.86 / 1.410 | +275.45 / 1.396 / 23 |
| D4-TAonly (touch60) | +1294.98 / 1.467 / 111 | +984.64 / 1.490 | +310.34 / 1.407 / 26 |

## Findings
- **No variant beats D3-noE4 out-of-sample (2026)** on net OR PF. All trade better-2025 for worse-2026.
- The D4 pooled gain is concentrated in **2025Q4** (base +902 → variants +1062–+1254) = in-sample curve-fit.
- **ADX23 is the OOS degrader:** the 2026Q2 drop (+56.95/1.15 → +11.86/1.03) appears in D4-both AND
  D4-ADXonly but NOT in D4-TAonly (2026Q2 identical to base) — so the ADX lever causes it.
- touch-age60 is the milder lever (2026Q2 untouched) but still nets slightly below base OOS
  (2026 +310 vs +327, PF 1.407 vs 1.475) — not an improvement.

## Decision
- **D3-noE4 remains the E1+E2 lock** (recent-OOS robust; both 2026 quarters healthy). D4 family rejected.
- Runs: `2026-06-21_{D4,D4-ADXonly,D4-TAonly}/`. Baseline `2026-06-21_D3-noE4_clone/` (exact-parity).

## Overfitting gate on D3-noE4 (research/stats/gate.py, new CLAUDE.md mandate) — ⚠️ WARN / under-powered
- per-trade Sharpe 0.138 (n=102) · **PSR vs 0 = 0.922** (WARN band 0.90–0.95, below the 0.95 PASS bar)
- **Min Track Record Length = 136 trades; we have only 102 → sample TOO SHORT.**
- DSR = n/a (the D-series sweep doesn't log `sr_trial_std` yet — known gap per research/stats/README).
- **Read:** D3-noE4 is the best + exact-parity candidate but NOT statistically confirmable at 95% on
  102 trades. Paths to clear it: (a) more sample — E1+E2+E5 (D4-E5 adds ~248 E5 trades, toward MinTRL)
  if MT5-profitable; (b) longer history; (c) accept WARN status + lean on MT5 demo forward-test.
