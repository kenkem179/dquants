# D4 candidate — MT5 result vs D3-noE4 baseline (E1+E2, XAU M1)

**Date:** 2026-06-21. **Verdict: ⚠️ pooled WIN but OOS (2026) REGRESSION — NOT a clean upgrade.**

## Run
- EA `dquants\KK-KenKem\KK-KenKem`, XAUUSD M1, 2025.03.02–2026.05.29, every-tick.
- Preset `KK-KenKem-XAUUSD-M1-D4.set` = D3-noE4 + `E1_MIN_MOMENTUM_ADX` 19.5→23 + `E2_MAX_TOUCH_AGE` 36→60.
- Collected from Agent-3000; baseline = `2026-06-21_D3-noE4_clone/` (+1048.88/PF1.389/102tr, exact-parity).

## Result
| period | D3-noE4 (base) | D4 | read |
|---|---|---|---|
| **Pooled** | +1048.88 / PF1.389 / 102 | **+1382.27 / PF1.489 / 112** | D4 wins headline |
| 2025 (train) | +722.02 / 1.360 / 78 | **+1108.48 / 1.537 / 87** | D4 much better |
| **2026 (OOS)** | **+326.86 / 1.475 / 24** | +273.79 / 1.359 / 25 | **D4 WORSE on net AND PF** |
| 2025Q4 | +902.52 / 3.20 | **+1254.02 / 3.90** | ← the entire D4 edge lives here |
| 2026Q1 | +269.91 / 1.86 | +261.93 / 1.68 | D4 slightly worse |
| 2026Q2 | +56.95 / 1.15 | +11.86 / 1.03 | D4 worse, near breakeven |

(2025Q1/Q2 are identical between sets — the filters don't change those trades.)

## Interpretation
- D4's two relaxed/tightened **entry** filters add ~10 trades, but the net/PF gain is **carried by
  2025Q4**. In the most recent regime (2026 H1, both quarters), D4 is flat-to-worse.
- This is the classic pooled-vs-recent-OOS overfit trap (cf. [[mastervp-m5-gate-sweep-lock]] T1/T2
  lesson). D3-noE4 was locked precisely because it keeps BOTH 2026 quarters healthy.
- **Recommendation: keep D3-noE4 as the lock** unless the user explicitly weights full-period PF/net
  over recent-regime robustness. Optional dig: isolate the two levers (ADX23-only vs touch60-only) to
  see if one is recent-OOS-safe while the other is the 2025Q4 curve-fit — costs 2 MT5 runs.
