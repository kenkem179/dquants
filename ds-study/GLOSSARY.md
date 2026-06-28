# 📖 Glossary & key concepts — for the aspiring quant data scientist

Don't run the notebooks blindly. Each term below has: **what it means** (plain English), **why it
matters here** (this project, not a textbook), and **where you meet it** (which notebook). Curated free
learning links are at the bottom.

**Legend:** `00` raw data · `01` validate · `02` bars · `03` features · `04` labels · `05` EDA ·
`06` characterize · `07` correlation/hypothesis · `08` discovery · `09` backtest · `10` strategies

---

## A. Data engineering — getting from raw text to query-able data

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Tick** | One bid/ask update from the broker at a moment in time. | The rawest data we have; everything is built up from ticks. | 00 |
| **Bid / Ask / Mid / Spread** | Sell price / buy price / their average / their gap (`ask−bid`). | We build signals on **mid** and pay the **spread** as a cost on every trade. | 00, 09 |
| **In-memory vs streaming** | Load the whole file into RAM (pandas) vs read it in chunks (DuckDB). | A 7 GB tick file won't fit in RAM — we **stream**. Never `pandas.read_csv` the raw ticks. | 00 |
| **DuckDB** | An in-process SQL engine that streams Parquet/CSV without loading it all. | The workhorse of the whole Layer-1 pipeline; counts 15 M rows in seconds, flat RAM. | 00–02, 09 |
| **Parquet** | A compressed, **columnar**, typed file format. | Reads only the columns you ask for → 10–100× faster than CSV. All our processed data is Parquet. | 00+ |
| **Columnar storage** | Values of one column stored together (vs row-by-row in CSV). | Asking for `spread` reads only spread bytes; pre-typed + compressed. *The* format of modern data work. | 00 |
| **One-directional pipeline** | `raw → processed → clean → bars → features → labels`, each written once, never edited. | Reproducibility: re-run from untouched ticks → byte-identical result. Same as an idempotent data pipeline. | 00–04 |

## B. Data quality & cleaning

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Data-quality checklist** | Systematic checks: bad prices, crossed spread, duplicates, spikes, gaps, coverage. | Bad ticks are the **#1 source of fake edges**. Cleaning is a hard gate. | 01 |
| **Drop vs keep+flag** | Delete the physically impossible; *keep & report* the merely weird. | A wide spread in a crash isn't an error — it's the key bar. Don't delete real signal. | 01 |
| **Spread-realism trap** | This feed's spread is variable in 2024 but flat in 2025/26. | Calibrate costs on flat years → understate the cost of trading in volatility. Career-saving caveat. | 01 |
| **Missing value (NaN)** | An absent cell — from warm-up, gaps, or no observable future. | Indicators are NaN until warmed up; labels are NaN for the last H bars. Drop, never invent. | 01, 03, 04 |
| **Lookahead / data leakage** | Letting information from after `t` influence a decision at `t`. | The #1 way to fake an edge. `bfill` leaks the future; we never invent ticks. *Career-ending bug.* | 01, 03, 04 |

## C. Bars & resampling

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Bar / candle (OHLC)** | Open/High/Low/Close summary of all ticks in a time window. | Strategies reason about candles, not raw ticks. KenKem trades **M1/M3** (never M5). | 02 |
| **Resampling / aggregation** | Collapsing many rows into one summary row per time bucket. | Ticks → M1/M3 bars via DuckDB `time_bucket`. Lossy on purpose — exposes structure. | 02 |
| **Event-time / sparse bars** | A bar exists only for a minute that had ≥1 tick. | Weekends & dead minutes simply don't exist (matches MT5). Indicators run on the **bar sequence**, not a clock. | 02 |
| **`tick_count`** | How many ticks formed a bar — our **volume proxy** (real volume is 0 on this feed). | The *weight* for the Volume Profile that MasterVP/Monster are built on. | 02, 03 |
| **Reconciliation** | The "does it add up?" check — Σ`tick_count` must equal the tick count. | Cheapest, highest-value test in data engineering; catches silent bucketing bugs. | 02 |

## D. Feature engineering — describing market state

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Feature** | A number describing the situation at bar `t` (the model's input `X`). | The highest-leverage skill in applied DS — research lives or dies here. | 03 |
| **Causality contract** | Every feature at `t` uses only bars `≤ t`. | The rule that outranks all others. Proven by a truncation test. | 03 |
| **Normalization** | Express features as **distances** (`(price−level)/price`) or **slopes** (% change). | Makes features comparable across price levels & instruments → same code works on BTC *and* XAU. | 03 |
| **EMA (moving average)** | Exponentially-weighted average of price; reacts faster than a simple MA. | Trend family; MT5 `adjust=False` convention so the MQL5 EA matches. | 03 |
| **RSI** | Momentum oscillator (0–100) from recent gains vs losses. | A *state descriptor* (value + slope + accel), not a naive buy/sell trigger. | 03 |
| **ATR (Average True Range)** | Average bar range — the project's **unit of risk**. | Stops/targets are placed in ATR multiples, so the strategy adapts to calm vs wild. | 03, 04 |
| **ADX / DI** | Trend **strength** (ADX) vs **direction** (+DI/−DI). | The regime gate: only trade breakouts when a trend is present. DI beat RSI in discovery. | 03, 08 |
| **Volume Profile (POC/VAH/VAL)** | Histogram of activity by *price*: peak = POC, ~70% band = value area. | **The** feature family for MasterVP/Monster; ranked #1 in discovery. Causal (uses *yesterday's* profile). | 03, 08 |
| **Ichimoku (Tenkan/Kijun)** | Trend/structure lines from rolling high-low midpoints. | KenKem's distilled E4 entry is a Tenkan/Kijun cross. | 03 |
| **Warmup** | Leading rows that are NaN until the slowest indicator has enough history. | EMA200 + ~1-day ATR window must fill; warmup rows are reported & dropped, never back-filled. | 03 |

## E. Labels — what we predict

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Supervised learning** | Learn a mapping `features(t) → label(t)` from many examples. | Frames the whole problem: can market-state predict the near future? | 04, 08 |
| **Forward return** | `close(t+k)/close(t) − 1` — where price goes next. | Simplest label; uses `shift(-k)` (legal lookahead — labels *may* see the future). | 04 |
| **Lookahead asymmetry** | Features look back; labels look forward; you act only on features. | Last `k` bars have no label (NaN) and must be dropped. | 04 |
| **Triple-barrier method** | Label by which is hit first: TP (`+1`), SL (`−1`), or time-out (`0`). | Path-aware, ATR-scaled — mimics a real stop-based trade (López de Prado). | 04 |
| **Class balance** | The fraction of each label class. | Symmetric 1×ATR is ~49.6/50.4 — a coin flip. That *honest* result pushes us to asymmetric targets. | 04, 08 |

## F. Describing data (univariate / bivariate)

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Mean / Median / Std** | Average / middle / typical spread of values. | Mean vs median divergence ⇒ skew. Std is the denominator of Sharpe, z-score, t-stat. | 05 |
| **Histogram / Outlier / IQR** | Distribution shape / far-out value / middle-50% range. | *Look before trusting a number.* In trading, outliers are often the interesting bars. | 05 |
| **Skew / Kurtosis / fat tails** | Asymmetry / tail-heaviness vs a bell curve. | Returns have **fat tails** — extremes far more common than 'normal' predicts; risk models must respect it. | 06 |
| **Stationarity / ADF test** | Stats that don't drift over time / a test for it. | **Price is non-stationary, returns are stationary** — *why* quants model returns, proven not assumed. | 06 |
| **Autocorrelation (ACF)** | Correlation of a series with its own past. | Returns ≈ 0 (efficient), but **\|returns\| > 0 = volatility clustering** (calm follows calm). | 06 |
| **Correlation / Pearson / Spearman** | Co-movement in [−1,1] / linear-only / rank-based. | Pearson is blind to curves; Spearman catches monotonic ones. Always *plot* first. | 05, 07 |
| **Mutual information (MI)** | Measures **any** dependency, even non-monotonic. | Surfaces non-linear signal Pearson misses; the fair first ranking in discovery. | 07, 08 |

## G. Inference — real or luck?

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Hypothesis (H0/H1)** | H0 = 'no effect' (skeptic's default) vs H1 = your claim. | Forces a claim you can *disprove*: H0 = 'this signal is worthless'. | 07 |
| **p-value** | Chance of data this extreme if H0 were true. | The 'is it non-zero?' gate — but beware the big-N trap. | 07 |
| **Big-N trap** | With huge samples, even trivial effects become 'significant'. | We have 400k+ rows — significance is cheap; **effect size** is what matters. | 07 |
| **Effect size (Cohen's d)** | *How big* the difference is, regardless of sample size. | Separates 'real & tradeable' from 'real but microscopic'. | 07 |
| **Train/test split (OOS)** | Choose on the past, judge on held-out future — split **by time**. | An edge must survive out-of-sample with the same sign. Never split randomly. | 07, 09, 10 |
| **Multiple-testing problem** | Test enough things and some pass by luck (~5% at p<0.05). | 41 features × 4 horizons → dozens of false positives. Fix: Bonferroni + OOS replication. | 07 |

## H. Discovery — which features matter

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Feature importance** | How much each feature improves a real model's prediction. | Catches features that matter only *in combination* (a single screen misses them). | 08 |
| **Gradient-boosted trees** | Many small decision trees that correct each other (LightGBM). | Captures non-linear, interacting effects; the discovery model. | 08 |
| **SHAP** | Game-theoretic credit for each feature's contribution to each prediction. | The robust importance ranking; VP distances + hour + DI led the real run. | 08 |
| **Multicollinearity / redundancy** | Features that move together (e.g. adjacent EMAs ~0.99). | Splits importance arbitrarily & adds noise; 41 features → ~24 effective. | 08 |
| **Regime / KMeans clustering** | Group bars into 'moods' (calm/trending/expanding). | Tests whether signal hides in specific regimes. Here every regime ≈ base rate — an honest null. | 08 |

## I. Strategy testing & validation

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Vectorized backtest** | Simulate a strategy with array math (no loops, no MT5). | The fast 'is there signal worth pursuing?' filter before the C++ engine. | 09 |
| **Signal** | A boolean rule: when (and which way) to be in the market. | e.g. `adx>25 & di_spread>0` = trend-up. | 09, 10 |
| **Transaction costs / slippage** | Spread + slippage + commission per trade. | **Uncosted backtests are fantasy** — costs routinely flip an edge negative. | 09 |
| **Expectancy / Win rate** | Avg profit per trade after costs / % of trades that profit. | Expectancy is the honest 'does it make money?'; a 40% win rate can still win big. | 09 |
| **Equity curve / Max drawdown** | Cumulative P&L / largest peak-to-trough drop. | Eyeball test (steady climb vs cliff); drawdown is what you must stomach. | 09, 10 |
| **Sensitivity: plateau vs spike** | How results move as a parameter changes. | Trust a stable **plateau**, distrust a lone **spike** (overfit luck). | 09 |
| **Walk-forward** | Repeated train→test across rolling windows. | The Phase-9 gold standard against overfitting; one split is just a starter. | 10 |
| **Monte Carlo bootstrap** | Resample trades thousands of times → a distribution of outcomes. | Luck vs structure: the real KenKem edge was 100% profitable across 5,000 resamples. | 10 |
| **Overfitting** | A 'strategy' that fits past noise and fails live. | The enemy. OOS, plateaus, costs, walk-forward, MC are all anti-overfitting tools. | 07–10 |
| **Profit Factor (PF)** | Gross profit ÷ gross loss. | The headline score; the promotion gate is ~PF 1.25 train / 1.15 OOS. | 10 |
| **Walk-forward efficiency** | OOS PF ÷ in-sample PF across re-opt folds. | ≈1.0 = no degradation on unseen data (not overfit); ≪1.0 = curve-fit. | 12 |
| **Fixed-beats-reopt** | A single locked param beats per-fold re-optimization. | The signature of a *real plateau*: a config that needs constant re-tuning is fragile. | 12 |
| **Drawdown honesty** | Quoting the worst plausible DD, not a benign window's. | The shipped '10% DD' was a lucky 4-month slice; the honest full-year figure is ~28% (MC 95th ~38%). Size for the worst. | 12 |
| **Risk of ruin** | P(equity ever falls below a floor) under random trade order. | Negligible at 1%/trade here, but the lived experience still includes 25%+ dips. | 12 |
| **Order-shuffle vs bootstrap** | Permute trades (path risk) vs resample with replacement (edge risk). | Shuffle stresses drawdown/sequence; bootstrap stresses the edge itself. | 12 |

## J. From research to production

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Four-layer architecture** | Python research → C++ core → C++ backtester → thin MQL5 EA. | Decisions never in MQL5; MT5 calls never in C++ core. Lets one strategy be unit-tested *and* shipped. | 10 |
| **Determinism** | Same ticks → same trades → same equity curve. | What makes C++ unit tests and MQL5 parity meaningful. | 10 |
| **Parity** | Byte-compatible C++ vs MQL5 output, diffed on identical ticks. | Proves the research core and the live EA produce identical signals. | 10, 11 |
| **Ground-truth ladder** | Python (toy) < C++ engine (model) < MT5 parity PASS (fact). | Confidence flows downward; each layer can lie to the one above. A backtest PF is a *claim* until MT5 reproduces it. | 11 |
| **Config-before-logic** | Diff the `.set` vs the MT5 `inputs_echo` *before* suspecting code. | One wrong input mimics a deep bug — KenKem's '50% recall' was a single `E1_MAX_CROSS_AGE` mismatch (→93%). | 11 |
| **Wilder vs SMA ATR** | MT5's `iATR` is a rolling *simple* MA of TR, not textbook Wilder. | A ~7% smoothing gap flipped ~a quarter of ATR-percentile gates; invisible alone, decisive at a boundary. | 11 |
| **Trade-level parity gate** | Greedy same-direction time-match with entry/P&L tolerances → PASS/FAIL. | Failure taxonomy: count→config, entry→logic, P&L→execution. The last gate before live. | 11 |
| **The three editions** | **MasterVP** (VP breakout) · **Monster** (VP+net-volume) · **KenKem** (trend menu). | The real optimization targets; each maps to a discovery finding. | 10 |
| **Promotion gauntlet** | costs → sensitivity → walk-forward → MC → C++ tests → MQL5 parity → demo. | A strategy is production-eligible only after *every* gate passes (`KENKEM_QUANT_OS.md` §7). | 10 |

## K. Institutional R&D and portfolio production

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Experiment registry** | Immutable record of hypothesis, data, commit, config, trials, costs, metrics, and decision. | Prevents repeating dead ideas and makes every lock auditable. | 13 |
| **Unified trade schema** | One canonical format for C++, MT5, and research trade streams. | Lets MasterVP, KenKem, XAU, BTC, and portfolio tools share the same diagnostics. | 13 |
| **Anchored Volume Profile** | VP built from a structural anchor such as session open, swing, or event. | MasterVP should test auction structure, not only rolling lookback windows. | 13 |
| **Meta-labeling** | A second model that accepts/sizes a primary signal rather than choosing direction. | Candidate for MasterVP breakout quality after the rule-based edge is proven. | 13 |
| **CPCV / PBO** | Combinatorial purged cross-validation / probability of backtest overfitting. | A stronger anti-overfit gate than one hand-picked OOS path. | 12, 13 |
| **Purging / Embargo** | Remove training samples that overlap or sit too near the test window. | Avoids leakage in serially correlated trade and label data. | 12, 13 |
| **DSR / MinTRL** | Deflated Sharpe Ratio / minimum track record length. | A searched lock is only credible if it pays the multiple-testing penalty with enough trades. | 12, 13 |
| **Flow toxicity** | Market state where aggressive/informed flow creates adverse selection. | Useful lens for failed breakouts and why raw flow filters can backfire. | 13 |
| **Tail correlation** | Correlation measured during the worst return days, not average days. | MasterVP and KenKem may look diversified until XAU chop hits both together. | 13 |
| **Component risk contribution** | Each stream's share of portfolio volatility or drawdown risk. | Prevents one EA/timeframe from secretly dominating the account. | 13 |
| **HRP** | Hierarchical Risk Parity allocation. | More stable than mean-variance for small, correlated EA trade streams. | 13 |
| **Book-level risk governor** | Account-level cap across all running EAs/charts. | Per-EA DD limits do not protect a shared account from correlated losses. | 13 |
| **Drift monitor** | Live expected-vs-realized scorecard for fills, PF, count, spread, regimes, and exits. | Defines when a released edge should be paused or reviewed. | 13 |

---

## 🔗 Free learning sources (curated, reputable)

**Start here — hands-on, free, a few hours each:**
- [**Kaggle Learn**](https://www.kaggle.com/learn) — in order: *Pandas → Data Cleaning → Feature
  Engineering → Intro to ML → Intermediate ML* (the last covers data leakage — gold for us).

**Statistics intuition (watch, don't memorize):**
- [**StatQuest with Josh Starmer**](https://www.youtube.com/c/joshstarmer) — the clearest explanations
  anywhere of p-values, t-tests, correlation, **SHAP**, gradient boosting, bootstrapping.
- [**Seeing Theory** (Brown)](https://seeing-theory.brown.edu/) — interactive visual statistics.

**The libraries you'll actually use:**
- [pandas](https://pandas.pydata.org/docs/user_guide/) · [DuckDB](https://duckdb.org/docs/) ·
  [scipy.stats](https://docs.scipy.org/doc/scipy/reference/stats.html) ·
  [statsmodels](https://www.statsmodels.org/stable/index.html) ·
  [scikit-learn](https://scikit-learn.org/stable/user_guide.html) ·
  [LightGBM](https://lightgbm.readthedocs.io/) · [SHAP](https://shap.readthedocs.io/)

**Trading terms in plain English:**
- [**Investopedia**](https://www.investopedia.com/) — spread, slippage, Sharpe, ADX, drawdown, Volume
  Profile, profit factor — look them up as you hit them.

**The quant deep-end (when ready):**
- **Book: *Advances in Financial Machine Learning*, Marcos López de Prado** — the canonical text
  (triple-barrier labeling, cross-validation pitfalls, backtest overfitting). Dense; come back to it.
- [**mlfinlab** (Hudson & Thames)](https://github.com/hudson-and-thames/mlfinlab) — open-source
  implementations of that book.

**The map of *this* project:** `docs/KENKEM_QUANT_OS.md` — the 10-phase SOP. Notebooks 00–10 are its
hand-cranked, single-symbol miniature. Read §7 to see where the rigor goes next.
