# KenKemExpert ⇄ C++ parity — reference-run recipe (anchor #1)

Goal: produce the MT5 ground-truth CSVs that the C++ engine must reproduce **exactly**. This is the
first parity anchor for the clean rewrite ([[kenkem-clean-rewrite-2026-06]]).

## The run (do this in MT5)

| Setting | Value |
|---|---|
| EA | **latest `KenKemExpert.mq5`** (compiled `KenKemExpert.ex5`, Jun 15) — the profitable original |
| Symbol | **XAUUSD** (your Exness XAU symbol that matches the real-tick history) |
| Timeframe | **M1** |
| Model | **Every tick based on real ticks** |
| Date range | **From 2026.02.01 — To 2026.03.01** (one clean month) |
| Deposit | **10000 USD** |
| Leverage | **1:500** |
| Inputs | **ALL DEFAULTS** (E1+E2+E4 on, E3+E5 off — do not change anything) **EXCEPT** flip the two parity exports below |

### Inputs to change (only these two)
- `InpExportTradeJournal = true`   → writes `MQL5/Files/KenKem/trades_<symbol>.csv` (per-trade ledger)
- `InpExportBarTrace = true`       → writes `MQL5/Files/KenKem/trace_<symbol>.csv` (per-bar indicators+decision)

Everything else stays at the shipped default. **Do not load any `.set`** — defaults are the anchor.

## Hand back to me
1. `MQL5/Files/KenKem/trades_<symbol>.csv`  ← the per-trade ledger (the primary parity target)
2. `MQL5/Files/KenKem/trace_<symbol>.csv`   ← the per-bar trace (indicator parity foundation)
3. The Strategy Tester **report** (HTML or screenshot): net profit, PF, #trades, max DD
4. The tester **Inputs** tab (or the journal echo) so I can confirm the exact config

## What's already staged on the C++ side (ready to diff)
- Reference ticks: `cpp_core/tools/ticks_xauusd_2026feb.csv` (8.0M real bid/ask ticks, Feb 2026)
- Warmup+window M1 bars: `cpp_core/tools/bars_xauusd_2025h2_2026_m1.csv`
- C++ baseline run (current engine, defaults E1+E2+E4):
  `./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2025h2_2026_m1.csv \`
  `  --ticks tools/ticks_xauusd_2026feb.csv --symbol-xau \`
  `  --from-ms 1769904000000 --to-ms 1772323200000 --out tools/kenkem/trades_cpp_xau_2026feb.csv`
  → **49 trades, net −117.05, PF 0.976** (E1 21 / E2 16 / E4 12). This is the side I reconcile to MT5.
- Diff gate: `research/validation/parity_diff.py --engine <cpp trades> --mt5 <mt5 trades>`

## Then (me)
1. `parity_diff.py` trade-level diff → localize the FIRST divergence (count / which-fires / SL-TP / exit).
2. Indicator parity from the bar trace (EMA/ADX/RSI/ATR/Ichimoku) — fix any MT5 seeding/shift gaps first.
3. Re-derive each divergent module from `KenKemExpert.mq5` as ground truth until trades match.
