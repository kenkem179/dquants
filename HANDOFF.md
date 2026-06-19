# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, C++ tests PASS.
Latest: TWO fixes — ATR=SMA (`f210631`) + MTF EMA off-by-one (`c3a51dc`). E1 now **74 matched / 4 missed /
26 overfire — 95% recall** (from 47/31/62 at session start)._

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

## ✅ MTF EMA off-by-one FIXED (commit `c3a51dc`) — matched 67→74, missed 11→4, overfire 31→26
The EA reads MTF EMAs via `GetEMA(tf,ema,ENTRY_SHIFT=1)`; `EMAHelpers.GetEMAValues` fills `emaBuffers` with a
**NON-series** `CopyBuffer(h,0,0,bufferSize=4,dst)` → order REVERSES (`dst[0]=B-3 … dst[3]=B`), so
`GetEMA(…,1)=dst[1]=B-2` (one bar BEFORE last closed). Engine read `align_tf-3` (=B-3) — one too stale, while
`s.emaM1` everywhere else correctly reads `ema[i1-1]=B-2`. Fixed `emas_ready_entry`+`m5_directional_ok`+E4
STEP-2 M3 read to `align_tf-2`. (Authoritative: `kke1gate.csv` showed 14/31 overfire were `BLOCK:mtf`.)
Recall now **95%** (74/78). NB: matched net engine +516 vs mt5 +1196 — the +7 recovered trades are
MT5-profitable but the engine exits them worse → an EXIT-parity issue on those, not entry.

## 🔬 RESIDUAL now = 26 overfire + 4 missed (re-decomposed vs `kke1gate.csv`)
- **12 `BLOCK:mtf`** — engine still passes mtf where MT5 blocks, but **M1 EMAs now match MT5 99.69%**, so these
  are **HTF (M3/M5) EMA boundary VALUE diffs** (not shift). Diagnosing needs MT5-side M3/M5 EMA values or a
  `KKE1GATE,…,mtf` detail dump of `m1/m3/m5/extreme` — **requires a user-side MT5 re-run** with enhanced gate
  trace. Likely boundary rounding from M3/M5 bar construction (engine aggregates M1 → native M3/M5).
- **8 `PASS:all`** — gate passed, blocked at EXECUTION (high-risk path). The earlier "intrabar" theory was
  WRONG: `DetectNewEntry`+`UpdateIndicatorCache` run ONCE per bar at the new-bar event (KenKemExpert.mq5:2429,
  2491), NOT per-tick — MT5 decides at bar-open like the engine. Sub-reason not yet pinned (spread off;
  daily-loss/aggregate-risk provably inert — see [[kenkem-e1-residual-is-intrabar-exec]]).
- **6 no-row** — MT5 never evaluated E1 there (arming/age timing).
- **4 missed**: 3 are MT5 SL-LOSSES the engine avoids (harmless), 1 end-of-test EA close.

## ▶️ NEXT ACTIONS (in order)
1. **Remaining 12 `mtf` need MT5-side data** — have the user re-run the EA with `KKE1GATE` detail dumping
   `m1_ready,m3_ready,m5_dir,extreme` (or the M3/M5 EMA values) at each `BLOCK:mtf`, to pin which HTF sub-check
   flips and whether it's M3/M5 bar-construction or an EMA-value diff. Without it, 12 mtf is a boundary floor.
2. **8 `PASS:all` execution overfire** — pin the GetEntryBlockReason / HandleHighRiskEntry sub-reason
   (IsInSidewayRange(10)? CheckMomentumForLevel?) by matching each to its tester.log SKIPPED line.
3. **Exit parity on the 7 newly-matched** (engine +516 vs mt5 +1196) — over-trail / TP-vs-SL-WIN family.
4. Accept 26/4 as the E1 floor and extend to **E2/E4/E5** (the bigger remaining scope).

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
