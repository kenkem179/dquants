# HANDOFF — read me first, update me last

_Last updated: 2026-06-16 by Claude (Opus 4.8). Branch `1-reorganize-code`._

## 🎯 Goal (CLEAN-SLATE RESET — supersedes all prior KK-KenKem work)
User was "super disappointed" by KK-KenKem and ordered a **clean rewrite**. All old KK-KenKem
"distilled subset / parity-ledger / over-fires" memory was DELETED at his request. Two acceptance
criteria (the whole job now):
1. **C++ reproduces the original `KenKemExpert` EA's MT5 backtest EXACTLY** (same trades/exits, P&L
   within tick-fill tolerance). User produces MT5 reference CSVs.
2. **KK-KenKem regenerated from the SAME logic** also reproduces KenKemExpert exactly → user kills the
   original EA and trusts dquants for the first time.

**Ground truth = `kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5`** (FULL strategy, PF~1.62). No distillation
— that was the old mistake. C++ = faithful 1:1 transcription. KK-KenKem = that logic with hardcoded
consts promoted to `input`s ⇒ at baseline `.set` it ≡ KenKemExpert **by construction**.

## ✅ Anchor LOCKED (with user, 2026-06-16)
Latest `KenKemExpert.mq5` @ shipped defaults · **XAUUSD M1** · every-tick **real ticks** · **Feb 2026**
· deposit 10000 / 1:500. Default config = **E1+E2+E4 on, E3+E5 off**.

## ✅ Validation loop WIRED & staged (ready to diff)
- **Key enabler:** KenKemExpert already ships `Parity/{TradeJournal,BarTrace}.mqh` — schema-built to diff
  1:1 vs the C++ ledger. Flip `InpExportTradeJournal=true` + `InpExportBarTrace=true`.
- Reference data exported: `cpp_core/tools/ticks_xauusd_2026feb.csv` (8.0M real ticks) +
  `bars_xauusd_2025h2_2026_m1.csv` (warmup+window).
- C++ baseline (current engine, defaults): **49 trades, net −117.05, PF 0.976** (E1 21 / E2 16 / E4 12) →
  `cpp_core/tools/kenkem/trades_cpp_xau_2026feb.csv`. Run cmd + full recipe:
  **`research/kenkem_parity/REFERENCE_RUN_RECIPE.md`**.
- Diff gate: `research/validation/parity_diff.py` ([[parity-gate-built]]).

## ⛔ BLOCKED ON: user MT5 run
User to run the recipe → hand back `trades_<sym>.csv` + `trace_<sym>.csv` + tester report + inputs echo.
THEN: parity_diff → localize FIRST divergence → fix module-by-module against KenKemExpert.mq5.

## ▶️ Next actions (staged program — tasks #1-5 in tracker)
1. **(done)** Lock anchor + export reference window.
2. **(in flight)** Align C++ `KenKemConfig` defaults to `InputParams.mqh` — background audit agent
   producing a divergence table; apply NO/UNCLEAR fixes next turn (CSV-independent).
3. **Stage 1** indicator parity vs `trace_<sym>.csv` (EMA/ADX/RSI/ATR/Ichimoku; MT5 seeding/shift).
4. **Stage 2-4** entry/gate/SL-TP/exit parity vs `trades_<sym>.csv` (triggers→gates→quality/conviction/
   RSI-div/ATR-pctile/sessions→SL/TP→exit path incl. ladder/panic/score-drop/session-end).
5. **Stage 5** rebuild `dquants/mql5/experts/KenKem/` (the symlinked deploy tree) as parameterized-
   identical port; prove KK-KenKem MT5 run == KenKemExpert MT5 run at baseline.

## 🔑 Key facts / gotchas
- Edit the DEPLOY EA at `dquants/mql5/experts/KenKem/` ([[deploy-ea-is-dquants-mql5-symlinked]]).
- **Tick engine only** for P&L ([[bar-engine-systemic-defect]]). Binary: `cpp_core/build/kenkem/tick_backtester`.
- Honor [[kenkem-parity-traps]] (EMA 10/25/71/97/192, ATR shift-0, BTC pip, EMA seeding). Broker = UTC+0;
  EA sessions are JST (TimeGMT()+9h) — verify C++ UTC session windows map correctly.
- Python: `~/miniforge3/envs/kenkem/bin/python`. Existing C++ is a reusable HARNESS (replay/config/CSV/
  tests) but modeled the wrong target — re-derive strategy logic from the EA.
- bash 3.2 here; kenkem env has bash 5. Per-step: test→commit→push→tick docs.

## 📚 Durable references
`research/kenkem_parity/REFERENCE_RUN_RECIPE.md` (the run) · `research/validation/parity_diff.py` (gate) ·
`docs/KENKEM_QUANT_OS.md` (SOP) · `~/.claude/.../memory/MEMORY.md` ([[kenkem-clean-rewrite-2026-06]]).
