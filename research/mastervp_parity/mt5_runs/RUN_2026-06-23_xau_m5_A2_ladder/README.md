# RUN 2026-06-23 — KK-MasterVP XAU M5 · A2 LADDER (profit-lock progressive trail)

**EA** dquants ▸ KK-MasterVP ▸ KK-MasterVP · **Symbol** XAUUSD · **Period** 2025.06.01 → 2026.05.29
· **TF** M5 · **Model** every tick · **Deposit** 10,000 USD · **.set** `KK-MasterVP-XAUUSD-M5-Ladder.set`

Differs from A1 base in ONLY one lever: `InpPmProgTrail=true` (progressive profit-lock trail).
Log inputs echo confirmed: rev ON, `InpPmProgTrail=true`, `InpPmGiveback=false`, parity ON, deposit 10k.

## Results (computed from trades CSV) — vs A1 base
| metric | A2 Ladder | A1 base | Δ |
|---|---|---|---|
| trades | 1334 | 1363 | −29 |
| net profit | **+45,463.44** | +62,731.58 | **−17,268 (−27.5%)** |
| profit factor | **1.348** | 1.402 | −0.054 |
| win rate | 49.9% (666/668) | 54.3% (740/623) | −4.4pp |
| avg win / avg loss | 264.69 / −195.84 | 295.68 / −250.51 | win −31, loss tighter |
| expectancy / trade | 34.08 | 46.02 | −11.94 |
| largest win / loss | 4,729.75 / −579.27 | 6,218.75 / −741.96 | both clipped |
| exit tags | SL-WIN=648, SL-LOSS=668, TP=18 | 725/623/15 | +45 losses, −77 wins |

## Verdict: LADDER HURTS — REJECT
The progressive trail tightens the runner stop too aggressively: it clips avg win (296→265) and
largest win (6,219→4,730), and converts ~77 trailed wins into losses (win rate 54→50%). Net falls
27.5%. The trailing-runner edge lives in the fat tail; the ladder cuts exactly that tail.
This is the opposite of the intended profit-protection benefit on this strategy. A1 base still leads.
