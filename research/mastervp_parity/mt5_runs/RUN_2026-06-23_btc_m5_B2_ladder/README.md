# RUN 2026-06-23 — KK-MasterVP BTC M5 · B2 LADDER (progressive profit-lock trail)

**EA** dquants ▸ KK-MasterVP ▸ KK-MasterVP · **Symbol** BTCUSD · **Period** 2025.06.01 → 2026.05.29
· **TF** M5 · **Model** every tick · **Deposit** 10,000 USD · **.set** `KK-MasterVP-BTCUSD-M5-Ladder.set`

Differs from B1 BTC base in ONLY `InpPmProgTrail=true`. rev OFF, MasterMult 30, SL 2.2, trail 6.0.

## Results vs B1 BTC base
| metric | B2 Ladder | B1 base | Δ |
|---|---|---|---|
| trades | 753 | 708 | +45 |
| net profit | **+2,311** | +1,531 | **+780 (+51%)** |
| profit factor | **1.070** | 1.049 | +0.021 |
| win rate | 50.6% (381/372) | 51.3% (363/345) | −0.7pp |
| avg win / avg loss | 92.91 / −88.94 | 90.80 / −91.10 | loss tighter |
| largest win / loss | 1,066.65 / −150.87 | 1,085.73 / −152.81 | ~same |
| maxDD (additive proxy) | **25.3%** | 28.6% | **−3.3pp better** |
| exit tags | SL-WIN=373, SL-LOSS=372, TP=8 | 352/345/11 | — |

## Verdict: LADDER HELPS ON BTC — opposite of XAU
As hypothesized: BTC's runner-trail tail is partly fictional on the noisy Exness feed, so the
progressive lock improves both net (+51%) AND drawdown (−3.3pp). The effect is small in absolute terms
(PF 1.049→1.070, still a marginal edge) but it is the RIGHT direction — unlike XAU where every lock hurt.
Confirms the per-symbol thesis: protect on BTC, leave runners alone on XAU. B3 Floor next to compare.
