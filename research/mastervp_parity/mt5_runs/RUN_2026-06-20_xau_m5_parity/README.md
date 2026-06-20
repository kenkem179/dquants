# RUN_2026-06-20_xau_m5_parity — first EA↔engine trade-level parity check

First production-gate parity run for the KK-MasterVP XAU M5 lock. **VERDICT: FAIL.**

## The MT5 run
- **Pair/TF:** XAUUSD-Exness-KK, **M5**
- **Period:** 2026.01.01 00:00 → 2026.06.01 00:00 (UTC)
- **Expert:** `dquants\KK-MasterVP\KK-MasterVP.ex5`
- **Set:** `KK-MasterVP-XAUUSD-M5.set` (= `used.set`) + `InpExportParity=true`
- Output: `trades_mt5_xau_m5.csv` (631 trades). Log slice: `tester_xau_m5.log`.

## The engine run (matched window)
```
./build/backtester --bars tools/bars_xauusd_2026_m5.csv --ticks tools/ticks_xauusd_2026_oos.csv \
  --set-all tools/mastervp/kkmastervp_xau_m5_LOCKED.set --symbol-xau \
  --trade-from-ms 1767225600000 --trade-to-ms 1780272000000 --out trades_cpp_xau_m5.csv
```
→ `trades_cpp_xau_m5.csv` (563 trades). Diff: `parity_report.txt` (`parity_diff.py --bar-seconds 300`).

## Result
| metric | engine | MT5 |
|---|---|---|
| trades | 563 | 631 |
| matched pairs | 416 | |
| unmatched | 147 engine-only | 215 MT5-only |
| net P&L | +10,334 | +2,027 (Δ 409%) |
| profit factor | 1.316 | 1.071 |
| exit-tag mismatch | 141/416 | |

## Diagnosis — entries are faithful; the gap is SL-level + cost/spread, not signal logic
- **Entry parity is GOOD:** on the 416 matched trades `entryΔ` is mostly **0.000** (a handful off only
  by 1-bar lag). Signal detection + entry timing port cleanly.
- **SL level is systematically OFF** by ~0.3–1.5 price on nearly every matched trade (`slΔ` column).
  This flips outcomes — 141 exit-tag mismatches, dominated by engine **SL-WIN where MT5 hits TP** or
  **SL-WIN↔SL-LOSS** swaps. That is the direct driver of the P&L gap, not different trades.
- **Leading root cause — ATR mode mismatch (highest-confidence lead):** the EA computes SL from MT5's
  built-in `iATR` (Engine.mqh:60), which is an **SMA of True Range**, while the engine ran the lock with
  `InpAtrMt5Mode=false` = **textbook Wilder/RMA ATR**. Same trap proven on KenKem (memory
  `kenkem-atr-is-sma-not-wilder`). Different ATR → different `sl_atr_brk*ATR` SL level → the observed slΔ.
  **Test:** re-run the engine with `InpAtrMt5Mode=true` (or make the EA compute Wilder ATR) and re-diff.
- **Secondary — cost/spread model:** MT5 ran real Exness variable spread (`spreadPips` 112–196 pts ≈
  $0.11–0.20/oz); the engine used the set's fixed spread. This explains part of the count gap (MT5 fires
  more, 631 vs 563 — likely spread/SL interplay near gates) and inflates the engine's net vs MT5's.

## Next actions
1. Re-run engine with `InpAtrMt5Mode=true`; re-diff. Expect slΔ→~0 and most exit-tag mismatches to clear.
2. If residual remains, align the engine spread to the MT5 average (or feed per-bar spread) and re-diff.
3. Then chase the count gap (147/215) via entry-time alignment on the still-unmatched trades.
