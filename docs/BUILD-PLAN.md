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
- [ ] Data plumbing: Python exports bars window (Parquet → flat file C++ reads)
- [ ] Parity harness driver: run computation layer per bar → emit `parity_*.csv`
- [ ] Level-1 diff vs `parity_BTCUSD-Exnes-0406_PERIOD_M3.csv` (master VP + regime + signal)
- [ ] Resolve node-gate ambiguity + indicator-seed drift from the diff
### Execution layer
- [ ] PositionManager (TP1 partial / BE-after-TP1 / runner chandelier trail) — TradeManager.mqh
- [ ] RiskManager (sizing, daily-DD, peak-DD, cooldowns) — RiskManager.mqh
- [ ] Filters (sessions, news calendar, ATR% band, spread, blocked hours)
- [ ] ExecutionSimulator (spread/slippage/commission, tick fills)
- [ ] TickEngine (replay ticks → bars → drive modules → trades) + `backtester` main
### Full validation
- [ ] Emit `trades_*.csv`; Level-2 trade diff vs reference
- [ ] Level-3 aggregate: reproduce PF 1.21/1.10 on XAUUSD M3
- [ ] Golden test: freeze a parity-CSV day as a `make test` regression guard

## Phase 8 — Optimization
- [ ] Python harness drives C++ engine (Optuna); attack tail-dependence via trail/TP1 params
- [ ] Sensitivity heatmaps (plateaus, not peaks)

## Phase 9 — Walk-forward + Monte Carlo
- [ ] Rolling train/validate/test; never mix periods

## Phase 10 — Promote
- [ ] Push winning params back to `KK-MasterVP.mq5`; demo forward-test
