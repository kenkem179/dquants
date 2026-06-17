# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⭐ ALWAYS maintain HANDOFF.md (root) — read first, update last

There is a HANDOFF.md at the repo root. It is the living baton between agents/sessions.

At the START of every session: read HANDOFF.md first (after this file). It tells you exactlywhere the previous agent left off, what is in flight, what is blocked (and on what), and the singlemost useful next action. When continueing from the HANDOFF.md and BUILD-PLAN.md, make sure to clean up the handoff notes by removing DONE items, and move the DONE items from BUILD-PLAN.md to BUILD-PLAN-ARCHIVED.md in the same ./docs folder.



Before you finish / pause / hand off: UPDATE HANDOFF.md. Keep it short and current — overwritestale content, don’t append endlessly. It must always answer: (1) current goal &amp; sub-goal, (2) whatjust changed (with commit hashes), (3) what’s blocked and on whom (e.g. “waiting on user MT5 run X”),(4) the exact next action, (5) any decisions made. This is mandatory, not optional.

HANDOFF.md is the fast tactical baton; docs/BUILD-PLAN.md remains the durable phase-by-phase plan(keep ticking it after each step) and ~/.claude memory holds cross-session facts. When theydisagree, trust git + the code, then reconcile all three.

## What this is

KenKem Quant OS — a quantitative research stack for finding, validating, and deploying XAUUSD /BTCUSD scalping edges on M1/M3 timeframes using real MT5 tick data. The full design and the10-phase research SOP live in docs/KENKEM_QUANT_OS.md — read it before doing substantive work.

The defining principle: research never runs inside the MT5 Strategy Tester. Logic is developed andtested in Python + C++, and only proven strategies are ported to a thin MQL5 EA.

## Four-layer architecture (the most important thing to understand)

Layer 1  Python Research   pipeline/ research/   →  DuckDB + Parquet, features, hypotheses
Layer 2  C++ Strategy Core cpp_core/             →  PURE LOGIC — no MT5 APIs, no broker, no OrderSend
Layer 3  C++ Tick Backtester cpp_core/backtester/ → headless, deterministic; the TRUE tester
Layer 4  MQL5 Adapter      mql5/                 →  thin OnTick() wrapper around Layer 2
The layer boundary is load-bearing: EMA/ATR/LongSignal/CalculateSL port ~1:1 from C++ to MQL5, whileOrderSend/PositionSelect/CopyRates/iATR are MT5-only and must stay in Layer 4. Never put tradingdecisions in Layer 4, and never put MT5 API calls in Layer 2. That separation is what lets the samestrategy be unit-tested headlessly and run in production unchanged.

## Environment

Python research runs in the conda env kenkem (Python 3.11). System python3 is 3.8.2 — do notuse it. Activate: conda activate kenkem. Recreate/repair: bash scripts/setup_env.sh.

Toolchain: Apple Silicon (arm64), Apple clang (C++20-capable), Homebrew is x86 under Rosetta.

Deps are pinned loosely in requirements.txt and installed by scripts/setup_env.sh.

## Common commands

# Python research env
conda activate kenkem
jupyter lab                                   # EDA notebooks (research/notebooks/)
pytest                                        # Python pipeline tests
streamlit run reports/&lt;dashboard&gt;.py          # visualization dashboards

# C++ strategy core + backtester (from cpp_core/)
cmake -S . -B build &amp;&amp; cmake --build build     # build core + backtester + tests
ctest --test-dir build                         # run all C++ unit tests
ctest --test-dir build -R &lt;name&gt;               # run a single test by regex
./build/backtester --data ../data/processed/ticks_btcusd_2024.parquet  # headless tick backtest
(C++ build files are scaffolded as the C++ core is implemented — match existing CMake targets whenadding files.)

## Data realities — read before touching data

Raw ticks: data/btcusd/BTCUSD_ticks_mt5_&lt;year&gt;.csv, tab-separated, ~12GB total (2025 ≈ 7.2GB /148M rows). Header: &lt;DATE&gt; &lt;TIME&gt; &lt;BID&gt; &lt;ASK&gt; &lt;LAST&gt; &lt;VOLUME&gt; &lt;FLAGS&gt;.

Never pandas.read_csv these files. Stream with DuckDB read_csv_auto or Polarsscan_csv(separator='\t'), write Parquet once, then work from Parquet.

LAST and VOLUME are 0 on this feed — do not use tick volume; use per-bar tick count.

Derive mid=(bid+ask)/2 and spread=ask-bid. DATE=YYYY.MM.DD, TIME=HH:MM:SS.mmm.

Raw CSVs and all *.parquet are gitignored; the 12GB data/btcusd/ stays in place (not moved).

## Non-negotiable research rules

No lookahead. Every feature/label at bar t uses only data ≤ t; labels look forward from t.

No repainting in both MQL and Pine script and C++



Always model costs (spread, slippage, commission, latency) in any backtest — uncosted results arefantasy, especially for scalping.

Prefer plateaus over peaks. Accept parameters only where sensitivity heatmaps are stable.

Never mix walk-forward periods. Out-of-sample must stay out-of-sample.

A strategy is production-eligible only after the full chain in docs/KENKEM_QUANT_OS.md §7 passes(costs → sensitivity → walk-forward → Monte Carlo → C++ tests → MQL5 parity → demo forward-test).

## Project Skills (the 10-phase SOP)

Each phase of the SOP is a slash-command skill in .claude/skills/. Invoke in order; each consumes theprior phase’s output:

/quant-1-import-data → /quant-2-validate-data → /quant-3-build-features → /quant-5-discovery →/quant-6-hypothesis → /quant-7-backtest → /quant-8-sensitivity → /quant-9-walkforward →/quant-10-promote-mt5

Use /codex for heavy C++/Python implementation and /gemini for independent review of plans andrisky logic.

## KenKem strategy port &amp; parity (the current main thrust)

The real goal is optimizing the user’s existing MQL5 strategies (sibling repo/Users/tokyotechies/Workspace/KEM/kenkem), while keeping in mind that they are not properly optimized yet..

We build KenKem Quant OS in the first place because we want to leverage Python to data analysis and C++ for automated testing before converting the optimized strategy to perfectly working MQL script that can reproduce exact test results in Meta Trader 5.

Original strategy descriptions (will need to be improved and optimized) are written in ../kenkem/notes/strategies. Do double check with MQL code in ../kenkem if exists to validate if you have doubts



Workflow for an existing/new EA: 1. Refer to existing MQL code (of Pine code if user specify), find all required common functions / classes/ helpers (most of them should have been written well in ../kenkem/MQL/KK-Common already), try to reuse equivalent functions/classes/helpers ( like indicator functions, indicator caching functions, trade manager, risk manager, broker helper, session helper, etc...) from dquants C++ common library first before writing code as needed; 2. Write C++  code for missing common functions/class/helpers and strategy specific parts, make sure that classes, functions are all well organized and testable; 3. Use C++ engine and prepared real tick data to conduct the most critical param sweeps to find the best combination =&gt; Lock down the best combination in a .set file in ../kenkem/MQL/Presets; 4. Port the C++ code perfectly to MQL5 code in ./mql5/experts folder





### First target: KenKemExpert - MQL5 is the sole source of truth even if the code is not profitable yet. We will make it profitable via intense testing with C++ . Do NOT read/cite Pine unless the user names a specific Pine file.

Implementation spec: research/hypotheses/*-SPEC.md. Authoritative params: just use code defaults.

C++ engine: cpp_core/ (dependency-free Makefile, make test). Replays the imported tick Parquetheadlessly — never calls MT5 headless to backtest, just to compile. Python is harness-only (Optuna, parity diff, charts).

Parity validation: the engine emits byte-compatible parity_*.csv (per-bar) + trades_*.csv(per-trade) to diff against MT5 (see SPEC §9 — three levels, bar-level first, tolerance compare).MT5 tester reference data lives at kenkem/Tester/Agent-127.0.0.1-3000/: logs/ for run logs,MQL5/Files/&lt;strategy name&gt;/ for the parity/trade CSVs. (Only master VP cols are valid in the parityCSV; sigValid is raw pre-gate DetectSignal.)

## Conventions

Layer 1 outputs are Parquet, queried via DuckDB. Keep the raw→processed→features→labels flowone-directional; never edit upstream artifacts in place.

C++ core is C++20 and deterministic: same ticks → same trades → same equity curve. This is whatmakes unit tests meaningful and MQL5 parity verifiable.

When porting C++→MQL5, keep the same param and function naming convention to make it each to mirror in a 1 to 1 manner



