# RUN 2026-06-23 — KK-MasterVP BTC M5 · B1 BASE (reversion OFF)

**EA** dquants ▸ KK-MasterVP ▸ KK-MasterVP · **Symbol** BTCUSD · **Period** 2025.06.01 → 2026.05.29
· **TF** M5 · **Model** every tick · **Deposit** 10,000 USD · **.set** `KK-MasterVP-BTCUSD-M5-BASE.set`

BTC base: reversion OFF (MT5-disconfirmed on noisy feed), MasterMult=30, SL 2.2 ATR, trail 6.0 ATR,
profit-lock OFF, parity ON. (First two attempts 21:55/21:56 ran on a XAUUSD chart by mistake — re-run
on BTCUSD at 21:57:54 → final 11,530.77; that is this run.)

## Results (computed from trades CSV)
| metric | value |
|---|---|
| trades | 708 |
| net profit | **+1,530.77** (final 11,530.77) |
| profit factor | **1.049** |
| win rate | 51.3% (363W / 345L) |
| avg win / avg loss | 90.80 / −91.10 |
| largest win / loss | 1,085.73 / −152.81 |
| maxDD (additive proxy) | 28.6% |
| exit tags | SL-WIN=352, SL-LOSS=345, TP=11 |

## Note: BTC M5 is a marginal edge over this window
PF 1.049 over 2025.06→2026.05 is far below the earlier OOS-window lock (PF ~1.21) — full-year window +
Exness feed is harder. Because the BTC runner-trail is known over-optimistic on this noisy feed, the
profit-lock variants (B2 Ladder / B3 Floor) are the interesting test here: unlike XAU, capping the
(partly fictional) tail MIGHT help. This base is the comparison line for B2/B3.
