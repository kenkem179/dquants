# RUN 2026-06-23 — KK-MasterVP XAU M5 · A1 BASE (profit-lock A/B baseline)

**EA** dquants ▸ KK-MasterVP ▸ KK-MasterVP · **Symbol** XAUUSD · **Period** 2025.06.01 → 2026.05.29
· **TF** M5 · **Model** every tick (real ticks) · **Deposit** 10,000 USD · **.set** `KK-MasterVP-XAUUSD-M5.set`

Config: reversion ON (deployed lock), all profit-lock OFF, parity export ON. First run on the
regenerated self-contained 101-key base. Reproduces the recorded lock baseline +62,732 exactly.

## Results (computed from trades CSV)
| metric | value |
|---|---|
| trades | 1363 |
| net profit | **+62,731.58** (final 72,731.58) |
| profit factor | **1.402** |
| win rate | 54.3% (740W / 623L) |
| avg win / avg loss | 295.68 / -250.51 |
| expectancy / trade | 46.02 |
| largest win / loss | 6,218.75 / -741.96 |
| exit tags | SL-WIN=725, SL-LOSS=623, TP=15 |

**Note:** only 15 of 1363 exits hit the fixed TP — 725 wins exit via *trailed* SL. The strategy is a
trailing-runner, so the profit-lock A/B (Ladder/Floor) and trail-tighten (Trail20/15) tests target
exactly the mechanism that produces ~98% of exits. This is the baseline they all compare against.
