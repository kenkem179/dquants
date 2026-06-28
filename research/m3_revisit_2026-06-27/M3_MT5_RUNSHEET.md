# M3 REVISIT — MT5 runsheet (settle M3 on the trusted judge, not the engine)

**Why:** MasterVP's profitable origin was XAU **M3** (Pine PF 1.24) and it shipped as an M3 lock
(OOS PF 1.114). It was demoted to M5 on a **C++-engine** comparison — the same engine whose
exit/runner accounting we later proved untrustworthy (the real M5 lock was found on the MT5
optimizer, *because the engine over-credits trailed runners*, which structurally favours M5's
bigger-runner config). M3 was never given the MT5-optimizer head-to-head M5 got. These 4 runs fix that.

Load each `.set` in **Strategy Tester → Inputs → Load** from the `dquants/<expert>/` folder.
Common to all: model **"Every tick based on real ticks"**, deposit **10000 USD**, leverage as your live.

---

## RUN 1 — MasterVP XAUUSD M3 (OPTIMIZER)  ⭐ the head-to-head
| | |
|---|---|
| Expert | **KK-MasterVP-Debug** |
| Symbol / TF | **XAUUSD** / **M3** |
| Dates | **2025.06.01 → 2026.05.29** (same window as the M5 lock) |
| `.set` | `KK-MasterVP/KK-MasterVP-XAUUSD-M3-OPT.set` |
| Mode | **Optimization = "Slow complete algorithm"**, rank by **Profit Factor** |
| Grid | `InpVpLookback` 80→240 step 20 (9) × `InpSlAtrBrk` 1.0/1.25/1.5 = **27 passes** |
| Exit (FIXED, proven) | RunnerRr 4.0 · Trail 2.75 · BeBuf 0.02 · Tp1Close 0 · **ProgTrail ladder 2.0/0.75/0.2** |
| **Pass bar** | beat the **XAU M5 lock PF 1.4246** (and watch maxDD). If a VpLookback plateau holds PF≥M5 with comparable DD, M3 is back in play. |

## RUN 2 — MasterVP BTCUSD M3 (OPTIMIZER)
| | |
|---|---|
| Expert | **KK-MasterVP-Debug** |
| Symbol / TF | **BTCUSD** / **M3** |
| Dates | **2025.01.01 → 2026.05.29** |
| `.set` | `KK-MasterVP/KK-MasterVP-BTCUSD-M3-OPT.set` |
| Mode | **Optimization = "Slow complete algorithm"**, rank by **Profit Factor** |
| Grid | `InpVpLookback` 16→48 step 4 (9, ×30 = 24h–72h) × `InpSlAtrBrk` 1.5/2.0/2.5 = **27 passes** |
| Exit (FIXED) | proven capped+ladder (same as Run 1) — beat wide RR10 on BTC in prior tests |
| **Pass bar** | any pass **PF > 1** on the FULL window with non-catastrophic DD. BTC was full-window <PF1 on M5; this asks whether M3 + the good exit clears 1.0 on the trusted judge. |

## RUN 3 — KK-KenKem XAUUSD M3 (single backtest, first look)
| | |
|---|---|
| Expert | **KK-KenKem** |
| Symbol / TF | **XAUUSD** / **M3** |
| Dates | **2025.06.01 → 2026.05.29** |
| `.set` | `KK-KenKem/KK-KenKem-M3-shifted.set` |
| Mode | **single backtest** (no optimization) |
| What it is | the D5-E4Long lock with the TF stack shifted **M1/M3/M5/M15/H1 → M3/M5/M15/M30/H1** (all MT5-native — M9/M45 don't exist, so a literal ×3 shift is impossible; this is the deployable equivalent). |
| Read | does it produce *any* edge? KenKem is M1-native (EMA periods 10/25/71/97/192 were tuned for the M1 stack), so on the shifted stack the horizons differ — this is a "see what happens" probe, not a tuned config. If it shows promise, we optimize. |

## RUN 4 — KK-KenKem BTCUSD M3 (single backtest, first look)
| | |
|---|---|
| Expert | **KK-KenKem** |
| Symbol / TF | **BTCUSD** / **M3** |
| Dates | **2025.01.01 → 2026.05.29** |
| `.set` | `KK-KenKem/KK-KenKem-M3-shifted.set` (same file as Run 3 — symbol is a tester setting) |
| Mode | **single backtest** |
| ⚠ Caveat | the lock's pip-based tolerances (e.g. `EMA_ALIGNMENT_TOLERANCE_PIPS=23`) are XAU-tuned; the EA auto-detects pip from digits but the *values* aren't BTC-tuned. Raw first look only. |

---

## After you run
- Leave each optimization `.opt` in the MT5 cache (I parse it with `scripts/parse_mt5_opt.py`) **or** export the
  results to XML. For the single KenKem runs, the standard backtest report is enough.
- I'll collect, compare M3 vs the M5/M1 locks on **PF · net · maxDD · tail**, run the winner through the
  overfitting gate, and update the plan — correcting "M3 rejected" to whatever the trusted judge actually says.
