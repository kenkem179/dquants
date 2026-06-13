# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**KenKem Quant OS** — a quantitative research stack for finding, validating, and deploying **XAUUSD /
BTCUSD** scalping edges on **M1/M3** timeframes using real MT5 tick data. The full design and the
10-phase research SOP live in **`docs/KENKEM_QUANT_OS.md`** — read it before doing substantive work.

The defining principle: **research never runs inside the MT5 Strategy Tester.** Logic is developed and
tested in Python + C++, and only proven strategies are ported to a thin MQL5 EA.

## Four-layer architecture (the most important thing to understand)

```
Layer 1  Python Research   pipeline/ research/   →  DuckDB + Parquet, features, hypotheses
Layer 2  C++ Strategy Core cpp_core/             →  PURE LOGIC — no MT5 APIs, no broker, no OrderSend
Layer 3  C++ Tick Backtester cpp_core/backtester/ → headless, deterministic; the TRUE tester
Layer 4  MQL5 Adapter      mql5/                 →  thin OnTick() wrapper around Layer 2
```

The layer boundary is load-bearing: `EMA/ATR/LongSignal/CalculateSL` port ~1:1 from C++ to MQL5, while
`OrderSend/PositionSelect/CopyRates/iATR` are MT5-only and must stay in Layer 4. **Never put trading
decisions in Layer 4, and never put MT5 API calls in Layer 2.** That separation is what lets the same
strategy be unit-tested headlessly and run in production unchanged.

## Environment

- Python research runs in the conda env **`kenkem`** (Python 3.11). System `python3` is 3.8.2 — do not
  use it. Activate: `conda activate kenkem`. Recreate/repair: `bash scripts/setup_env.sh`.
- Toolchain: Apple Silicon (arm64), Apple clang (C++20-capable), Homebrew is x86 under Rosetta.
- Deps are pinned loosely in `requirements.txt` and installed by `scripts/setup_env.sh`.

## Common commands

```bash
# Python research env
conda activate kenkem
jupyter lab                                   # EDA notebooks (research/notebooks/)
pytest                                        # Python pipeline tests
streamlit run reports/<dashboard>.py          # visualization dashboards

# C++ strategy core + backtester (from cpp_core/)
cmake -S . -B build && cmake --build build     # build core + backtester + tests
ctest --test-dir build                         # run all C++ unit tests
ctest --test-dir build -R <name>               # run a single test by regex
./build/backtester --data ../data/processed/ticks_btcusd_2024.parquet  # headless tick backtest
```

(C++ build files are scaffolded as the C++ core is implemented — match existing CMake targets when
adding files.)

## Data realities — read before touching data

Raw ticks: `data/btcusd/BTCUSD_ticks_mt5_<year>.csv`, **tab-separated**, ~12GB total (2025 ≈ 7.2GB /
148M rows). Header: `<DATE> <TIME> <BID> <ASK> <LAST> <VOLUME> <FLAGS>`.

- **Never `pandas.read_csv` these files.** Stream with DuckDB `read_csv_auto` or Polars
  `scan_csv(separator='\t')`, write Parquet once, then work from Parquet.
- `LAST` and `VOLUME` are `0` on this feed — **do not use tick volume**; use per-bar tick *count*.
- Derive `mid=(bid+ask)/2` and `spread=ask-bid`. `DATE`=`YYYY.MM.DD`, `TIME`=`HH:MM:SS.mmm`.
- Raw CSVs and all `*.parquet` are gitignored; the 12GB `data/btcusd/` stays in place (not moved).

## Non-negotiable research rules

- **No lookahead.** Every feature/label at bar `t` uses only data ≤ `t`; labels look forward from `t`.
- **Always model costs** (spread, slippage, commission, latency) in any backtest — uncosted results are
  fantasy, especially for scalping.
- **Prefer plateaus over peaks.** Accept parameters only where sensitivity heatmaps are stable.
- **Never mix walk-forward periods.** Out-of-sample must stay out-of-sample.
- A strategy is production-eligible only after the full chain in `docs/KENKEM_QUANT_OS.md` §7 passes
  (costs → sensitivity → walk-forward → Monte Carlo → C++ tests → MQL5 parity → demo forward-test).

## Project Skills (the 10-phase SOP)

Each phase of the SOP is a slash-command skill in `.claude/skills/`. Invoke in order; each consumes the
prior phase's output:

`/quant-1-import-data` → `/quant-2-validate-data` → `/quant-3-build-features` → `/quant-5-discovery` →
`/quant-6-hypothesis` → `/quant-7-backtest` → `/quant-8-sensitivity` → `/quant-9-walkforward` →
`/quant-10-promote-mt5`

Use `/codex` for heavy C++/Python implementation and `/gemini` for independent review of plans and
risky logic.

## KenKem strategy port & parity (the current main thrust)

The real goal is optimizing the user's **existing MQL5 strategies** (sibling repo
`/Users/tokyotechies/Workspace/KEM/kenkem`), not inventing new ones. First target: **KK-MasterVP**
(volume-profile breakout, XAUUSD/BTCUSD **M1/M3** — never M5).

- **MQL5 is the sole source of truth** for every strategy — do NOT read/cite Pine unless the user names
  a specific Pine file. Port from `kenkem/MQL5/Experts/KK-MasterVP/*.mqh`.
- Implementation spec: `research/hypotheses/KK-MasterVP-SPEC.md`. Authoritative params:
  `kenkem/MQL5/Experts/KK-MasterVP/KK-MasterVP-baseline.set` (differs from code defaults).
- C++ engine: `cpp_core/` (dependency-free `Makefile`, `make test`). Replays the imported tick Parquet
  headlessly — **never calls MT5**. Python is harness-only (Optuna, parity diff, charts).
- **Parity validation:** the engine emits byte-compatible `parity_*.csv` (per-bar) + `trades_*.csv`
  (per-trade) to diff against MT5 (see SPEC §9 — three levels, bar-level first, tolerance compare).
  **MT5 tester reference data lives at `kenkem/Tester/Agent-127.0.0.1-3000/`**: `logs/` for run logs,
  `MQL5/Files/<strategy name>/` for the parity/trade CSVs. (Only master VP cols are valid in the parity
  CSV; `sigValid` is raw pre-gate DetectSignal.)

## Conventions

- Layer 1 outputs are **Parquet**, queried via DuckDB. Keep the raw→processed→features→labels flow
  one-directional; never edit upstream artifacts in place.
- C++ core is C++20 and **deterministic**: same ticks → same trades → same equity curve. This is what
  makes unit tests meaningful and MQL5 parity verifiable.
- When porting C++→MQL5, port only the pure functions (signal/SL/TP); the EA stays thin.
