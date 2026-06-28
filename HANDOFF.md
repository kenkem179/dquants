# HANDOFF - read first, update last

Last updated: 2026-06-28 by Codex. Branch: `3-codex-handoff`.

## Current Goal
Autonomously execute the most valuable BUILD-PLAN items, one at a time, focused on:
- **MasterVP BTC M3** reliability/edge/cost pre-gates.
- **KenKem XAU M1 with tick-activity Volume Profile** as a structural feature.

Top priority remains production-grade profitable EAs. Notebook/learning work is secondary.

Secondary content work completed: drafted a long-form social post pack in `docs/sns/social-post-series-2026-06.md`.

## What Just Changed
- Marked and executed Codex steps in `docs/BUILD-PLAN.md`.
- **Codex-Step-1 / R0 DONE:** `research/data_quality/EVIDENCE_TIERS.md`.
  - Local BTC/XAU MT5 raw samples show LAST and VOLUME are 100% zero.
  - Current VP evidence is quote-activity/tick-count evidence, not traded-volume evidence.
- **Codex-Step-2 / R1 DONE:** `research/data_quality/BTCUSD_M3_MASTERVP_TICK_PROFILE_PROXY_VALIDATION.md`.
  - PASS-WARN: BTC M3 tick-count POC is usually stable under perturbation, but needs cross-feed/real-volume
    validation before traded-volume claims.
- **Codex-Step-3 / K1a DONE:** `research/kenkem_parity/vp_entry_audit/KENKEM_M1_VP_ENTRY_AUDIT.md`.
  - VP location appears to differentiate entry-family quality, but not enough for code changes.
- **Codex-Step-4 / K1b DONE:** `research/kenkem_parity/vp_entry_audit/KENKEM_M1_VP_CANDIDATE_RULES.md`.
  - Do not change KenKem EA. Stronger hard filters fail MinTRL or remain quarter-sensitive.
- **Codex-Step-5 / M1a DONE -> STOP:** `research/mastervp_parity/btc_m3_event_taxonomy_2026-06-28/BTC_M3_EVENT_TAXONOMY.md`.
  - BTC M3 stream is breakeven/negative: 478 trades, PF 0.995. Tested variables are non-monotone.
- **Codex-Step-6 / R4 DONE:** `research/tools/normalize_trades.py` and
  `research/trade_streams/TRADE_STREAM_NORMALIZATION_REPORT.md`.
  - Canonical trade streams now exist for MasterVP BTC M3, KenKem XAU M1, and KenKem XAU M1 with VP context.
- **Codex-Step-7 / K1c DONE -> STOP:** `research/kenkem_parity/vp_sizing_overlay/KENKEM_M1_VP_SIZING_OVERLAY.md`.
  - Do not implement KenKem VP sizing yet. Walk-forward cell sizing underperforms base:
    base net 1987.64 / PF 1.517 vs WF net 1847.38 / PF 1.483.
- **Codex-Step-8 / R5a DONE -> STOP for BTC:** `research/execution/COST_HEADROOM_GATE_2026-06-28.md`.
  - BTC M3 has no cost headroom: net -75.30, mean PnL/trade -0.158; +1 USD/trade stress gives net -553.30 / PF 0.97.
  - KenKem XAU M1 has limited positive cost headroom: mean PnL/trade 14.097; +10 USD/trade leaves PF 1.13,
    +20 USD/trade flips net negative.
- **Social copy draft added:** `docs/sns/social-post-series-2026-06.md`.
  - 18 publish-ready posts, realistic/no-hype tone, optional image placeholders, short compliance-safe disclaimers.
- **Numbered post series added:** `docs/sns/posts/01-60-first-posts.md`.
  - 60 step-by-step posts from the beginning, revised to be slightly longer and more technical while staying compact, with optional image suggestions and short disclaimers.
- **Second numbered post series added:** `docs/sns/posts/61-120-systematic-trading-inspiration.md`.
  - 60 inspirational posts for engineers, data scientists, and discretionary traders moving into systematic trading, with one concept per few posts and compact lessons learned.
- **Image Generation Plan added:** `docs/sns/posts/IMAGE-PLAN.md`.
  - Visual storytelling strategy for the 120-post series, including strategy visuals (EMA, VP), infrastructure, and founder journey themes.
- **Post series updated with images:** `docs/sns/posts/01-60-first-posts.md` and `docs/sns/posts/61-120-systematic-trading-inspiration.md`.
  - All 120 posts now include illustrative, realistic, and technical image placeholders/stories.

Validation run:
- `python -m py_compile` on all new research scripts passed.
- `git diff --check` passed.

## Current Blocker
I cannot honestly self-validate further BTC M3 or KenKem+VP EA code changes from current local evidence:
- MasterVP BTC M3 is already negative/breakeven before extra realistic costs and has no monotone structural
  pre-entry feature in the current event taxonomy.
- KenKem VP hard filters and VP sizing overlays do not pass robust promotion criteria.
- Higher-precision cost/latency modeling is blocked because current exports lack deal-level fields:
  `lot`, `commission`, `slippage`, richer `exit_ts`/`exit`, and realized `r_multiple` for MasterVP.
- Any production-grade BTC claim still needs realistic BTC costs, session/weekend modeling, and MT5 confirmation.

## Exact Next Action
Best next work after this stop:
1. For **KenKem XAU M1**, run `K2 - Lag-aware entry redefinition` on the base edge: separate trigger/state/risk
   geometry and focus on cost-aware invalidation, not VP.
2. For **MasterVP BTC M3**, do not run new sweeps until either:
   - trade exports include lot/exit/commission/slippage for real repricing, or
   - a new structural hypothesis passes model-free event taxonomy before costs.
3. Improve C++/MQL trade exports so future canonical streams include enough broker/deal fields for R5/R6.

If content work resumes, refine or split the social posts into a tighter Facebook/Threads pack.
Or split `docs/sns/posts/01-60-first-posts.md` into one-file-per-post for easier publishing.
Or split `docs/sns/posts/61-120-systematic-trading-inspiration.md` into one-file-per-post for publishing cadence.
Consider using AI image generation tools with the detailed prompts provided in the post files.

Product release blocker remains user MT5 visual spot-check for `KK-MasterVP-Profiler` on XAU M5.

## Decisions To Preserve
- Tick-volume VP is quote-activity VP unless cross-feed/real-volume validation proves otherwise.
- EMA/RSI/DMI/ADX are lagging state descriptors; require incremental OOS/path evidence before they drive entries,
  stops, or targets.
- Do not modify KenKem EA for VP filters or VP sizing from current evidence.
- Do not run more MasterVP BTC M3 parameter sweeps from current evidence.
- Treat blank cost fields as unknown, not zero.
