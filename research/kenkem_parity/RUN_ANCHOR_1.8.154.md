# How to run the 1.8.154 parity anchor (for the user)

The standalone EA `KenKemExpert.mq5` (v1.8.154) has been instrumented with a per-bar parity trace.
Run it once in the MT5 Strategy Tester to produce the ground truth the C++ engine re-anchors against.

## EA branch
kenkem repo is on branch **`parity-trace-1.8.154`** (additive instrumentation; commits `3e8d12f`, `0e12256`).
EA already compiled (`✓ OK`). If you switch branches, recompile:
`bash /Users/tokyotechies/Workspace/KEM/dquants/scripts/compile_mql5.sh /Users/tokyotechies/Workspace/KEM/kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5`

## Strategy Tester settings
| Setting | Value |
|---|---|
| Expert | `KenKem\KenKemExpert` |
| Symbol | **XAUUSD** (the Exness symbol the dquants ticks came from) |
| Timeframe | **M1** |
| Modelling | **Every tick based on real ticks** |
| Date range | **2026.02.01 → 2026.02.28** (the CLEAN anchor window — no missing tick days) |
| Deposit / leverage | 10000 USD / 1:500 (match whatever you want the C++ baseline to be) |
| Commission | **0** (the C++ engine assumes zero; must match or `$` won't tie) |

## Inputs tab — enable BOTH toggles
- **`InpExportParityTrace = true`** → per-bar trace
- **`ENABLE_CSV_EXPORT = true`** → per-trade ledger

Otherwise use your current default / baseline config (whatever you want the C++ engine to reproduce).
Tell me the config you ran with (or just the .set) so I sweep the same surface.

## Outputs (tell me when done; I read them directly)
Under the tester agent sandbox `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/`:
- **Parity trace:** `KenKem/parity_trace_XAUUSD.csv`
  Columns: `ts_ms,dt,ema0..4,adx_m1/m3/m5/m15,diP_*,diM_*,adxS,diPS,diMS,atr,rsi,close,high,low,tenkan,kijun,senkouA_m3,senkouB_m3,sideways,atr_pctile,session,fire_dir`
  (`fire_dir` is currently always 0 — a known TODO; actual fires come from the trade ledger. Ask me to wire it if you want per-bar fire/skip diagnostics for the over-fire work.)
- **Trade ledger:** `<YYYYMM>_KenKem_XAUUSD_<account>_trades.csv` (47-col analytics schema; I'll adapt the diff tool to it).

## What I do when the CSVs land
1. Diff the C++ engine trace vs `parity_trace_XAUUSD.csv` (same-ts join) → confirm indicators/ATR/percentile match on 1.8.154; port any 1.8.15→1.8.154 logic deltas.
2. Diff trades → drive entry-selection + P&L parity; attack the over-fire with the gate columns.

## Separately: XAU tick re-export
See `XAU_TICK_REFETCH_LIST.md` — the export is missing whole trading days (Feb-2026 anchor is clean, so this is only needed for 2024/2025 windows).
