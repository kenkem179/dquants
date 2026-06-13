# KenKem Quant OS — Master Implementation Plan

> Single source of truth, merged from `initial-playbook` and `World_Class_Quant_Scalping_Guide.md`.
> Goal: find profitable **XAUUSD / BTCUSD** edges on **M1/M3** using real tick data, validate them
> scientifically, and deploy only proven strategies to MT5 — **without** trapping research inside the
> MT5 Strategy Tester.

---

## 0. North Star

Research flow (never start from indicators):

```
Tick Data → Features → Forward Returns → Statistical Edge → Validation → Strategy → Deployment
```

The edge comes from the **research process**, not any single indicator. Optimize for statistical
significance, repeatability, and regime robustness. Avoid curve-fitting, blind optimization, and
indicator worship.

## 1. The Four-Layer Architecture

This is the core design (from `initial-playbook`). Each layer has a hard boundary — that boundary is
what makes the C++ → MQL5 conversion near 1:1.

```
┌─────────────────────────┐
│ Layer 1: Python Research │  pipeline/  research/   → DuckDB + Parquet, features, hypotheses
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│ Layer 2: C++ Strategy Core│  cpp_core/  → PURE LOGIC. No MT5 APIs, no broker, no OrderSend.
└───────────┬─────────────┘
            ├──────────► Layer 3: C++ Tick Backtester  (cpp_core/backtester/) — the TRUE tester
            └──────────► Layer 4: MQL5 Adapter          (mql5/) — thin OnTick() wrapper
```

**Why this split:** `EMA()`, `ATR()`, `LongSignal()`, `CalculateSL()` translate ~1:1 from C++ to MQL5.
Only `OrderSend()`, `PositionSelect()`, `CopyRates()`, `iATR()` are MT5-specific and live in Layer 4.
Keep all decision logic in Layer 2 so the same code is tested headlessly (Layer 3) and runs in MT5 (Layer 4).

MT5 Strategy Tester is the **final sanity check only**, never the research environment.

## 2. Repository Layout

```
data/
  btcusd/             # RAW MT5 tick exports (tab-separated CSV, ~12GB) — gitignored, leave in place
  raw/                # other raw drops (XAUUSD to be added)
  processed/          # cleaned ticks + M1/M3 bars as Parquet
  features/           # features.parquet
  labels/             # forward-return labels
pipeline/             # Layer 1 Python: data load, clean, bars, features, labels
research/
  notebooks/          # JupyterLab EDA
  discovery/          # correlation / MI / SHAP / clustering reports
  hypotheses/         # generated hypotheses + test results
backtests/results/    # equity curves, trade logs, metrics
reports/              # Plotly/Streamlit dashboards (HTML)
cpp_core/
  include/ src/       # Strategy, PositionManager, RiskManager, ExecutionSimulator, TickEngine
  backtester/         # headless tick backtest driver
  tests/              # unit tests (deterministic)
mql5/
  experts/            # thin EA adapters
  include/            # shared mqh wrappers
scripts/              # setup_env.sh and ops scripts
docs/                 # this plan + design notes
```

## 3. Data Contract (MT5 tick export)

Raw files (`data/btcusd/BTCUSD_ticks_mt5_<year>.csv`) are **tab-separated** with header:

```
<DATE>	<TIME>	<BID>	<ASK>	<LAST>	<VOLUME>	<FLAGS>
2024.01.01	00:00:00.036	42250.77	42273.01	0.00	0	6
```

- `DATE` = `YYYY.MM.DD`, `TIME` = `HH:MM:SS.mmm` (millisecond ticks).
- `LAST` and `VOLUME` are typically `0` for FX/CFD feeds — **do not rely on tick volume**; use tick *count* per bar instead.
- Derive `mid = (bid + ask) / 2` and `spread = ask - bid`.
- Files are large (2025 ≈ 7.2GB / 148M ticks). **Never load with pandas `read_csv`** — stream via DuckDB / Polars `scan_csv` and write Parquet once.

## 4. The 10-Phase SOP

Each phase has a matching project skill (see CLAUDE.md → "Project Skills"). Run them in order; each
phase's output is the next phase's input.

| # | Phase | Skill | Input | Output | Acceptance |
|---|-------|-------|-------|--------|------------|
| 1 | Import Data | `/quant-import-data` | raw CSV | `data/processed/ticks_*.parquet` | row counts match, no parse errors |
| 2 | Validate Data | `/quant-validate-data` | ticks parquet | validation report | no dup ts, no neg spread, session coverage OK |
| 3 | Build Bars + Features | `/quant-build-features` | ticks parquet | `data/processed/bars_*.parquet`, `data/features/features.parquet` | features non-null, no lookahead |
| 4 | Forward-Return Labels | (part of build-features) | bars/features | `data/labels/labels.parquet` | labels align to bar t, computed from t+k |
| 5 | Discovery | `/quant-discovery` | features+labels | correlation/MI/SHAP/cluster report | top drivers ranked, redundancy flagged |
| 6 | Hypotheses | `/quant-hypothesis` | discovery report | `research/hypotheses/*.md` | each has rule, expectancy, sample size |
| 7 | Backtest | `/quant-backtest` | hypothesis + bars | equity curve, trade log, metrics | costs modeled (spread/slip/commission/latency) |
| 8 | Sensitivity | `/quant-sensitivity` | strategy params | parameter heatmaps | stable plateau, not a single peak |
| 9 | Walk-Forward + MC | `/quant-walkforward` | strategy | WF + Monte Carlo report | OOS holds, no period mixing |
| 10 | Promote to MT5 | `/quant-promote-mt5` | C++ strategy core | MQL5 EA + forward-test plan | C++ tests pass, EA mirrors core logic |

### Per-phase detail

**Phase 1 — Import.** Stream tab-separated CSV → typed Parquet (partition by year/month). Parse
`DATE`+`TIME` into a single UTC timestamp. Add `mid`, `spread`. Use DuckDB `read_csv_auto` or Polars
`scan_csv(separator='\t')`.

**Phase 2 — Validate.** Drop duplicate timestamps, impossible prices, negative spread, maintenance
spikes. Check spread distribution, missing periods, session coverage. Emit a report — bad data is the
#1 source of fake edges.

**Phase 3 — Bars + Features.** Build M1/M3 OHLC + `spread_mean/spread_max/tick_count`. Then features:
EMA(12/25/50/75/100/200) slope/distance/compression; RSI(7/14/21) value/slope/accel; ADX/DI+/DI-
spread; ATR value/slope/**percentile**; Volume-Profile distance to POC/VAH/VAL; Ichimoku distance to
Tenkan/Kijun + cloud thickness; session/hour/day-of-week. **No lookahead** — every feature at bar `t`
uses only data ≤ `t`.

**Phase 4 — Labels.** `future_return_{5,10,20,60}` = `close(t+k) - close(t)`. Also the more useful
`hit_tp_before_sl` (triple-barrier style) — this is the real ground truth for scalping.

**Phase 5 — Discovery.** Correlation + Mutual Information of each feature vs forward return; train
LightGBM then **SHAP** for true drivers; HDBSCAN/KMeans for regimes (Strong Trend, Weak Trend,
Compression, Expansion, Reversal) — research each regime separately. Remove redundant features.

**Phase 6 — Hypotheses.** Turn discovery into explicit rules, e.g. *Long if ADX>23 AND ATR_pct>70 AND
price>POC*. Each hypothesis records win rate, profit factor, expectancy, sample size.

**Phase 7 — Backtest.** Vectorized (`vectorbt`) for fast screening; then the **C++ TickEngine** for
truth on real ticks (2019→2025). Always model spread, slippage, commission, latency — otherwise
results are fantasy. Track CAGR, Max DD, Sharpe, Sortino, Profit Factor.

**Phase 8 — Sensitivity.** Heatmaps over parameter pairs (e.g. ADX threshold × ATR threshold). Accept
only **stable plateaus**; reject lone peaks (curve-fit).

**Phase 9 — Walk-Forward + Monte Carlo.** Rolling train(2y)/validate(6m)/test(6m), never mixing
periods. Monte Carlo: randomize trade order / slippage / execution to estimate robustness.

**Phase 10 — Promote.** Implement the validated logic as a `Strategy` subclass in `cpp_core/`, prove it
with deterministic unit tests + the tick backtester, then hand-port the signal/SL/TP functions into a
thin MQL5 EA (`OnTick → Strategy.Update → if LongSignal OrderSend`). Forward-test on a demo/VPS before
production.

## 5. C++ Strategy Core — class skeleton (Layer 2/3)

```cpp
class Strategy           { public: bool LongSignal(); bool ShortSignal();
                                   double CalculateSL(); double CalculateTP(); };
class PositionManager    { /* open/close/track positions */ };
class RiskManager        { /* sizing, max DD, exposure limits */ };
class ExecutionSimulator { /* spread, slippage, commission, latency */ };
class TickEngine         { /* Tick → Strategy → PositionManager → Equity Curve */ };
```

Rules: C++20, header-light, **deterministic** (same ticks → same trades → same equity), zero MT5/broker
symbols in Layer 2. The backtester replays ticks event-driven and is fully headless + unit-tested.

## 6. AI Research Team

- **Claude Code** = Research Manager / orchestrator (this repo).
- **Codex CLI** (`/codex`) = Implementation Engineer for heavy C++/Python builds.
- **Gemini CLI** (`/gemini`) = independent Reviewer for plans and risky logic.

## 7. Definition of "Done" for a Strategy

A strategy is production-eligible only when: positive expectancy survives realistic costs → stable
sensitivity plateau → out-of-sample walk-forward holds → Monte Carlo robustness acceptable → C++ unit
tests pass → MQL5 EA reproduces C++ signals on the same ticks → demo forward-test confirms.
