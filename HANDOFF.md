# HANDOFF — read me first, update me last

_Last updated: 2026-06-20 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN. Latest (KenKem): D3 MT5 confirm OVERTURNED engine (engine E4 EXITS are fictional) → **LOCK = D3-noE4 (E4 OFF), MT5 +1049/PF1.39**; E1+E2 sweep → **D4 candidate** (+ADX23 +touch-age60, engine +1695/PF1.42) awaiting MT5. ⚠️ MT5 `.set` Load needs flush-left (no indent). See 🟢 KenKem D3-noE4 section for the 3 NEXT actions. Also live: MasterVP — **BTC M5 MT5 run BAD: T3 reversion edge FICTIONAL on the BTC/Exness feed (engine revNet +5,414 vs MT5 −76, PF 1.293 vs 1.058) → reverted `InpEnableReversion`→false, BTC M5 NOT deployable; XAU M5 (+60,264/PF 1.40 MT5) is the sole validated front-runner** (`mt5_runs/RUN_2026-06-20_btc_m5_locked_reversion/FINDINGS.md`). Earlier: T2 hour-block 2,3,14 (PF 1.296, MT5-confirmed) + T3-EXIT TP1ClosePct 20→0 locked (commit 4f45ec3)._

## 🎨 KK-MasterVP-Profiler INDICATOR — EA-exact parity build (2026-06-20) — Phase A+B DONE, awaiting MT5 confirm
Goal (user): the Profiler indicator shows an entry on the EXACT candle the KK-MasterVP EA enters, by REUSING
the EA's own decision code. Single-source via **shared includes** (NOT a one-file compile-switch — impossible
in MQL5). Both EA + indicator compile **0/0**.
- **Phase A DONE:** NEW shared `mql5/experts/KK-MasterVP/Decision.mqh` (pure chart-deterministic gate:
  MVP_QualityOk + MVP_DeterministicGatesPass). `Engine.mqh` OnNewBar routed through it — BEHAVIOUR-NEUTRAL
  (same gate set, no side effects, deterministic gates grouped ahead of live ones). EA 0/0.
- **Phase B DONE (commit pending):** rewrote `mql5/indicators/KK-MasterVP-Profiler/KK-MasterVP-Profiler.mq5`
  as the EA twin — `#include`s the EA stack (Types/VolumeProfile/Regime/NodeEngine + Inputs/Strategy/Decision/
  SessionNews; NEVER Engine.mqh) and REPLAYS OnNewBar's shift map per bar (master VP@InpMasterMult×InpVpLookback
  + node + regime + MVP_DetectSignal + MVP_DeterministicGatesPass + one-position + SN max-trades). Draws entry
  E/SL/TP1/TP2 + WON/LOST/BE, SL→BE→ATR-trail stop path, master VAH/VAL/POC lines, regime EMAs, **blocked-hour
  gray shading** (SN_IsBlockedHour via SN_RefTime), status panel. Display knobs prefixed `InpViz*`; all EA
  `Inp*` inherited → drive from the EA `.set`. Daily-DD IGNORED (user-approved; needs live equity). Local POC
  INERT in lock (reversion-only SL) → faint + OFF by default. Indicator CLAUDE.md rewritten to match.
- **⏳ NEXT:** (1) user MT5 visual spot-check: attach indicator to XAU M5 with the EA `.set`, confirm markers
  sit on the same candles the EA backtest opens. (2) Behaviour-neutral EA confirm: re-run locked XAU M5 set,
  expect UNCHANGED numbers vs the last XAU M5 MT5 run. Engine/Strategy logic otherwise untouched.

## 🔥 PROFITABILITY UPLIFT — T2 hour-block + T3-EXIT + T3-REVERSION (2026-06-20) ✅ DONE
6-fold WF with PER-FOLD recent-regime decomposition (the T1 discipline). New diag
`research/mastervp_parity/hour_atr_decomp.py` (per-broker-hour net/PF + per-fold split).
- **MasterVP (XAU M5) — WIN, LOCKED `InpBlockedHoursStr=2,3,14`** (ref-tz UTC+10 = block UTC04 Asian-lunch
  lull + UTC16,17 late-London chop). Pooled PF 1.243→**1.296**, net +16.6%, maxDD 12.5→**10.0%**, worst-fold
  1.102→**1.196**; 5/6 folds improve, BOTH recent folds rise (F5 +533, F6 +640) → passes recent-regime check.
  MC(20k): P(profit)99.9%, PF 5th-pctile 1.158, maxDD median 22.2%/95th 34.7% (all better than baseline lock).
  REJECTED: news hr0 (net-harmful — post-data hr has continuation winners), Asia hr10 + hr18 (over-block),
  ATR upper-band `InpMaxAtrPct` (non-monotonic curve-fit noise, costs net). `InpBlockedHoursStr` is a REAL EA
  input (same UTC+10 frame via `SN_RefTime`) → ships via `.set`, NO recompile. Engine lock + EA preset
  `KK-MasterVP-XAUUSD-M5.set` updated + redeployed (kenkem Presets + MT5 Tester Presets). **✅ MT5 CONFIRMED**
  (`mt5_runs/RUN_2026-06-20_xau_m5_T2_hourblock`): blocked hours UTC04/16/17 EXACTLY empty in MT5 (block
  ported faithfully via `SN_RefTime`); PF 1.370 engine vs 1.366 MT5 (0.3%), lag 3.2%, 468/535 matched.
  net Δ 9.2% = known feed-noise (strict-gate FAIL only). On this window block lifted PF 1.339→1.370. CLEARED for demo.
- **Monster (BTC M3) — NO CHANGE (re-validated).** T2 was already done in its lock (`8,10,11,16` + best_btc
  cluster sessions + active ATR band 0.158). Top pooled candidate `8,9,10,11,16` (PF→1.231) is ANOTHER T1
  trap: gain carried by 2025 (F1 +787/F2 +247) while recent F5 −372/F6 −321 + dd worse → REJECTED. Keep current.
- **T1 (gate sweep) — DONE earlier:** MasterVP gates tested→reverted to baseline (commit ded3e81); Monster
  gates negative. MT5 parity confirmed faithful. See [[mastervp-m5-gate-sweep-lock]]. 🔑 LESSON (reconfirmed
  twice in T2): decompose per-fold (esp. recent OOS) BEFORE locking — pooled WF avg hides regime shifts.
- **T3-EXIT (XAU M5) — WIN, LOCKED `InpTp1ClosePct` 20→0** (commit 4f45ec3). The Pine 20% partial was
  INHERITED verbatim, never WF-swept (the M5 lock only swept entry/risk). Per-fold sweep
  (`wf_mastervp.py --grid InpTp1ClosePct`) is MONOTONIC (0<10<20<35<50 on PF/net/dd/worst-fold) → banking
  any partial caps the trailed runner. 0%: pooled PF 1.296→**1.335**, net +15.3% (19.3k→22.3k), maxDD
  10.0→**9.2%**, worst-fold 1.196→**1.219**; ALL 6 folds improve incl. both recent. Matches Monster/BTC.
  EA recompiled 0/0; shipped `KK-MasterVP-XAUUSD-M5-LOCKED.set` (MT5 Presets). ⏳ needs MT5 re-run.
  LESSON: WF-sweep even pre-tuned "faithful" values. See [[mastervp-tp1-partial-zero-is-best]].
- **⏳ IN FLIGHT: full exit-block joint WF sweep** (`InpTp1ClosePct × InpTp1R × InpTrailAtrMult`, 33 combos
  × 6 folds, `research/mastervp_parity/exit_block_sweep.out`) — the entry side got a joint sweep, the exit
  side never did. Lock the whole exit block the same way once it lands.
- **T3-REVERSION (mean-reversion activation) — DONE, 2 WINS / 2 REJECTS** (`research/mastervp_parity/wf_t3.py`,
  generalized 4-config harness). Reversion fires ONLY in balance (non-trend) regime = complement of breakout
  → additive. Swept enable→retest→body→sl×4 configs, 6-fold WF + MC, per-fold recent-regime discipline:
  - **BTC M5 (KK-MasterVP) — 🧨 MT5-DISCONFIRMED → REVERTED to breakout-only (2026-06-20).** Engine WF
    sweep had claimed a WIN (`InpEnableReversion=true`…, pooled PF 1.217→1.308, net +62%, revNet +5,158).
    **User ran the locked set in MT5 → BAD.** `mt5_runs/RUN_2026-06-20_btc_m5_locked_reversion/FINDINGS.md`:
    fair overlap window engine **PF 1.293 / +10,129 / win 59.6%** vs MT5 **PF 1.058 / +1,761 / win 51.2%**;
    engine **revNet +5,414 vs MT5 −76** → the reversion edge is FICTIONAL on the BTC/Exness feed. Only 57%
    of trades match (XAU ~86%); on matched, exits agree 89% but engine over-wins +8 pts (feed round-trips
    intrabar: 45% continuation vs 94% OANDA — already measured). Same shape as Monster BTC M3 (1.178→1.031).
    **ACTION TAKEN:** flipped `InpEnableReversion` true→false in engine set + all 3 EA presets + MT5 Presets.
    **BTC M5 MasterVP = NOT live-deployable** (breakeven live); the 57% entry-match gap must be closed first.
    **XAU M5 is the sole validated front-runner** (same-session MT5: +60,264 / PF 1.400 / 1294 trades).
  - **XAU M5 (KK-MasterVP) — WIN, LOCKED** `InpEnableReversion=true` at DEFAULT rev params (no tuning beat
    them). Measured ON TOP of the T3-EXIT TP1=0 base: pooled PF 1.335→**1.344**, net +3.6%, maxDD 9.2→**7.8%**,
    6/6 folds, worst-fold 1.219→**1.223** (rises), F6 1.49→1.52. revNet small (+48) = mostly dd-smoothing, not
    standalone edge. MC(20k): P(profit) 100%, PF 5th 1.198, 11/12 months & 7/8 folds, full-stream maxDD med 23.3%.
  - **XAU M3 — REJECT** (revNet ~+27 break-even, maxDD 14.2→15.9% worse, worst-fold 0.731→0.674 deepens).
  - **Monster BTC M3 — REJECT** (default rev: folds PF>1 6/6→4/6, F3+F6 go negative, maxDD 10.6→13.8%).
  Both wins: engine locks + EA presets (`KK-MasterVP-{XAUUSD,BTCUSD}-M5.set`) updated + redeployed (kenkem
  Presets + MT5 Tester Presets). All rev keys are REAL EA inputs → ship via `.set`, NO recompile. ⏳ needs MT5 re-run.

## 📚 ds-study learning track — RELIABILITY HALF ADDED (NB 11 + 12, additive)
Added two notebooks teaching the half that made MasterVP *reliable* (00→10 only taught finding an edge).
**NB 11 `parity_ground_truth`** — ground-truth ladder, diff-config-before-logic (real `.set` diff),
Wilder-vs-SMA ATR bug reproduced on real M1 bars (6.9% mean / 23% bucket flip), trade-level PASS/FAIL
matcher (real `_locked_oos.csv`). **NB 12 `overfitting_and_drawdown_honesty`** — peak-vs-plateau,
walk-forward (11/12 months PF>1) + Monte-Carlo (P(profit) 99.6%, PF 5th 1.10) on real `_wf_fullrun.csv`,
drawdown honesty (calmest 4mo 13.9% vs full-year 27.7% vs MC95th 38.7%). Both executed 0-errors against
real artifacts; README/GLOSSARY updated additively; generator `ds-study/scratch/_gen_nb11_12.py`. Nothing deleted.

## 🟢 KK-MasterVP — TRADE-LEVEL PARITY VERIFIER SHIPPED (production gate, commit 5fc34c9)
**User ask:** make perfect MQL EA editions from the C++ pipeline for production; chose the
**MasterVP parity verifier** track + deploy via **MT5 demo forward-test first**.
- **Gap found & closed:** the shipped KK-MasterVP EA had NO trade-export, so "compiles" could
  never be upgraded to "proven-faithful." Added `mql5/experts/KK-MasterVP/Parity.mqh` — a
  trade-level journal byte-compatible with the C++ `kk::to_trades_csv` ledger (21 cols, matched
  rounding), gated by **`InpExportParity`** (default OFF). Wired into `Engine.mqh` (init/close,
  fill-capture, per-tick MFE/MAE, `OnTradeTransaction` → realized P&L across TP1 partial+final,
  TP/SL-WIN/SL-LOSS/EA tags). Compiles **0/0**.
- **Chain proven:** engine-vs-engine smoke (108 trades, May-2026 XAU M5) → `parity_diff.py` **PASS**.
- **Procedure documented:** `research/mastervp_parity/PARITY_WORKFLOW.md` (3 steps: MT5 tester with
  `InpExportParity=true` → C++ backtester same window/set → `parity_diff.py` PASS/FAIL).
- **✅ FIRST PARITY RUN → FAIL → ROOT-CAUSED → EA FIXED** (`research/mastervp_parity/mt5_runs/
  RUN_2026-06-20_xau_m5_parity/`). XAU M5, 2026.01-06: EA 631 vs engine 563, 416 matched, entries
  FAITHFUL (entryΔ≈0), SL formula identical.
  - **ROOT CAUSE = EA runner-TP PORT BUG (not spread).** Exit-tag decomp: MT5 **170 TP** / 175 SL-WIN /
    286 SL-LOSS vs engine **10 TP** / 313 SL-WIN / 239 SL-LOSS. EA capped broker TP at `sig.tp2`=1.8R;
    engine uses 10R runner backstop + chandelier trail (`position_manager.hpp:93-97`, trail_runner=true,
    enable_struct_tp=false, runner_rr=10). **FIXED `Engine.mqh:226`:** TP=`sig.entry±sig.risk·InpRunnerRr`
    when InpTrailRunner. EA recompiles **0/0**. Memory [[mastervp-feed-spread-10x-mismatch]].
  - **SPREAD = real but MINOR:** engine feed 18.9pts vs live Exness 189pts (10×), but `--extra-spread 0.170`
    moved PF only 1.31→1.28 (~$2/trade). Added `--extra-spread` to backtester (`tick_engine::set_extra_spread`,
    golden tests green) for live-cost stress. (My first "spread=root cause" call was WRONG — corrected.)
  - ATR-mode hypothesis tested + DISCONFIRMED.
- **✅ TP FIX CONFIRMED — NEAR-PARITY** (`RUN_2026-06-20_xau_m5_parity_v2_tpfix/`). MT5 re-run after the
  fix: trades 631→**561** (engine 563), TP exits 170→**7** (engine 10), exit-mismatch 141→**39**, matched
  416→**483**, net Δ **409%→2.42%**, PF **1.304 vs engine 1.316**. The runner-TP port bug WAS the parity
  gap. `parity_diff.py` still says FAIL only because net Δ 2.42% > strict 1.0% gate — but that residual is
  **feed-level noise** (bar/ATR value diffs + spread on ~80 boundary trades + 39 exit flips), NOT a logic
  bug. Signal/entry/exit mechanics are faithfully reproduced.
- **▶️ NEXT ACTIONS:**
  1. **Demo forward-test** — the EA now demonstrably reproduces the validated engine; XAU M5 is cleared.
  2. Stress the lock for live PF: `--extra-spread 0.17` (engine PF holds ~1.28 at real Exness cost).
  3. Replicate the runner-TP fix + add `Parity.mqh` into **KK-MasterVP-Monster**, then parity-run it.
  4. (optional) decide whether ~2-3% feed noise is the accepted parity floor for this pair.
  KenKem still NOT production-eligible (E5 parity open).

## 🟣 KK-MasterVP-Monster (BTC) — WALK-FORWARD RE-LOCK this session (robustness ↑, EA re-shipped)
**User ask (this session):** autopilot the walk-forward / multi-fold robustness path I proposed last
time (instead of more single-split sweeping), then auto-produce the MQL EA. **DONE — committed/pushed.**
- **WHY WF:** the prior audit left the inherited secondary params at spec defaults to avoid curve-fitting
  one OOS window. The rigorous test (SOP `/quant-9-walkforward`) is **6 disjoint folds** (2 in the 2025
  train ticks, 4 in the 2026 OOS ticks), adopting a change only if robust ACROSS folds (improves pooled
  result AND the worst fold). Harness `research/monster_parity/wf_monster.py` + engine `--trade-to-ms`
  fold cap (the latter committed by the parallel MasterVP agent — already in HEAD).
- **RESULT — 3 secondary params re-tuned, the rest CONFIRMED at defaults:**
  - Re-locked: `InpDiSpreadMin` 6→4, `InpImpulseTrendSlopeBars` 10→6 (dominant lever, impNet +45%),
    `InpTp1ClosePct` 15→0 (no TP1 bank; BE-after-TP1 still de-risks at 1R). They **stack constructively**
    (tested jointly — repo's "sequential wins can fail jointly" guard): convert the two losing 2026 folds
    to positive → **6/6 folds PF>1, worst-fold PF 1.001** (was 0.867), pooled PF 1.106→**1.140**, dd
    16.0→**13.7%**. On the ORIGINAL single split: **OOS PF 1.131→1.192** (now clears the ≥1.15 deploy
    gate), OOS net +1,956→**+3,014**, OOS dd 10.1→**9.5%**, train also up (1.071→1.084).
  - CONFIRMED inherited-correct by WF: EMA 24/194 (outright best), ema_sep 0.25, node touch 0.05 + gate
    ON, impulse entry_buf 0.4 (flat/inert). REJECTED: impulse max_dist 3.0 (worsens worst fold). Daily-DD
    limiters structurally INERT (6/8/10 identical) — kept 6% as live-safety floor. Full table in
    `research/monster_parity/MONSTER_M3_FINDINGS.md` (WALK-FORWARD section).
- **EA RE-SHIPPED** `mql5/experts/KK-MasterVP-Monster/` recompiles **0/0**; the 3 params updated in
  `Inputs.mqh` defaults + all 4 presets (EA folder + `kenkem/MQL5/Presets/`, impulse + NoImpulse). M1-net
  via iVolume=tick_volume. **MANUAL MT5 FORWARD-TEST is the next action.** `InpEnableImpulse` toggles A/B.
- **M5:** still NOT robust on BTC (prior session) — Monster ships **M3 only**.

## 🟠 KK-MasterVP-Monster (BTC M3) — EA fixed + parity-ready + spread-stressed (this session)
- **EA FIXED:** ported the runner-TP fix (`Engine.mqh`: TP=`sig.entry±sig.risk·InpRunnerRr`=5.3R when
  InpTrailRunner, mirrors monster_engine.hpp:275-287; was capped at sig.tp2=3.0R) + added trade-level
  `Parity.mqh` (InpExportParity). Compiles **0/0**. Engine lock reproduces OOS PF 1.192.
- **SPREAD-FRAGILE:** OOS PF 1.192→1.172(+1)→1.157(+2.5)→**1.121(+5)**. Thinner than XAU M5. Cost-aware
  SL re-tune found NO robust improvement (wider SL curve-fits train, degrades OOS). Lock SL=3.7 is the
  OOS-optimum. `research/monster_parity/MONSTER_SPREAD_ROBUSTNESS.md`.
- **✅ PARITY RUN DONE** (`research/monster_parity/mt5_runs/RUN_2026-06-20_btc_m3_parity/`). BTC M3,
  2026.01-06. TP fix CONFIRMED (MT5 TP=3, exit dist 154/3/148/115 ≈ engine 159/3/144/99). Entries faithful.
  **BTC spread ~$11 ≈ engine feed — NO 10× inflation (unlike XAU);** engine PF was already realistic-cost.
  **BUT net Δ 498%: engine +2,801/PF 1.178 vs MT5 +469/PF 1.031.** Matched 345 agree; gap = unmatched
  (75 MT5-only / 59 engine-only) → EA takes ~75 trades the engine doesn't near session boundaries.
  **→ Monster is MARGINAL live (PF ~1.03), NOT clearly deployable.** XAU M5 is the strong candidate.
- **▶️ NEXT for Monster (only if pursuing it):** diagnose the 75 MT5-only entries — compare entry-gate /
  MaxTradesPerSession / cooldown counting between EA & engine near session/force-close boundaries.
  Otherwise deprioritize vs the XAU M5 forward-test.

## 🔀 ACTIVE THRUST (2026-06-20): KK-MasterVP Pine-faithful rebuild → param sweep → EA
**User pivoted** from KenKem E1–E5 parity to optimizing **KK-MasterVP on XAUUSD M3**. KenKem state
preserved below (📌 PAUSED) — not abandoned.

- **Goal:** reproduce the profitable TradingView Pine (`research/mastervp_parity/KK-MasterVP.pine`,
  PF 1.24 / 5,204 trades / +2583%/yr OANDA XAU) in the C++ engine, then *add missing risk management*
  (daily-DD, consec-loss, anti-chase, ATR-pctile gate, trail/stall exit) via disciplined param sweeps,
  then port to an MQL5 EA for the user's manual MT5 forward test.
- **User chose:** Fresh **Pine-faithful** build · **XAUUSD M3** first · objective **Robust PF + plateau**.
- **User directive (autopilot):** "go autopilot until the C++ engine is super faithful, nothing left to
  sweep while I sleep, then produce the MQL EA for manual testing."
- **✅ S0 DONE (commit a087b52, pushed):** engine aligned to ref Pine via `tools/mastervp/pine_faithful_xau.set`
  + `backtester --set-all` (applies ALL keys incl. MQL non-inputs). Built `research/mastervp_parity/diff_tv.py`
  (regroups TV TP1+TP2 portions → positions; distributional compare). **Entry model is FAITHFUL:** over
  2025-06-19..2026-05-29, engine 2610 positions vs TV 2445 (1.07×), win 56.4 vs 57.8%, hours aligned, TP1-rate
  aligned, %long ±4. **Two fixes found:** (a) `broker_gmt_offset` was DEAD — wired it; the TV hour fingerprint
  proves Pine sessions ran in **UTC+10** (Asia-open 00:00→14:00 UTC spike; gap 21-24→11-13 UTC empty); set
  offset=10. (b) added `min_atr_ticks` floor (Pine=40), default 0/off so golden test intact.
- **🔑 KEY FINDING — residual PF gap is FEED-DRIVEN, not a bug:** baseline PF 1.01 vs TV 1.25 at MATCHING win
  rate. BE on/off experiment proved it: on OANDA a break that reaches 0.8R continues to 1.8R **94%** of the
  time; on our **MT5/Exness feed only ~45%** (it round-trips). So the TV edge leans on OANDA's smooth
  post-breakout continuation — the edge must be REBUILT for the real feed via exit/risk sweeps. This is the point.
- **✅ SWEEPS DONE + EA SHIPPED (this session) — autopilot endpoint reached:**
  - **S1 entry:** break_buf 0.7 / adx 22 / di 8 best. **S4 exit:** chandelier trail beats fixed-TP2,
    `trail_atr_mult=2.0 + sl_atr_brk=1.0`. **S6b risk:** daily-DD **10%** (plateau 8/10/12),
    loss-streak limiter HURTS (off), risk **1.0%** (lowest-DD plateau). **Q1 (ATR-pctile gate):** inert on
    MasterVP — keep off. **Q2 (anti-chase break_max_atr):** capping HURTS on this feed (2 ATR → negative) — off.
  - **⭐ S8/S8b VP-length (user-requested):** train peak **85×4 (PF 1.271) COLLAPSES to break-even OOS** (curve-fit);
    long-window generalizes. **LOCKED master VP = 480 bars (24h M3) = `InpVpLookback=120 × InpMasterMult=4`.**
    **TRAIN PF 1.264 / OOS PF 1.114, OOS net +4,575, OOS maxDD 17.5%.** Sits interior to a broad OOS plateau
    (480→720 bars all OOS PF 1.11–1.15; <360 collapses, >720 falls off).
  - **⭐ DISCOVERY: local VP is INERT in breakout-only mode** — breakout keys off the MASTER VP's VAH/VAL only;
    local VP is consumed only by reversion (off). Master length is the sole driver. See
    `research/mastervp_parity/VP_LENGTH_STUDY.md`. → user's multi-TF VP idea is a real *future* enrichment
    (turn the dead local/HTF-M5/M15 VP into a breakout AGREEMENT gate; build in C++ + sweep + OOS first).
  - **Locked config:** `cpp_core/tools/mastervp/kkmastervp_xau_m3_LOCKED.set`. OOS validator: `/tmp/vp_oos.py` pattern.
- **✅ MQL5 EA SHIPPED (compiles 0/0):** `mql5/experts/KK-MasterVP/` — `Engine.mqh` now ports the FULL C++ safety
  gate stack (quality→session→ATR-ticks floor→spread→max-trades→daily-DD predictive→blocked-hour→peak-DD→
  cooldown→news) + RiskManager (daily-DD 10% + 12h cooldown) + broker-UTC auto-detect (sessions trade the same
  wall-clock hours on ANY broker). Fixed the old EA's hardcoded MTF/RSI veto → now flag-gated (Pine has neither).
  `SessionNews.mqh` = self-contained Sessions (filters.hpp port) + NewsFilter (CSV+embedded calendar) for the
  user's KenKem-style session config + news avoidance (default OFF; live-only overlay, not in backtest PF).
  Preset `KK-MasterVP-XAUUSD.set` shipped to EA folder + `../kenkem/MQL5/Presets/`. **READY FOR MANUAL MT5 TEST.**
- **✅ M5 DEDICATED SWEEP DONE (this session) — M5 BEATS M3 on every axis:** master-len → entry → exit →
  risk, each train→OOS, plateau-picked (`research/mastervp_parity/M5_SWEEP_FINDINGS.md`). Inertness
  re-confirmed (master bars = sole driver). **Locked M5: master 432 bars (36h) = 108×4 · break_buf 0.85 ·
  sl_atr_brk 1.2 · trail 2.5** (rest = M3 lock). Caught the trail overfit-trap (train loves 4.0, OOS peaks
  2.0–2.5). Daily-DD inert on M5 (kept 10% as live net). Result: **OOS PF 1.327 / dd 10.3% / win 58.6% /
  net 7,886 / n 442** vs M3 lock OOS PF 1.114 / dd 17.5%, AND more tail-robust (M5 top-10 = 121% of net vs
  M3 208%). Engine lock `cpp_core/tools/mastervp/kkmastervp_xau_m5_LOCKED.set`; EA preset
  `mql5/experts/KK-MasterVP/KK-MasterVP-XAUUSD-M5.set` (+ kenkem Presets) — attach EA to an **M5** chart.
- **✅ BTCUSD SWEEP DONE (this session, NO-SESSION 24/7, M3+M5):** `research/mastervp_parity/BTC_SWEEP_FINDINGS.md`.
  **M3 BTC = NO edge** (train tunes to PF 1.13 but every config collapses OOS PF 0.72–0.83, dd 57–75% — overfit;
  train/OOS anti-correlated; NOT shipped). **M5 BTC = modest plateau-robust edge** at a LONG master: master
  **720 bars (60h) = VpLookback24×MasterMult30 · adx30 · break_buf1.0 · sl2.2 · trail6.0**, 24/7 sessions.
  Positive on BOTH train+OOS across a 4-D plateau (master×adx×sl×trail): **TRAIN PF 1.155/dd13.9% · OOS PF
  1.214/dd14.2%/win57.4/net+4,228**. ⚠️ tail-skewed (OOS top10=219% of net — lower-conviction than XAU; the
  trend-breakout fat-tail shape). Lock `cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set`; EA preset
  `KK-MasterVP-BTCUSD-M5.set` (+ kenkem Presets, attach to BTCUSD M5 chart). `sweep.py` now has `--symbol btc`;
  combined BTC bars `bars_btcusd_2025_2026_{m3,m5}.csv` built (gitignored). Train win only 3.5mo = main limiter.
- **✅ WF + MONTE-CARLO HARDENING DONE (this session) — XAU M5 lock CLEARED for forward-test:**
  `research/mastervp_parity/WF_MC_FINDINGS.md`. Added C++ `--trade-to-ms` fold cap (`tick_engine
  ::set_trade_to_ms`; golden tests green) + `wf_mc.py` (stability+MC) + `wf_reopt.py` (anchored re-opt) +
  continuous tick file `ticks_xau_full.csv` (gitignored). Canonical continuous stream (1,413 trades over
  2025-06→2026-05, x4.11/+311%, PF 1.260): **walk-forward 11/12 months & 7/8 equal folds PF>1** (only
  Aug-2025 negative, trendless chop); **anchored re-opt 4/5 OOS folds PF>1, WF-eff ~1.0**, and the FIXED
  432b lock BEATS per-fold re-optimization (5/5 vs 4/5) → **not a curve-fit, no periodic re-tuning needed.**
  **Monte-Carlo (20k):** P(profit) 99.6%, PF 5th-pctile 1.108, risk-of-ruin ≤50%=0.06% at 1%/trade.
  ⚠️ **DRAWDOWN HONESTY:** the headline OOS dd 10.3% was a benign 4-month window — true full-year maxDD
  **27.7%** (MC 95th ~38%, worst ~55%); size for **~30-40% peak**, not 10%. **No param change**; EA preset
  annotated + re-synced to kenkem Presets; EA recompiles **0/0**.
- **▶️ NEXT (when user returns):** manual MT5 forward-test — XAU **M5 preset is the validated front-runner**
  (XAU M3 A/B; BTCUSD-M5 candidate but lower-conviction/tail-skewed). Remaining optional research: same
  WF+MC pass on the M3/BTC locks, and the local/HTF-VP breakout-agreement gate. Note: EA news/session
  overlays diverge intentionally from the backtest (live-safety), so forward results may be fewer than OOS PF.
- **Data:** combined bars `cpp_core/tools/bars_xauusd_2025_2026_m3.csv`; full ticks `ticks_xauusd_2024_2026.csv`
  (5.2GB); train/oos cuts above. TV log: `~/Downloads/KK_-_Master_VP_OANDA_XAUUSD_2026-06-20.csv`.

---

## 🟢 KenKem XAU M1 — OPTIMIZATION: D3-noE4 LOCKED (MT5-confirmed) → D4 candidate awaiting MT5 (2026-06-20)
Pivoted parity→profit. Harness `research/optimization/sweep_kenkem_opt.py` (TICK engine; line-mutates a
base `.set`; reports ALL + 2025/2026-OOS + per-quarter; families: `combos sl tp gates cand wf reorder
e1e2 e1e2b`). Data = XAU 2025-03→2026-05 (15mo). Full writeup w/ all evidence:
**`research/optimization/KENKEM-D3-OPT-FINDINGS.md`** (read the top ⚠️ block first).

**⚠️ MAJOR THIS SESSION — engine D3 was INFLATED by an E4 EXIT BUG (MT5 confirm overturned it):**
- Two `.set` runs were silently ignored by MT5 because the preset had **leading whitespace** on every
  line — **MT5's Tester→Load only accepts flush-left `key=value`** (engine parser tolerates indent). FIXED
  (strip WS, re-sync Presets). *Lesson: every KenKem `.set` we ship MUST be flush-left; verify with
  `grep -cE '^[[:space:]]+'` = 0.*
- Real MT5 D3 = **+905 / PF 1.22 / 155 tr** vs engine +2194/PF1.40. Time-aligned diff
  (`research/kenkem_parity/mt5_runs/2026-06-20_D3/`): ENTRY parity FINE (141/155 matched, over/under-fire
  net ~0); **E1 exit-CLEAN** (eng +883 vs MT5 +868); **E4 EXITS BROKEN** — 48/48 matched E4 have IDENTICAL
  entry time+price but engine books +747 vs MT5 **−42** (engine TP where MT5 hits SL; SL levels differ only
  ~0.29 → engine MISSES the intrabar adverse path; engine `maeR` is a 0.00 stub). E2 mildly optimistic.
- ⇒ engine "E4 is best (PF1.51)" + the reorder-rejection rationale are ARTIFACTS. **In MT5, E4 is a net
  LOSER.** Engine sweep numbers carry exit-optimism bias: worst E4, mild E2, ~none E1 (entry-side trustworthy).

**✅ LOCK = D3-noE4 (E4 OFF), `research/kenkem_parity/KK-KenKem-XAUUSD-M1-D4...` → `KK-KenKem-XAUUSD-M1-D3-noE4.set`.**
MT5 A/B confirmed: **+1049 / PF 1.39 / 102 tr** (`mt5_runs/2026-06-20_D3-noE4/`) vs full-D3 +905/PF1.22;
OOS 2026 +243/1.23→**+327/1.47**; profitable quarters 3/6→**4/6** (25Q2 +231, 26Q2 flips −279→+57; only
26Q1 liked E4, outweighed). D3 keys: `USE_DYNAMIC_RR_SCALING=false`, `E1_ATR_SL_CAP_MULTIPLIER=3.5`,
`SIDEWAYS_BLOCK_THRESHOLD=45`, `MIN_ENTRY_ATR_PERCENTILE=70`, **+ `ENABLE_E4_ENTRIES=false`**.

**🆕 D4 CANDIDATE (engine, NOT yet MT5-confirmed) `KK-KenKem-XAUUSD-M1-D4.set` (in Presets, flush-left):**
D3-noE4 **+ `E1_MIN_MOMENTUM_ADX` 19.5→23 + `E2_MAX_TOUCH_AGE` 36→60**. Both are ENTRY filters (the side
the engine models faithfully) → should translate to MT5. Engine ALL +1247→**+1695 / PF 1.42**, Sharpe
2.47→**3.12**, OOS +251→**+293**, per-quarter keeps BOTH 2026 quarters positive (26Q1 +202, 26Q2 +91).
Levers ADDITIVE (e1e2b: S1+ADX23 +1397, S2+TA60 +1470, S3 both +1695). REJECTED: `min_TQ_E1=8` (redundant
w/ ADX23), `E1_RR=1.5` (pooled-OOS +353 illusion — per-quarter 26Q2 FLIPS to −98). ATRpct70 + sideways45
already optimal; E1 HTF-DI & low min_TQ inert; cross-age 100-120 = overfit trap.

▶️ **NEXT ACTIONS (in priority order):**
1. **MT5-confirm D4** — run KenKemExpert (XAU M1, 2025.03.02–2026.05.29, every-tick) w/ `KK-KenKem-XAUUSD-M1-D4.set`.
   Auto-collect→diff vs engine /tmp-style (use `cpp_core/build/kenkem/tick_backtester --set <D4.set> --symbol-xau
   --out X.trades.csv`, then time-align by (minute,dir,kind)). Expect ~+1100–1300 if entry-faithfulness holds.
   If confirmed, D4 becomes the new lock (update preset name + memory + this section).
2. **E5 evaluation (user explicitly asked why E5 was ignored — it was wrongly dismissed on engine numbers).**
   ✅ PRESET READY: `KK-KenKem-XAUUSD-M1-D4-E5.set` (D4 + `ENABLE_E5_ENTRIES=true`, flush-left, staged in
   Presets). Engine reference (DIRECTIONAL only — ~53% E5 recall + exit optimism, [[kenkem-e5-2026-selection-break]]):
   D4 148tr/+1695/PF1.419 → D4+E5 397tr/+2092/**PF 1.184** (E5's 248 tr = +435 @ PF~1.04, dilutes book +
   nibbles E1/E2 via slot contention). Engine says "dilutes", but it MISSES ~half of real E5 + the accidental
   first run = **E5-only +1019/331tr in MT5** → only MT5 settles it. **RUN #2 after D4:** Load D4-E5 preset,
   same XAU M1 2025.03.02–2026.05.29 every-tick; SHIP E5 only if E1+E2+E5 beats D4 on BOTH net AND PF.
3. **Engine E4 intrabar-exit fix** — so future E4/E2 exit sweeps are trustworthy (per-tick barrier check at
   `cpp_core/include/kk/kenkem/trade_manager.hpp:110-114` looks correct; suspect entry-bar arming / exit
   granularity or trail level. The MAE stub should also be implemented for diagnosis). Unlocks revisiting E4.
- Stubborn losers in EVERY config: 25Q1 (sparse early data) + 25Q3 (summer chop) — a session/vol filter is
  the likely lever there (untested).

## 🟢 KenKem E4 — FIRST PARITY DIFF → SL-cap bug fixed → recall 78.7%→94.3% (2026-06-20, commit af8b798)
First-ever E4 benchmark (engine vs `RUN_2026-06-19_..._E4only`, 244 MT5 trades; feed the run's
`inputs_echo.txt` DIRECTLY as `--set` — section headers parse to empty keys, harmless; zero transcription risk).
- **ROOT (systematic): engine SL +39.5% too wide in 190/192 matched** (pinned to the 4.0×ATR cap; MT5 ~2.9×ATR).
  The EA's `CalculateStopLossWithCustomEMA` (EntryBase.mqh) picks cap/floor via `(entryType==1)?E1:E2` →
  **entryType=4 falls through to E2 (cap 3.0/floor 1.1); the `E4_ATR_SL_*` inputs are PARSED but DEAD.**
  Engine had faithfully coded the *documented* 4.0/1.25. Fixed `atr_sl_caps(kind==4)`→e2 bounds.
- **CASCADE (wider SL was binding occupancy/risk limiters, suppressing entries):** matched **192→230 (94.3%)**,
  missed 52→14, overfire 23→24, |Δrisk(SL)| median 0.93→**0.166**, |ΔpnlUSD| median 12.96→**7.96**, exact-min 230/230.
- **E4 recall now MAXED** (with E1 93% / E2 96%): the 14 missed net **−409 (4/14 win, EA-cut losers)** — don't chase.
  Residual SL bias +5.9% = the shared forming-vs-closed ATR floor (E1/E2 have it too; untouched). E1/E2 byte-identical.
- Added `test_e4_sl_uses_e2_cap`. ▶️ **E4 exits not yet diffed** (matched |Δpnl| 7.96 is small; lower priority).
  Next per user's pick: **E1 22-not-armed overfire** (mine committed `kke1arm.csv.gz` vs engine `triggers.hpp`).

## 🟢 KenKem E5 — real-path trace COLLECTED → 1 fix shipped (+8 recall) → residual decomposed (2026-06-20)
_Real-path E5 entry trace ran clean: `mt5_runs/RUN_2026-06-20_1.8.154_xau_2026H1_E5only_realtrace/`
(`realtrace_*.csv` = 4,914 armed/fired E5 bar snapshots w/ the LIVE per-bar `final_decision`; 108 E5 +949).
Engine repro (commit **2f5143c**, `MT5_E5_2026.set`, `--from-ms 1767225600000 --to-ms 1780272000000`).
Full writeup: **`research/kenkem_parity/E5_REALTRACE_FINDINGS.md`**._

_**✅ FIX SHIPPED — `hr_momentum_level(E5)` = NONE (risk_exec.hpp).** EA `Entry5::GetHighRiskMomentumCheck()`
is hardcoded `NONE` (InputParams.mqh NONE=-1) → the E5 high-risk route applies NO momentum gate; the engine
had no kind==5 case so it fell through to `c.hr_momentum_e1`=3 (M1_AND_M3), wrongly filtering E5 HR entries.
**matched 49→57, missed 59→51, recall 45.4→52.8%** (recovered 8 of the 40 HIGH_RISK_ROUTE misses). Golden 28/28._

_**✅ RESIDUAL 51 missed VALUE-DIFFED (v2cols run, this session) — decomposition OVERTURNED.** The richer
realtrace (10 new gate-INPUT cols, kenkem `ebd1bde`) + 2 new env-gated engine dumps (`KK_E5_VALDUMP`:
E5V=M1 EMA stack@B-1/B-2/B-3 + alignment verdict; E5D=M1/M5/M15 DI+ADX closed&forming) → tool
`diff_e5_valuediff.py`. The prior "26 unarmed + 15 htf + 7 trend_core" was a MISATTRIBUTION:_
- _**42 M1 onset/arming** — engine never arms the M1 4-EMA strict-alignment onset (the near-sole root)._
- _**1 htf** — engine M5 **closed** adx/di == EA realtrace EXACTLY (20.7,20.0,17.6); NOT an HTF value diff._
- _**2 trend_core / 2 armed-pass / 4 nojoin** — negligible. HTF & trend-core were arming misclassifications._

_**ROOT (proven, NOT a value/seeding bug):** the onset BAR-PAIRING. `KK_E5_VALDUMP` shift-test → the EA's
logged alignment `ema25` matches the engine stack at **B-1 (m1s1) EXACTLY 42/42** (engine EMA values are
correct == MT5 at the same bar), but the engine onset reads **B-2 (m1s2, faithful)**. **BUT a naive global
fresh shift REGRESSES** (`KK_E5_FRESH_ONSET`: recall 52.8→41.7%, matched 57→45, overfire 33→53) — arming &
fire are coupled, faithful B-2 is net-best. The 42 are marginal near-tie alignment bars._

_**Worth chasing:** the 51 missed MT5 trades net **+466 (53% win)** — REPRESENTATIVE of the full E5 edge
(+949/52%), unlike E1's all-loser misses. Recovering ≈ half the E5 P&L. Full writeup: `E5_REALTRACE_FINDINGS.md`._

### ▶️ NEXT for E5 — DECISION POINT (recall is at the faithful 52.8% ceiling)
The 42 onset misses need the EA's **exact latch internals**, not a shift (the shift regressed). To port
MT5's precise `aligned@cur && !aligned@prv` pairing, the realtrace must add `m_prevBullishAligned`/
`m_prevBearishAligned` (prior-bar alignment) + `m_lastBullishSignal`/`m_lastBearishSignal` (armed-bar idx).
**Options:** (A) add those 4 cols to RealTrace.mqh + 1 more MT5 run → port the exact latch (regression risk,
real +466 edge); (B) accept the 52.8% faithful ceiling and move to **E1/E2/E4** parity (per user's E5→E1
directive). _Recommend B unless the user wants to push E5 recall._ Engine instruments + analysis committed.

## 🎯 (KenKem) Goal: optimize E5 then E1 (user directive). Parity first (foundation), then param sweep.
Ground truth E5 = `research/kenkem_parity/mt5_runs/RUN_2026-06-19_1.8.154_xau_2yr_E5only_cd120/`
(trades.csv 656 trades net +1267 PF 1.10; trace.csv.gz per-bar E5 TraceBar; inputs_echo.txt).

## ▶️ THIS SESSION (2026-06-20) — E5 entry onset FIXED; E5 exit parity is the next blocker
1. **[committed d1704ab] E5 onset off-by-one** — `triggers.hpp` E5 read M1 alignment at B-1/B-2 (1 bar
   too fresh); MT5's trapped GetEMA → onset = aligned@B-2 && !aligned@B-3. Gated on `kFaithful`
   (e5_cur=m1s2, e5_prv=m1s2-1). Result (MT5_E5_ONLY.set vs E5only_cd120):
   matched **295→399**, missed 361→257, overfire 344→233, exact-minute **66→342**, |Δentry| **0.286→0**.
   See memory [[kenkem-e5-onset-trap-fix]]. Tool added: `research/kenkem_parity/diff_e5_trace.py`.
2. **[DIAGNOSED, not fixed] E5 EXIT parity = the P&L gap.** On 399 matched trades: tag-agree 61%,
   engine net **−489 vs MT5 +733** (Δ −1222). Per-cell P&L drain:
   - **EA→SL-LOSS (67): Δ −1826** — MT5 cuts losers early ("EA"); engine rides to full SL. #1 drain.
   - **TP→SL-WIN (25): Δ −1050** — engine trails too tight, exits before MT5 reaches TP.
   - (the full MT5-"EA" row nets ~even +21; the killers are specifically EA→SL-LOSS and TP→SL-WIN.)
   ROOT (partly localized): `exits.hpp:55-63` `panic_exit_enabled`/`score_drop_enabled` for E5
   FALL THROUGH to the E1 flags (stale comment "E3/E5 not used"). In the E5 set E1-panic=true so panic
   IS on, but fidelity differs (per-tick vs once-per-bar ADX-collapse; unmodeled `minADXToHold=18`
   hold-exit + `ENABLE_PRE_BE_STRUCTURE_PROTECTION=true` PRE_BE_TRIGGER_R=0.5 structure SL move +
   E5_TRAILING_SL_FACTOR=0.38 / E5_PARTIAL_TP_TRIGGER=0.8 trailing). Needs E5-specific exit fields +
   panic/pre-BE/trail parity pass.

## ▶️ NEXT ACTIONS (in order)
1. **E5 exit parity**: add `panic_exit_e5`/`score_drop_e5`/`di_flip_e5` config fields + parse
   `ENABLE_*_E5`; route `panic_exit_enabled(5)`→e5 flag. Then attack EA→SL-LOSS (panic ADX-collapse
   fidelity / minADXToHold=18 hold-exit) and TP→SL-WIN (trailing/PRE-BE). Re-diff with
   `matched_exit_crosstab.py`; target matched-net sign-match + tag-agree >80%.
2. **Then E5 sweep** on the C++ engine over real ticks (existing harness: `research/optimization/
   sweep_e5_exits.py`; 9-col table via `report_metrics.py`). Lock best combo in a `.set` under
   `kenkem/MQL5/Presets`. Candidate knobs: E5_MAX_EMA_CROSS_AGE, MIN_TREND_QUALITY_E5,
   E5_MIN_MOMENTUM_ADX, E5_RR, E5_HTF_*, trailing/partial, MIN_ENTRY_ATR_PERCENTILE.
3. Then repeat for E1 (entry parity already ~93%; focus E1 exits + sweep).
4. After E1→E5 locked: pip→ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before.

## 🔁 Repro E5 (~24s tick run, ~4s trace)
```
cd cpp_core && make test && make kenkem_trace kenkem_tick
./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --ticks tools/ticks_xauusd_2024_2026.csv --symbol-xau --spread 0.05 \
  --set ../research/kenkem_parity/MT5_E5_ONLY.set --out /tmp/e5.csv
M=research/kenkem_parity/mt5_runs/RUN_2026-06-19_1.8.154_xau_2yr_E5only_cd120/trades.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e5.csv --mt5 $M --kind E5         # 399/257/233
python research/kenkem_parity/matched_exit_crosstab.py --engine /tmp/e5.csv --mt5 $M     # exit P&L cells
./build/kenkem/trace_dumper --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --symbol-xau \
  --spread 0.05 --set ../research/kenkem_parity/MT5_E5_ONLY.set --out /tmp/e5_trace_eng.csv
python research/kenkem_parity/diff_e5_trace.py --eng /tmp/e5_trace_eng.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-19_1.8.154_xau_2yr_E5only_cd120/trace.csv.gz
```

## 📌 E1 context (prior sessions, unchanged this session)
Ground truth = MT5 run `research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/`
(echoed inputs in `inputs_echo.txt`; engine `.set` must mirror them exactly).

## ▶️ THIS SESSION — re-ran E1/E2 on this machine; found+fixed the real E1 blocker
Fresh baseline on complete data (162.7M ticks, ~24s/run), all matches exact-minute (pure selection problem):

| Kind | Window | MT5 | Eng | Matched | Missed | Overfire | Recall |
|------|--------|-----|-----|---------|--------|----------|--------|
| E1 | Full      | 183 | 238 | **171** | 12 | 67 | **93.4%** |
| E1 | Gap-free  |  82 | 107 |  **78** |  4 | 29 | **95.1%** |
| E2 | Full      | 142 | 159 | **136** |  6 | 23 | **95.8%** |
| E2 | Gap-free  |  69 |  79 |  **65** |  4 | 14 | **94.2%** |

**ROOT CAUSE of the old "E1 50% recall" = a single config mismatch, NOT an engine bug.**
- `anchor_E1E2.set` had `E1_MAX_CROSS_AGE=28` but the MT5 run echoed **80**. (28 was a live-trading
  "cut over-trading" cap baked into both the set and `kenkem_config.hpp:199` default.) A full set-vs-echo
  diff showed this was the **ONLY** value mismatch of 193 keys.
- Effect: engine expired armed crosses at age 28 while MT5 held them to 80 → MT5 fired E1 on bars the
  engine had already dropped. **Fixed set → E1 recall 50%→93.4%** (matched 92→171, missed 91→12). E2 unchanged.
- Diagnostic that nailed it (reproducible): categorized the old 91 missed E1 via `KK_EMIT_GATE_REASON`:
  56 = armed-then-expired (cross-age!), 18 = never-armed, only **17 gate-blocks (1 sideways)**. The prior
  HANDOFF's "sideways over-block, highest-leverage" was wrong — sideways blocks 1 of 91.
- Also corrected: the "E1↔E2 interaction (78→183 E1)" was a **lot-size artifact** — the E1-only set runs
  `MY_STANDARD_LOT_SIZE=100` (MT5 account limiters choke E1 to 78), the E1E2 set runs 0.15 (limiters off,
  183 fire). Not a real entry interaction.

## 🟡 RESIDUAL = E1 overfire (68 full / 29 gap-free) — NOW LOCALIZED at trade level. E2 overfire 23/14.
Using the new MT5 gate trace (`RUN_2026-06-19_..._E1E2_gatetrace/kke1gate.csv`, 104k per-armed-bar E1
verdicts, aligned at engine = MT5 + 60s), each of the 68 overfire trades was matched to MT5's verdict:
- **41/68 = MT5_BLOCK:mtf** → the engine's MTF (M3/M5 EMA-alignment) gate is too PERMISSIVE; MT5 armed the
  cross and blocked it on MTF, the engine passed & fired. Confusion matrix: 240 bar-evals engine-PASS where
  MT5=mtf (+10 trend_quality); EVERY other gate matches ~100% (htf 58,672/58,832, price_pos/momentum/
  trend_strength/rsi_div clean). NOT a shift bug — M3/M5 reads already use `align_tf-2` (gates.hpp:88,94).
  It's genuine M3/M5 EMA VALUE divergence near the `tol` band.
- **~~22/68 = MT5_not_armed~~ → CORRECTED (2026-06-20): only ~8, and NOT phantom arms.** Cross-referencing
  each of the 67 current overfire against the actual `kke1arm.csv.gz` arm-state at the entry bar: **0 had
  MT5 armU/armD = −1** (the gate-trace "not_armed" label conflated expired/consumed arms). 59/67 = MT5
  DID arm → downstream block (the 41 MTF + ATR/limiter exec). The remaining **8 are arm-TIMING offsets on
  REAL crosses** (engine-early detection e.g. 2024-02-21 13:15 fires 8min before MT5's armU=0@13:23;
  re-arm-after-age-80-expiry e.g. 2025-04-29; one opposite-dir). Net **+377 engine-FAVORABLE, 5/8 wins** →
  NOT worth a fix (regression risk on the 171 matched, heterogeneous, no single bug). The 59 armed-gate
  overfire net only +35 (near-neutral). **CONCLUSION: E1 overfire has NO clean local fix; the only
  actionable lever is the MT5 M3/M5 EMA-at-entry dump (item 3) for the 41 MTF value-diff.**
- 5/68 = MT5_PASS (benign timing/occupancy near-miss).
- Reverse (engine BLOCK where MT5 PASS) is tiny: 8 conviction + 2 mtf + 1 tq = the engine-only conviction
  gate slightly over-blocks → a minor missed-entry source.

## ▶️ NEXT ACTIONS (in order)
1. **[committed]** `E1_MAX_CROSS_AGE=80` in `anchor_E1E2.set` (E1 recall 50→93%). `kenkem_config.hpp:199`
   default stays 28 (live-trading opt) — parity is driven by the `.set`.
2. **[ENGINE, no new MT5 data]** Mine `kke1arm.csv.gz` vs the engine's E1 arm decisions to fix the 22
   MT5_not_armed overfire (cross-detection divergence). diff against the engine's cross-arm logic
   (`triggers.hpp` ema cross arming).
3. **[USER]** One MT5 re-run dumping **M3/M5 EMA1..4 at ENTRY_SHIFT** (the BarTrace lacks them — only M1
   ema0..4 + per-TF ADX/DI present). Needed to value-diff the 41 MTF-gate overfire. This is the long-standing
   M3/M5-alignment ceiling, now pinpointed to exactly the MTF gate.
4. **✅ E4 DONE** (commit af8b798, recall 94.3%) — see the E4 section at the top. Entry recall maxed;
   E4 exits not yet diffed (low priority, matched |Δpnl| 7.96 already small).
5. After E1→E5 LOCKED: pip→ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before.

## 📁 NEW: MT5 gate-trace run (committed this session)
`research/kenkem_parity/mt5_runs/RUN_2026-06-19_1.8.154_xau_2yr_E1E2_gatetrace/` — from
`MT5_E1E2_GATETRACE.set` (≡ reference run + E1_GATE_TRACE/E1_ARM_TRACE). trades.csv (325, **byte-identical
to the reference** → trace didn't perturb logic), kke1gate.csv (104,221), kke1arm.csv.gz (509,662),
trace.csv.gz (per-bar BarTrace), tester.log.gz, inputs_echo.txt. Confusion tool: `diff_gate_reason.py`.

## 🔁 Repro (~24s/run)
```
cd cpp_core && make test                     # 28 checks green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1E2.set --out /tmp/e1e2.csv
M=research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/trades.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e1e2.csv --mt5 $M --kind E1   # 171/12/67
python research/kenkem_parity/diff_kk.py --engine /tmp/e1e2.csv --mt5 $M --kind E2   # 136/6/23
# gate-reason diagnostic (categorize missed E1):
KK_E1_FAITHFUL=1 KK_EMIT_GATE_REASON=1 ./build/kenkem/tick_backtester ... 2>/tmp/gr.txt
```

## 📦 Data / instruments
- Complete data: `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` (849,963 M1
  bars / 162.7M ticks, 2024-01 → 2026-05). Research parquets `data/processed/ticks_xauusd_{2024,2025,2026}.parquet`.
- MT5 ref runs: `RUN_2026-06-18_1.8.154_xau_2yr_E1E2/` (325 trades = 183 E1 + 142 E2; the diff target) and
  `..._E1only_trace/` (78 E1, lot=100, has `kke1gate.csv`).
- Sets: `anchor_E1E2.set` (E1+E2, lot 0.15, now E1_MAX_CROSS_AGE=80 ✓), `anchor_E1_only_trace.set`
  (E1 only, lot=100 — limiter regime, do not use for the free-fire baseline).
- 3 core engine fixes confirmed PRESENT in this branch (verified by code read): ATR=SMA-of-TR
  (`tf_cache.hpp:42`), MTF-EMA shift (`snapshot.hpp:131`), sideways 5-bar-avg (`snapshot.hpp:85-98`).
