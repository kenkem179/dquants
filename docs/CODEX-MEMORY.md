# Codex Memory - KenKem Quant OS

This is repo-scoped memory for Codex local, Codex Cloud, and mobile handoff. It intentionally avoids depending
on Claude Code private memory. Read after `HANDOFF.md` and before doing strategy work.

## Core Architecture
- Layer 1: Python research in `pipeline/` and `research/` using DuckDB/Parquet.
- Layer 2: C++ strategy core in `cpp_core/`, pure deterministic logic, no MT5 APIs.
- Layer 3: C++ tick backtester, the headless deterministic tester.
- Layer 4: MQL5 adapters in `mql5/`, thin live/tester wrapper only.
- Never put MT5 API calls in Layer 2 and never put trading decisions only in Layer 4.

## Environment
- Python research uses conda env `kenkem` with Python 3.11. Do not use system Python 3.8 for research.
- Raw tick CSVs and Parquet files are large and gitignored. Never `pandas.read_csv` raw tick CSVs; stream with
  DuckDB/Polars and work from Parquet.
- XAU/BTC tick feeds have `LAST`/`VOLUME` effectively unusable; use tick count per bar, bid/ask, mid, spread.

## Research Rules
- No lookahead, no repainting, no pooled OOS cheating.
- Always model spread/slippage/commission/latency for backtests.
- Prefer stable parameter plateaus over peaks.
- Any searched lock needs the overfitting gate in `research/stats/gate.py`; record `n_trials`,
  `sr_trial_std`, DSR/PSR/MinTRL where possible.
- Use the tick engine for P&L/parity claims, not the bar engine.
- For exit-side MasterVP behavior, MT5 is the judge because the C++ exit model has known runner/trail optimism.
- Treat MT5 `tick_volume`/tick count as quote activity, not exchange traded volume. Any MasterVP volume-profile
  claim must be labeled as quote-activity VP unless validated against real-volume/cross-feed evidence.
- Treat EMA/RSI/DMI/ADX as lagging state descriptors unless they prove incremental OOS value. They can gate
  regime, but should not be trusted as standalone predictive alpha.

## Current Product Truth
- **KK-MasterVP XAU M5 1.07** is the main validated/released MasterVP edge.
- **KK-KenKem XAU M1 D5-E4Long** is the validated KenKem edge; accept KenKem as M1-only unless fresh work
  explicitly reopens it.
- BTC is not production-grade. Recent work showed BTC can be regime-dependent, but no robust BTC lock is
  currently accepted.
- Monster is retired unless explicitly reopened.
- Top priority is making durable, profitable production EAs for volatile XAU/BTC markets using the current
  pipelines and algorithms. Jupyter notebooks are secondary: useful for learning and documentation, not the main
  deliverable.

## Current Baton
- Active blocker: user MT5 visual spot-check for `KK-MasterVP-Profiler` parity on XAU M5.
- Profiler code was rebuilt to use EA-exact signal/gate logic and lock-faithful exit replay while preserving
  the rich display shell.
- MasterVP EA 1.07 was re-cut with compliance disclaimer in broadcast messages; user still needs to upload the
  market `.ex5`.

## Important Traps
- MT5 `.set` files must be flush-left `key=value`; indented settings may load incorrectly.
- MQL5 source of truth for existing KenKem strategies is the sibling `../kenkem` MQL code unless the user names
  another source. Do not read/cite Pine unless the user names a Pine file.
- E5 parity has an onset/latch trap: MT5 reads B-1 and freezes prior alignment across low-ADX gaps; naive shifts
  regress. E5 stays off unless deliberately reopened.
- KenKem M3/K1 was tested and rejected; do not re-open without a new hypothesis.
- Node-net values have an MQL<->C++ parity gap when node-net VALUE is consumed. VAH/VAL/POC distances are safer;
  node-net/absorption requires parity proof first.
- BTC pip scaling is dangerous. Any BTC KenKem work needs pip-denominated decision params converted to
  ATR-relative before trusting sweeps.
- The next build-plan priority is **Phase 1 reliability infrastructure**, starting with data evidence tiers,
  tick-profile proxy validation, and lag-indicator redundancy/delay audits before any fresh alpha sweep.

## Handoff Rules For Codex
- Start every session by reading `AGENTS.md`, `HANDOFF.md`, `docs/CODEX-MEMORY.md`, and
  `docs/BUILD-PLAN.md`.
- Update `HANDOFF.md` last.
- Keep `docs/BUILD-PLAN.md` for open executable work only; move completed/rejected items into
  `docs/BUILD-PLAN-ARCHIVED.md`.
- Do not edit `.claude/*` or Claude Code settings unless the user explicitly asks.
