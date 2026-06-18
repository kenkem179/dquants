---
name: ds-study-track
description: ds-study/ learning sandbox — keep it in sync as the real research progresses
metadata: 
  node_type: memory
  type: project
  originSessionId: ea403f37-60f3-4281-9a3a-951b1f2b1784
---

The user is learning data science by following the quant development. There's a dedicated
read-only sandbox at `ds-study/` (outside the pipeline; never writes to `data/`).

**Expanded 2026-06-14 to a full 00→10 curriculum** mirroring the 10-phase SOP (was just the 4
mid-stream notebooks). The original four were *preserved via `git mv` and enhanced in place* (NOT
rewritten); pristine copies live in `ds-study/scratch/_backup_orig/` (gitignored). Sequence:
`00_raw_tick_data` (Phase 1: streaming/DuckDB/Parquet) → `01_validate_and_clean` (Phase 2) →
`02_ticks_to_bars` (Phase 3a resampling) → `03_feature_engineering` (Phase 3b: 41 causal features) →
`04_labeling` (Phase 4: fwd-ret + triple-barrier) → `05_first_look_eda` (was 01) →
`06_characterize` (was 02) → `07_correlation_hypothesis` (was 03) → `08_discovery` (Phase 5: MI/SHAP/
LightGBM/redundancy/regimes, loads the real `research/discovery/*` artifacts) → `09_quick_backtest`
(was 04) → `10_research_to_strategies` (Phases 6–10: walk-forward + Monte Carlo demos + the 3 editions
+ promotion gauntlet, cites `research/optimization/best_*.set` + RESULTS/PROMOTION-SPEC).

Every notebook opens with a **goal banner** (⏱️ time · 🧭 SOP phase · 🧩 which edition it feeds ·
🎯 goal · 🔑 one thing to remember). README has a **fast-path** (🟢 90-min core `00→03→04→09`;
🔵 strategy path `03→08→10`; 🟣 full). GLOSSARY rewritten with sections A–J. All 11 executed against
real BTC/XAU data via `~/miniforge3/envs/kenkem/bin/python` (0 cell errors).

**Build infra (reusable):** `ds-study/scratch/_build/nbkit.py` (nbformat builder + shared setup cell +
`banner()`) and `build_0N.py` / `enhance_existing.py`. Cell content uses `r'''...'''` so SQL inside
code cells can use `"""`. To add/edit a notebook: edit the builder, run it with the kenkem interpreter.

**Why:** user wants real DS intuition (not run code blindly), the *full upstream journey* (data
engineering + feature engineering — "how we got to this point"), AND to be time-efficient/goal-oriented.
Explicitly: "don't delete anything you've done for me — just change/update/enhance."

**How to apply:** keep the curriculum in sync as research advances; preserve+enhance, never discard.
Keep examples honest (negative results shown deliberately). Many 🎯 exercises ask the learner to repeat
a step on **XAUUSD** (its pipeline is only half-built — real unblazed work). Related:
[[real-target-kenkem-strategies]], [[discovery-findings]], [[pipeline-phase3-conventions]],
[[python-env-kenkem]], [[workflow-commit-and-plan]].
