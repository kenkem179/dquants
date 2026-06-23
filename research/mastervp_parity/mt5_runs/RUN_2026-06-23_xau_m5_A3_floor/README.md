# RUN 2026-06-23 — KK-MasterVP XAU M5 · A3 FLOOR (profit-lock giveback cap)

**EA** dquants ▸ KK-MasterVP ▸ KK-MasterVP · **Symbol** XAUUSD · **Period** 2025.06.01 → 2026.05.29
· **TF** M5 · **Model** every tick · **Deposit** 10,000 USD · **.set** `KK-MasterVP-XAUUSD-M5-Floor.set`

Differs from A1 base in ONLY the giveback group: `InpPmGiveback=true`, `InpPmGivebackArmR=1.5`,
`InpPmGivebackCapFrac=0.50` (arm at 1.5R, never give back more than 50% of peak). Log echo confirmed.
(Log final balance 44,252.55; CSV-computed net 44,132.39 — ~120 gap = open position at test end.)

## Results (computed from trades CSV) — vs A1 base
| metric | A3 Floor | A1 base | Δ |
|---|---|---|---|
| trades | 1493 | 1363 | +130 |
| net profit | **+34,132** | +62,732 | **−28,599 (−45.6%)** |
| profit factor | **1.251** | 1.402 | −0.151 |
| win rate | 53.9% (805/688) | 54.3% (740/623) | −0.4pp |
| avg win / avg loss | 211.01 / −197.28 | 295.68 / −250.51 | win −85 |
| expectancy / trade | 22.86 | 46.02 | −23.16 |
| largest win / loss | 2,663.68 / −495.10 | 6,218.75 / −741.96 | win HALVED |
| exit tags | SL-WIN=797, SL-LOSS=688, TP=8 | 725/623/15 | more+smaller wins |

## Verdict: FLOOR HURTS WORST — REJECT
The giveback cap arms early (1.5R) and yanks runners out at 50% of peak. Win rate holds (53.9%) but
avg win collapses 296→211 and largest win is HALVED (6,219→2,664). More, smaller wins + freed capital
→ +130 trades, but each captures far less. Net falls 45.6% — the worst of the three protection variants.
Same lesson as A2: this is a fat-tail trailing-runner; capping the tail destroys the edge. A1 base leads.
