---
name: ds-study-track
description: ds-study/ learning sandbox — keep it in sync as the real research progresses
metadata: 
  node_type: memory
  type: project
  originSessionId: ea403f37-60f3-4281-9a3a-951b1f2b1784
---

The user is learning data science by following the quant development. There's a dedicated
read-only sandbox at `ds-study/` (outside the pipeline; never writes to `data/`):
`notebooks/01_first_look` (EDA basics) → `02_clean_and_characterize` (quality, stationarity,
fat tails, ACF) → `03_correlation_and_hypothesis_testing` (Pearson/Spearman/MI, p-values,
t-tests, train/test) → `04_quick_backtest` (pure-Python vectorized backtest WITH real spread
costs). Plus `GLOSSARY.md` (terms + free links: Kaggle Learn, StatQuest) and `scratch/` (gitignored).
Notebooks load real BTCUSD M3 features/labels/bars and are executed with outputs pre-baked.

**Why:** user explicitly wants to build real DS intuition, not run code blindly — and asked me to
keep adding notebooks that mirror each development step.

**How to apply:** when a substantive research step finishes, offer to drop a matching `0N_*.ipynb`
into ds-study/ that reproduces it by hand at a teaching altitude. Keep examples honest (show
negative results — the trend-continuation example deliberately fails after costs). Related:
[[real-target-kenkem-strategies]], [[discovery-findings]], [[workflow-commit-and-plan]].
