# RUN 2026-06-23 — KK-MasterVP XAU M5 · C1 TRAIL20 (runner trail 2.5 → 2.0 ATR)

**EA** dquants ▸ KK-MasterVP ▸ KK-MasterVP · **Symbol** XAUUSD · **Period** 2025.06.01 → 2026.05.29
· **TF** M5 · **Model** every tick · **Deposit** 10,000 USD · **.set** `KK-MasterVP-XAUUSD-M5-Trail20.set`

Differs from A1 base in ONLY `InpTrailAtrMult` (2.5 → 2.0 = tighter runner trail). Profit-lock OFF, rev ON.

## Results (computed from trades CSV) — vs A1 base
| metric | C1 Trail20 | A1 base | Δ |
|---|---|---|---|
| trades | 1361 | 1363 | −2 |
| net profit | **+53,322** | +62,732 | **−9,410 (−15.0%)** |
| profit factor | **1.316** | 1.402 | −0.086 |
| win rate | 38.9% (530/831) | 54.3% (740/623) | −15.4pp |
| avg win / avg loss | 419.25 / −203.23 | 295.68 / −250.51 | win +124 |
| expectancy / trade | 39.18 | 46.02 | −6.84 |
| largest win / loss | 4,856.15 / −798.19 | 6,218.75 / −741.96 | win −1,363 |
| exit tags | SL-LOSS=831, SL-WIN=518, TP=12 | 725/623/15 | +208 losses |

## Verdict: TIGHTER TRAIL HURTS — REJECT
A 2.0-ATR trail sits closer to price, so normal pullbacks knock runners out before they reach profit:
SL-WIN 725→518, SL-LOSS 623→831 (win rate 54%→39%). Survivors are only the cleanest trends (avg win
rises 296→419) but there are too few of them — net falls 15%. Consistent with A2/A3: cutting the
runner early forfeits the fat-tail edge. The 2.5 base is on the correct side. A1 base leads.
