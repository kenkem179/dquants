# 📖 Glossary & key concepts — for the aspiring quant data scientist

Don't run the notebooks blindly. Each term below has: **what it means** (plain English),
**why it matters here** (this project, not a textbook), and **where you meet it** (which
notebook). Curated free learning links are at the bottom.

Legend: `NB01`=first look · `NB02`=clean+characterize · `NB03`=correlation+hypothesis · `NB04`=backtest

---

## A. Data handling & quality

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **DataFrame** | A table in code (rows × named columns), from the pandas library. | Every dataset you touch is a DataFrame. | NB01 |
| **Parquet** | A compressed, columnar file format. Reads only the columns you ask for. | Our bars/features/labels are Parquet; loads in milliseconds vs minutes for CSV. | NB01 |
| **Missing value (NaN)** | An absent cell. From warm-up periods, gaps, or bad data. | Indicators (EMA, ADX) are NaN until they have enough history. | NB02 |
| **Lookahead / data leakage** | Letting information from the future sneak into a decision at time `t`. | The #1 way to fake an edge. Never forward-fill features. *Career-ending bug.* | NB02, NB03 |
| **Stationarity** | A series whose statistical properties (mean, variance) don't drift over time. | **Prices are non-stationary, returns are stationary** — this is *why* quants model returns. | NB02 |
| **ADF test** | Augmented Dickey-Fuller: a hypothesis test for stationarity. | We prove price ≠ stationary, returns = stationary, instead of assuming it. | NB02 |
| **Winsorize / clip** | Cap extreme values at a percentile to tame outliers. | Useful before linear models; *avoid* when the extreme bar IS the signal. | NB02 |

## B. Describing one variable (univariate)

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Mean / Median** | Average vs middle value. | If they diverge, the data is skewed (extreme values pull the mean). | NB01 |
| **Standard deviation (std)** | Typical distance of values from the mean — i.e. spread. | The denominator of almost every risk/signal metric (Sharpe, z-score, t-stat). | NB01 |
| **Histogram** | Bar chart of how often values fall in each bucket → the *shape* of data. | First look at any column's distribution. | NB01 |
| **Outlier** | A value far from the rest (flagged by z-score >3 or the IQR rule). | In trading the outliers are often the *interesting* bars — notice, don't auto-delete. | NB01 |
| **IQR (interquartile range)** | Q3 − Q1, the middle 50% of data; the box in a boxplot. | Robust outlier fence that doesn't assume a normal distribution. | NB01 |
| **Skew** | Asymmetry of a distribution. | Returns are slightly skewed; many indicators are heavily skewed. | NB02 |
| **Kurtosis / fat tails** | How heavy the tails are vs a bell curve (normal = 0). | Financial returns have **fat tails** — extreme moves far more common than 'normal' predicts. Underestimate this and risk models blow up. | NB02 |
| **QQ-plot** | Plots your data's quantiles against a normal's. Points leaving the line = fat tails. | Visual proof returns aren't normal. | NB02 |
| **Autocorrelation (ACF)** | Correlation of a series with its own past. | Returns ≈ 0 (markets efficient); **\|returns\| > 0 = volatility clustering** (calm follows calm). | NB02 |

## C. Relationships between variables (bivariate)

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Correlation** | A number in [−1, +1] for how two things move together. | The core discovery tool: which features move with forward returns? | NB01, NB03 |
| **Pearson** | Correlation that only sees **straight-line** relationships. | Default, but **blind to curves** — can read ~0 on a strong U-shaped link. | NB03 |
| **Spearman** | Correlation of **ranks**; catches any monotonic (curved-but-consistent) link. | Cross-check Pearson; more robust to outliers. | NB03 |
| **Mutual information (MI)** | Measures **any** dependency, even non-monotonic. 0 only if truly independent. | Surfaces non-linear signal Pearson misses; used in the project's Phase-5 discovery. | NB03 |
| **Correlation ≠ causation** | Moving together doesn't mean one causes the other. | Spurious correlations are everywhere with 41 features × 4 horizons. | NB01, NB03 |
| **Scatter plot** | One dot per row, feature on X, target on Y. | *Always plot before trusting a correlation number.* | NB01 |

## D. Inference — is it real, or luck?

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Hypothesis (H0 / H1)** | H0 = 'no effect' (skeptic's default); H1 = the effect you claim. | Forces a claim you can *disprove*. We write H0 = 'signal is worthless'. | NB03 |
| **p-value** | Probability of seeing data this extreme if H0 were true. p<0.05 → 'significant'. | The gate for 'is this non-zero?' — but see the big-N trap. | NB03 |
| **The big-N trap** | With huge samples, *even trivial* effects become 'significant'. | We have 400k+ rows — significance is cheap; **effect size** is what matters. | NB03 |
| **Effect size (Cohen's d)** | *How big* the difference is, independent of sample size. | Distinguishes 'real and tradeable' from 'real but microscopic'. | NB03 |
| **t-test / t-stat** | Tests whether a mean differs from 0 (or two means differ). | Is the signal group's mean return reliably > 0? Reused as the backtest's t-stat. | NB03, NB04 |
| **Bootstrap** | Resample the data many times to get a confidence interval. | How stable is a correlation/edge across resamples? | NB03 |
| **Train / test split (out-of-sample)** | Fit/choose on past data, judge on *held-out future* data. | An edge MUST survive OOS with the same sign. Split **by time**, never randomly. | NB03, NB04 |
| **Multiple-testing problem** | Test enough things and some pass by pure luck (~5% at p<0.05). | Testing 41 features → dozens of false positives. Fix: Bonferroni + OOS replication. | NB03 |

## E. Strategy testing

| Term | What it means | Why it matters here | Where |
|---|---|---|---|
| **Vectorized backtest** | Simulate a strategy with array math (no loops, no MT5). | The fast 'is there signal worth pursuing?' filter before the C++ engine. | NB04 |
| **Signal** | A boolean rule: when to be in the market and which direction. | e.g. `adx>25 & di_plus>di_minus` = trend-up. | NB04 |
| **Transaction costs** | Spread + slippage + commission paid per trade. | **Uncosted backtests are fantasy.** Costs ate ~20% of a typical move here and flipped the edge negative. | NB04 |
| **Spread** | Ask − Bid: the instant cost of a round trip. | Pulled from real bar data; the silent killer of scalping strategies. | NB04 |
| **Slippage** | Getting a worse fill price than expected. | Modeled as extra bps; sensitivity to it is a survival test. | NB04 |
| **Expectancy** | Average profit per trade after costs. | The single honest 'does this make money?' number. | NB04 |
| **Win rate** | % of trades that profit. | Seductive but incomplete — a 40% win rate can still be very profitable. | NB04 |
| **Equity curve** | Cumulative P&L over time. | Eyeball test: steady climb (good) vs cliff (regime-dependent / overfit). | NB04 |
| **Sharpe ratio** | Return per unit of risk (mean / std of returns). | The standard 'quality of returns' score; higher = smoother gains. | NB04 |
| **Max drawdown** | Largest peak-to-trough drop in the equity curve. | What you'd actually have to stomach; sizing/risk limits exist to bound this. | NB04 |
| **Sensitivity / plateau vs spike** | How results change as a parameter moves. | Trust a **plateau** (stable neighbourhood), distrust a lone **spike** (overfit luck). | NB04 |
| **Walk-forward** | Repeated train→test across rolling windows (not one split). | The project's Phase-9 gold standard; one split is just a starter. | NB04 |
| **Overfitting** | A 'strategy' that fits past noise and fails live. | The enemy. Every technique above (OOS, plateaus, costs) is an anti-overfitting tool. | NB03, NB04 |

---

## 🔗 Free learning sources (curated, reputable)

**Start here — hands-on, free, a few hours each:**
- [**Kaggle Learn**](https://www.kaggle.com/learn) — do these in order: *Pandas → Data Cleaning →
  Feature Engineering → Intro to ML → Intermediate ML* (the last covers data leakage, which is
  gold for us). Each is a short notebook course with exercises.

**Statistics intuition (watch, don't memorize):**
- [**StatQuest with Josh Starmer** (YouTube)](https://www.youtube.com/c/joshstarmer) — the clearest
  explanations anywhere of p-values, t-tests, correlation, distributions, bootstrapping.
- [**Seeing Theory** (Brown Univ.)](https://seeing-theory.brown.edu/) — interactive visual stats.

**The library docs you'll actually use:**
- [pandas](https://pandas.pydata.org/docs/user_guide/) · [scipy.stats](https://docs.scipy.org/doc/scipy/reference/stats.html)
  · [statsmodels](https://www.statsmodels.org/stable/index.html) · [scikit-learn](https://scikit-learn.org/stable/user_guide.html)
  · [DuckDB](https://duckdb.org/docs/)

**Trading terms in plain English:**
- [**Investopedia**](https://www.investopedia.com/) — look up spread, slippage, Sharpe ratio, ADX,
  drawdown, expectancy as you hit them.

**When you're ready for the real quant deep-end:**
- **Book: *Advances in Financial Machine Learning*, Marcos López de Prado** — the canonical text on
  ML for trading (labeling, cross-validation pitfalls, backtest overfitting). Dense; come back to it.
- [**Hudson & Thames / mlfinlab**](https://github.com/hudson-and-thames/mlfinlab) — open-source
  implementations of that book's techniques.

**The map of *this* project:** `docs/KENKEM_QUANT_OS.md` — our 10-phase SOP. Notebooks 01–04 are a
hand-cranked, single-symbol miniature of Phases 2→7. Read §7 to see where the rigor goes next.
