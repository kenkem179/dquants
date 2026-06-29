# KenKem Exit-Giveback & SL-Geometry Analysis (lock D5-E4Long, full window)

2026-06-29. Source: `lock_trades_maeR_full.csv` (198 trades, the D5-E4Long lock over the full XAU M1
tick window, now with the **newly-fixed `maeR`**). Repro: `/tmp/giveback.py`. Engine numbers — directionally
trustworthy (KenKem tick engine is MT5-validated on net/PF) but exact R-magnitudes have fill-precision error
bars; **rank here, confirm on MT5.**

## Per-entry excursion & capture

| entry | n | net$ | win% | mean mfeR (peak) | mean realR | capture | mean maeR |
|-------|--:|-----:|-----:|-----:|-----:|-----:|-----:|
| E1 | 82 | 1019 | 58.5 | 0.74 | +0.09 | 12.6% | 0.46 |
| E2 | 54 | 368 | 42.6 | 0.56 | +0.11 | 18.8% | 0.37 |
| E4 | 62 | 808 | 53.2 | 0.91 | +0.14 | 15.4% | 0.48 |

`realR` = realized R at exit; `capture` = ΣrealR / Σmfe R; `maeR` = adverse excursion in R.

## Finding 1 — the headline "capture 12–19%" is mostly losers, NOT surrendered winners

The first instinct ("E4 gives back all its hard-earned profit") looks confirmed by the 15% capture — but
that aggregate is dragged down by **losers** (negative realR), not by winners round-tripping. The clean test:

**Trades that peaked ≥1.0R then exited ≤0.3R (a genuine profit round-tripped):**
- E1: 9/82 (11%) — **$41 total** left on the table
- E2: 0/54 (0%)
- E4: 7/62 (11%) — **$26 total** left on the table

So clear profit round-trips surrender **~$67 across E1+E4**, against **+$1,827** net from those two entries.
**The "bleeding all the profit" story is a ~4% effect, not the main event.** This is a scalping book: most
trades live and die within ±0.9R of breakeven, and the net is modest positive expectancy × many trades.

**Implication for the E4 laddered-TP idea:** E4 *already has* a 3-stage laddered TP + a partial, but its
first bank arms at 0.70 × 2.4RR ≈ **1.68R, which only 18% of E4 trades ever reach** (median E4 peak = 0.79R).
The machinery exists; it's calibrated for a move E4 rarely makes. **E1 is worse** — first bank at 1.71R,
reached by **2%** of trades = effectively dead. Recalibrating the bank/BE-arm to where trades actually peak
(~0.5–0.8R) is worth a *sweep*, but the upside is bounded (the round-trip pot is small) and it fights the
fat-tail caution (banking early caps runners — repeatedly the 0% optimum on MasterVP/Monster). So: test it,
don't assume it.

## Finding 2 — the cleaner lever is SL geometry (your #3), and the data shows real asymmetry

| entry | losers' maeR (median) | winners dipping ≥0.5R adverse | winners dipping ≥0.75R |
|-------|-----:|-----:|-----:|
| E1 | 0.80 | 9/48 (19%) | 2 |
| E2 | 0.55 | 3/23 (13%) | 1 |
| E4 | 0.75 | 7/33 (21%) | 4 |

Losers reach their stop at **0.55–0.80R adverse**, while **winners almost never dip past 0.75R** (1–4 trades
per entry). That asymmetry is exactly what a stop-tightening sweep exploits: pull the SL in toward ~0.75–0.85R
and you cut the average loss with minimal winner damage — **especially E2** (losers stop at 0.55R already;
its SL may even be *too tight* to widen, or its entry too late — ties to the E2 redesign). This is a
**measurable, gate-able edge**, and it's the under-optimization you've been worried about.

## What this means for the plan

1. **#2 (E4 anti-bleed) is real but modest** — recalibrate the *existing* partial/BE-arm earlier (not add new
   TP machinery), and sweep it; don't expect a transformation. Honest expected value: small.
2. **#3 (per-entry RR + ATR-SL) is the main prize** — and the reason it was never done right is the only
   sweep harness (`optimize_kenkem.py`) runs on the **bar engine** (P&L-sign defect). Redo it on the **tick
   engine**, full window, through `research/stats/gate.py`, per-quarter walk-forward.
3. **Stops, not targets, are where the asymmetry lives.** Lead the sweep with per-entry ATR-SL cap/floor +
   converting the fixed `SL_EMA_DISTANCE=27 pips` to ATR-relative, then RR, then the bank/BE-arm timing.

Nothing locks without DSR/PSR/MinTRL + an MT5 confirm.
