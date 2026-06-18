# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, 29 C++ checks PASS._

## 🎯 Goal: KenKem **E1 perfect parity** (then E2, E4, E5), engine ⇄ MT5. Ground truth = the canonical EA.

## ✅ THIS SESSION — EA-faithful EXIT pipeline ported (P1–P3) + ROOT CAUSE re-diagnosed
Replaced the distilled `manage_tick` (partial→BE→single chandelier) with the canonical
`KenKemExpert.mq5` STANDARD-mode pipeline. Two commits (pushed):
- **4b7e2fc** P1: R-mult BE (D), smart-partial-on-retrace (F), 3-stage ladder (G), origTPDist trail (T),
  the **load-bearing price split** (`live_px` for SL/TP+ladder; bar-frozen `bar_px` = EA
  `cache.currentPrice/high/low` = bar first-tick bid for D/F/T/best), and the **entry-bar gate**
  (`barsSinceEntry>0` skips management, broker SL/TP still fills).
- **d4a51ee** P2/P3: TP-extension (E, static 6/25 pips) + **live volatility multiplier** in the trail
  (`clamp(formingBarRange/atr14, 0.7, 1.5)`; tick_engine tracks forming-bar bid range + 14-bar TR).

Files: `cpp_core/include/kk/kenkem/{trade_manager.hpp,tick_engine.hpp}`,
`cpp_core/tests/kenkem/test_kenkem_trade_manager.cpp` (rewritten for the new model).

## 🔬 DECISIVE EVIDENCE — from MT5 `tester.log.gz` (RUN 1.8.154, 78 trades). THIS REPRIORITIZES THE SPEC.
Mechanism fire counts in MT5: **TRAILING SL 290** · PARTIAL 93 · PANIC 24 · R-MULT BE 20 · BE 18 ·
SIDEWAY 15 · EARLY 9 · PRE-BE 6 · **TP EXTENSION 1** · **LADDER 0** (all 106 trailing lines `Ext #0`).
- ⇒ **The ladder (SPEC P1 G) and TP-extension (SPEC P3 E) are essentially INERT in MT5.** My ports are
  correctly near-inert and are **NOT** the divergence source. (SPEC §0's "SL-WIN 7% vs 35% ⇒ ladder"
  hypothesis is WRONG — the ladder never fires; the SL-WIN comes from the **TRAILING SL**.)
- ⇒ Decoded a trailing line: dist = best−newSL = 0.469 = `0.40*origTPDist*0.70` ⇒ **volMult=0.70 confirmed**
  (my live volMult port is faithful). `bestPrice==marketPrice` at bar-boundary ts ⇒ **bar-frozen model confirmed**.

## 🧨 TRUE ROOT CAUSE of the residual exit gap = **SL/TP LEVELS differ (entry-side), not exit mechanics**
Same matched trade: engine TP **2032.609** vs MT5 TP **2032.073**. Across 46 matched trades the engine's
**risk (|entry−SL|) is systematically TIGHTER**: median Δ −0.248, **ratio 0.949 (~5% tight)**, 36/46
engine<MT5, **7 EXACT**, 3 wider. Wider engine TP ⇒ later 0.90 partial-eligibility + looser
`0.40*origTPDist` trail ⇒ the trail never catches the retrace ⇒ engine rides to TP where MT5 books SL-WIN.
**Exit mechanics cannot tie out until SL/TP levels match** — every exit change this session was net-neutral
(net 1456.63, SL-WIN 11% vs MT5 35%) BECAUSE the level gap dominates.

### Where the 5% comes from (traced into the EA):
EA `CalculateStopLossWithCustomEMA` (EntryBase.mqh:637) = structure stop (`min(recentLow,emaLevel)−27pip`)
→ **ATR arbitration** (floor `1.2*ATR`, cap `4.0*ATR`) → `ApplySpreadBuffer`. The engine's `compute_sl`
(entries.hpp:57) mirrors structure+arbitration but the gap is the **ATR value feeding the floor/cap**:
- `ApplySpreadBuffer`/`CalculateBufferedStopWithSpread` only widens if rawSL < 0.5*spread (≈0.025) ⇒ INERT,
  not the cause (engine omitting it is fine).
- The **7 EXACT matches = pure-structure SLs** (ATR arb doesn't bind). The **36 tighter = ATR floor/cap
  binds with a slightly-low engine ATR** — the documented **Wilder-seeding / `InpAtrMt5Mode` caveat**
  ([[parity-findings-front-half]], [[atr-percentile-parity-wall]], `snapshot.hpp:159-165` forming Wilder step).

## ▶️ NEXT ACTION — make `cache.atrM1` MT5-faithful, THEN re-measure exits
1. **Tie out `s.atrM1` to MT5's `iATR(14)` shift-0** (the forming Wilder step). Diagnostic: dump engine
   atrM1 per entry-bar vs MT5 `trace.csv` `atr` column (joined by ts−60000); the floor/cap bind cases are
   where they diverge. Adopt the MT5 ATR mode/seeding (the `InpAtrMt5Mode` lesson). Target: `|Δrisk|`
   median 0.25→~0 on the 36 currently-tight trades; the 7 exact must STAY exact.
2. Also verify `recentHigh/recentLow` (entries.hpp recentHi/Lo) use `iHighest/iLowest(MODE,18,ENTRY_SHIFT)`
   with the SAME window+shift as Entry1.mqh:125 (a wrong/short window also tightens the stop).
3. **Re-run the 2yr E1 diff** — expect SL-WIN to jump toward 35% and Δpnl to collapse ONCE levels match,
   because the trail (volMult 0.7, origTPDist) is already correct and will then bind at MT5's geometry.
4. Only AFTER levels+exits tie out: re-enable `ENABLE_LOSS_COOLDOWNS=true` (occupancy/limiters) to collapse
   the 96 overfire / 32 missed (those are entry-count, unchanged this session: engine 149/142-windowed vs 78).

## 🔁 Repro (full 2yr, ~25s each)
```
cd cpp_core && make test                       # 29 checks, green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/e.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
# exit-tag dist + matched Δrisk characterization: ad-hoc python in this session's transcript.
# MT5 mechanism fires: gzcat <RUN>/tester.log.gz | grep -c "TRAILING SL"   (etc.)
```
Current diff: matched 46 / missed 32 / overfire 96; Δpnl median **51.15** (was 60.3); exit-tag
engine SL-WIN **11%** TP 32% SL-LOSS 36% EA 21%  vs  MT5 SL-WIN **35%** TP 21% SL-LOSS 28% EA 17%.

## 📦 Data / instruments
- Full 2yr XAU: `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv (5.17GB)}`.
- MT5 ref `research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/`:
  `trades.csv` (78), `kke1gate.csv` (554 PASS), `trace.csv` (291MB; has per-bar `atr` col), `tester.log.gz`.
- Ground-truth EA = `kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5` (+ `TradeManagement/TradeManager.mqh`,
  `Entries/EntryBase.mqh`). NOTE: dquants `mql5/experts/KenKem/` is the THIN KK-rewrite (Engine.mqh), NOT
  this EA — do not confuse them. Exit port spec: `research/hypotheses/KENKEM-EXIT-PARITY-SPEC.md`
  (its P1/P3 emphasis is now superseded by the log evidence above — TRAILING SL + SL-levels are the levers).

## 🧱 After E1→E5 parity LOCKED (user's explicit next phase)
Convert pip-denominated params to ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before — parity is
ground truth. See [[goal-pip-to-atr-relative]].
