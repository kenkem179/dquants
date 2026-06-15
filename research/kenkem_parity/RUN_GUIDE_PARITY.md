# KenKem MT5 reference run — one-batch guide (you click Start, I diff)

Goal: produce the **missing KenKem MT5 trade ledger** (the oracle). I've instrumented the EA,
built the matching C++ ledger, and written the diff. You run the tester; I do the rest.

All three EAs are compiled and ready (`.ex5` next to each `.mq5`). Do **KenKem first** — that's
the only strategy with no existing reference. MasterVP/Monster (step 4) just relock theirs.

---

## What I changed (so the reference is faithful)

- Added `MQL5/Experts/KenKem/Parity/TradeJournal.mqh` (self-contained, polls position
  transitions; no trading-logic effect) and wired 4 lines into `KenKemExpert.mq5`.
- It writes one row per closed trade to `MQL5/Files/KenKem/trades_<SYMBOL>.csv`,
  column-aligned with the C++ ledger so they diff 1:1.
- Parity `.set` = tuned `best_kenkem_<sym>.set` + a STAGE-1 overlay that neutralizes every
  governor the distilled C++ engine does NOT model (limit orders, news, daily-loss / drawdown /
  recovery / black-swan / profit-protection, pre-BE-structure, TP-extension/ladder). This
  isolates the **core E5 entry+exit logic** for the first proof. Stage 2 ports the governors.

---

## STEP 1 — KenKem XAUUSD reference (do this one)

In MetaTrader 5 Strategy Tester:

| Setting        | Value |
|----------------|-------|
| Expert         | `KenKem\KenKemExpert` |
| Symbol         | **XAUUSD** (the same Exness symbol the dquants ticks came from) |
| Timeframe      | **M1** |
| Modelling      | **Every tick based on real ticks** |
| Date range     | **2025.03.01 → 2025.05.31** |
| Deposit        | **10000 USD**, leverage **1:200** |
| **Commission** | **0** (the C++ engine assumes zero commission — must match or `$` won't) |
| Spread         | Current / from real ticks |
| Inputs (Load)  | `research/kenkem_parity/parity_kenkem_xau.set` |

Confirm `InpExportTradeJournal = true` shows in the Inputs tab, then **Start**.

When it finishes, the CSV is at:
`kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/KenKem/trades_XAUUSD.csv`
(if you ran the visual/real-tester it may be under the main terminal's `MQL5/Files/KenKem/`).
**Tell me when it's done** — I read it from there directly.

---

## STEP 2 — (I do this) diff against the C++ ledger

I already generated the matching C++ ledger for the same window:
`research/kenkem_parity/cpp_trades_xau_paritywin.csv` (395 trades, 2025-03-03 → 2025-05-30).

I run:
```
python cpp_core/tools/kenkem/diff_kenkem_trades.py \
  research/kenkem_parity/cpp_trades_xau_paritywin.csv \
  <path-to>/trades_XAUUSD.csv
```
This reports entry-selectivity parity (matched / missed / extra) + per-trade geometry deltas
(entry, riskPrice, exitPrice, realizedUsd) + dir/exitTag mismatches.

---

## STEP 3 — (I do this) close the gap

From the diff I make `kk::common::PositionManager` configurable per-strategy and migrate KenKem
onto it (MasterVP/Monster stay byte-identical), re-diff until geometry matches within tolerance.
Then stage 2: turn the neutralized governors back ON in both the `.set` and the C++ engine.

---

## STEP 4 — (optional, same sitting) relock MasterVP / Monster references

Their ref CSVs are missing from disk; regenerate while you're in the tester:

- Expert `KK-MasterVP\KK-MasterVP`, Inputs `MQL5/Presets/KK-MasterVP-parity-btc.set`
  (already has `InpExportTradeJournal=true`), Symbol BTCUSD, M3, real ticks, commission 0.
- Same for `KK-MasterVP-Monster\KK-MasterVP-Monster`.
- Output → `MQL5/Files/KK-MasterVP/trades_*.csv` — I diff with `cpp_core/tools/common/diff_trades.py`.

(Monster historically produced ZERO trades in MT5 — this run also confirms whether that port is
fixed, which is its own open question.)
