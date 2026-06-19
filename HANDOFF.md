# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, 29 C++ checks PASS._

## 🎯 Goal: KenKem **E1 perfect parity** (then E2, E4, E5), engine ⇄ MT5. Ground truth = the canonical EA.

## ✅ THIS SESSION — TP PARITY FIXED (commit `1ba5157`); tag-agree 66%→**81%**, |Δpnl| med 114→**4.6**
The matched-pair TP was systematically ~0.3–0.4 too CLOSE, firing TP where MT5 trails out for a smaller
SL-WIN. Traced to the canonical EA's `setMaxTPForTrade` → `finalRR = entry.GetRewardRatio() *
GetDynamicRRMultiplier()`. Two faithful fixes:
1. **Short-RR factor was a misattribution.** `GetRewardRatio()` returns ONE per-entry
   `m_config.rewardRatio` applied identically long/short — there is NO long/short split. The engine's
   `KK_E1/E2/E4_SHORT_FACTOR` (0.875/0.867) made every short's TP ~12–14% too close. Set to **1.0**.
2. **`GetDynamicRRMultiplier` un-ported** (SessionManager.mqh:93): `rrRatio *=` session×ATR-pctile scaler
   (ASIA 0.95 / US 1.15 / EU 1.0; ATR pctile ≥75→1.12, ≤25→0.88; clamp [0.70,1.30]).
   `USE_DYNAMIC_RR_SCALING=true`; `ENABLE_ADAPTIVE_E*` all **false** → `GetRewardRatio()` stays static, so
   this multiplier is the ONLY unmodeled RR term. Added `kk_dynamic_rr_mult` + `kk_session_id` in
   entries.hpp, threaded into `compute_tp`.

### Result (FULL 2yr E1 anchor, `KK_E1_FAITHFUL=1`) — see Repro below
- matched exit-tag agreement **66%→81%**; per-trade |ΔpnlUSD| median **114.23→4.56**.
- over-trail (MT5 SL-WIN→eng TP) **5→2**; **SL-LOSS 11/11 exact**; SL-WIN 10→13/15; TP 9→10/12.
- matched net engine **+639** vs MT5 **+990** (gap now in a few outliers + the 31 missed entries).

## 🟢 DATA BLOCKER — APPARENTLY RESOLVED (verify with user)
`cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` on disk now give
**849,963 bars / 162,761,235 ticks** — i.e. the COMPLETE source (matches the proven-exact 848,532 /
162,657,649, [[tick-source-parity-proven-exact]]), NOT the 577k holes-affected regen the prior handoff
feared. All this session's numbers use the complete data. **Confirm with the user** whether they
restored the full Exness export (or it was never actually deleted) before trusting absolute counts.

## ▶️ NEXT ACTIONS (in order)
1. **Entry-count gap is now the dominant residual: 31 missed / 62 overfire.** The matched-net gap
   (engine +639 < MT5 +990) is mostly the **31 MISSED** MT5 trades (engine never fired) — they likely
   hold MT5's big winners. This is the over/under-FIRE problem, not exits. Per
   [[kenkem-e1-overfire-trendcore]] the over-fire is ~84% spurious cross-ARMING (audit
   `triggers.hpp:64–84` cross-arm geometry) + account limiters. Re-enable `ENABLE_LOSS_COOLDOWNS` and
   port the occupancy/daily/consec-loss limiters ([[atr-percentile-parity-wall]]).
2. **2 remaining over-trail + 1 TP→SL-WIN** (both SHORTS: 2024-11-11, 2025-02-12). With short-factor &
   dynamic-RR fixed, `tpExt` is STILL 0 on these (TP extension never fires — bar-frozen `bar_px` never
   gets within 25 pips of TP because the trade hits TP on a live spike first). If MT5 extends TP here,
   that's the last exit lever. Use `KK_TRADE_DIAG=1` (per-trade hr/tpExt/origTP/finalTP/finalSL/best
   cols) + `KK_ENTRY_DIAG=1` (per-entry RR/anchor/session). Lower priority than #1.
3. After E1 net+counts converge, repeat for E2/E4/E5.

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
```
Current (complete data): matched 47 / missed 31 / overfire 62; |Δrisk| 0.081; |ΔpnlUSD| median **4.56**;
matched tag-agree **81%**; matched net engine **+639** vs mt5 **+990**.

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
