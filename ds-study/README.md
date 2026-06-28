# ds-study — from software engineer to quant, one notebook at a time 🧪→📈

A **hands-on, read-only curriculum** that walks the *entire* journey a quant data scientist actually
takes — from 24 GB of raw broker text to three validated trading strategies — using this project's
**real BTCUSD / XAUUSD** data. It exists so a strong software engineer with **no data-science
background** can rebuild the full thinking process behind KenKem, MasterVP and Monster, and understand
*why* every decision was made.

Every notebook is **already executed** against the real data, so you can read the outputs before you
run a thing. Each one opens with a **goal banner** (⏱️ time · 🎯 goal · 🔑 the one thing to remember).

---

## The one rule 🚫

**Never write into `data/`.** Load the Parquet files the pipeline produces, explore them, plot them —
but if you want to save something, put it in `ds-study/scratch/` (gitignored). Your experiments can
never corrupt the research pipeline.

## Setup (one time)

```bash
source ~/miniforge3/etc/profile.d/conda.sh && conda activate kenkem   # Python 3.11 env (NOT system python3)
jupyter lab                                                           # navigate to ds-study/notebooks/
```

If a library is missing inside `kenkem`: `pip install jupyterlab seaborn lightgbm shap`.

---

## The curriculum (00 → 10) — mirrors the project's 10-phase SOP

Each notebook is the hand-cranked, *understand-it-yourself* version of one production phase. They run
**standalone** and **top-to-bottom**, and each consumes the previous one's output.

| # | Notebook | SOP phase | What you learn | ⏱️ |
|---|----------|-----------|----------------|----|
| **00** | `raw_tick_data` | 1 · Import | Tick data, the big-data problem, **streaming with DuckDB**, Parquet | 15m |
| **01** | `validate_and_clean` | 2 · Validate | Data-quality checklist, **drop vs keep+flag**, spread-realism trap, leakage | 20m |
| **02** | `ticks_to_bars` | 3a · Bars | **Resampling** ticks → OHLC candles, event-time/sparse bars, reconciliation | 20m |
| **03** | `feature_engineering` | 3b · Features | **The 41 features**: causal + normalized; EMA/RSI/ATR/ADX/**Volume Profile**/Ichimoku | 30m |
| **04** | `labeling` | 4 · Labels | Forward returns, the **triple-barrier** method, class balance | 25m |
| **05** | `first_look_eda` | 5 · EDA | Distributions, outliers, correlation — *look before you model* | 25m |
| **06** | `characterize` | 5 · Characterize | **Stationarity**, fat tails, autocorrelation, volatility clustering | 25m |
| **07** | `correlation_hypothesis` | 6 · Hypothesis | Pearson vs Spearman vs **MI**, p-values, **effect size**, out-of-sample | 30m |
| **08** | `discovery` | 5 · Discovery | **Feature ranking** (MI + SHAP), redundancy, **regime clustering** | 35m |
| **09** | `quick_backtest` | 7 · Backtest | **Costed** vectorized backtest, equity curve, mini sensitivity sweep | 30m |
| **10** | `research_to_strategies` | 6–10 · Promote | **Walk-forward**, **Monte Carlo**, the 3 editions, the promotion gauntlet | 35m |

### 🛡️ The reliability half (11 → 12) — how a *found* edge becomes a *trusted* one

Notebooks 00–10 teach you to **find** an edge. These two teach the harder, less-glamorous half that
actually made KK-MasterVP shippable: proving the edge is **real** (matches the broker trade-for-trade)
and **honest** (survives out-of-sample and reports the drawdown of the *worst* plausible path, not a
lucky window). Both run on the project's **real** parity + walk-forward artifacts.

| # | Notebook | SOP phase | What you learn | ⏱️ |
|---|----------|-----------|----------------|----|
| **11** | `parity_ground_truth` | 7 · MQL5 parity | **Diff config before logic**, the Wilder-vs-SMA ATR bug, trade-for-trade **PASS/FAIL** matching | 30m |
| **12** | `overfitting_and_drawdown_honesty` | 8–9 · WF/MC | **Peak vs plateau**, walk-forward & Monte-Carlo on the real locked stream, **drawdown honesty** | 35m |
| **13** | `institutional_scalping_rd_playbook` | program design | MasterVP/KenKem R&D gates, glossary, regime/cost/portfolio thinking, release scorecard | 45m |

> 📖 Keep **`GLOSSARY.md`** open in a tab — every term above is defined there with *why it matters here*.

---

## 🏃 Don't have time for all 11? Three honest paths

You said it yourself: you don't have unlimited hours. Pick the path that matches your goal **today**.

- **🟢 The 90-minute core (the irreducible quant loop).** `00 → 03 → 04 → 09`.
  Where data comes from → how features are built → what we predict → does it make money after costs.
  *If you only ever read four, read these.*

- **🔵 The "why does the strategy look like that?" path.** `03 → 08 → 10`.
  The features → which ones actually matter → how that became MasterVP/Monster/KenKem. Best if you care
  more about the *strategies* than the statistics.

- **🛡️ The "why should I trust this number?" path.** `09 → 11 → 12`. A backtest result → proving it
  matches the broker → proving it isn't overfit and its drawdown is honest. The reliability mindset in 90 min.

- **🟣 The full deep-dive (everything, in order).** `00 → 12`. The complete craft. Do one or two a day;
  re-run each changing **one** thing; then do the **🎯 Your turn** exercises.

> ⚡ **The 10-minute skim.** Open every notebook and read **only** its goal banner + the bold
> "Concept" boxes. You'll have the whole map in your head before deciding where to dig.

---

## How to actually learn this (not just read it)

1. **Read the banner + outputs first.** They're pre-baked — you can absorb a notebook before running it.
2. **Run it top-to-bottom once.** Just watch it work.
3. **Change ONE thing** and re-run — a different feature, threshold, year, or symbol.
4. **Do the 🎯 Your turn** exercises (many ask you to repeat the step on **XAUUSD**, whose pipeline is
   only half-built — so you'd be doing *real, unblazed* work, not a toy exercise).
5. **When a result surprises you, ask** *"why did X come out that way?"* — that's the whole game.

### ⚠️ Read the results honestly
The example signals in `07`/`09`/`10` are **deliberately weak** — they barely clear zero in-sample and
fade out-of-sample after costs. That is **intentional and real**, not a broken notebook. The single
most valuable lesson in quant is that *most signals are noise and costs are brutal*; finding the rare
edge that survives every gate (costs → sensitivity → walk-forward → Monte Carlo → C++ → MQL5 → demo) is
the entire job. Notebooks 08 and 10 show what the survivors look like.

---

## How this maps to the real research

The notebooks load the *same* files the project's discovery and strategy work used:

| File | What it is | Built in |
|------|------------|----------|
| `data/btcusd/BTCUSD_ticks_mt5_*.csv` | raw MT5 tick exports (tab-separated, ~24 GB) | — |
| `data/processed/ticks_*_clean.parquet` | validated tick stream | NB 00–01 |
| `data/processed/bars_*_M{1,3}_*.parquet` | OHLC price bars | NB 02 |
| `data/features/features_*_M3.parquet` | the 41 indicator features per bar | NB 03 |
| `data/labels/labels_*_M3.parquet` | forward returns + triple-barrier outcome | NB 04 |
| `research/discovery/*` | the real Phase-5 feature rankings & regimes | NB 08 |
| `research/optimization/best_*.set`, `*RESULTS*.md` | the tuned strategies & scorecard | NB 10 |
| `research/kenkem_parity/*.set`, `bars_xauusd_M1_kk.csv` | real configs + bars for the parity/ATR demos | NB 11 |
| `research/mastervp_parity/_wf_fullrun.csv`, `WF_MC_FINDINGS.md` | the real locked KK-MasterVP trade stream + WF/MC report | NB 12 |

**The whole project in one sentence:** *which feature columns, at bar `t`, actually predict the future
— and does trading on them survive costs and out-of-sample testing?* You start poking at that in NB 08,
and answer it for real in NB 10.

> The map of *this* project: `docs/KENKEM_QUANT_OS.md` (the 10-phase SOP). Notebooks 00–10 are its
> hand-cranked miniature on a single symbol. After this curriculum, §7 will read like a list of things
> you've *done*.

```
ds-study/
  notebooks/00 … 10        ← the curriculum: find an edge (start at 00, or pick a path above)
  notebooks/11 … 12        ← the reliability half: prove it's real (parity) & honest (overfitting/DD)
  GLOSSARY.md              ← every term defined + why it matters here + free learning links
  scratch/                 ← your experiments + saved files (gitignored — break things freely)
  README.md
```
