# KenKem (distilled) — results

The original `KenKemExpert.mq5` (~9.7k LOC, E1/E2/E4 + many gates/exits) was **distilled** to its
essential winning core in a separate `kk::kenkem` C++ engine (config → tf-cache → triggers → snapshot →
gates → entries → trade-manager → engine), not byte-reproduced. Validation = the quant SOP (costs →
optimize → train/test → OOS → Monte Carlo → spread sensitivity), not MT5 byte-parity.

## Headline — the entries are a MENU (toggle separately or combine)
KenKem's value is its **four independently-toggleable entries**, confirmed by the data:

**Standalone PF, BTC 2025 (untuned defaults), every one profitable:**
| Entry | PF | Win% | Net | Character |
|---|---|---|---|---|
| **E5** SuperBros (fresh strict M1 EMA-stack align + price>EMA25) | **1.147** | 57% | +$47k | best standalone |
| **E4** Ichimoku Tenkan/Kijun cross | 1.090 | 46% | +$41k | high-selectivity |
| **E1** EMA-stack cross (MTF + momentum) | 1.064 | 41% | +$21k | trend continuation |
| **E2** EMA75 pullback touch | 1.036 | 51% | +$18k | pullback |

**Optimized combinations (the production picks), 2026 true OOS:**
| Symbol | Best combo | 2025 PF | **2026 OOS PF** | OOS net | maxDD |
|---|---|---|---|---|---|
| BTC (max PF) | **E4 only** | 1.270 | **1.239** | +$61k | $8.6k |
| BTC (max net) | **E1+E4+E5** | 1.210 | 1.145 | **+$79k** | $10.2k |
| XAU (best) | **E4+E5** | 1.247 | **1.132** | +$32k | $5.9k |

Takeaways: **E5 was wrongly skipped initially and is the strongest standalone**; **E5 improves XAU**
(E4+E5 beats E4-only on both PF and net OOS); on BTC, E4-only maximizes PF while E1+E4+E5 maximizes net
with every entry contributing positively OOS. E2 rarely makes the optimized cut but is profitable solo.

## Numbers (fixed-fraction sizing on $10k, costs modelled)
| | 2025 (IS, train+test) | 2026 (true OOS) |
|---|---|---|
| **BTC** PF | **1.270** (test-split 1.201) | **1.239** |
| BTC net / maxDD | +$149.6k / $4.9k | +$61.3k / $8.6k |
| BTC win% | 57.5% | 57.3% |
| **XAU** PF | **1.207** (test-split 1.074) | **1.083** |
| XAU net / maxDD | +$78.0k / $4.5k | +$14.1k / $8.0k |

## Robustness (all on OUR engine — kk::kenkem is the authoritative backtest, no MT5 needed)
`research/optimization/robustness_kenkem.py` — monthly breakdown + MC + spread sensitivity.

**Production combos:**
| Combo | Months +ve | MC %prof | PF P5 | spread sweep |
|---|---|---|---|---|
| BTC E1+E4+E5 (2026 OOS) | 6/6 | 100% | 1.096 | PF 1.145→1.058 ($2→$6) |
| XAU E4+E5 (2026 OOS) | 5/5 | 99.8% | 1.057 | PF 1.139→1.103 ($0.03→$0.12) |
| BTC E1+E4+E5 (2025 IS) | 11/11 | 100% | 1.173 | — |
| XAU E4+E5 (2025 IS) | 11/12 | 100% | 1.194 | — |

E4-only BTC alt: 2026 MC 100% profitable, PF P5 1.164; spread PF 1.270→1.173 ($2→$6). Near-every month
positive across two years; every entry contributes positively OOS (E5 the strongest leg). Edges survive
3× spread.

## Entry-set comparison (2026-06-14, user request — "what to keep in production")
Controlled experiment (`sweep_kenkem_entrysets.py`): each entry-set FORCED on, an INDEPENDENT 400-trial
Optuna search over shared + active-entry params on 2025, winner re-run on **2026 = true OOS** (the
production decider). E3 is absent in the distilled engine, so the requested E1&E3&E5 ran as E1&E5.

**Ranked by 2026 OOS PF:**

| BTC combo | OOS PF | OOS net | IS PF | note |
|---|---|---|---|---|
| **E5** | **1.523** | 55.6k | 1.606 | most robust per-trade edge; near-perfect IS→OOS |
| **E2+E5** | 1.348 | **124.8k** | 1.345 | best net among robust combos; IS≈OOS (very stable) |
| E4 | 1.291 | 89.0k | 1.295 | solid, stable |
| E2 | 1.273 | 99.6k | 1.262 | solid (OOS≥IS) |
| ALL | 1.207 | 121.7k | 1.241 | net high, PF diluted |
| E1+E5 | 1.193 | 66.0k | 1.376 | **overfits** (1.376→1.193) |
| E1+E2 | 1.166 | 91.1k | 1.191 | |
| E1+E2+E4 | 1.133 | 78.2k | 1.211 | degrades |
| E1 | 1.121 | 27.8k | 1.267 | weakest; degrades OOS |

| XAU combo | OOS PF | OOS net | IS PF | note |
|---|---|---|---|---|
| **E5** | **1.636** | 33.1k | 1.635 | best PF, perfect consistency, low net |
| E1 | 1.380 | 28.0k | 1.257 | strong standalone (OOS>IS) |
| **E2** | 1.355 | 62.1k | 1.221 | high net + robust (OOS>IS) |
| E1+E5 | 1.307 | 43.7k | 1.374 | |
| **E2+E5** | 1.270 | 63.2k | 1.247 | best net+robust blend |
| E1+E2 | 1.234 | 57.1k | 1.191 | |
| E4 | 1.168 | 40.2k | 1.262 | **degrades OOS** (1.262→1.168) |
| E1+E2+E4 | 1.167 | 62.3k | 1.193 | E4 drag |
| ALL | 1.166 | 84.2k | 1.189 | net high, PF lowest |

**Findings (every combo is OOS-profitable):**
- **E5 (SuperBros M1 EMA-alignment) is the most robust entry on BOTH symbols** — highest OOS PF, IS≈OOS.
  Confirms keeping E5 as the core. Current BTC prod (E5-only) is the most robust single config.
- **E1 is the weakest** (lowest OOS PF on BTC; only decent standalone on XAU) and the E1 combos OVERFIT
  (IS PF collapses OOS). Recommend dropping E1.
- **E4 degrades OOS on XAU** (1.262→1.168) — it is the weak leg inside the current XAU prod (E2+E4+E5).
- **E2 is a strong, robust net contributor** on both (OOS≥IS).
- **Recommended production: E2+E5 on both symbols** — best blend of high net + robust OOS PF + IS≈OOS
  consistency, dropping the two weak/overfitting legs (E1 everywhere, E4 on XAU). vs current:
  BTC E5-only → E2+E5 keeps OOS PF 1.35 while **2.2× the net** (56k→125k); XAU E2+E4+E5 → E2+E5 drops the
  E4 drag (OOS PF 1.17→1.27 at similar net). Each combo's tuned config saved as
  `best_kenkem_<combo>_<sym>.set` — promotion to the locked `best_kenkem_<sym>.set` pending user sign-off.

## Artifacts
- Engine: `cpp_core/include/kk/kenkem/*.hpp` (8 unit tests, 131 checks).
- Backtester: `cpp_core/tools/kenkem/backtester.cpp` (loads M1, aggregates M3/M5/M15).
- Optimizer: `research/optimization/optimize_kenkem.py` → `best_kenkem_{btc,xau}.set`.
- Bars: `cpp_core/tools/bars_{btcusd,xauusd}_{2025,2026}_m1.csv`.

## Caveats / honesty
- Bars are BID + a fixed modelled spread (not per-bar); intra-bar fills use an adverse-first OHLC walk.
  These are standard backtest approximations, conservative on fills.
- "Distilled" ≠ the live EA. To deploy, a thin EA must match THIS engine's E4 logic + sizing (see
  promotion plan). The existing EA's E4 differs (extra gates, compounding sizing, the 8-way exit cascade).
