# E4-only — standalone E4 edge isolation (XAU M1, MT5, 2025.03–2026.05)

**Date:** 2026-06-21. **Verdict: ❌ E4 standalone is a NET LOSER (no edge) — but two strong asymmetries make it a rework candidate, not a write-off.**

## Run
- EA `dquants\KK-KenKem\KK-KenKem`, XAUUSD M1, 2025.03.02–2026.05.29, every-tick.
- Preset `KK-KenKem-XAUUSD-M1-E4only.set` (ONLY `ENABLE_E4=true`; E1/E2/E3/E5 off; else = D3-noE4).

## Result
| cut | net | PF | n | win% |
|---|---|---|---|---|
| **pooled** | **−98.52** | **0.952** | 73 | 41% |
| 2025 | −252.48 | 0.854 | 64 | 39% |
| 2026 (OOS) | +153.96 | 1.466 | 9 | 56% |

Gate: per-trade Sharpe **−0.0143**, PSR vs 0 **0.452** (below coin-flip), MinTRL ∞. **No confirmable edge.**
Confirms the long-standing "E4 = MT5 net-loser" finding — as a blanket signal E4 does not work.

## The two asymmetries (the optimization hooks for later)
**1. Direction — the short side IS the whole loss:**
| dir | net | PF | n | win% |
|---|---|---|---|---|
| **LONG** | **+387.75** | **1.400** | 35 | 40% |
| **SHORT** | **−486.27** | **0.555** | 38 | 42% |

E4 LONGS are genuinely profitable (PF 1.40); E4 SHORTS are garbage. A long-only E4 flips the family
positive. (Plausible: E4 = "smart early trend" — early-trend longs in a secular gold uptrend catch the
move; early shorts get run over.)

**2. Exit tag — the management exit bleeds:**
| exitTag | net | n | win% | read |
|---|---|---|---|---|
| TP | +1302.55 | 8 | 100% | target hits are clean |
| SL-WIN | +463.90 | 16 | 100% | trailed-to-profit clean |
| SL-LOSS | −965.89 | 16 | 0% | hard stops |
| **EA** | **−899.08** | **33** | **18%** | ← the management/early-cut exit is the bleed |

45% of trades exit via the `EA` (manager) path at 18% win / −899 — it cuts winners short and/or holds
losers. The raw entry isn't catastrophic; the exit handling on E4 is.

## Read for optimization (deferred per user — after E3-only collected)
- E4 is NOT shippable as-is, but **long-only E4 + an exit-path fix** is a real lever. Candidate sweeps:
  (a) E4 LONG-only toggle; (b) tighten/disable the `EA` early-cut for E4; (c) E4 as an *add-on* to the
  E1+E2 lock (does long-only E4 lift the D3-noE4 blend without diluting PF?). Each MT5-gated.
- Any E4 lock must clear `research/stats/gate.py` standalone, not just pool-and-pass (the E5 lesson).
