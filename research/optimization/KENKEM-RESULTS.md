# KenKem (distilled) — results

The original `KenKemExpert.mq5` (~9.7k LOC, E1/E2/E4 + many gates/exits) was **distilled** to its
essential winning core in a separate `kk::kenkem` C++ engine (config → tf-cache → triggers → snapshot →
gates → entries → trade-manager → engine), not byte-reproduced. Validation = the quant SOP (costs →
optimize → train/test → OOS → Monte Carlo → spread sensitivity), not MT5 byte-parity.

## Headline
The optimizer **disabled E1 (EMA-stack cross) and E2 (EMA75 pullback)** — they added drawdown without
edge. The robust strategy is **E4 only: the Ichimoku Tenkan/Kijun cross**, gated by a high ADX-momentum
requirement (~26), multi-TF DI alignment, a sideways/chop block, and an M5/M15 HTF filter; tight
structure SL (ATR-capped ~2×), RR ~1.7, partial-TP at ~53% then a 0.27× chandelier trail.

## Numbers (fixed-fraction sizing on $10k, costs modelled)
| | 2025 (IS, train+test) | 2026 (true OOS) |
|---|---|---|
| **BTC** PF | **1.270** (test-split 1.201) | **1.239** |
| BTC net / maxDD | +$149.6k / $4.9k | +$61.3k / $8.6k |
| BTC win% | 57.5% | 57.3% |
| **XAU** PF | **1.207** (test-split 1.074) | **1.083** |
| XAU net / maxDD | +$78.0k / $4.5k | +$14.1k / $8.0k |

## Robustness
- **BTC 2026 OOS Monte Carlo** (5000 bootstraps, n=2916): **100% profitable**, PF P5 **1.164**, net P5 $43k.
- **BTC spread sensitivity** (optimized set): PF 1.270 ($2) → 1.246 ($3) → 1.221 ($4) → 1.173 ($6).
  The edge survives double the realistic spread.

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
