# RUN 2026-06-23 — KK-MasterVP BTC M5 · B3 FLOOR (giveback cap, keep >=67% of peak after 1.5R)

**EA** dquants ▸ KK-MasterVP ▸ KK-MasterVP · **Symbol** BTCUSD · **Period** 2025.06.01 → 2026.05.29
· **TF** M5 · **Model** every tick · **Deposit** 10,000 USD · **.set** `KK-MasterVP-BTCUSD-M5-Floor.set`

Differs from B1 BTC base in ONLY giveback group: `InpPmGiveback=true`, ArmR=1.5, CapFrac=0.33. rev OFF.

## Results vs B1 base and B2 Ladder
| metric | B3 Floor | B2 Ladder | B1 base |
|---|---|---|---|
| trades | 927 | 753 | 708 |
| net profit | **+2,206** | +2,311 | +1,531 |
| profit factor | **1.053** | 1.070 | 1.049 |
| win rate | 52.3% | 50.6% | 51.3% |
| largest win | 951 | 1,067 | 1,086 |
| maxDD (proxy) | 27.8% | 25.3% | 28.6% |
| exit tags | 483/442/2 | 373/372/8 | 352/345/11 |

## Verdict: FLOOR ~ flat-to-slightly-positive; LADDER is the BTC winner
B3 net +2,206 (+44% vs base) but PF barely moves (1.049→1.053) and DD is barely better (28.6→27.8%).
The Floor arms early and churns many more trades (927) for the same money — less clean than the Ladder.
On BTC the Ladder (B2: PF 1.070, DD 25.3%) is the better protection. Both beat base, confirming the
per-symbol thesis, but BTC M5 remains a marginal edge overall (PF ~1.05–1.07) — not a strong deploy.
