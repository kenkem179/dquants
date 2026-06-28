# HANDOFF - read first, update last

Last updated: 2026-06-28 by Codex. Branch: `2-stabilization`.

## Current Goal
Make the repo self-orienting for Codex local, Codex Cloud, and mobile handoff without touching Claude Code
settings or Claude memory files.

Active product sub-goal remains **PF1: KK-MasterVP Profiler <-> KK-MasterVP EA visual parity**.

## What Just Changed
- Added/updated Codex-facing continuity docs only:
  - `AGENTS.md`
  - `HANDOFF.md`
  - `docs/CODEX-MEMORY.md`
  - `docs/BUILD-PLAN.md`
  - `docs/BUILD-PLAN-ARCHIVED.md`
- No strategy code changed in this handoff-cleanup pass.
- Claude-specific files/settings were intentionally not edited. Existing dirty `.claude/*` files predate this
  handoff pass and should be left alone unless the user explicitly asks.

Recent relevant commits already in git:
- `0cec4fd` build(profiler): market-edition builder hides the 52 leaked EA inputs
- `ca75432` release(mastervp): re-cut 1.07, no version bump, with compliance disclaimer
- `1ac0db1` feat(notify): append compliance disclaimer to broadcast trade messages
- `b8c7a49` feat(profiler): rebuild KK-MasterVP-Profiler as EA-exact parity twin + bounded replay perf
- `c018d6c` research(btc): reconcile production BTC as regime-dependent, not robust enough to ship
- `a1eeeea` research(kenkem): M3/K1 lever tested -> rejected, accept KenKem M1-only

## Current Blocker
Waiting on **user MT5 visual spot-check**:
- Attach `KK-MasterVP-Profiler` on **XAU M5** with the current EA lock `.set`.
- Confirm Profiler entry markers land on the EA backtest entry candles.
- Confirm WON/LOST/BE verdicts and stop path match sampled realized EA trades.
- Known legitimate mismatch: predictive daily-DD cannot be reproduced by the indicator because it needs live
  equity.

## Exact Next Action
If the user confirms the Profiler visual check:
1. Commit the Profiler parity/performance changes if not already committed in the active worktree.
2. Run the Profiler market builder/release packaging.
3. Decide version bump for the Profiler release.

If starting a fresh Codex Cloud/mobile thread:
1. Read `AGENTS.md`.
2. Read this `HANDOFF.md`.
3. Read `docs/CODEX-MEMORY.md`.
4. Read `docs/BUILD-PLAN.md`.
5. Trust git + code over stale notes if anything disagrees, then reconcile these files.

## Decisions To Preserve
- Do not touch Claude Code settings or `.claude/*` memory files unless explicitly asked.
- MQL5 is the source of truth for existing KenKem EAs; C++ is the sweep/parity engine.
- MT5 is the judge for exit-side behavior; the C++ exit model is useful for ranking but has known runner/trail
  optimism.
- Any lock chosen by search needs the overfitting gate with `n_trials` and `sr_trial_std` when available.
- `.set` files must be flush-left `key=value`; MT5 silently ignores indented settings.
- BTC remains research-only unless a fresh candidate passes parity, costs, WF/MC, DSR/MinTRL, and MT5 confirm.
