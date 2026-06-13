# ds-study — your data-science sandbox 🧪

A **read-only playground** for learning data science by following along with the KenKem
quant research. Nothing in here is part of the production pipeline — break things freely.

## The one rule

**Never write into `data/`.** Load the Parquet files my pipeline produces, explore them,
plot them, but if you want to save something, put it in `ds-study/scratch/` (gitignored).
This guarantees your experiments can never corrupt the research pipeline.

## Setup (one time)

```bash
conda activate kenkem      # the project's Python 3.11 env — NOT system python3
jupyter lab                # opens in browser; navigate to ds-study/notebooks/
```

If `jupyter` is missing: `pip install jupyterlab seaborn` inside the `kenkem` env.

## What's here

```
ds-study/
  notebooks/
    01_first_look.ipynb                      ← START HERE. Load, mean/std/outliers, correlation, plots.
    02_clean_and_characterize.ipynb          ← Data quality, cleaning, stationarity, fat tails, autocorrelation.
    03_correlation_and_hypothesis_testing.ipynb ← Pearson vs Spearman vs MI; p-values; t-tests; out-of-sample.
    04_quick_backtest.ipynb                  ← Pure-Python vectorized backtest WITH real costs + equity curve.
  GLOSSARY.md             ← every term defined + why it matters here + free learning links. Keep it open.
  scratch/                ← dump your own experiments + saved files here (gitignored)
  README.md
```

The four notebooks are a hand-cranked miniature of the project's real SOP (Phases 2→7): explore →
clean & characterize → test a hypothesis → quick-backtest. Each runs standalone and top-to-bottom.

## How this maps to the real research

The notebook loads the *same* files my discovery analysis used:

| File                                         | What it is                              |
|----------------------------------------------|-----------------------------------------|
| `data/processed/bars_btcusd_M3_2025.parquet` | OHLC price bars (3-minute candles)      |
| `data/features/features_btcusd_M3.parquet`   | 41 indicator features per bar           |
| `data/labels/labels_btcusd_M3.parquet`       | forward returns (the thing we predict)  |

The core question of this whole project, in one sentence:
**which feature columns, at bar `t`, actually predict the `fwd_ret_*` columns?**
That's what you'll start poking at in cell-block 7 of the notebook.

## Learning path (suggested order, baby steps)

1. Skim **`GLOSSARY.md`** first — even 5 minutes orients you. Keep it open in a tab while you work.
2. Run `01` → `02` → `03` → `04` top to bottom, once each — just watch them work. (Outputs are
   pre-baked, so you can read them before running anything.)
3. Re-run each changing ONE thing at a time (a different feature, threshold, year, or cost).
4. Do the "🎯 Your turn" exercises at the bottom of each notebook.
5. When a result surprises you, ask me *"why did X come out that way?"* — that's the loop.

### ⚠️ Read the results honestly
The example hypothesis in `03`/`04` (trend-continuation) **does not survive** — it's barely positive
in-sample, flips sign out-of-sample, and goes net-negative after costs. That's **intentional and
real**, not a broken notebook. The most valuable lesson in quant is that *most signals are noise and
costs are brutal*. Finding the rare edge that survives all four gates is the whole job.
