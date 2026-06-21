# TradingView / Pine reference trade logs (KK-MasterVP)

Profitable **Pine `strategy()` backtests exported from TradingView** — kept as a *directional*
cross-check target for the C++ engine and the MT5 EA. **Not ground truth** (see caveats): TV is a
different platform AND a different backtest engine than MT5/Exness. But XAUUSD price is consistent
across venues, so what reproduces on OANDA here should be broadly reproducible on Exness MT5 — this is
the comparison anchor for that claim.

> Distinction from `../mt5_runs/`: those are real MT5 tester outputs used for *strict byte-parity*
> (`/quant-0-parity-baseline`). These TV logs are a *softer* sanity reference — they can corroborate a
> direction/magnitude, they cannot certify parity.

## Files

### `trades_pine_oanda_XAUUSD_M3_365d_2026-06-21.csv`
KK-MasterVP Pine on **OANDA XAUUSD, M3**, the 365 days ending 2026-06-21.
Source: TradingView "List of Trades" export (UTF-8 BOM stripped on import).

| metric | value |
|---|---|
| window | 2025-06-20 → 2026-06-19 (364 d) |
| closed legs (TV trade numbers) | **5,196** |
| distinct entries (dt+dir) | **2,598**  (~7/day — the M3 trade-frequency case) |
| win rate | **57.1 %** |
| profit factor | **1.244** |
| net P&L | **+$283,344** (start 10k, compounded; final cum P&L column) |
| dir mix | 2,648 short / 2,548 long |

Schema (TV): `Trade number,Type,Date and time,Signal,Price USD,Size (qty),Size (value),`
`Net PnL USD,Net PnL %,Favorable excursion USD/%,Adverse excursion USD/%,Cumulative PnL USD/%`.

## Read-before-trusting caveats
- **TV books TP1 and TP2 partials as separate Trade numbers** → 5,196 *legs* ≈ 2,598 *distinct
  entries* (each entry usually = a TP1 leg + a runner/TP2 leg, same entry timestamp). Compare on
  *entries*, not raw leg counts, against the engine/MT5.
- Pine declares `commission cash_per_order 0.50`, `slippage 8 ticks`, `calc_on_every_tick=true`,
  `use_bar_magnifier=true` — its fill model differs from both the C++ engine and MT5.
- OANDA feed ≠ Exness feed (spread/microstructure differ); intrabar path differs.
- Pine backtesting is **not 100 % trustworthy** (user's words) — treat as a directional corroboration,
  always re-confirm a lock in MT5 (`/quant-0-parity-baseline`, notebook §8).

## Why M3 (user's thesis)
M5 means far fewer trades/day (longer master-POC window) — wasted opportunity. **M3 is the intended
target**: ~7 entries/day here vs the M5 lock's sparser cadence. The existing C++ study config
(`KK-MasterVP-XAUUSD-M3-BASE.set`, used in `MasterVP_End_to_End.ipynb`) is already M3 — this log is its
first external corroboration target. Next: run the engine on XAU M3 over this exact window and compare
net/PF/entry-cadence (cross-platform, so expect a divergence band, not a match).
