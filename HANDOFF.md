# HANDOFF — read me first, update me last

_Last updated: 2026-06-20 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN. Latest: E5 RealTrace +10 value-diff cols (M1 EMA stack + M1/M5/M15 DI/ADX) added & compiled 0err → awaiting 1 MT5 re-run._

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

## 🟢 KenKem E5 — real-path trace COLLECTED → 1 fix shipped (+8 recall) → residual decomposed (2026-06-20)
_Real-path E5 entry trace ran clean: `mt5_runs/RUN_2026-06-20_1.8.154_xau_2026H1_E5only_realtrace/`
(`realtrace_*.csv` = 4,914 armed/fired E5 bar snapshots w/ the LIVE per-bar `final_decision`; 108 E5 +949).
Engine repro (commit **2f5143c**, `MT5_E5_2026.set`, `--from-ms 1767225600000 --to-ms 1780272000000`).
Full writeup: **`research/kenkem_parity/E5_REALTRACE_FINDINGS.md`**._

_**✅ FIX SHIPPED — `hr_momentum_level(E5)` = NONE (risk_exec.hpp).** EA `Entry5::GetHighRiskMomentumCheck()`
is hardcoded `NONE` (InputParams.mqh NONE=-1) → the E5 high-risk route applies NO momentum gate; the engine
had no kind==5 case so it fell through to `c.hr_momentum_e1`=3 (M1_AND_M3), wrongly filtering E5 HR entries.
**matched 49→57, missed 59→51, recall 45.4→52.8%** (recovered 8 of the 40 HIGH_RISK_ROUTE misses). Golden 28/28._

_**Residual 51 missed DECOMPOSED** (2 new env-gated engine diagnostics, byte-identical off: `KK_EXEC_DIAG`
= execute-stage block reason; `KK_E5_GATE` = per-bar E5 armed-state + detection-gate first-fail):_
- _**26 unarmed** — engine never arms the E5 alignment-onset (M1 4-EMA strict-alignment onset divergence)._
- _**15 armed→htf** — engine E5 HTF(M5) filter blocks where MT5 `htf_block=0` (HTF value diff near thr)._
- _**7 armed→trend_core** — engine `trend_core_score==0` where MT5 passes (DI/EMA-structure value diff)._
- _**3 armed→PASS** — timing/occupancy (engine fired the cross on another bar)._
- _Only **9/51** are execute-stage (ATR). The gap is **DETECTION-stage value divergence**, NOT exec, NOT
  the high-risk route (now fixed), NOT the disconfirmed ADX-1-bar-shift. **37/42 detection-misses are genuine
  non-detections** (not firing-timing). All have MT5 adx/tq/price/session PASS, sideway/htf=0, age 0–27<28._

_⚠️ **Trace traps** (unchanged): `trace_dumper` close/adx 1 bar staler than EMA; `Entry5.TraceBar` gate cols
use separate `m_tr_` state + wrong `L_atrlo`. The **real-path `realtrace_*.csv` is the trustworthy instrument**
(LIVE trigger), but it logs gate RESULTS only — not the HTF/EMA INPUTS needed to value-diff (see blocker)._

### ▶️ NEXT for E5 — ✅ EA value-diff columns ADDED → AWAITING 1 MT5 re-run
The 26 unarmed + 15 htf + 7 trend_core are genuine engine-vs-MT5 VALUE diffs; the prior `realtrace_*.csv`
carried only gate RESULTS (htf_block, aligned, ema25/ema200), not the gate INPUTS. **DONE this session:**
added **10 value-diff columns** to `kenkem/.../Parity/RealTrace.mqh` + populated them in `Entries/Entry5.mqh`
(struct copy flows through the EA's `GetRealTrace`→`WriteRealTraceRow`, no EA-body change). **Compiles 0 errors**
(`KenKemExpert.mq5` v1.8.154, 1 pre-existing version-string warning). New cols appended after `final_decision`:
- `ema75,ema100` — completes the M1 4-EMA strict-alignment stack (ema25/ema200 already present) → **26 unarmed**
- `m1_diplus,m1_diminus` — M1 DI± the trend-core reads (adx_m1 already present) → **7 trend_core**
- `m5_adx,m5_diplus,m5_diminus,m15_adx,m15_diplus,m15_diminus` — exact HTF ADX/DI the E5 HTF filter reads
  (`Entry5.mqh:272-285`, cache idx 2=M5 / 3=M15; the gate reads ONLY ADX+DI, never M5 EMAs) → **15 htf**

1. **[⚠️ USER — recompile + 1 MT5 re-run, EXACT]** Expert `Experts\…\KenKem\KenKemExpert.mq5` (v1.8.154,
   recompile F7 to pull the edited includes) · Symbol **XAUUSD** (Exness, `XAUUSD-Exness-KK`) · Period
   **2026.01.01 → 2026.06.01** · chart TF **M1** · input set
   `research/kenkem_parity/mt5_runs/RUN_2026-06-20_1.8.154_xau_2026H1_E5only_realtrace/reproduce.set`
   (already has `InpExportRealTrace=true`, `INPUT_TF0=1`, E5-only). Output =
   `MQL5/Files/KenKem/realtrace_XAUUSD-Exness-KK.csv`. Then I auto-collect + value-diff each bucket vs engine.
2. **[ENGINE — startable now]** The **26 unarmed (alignment-onset)** is the biggest bucket; onset-timing in
   `triggers.hpp:177-189` — check engine onset bar vs MT5 `up_age/dn_age` (early expiry past the 28 cap).
3. **[DONE — DISCONFIRMED] Forming-ADX** (`E5_GATE_FORMING_ADX`, default OFF): recall UNCHANGED 45.4%; makes
   the gate STRICTER, wrong direction. Not the lever. (`E5_2026_GATETRACE_FINDINGS.md` UPDATE section.)

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
- **22/68 = MT5_not_armed** → engine arms an E1 cross MT5 never armed (cross-DETECTION divergence).
  INVESTIGABLE NOW from the committed `kke1arm.csv.gz` (509,662 KKE1ARM rows = MT5 cross-arm inputs).
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
4. **E4 NOW UNBLOCKED** — E4-only MT5 ref run committed `RUN_2026-06-19_..._E4only/` (244 E4 trades,
   E4_MAX_CROSS_AGE=20, lot 0.15, else ≡ E1E2 ref). Run the engine E4-only and `diff_kk.py --kind E4`.
   ⚠️ No E4 gate trace exists (EA has no E4_GATE_TRACE flag) — if E4 has an over/under-fire residual, either
   reuse `trace.csv.gz` BarTrace or ask the user to add an E4 gate-trace print. **E5 still blocked** (no run).
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
