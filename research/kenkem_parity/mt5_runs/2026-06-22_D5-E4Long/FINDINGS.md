# D5-E4Long — E1+E2 lock + E4 LONG-only add-on (XAU M1, MT5, 2025.03–2026.05)

**Date:** 2026-06-22. **Verdict: ✅ UPGRADE. Beats the D3-noE4 lock on net, PF, AND the overfitting
gate — the first KenKem config to PASS the gate. Recommend adopting as the new lock (pending WF+MC).**

## Run (validated clean)
- EA `dquants\KK-KenKem\KK-KenKem`, XAUUSD M1, 2025.03.02–2026.05.29, every-tick.
- Preset `KK-KenKem-XAUUSD-M1-D5-E4Long.set` = D3-noE4 + `ENABLE_E4=true` + `E4_LONG_ONLY=true`.
- **Verified from MT5 log input-dump: `E4_LONG_ONLY=true` applied; E4 fired 25 LONG / 0 SHORT.**
  (First attempt ran a stale cached binary — fixed by MT5 clean-restart; this is the valid run.)

## Result vs the lock
| metric | D3-noE4 (lock) | **D5-E4Long** | Δ |
|---|---|---|---|
| pooled net | +1048.88 | **+1427.17** | **+36%** |
| pooled PF | 1.389 | **1.428** | accretive |
| trades | 102 | 126 | +24 (E4-long adds, ~1 E1/E2 cannibalized) |
| 2026 OOS net/PF | +326.86 / 1.475 | **+497.15 / 1.523** | better on both |
| per-trade Sharpe | 0.138 | **0.145** | quality, not dilution |
| **gate PSR vs 0** | 0.922 WARN | **0.955 PASS** | clears 0.95 |
| **gate MinTRL** | 136 > 102 FAIL | **118 < 126 SUFFICIENT** | clears |

## By kind
| kind | net | PF | n | win% |
|---|---|---|---|---|
| E1 | +737.89 | 1.460 | 58 | 59% |
| E2 | +354.96 | 1.352 | 43 | 44% |
| **E4-long** | **+334.32** | **1.465** | 25 | 44% |

E4-long is net-positive AND PF-accretive — exactly why the blend's PF rises (contrast E5's PF 1.082
which diluted). The add-on barely cannibalizes E1/E2 (101 here vs 102 in the lock).

## The 2026Q2 yellow flag — exonerated
| 2026Q2 | net | n |
|---|---|---|
| E1+E2 subset | **+73.22** | 11 |  ← BETTER than lock's E1+E2 (+56.95) |
| E4-long | **−192.29** | 4 |  ← the entire quarter's drag (2 April stop-outs) |

The soft quarter is NOT a core regime breakdown — E1+E2 actually improved. It's small-sample lumpiness
in the 25-trade E4-long family (2 of 4 trades stopped out in April). E4-long otherwise carries 2026Q1
(+384.44). Risk to note: E4-long's small n means wide quarter-to-quarter swings.

## Decision
- **Adopt D5-E4Long as the new KenKem lock candidate** — strictly dominates D3-noE4 (net ↑, PF ↑, OOS ↑)
  and is the FIRST config to clear the overfitting gate (PSR 0.955 ≥ 0.95, MinTRL 118 < 126).
- This is hypothesis-driven (long-only, derived from the E4 isolation finding), not a wide sweep, so
  multiple-testing inflation is minimal; PSR-vs-0 + MinTRL PASS at the achievable level (DSR n/a — no
  sweep `sr_trial_std`).
- **Prudent next before final lock/release:** walk-forward + Monte-Carlo on D5-E4Long (CLAUDE.md §7),
  watching E4-long's per-fold stability given its small n. Then `make release STRATEGY=KK-KenKem`.
- E4_LONG_ONLY toggle is default-OFF → base clone stays exact-parity; only D5-E4Long.set turns it on.
