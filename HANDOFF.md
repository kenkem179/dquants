# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, C++ tests PASS.
Latest: ATR ROOT-CAUSED & FIXED (commit `f210631`) — MT5 iATR is SMA-of-TR, not Wilder. Big parity jump._

## 🎯 Goal: KenKem **E1 perfect parity** (then E2, E4, E5), engine ⇄ MT5. Ground truth = the canonical EA.

## ✅ THIS SESSION — ATR FIXED (commit `f210631`): overfire **62→31**, missed **31→11**, matched **47→67**
The forming-bar ATR divergence is SOLVED. The prior diagnosis ("track forming H/L tick-by-tick") was a
**red herring**: MT5 uses first-tick **H=L=open** on 100% of bars exactly like the engine (forming TR already
matched 99.94%). **Real bug = the CLOSED-bar smoothing. MT5's built-in `iATR` is a rolling SIMPLE MA of
True Range** (`ATR[i]=ATR[i-1]+(TR[i]-TR[i-n])/n`), **NOT Wilder/SMMA.** The engine's `kk::ind::atr` used
Wilder → ~6% mixed-sign off → 29% of bars got the wrong ATR-percentile block category.
- Fix (KenKem-only): `indicators.hpp` add `atr_sma_from_tr`/`atr_sma_mt5`; `tf_cache.hpp` cache ATR(14)→SMA
  + store TR series; `snapshot.hpp` M1+M3 forming shift-0 = SMA window-slide `atr_c + (tr_form - tr[i1-(n-1)])/n`.
- Verify (vs MT5 trace, 848,532 bars): forming-ATR exact(<1e-4) **0.12%→99.93%**; pctile exact **31.6%→81.4%**
  (±3 on 99.96%); entry-gate block-category agree **~71%→100%**.
- ⚠️ **1-bar trace label offset** (key for any future ATR/trace diff): MT5 trace row ts=T = decision at OPEN
  of bar T+1; align engine→MT5 with **shift −1** (engine ts−60000 = MT5 ts) → prevClose matches 100%.

### Prior session (commit `1ba5157`) — TP parity: short-RR factor→1.0 + ported `GetDynamicRRMultiplier`.
Tag-agree 66%→81%, |ΔpnlUSD| med 114→4.6, SL-LOSS 11/11. (Detail in [[kenkem-tp-parity-rr-fixes]].)

### Result now (FULL 2yr E1 anchor, `KK_E1_FAITHFUL=1`)
- matched **67** / missed **11** / overfire **31** (engine 98 vs MT5 78). Recall 60%→**86%**.
- matched exit-tag agreement **87%** (58/67); |ΔpnlUSD| median 5.12; matched net engine **+673** vs MT5 **+959**.

## 🟢 DATA BLOCKER — APPARENTLY RESOLVED (verify with user)
`cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` on disk now give
**849,963 bars / 162,761,235 ticks** — i.e. the COMPLETE source (matches the proven-exact 848,532 /
162,657,649, [[tick-source-parity-proven-exact]]), NOT the 577k holes-affected regen the prior handoff
feared. All this session's numbers use the complete data. **Confirm with the user** whether they
restored the full Exness export (or it was never actually deleted) before trusting absolute counts.

## 🔬 RESIDUAL DECOMPOSED (31 overfire + 11 missed) — ROOT = bar-open vs intrabar execution-gate eval
Matched ALL 31 overfire to MT5 tester.log SKIPPED lines (by entry price): **every one is a trade MT5
classified HIGH-RISK** (`potentialLoss ≥ getMaxLossUSD`) **then blocked at the execution layer** —
440 "high-risk blocked by risk limits" (≈ATR per debug), 19 "Market in sideway range", 15 weak-momentum.
Cross-ref of the 12 cleanest ("MT5 gate fire=1, no trade"): pctile 65.6–87.5 at **bar-open**, several `sess=0`.

**The two un-ported stateful limiters are STRUCTURALLY INERT here — DO NOT re-attempt for this run:**
- `MAX_AGGREGATE_RISK_RATIO` = `MAX_LOSS_RATIO_E1 × 4`, but `MAX_CONCURRENT_POSITIONS_ALLOWED = 2` caps
  exposure at ≤2× per-trade risk → 4× cap can NEVER bind. Provably dead.
- Daily-loss (`MAX_DAILY_LOSS_RATIO=0.072`) needs ~7 losses/day; at ~0.13 trades/day it's never reached.
- A/B: both ported faithfully into tick_engine and tested → **0 trade change**. Reverted (kept the tree lean).
  Position-limit IS already enforced (tick_engine.hpp:236). `ENABLE_LOSS_COOLDOWNS` also inert (0 change).

**TRUE residual cause = the EA evaluates execution gates (ATR-pctile / sideways / session) at the FIRING
TICK intrabar** (its `cachedATRPercentile` updates every tick; the trigger fires mid-bar), **while the
engine decides at bar-open on closed bars.** By the firing tick the forming bar's range has expanded →
pctile rises over the 90 ceiling (ATR-HIGH block) etc. The engine already tracks the intrabar range
(`cur_bar_hi_/cur_bar_lo_`) but FIRES at the first tick, so a pure ATR-read change buys nothing — faithfully
closing this needs **intrabar trigger/entry evaluation**, a real architectural shift (regression risk to the
67 matched). The 11 missed are the mirror image (MT5 catches an intrabar fire the bar-open engine doesn't).

## ▶️ NEXT ACTIONS (in order)
1. **DECISION NEEDED (architectural):** pursue intrabar execution-gate evaluation? It's the only faithful way
   to close the bulk of the 31/11, is ATR-centric (user's #1 priority), but risks the 67 matched. Scope: move
   the E1 trigger/fire + execution gates (ATR-pctile, IsInSidewayRange(10), session) from the bar-open
   `on_bar_closed_` to a per-tick path using `cur_bar_hi_/cur_bar_lo_`. Validate every step with diff_kk +
   matched_exit_crosstab. If not worth it, **31/11 is an acceptable long-tail floor** — move to E2/E4/E5.
2. **Over-trail TP-vs-SL-WIN (3 matched):** 2024-12-02, 2024-05-10, 2025-11-20 — engine runs to TP where MT5
   trails out for a smaller SL-WIN. `tpExt` still 0. Cheap, isolated, no architectural change.
3. **Sanity-check `|Δrisk(SL)|`** (median 0.081→0.181 on the larger 67-trade set); SL now uses SMA `atrM1_sl`.
4. After E1 converges (or 31/11 accepted), repeat for E2/E4/E5.

## 🔁 Repro (full 2yr, ~30s)
```
cd cpp_core && make test                        # 29 checks, green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/e.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
python research/kenkem_parity/matched_exit_crosstab.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
# diagnostics: prefix KK_TRADE_DIAG=1 and/or KK_ENTRY_DIAG=1 (2>/tmp/diag.txt)

# --- ATR-pctile root-cause diagnostics (this session) ---
# 1) oracle A/B: feed MT5's exact per-bar pctile, expect overfire 62->47
D=research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace
gzcat $D/trace.csv.gz | awk -F, 'NR>1{print $1","$33}' > /tmp/pctile_oracle.csv
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --ticks tools/ticks_xauusd_2024_2026.csv --symbol-xau --spread 0.05 \
  --set research/kenkem_parity/anchor_E1_only_trace.set --pctile-oracle /tmp/pctile_oracle.csv --out /tmp/e_oracle.csv
# 2) per-bar pctile divergence: engine trace_dumper col atr_pctile vs MT5 col 33
./build/kenkem/trace_dumper --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --set research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/eng_trace.csv
# (then compare /tmp/eng_trace.csv[atr_pctile] vs $D/trace.csv.gz col33 -> 31.6% exact, 29% wrong category)
```
Current (post-ATR-fix `f210631`): matched **67** / missed **11** / overfire **31**; |Δrisk| 0.181;
|ΔpnlUSD| median **5.12**; matched tag-agree **87%**; matched net engine **+673** vs mt5 **+959**.
(ATR-pctile diagnostics below are now mostly historical — block-category agrees 100%.)

## 📦 Data / instruments
- Full 2yr XAU: `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` —
  REGENERATED this session from `data/xauusd/` symlinked raws; **incomplete** (577,738 bars). gitignored.
- **MT5 ref run (committed)** at `research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/`:
  `trades.csv` (78, the diff target) · `kke1gate.csv` · `tester.log.gz` (input echo + mechanism counts +
  `TRAILING SL` lines) · `trace.csv.gz` (gunzip before use). EA=canonical KenKemExpert, XAU 2024.01→2026.06.
  **Input echo confirms MY_STANDARD_LOT_SIZE=100, COMMON_MAX_RISK_PER_TRADE=0.01, leverage 1:500.**
- Ground-truth EA = `kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5` (+ `TradeManagement/TradeManager.mqh`,
  `Config/InputParams.mqh`). dquants `mql5/experts/KenKem/` is the THIN KK-rewrite — NOT this EA.

## 🧱 After E1→E5 parity LOCKED (user's explicit next phase)
Convert pip-denominated params to ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before — parity
is ground truth. See [[goal-pip-to-atr-relative]].
