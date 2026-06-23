# RUN 2026-06-23 — KK-MasterVP XAU M5 · C2 TRAIL15 (runner trail 2.5 → 1.5 ATR)

**EA** dquants ▸ KK-MasterVP ▸ KK-MasterVP · **Symbol** XAUUSD · **Period** 2025.06.01 → 2026.05.29
· **TF** M5 · **Model** every tick · **Deposit** 10,000 USD · **.set** `KK-MasterVP-XAUUSD-M5-Trail15.set`

Differs from A1 base in ONLY `InpTrailAtrMult` (2.5 → 1.5 = tightest runner trail tested). PL OFF, rev ON.

## Results vs A1 base — and the trail curve
| metric | C2 Trail15 | C1 Trail20 | A1 base (2.5) |
|---|---|---|---|
| net profit | **+42,053** | +53,322 | +62,732 |
| profit factor | **1.222** | 1.316 | 1.402 |
| win rate | 43.1% | 38.9% | 54.3% |
| avg win | 357.85 | 419.25 | 295.68 |
| largest win | 3,653 | 4,856 | 6,219 |
| trades | 1505 | 1361 | 1363 |
| exit tags | 640/857/8 | 518/831/12 | 725/623/15 |

## Verdict: MONOTONIC — tighter trail = worse. REJECT.
Net falls 2.5 → 2.0 → 1.5 ATR: 62.7k → 53.3k → 42.1k (−33% at 1.5). PF 1.402 → 1.316 → 1.222.
The trail curve is monotone in this range; the 2.5 base is the best of the three (likely at/above the
plateau). Confirms the fat-tail thesis cleanly: every notch tighter forfeits more runner upside.
A1 base leads all 5 XAU tests so far.
