---
name: codex-big-picture-2026-06-28
description: "Codex snapshot of dquants: architecture, validated edges, current blockers, and risk posture"
metadata:
  node_type: memory
  type: project
  origin: codex
  date: 2026-06-28
---

`dquants` is KenKem Quant OS: a research-to-release stack for XAUUSD/BTCUSD scalping strategies using
real MT5 tick data. The load-bearing design is four layers:
1. Python research in `pipeline/` and `research/` for data import, feature work, hypotheses, sweeps, and
   validation harnesses.
2. C++ pure strategy logic in `cpp_core/`, with no MT5 APIs or broker calls.
3. A deterministic C++ tick backtester, treated as the fast headless tester.
4. Thin MQL5 adapters in `mql5/`, where MT5-specific order/session/account mechanics live.

The project exists to optimize and release the user's existing MQL5 strategies, not to invent unrelated
strategies. MQL5 is the canonical strategy source when porting existing EAs; Pine is not consulted unless
the user names a specific Pine file. The durable SOP is in `docs/KENKEM_QUANT_OS.md`; tactical state is in
root `HANDOFF.md`; open/archived work is tracked in `docs/BUILD-PLAN.md` and
`docs/BUILD-PLAN-ARCHIVED.md`.

Current validated successes:
- KK-MasterVP XAU M5 is the main validated/released edge. The 1.07 lock is MT5-confirmed and DSR-passed,
  centered on RR around 4.0, trail 2.75, BE buffer 0.02, and the late-arm ProgTrail ladder.
- KK-KenKem XAU M1 D5-E4Long is the other standing validated edge, but it is narrower and sample-thin.
- The full research loop has been proven in practice: strategy formalization, C++ tick-engine testing,
  MT5 confirmation, release packaging, account locks, marketplace builds, and user-run MT5 validation.
- The team has repeatedly rejected attractive ideas when MT5 or robust OOS tests disconfirmed them. This
  self-correction is a core strength of the repo.

Current active state as of 2026-06-28:
- The active handoff is PF1: the KK-MasterVP Profiler indicator was rebuilt to behave like the released EA
  while preserving its richer visual shell. It compiles cleanly; the EA was not touched. The remaining gate is
  a user MT5 visual spot check on XAU M5 with the EA lock `.set`, confirming entry markers, realized
  WON/LOST/BE verdicts, and stop paths match the EA backtest sample. Do not package/release the Profiler until
  that spot check passes.
- The market dialog curation mechanism for the Profiler exists, but the Profiler release recut remains gated
  on the visual parity check.

Important challenges and traps:
- The C++ engine is a useful ranking proxy, but the exit model has been proven unreliable for some exit-side
  decisions. For exit geometry, MT5 optimizer/backtest is the judge.
- Node-net value parity is not trustworthy between MQL5 and C++ after the H12c node absorption veto exposed a
  large gap. Any future feature consuming node-net values must first prove per-entry MQL5-C++ parity.
- BTC is not a robust shipped edge. BTC M3 was rejected as overfit/OOS-catastrophic. BTC M5 may show recent
  regime-dependent improvement, but it is not a clean release-grade lock and live/engine differences can be
  thinner than optimistic engine results.
- KenKem M3 was tested and rejected. KenKem should be treated as M1-only unless the user explicitly reopens a
  costly engine-generalization path.
- KenKem E5 parity is a known hard problem: the engine currently hits a roughly 52.8% ceiling due to onset
  latch / B-1 vs B-2 / ADX-freeze behavior. E5 stays off unless the user chooses more instrumentation or an
  exact port effort.
- The KenKem M1 edge is real but narrow, tail-heavy, and close to MinTRL limits; broad sweeps can easily
  destroy statistical validity.
- Cost realism, spread/slippage/commission, DSR/PSR/MinTRL, walk-forward, Monte Carlo, and MT5 parity are not
  optional gates. Uncosted or ungated scalping results should be treated as fantasy.

How to work from this memory:
- Start every session by reading `CLAUDE.md`, then `HANDOFF.md`, then `docs/BUILD-PLAN.md`.
- Trust git and current code over stale memory. If documents disagree, reconcile them instead of choosing the
  convenient one.
- Before changing behavior, identify whether the lever is entry-side or exit-side. Entry-side work can use the
  C++ engine as a fast proxy; exit-side work needs MT5 validation before a verdict.
- Keep all new changes byte-identical to the current lock when default-off. Prove that with tests/trade diffs
  before any release or packaging step.
