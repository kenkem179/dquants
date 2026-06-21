# E3-only — standalone E3 edge isolation (XAU M1, MT5, 2025.03–2026.05)

**Date:** 2026-06-21. **Verdict: ❌ DEAD. E3 is a sparse net-loser (20 trades, PF 0.497). Not optimizable — leave OFF.**

## Run
- EA `dquants\KK-KenKem\KK-KenKem`, XAUUSD M1, 2025.03.02–2026.05.29, every-tick.
- Preset `KK-KenKem-XAUUSD-M1-E3only.set` (ONLY `ENABLE_E3=true`; else = D3-noE4).

## Result
| cut | net | PF | n | win% |
|---|---|---|---|---|
| **pooled** | **−145.06** | **0.497** | **20** | 25% |
| LONG | +21.10 | 1.177 | 11 | 36% |
| SHORT | −166.16 | 0.019 | 9 | 11% |
| exit `EA` | −253.39 | — | 18 | 17% |

## Read
- **20 trades in 15 months = unoptimizable.** Any param sweep on 20 samples is instant overfit; the gate
  is hopeless (negative Sharpe). There is no statistical surface to optimize against.
- Same shape as E4: shorts catastrophic (PF 0.019, 1 win/9), longs marginally positive but tiny (+21 over
  11 = noise), and 18/20 exit via the `EA` manager path at 17% win.
- The original "E3 is horrible" assessment is confirmed in MT5. A rework would have to be a from-scratch
  signal redesign (the current counter-trend reversal logic simply doesn't fire enough or win enough), not
  a parameter tune — out of scope for the current lock effort.

## Decision
- **E3 stays OFF.** No optimization attempted (no sample to optimize on). Revisit only as a fresh signal-
  design project if ever desired, with its own discovery → backtest → gate chain.
