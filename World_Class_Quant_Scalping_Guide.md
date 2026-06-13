# World-Class Quant Scalping Research Manual

## Objective
Build a fully data-driven quantitative research pipeline for BTCUSD and XAUUSD scalping on M1/M3 using real tick data.

---

# Table of Contents

1. Quant Mindset
2. Hardware & Software Setup
3. Data Architecture
4. Tick Data Collection
5. Data Cleaning
6. Bar Construction
7. Feature Engineering
8. Market Regime Detection
9. Forward Return Labeling
10. Exploratory Data Analysis
11. Correlation Analysis
12. SHAP Analysis
13. Pattern Discovery
14. Hypothesis Testing
15. Vectorized Backtesting
16. Execution Simulation
17. Parameter Sensitivity Analysis
18. Bayesian Optimization
19. Walk-Forward Validation
20. Monte Carlo Validation
21. Portfolio Construction
22. Visualization Dashboard
23. ML Research Pipeline
24. MT5 Deployment Workflow
25. Recommended Folder Structure
26. Recommended Libraries
27. Daily Quant Research Routine
28. Roadmap to Top 1% Quant Level

---

# 1. Quant Mindset

Never begin with indicators.

Research flow:

Tick Data
→ Features
→ Forward Returns
→ Statistical Edge
→ Validation
→ Strategy
→ Deployment

Avoid:
- Curve fitting
- Blind optimization
- Indicator worship

Focus on:
- Statistical significance
- Repeatability
- Regime robustness

---

# 2. Hardware & Software

Primary Machine:
- MacBook Pro M5

Install:

- Homebrew
- Miniforge
- Python 3.11
- JupyterLab
- Git
- VS Code

Core libraries:

pip install

- polars
- duckdb
- pyarrow
- numpy
- scipy
- statsmodels
- scikit-learn
- lightgbm
- shap
- optuna
- vectorbt
- plotly
- matplotlib
- ta
- pandas

---

# 3. Data Architecture

Raw Tick Data
→ Parquet
→ M1/M3 Bars
→ Features
→ Labels
→ Research Datasets

Use:

Parquet + DuckDB

Avoid:

Large CSV processing during research.

---

# 4. Tick Data Collection

Sources:

- Exness Export
- MT5 Export
- Broker Tick Archives

Store:

timestamp
bid
ask
spread
volume

Create:

mid = (bid + ask)/2

---

# 5. Tick Cleaning

Remove:

- duplicates
- impossible prices
- negative spread
- maintenance spikes
- bad ticks

Validate:

- spread distribution
- missing periods
- session coverage

---

# 6. Bar Construction

Generate:

M1
M3

Store:

open
high
low
close
spread_mean
spread_max
tick_count

---

# 7. Feature Engineering

## Trend

EMA

12
25
50
75
100
200

Features:

- EMA slope
- EMA distance
- EMA compression

## Momentum

RSI

7
14
21

Features:

- RSI value
- RSI slope
- RSI acceleration

## DMI

ADX
DI+
DI-

Features:

- DI spread
- ADX trend
- ADX acceleration

## Volatility

ATR

Features:

- ATR
- ATR slope
- ATR percentile

## Structure

Volume Profile

Features:

- Distance to POC
- Distance to VAH
- Distance to VAL

## Ichimoku

Features:

- Distance to Tenkan
- Distance to Kijun
- Cloud thickness

## Time

Features:

- Session
- Hour
- Day of week

---

# 8. Market Regime Detection

Cluster market conditions.

Use:

- HDBSCAN
- KMeans

Typical regimes:

1. Strong Trend
2. Weak Trend
3. Compression
4. Expansion
5. Reversal

Research each separately.

---

# 9. Forward Return Labeling

Create labels:

future_return_5
future_return_10
future_return_20
future_return_60

Example:

close(t+20) - close(t)

This becomes your ground truth.

---

# 10. Exploratory Data Analysis

Visualize:

- Distribution
- Histograms
- Heatmaps
- Session performance

Questions:

Which hours work best?
Which volatility regimes work best?

---

# 11. Correlation Analysis

Measure:

Feature
vs
Forward Return

Examples:

RSI
ADX
ATR
POC Distance

Remove redundant features.

---

# 12. SHAP Analysis

Train:

LightGBM

Then:

SHAP

Questions:

Which variables actually drive profits?

Many traders discover:

Volume Profile > RSI

---

# 13. Pattern Discovery

Use:

HDBSCAN

Find recurring profitable structures.

Example:

High ADX
+ Rising ATR
+ Above POC

---

# 14. Hypothesis Testing

Example:

Long if:

ADX > 25
AND
Price > POC

Measure:

- Win rate
- Profit factor
- Expectancy

---

# 15. Backtesting

Use:

vectorbt

Advantages:

- Fast
- Reproducible
- Python native

Track:

- CAGR
- Max DD
- Sharpe
- Sortino
- Profit Factor

---

# 16. Execution Simulation

Critical for scalping.

Include:

- Spread
- Slippage
- Commission
- Latency

Otherwise results are fantasy.

---

# 17. Parameter Sensitivity

Create heatmaps.

Examples:

ADX Threshold
vs
ATR Threshold

Look for:

Stable plateaus

Avoid:

Tiny peaks

---

# 18. Bayesian Optimization

Use:

Optuna

Better than brute force.

Optimize:

- ADX threshold
- RSI threshold
- ATR multiplier

---

# 19. Walk-Forward Validation

Train:
2023

Validate:
2024

Test:
2025

Never mix periods.

---

# 20. Monte Carlo Validation

Randomize:

- trade order
- slippage
- execution

Estimate robustness.

---

# 21. Portfolio Construction

Separate:

BTCUSD
XAUUSD

Evaluate:

- Correlation
- Diversification

Avoid relying on one market.

---

# 22. Visualization Dashboard

Build:

Plotly Dash
or
Streamlit

Visuals:

- Equity curve
- Drawdown
- Heatmaps
- SHAP importance
- Regime performance

---

# 23. ML Research Pipeline

Models:

- LightGBM
- XGBoost
- Random Forest

Avoid deep learning initially.

Focus on explainability.

---

# 24. MT5 Deployment

Research in Python.

Deploy only proven ideas.

Pipeline:

Python Research
→ MT5 Indicator
→ MT5 EA
→ Forward Test
→ Production

---

# 25. Folder Structure

data/
raw/
processed/

features/
labels/

research/

backtests/

reports/

---

# 26. Recommended Libraries

Data:
- Polars
- DuckDB

Research:
- NumPy
- SciPy

ML:
- LightGBM
- SHAP

Backtesting:
- vectorbt

Optimization:
- Optuna

Visualization:
- Plotly

---

# 27. Daily Quant Routine

Morning

- Data integrity check
- Research review

Afternoon

- Feature experiments
- Hypothesis tests

Evening

- Walk-forward validation
- Journal findings

Track every experiment.

---

# 28. Roadmap to Top 1%

Level 1
Retail Trader

Level 2
Systematic Trader

Level 3
Quant Researcher

Level 4
Strategy Portfolio Manager

Level 5
World-Class Quant

Characteristics:

- Research first
- Evidence first
- Statistics first
- Automation first
- Continuous validation

The edge comes from the research process, not from any single indicator.
