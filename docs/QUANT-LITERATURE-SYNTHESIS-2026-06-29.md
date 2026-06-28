# Quant-Literature Synthesis — what to borrow, what to ignore (2026-06-29)

Source PDF (`My - Study notes.pdf`, 191 pp) concatenates two books:
1. **Ernest P. Chan — _Quantitative Trading: How to Build Your Own Algorithmic Trading Business_ (2nd ed.)** — pp.1–74.
   Discipline, performance metrics, Kelly/risk, regime, stationarity/cointegration, exits.
2. **Peng Liu — _Quantitative Trading Strategies Using Python_ (Apress, 2023)** — pp.76–191.
   Returns/risk foundations, technical indicators, trend/momentum backtesting, **Bayesian optimization via Gaussian Processes**.

**Framing (mutual-skepticism):** dquants is already *ahead* of both books on the thing that kills retail quants —
overfitting statistics. We run DSR/PSR/MinTRL/CPCV/PBO (post-2014 Lopez-de-Prado machinery); Chan (pre-2014) only
warns qualitatively about data-snooping and "use fewer parameters." So we do **not** adopt their weaker rigor. We mine
them for techniques we are genuinely lighter on, and we reject the parts that don't survive contact with XAU/BTC CFD
M1/M3 scalping. Every adopted item gets a falsifiable decision rule and goes through the existing gate before it locks.

---

## TIER 1 — Adopt now (genuinely additive, low risk)

### 1. Empirical Kelly position sizing + risk-of-ruin (Chan Ch.6)
- **Idea:** optimal fraction-of-equity-to-risk maximizes long-run log-growth; `g = m − s²/2` (variance directly
  destroys compounding); max growth ∝ Sharpe². Half-Kelly for safety; the binding cap is
  `min(half-Kelly, maxTolerableDD / worstHistoricalLoss)`. Delever as trailing mean→0 (Kelly f→0); never average down.
- **Why it's additive:** our BUILD-PLAN Phase-4 P3 only *names* "capped fractional Kelly" — it was never computed.
  Live sizing is currently ad-hoc.
- **dquants caveat:** Chan's closed form `f=m/s²` assumes Gaussian. XAU/BTC have documented fat tails
  ([[mastervp-profit-lock-ladder]] "real fat tail"), so Gaussian-Kelly **over-bets**. We compute *empirical* Kelly
  (`argmax_f mean ln(1+f·R)` over realized R-multiples) instead — built in `research/risk/kelly_sizing.py`.
- **Live result (this session):** KenKem XAU M1 full-Kelly **0.174**, half-Kelly **0.087**, but Monte-Carlo
  **risk-of-ruin(50% DD) = 44%** at half-Kelly → KenKem should sit at **quarter-Kelly or a fixed 1–2%/trade**, far
  below the growth-optimal point. MasterVP-BTC Kelly ≈ 0 (consistent with its REJECT). **Decision rule:** no strategy
  is sized above the drawdown-capped fraction, and never above quarter-Kelly given fat tails.

### 2. Ornstein-Uhlenbeck half-life for mean-reversion timing (Chan Ch.7, Ex.7.5)
- **Idea:** fit `dz = θ(μ−z)dt`; half-life `= ln2/θ` is the robust expected reversion time, estimated from the
  **whole series** (not the few trades → data-snooping-safe). Use it as the holding-period / time-stop for any
  mean-reversion logic, and `μ` as the reversion target.
- **Adopt for:** MasterVP reversion-book holding bound (M6); a regime feature (P1). Built `research/stats/half_life.py`.
- **Caveat:** half-life drifts across regimes — estimate per-quarter; a positive/insignificant β means *not*
  mean-reverting on that horizon → do **not** impose a reversion time-stop (treat as trending).

### 3. Regime-conditioned stop-loss law (Chan Ch.6 — the single best exit insight in either book)
- **Idea:** a stop-loss is only rational in a **momentum/trending** regime; in a **mean-reverting** regime a stop
  exits at the worst possible time and is harmful. Heuristic for which regime: **news/fundamental-driven moves trend**
  (don't stand in front of the freight train); **price moves with no news = liquidity events → mean-revert** (hold).
  Corollary: prefer exiting on an *opposite entry signal* over an arbitrary stop price (no extra data-snooped param).
- **Why additive:** our SL/exit research (K4, M6) and the MasterVP "don't give it back" falsifications never
  *conditioned the stop on regime*. This reframes them: the giveback-stops failed because XAU breakouts are momentum
  (stops help) while we were testing reversion-style giveback logic.
- **Decision rule:** exit policy must be selected per regime label, not globally; an SL change is only adopted if it
  helps in the regime it's meant for and is neutral-or-better pooled. Ties into Tier-1 #2 and Tier-2 #5.

---

## TIER 2 — Adopt as upgrades to existing phases (medium effort, gated)

### 4. Bayesian optimization via Gaussian Processes for the sweep (Liu Ch.9)
- **Idea:** model the noisy black-box objective `Sharpe = f(params)` with a GP surrogate; an acquisition function
  balances explore/exploit to find the optimum in *far fewer* costly backtests than grid search. Objective should be
  risk-adjusted (Sharpe / Calmar), and **evaluated over multiple backtesting periods**, taking the params that are
  consistently good (robustness), not the single-period peak.
- **vs what we have:** we use Optuna (TPE). GP-BO is a sibling; the *real* upgrade is Liu's **multi-period-consistency
  objective** — score a param set by its worst/!median across folds, not pooled return. That directly attacks the
  peak-vs-plateau failure mode the CLAUDE.md rules already care about.
- **Decision rule:** the sweep objective becomes "best *worst-fold* costed PF/Sharpe," and every BO/Optuna lock still
  passes the DSR/PSR/MinTRL + CPCV/PBO gate with recorded `n_trials`/`sr_trial_std`. BO changes search efficiency, not
  the lock bar.

### 5. Conditional Parameter Optimization / CPO (Chan Ch.7, Ex.7.1)
- **Idea:** instead of static params (or slow walk-forward), train a supervised model (random-forest+boosting) to
  predict **the strategy's own next-period return** given (candidate params + market-condition features); each period
  pick the params with the best predicted outcome. Key: you predict *your strategy's* return, not the market's —
  a non-reflexive, private target nobody else is arbitraging.
- **Adopt for:** the regime-conditional ensemble (K6) and breakout-quality model (M4) — this is the principled way to
  make KenKem E1/E2/E4/E5 on/off and MasterVP exits regime-adaptive.
- **Hard caveat:** this is the most overfit-prone technique in either book. Mandatory purged/embargoed CV + PBO, a
  small feature set, monotonic sanity checks, and a hard rule-based fallback if OOS calibration drifts. Build
  **default-OFF**, prove it beats the static lock in MT5, or it stays research-only.

### 6. Metalabeling (Chan Ch.2/3 — Lopez de Prado) for trade sizing/filtering
- **Idea:** a secondary model that does NOT pick direction; it only predicts the **probability your already-valid
  signal is profitable**, and sizes/filters with it. Private, non-reflexive target.
- **Adopt for:** M4 (already names "meta-label") and as the sizing input feeding Tier-1 #1 (Kelly × P(profit)).
- **Caveat:** same overfit discipline as #5; only over the existing entry signals, never to invent new entries.

---

## TIER 3 — Note, mostly already covered or low-applicability

- **Sharpe rules of thumb (Chan):** SR<1 not standalone; ~2 = profitable most months; ~3 = most days. Add **Calmar =
  CAGR/maxDD** to the perf table (cheap, useful). HFT high-SR-via-law-of-large-numbers argues our M1/M3 scalping
  cadence is the *right* regime for high Sharpe — keep frequency up.
- **Backtest-bias checklist (Chan Ch.2/3):** survivorship, look-ahead (point-in-time vs restated), data-snooping,
  regime shift, **favor recent-period performance**. We already enforce most; the explicit "weight the most recent
  months heaviest" is worth codifying (matches the BTC regime-dependent finding [[btc-no-robust-edge-closed]]).
- **Low-beta + leverage > high-beta (Chan Ch.7):** equities-specific (Fama-French). N/A to single-instrument
  XAU/BTC scalping, but the underlying truth — *prefer the lower-variance path and lever it, because growth ∝ Sharpe²*
  — is exactly why our cost/variance control matters more than chasing raw return.
- **Cointegration / pairs trading (Chan Ch.7):** not our game (single-instrument scalping). Keep the *stationarity*
  machinery (#2), drop the pairs framing — UNLESS we ever build an XAU-vs-GC or BTC-vs-BTC-futures cross-feed, where
  CADF/Johansen would apply (ties to the deferred R8 cross-feed audit).
- **Factor models / PCA (Chan Ch.7), seasonal trades:** portfolio/cross-sectional; low applicability to two
  instruments. Seasonal/time-of-day *is* relevant (we already block hours — [[mastervp-m5-t2-hour-block-lock]]).
- **Liu foundations (returns/log-returns/variance/indicators):** below our current level; nothing to adopt.

---

## Net changes this synthesis drives
- New tools: `research/risk/kelly_sizing.py`, `research/stats/half_life.py` (Tier-1 #1/#2, built + self-tested).
- BUILD-PLAN: strengthen P3 (empirical-Kelly sizing + risk-of-ruin), add a **regime-conditioned exit** item, add
  **OU half-life** to the reversion/regime work, add **CPO** and **multi-period-consistency BO objective** to the
  sweep/ensemble phases, add **Calmar** + "weight recent months" to the metrics/gate. All gated; nothing locks without
  DSR/PSR/MinTRL + MT5.
- Memory: reference facts for empirical-Kelly sizing, the regime-conditioned stop-loss law, OU half-life, CPO/BO.
- **Unchanged:** released editions, the overfitting gate bar, MT5-is-final-judge-of-exits. We got more techniques, not
  a lower standard.
