# KK-MasterVP Port — Build Plan & Progress Tracker

Living checklist for porting the **KK-MasterVP** MQL5 strategy into the headless C++ tick backtester
and optimizing it. Source of truth = MQL5 (`kenkem/MQL5/Experts/KK-MasterVP/`). Spec =
`research/hypotheses/KK-MasterVP-SPEC.md`. Each step: build → `make -C cpp_core test` → commit → push.

Legend: `[x]` done · `[~]` in progress · `[ ]` todo. "commit" = short hash once landed.

## Data pipeline (generic, reusable) — DONE
- [x] Phase 1 Import — `pipeline/import_data.py` (BTCUSD + XAUUSD ticks → Parquet)
- [x] Phase 2 Validate/clean — `pipeline/validate_data.py`
- [x] Phase 3 Bars + features — `pipeline/build_bars.py`, `features.py`, `indicators.py`
- [x] Phase 4 Labels — `pipeline/labels.py`
- [x] Phase 5 Discovery — `research/discovery/discover.py` (VP/hour/DI dominate; no lone-feature edge)

## Phase 6 — Formalize strategy (reframed: port the real EA) — DONE
- [x] KK-MasterVP implementation spec (bidirectional) — `research/hypotheses/KK-MasterVP-SPEC.md`
- [x] Parity methodology (3 levels, bar-first) — SPEC §9
- [x] Located authoritative params (`KK-MasterVP-baseline.set`) + parity reference + news calendar

## Phase 7 — C++ tick engine + port (IN PROGRESS)
### Computation layer (per-bar parity surface) — DONE
- [x] Build system + test harness (`cpp_core/Makefile`, `kk/test.hpp`) — dependency-free clang C++20
- [x] Types (`kk/types.hpp`: Tick/Bar/VPResult/NodeState/RegimeState/Signal)
- [x] Config + `.set` loader, non-input parity hazard handled (`kk/config.hpp`)
- [x] VolumeProfile (BuildVAFromHist + ComputeVP_Bar) — `kk/volume_profile.hpp`
- [x] Indicators (EMA/Wilder/ATR/RSI/ADX) — `kk/indicators.hpp`
- [x] NodeEngine (decay/touch/absorption, sliding grid) — `kk/node_engine.hpp`
- [x] Regime (trend vs balance) — `kk/regime.hpp`
- [x] DetectSignal (4 bidirectional signals + SL/TP economics) — `kk/strategy.hpp`
### Front-half validation (do BEFORE execution half)
- [x] Python reference harness `cpp_core/tools/validate_parity_py.py` (bid M3 bars from ticks)
- [x] Level-1 diff vs `parity_BTCUSD-Exnes-0406_PERIOD_M3.csv`: **master VP <0.001, ADX/+DI/-DI
      <0.005, trend agree 100%** (480/480 rows) on BTCUSD M3 2026-04-09
- [x] Resolved: EA uses MT5 `iADX` (EMA 2/(n+1) of per-bar 100·DM/TR), **not** Wilder iADXWilder
      → ported to C++ `dmi_adx_mt5` + golden test; regime must consume it
- [x] Resolved (caveat): ATR matches on avg (ratio mean 0.9986) but diverges on vol spikes —
      MT5 tester's tick model captures wider intrabar extremes than the exported CSV. VP/ADX are
      robust (window-extreme / ratio based); ATR is not. Perfect ATR parity unattainable from CSV.
- [x] C++ parity harness driver: Parquet→bars→computation layer per bar → emit `parity_*.csv`.
      Bridge `tools/export_bars.py` (DuckDB Parquet→bid M3 bars CSV) → `build/parity_driver`
      (`include/kk/parity_runner.hpp` drives VP+regime+indicators+node+DetectSignal per bar, MT5
      shift map verified from MQL source) → `tools/diff_parity.py` vs MT5 ref. **Result on the
      480-row BTCUSD M3 2026-04-09 ref: master VP ≤0.001, +DI/-DI/ADX exact (0.000), trend 100%,
      raw sigValid 74/75 (entry exact on both-fired rows). The 1 miss (00:03) + sl/tp deltas are the
      documented ATR-from-CSV spike caveat.**
### Execution layer
- [x] PositionManager (TP1 partial / BE-after-TP1 / runner chandelier trail) — `include/kk/position_manager.hpp`,
      port of TradeManager.mqh. Per-tick state machine (broker SL/TP first, then EA TP1→BE→trail; trail only
      ever tightens, anti-churn step). Tracks mfeR/maeR (broker-spec-free) + realized USD (via broker specs).
      4 unit tests cover SL-loss / TP1→trail→SL-win / backstop-TP / trail-tightens-only. `Params` gained broker
      spec fields (tick_value/tick_size/lot_step/min_lot/commission/start_balance) — **awaiting real Exness numbers**.
- [x] RiskManager (sizing, daily-DD, peak-DD, cooldowns) — `include/kk/risk_manager.hpp`, port of
      RiskManager.mqh. Owns balance/peak/day-start/streak/cooldown; budget=balance·riskAccPct%,
      lot=budget/(stop·vppl)·peakDDmult, predictive daily-DD breaker, 22% halt / 15%→×0.55 soft-block,
      3-loss→4h + daily-DD→12h cooldowns (extend-only). 7 unit tests pass.
- [x] Filters (sessions, news calendar, ATR% band, spread, blocked hours) — `include/kk/filters.hpp`
      (port of SessionManager.mqh): sessions (Asia/Ldn/NY UTC), blocked hours (+ranges), max-trades/session
      reset, ATR% band, spread + TP1 cost-clearance gates. 6 unit tests pass. MTF-agree (M15 EMA) + RSI
      veto quality gates now wired in the TickEngine (`quality_ok_`); news calendar inert for v1 parity.
- [x] ExecutionSimulator (`include/kk/execution.hpp`): market fill model — long buys ask / short sells bid
      on the first tick of the bar after the signal bar; $0 commission; slippage seam (=0 = tester parity).
- [x] TickEngine (`include/kk/tick_engine.hpp`): the Layer-3 integrator. Precomputes the validated
      front-half over the full bar series, then replays ticks reproducing the MT5 OnTick loop —
      per-tick UpdatePeakEquity + ManageOpenPosition, per-new-bar session/day context → force-close →
      DetectSignal (shift-1) → quality gate (MTF/RSI) → safety gate + flat check → spread-vs-TP1 →
      market fill → trade journal. Fixed PositionManager to use **effRisk=|fill−SL|** + **anchor-based
      runner backstop** (TradeManager.mqh:61,99). 3 integration tests (fill model, coherent+balance-
      reconciled trades on the golden fixture, determinism) pass. **Next:** real-tick export + Level-2 diff.
### Full validation
- [ ] Emit `trades_*.csv`; Level-2 trade diff vs reference
- [ ] Level-3 aggregate: reproduce PF 1.21/1.10 on XAUUSD M3
- [x] Golden test (`tests/test_parity_golden.cpp` + frozen `tests/golden/`): replays the bid M3
      warmup slice + MT5 ref day in `make test`; asserts VP/DI/trend/sigValid stay within tolerance.
      Front-half faithfulness is now a regression guard, not a one-off. (Trade-level diff still TODO.)

## Phase 8 — Optimization
- [ ] Python harness drives C++ engine (Optuna); attack tail-dependence via trail/TP1 params
- [ ] Sensitivity heatmaps (plateaus, not peaks)

## Phase 9 — Walk-forward + Monte Carlo
- [ ] Rolling train/validate/test; never mix periods

## Phase 10 — Promote
- [ ] Push winning params back to `KK-MasterVP.mq5`; demo forward-test
