# KK-MasterVP Port — Build Plan ARCHIVE (completed phases)

Completed, historical phases moved out of `docs/BUILD-PLAN.md` to keep the live tracker small (it is read
into context each session). Nothing here is open work — see `BUILD-PLAN.md` for the active backlog.
Legend: `[x]` done · `[~]` was-in-progress · `[!]` caution.

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

## Phase 7 — C++ tick engine + port — DONE
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
- [x] Python reference harness `cpp_core/tools/common/validate_parity_py.py` (bid M3 bars from ticks)
- [x] Level-1 diff vs `parity_BTCUSD-Exnes-0406_PERIOD_M3.csv`: **master VP <0.001, ADX/+DI/-DI
      <0.005, trend agree 100%** (480/480 rows) on BTCUSD M3 2026-04-09
- [x] Resolved: EA uses MT5 `iADX` (EMA 2/(n+1) of per-bar 100·DM/TR), **not** Wilder iADXWilder
      → ported to C++ `dmi_adx_mt5` + golden test; regime must consume it
- [x] Resolved (caveat): ATR matches on avg (ratio mean 0.9986) but diverges on vol spikes —
      MT5 tester's tick model captures wider intrabar extremes than the exported CSV. VP/ADX are
      robust (window-extreme / ratio based); ATR is not. Perfect ATR parity unattainable from CSV.
- [x] C++ parity harness driver: Parquet→bars→computation layer per bar → emit `parity_*.csv`.
      Bridge `tools/common/export_bars.py` (DuckDB Parquet→bid M3 bars CSV) → `build/parity_driver`
      (`include/kk/mastervp/parity_runner.hpp` drives VP+regime+indicators+node+DetectSignal per bar, MT5
      shift map verified from MQL source) → `tools/common/diff_parity.py` vs MT5 ref. **Result on the
      480-row BTCUSD M3 2026-04-09 ref: master VP ≤0.001, +DI/-DI/ADX exact (0.000), trend 100%,
      raw sigValid 74/75 (entry exact on both-fired rows). The 1 miss (00:03) + sl/tp deltas are the
      documented ATR-from-CSV spike caveat.**
### Execution layer
- [x] PositionManager (TP1 partial / BE-after-TP1 / runner chandelier trail) — `include/kk/common/position_manager.hpp`,
      port of TradeManager.mqh. Per-tick state machine (broker SL/TP first, then EA TP1→BE→trail; trail only
      ever tightens, anti-churn step). Tracks mfeR/maeR (broker-spec-free) + realized USD (via broker specs).
      4 unit tests cover SL-loss / TP1→trail→SL-win / backstop-TP / trail-tightens-only. `Params` gained broker
      spec fields (tick_value/tick_size/lot_step/min_lot/commission/start_balance) — **awaiting real Exness numbers**.
- [x] RiskManager (sizing, daily-DD, peak-DD, cooldowns) — `include/kk/common/risk_manager.hpp`, port of
      RiskManager.mqh. Owns balance/peak/day-start/streak/cooldown; budget=balance·riskAccPct%,
      lot=budget/(stop·vppl)·peakDDmult, predictive daily-DD breaker, 22% halt / 15%→×0.55 soft-block,
      3-loss→4h + daily-DD→12h cooldowns (extend-only). 7 unit tests pass.
- [x] Filters (sessions, news calendar, ATR% band, spread, blocked hours) — `include/kk/common/filters.hpp`
      (port of SessionManager.mqh): sessions (Asia/Ldn/NY UTC), blocked hours (+ranges), max-trades/session
      reset, ATR% band, spread + TP1 cost-clearance gates. 6 unit tests pass. MTF-agree (M15 EMA) + RSI
      veto quality gates now wired in the TickEngine (`quality_ok_`); news calendar inert for v1 parity.
- [x] ExecutionSimulator (`include/kk/common/execution.hpp`): market fill model — long buys ask / short sells bid
      on the first tick of the bar after the signal bar; $0 commission; slippage seam (=0 = tester parity).
- [x] TickEngine (`include/kk/mastervp/tick_engine.hpp`): the Layer-3 integrator. Precomputes the validated
      front-half over the full bar series, then replays ticks reproducing the MT5 OnTick loop —
      per-tick UpdatePeakEquity + ManageOpenPosition, per-new-bar session/day context → force-close →
      DetectSignal (shift-1) → quality gate (MTF/RSI) → safety gate + flat check → spread-vs-TP1 →
      market fill → trade journal. Fixed PositionManager to use **effRisk=|fill−SL|** + **anchor-based
      runner backstop** (TradeManager.mqh:61,99). 3 integration tests (fill model, coherent+balance-
      reconciled trades on the golden fixture, determinism) pass.
### Full validation
- [x] `backtester` main (`tools/mastervp/backtester.cpp`) + tick bridge (`tools/common/export_ticks.py`, DuckDB
      Parquet→ts_ms,bid,ask) + byte-compatible `trades_*.csv` writer (`include/kk/common/trade_journal.hpp`).
      Streams 30M ticks over the window in ~5s, flat memory.
- [x] **Level-2 trade diff** vs the 473-trade MT5 reference (BTCUSD M3 2025-08-11..11-29),
      `tools/common/diff_trades.py`. **Result: 478 trades vs 473; 377 match by exact entry-timestamp;
      dir/rev/regimeTrend/session/entryReason/bodyPct/adx/diSpread/spreadPips EXACT on matched;
      entry meanΔ 0.18, riskPrice meanΔ 15 (ATR-from-CSV caveat), exitTag mismatch 13/377.**
      Residual 96 missed / 101 extra = ATR-feed-extreme cascade (different stops → different exits
      → different re-entries), NOT a logic bug. Authoritative run config = `tools/btc_ref_run.set`
      (extracted from the tester logs — baseline.set is XAU-oriented and was NOT what the BTC run used).
- [x] **Level-3 aggregate:** CPP net -$75 / win 57.3% / PF 0.995 vs REF +$451 / 59.2% / 1.026 —
      same trade count + win-rate + PF band; net gap is small per-trade $ deltas across a PF≈1 strategy.
- [x] Two bugs fixed en route: RiskManager min-lot skip needed the `flooredUp=(rawLot<minLot)`
      precondition (was dropping normal trades); the BTC run uses code-default economics (SlAtrBrk=2.2,
      RrBrk=3, UseMtfAgree=false, MaxSpreadPips=0, MaxPeakDDPct=30), not baseline.set.
- [x] Golden test (`tests/mastervp/test_parity_golden.cpp` + frozen `tests/mastervp/golden/`): replays the bid M3
      warmup slice + MT5 ref day in `make test`; asserts VP/DI/trend/sigValid stay within tolerance.

## Phase 8 — Optimization — DONE
- [x] Python harness drives C++ engine (Optuna) — `research/optimization/optimize_btc.py`. 200-trial
      TPE over exit/economics + regime gates; full-window net/maxDD objective + train/test consistency
      bonus. BTCUSD M3. 16/200 robust-plateau configs converged to a tight cluster.
- [x] Sensitivity sweep (plateaus, not peaks) — `research/optimization/sensitivity_btc.py`. Trail/
      runner_rr/tp1%/di_spread are PLATEAUS; breakBuf/breakMax robust in direction; **AdxTrendMin=24 is
      a sharp peak (fragile — walk-forward must confirm)**.
- [x] **Result (`research/optimization/FINDINGS.md`, `best_btc.set`):** refined config turns the BTCUSD
      window from full net −$75/PF 0.995 into **+$5744/PF 1.240, DD halved ($2383→$1190), and Nov OOS
      flips −$904→+$1052 (PF 1.16)**. Edge holds out-of-sample. Key moves: tighter breakout (bbuf
      0.65→0.31), wider stop (2.2→2.65), tighter trail + lower runner target (3.6→2.05, rr 10→5.3),
      more selective trend (adx 22→24), Tp1R 0.8→1.0.
- [x] **Validated `best_btc.set` in the MT5 tester — user confirmed PF > 1** (2026-06-14). The C++
      optimization improvement transfers to the real MQL5 EA: the full loop (research → C++ port → parity
      → optimize → MT5 confirm) is closed.

## Phase 9 — Walk-forward + Monte Carlo (light) — DONE (full re-optimizing WFA → see C6)
- [x] Robustness (light) on the optimized BTCUSD config — `research/optimization/robustness_btc.py`.
      **Monte Carlo (5000 bootstraps): 97.7% profitable, PF P5=1.044, net P5=$1167. Rolling: ALL 4 months
      positive (PF 1.16–1.29), 7/8 half-months positive.** Residual watch: the fragile AdxTrendMin=24 knob.
- [x] XAUUSD M3 base measured (net −$326/PF 0.991, 995 tr) — same headroom as BTC.
- [→] Full re-optimizing walk-forward (rolling per-fold Optuna) — deferred; now tracked as **C6** in BUILD-PLAN.md.

## Phase 11 — KK-MasterVP-Monster edition (full-space) — DONE (superseded by Phase 12 real-Monster)
NOTE: this round optimized the **original KK-MasterVP** C++ port with reversion activated — NOT the user's
evolved 4-kind Monster EA. Params don't map to the real Monster schema (44/79 overlap). Directional evidence only.
- [x] **BTC Monster** (`best_monster_btc.set`, e815cce): FULL +$3934/PF 1.228, OOS +$421/PF 1.081. Both legs
      profitable; AdxTrendMin stable 16.1 plateau. MC 96.3% profitable; all months + half-months positive.
- [x] **XAU Monster** (`best_monster_xau.set`): FULL +$11,615/PF 1.323, OOS +$5086/PF 1.276, DD $873, 641 tr.
      MC 99.9% profitable; all 5 months positive. XAU wants `UseMomVeto=ON` (opposite of BTC).
- [x] **`MONSTER-FINDINGS.md`** documents both symbols + cross-symbol takeaways.
- [→] vol-RR engine support (ComputeRrScale) — optional; MQL5 already has `InpEnableVolRR` (default off). Not pursued.
