# VP-length re-sweep — are we missing edge on BTC M3, BTC M5, XAU M3? (2026-06-22)

**User ask:** re-run VP-length (and other needed) sweeps to make sure we are not missing great
opportunities on **BTC M3, BTC M5, XAU M3**.

**TL;DR — No missed VP-length edge. All locks sit on robust train+OOS plateaus.** BTC M3 has NO
breakout edge at ANY master-VP length (structurally dead). The genuine remaining opportunities are
*not* VP-length — they are the two structural ideas the user raised: SL-beyond-FVG for M3 breakouts
and reversion-on-LOCAL-VP (both need engine work; tracked in BUILD-PLAN).

## Method
- Master VP length = `InpVpLookback × InpMasterMult` is the **sole** breakout driver (local VP inert in
  breakout-only mode — `VP_LENGTH_STUDY.md`). We scan master-bar count by varying `InpMasterMult` at the
  lock's `InpVpLookback`, on **both** the TRAIN and OOS tick windows, and plateau-pick: a length only
  counts if positive on BOTH windows (not a train-only or OOS-only spike).
- Harness: `research/mastervp_parity/vp_length_sweep_2026-06-22.py` (raw output `_vplen_sweep_M1bars.out`).
- Engine: `cpp_core/build/backtester` (rebuilt from HEAD this session — Monster-merge engine, all new
  families OFF by default). `--trade-to-ms` caps train at OOS start → no leakage.

### ⚠️ Data-integrity correction (important — read this)
The per-year XAU M3 bar file (`bars_xauusd_2026_m3.csv`, built Jun 16) was **incomplete**: 29,399 bars
for 2026 vs 48,161 from an M1 resample — it is missing whole XAU trading days that the Jun-19 M1 rebuild
added (matches [[bar-parity-solved-missing-days]]). The first sweep run on those stale concatenated bars
gave inflated XAU numbers. **All combined bars were rebuilt from the authoritative full-range M1 file**
(`bars_xauusd_2024_2026_m1.csv` / `bars_btcusd_2025_2026_m1.csv`, bit-exact vs MT5) via
`cpp_core/tools/resample_m1.py` (M3/M5 = floor-to-TF aggregation of M1 OHLC; exact). **Validation:** on
the corrected bars the XAU-M3 lock TRAIN PF = **1.258**, matching the documented 1.264 → data now right.
BTC's 2026 OOS bars were already identical between sources (verified), so BTC OOS was never affected.

## Results (corrected M1-resampled bars)

### XAU M3 — lock 480b (120×4). NO missed edge; lock on plateau, lowest DD.
| master | TRAIN PF/net/dd% | OOS PF/net/dd% | |
|---:|---|---|---|
| 240 | 1.033 / +2086 / 46.5 | 1.035 / +694 / 25.3 | weak |
| 360 | 1.238 / +18285 / 18.9 | 1.073 / +1396 / 21.5 | |
| **480** | **1.258 / +20518 / 28.6** | **1.320 / +5583 / 11.5** | **LOCK — lowest OOS DD** |
| 600 | 1.097 / +5424 / 28.3 | 1.163 / +2966 / 22.8 | |
| 720 | 1.199 / +14989 / 18.8 | 1.355 / +5552 / 14.1 | co-equal (↑PF, ↑DD) |
| 960 | 1.159 / +9562 / 18.1 | 1.264 / +3886 / 13.7 | plateau edge |
| 1200 | 1.084 / +3789 / 32.7 | 0.978 / −302 / 22.1 | collapses |
Plateau 480–960 positive on both windows. Lock (480) has the **lowest OOS DD (11.5%)**; 720 is a
co-equal alternative (OOS PF 1.355 but DD 14.1%). XAU M3 lock is MT5-exact-parity-validated — not worth
disturbing for a marginal, single-window PF tick. **Verdict: keep 480.**

### BTC M5 — lock 720b (24×30). NO missed edge; lock = lowest OOS DD.
| master | TRAIN PF/net/dd% | OOS PF/net/dd% | |
|---:|---|---|---|
| 360 | 1.019 / +275 / 13.5 | 0.988 / −247 / 37.0 | |
| 480 | 1.312 / +4043 / 12.9 | 0.940 / −1123 / 38.5 | train-only (overfit) |
| 600 | 1.171 / +1983 / 16.8 | 1.121 / +2384 / 16.4 | plateau |
| **720** | **1.150 / +1940 / 13.6** | **1.263 / +5530 / 14.7** | **LOCK — lowest OOS DD** |
| 840 | 1.087 / +994 / 12.9 | 1.123 / +2572 / 37.2 | |
| 960 | 1.333 / +3805 / 11.2 | 1.282 / +5204 / 20.4 | alt: ↑train ↑PF, ↑DD |
| 1200 | 1.197 / +2504 / 14.5 | 1.139 / +2519 / 24.1 | |
| 1440 | 1.094 / +1072 / 17.7 | 1.358 / +6207 / 21.9 | OOS-only (thin train) |
Plateau 600–960 positive on both. Lock (720) has the best DD-adjusted profile (OOS PF 1.263 @ DD 14.7%).
960 is a real alternative (best TRAIN PF 1.333, OOS PF 1.282) but +5.7pts OOS DD. 1440's high OOS PF is a
tail/curve-fit (train only 1.094). **Verdict: keep 720.** (BTC M5 remains MT5-marginal regardless — feed
caveat; not a deploy front-runner.)

### BTC M3 — NO LOCK. NO edge at any VP length. Structurally dead for breakout.
| master | TRAIN PF/net/dd% | OOS PF/net/dd% |
|---:|---|---|
| 360 | 0.784 / −6688 / 70.1 | 0.816 / −8194 / 87.0 |
| 480 | 0.748 / −7185 / 72.3 | 0.828 / −7206 / 82.6 |
| 720 | 0.900 / −3310 / 42.3 | 0.773 / −8598 / 89.9 |
| 960 | 0.810 / −5657 / 63.0 | 0.790 / −8012 / 84.1 |
| 1440 | 0.883 / −3621 / 40.9 | 0.778 / −7976 / 84.4 |
| 1920 | 0.794 / −5598 / 58.6 | 0.822 / −6735 / 72.1 |
| 2880 | 0.879 / −3846 / 42.5 | 0.890 / −4685 / 63.5 |
Every length is a **net loser on BOTH windows** (PF 0.75–0.90, DD 40–90%, 800–1550 trades). BTC M3
breakout over-trades a too-noisy TF and bleeds. VP-length tuning cannot fix this — it's a mechanism
problem, not a parameter. **The opportunity on BTC M3 is a different entry geometry (FVG-SL / local-VP
reversion), or simply not trading BTC on M3.**

## Secondary-lever plateau check (ADX / break-buf / SL at lock VP)
Each lever swept around its lock on BOTH train+OOS (`_vplen_secondary.out`). **Every lock is confirmed
on the joint basis — no alternative beats it on train AND OOS together.**

### XAU M3 (lock: ADX22 / break0.7 / SL1.0)
| lever | best joint | note |
|---|---|---|
| ADX | **22** (OOS 1.320) — 18/26/30 all lower OOS | lock confirmed |
| break-buf | **0.7** (OOS 1.320); 0.55 slightly ↑train but ↓OOS | lock confirmed |
| SL-atr | **1.0** (OOS 1.320/dd11.5). **1.3 = OOS 1.405/dd8.7 BUT train collapses 1.258→1.153/dd43%** | ⚠️ OOS-only spike, NOT a plateau — curve-fit trap, do NOT chase |

### BTC M5 (lock: ADX30 / break1.0 / SL2.2)
| lever | best joint | note |
|---|---|---|
| ADX | **30** (train 1.150 + OOS 1.263) — 18/22/26 all weak on ≥1 window | lock confirmed |
| break-buf | **1.0** (OOS 1.263/dd14.7); lower bufs ↑train but blow OOS dd to 28% | lock confirmed |
| SL-atr | **2.2** (widest) wins BOTH windows; **tighter stops collapse it** (0.7→OOS PF 0.773/dd64%) | lock confirmed |

**Cross-cutting signal for the FVG work:** on BTC M5 the SL lever is monotone — *wider* breakout stops
strictly help (0.7→2.2 flips OOS PF 0.773→1.263). The XAU SL=1.3 OOS bump points the same way. This is
exactly the user's FVG-SL thesis (anchor the stop *beyond* structure so noise can't tag it). The lesson
the secondary sweep adds: a blind wider-ATR stop trades OOS PF for train PF (XAU 1.3 case) — a *structural*
stop (beyond the FVG) is the disciplined way to get the OOS benefit without the train degradation. → motivates
the FVG-SL engine work below rather than just loosening `InpSlAtrBrk`.

## Conclusions / next
1. **VP-length is settled** — no missed opportunity; locks are well-placed. Do not chase single-window
   PF ticks (720 XAU / 960 BTC-M5) — they cost DD and need a 6-fold WF before any lock change, and the
   current locks are MT5-validated.
2. **BTC M3 breakout is dead** at every VP length — pursue it only via a new mechanism.
3. **Real opportunity levers (tracked in BUILD-PLAN):**
   - SL-beyond-FVG for M3 breakouts (await user's examples → implement OFF-by-default, sweep).
   - Reversion fades LOCAL VP node, not master VP (`[[reversion-local-vp-assumption]]`; currently master).
