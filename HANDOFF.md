# HANDOFF — read me first, update me last

_Last updated: 2026-06-17 by Claude (Opus 4.8). Branch `1-reorganize-code`._

## 🎯 Goal (CLEAN-SLATE RESET — autopilot, 3 strategies)
User was "super disappointed" by the distilled KK-KenKem and ordered a faithful rewrite, then expanded
to autopilot across THREE strategies. The arc: **C++ reproduces the original EA EXACTLY → use C++ for
fast param sweeps → port the tuned logic BACK to MQL5.** Order: **KenKem → MasterVP → MonsterEdition**
(for Monster, read the Pine code properly — user named it). Acceptance: C++ trades == MT5 trades within
tick-fill tolerance, then regenerate the EA from the same logic so it ties out at baseline.

**Ground truth = the original EA source** (read it, never guess). For KenKem:
`kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5` + its `Core/`,`Entries/`,`TradeManagement/`,`Utils/` mqh.

## ✅ Anchor LOCKED · ✅ Stage 1 DONE (indicators bit-exact)
Anchor: latest `KenKemExpert.mq5` @ defaults · XAUUSD M1 · every-tick real ticks · **Feb 2026** ·
deposit 10000 / 1:500 · config E1+E2+E4 on, E3+E5 off.
MT5 ground truth: `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/KenKem/{trades,trace}_XAUUSD-Exness-KK.csv`
(9 trades: E4×7,E1×1,E2×1; 27379-row bar trace).

**Stage 1 (commit `680e55d`): 5/6 indicator families now bit-exact** vs the MT5 trace (joined
`cpp_ts−60000 == mt5_ts`): ema0-4 Δ0.00008, rsi Δ0.00046, high/low Δ0.00001, close/adx ~0. ATR Δ0.31 is
a documented ~2% tick-completeness residual (NOT formula — bid/mid/ask all give 0.306). Full write-up +
THE REUSABLE METHODOLOGY: **`research/kenkem_parity/INDICATOR_PARITY_SPEC.md`**. Fixes were in
`indicators.hpp` (rsi_wilder_mt5/step), `tf_cache.hpp` (rsi_ag/al), `snapshot.hpp` (per-indicator shifts:
EMA i1-2, ATR/RSI/high-low forming-bar-first-tick). The EMA "shift 1" is really shift 2 — non-series
`CopyBuffer` index inversion. This trap WILL recur in MasterVP/Monster.

## 🔄 Stage 2-4 IN PROGRESS (entry/gate/exit parity → match the 9 trades)
With exact indicators the tick engine fires **50 trades (E1 17/E2 16/E4 17) vs MT5 9; 0/9 matched.** The
existing C++ entry layer (`triggers/gates/entries/engine.hpp`) is the OLD DISTILLATION — its own comments
admit gates were "parsed-and-ignored," session is UTC (EA uses JST), concurrency/cooldown are author-added
backstops with knobs, trend-quality is 0-6 not the real 0-13. **Must rebuild faithfully from the EA.**
Tell: MT5 fires ~1 trade/day at session-gated times; C++ fires many/day → missing session + conviction +
trend-quality + RSI-div + concurrency gating.

**4 background mapping agents launched** (write specs to `research/kenkem_parity/`):
- `SPEC_E4.md` (dominant 7/9) · `SPEC_E1_E2.md` (why only 1+1 fire) · `SPEC_PIPELINE.md` (OnTick order,
  session JST, concurrency/cooldown ≈1 trade/day, trend-quality 0-13, conviction, RSI-div, ATR-pctile,
  risk guards) · `SPEC_EXITS.md` ("EA" managed close = 5/9 exits: panic/score-drop/session-end/trail).

### ▶️ NEXT ACTION (resume here)
1. When specs land, rebuild in this order (biggest suppressor first):
   a. **Pipeline/session/concurrency** (faithful JST sessions + one-trade gating) — collapses 50→~9/day.
   b. **Conviction + trend-quality 0-13 + RSI-div veto + ATR-pctile** gates per entry.
   c. **E4 trigger+gate** exact (it's 7/9), then E1/E2.
   d. **SL/TP + managed exits** ("EA" tag path) to match exitPrice/realizedUsd.
2. Re-diff after each: `tick_backtester` → `research/validation/parity_diff.py` (window-aligns vs MT5).
   Target: 9/9 matched, entry/SL/exit/PnL within tolerance.
3. Then **Stage 5**: regenerate `dquants/mql5/experts/KenKem/` (symlinked deploy tree) as the
   parameterized-identical port; prove KK-KenKem MT5 run == KenKemExpert at baseline.
4. Then repeat the whole methodology for **MasterVP**, then **MonsterEdition** (read Pine for Monster).

## 🔑 Key facts / gotchas
- Rebuild + run: `cd cpp_core && make kenkem_tick kenkem_trace && make test`. Binaries in `build/kenkem/`.
- Trade diff window-aligns automatically. Trace diff MUST join `cpp_ts−60000 == mt5_ts`.
- **Tick engine only** for P&L ([[bar-engine-systemic-defect]]). EMA non-series shift-2 trap. shift-0 =
  forming bar first-tick (O=H=L=C=open), model as one Wilder step — never read the future bar's OHLC.
- Edit the DEPLOY EA at `dquants/mql5/experts/KenKem/` ([[deploy-ea-is-dquants-mql5-symlinked]]).
- Python: `~/miniforge3/envs/kenkem/bin/python`. Per-step: test→commit→push→tick docs.
- Staged data: `cpp_core/tools/{ticks_xauusd_2026feb.csv, bars_xauusd_2025h2_2026_m1.csv}`.

## 📚 Durable refs
`research/kenkem_parity/INDICATOR_PARITY_SPEC.md` (Stage 1 + methodology) · `ANCHOR1_FINDINGS_2026-02.md` ·
`REFERENCE_RUN_RECIPE.md` · `research/validation/parity_diff.py` · `docs/KENKEM_QUANT_OS.md` ·
`~/.claude/.../memory/MEMORY.md` ([[kenkem-clean-rewrite-2026-06]]).
