# RUN 2026-06-23 — KK-MasterVP XAU M5 · D2 SL10 (tighter initial breakout SL 1.2 → 1.0 ATR)

**EA** dquants ▸ KK-MasterVP ▸ KK-MasterVP · **Symbol** XAUUSD · **Period** 2025.06.01 → 2026.05.29
· **TF** M5 · **Model** every tick · **Deposit** 10,000 USD · **.set** `KK-MasterVP-XAUUSD-M5-SL10.set`

Differs from A1 base in ONLY `InpSlAtrBrk` (1.2 → 1.0). Runner trail 2.5, TP1=0, PL OFF, rev ON.
The DD-protection hypothesis: smaller initial stop → smaller losers without touching winners.

## Results vs A1 base
| metric | D2 SL10 (1.0) | A1 base (1.2) | Δ |
|---|---|---|---|
| trades | 1484 | 1363 | +121 |
| net profit | **+44,811** | +62,732 | **−17,920 (−28.6%)** |
| profit factor | **1.270** | 1.402 | −0.132 |
| win rate | 54.0% (801/683) | 54.3% (740/623) | −0.3pp |
| avg win / avg loss | 263.21 / −243.08 | 295.68 / −250.51 | win −32 |
| largest win / loss | 5,159.78 / −623.83 | 6,218.75 / −741.96 | win −1,059 |
| **maxDD (additive proxy)** | **33.4%** | **23.4%** | **+10pp WORSE** |
| exit tags | SL-WIN=780, SL-LOSS=683, TP=21 | 725/623/15 | +60 losses |

## Verdict: TIGHTER SL HURTS — even drawdown got WORSE. REJECT.
The DD hypothesis is FALSIFIED. A 1.0-ATR stop sits inside normal breakout noise, so it is hit before
trades can work: SL-LOSS 623→683 and +121 total trades (stopped-out capital churns back in). It also
clips winners that needed room (largest win 6,219→5,160). Net −28.6%, PF −0.13, AND maxDD +10pp.
The wider 1.2 base gives breakouts room to breathe and is better on EVERY axis. A1 base leads.

## XAU M5 SWEEP COMPLETE — A1 base wins all 7
Ladder, Floor, Trail2.0, Trail1.5, TP1-bank25, SL1.0 all underperform the deployed lock. Every lever
that protects/tightens forfeits more than it saves. The strategy is a fat-tail trailing-runner; the
2.5-ATR trail + 1.2-ATR SL + no-partial + no-profit-lock configuration is confirmed optimal live.
