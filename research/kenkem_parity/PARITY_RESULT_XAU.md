# KenKem trade-level parity — FIRST MT5 result (XAUUSD, E5, stage-1)

**Date:** 2026-06-15. **Window:** 2025.03.01 → 2025.05.31 (real ticks, M1).
**Config:** `parity_kenkem_xau.set` — E5-only, governors neutralized (stage-1 core-logic isolation).
**Commission:** 0 both sides. **MT5 EA:** `KenKemExpert` (instrumented), Exness XAUUSD-Exness-KK.

## Headline: the dquants C++ engine is NOT faithful — it inverts the verdict

| Source | Trades | Net USD | PF | Win% |
|---|---:|---:|---:|---:|
| **MT5 (truth)** — instrumented KenKem EA | **136** | **+995** | **1.23** | 52% |
| **dquants C++** — `kenkem_tick_backtester` | 394 | **−1,899** | **0.90** | 77% |

The real EA is **profitable** on this window; the dquants C++ port shows the **same strategy losing**.
Any fine-tuning done on the C++ engine alone is therefore untrustworthy — this is the concrete proof
behind the user's concern. Files: `mt5_trades_xau_paritywin.csv` (ref), `cpp_trades_xau_paritywin.csv`
(C++), `diff_xau_paritywin.txt` (raw diff).

## The three structural divergences (root causes for task #4)

1. **C++ over-fires ~3×** (394 vs 136). Even fuzzy ±10-min same-direction matching pairs only 48% of
   MT5 trades to a C++ trade. The C++ E5 entry gating is too loose / missing EA selectivity (the EA is
   far more selective than the distilled engine reproduces). This is the dominant gap.

2. **Stop geometry is too tight in C++.** On matched trades, MT5 `riskPrice` is ~2–12 while C++ is ~1–3
   (mean |Δ| ≈ 2.5 on that scale). The EA's E5 SL is much wider (EMA-200-based, per the port-trap notes);
   the C++ uses a tighter stop → more full stop-outs and a "many tiny wins + occasional −1R" profile
   (C++ 77% WR yet PF 0.90), vs the EA's fewer-but-bigger wins (52% WR, PF 1.23). This is the
   [[kenkem-e5-root-cause-exits]] exit-geometry problem, now confirmed against real MT5.

3. **Session-end / EA-initiated closes not modeled in the tick engine.** Most MT5 exits are tagged `EA`
   (CLOSE_ALL_TRADES_AT_SESSION_END and similar); the C++ tick engine runs every trade to SL/TP. The C++
   `tick_engine.hpp` does not implement session-end flat (the bar engine does — must port it to ticks).

(Entry timing also drifts a few minutes on the trades that do pair — secondary; fix after 1–3.)

## Next (task #4) — close the gap, in priority order

1. **Entry selectivity** — reconcile the C++ E5 gate set against the EA's `DetectSignal`+trend-quality so
   trade COUNT converges (~136). Use the `trace_dumper` golden per-bar trace to localize which gate the
   C++ passes that the EA blocks.
2. **SL geometry** — match E5 SL construction (EMA-200 distance, ATR cap) so `riskPrice` converges.
3. **Exits** — port session-end flat + the EA's BE/trail formula into the configurable
   `kk::common::PositionManager`; KenKem migrates onto it (MasterVP/Monster stay byte-identical).
4. Re-run this exact diff until trades/geometry/$ match within tolerance; then stage-2 (governors ON).

## Reproduce
```
# C++ side (already saved):
cpp_core/build/kenkem/tick_backtester --bars-m1 research/kenkem_parity/bars_xauusd_M1_kk_BID.csv \
  --ticks <xau-tick-stream> --symbol-xau --set research/kenkem_parity/parity_kenkem_xau.set \
  --from-ms 1740787200000 --to-ms 1748736000000 --out research/kenkem_parity/cpp_trades_xau_paritywin.csv
# MT5 side: load parity_kenkem_xau.set in tester (see RUN_GUIDE_PARITY.md), commission 0.
# Diff:
python cpp_core/tools/kenkem/diff_kenkem_trades.py \
  research/kenkem_parity/cpp_trades_xau_paritywin.csv research/kenkem_parity/mt5_trades_xau_paritywin.csv
```
