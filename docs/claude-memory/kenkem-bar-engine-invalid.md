---
name: kenkem-bar-engine-invalid
description: KenKem PF numbers are from a bar-OHLC engine and FAILED MT5 — not trustworthy until a tick engine exists
metadata: 
  node_type: memory
  type: project
  originSessionId: 7f6d0397-7b89-4d5f-842e-9b83928da35a
---

The KenKem distilled track (E1/E2/E4/E5) is backtested by `cpp_core/include/kk/kenkem/engine.hpp`,
a **bar-OHLC-walk** engine (4 points/M1 bar, adverse-first), NOT a tick engine. MasterVP has a real
tick engine (`mastervp/tick_engine.hpp`) + parity_runner and passed MT5 trade-level parity; **KenKem
has neither**. No `kenkem` parity_runner; no KenKem parity/trade CSVs ever produced.

On 2026-06-15 the user ran the promoted MQL5 (KK-KenKem, E5-only, `best_tuned_e5_xau.set`) in the MT5
tester, XAUUSD M1, 2025.08→2026.06: **PF 0.85, net −$6,224 (10k→3.8k), 70% DD, 86% win but avg win
$21.6 vs avg loss −$156** — a negative-skew blowup. dquants `KENKEM-RESULTS.md` had claimed **OOS PF
1.62** for the same config. Opposite sign.

**Why:** the strategy's whole edge is path-dependent intrabar management (partial@0.2R → breakeven →
chandelier trail). A 4-point bar walk flatters this (locks partials/BE optimistically, undercounts
full-SL hits → fake high win rate). Plus `commission_per_lot = 0.0` and thin spread ($0.05 XAU). Optuna
then optimized ON this engine → overfit to its blind spot; "2026 OOS" is OOS in time but in-sample to
the simulator's flaw.

**Rule:** treat EVERY KenKem PF in KENKEM-RESULTS.md as engine-internal / UNVERIFIED. Never put a
KenKem bar-engine PF in a comparison table as if validated.

**FIXED 2026-06-15:** built `cpp_core/include/kk/kenkem/tick_engine.hpp` + `tools/kenkem/
tick_backtester.cpp` (make target `kenkem_tick`). Replays real bid/ask ticks through the same
signal/SL/TP front-half. VALIDATED vs MT5: ungated E5 → PF 0.855 (MT5 0.85), net −74.6% (MT5 −74.1%) —
bar engine had said +420%. USE THE TICK ENGINE for any KenKem P&L now; the bar engine
(`run_backtest` in engine.hpp) is only safe for entry-frequency/diagnostics. Also wired the previously-
defined-but-unenforced governors (min_entry_atr_pctile, max_entries_per_day, e5_require_trend_core).
Through the tick engine ALL dquants-tuned configs still lose (overfit to the old bar engine); the
ORIGINAL KenKemExpert E1+E2 is the only MT5-profitable artifact. See [[mt5-reality-all-three-fail]],
[[parity-findings-trade-level]].
