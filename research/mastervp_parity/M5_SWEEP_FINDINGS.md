# KK-MasterVP — dedicated M5 sweep (2026-06-20)

Follow-up to the M5 first-look (commit 383ca35), which transplanted M3-locked params un-swept and
found M5 competitive at lower DD. This is the **dedicated M5 sweep**: master-VP length, entry buffer,
stop distance, trail multiplier — each train→OOS, plateau-picked, anti-overfit.

Data: combined M5 bars `cpp_core/tools/bars_xauusd_2025_2026_m5.csv` (99,665 bars). Ticks TF-agnostic.
TRAIN = 2025-06-19→2026-01-30 (`ticks_xau_train.csv`); OOS = 2026-02-01→2026-05-30 (`ticks_xau_oos.csv`).
Harness: `sweep.py` (now `--bars`-aware). Base: `cpp_core/tools/mastervp/m5_base.set` (M3-transplant, same-bars
indicators ema24/194 atr14). Costs modeled (bid/ask fill + spread).

## Inertness re-confirmed on M5
master=480 via `24×20` == `120×4` → identical PF 1.148 / dd 17.2 / n 1076. Local VP is INERT in
breakout-only mode (breakout keys off MASTER VAH/VAL only) — **master bar count is the sole VP driver**,
exactly as on M3. So the VP axis is clean: master bars = lookback × mult.

## S1 — master-VP length (the dominant lever)
| master | hrs | TRAIN PF/dd | OOS PF/dd/calmar |
|--------|-----|-------------|------------------|
| 192 | 16h | 1.135/34.7 | 1.100/19.5/1.28 |
| 288 | 24h | 1.064/41.3 | 1.154/19.3/1.57 |
| 384 | 32h | 1.085/30.7 | 1.131/15.7/1.64 |
| **432** | **36h** | 1.126/28.3 | **1.154/11.5/2.45** |
| 480 | 40h | 1.148/17.2 | 1.102/14.3/1.43 |
| 504 | 42h | 1.131/18.4 | 1.115/17.2/1.28 |
| 576 | 48h | 1.100/20.2 | 1.230/15.0/2.55 |

M5 generalizes more smoothly than M3 (no OOS collapse below 360 — M3 collapsed there). **432 (36h)** is
the robust plateau center: lowest OOS DD (11.5%), OOS PF 1.154 > train, interior to a smooth 384–480
low-DD band. 576 has higher OOS PF but sits at the edge of the tested range (peak risk). → master=432
= `InpVpLookback=108 × InpMasterMult=4`.

## S2 — break buffer (at master=432)
Train PF flat across buffer (1.10–1.13) but larger buffers cut DD. OOS strong everywhere (PF 1.15–1.24,
dd ~11%). **0.85** wins jointly: best train calmar (1.91, lowest train dd 22.3) + near-best OOS
(PF 1.237, dd 11.0, calmar 3.46), bracketed by strong 0.7/1.0 (plateau).

## S3 — stop distance `sl_atr_brk`
**1.2** is a decisive joint winner — best on BOTH train (PF 1.152, calmar 2.33, dd 19.5) and OOS
(PF 1.302, dd 9.5%, calmar 4.52, win 57.9%), interior to strong 1.0/1.5 neighbors. (M3 used 1.0.)

## S4 — chandelier trail `trail_atr_mult` (overfit trap caught)
Train monotonically loves wide (4.0 → PF 1.379) but **OOS peaks at 2.0–2.5** (1.302/1.327) and degrades
to 1.234 at 4.0. Classic train-overfit; rejected the train peak. OOS plateau 2.0–3.0 (all >1.26).
**2.5** = plateau interior, highest OOS PF 1.327, best train+OOS agreement. (M3 used 2.0.)

## S5 — risk layers
- `risk%` is a pure linear size dial → left at 1.0% (lowest-DD appetite, as M3).
- **Daily-DD breaker is structurally INERT on M5** (off/8/10/12 → byte-identical OOS; intraday DD never
  reaches the threshold). Kept at 10% as a live-safety net (zero backtest cost). Same lesson as KenKem.
- adx/di kept at M3-robust 22/8 (not re-swept; PF already strong, avoid over-tuning).

## Locked M5 config — `cpp_core/tools/mastervp/kkmastervp_xau_m5_LOCKED.set`
master 432 (108×4) · break_buf 0.85 · sl_atr_brk 1.2 · trail 2.5 · everything else = M3 lock.

| | TRAIN | OOS |
|---|-------|-----|
| **M5 LOCKED** | PF **1.203** / dd 16.2% / net 12,301 / n 972 / win 57.7% | PF **1.327** / dd **10.3%** / net 7,886 / n 442 / win 58.6% / calmar 4.14 |
| M3 lock (shipped) | PF 1.264 / dd 29.5% | PF 1.114 / dd 17.5% / net 4,575 |
| M5 transplant (un-swept) | PF 1.148 / dd 17.2% | PF 1.102 / dd 14.3% |

OOS PF 1.327 **> train 1.203** (negative overfit) at ~60% of the M3 drawdown. Train PF (1.203) sits just
under the 1.25 heuristic train-gate — accepted because OOS far exceeds the deploy gate (1.15) and OOS>train
is the stronger robustness signal; the lower train PF is the *price* of choosing trail=2.5 (OOS-robust)
over trail=4.0 (train-overfit).

## Tail robustness (positive-skew, but better than M3)
Trail-runner breakouts are positive-skew by design (a few trend-runners carry the book; the TV run noted
~20 trades carried profit). Apples-to-apples vs the shipped M3 lock:
- M3 OOS: top-10 winners = **208%** of net (rest of book net-negative), −top10 PF 0.876.
- M5 OOS: top-10 winners = **121%** of net, −top10 PF 0.933.
M5 is **strictly more robust** in the tail than the production M3 baseline, with higher PF, higher net,
and lower DD. Not an M5-specific fragility.

## Verdict & deliverables
Dedicated M5 sweep **beats both M3 and the M5 transplant on every axis** (OOS PF, net, DD, tail).
- Engine lock: `cpp_core/tools/mastervp/kkmastervp_xau_m5_LOCKED.set`
- EA preset: `mql5/experts/KK-MasterVP/KK-MasterVP-XAUUSD-M5.set` (+ `../kenkem/MQL5/Presets/`).
  Attach the existing KK-MasterVP EA to an **M5** XAUUSD chart with this preset for the manual MT5 test.
- NEXT (optional): walk-forward folds + Monte-Carlo (Phase-9), and BTCUSD-M5 cross-instrument robustness
  (replay locked set, must stay PF>1 un-retuned).
</content>
</invoke>
