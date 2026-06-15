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

## Task-#4 progress (iteration 1, 2026-06-15) — SL fixed, exits modeled, entry over-fire remains

Changes (C++ tick engine, all tested — 22 checks pass):
- **SL geometry FIXED.** Added a dedicated E5 stop path (pure `ema200 ∓ 2·spread`, `E5_MIN_SL_PIPS`
  floor, ATR-cap only when `E5_USE_ATR_SL_ARBITRATION`). Matched-trade `riskPrice` mean |Δ| **2.52 → 0.15**
  (e.g. 11.66 vs 11.89). Root cause #2 closed.
- **Exit mechanisms ported to the tick engine** (it previously ran every trade to SL/TP): session-end
  flat (`CLOSE_ALL_TRADES_AT_SESSION_END`), fast-ADX panic, score-drop — bar-gated on the closed-bar
  snapshot, tagged `EA` like the MT5 journal. Win% **77 → 57** (MT5 52), net **−1899 → −951** (MT5 +995).
- **Entry selectivity wired:** `MIN_TREND_QUALITY_E5=5` gate (was ignored — only `trend_core!=0`), and a
  one-per-(kind,dir) occupancy guard (EA's `checkOpen{L,S}E5==-1`).

Still open — **entry over-fire ~3×** (C++ 395 vs MT5 136; 5.9 vs 2.2 trades/day). Localized: on
down-trending days **MT5 takes only shorts; C++ adds counter-trend longs**. `MIN_TREND_QUALITY_E5` is a
contributor but no integer threshold matches (tq8→325, tq11→36). Remaining suspects, in likely order:
1. **Multi-TF sideway** — EA blocks E5 via `IsMultiTfSideway` (2/3 of M1/M3/M5 ≥ `E5_SIDEWAYS_BLOCK_THRESHOLD=50`);
   C++ uses single-TF M1 `sideways_blocked`. Needs M3/M5 sideway scores in the snapshot.
2. **Deferred-entry gate** — EA defers a sideway-blocked signal, then requires close within `1·ATR` of EMA25.
3. **Consumed-lock semantics** — EA re-arms only after alignment breaks *while no position open*; C++ re-arms
   on any fresh onset after close.
4. **HTF weak-case** — EA allows both dirs when M5 HTF is weak/invalid; C++ `htf_tf_ok` blocks both.

Also: C++ now over-closes via `EA` (252 vs 40) — a symptom of the over-fire + panic/session WHEN-timing.

**Next step (the right tool, not more guessing):** golden per-bar trace — run `kenkem_trace` (C++) at the
136 MT5 entry bars and at the C++ extra bars to see exactly which gate diverges; port the matching gate;
re-diff. Build the EA-side trace instrument (deferred half) if the C++ trace alone doesn't localize it.

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
