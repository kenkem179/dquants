# KenKem Quant OS - Institutional R&D Build Plan

Purpose: turn the XAUUSD/BTCUSD scalping program into a disciplined research and production machine that ships
**world-class profitable EAs** able to stand the test of time in volatile XAU and BTC markets:
**MasterVP** (tick-volume-profile breakout first, reversion second) and **KenKem** (EMA/ADX/RSI entry ensemble).

The Jupyter notebooks are **secondary support material**. They exist to teach and document the thinking process.
The top priority is always executable R&D, validation, production release, and live risk control for the EAs.

This is not a parameter wishlist. Each item is an executable experiment or production gate with a falsifiable
decision rule. Completed/rejected work moves to `docs/BUILD-PLAN-ARCHIVED.md`; update `HANDOFF.md` last.

Core external research anchors:
- Bailey & Lopez de Prado, **Deflated Sharpe Ratio**: selection bias, multiple testing, non-normal returns.
  https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2460551
- Bailey, Borwein, Lopez de Prado & Zhu, **Probability of Backtest Overfitting / CSCV**.
  https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2326253
- Lopez de Prado, **Hierarchical Risk Parity**.
  https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2708678
- Easley, Lopez de Prado & O'Hara, **Flow Toxicity / VPIN**.
  https://papers.ssrn.com/sol3/papers.cfm?abstract_id=1695596
- Cont, Kukanov & Stoikov, **Order-flow imbalance and short-horizon price impact**.
  https://arxiv.org/abs/1011.6402
- MetaQuotes MQL5 docs distinguish `tick_volume` from `real_volume` in `MqlRates`, and `CopyTicks` separates
  bid/ask quote ticks from last/volume trade ticks. In this CFD/MT5 context, MasterVP's "volume profile" must
  be treated as **quote/tick-activity profile**, not exchange traded-volume profile.
  https://www.mql5.com/en/docs/constants/structures/mqlrates
  https://www.mql5.com/en/docs/series/copyticks

Legend: `[~]` in progress, `[ ]` todo, `[B]` blocked on user/MT5/external data.

---

## Operating Doctrine

1. **MT5 is the final judge of exits.** The C++ engine remains the fast entry/detection tester, but MasterVP
   runner/trail exits have known optimism. Exit changes need MT5 A/B or optimizer confirmation.
2. **Gate 0 is parity.** No sweep result is trusted until C++/MQL5 behavior is reproduced to tolerance on a
   reference run for the symbol/timeframe/entry family being studied.
3. **Search must pay rent.** Every search records `n_trials`, `sr_trial_std`, OOS folds, MinTRL, PSR/DSR/PBO.
4. **Prefer structural hypotheses.** A new VP anchor, cost model, regime classifier, or exit-state machine is
   worth more than another small ADX/SL/RR grid on a single symbol.
5. **BTC is guilty until proven robust.** BTCUSD work must include realistic weekend/cost modeling, BTC-specific
   hour/session analysis, and MT5 confirmation. Do not inherit XAU assumptions.
6. **Release only portfolios, not isolated charts.** Live risk must be controlled at book level: EA x symbol x
   timeframe, not per chart.
7. **Tick volume is not real volume.** On Exness/MT5 CFD data, tick count is a quote-activity/liquidity proxy.
   Never claim traded-volume edge unless it is validated against `real_volume` or an exchange-traded proxy.
8. **Lagging indicators are state variables, not alpha by themselves.** EMA/RSI/DMI/ADX can describe trend,
   compression and regime, but entries, stops and targets must be validated through path behavior, structure,
   cost stress and forward evidence.

---

## Phase 0 - Immediate Baton / Product Hygiene

- [B] **P0.1 - MasterVP Profiler visual parity sign-off.**
  User MT5 task: attach `KK-MasterVP-Profiler` on XAU M5 with the current EA lock `.set`; confirm entries,
  verdicts, and stop paths match sampled EA backtest trades. Daily-DD is allowed to differ because it needs
  live equity.

  **Done when:** user confirms visual parity; then package Profiler market release.

- [ ] **P0.2 - MasterVP 1.07 upload follow-through.**
  Upload `releases/1.07/market/KK-MasterVP-Market-1.07.ex5`.

- [ ] **P0.3 - Handoff discipline.**
  Keep `HANDOFF.md`, `docs/CODEX-MEMORY.md`, this plan, and `docs/BUILD-PLAN-ARCHIVED.md` synchronized after
  every research run.

---

## Phase 1 - Reliability Infrastructure Before More Alpha

The objective is to stop spending statistical power on weak sweeps and make every future result auditable.
This phase exists because the current data/feature stack has two structural weaknesses: MT5 CFD tick profiles
lack real exchange volume, and EMA/RSI/DMI are lagging transforms. Reliability must come from measurement,
cross-checks and validation gates, not faith in any indicator.

- [ ] **R0 - Data truth and evidence-tier ledger.**
  Build a symbol/data-source evidence matrix:
  MT5 Exness ticks, MT5 bars, broker live logs, optional second broker feed, and optional exchange proxy
  (`GC`/`MGC` for gold, BTC futures or spot exchange data for BTC). For each source record:
  bid/ask availability, last/real volume availability, tick-count meaning, spread realism, timezone/session,
  gaps, weekend behavior, and whether it can be used for P&L, entry timing, or only robustness confirmation.

  **Output:** `research/data_quality/EVIDENCE_TIERS.md`.

  **Decision rule:** any MasterVP VP result from MT5 tick counts is labeled "quote-activity VP" unless it
  replicates on an independent traded-volume or cross-feed proxy. If quote-activity and real-volume evidence
  disagree, the feature is not release-grade until explained.

- [ ] **R1 - Tick-profile proxy validation.**
  Quantify whether tick-count/quote-activity profiles are stable enough to support MasterVP:
  compare profile levels across years, sessions, spread regimes, and if available second feed/exchange proxy.
  Measure whether VAH/VAL/POC distances and node-density ranks are preserved under:
  alternate broker feed, synthetic downsampling, spread spikes, missing ticks, and session re-anchoring.

  **Decision rule:** MasterVP may use tick-count VP only for structures whose level/rank stability survives
  perturbation. Unstable node-net/absorption values are research-only until parity/cross-feed proof.

- [ ] **R2 - Indicator lag and redundancy audit.**
  For EMA/RSI/DMI/ADX features, measure:
  signal delay versus price impulse, correlation/redundancy, half-life of predictive information, feature
  importance stability across folds, and whether each feature adds incremental value after price/volatility/VP
  structure is already known.

  **Decision rule:** lagging indicators can stay as regime/state filters only if they improve OOS robustness or
  conditional MFE/MAE. They cannot be the sole reason for an entry, SL, or target.

- [ ] **R3 - Experiment registry and immutable result ledger.**
  Build `research/registry/` with one JSON/YAML row per experiment:
  hypothesis id, strategy, symbol, timeframe, train/OOS dates, commit hash, data hashes, `.set` hash, cost model,
  `n_trials`, `sr_trial_std`, metrics, gate verdict, artifact paths, final decision.

  **Done when:** every new sweep/backtest/MT5 run writes a registry row and `research/registry/index.csv`.

- [ ] **R4 - Unified trade-stream schema.**
  Normalize C++ and MT5 trade CSVs into one canonical schema:
  `strategy,symbol,tf,entry_type,side,entry_ts,exit_ts,entry,exit,sl,tp,lot,spread,commission,slippage,
  pnl_usd,r_multiple,mfe_r,mae_r,exit_tag,regime_id,session_id,config_id`.

  **Done when:** `research/tools/normalize_trades.py` consumes current MasterVP/KenKem exports and validates
  required columns.

- [ ] **R5 - Realistic cost and latency model.**
  Add a symbol-specific cost surface:
  spread distribution by session/regime, commission per lot, latency tick-delay, adverse slippage, rollover/swap
  for holds crossing server rollover, weekend BTC spread shock model.

  **Decision rule:** any edge whose PF falls below 1.15, DSR below 0.95, or MinTRL fails under plausible costs
  is not release-grade.

- [ ] **R6 - Exit-model calibration audit.**
  Quantify where the C++ engine disagrees with MT5 for MasterVP exits:
  runner credit, trail path, BE/prog-trail sequencing, same-bar hit ambiguity, fill price, and tick-delay.

  **Output:** `research/mastervp_parity/EXIT_MODEL_CALIBRATION.md` with a correction/haircut policy.
  Until this is done, C++ exit-side wins are research leads only.

- [ ] **R7 - CPCV/PBO gate for all searched locks.**
  Wire `research/stats/cpcv.py` into the lock process. Use purged/embargoed folds whenever labels or trades
  overlap in time.

  **Done when:** the promotion script can report PSR, DSR, MinTRL, and PBO for each lock candidate.

- [ ] **R8 - Missing-data and cross-feed audit.**
  Build a matrix of coverage, spread realism, gaps, flat-spread years, and MT5-vs-export bar parity for XAUUSD
  and BTCUSD. Decide whether to add an independent broker/feed or exchange-traded proxy data for validation.

---

## Phase 2 - MasterVP: Breakout Book

MasterVP is the flagship because the VP breakout has a real XAU M5 edge and a coherent market hypothesis. The
task is to evolve from "rolling tick-activity VP breakout" to a structurally measured auction/volume-profile
breakout book. Until R0/R1 prove otherwise, every MasterVP VP feature is a **quote-frequency / liquidity
attention proxy**, not real traded volume.

- [ ] **M1 - Breakout event taxonomy.**
  For every detected breakout, export pre-entry features:
  distance to VAH/VAL/POC, distance to prior session VAH/VAL/POC, node density above/below, profile balance,
  breakout distance in ATR, local trend persistence, spread regime, time-of-day, post-breakout runway, and
  pseudo-order-flow variables from tick direction/classification. Mark every VP field with its source:
  `tick_count`, `real_volume`, `broker_second_feed`, or `exchange_proxy`.

  **Decision rule:** no new breakout gate can be swept until an edge autopsy shows monotone or economically
  explainable conditional expectancy using `mfeR/reach1R`, not only realized P&L.

- [ ] **M2 - Anchored/session VP engine.**
  Add default-OFF VP contexts:
  current session VP, prior session VP, London/NY session VP, swing-anchored VP, and rolling VP. Keep each
  profile causal and exported for parity.

  **Hypothesis:** first break from an auction range is higher quality when rolling tick-activity VP and
  anchored/session VP agree on value-area edge and next-node runway. If an exchange-volume proxy is available,
  require level/rank agreement before promoting any new VP logic.

  **Gate:** XAU M5 first; BTC only after cost/session model. A/B against current lock with unchanged exits.

- [ ] **M3 - Multi-timeframe VP confluence.**
  Use M15/H1 or session VP to classify whether M5 breakout is:
  continuation away from higher-TF value, breakout into higher-TF value, or failed auction back into value.

  **Decision rule:** adopt only if it improves worst-fold PF and tail drawdown without relying on a single
  2026 runner cluster.

- [ ] **M4 - Breakout quality model / meta-label.**
  Build a secondary model that does not choose direction. It only sizes/filters already-valid MasterVP breakout
  entries using features available at entry.

  **Constraints:** purged CV, embargo, probability calibration, monotonic sanity checks, no more than a small
  feature set, and a hard fallback to rule-based lock if OOS calibration drifts.

- [ ] **M5 - True discrete profit-rung ladder.**
  Build default-OFF `pm_ladder`: e.g. bank x% at 1R, y% at 2R, trail remainder, with C++ and MQL parity.
  Current ProgTrail is a continuous ratchet, not a discrete liquidation ladder.

  **MT5-first decision rule:** run on XAU M5; accept only if pooled PF, 2025H2, 2026, DD, and DSR all beat or
  tie the current ProgTrail lock. Engine is not enough.

- [ ] **M6 - Failed-breakout / reversion book design.**
  Do not add reversion as random countertrend. Define explicit failure states:
  breakout beyond VAH/VAL, no continuation within N bars, return into value, adverse flow/toxicity, and local VP
  rejection. Reversion TP should be local POC/value mean, not blindly the master POC.

  **Decision rule:** reversion book must have positive standalone expectancy, low correlation to breakout book,
  and improve portfolio DD. If it only lowers DD by deleting breakout winners, reject.

- [ ] **M7 - BTC MasterVP revisit only after R0/R1/R5/M2.**
  BTC can be revisited only with BTC-specific sessions/weekend costs, evidence-tier labeling, tick-profile
  stability checks, and anchored VP/runway variables. The prior BTC M3/M5 evidence is negative. Treat any BTC
  win as a hypothesis until MT5 confirms.

---

## Phase 3 - KenKem: EMA/ADX/RSI Strategy Rebuild

KenKem is valuable because it is less correlated with MasterVP, but its current entries, SL distance and fixed
RR are too rule-of-thumb. EMA/RSI/DMI are lagging transforms, so the objective is to preserve the proven XAU M1
edge while replacing indicator-trigger faith with measured invalidation, path behavior, regime filters and
dynamic targets.

- [ ] **K1 - Entry-family autopsy at bar and trade level.**
  For E1/E2/E4/E5, export:
  trigger type, EMA stack compression/expansion, trend age, cross age, touch age, ADX/DI state, ATR percentile,
  session, distance to EMA200, distance to VP levels, pre-entry chop score, MFE/MAE path, exit bucket.

  **Decision rule:** no entry filter is swept until it shows a conditional `mfeR/reach1R/maeR` edge and keeps
  `n >= MinTRL`.

- [ ] **K2 - Lag-aware entry redefinition.**
  For each E1/E2/E4/E5 entry, separate:
  (a) the **trigger** that acts near the turn/expansion, (b) the **state filter** that confirms regime, and
  (c) the **risk geometry** that defines invalidation. EMA/RSI/DMI should mostly live in (b), not pretend to be
  fast predictive triggers.

  **Output:** `research/kenkem_parity/KENKEM_ENTRY_ROLE_AUDIT.md`.

  **Decision rule:** if an entry only works because a lagging indicator crosses after the move is already
  mature, it must be redesigned, downweighted, or rejected.

- [ ] **K3 - ATR-relative parameter purge for cross-symbol work.**
  Convert decision thresholds currently expressed in pips/points into ATR-relative or spread-relative units:
  EMA alignment tolerance, RSI divergence min distance, EMA distance SL bounds, min SL, TP extension bounds,
  bare `N*pip_size` literals.

  **Done when:** XAU M1 reproduces the lock under converted defaults, then BTC M1/M3/M5 can be tested without
  meaningless XAU pip thresholds.

- [ ] **K4 - Structural stop-loss research.**
  Replace blind ATR/fixed distance with measured invalidation candidates:
  EMA stack invalidation, swing high/low, VP value-area edge, FVG boundary, ATR floor/cap, and spread buffer.

  **Gate:** compare by entry family; preserve or improve `maeR`, tail loss, and PF under realistic costs. MT5
  confirms final exit geometry.

- [ ] **K5 - Dynamic RR / target policy.**
  Replace fixed RR with target families:
  nearest VP node, prior session value edge, ATR-scaled target capped by expected MFE, trend-strength-conditioned
  RR, and time-stop if MFE does not develop.

  **Decision rule:** target policy must improve expectancy per unit drawdown without relying on top-5 winners.

- [ ] **K6 - Regime-conditional entry ensemble.**
  Instead of static E1/E2/E4/E5 on/off, assign each entry type to regimes:
  trend persistence, compression-to-expansion, chop, high-spread/low-liquidity, session. This can be rule-based
  first; ML meta-label only after the rule-based matrix is stable.

  **Guardrail:** do not cut trade count below MinTRL. Use per-quarter OOS; 2025Q3 chop and 2026Q2 softness are
  the explicit stress cases.

- [ ] **K7 - E5 reopen only if it adds independent sample safely.**
  E5 has a known latch/onset trap and currently stays off. Reopen only if the goal is to add sample while
  preserving parity, not to chase noisy net profit.

  **Done when:** exact latch parity is proven or a deliberate, default-OFF approximation beats the lock in MT5
  with DSR pass.

- [ ] **K8 - BTC KenKem program.**
  Run only after K3. Test BTC M1/M3/M5 as independent hypotheses with BTC-specific cost/session models.

  **Decision rule:** adopt a BTC KenKem lock only if it clears standalone PF, per-fold/per-quarter robustness,
  DSR/PBO/MinTRL, and final MT5 confirmation. Otherwise record rejected and keep BTC closed.

---

## Phase 4 - Regime, Portfolio and Risk

The real production product is a book of trade streams. This phase decides when each stream is allowed to trade
and how much risk it receives.

- [ ] **P1 - Regime state model.**
  Build a compact regime classifier:
  volatility percentile, trend persistence/Hurst proxy, VP balance/imbalance, spread/cost regime, session, and
  recent realized drawdown state. Start unsupervised for diagnostics, then hard-code simple deployable states.

  **Output:** per-trade regime id in normalized trade schema.

- [ ] **P2 - Conditional expectancy matrix.**
  For each stream (`MasterVP breakout`, `MasterVP reversion`, `KenKem E1/E2/E4/E5`, symbol, timeframe), compute
  expectancy, PF, MFE, MAE, hit-rate, DD contribution by regime.

  **Decision rule:** a stream trades only in regimes where conditional expectancy is positive and sample size is
  sufficient, or it is explicitly marked "exploratory/demo only".

- [ ] **P3 - Portfolio allocation.**
  Use HRP/risk parity as default because small samples make mean-variance unstable. Compare equal risk, inverse
  variance, HRP, and capped fractional Kelly under purged CV.

  **Done when:** output is lot multipliers per stream plus component-risk contribution and tail-correlation report.

- [ ] **P4 - Account-level risk governor.**
  Build live MT5 Layer-4 risk controls:
  total open risk cap, shared daily DD, shared trailing DD, common flatten/halt latch, and per-symbol exposure
  cap via terminal GlobalVariables.

  **This is release-critical:** per-EA DD limits are not enough when multiple EAs share one account.

- [ ] **P5 - Live drift monitor.**
  Daily/weekly report:
  realized PF vs expected, slippage/spread distribution, entry count by regime, exit bucket drift, correlation
  drift, drawdown overlap, and kill-switch status.

---

## Phase 5 - Production Release Gates

No strategy or portfolio is "production" until every gate passes.

- [ ] **G1 - Data gate.**
  Raw -> processed -> bars/features reproducible; no hidden data gaps; MT5 reference bars match; costs measured;
  evidence tier assigned to every data source; tick-volume features labeled as quote-activity proxies unless
  cross-feed/real-volume validation exists.

- [ ] **G2 - Parity gate.**
  C++/MQL5 or MQL5/MT5 reference diff passes at bar, entry, and trade levels for the specific symbol/TF.

- [ ] **G3 - Edge autopsy gate.**
  Conditional edge is visible in MFE/MAE/path metrics before realized P&L and is economically coherent. Lagging
  indicator features must add incremental OOS value after price/volatility/VP structure is known.

- [ ] **G4 - Validation gate.**
  Costs -> sensitivity plateau -> WF/CPCV -> MC -> PSR/DSR/PBO/MinTRL -> final MT5 confirmation.

- [ ] **G5 - Portfolio gate.**
  Stream-level edge plus book-level allocation and account risk cap. No single EA release without book-risk
  impact estimate.

- [ ] **G6 - Forward-test gate.**
  Demo or tiny-live forward test with expected-vs-realized scorecard. Promote only after drift is explainable.

---

## Secondary - Learning Path Notebook

- [ ] **L1 - Maintain the notebook learning spine.**
  The standalone notebook `ds-study/notebooks/13_institutional_scalping_rd_playbook.ipynb` is the glossary and
  thinking-process guide for this plan. Keep it useful, but never let notebook polish outrank building,
  validating, hardening, and releasing profitable EAs.
