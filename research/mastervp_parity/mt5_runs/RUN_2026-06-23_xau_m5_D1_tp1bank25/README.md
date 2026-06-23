# RUN 2026-06-23 — KK-MasterVP XAU M5 · D1 TP1BANK25 (bank 25% at TP1)

**EA** dquants ▸ KK-MasterVP ▸ KK-MasterVP · **Symbol** XAUUSD · **Period** 2025.06.01 → 2026.05.29
· **TF** M5 · **Model** every tick · **Deposit** 10,000 USD · **.set** `KK-MasterVP-XAUUSD-M5-Tp1bank25.set`

Differs from A1 base in ONLY `InpTp1ClosePct` (0 → 25%). Bank 25% at TP1, 75% rides the 2.5 trail. PL OFF, rev ON.

## Results vs A1 base
| metric | D1 Tp1bank25 | A1 base | Δ |
|---|---|---|---|
| trades | 1363 | 1363 | 0 (same entries) |
| net profit | **+43,229** | +62,732 | **−19,502 (−31.1%)** |
| profit factor | **1.334** | 1.402 | −0.068 |
| win rate | 55.9% (762/601) | 54.3% (740/623) | +1.6pp |
| avg win / avg loss | 226.49 / −215.23 | 295.68 / −250.51 | win −69 |
| largest win / loss | 3,646.39 / −543.18 | 6,218.75 / −741.96 | win HALVED |
| exit tags | SL-WIN=747, SL-LOSS=601, TP=15 | 725/623/15 | +22 wins, −22 losses |

## Verdict: PARTIAL BANKING HURTS — REJECT
Identical entries (1363) confirm this is a pure exit change. Banking 25% at TP1 nudges win rate up
(+1.6pp, fewer SL-LOSS) but caps the runner: largest win HALVED (6,219→3,646), avg win 296→226.
Net falls 31%. Same fat-tail lesson as the WF sweep that already locked TP1=0% — the banked quarter
is worth far less than the tail it forfeits. A1 base (TP1=0) leads all 6 XAU tests.
