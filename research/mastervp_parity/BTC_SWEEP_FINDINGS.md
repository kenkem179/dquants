# KK-MasterVP — BTCUSD sweep, NO SESSION (trade 24/7), M3 & M5 (2026-06-20)

User asked: sweep MasterVP on BTCUSD, no session filter (trade anytime), M3 and M5.
24/7 modelled as 3 sessions covering the full day (Asia 00-08 / Ldn 08-16 / NY 16-24, offset 0) so
`inAnySession` is always true; per-session trade counter still resets 3×/day (maxTrades=4 → 12/day).

Data: combined bars `bars_btcusd_2025_2026_{m3,m5}.csv` (built this session). TRAIN = Aug–Nov 2025
(`ticks_btcusd_2025_window.csv`, ~3.5mo); OOS = Jan–Jun 2026 (`ticks_btcusd_2026_oos.csv`, ~5mo).
Harness `sweep.py --symbol btc`. Costs modelled (bid/ask + BTC specs). Base sets transplant XAU structural
params; master-len + entry/exit RE-SWEPT for BTC.

## Headline
- **M3 BTC = NO robust edge.** Best train config reaches PF ~1.13, but **every train-positive config
  collapses OOS** (PF 0.72–0.83, DD 57–75%) — pure overfit to the 3.5-mo train window. Do NOT deploy.
- **M5 BTC = a modest but plateau-robust edge** at a LONG master (60h) + strong trend filter. Positive on
  BOTH train and OOS across a 4-D plateau (master × adx × sl × trail). Tail-skewed (caveat below). Shipped.

## M3 — overfit, rejected
XAU-transplanted params lose outright (PF 0.76 train / 0.82 OOS). Master-length: all losing, longer = less
bad (720b/36h least-bad). Best train after sl/trail/adx/buf tuning: master720, sl1.6, trail6.0, adx26,
buf1.0 → **train PF 1.132 / dd 21.2%**. The same family OOS: **PF 0.72–0.83, net −5.5k to −7.4k, DD 57–75%.**
Train and OOS are *anti-correlated* on M3 — the Aug–Nov 2025 and Jan–Jun 2026 BTC regimes disagree. No lock.

## M5 — robust plateau (the real finding)
Win-rate ~50% with XAU params (PF 0.73–0.88, all losing). The edge appears only with a **long master +
strong filters + wide stops/trail** (trend-following geometry). Neighborhood sweep, **both windows
positive across the whole adx∈{28,30} × master∈{48,60,72h} block:**

TRAIN PF (dd%) — master(h) × adx, at sl2.2/trail6/buf1.0:
| master | adx28 | adx30 | adx32 |
|--------|-------|-------|-------|
| 48h | 1.242(11.7) | 1.357(10.6) | 1.257(14.9) |
| 60h | 1.118(17.7) | 1.155(13.9) | 1.117(14.6) |
| 72h | 1.199(10.6) | 1.247(8.6) | 1.198(11.3) |

OOS PF (dd%):
| master | adx28 | adx30 | adx32 |
|--------|-------|-------|-------|
| 48h | 1.136(15.0) | 1.134(13.9) | 1.027(21.7) |
| 60h | 1.257(10.5) | 1.214(14.2) | 0.985(25.4) |
| 72h | 1.268(16.7) | 1.174(22.4) | 1.083(27.4) |

adx32 is the cliff edge (OOS weakens to ~1.0). The robust interior = **adx 28–30, master 48–72h**.
Exit grid is ALSO a full plateau: sl∈{2.2,2.6} × trail∈{4,6,8} all PF>1.0 on **both** windows (sl1.8 is
marginal); sl2.2/trail6 is the OOS peak.

### Locked M5 BTC config — `cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set`
master **720 bars (60h)** = `VpLookback24 × MasterMult30` · `adx_trend_min 30` · `break_buf 1.0` ·
`sl_atr_brk 2.2` · `trail_atr_mult 6.0` · 24/7 sessions · rest = XAU defaults (rr1.8, tp1 0.8R/20%, BE,
risk1%, daily-DD10%, di8, ema24/194, atr14).

| | TRAIN | OOS |
|---|-------|-----|
| **M5 BTC LOCKED** | PF **1.155** / dd 13.9% / net +2,032 / n 270 / win 59.3% | PF **1.214** / dd 14.2% / net +4,228 / n 380 / win 57.4% |

OOS PF > train (no overfit), plateau-interior pick (every neighbor positive both windows).

### Caveat — positive-skew / tail-dependent
M5 BTC OOS top-10 winners = **219% of net** (−top10 → PF 0.745); train 330%. More tail-dependent than
XAU M5 (121%), comparable to the shipped XAU **M3** baseline (208%). This is the expected shape of a
trend-breakout-with-wide-trail (cut many small losers, a few big runners pay) — but it means BTC M5 is a
**lower-conviction** edge than XAU. Treat as a candidate for forward-test, not a high-confidence lock.

## Deliverables
- Engine locks: `kkmastervp_btc_m5_LOCKED.set` (shipped). M3 = no lock (no edge).
- EA preset: `mql5/experts/KK-MasterVP/KK-MasterVP-BTCUSD-M5.set` (+ kenkem Presets) — 24/7, attach EA to a
  **BTCUSD M5** chart.
- Base sets: `m3_base_btc.set`, `m5_base_btc.set` (no-session). Combined bars `bars_btcusd_2025_2026_{m3,m5}.csv`.
- NEXT (optional): walk-forward folds to further stress the M5 edge; revisit if more BTC history is imported
  (the short 3.5-mo train is the main robustness limiter).
</content>
