---
name: kenkem-config-lie-fixed
description: "dquants KenKem port was a config \"lie\"; entry filters/governors/exits now wired, E2 profitable, E1 still bleeds"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0ac8cf33-ad05-46e6-b035-547b59950dbe
---

The dquants C++ "KenKem" edition lost money where the original `KenKemExpert.ex5` backtests at **PF 1.39**
(XAUUSD M1, 2025.03.01→2026.05.29; E1+E2 only, E3/E4/E5 OFF; +$1,969, 164 trades, Recovery 1.40,
Sharpe 13.61). Root cause found 2026-06-15: the distilled engine **parsed all 250 EA params from the
`.set` but only applied a fraction** — conviction scoring, full 0-11 trend-quality, RSI-divergence veto,
ATR high-vol block, consecutive-loss governor, and the panic/score-drop exits were silently ignored, so
the `.set` looked faithful while the engine over-traded chop and rode losers to full SL.

**Fixed** (commits `b4efb90` + `d19ddc2` on branch `1-reorganize-code`): added
`cpp_core/include/kk/kenkem/scoring.hpp` + `exits.hpp`, wired conviction/trend-quality/RSI-veto + ATR
high-block + consec-loss/min-seconds governors + panic/score-drop exits + **JST session filtering** into
`entries.hpp`/`engine.hpp`/`tf_cache.hpp`/`kenkem_config.hpp`, each behind its existing config flag so
**config now drives behaviour**. All 10 kenkem unit tests pass. Trajectory on identical data (439,777
bars == MT5 report exactly): net **-23,067 → -930**, PF **0.94 → 0.99**, **max DD 31,984 → 5,245**.

**Timezone resolved (data-driven):** journal AND dquants parquet are both **UTC**; the EA's JST sessions
apply with **SERVER_GMT_OFFSET=9** (ground-truth entry hours map exactly onto JST Japan/London/NY with
journal = JST−9). Run with `--set research/kenkem_parity/winning_sess.set` (winning.set + offset 9).

**Remaining gap to PF 1.39:** with sessions on, BOTH entry types over-trade ~6× (E1 522 vs 86, E2 415 vs
70) at PF≈0.99 — entries still lower-quality than the EA's 156 @ PF 1.39. Unwired: `HasSufficientMomentum`
(E1 requires, E2 omits), `E1_HTF_TREND_FILTER` strength + high-risk-path branch, and an audit of the
EMA-cross/touch **trigger frequency** (likely the dominant 6× factor) + conviction/TQ integer-score
exactness. See task #6 and `research/kenkem_parity/STATUS.md`. Ground truth at
`research/kenkem_parity/ground_truth_ledger.csv` (build via `build_ledger.py`). Supersedes the old
[[kenkem-distilled-result]] and [[kenkem-bar-engine-invalid]] framing for the engine wiring.
