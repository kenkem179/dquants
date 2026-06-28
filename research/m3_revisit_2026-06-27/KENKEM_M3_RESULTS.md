# KenKem M3 — MT5 results (collected 2026-06-28)

Window 2025.06.01→2026.05.29, real ticks, deposit 10,000. EA KK-KenKem.

| Run | Symbol | TF stack (INPUT_TF0..4) | Net | Trades | Win% | Verdict |
|-----|--------|--------------------------|-----|--------|------|---------|
| ⚠ mis-config | XAUUSD M3 chart | **1/3/5/15/H1 (M1 base!)** | +1,187 | 99 | 49.5% | NOT an M3 test — shifted .set not loaded; M1 strategy on an M3 chart. Discard. |
| ✅ BTC M3 | BTCUSD M3 | 3/5/15/30/H1 (M3 base) | **+141** | 80 | 47.5% | Breakeven. KenKem is XAU-pip-tuned → no edge on BTC, but no blow-up. |
| ❌ XAU M3 | XAUUSD M3 | 3/5/15/30/H1 | — | — | — | **STILL NEEDED** — the important one (XAU = proven instrument). |

Notes:
- KenKem reads data from explicit `INPUT_TF*` timeframes, so the chart TF alone does NOT change the
  strategy base — `INPUT_TF0` must be 3 (M3). Verify via the journal "TIMEFRAME CONFIGURATION" echo.
- M9/M45 don't exist in MT5, so a literal ×3 shift of the M1/M3/M5/M15 stack is impossible; the
  deployable equivalent is M3/M5/M15/M30/H1 (what `KK-KenKem-M3-shifted.set` sets).
