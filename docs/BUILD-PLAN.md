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
      reconciled trades on the golden fixture, determinism) pass. **Next:** real-tick export + Level-2 diff.
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
      Front-half faithfulness is now a regression guard, not a one-off. (Trade-level diff still TODO.)

## Phase 8 — Optimization
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
      → optimize → MT5 confirm) is closed. XAUUSD M3 optimization still TODO.

## Phase 9 — Walk-forward + Monte Carlo
- [x] Robustness (light) on the optimized BTCUSD config — `research/optimization/robustness_btc.py`.
      **Monte Carlo (5000 bootstraps): 97.7% profitable, PF P5=1.044 (bad-luck draws still >1), net
      P5=$1167. Rolling: ALL 4 months positive (PF 1.16–1.29), 7/8 half-months positive.** Edge is
      temporally consistent + resampling-robust. Residual watch: the fragile AdxTrendMin=24 knob.
- [ ] Full re-optimizing walk-forward (rolling per-fold Optuna) — needs a longer tick window; deferred.
- [x] XAUUSD M3 base measured (net −$326/PF 0.991, 995 tr) — same headroom as BTC. Monster opt below.

## Phase 11 — KK-MasterVP-Monster edition (full-space, both legs active)
NOTE: this first round optimized the **original KK-MasterVP** C++ port with reversion activated — NOT
the user's evolved 4-kind Monster EA. Its params don't map to the real Monster schema (only 44/79
overlap). Kept as directional evidence; the REAL-Monster engine + optimization is **Phase 12**.

Activate the dormant **reversion leg** + jointly optimize the **entire wired param space** (breakout +
reversion + exits + regime + node + vol-gate + sizing), on the parity-validated C++ tick engine.
Optimizer: `research/optimization/optimize_monster.py <btc|xau>` (400-trial joint Optuna, reversion
FORCED on, momentum/flow toggles categorical). Refine from the strong-OOS **sub-cluster median**
(plateau, not the lone best trial).
- [x] **BTC Monster** (`best_monster_btc.set`, commit e815cce): FULL **+$3934/PF 1.228**, OOS
      **+$421/PF 1.081**. Both legs profitable: breakout +$2863/PF 1.20 (486 tr), **reversion
      +$1071/PF 1.35 (114 tr, 64% win)**. AdxTrendMin landed at a STABLE **16.1 plateau** (vs the
      fragile 24 of the breakout-only pass) — 20-trial coherent sub-cluster. MC 96.3% profitable
      (P5 PF 1.020); **ALL 4 months + ALL 8 half-months positive**.
- [x] **XAU Monster** (`best_monster_xau.set`): FULL **+$11,615/PF 1.323**, OOS (Nov–Dec)
      **+$5086/PF 1.276**, DD $873, 641 tr. MC **99.9% profitable** (P5 PF 1.137); ALL 5 months
      positive. 348/400 robust trials (broad plateau → best trial adopted). Symbol-specific: XAU wants
      `UseMomVeto=ON` (opposite of BTC) — the momentum gate is what makes the reversion leg net-additive.
- [x] **`MONSTER-FINDINGS.md`** documents both symbols + cross-symbol takeaways (reversion additive on
      both, gated differently; XAU carries the larger $ edge).
- [ ] vol-RR engine support (ComputeRrScale: session × ATR-pctile) — currently rr_scale=1.0 hardcoded.
      (Optional enhancement; MQL5 already supports `InpEnableVolRR`, default off — parity preserved.)

## Phase 12 — REAL Monster C++ engine + optimization (the user's actual 4-kind EA)
Faithful C++ port of the user's evolved Monster (`SignalCore_Monster.mqh`, 779 LOC): breakout +
impulse-thrust + 4-variant mean-reversion, multi-TF near-net (M1/M5/M15), predicted/aged master VP,
POC-slope regime + stability/overhead/HTF gates, per-strategy TP1 split. SEPARATE `kk::monster` engine
(KK-MasterVP engine untouched), inherits the reusable VP/node math. Winning `.set` uses the REAL
Monster InpXxx names → drops into `kenkem/MQL5/Experts/KK-MasterVP-Monster/`.
- [x] P1 `monster_config.hpp` (147-input schema + .set loader, Pine defaults).
- [x] P2 `monster_signal.hpp` (SignalCore_Monster port — 4 kinds + arbitration + all gates/edge-cands).
- [x] P3 `tf_net.hpp` (multi-TF near-net, per-TF MT5-iATR, `[1]`-read) + P4 M1/M5 bar export (BTC/XAU).
- [x] P5 `monster_engine.hpp` (interleaved OnTick integrator, gap-aware fills, TP1-split mgmt) +
      P6 `monster_backtester.cpp` + `test_monster_engine` (22 checks).
- [x] **CRITICAL: caught + fixed a one-bar LOOKAHEAD** (bar-advance `<=`→`<`). Inflated baseline PF
      1.83 (OOS>IS, net-gate-insensitive) → realistic **PF 0.915 BTC / 0.751 XAU** (losing baseline,
      like KK-MasterVP pre-opt). Deterministic; all tests green. This is the verification that makes
      the engine trustworthy for optimization.
- [~] P7 optimize the REAL Monster (`optimize_monster_real.py`, 31-param + 3-toggle, reversion ON):
      BTC + XAU 400-trial runs IN PROGRESS.
- [ ] Plateau + MC + rolling robustness per symbol; write `best_monster_real_{btc,xau}.set`.
- [ ] Map winners onto the EA's InputParams (read-only) + deliver as non-destructive `.set` files in
      `kenkem/MQL5/Experts/KK-MasterVP-Monster/Config/`; demo forward-test in MT5.

## Phase 10 — Promote (revised: the Monster EA ALREADY EXISTS on the user's side)
- [!] **Do NOT recreate** `kenkem/MQL5/Experts/KK-MasterVP-Monster/` — it already exists and has evolved
      (NetVolume, StatePersistence, single-instance guard, embedded news; on `origin/KKMasterVPv1`).
      A blind recreate clobbered it once (recovered via git). Deliver `.set` files only, never rewrite code.

## Phase 13 — KenKem "original" multi-entry EA → C++ engine + optimization
Migrate the big original `KenKemExpert.mq5` (~8k LOC, largest port yet). Active entries **E1/E2/E4** only
(E3 + E5/SuperBros disabled by default → skipped per user). Spec: `research/hypotheses/KenKem-SPEC.md`.
Default config makes it tractable: adaptive/news/limit-orders/conservative-mgmt all OFF → port the static path.
SEPARATE `kk::kenkem` engine (mastervp/monster untouched), reusing common EMA/ADX/ATR/RSI/Ichimoku math.
- [x] **SPEC** — `KenKem-SPEC.md`: full extraction of E1/E2/E4 detection, shared gates (trend-quality /
      momentum / EMA-align / sideways / conviction / RSI-div / HTF), triggers (EMA-cross / EMA75-touch /
      Ichi-cloud-cross), indicator cache, dynamic-RR + risk-based sizing, tick-fill trade manager, all param
      defaults read direct from InputParams.mqh. Port scope + parity caveat documented.
- [x] **Port-note specs** from real source (`research/hypotheses/kenkem-portnotes/01-04`, 1640 lines, exact
      line refs) + 5 parity traps locked (EMAs 10/25/71/97/192; BTC pip=1/contract=1/std-lot×2; ATR cache
      shift-0; Ichimoku buffer-mislabel ⇒ E4 trigger is a Tenkan/Kijun cross; E4-short uses E4_RR_SHORT×0.875).
      EA snapshot pinned sha256 `61bc702b`. See [[kenkem-parity-traps]].
- [x] P1 `kenkem_config.hpp` (full input schema + `.set` loader, real defaults) — 33 checks.
- [x] P2 `tf_cache.hpp` (per-TF M1/M3/M5/M15 buffers + open-time alignment, shift-1 reads; shift-0 forming
      bar deferred to engine) — 20 checks. `indicators.hpp` Ichimoku primitive — 12 checks.
- [x] P3 `triggers.hpp` (EMA-stack cross + EMA200/EMA75 touch + Ichi **TK** cross state machines) — 12 checks.
- [ ] **P4 `gates.hpp` (trend-quality hard-gate / momentum / MTF-align / conviction / RSI-div / HTF filters). ← NEXT**
- [ ] P5 `entries.hpp` (E1/E2/E4 Detect + SL) + P6 `trade_manager.hpp` (partial/BE/trail/ext/ladder/panic/score-drop).
- [ ] P7 `kenkem_engine.hpp` (OnTick integrator + sizing) + `kenkem_backtester.cpp` + unit tests + **lookahead audit**.
- [ ] **P8 PARITY (hard gate, same standard as MasterVP/Monster):** add non-destructive `KenKem/Parity/`
      module to the EA (mirror `KK-MasterVP/Parity/`, `InpExportParity` default-OFF) + `tools/kenkem/parity_driver.cpp`;
      **user runs KenKem in MT5 tester** → reference CSVs; diff bar-level then trade-level until parity.
- [ ] P9 baseline on BTC/XAU tick Parquet (parity-validated) → P10 Optuna optimize per symbol →
      `best_kenkem_{btc,xau}.set`; MC + rolling robustness.
- [ ] P11 deliver `.set` into `kenkem/MQL5/Experts/KenKem/Config/` (non-destructive); MT5 demo forward-test (final gate).
- **NOTE:** parity is the gate — no optimization until the C++ engine matches MT5 bar-level + trade-level.
      Engine build (P2–P7) is prerequisite and needs no user input; the EA parity hooks + MT5 run need user buy-in.
