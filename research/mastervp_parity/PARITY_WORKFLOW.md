# KK-MasterVP EA ↔ C++ engine — trade-level parity verifier

The last link before production: prove the **shipped MT5 EA reproduces the locked C++
backtest trade-for-trade**, not just "the engine liked the config." This is SOP §7's
"MQL5 parity" gate for KK-MasterVP (XAU M5 lock is the front-runner).

## What was built (commit on `reliableBaseline`)
- **`mql5/experts/KK-MasterVP/Parity.mqh`** — trade-level journal. On each *closed*
  position it emits one row byte-compatible with the C++ `kk::to_trades_csv` ledger
  (same 21 columns, same rounding). Gated by **`InpExportParity`** (default OFF — live
  and forward runs are unaffected).
- Wired into `Engine.mqh`: `ParityInit/Close`, fill-capture (entry context + actual
  fill price + spread), per-tick MFE/MAE tracking, and an `OnTradeTransaction` handler
  that accumulates realized P&L across the TP1 partial + final out-deal and writes the
  row with the correct exit tag (`TP` / `SL-WIN` / `SL-LOSS` / `EA`).
- Compiles **0 errors / 0 warnings**.

## Run it (3 steps)

### 1. MT5 Strategy Tester (you)
- Symbol/TF: **XAUUSD M5** (the validated lock). Model: *Every tick based on real ticks*.
- Inputs tab → **Load** `KK-MasterVP-XAUUSD-M5.set`, then set **`InpExportParity = true`**.
  Keep `InpAvoidNews=false` and `InpBlockedHoursStr=""` for the parity run — the news/
  session overlays are live-only and intentionally diverge from the backtest.
- Pick a date range and **write it down** (this is the window you match the engine to).
- Run. Output lands at:
  `<tester agent>/MQL5/Files/KK-MasterVP/trades_XAUUSD_PERIOD_M5.csv`
  (e.g. `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/KK-MasterVP/...`).

### 2. C++ engine — same window, same set
```bash
cd cpp_core && make backtester
./build/backtester \
  --bars  tools/bars_xauusd_2026_m5.csv \
  --ticks tools/ticks_xauusd_2026_may_window.csv \   # pick the tick file covering your MT5 range
  --set-all tools/mastervp/kkmastervp_xau_m5_LOCKED.set --symbol-xau \
  --out /tmp/trades_cpp_xau_m5.csv
```
Use `--trade-from-ms <ms>` / `--trade-to-ms <ms>` to clip the engine to the exact MT5
window if the tick file is wider. (`research/mastervp_parity/wf_mc.py` shows the ms helpers.)

### 3. Diff → PASS/FAIL verdict
```bash
python3 research/validation/parity_diff.py \
  --engine /tmp/trades_cpp_xau_m5.csv \
  --mt5    "<tester agent>/MQL5/Files/KK-MasterVP/trades_XAUUSD_PERIOD_M5.csv" \
  --bar-seconds 300 --label "KK-MasterVP XAU M5 forward-parity"
```
`--bar-seconds 300` for M5 (180 for M3). The tool window-filters the engine to the MT5
entry-time span, greedily matches by entry-time+direction, and prints per-trade entry/
risk/exit/P&L deltas + a PASS/FAIL against the contract tolerances.

## Reading the result
- **PASS** → the EA is parity-clean for that window; proceed to demo forward-test with
  confidence the live logic == the validated engine.
- **Count mismatch** → almost always a *config* gap (some `Inp*` in MT5 ≠ the `.set` the
  engine ran). Diff the MT5 `inputs_echo`/journal against the `.set` first (this exact
  trap cost days on KenKem — see memory `kenkem-e1-cross-age-config-mismatch`).
- **Matched but P&L/exit drift** → execution-side divergence (fill model, spread,
  trail granularity). The `mfeR/maeR` + `exitTag` columns localize it.

## Caveats / known intentional divergences
- News blackout + blocked-hours + force-close-on-session are **live-safety overlays not
  in the C++ backtest** — keep them OFF for the parity run, then re-enable for live.
- Entry timestamp is stamped at the new-bar open (the fill bar); `parity_diff` tolerates
  a ±`--lag-bars` offset, so a 1-bar stamp difference will not break matching.
- Smoke-tested engine-vs-engine on the May-2026 window (108 trades) → **VERDICT: PASS**,
  confirming the header/rounding/matcher chain is sound end-to-end.

## Same pattern for the other locks
- XAU M3 A/B: `kkmastervp_xau_m3_LOCKED.set`, `--bars ..._m3.csv`, `--bar-seconds 180`.
- BTC M5: `kkmastervp_btc_m5_LOCKED.set`, `--symbol-btc`, M5 BTC bars, `--bar-seconds 300`.
- Monster (BTC M3): needs the same `Parity.mqh` hook added to `KK-MasterVP-Monster`
  (NOT yet wired — see HANDOFF next-action).
