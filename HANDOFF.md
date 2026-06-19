# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, 29 C++ checks PASS._

## 🎯 Goal: KenKem **E1 perfect parity** (then E2, E4, E5), engine ⇄ MT5. Ground truth = the canonical EA.

## ✅ THIS SESSION — HIGH-RISK CASCADE FIXED (commit `2644cc7`); matched net −348 → **+527**
The previous "TRAILING-SL overshoot / SL-WIN under-reproduction" residual was a 3-link cascade, ALL
keyed off one fact: the canonical run flags **ALL 78 E1 entries as high-risk** (`tester.log`: every
entry = "High risk/far SL with strong trend"). The engine was firing the high-risk path on only 4/95.
Root causes (all fixed):
1. **Risk-ratio not propagated.** `COMMON_MAX_RISK_PER_TRADE=0.01` was parsed into `common_max_risk`
   but the per-entry `max_loss_ratio_e*` kept their 0.02-based defaults (EA computes them as globals:
   E1×1.05/E2×1.00/E4×1.02/E5×1.00, InputParams.mqh:62-69). → engine budget 2× too high → high-risk
   threshold 2× too high.
2. **Stale set lot.** `anchor_E1_only_trace.set` had `MY_STANDARD_LOT_SIZE=0.15`; the reference run
   used **100** (`tester.log` input echo). With std_lot=100 the lot is always risk/margin-capped, so
   `potentialLoss ≈ maxLoss×riskDistPips ≥ maxLoss` → every trade trips HandleHighRiskEntry (TP×0.65
   multiplier + 0.55 partial). With 0.15 the scaled term bound and almost nothing read as high-risk.
3. **HR partial override un-ported.** High-risk trades arm the smart-partial/trail at
   `HIGH_RISK_PARTIAL_TP_TRIGGER=0.55` (vs E1=0.90) & slice 0.42 (TradeManager.mqh:680-684). Added
   cfg fields + `Position.is_high_risk` + wiring in `manage_tick`.

### Result (2yr E1 anchor, `anchor_E1_only_trace.set`, `KK_E1_FAITHFUL=1`)
- **Matched net: engine +527.1 vs MT5 +454.0** (was −348; sign flipped, magnitude now matches).
- |ΔpnlUSD| median **66→20**; |Δrisk| **0.080→0.036**; overfire **96→40**; 27/29 exact-minute.
- Engine now slightly **OVER-trails** (5 of MT5's 9 matched SL-WINs ride to a bigger TP) — the
  opposite (and far healthier) problem vs the prior under-arming losses. matched tag-agree 59%.

## ⚠️ DATA BLOCKER (the one thing that needs the USER)
The complete tick source that produced the committed reference (5.17 GB ticks → **848,532** bars,
78 trades) is **GONE** from disk. Regenerating from the surviving raw CSVs
(`data/xauusd/XAUUSD_ticks_mt5_*.csv` via `cpp_core/tools/common/build_anchor_2yr.py`) yields only
**577,739** bars — large holes in **2024-H2** (raw 2024 file ends 2024-12-22) and **2025-H2**
(see [[xau-data-gap-2025h2]]). So absolute matched/missed/overfire counts are NOT the baseline's
(49 "missed" is inflated by ~20 pure data-hole days). **Matched-pair comparison is the only valid
signal** until the user re-provides the complete Exness export. The fixes above are code-confirmed
against the EA + `tester.log`, independent of the holes.

## ▶️ NEXT ACTIONS (in order)
1. **Reconcile the rest of the anchor set** against the reference `tester.log` input echo (dump:
   `grep -P "\\tTester\\t  \\S+=" tester.log`). I fixed MY_STANDARD_LOT_SIZE; OTHER keys may also be
   stale — that's the cheapest remaining parity win and needs no new data.
2. **Tune the slight over-trail** (engine +527 > MT5 +454). On the 5 matched "engine-TP vs MT5-SL-WIN"
   pairs (printed by `matched_exit_crosstab.py`) the engine rides past MT5's trailing-SL exit. Suspect
   the live volMult clamp or partial-eligibility timing now arming a touch early. MINOR — levels + HR
   path are correct; this is fine-tuning.
3. **Entry-count gap (40 overfire):** re-enable `ENABLE_LOSS_COOLDOWNS=true` (occupancy/limiters),
   per [[atr-percentile-parity-wall]] — over-fire = unmodeled account limiters.
4. Get the user to re-provide the complete 2024-2026 Exness tick export to restore exact-baseline counts.

## 🔁 Repro (full 2yr, ~30s; data must be regenerated first if missing — see DATA BLOCKER)
```
# regenerate anchor (holes-affected): ~/miniforge3/envs/kenkem/bin/python \
#   cpp_core/tools/common/build_anchor_2yr.py --sym xauusd \
#   --raw-glob 'data/xauusd/XAUUSD_ticks_mt5_*.csv' --from 2024-01-01 --to 2026-06-01 --out-dir cpp_core/tools
cd cpp_core && make test                        # 29 checks, green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/e.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
python research/kenkem_parity/matched_exit_crosstab.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
```
Current diff (holes-affected data): matched 29 / missed 49 / overfire 40; |Δrisk| 0.036;
|ΔpnlUSD| median 20; matched net engine **+527** vs mt5 **+454**.

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
