# HANDOFF - read first, update last

Last updated: 2026-06-28 by Codex. Branch: `3-codex-handoff`.

## Current Goal
Build a much more tailored, institutional-grade R&D and production build plan for the user's XAUUSD/BTCUSD
scalping program:
- **MasterVP**: flagship tick-volume-profile strategy; breakout book first, failed-breakout/local-VP reversion
  second.
- **KenKem**: original EMA/ADX/RSI strategy; improve entry selectivity, stop invalidation, dynamic targets, and
  symbol portability.

Priority clarification from user: **the top priority is profitable, durable production EAs for volatile XAU/BTC
markets using the current pipelines and algorithms. Jupyter notebooks are secondary support material**, not the
main deliverable.

## What Just Changed
- Revised `docs/BUILD-PLAN.md` again after user clarified the core reliability concern:
  MT5/Exness tick-volume profiles lack real traded volume, and EMA/RSI/DMI are lagging indicators.
  The plan now front-loads:
  - `R0` data truth/evidence tiers;
  - `R1` tick-profile proxy validation;
  - `R2` indicator lag/redundancy audit;
  - MasterVP VP fields labeled by source (`tick_count`, `real_volume`, second broker, exchange proxy);
  - KenKem lag-aware entry-role audit before more entry sweeps.
- Replaced `docs/BUILD-PLAN.md` with a program-level, executable R&D roadmap:
  - shared research infrastructure and experiment registry;
  - MasterVP breakout/reversion development;
  - KenKem structural rebuild;
  - regime, portfolio and account-risk production layer;
  - release gates from data/parity through forward-test.
- Added standalone learning notebook:
  - `ds-study/notebooks/13_institutional_scalping_rd_playbook.ipynb`
- Updated study navigation/glossary:
  - `ds-study/README.md`
  - `ds-study/GLOSSARY.md`
- Added priority clarification in `docs/BUILD-PLAN.md`, `docs/CODEX-MEMORY.md`, and this handoff: EA R&D and
  production hardening outrank notebook work.
- External research anchors added in the plan/notebook:
  DSR, PBO/CSCV, HRP, VPIN/flow toxicity, order-flow imbalance.

## Current Blockers
- No code blocker. This pass was documentation/notebook planning only.
- Existing product blocker remains user MT5 visual spot-check for `KK-MasterVP-Profiler` on XAU M5.

## Exact Next Action
If continuing the build-plan work:
1. Start Phase 1 in `docs/BUILD-PLAN.md`: `R0` data truth/evidence tiers.
2. Then implement `R1` tick-profile proxy validation and `R2` lag-indicator redundancy/delay audit.
3. Only after that move to experiment registry, unified trade schema, and realistic cost/latency model.
4. Keep MasterVP exit-side changes MT5-judged; keep BTC closed until cost/session/parity gates are met.

If continuing product release work:
1. Wait for user Profiler visual parity confirmation.
2. Package Profiler market release.
3. Upload/follow through on MasterVP 1.07 market binary as needed.

## Decisions To Preserve
- Do not chase more single-symbol parameter grids before Phase 1 research infrastructure is in place.
- MasterVP gets priority because the VP breakout edge is more structurally coherent and has more expansion room.
- KenKem improvement should focus on structural stop/target/regime logic, not adding random indicators.
- BTCUSD requires BTC-specific costs, sessions, parity, and ATR-relative thresholds; do not port XAU assumptions.
- Release decisions are portfolio/book-level decisions, not per-chart backtest decisions.
- Tick-volume VP is a quote-activity proxy unless cross-feed/real-volume validation proves otherwise.
- EMA/RSI/DMI/ADX are lagging state descriptors; require incremental OOS/path evidence before letting them drive
  entries, stops or targets.
