# HANDOFF — read me first, update me last

_Last updated: 2026-06-18 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, 28 C++ checks pass._
_Anchor = 2yr E1E2 (`research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/`)._

## 🎯 Current goal: Phase A6 — KenKem E1E2 parity gate (BUILD-PLAN.md)
Baseline (reproduced exactly): **155/325 matched**, E1 624 vs MT5 183 (3.4× over), E2 190 vs 142.
Repro (full 2yr run ≈ 20s, 162M ticks):
```
cd cpp_core && make kenkem_tick
./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --ticks tools/ticks_xauusd_2024_2026.csv --symbol-xau \
  --set ../research/kenkem_parity/anchor_E1E2.set --from-ms 1704067200000 --to-ms 1780272000000 --out /tmp/e.csv
~/miniforge3/envs/kenkem/bin/python research/kenkem_parity/diff_kk.py \
  --engine /tmp/e.csv --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/trades.csv
```

## 🔬 DECISIVE DIAGNOSIS this session — over-fire ROOT CAUSE localized
The E1 over-fire (3.4×) is **the armed trigger firing LATE within its 80-bar window**, NOT a gate
threshold and NOT ATR. Proof + ruled-out list:
- **AGE sweep is the lever:** `E1_MAX_CROSS_AGE` 80→576 fires, 20→502, 5→341, **1→154** (≈MT5 183).
  So the engine arms a trigger, the strong-trend gates eventually all pass on *some* bar in the window,
  and it fires — ~3× more often than MT5 per arm.
- **Arming is too frequent:** engine arms E1 ~7289× (cross 3806 + EMA200-touch 3687). MT5 arms far fewer
  (concrete proof: on 2024-01-15 MT5's E1 trigger EXPIRED at 00:07 and never re-armed all day, yet the
  engine fired L-E1 at 05:50). Both arm sources over-fire ~equally.
- **RULED OUT (don't re-investigate):**
  - ATR-percentile gate WORKS/binds hard (E1 2722→624 when ON). Not the lever.
  - Conviction NOT binding — even thr=11 leaves E1 466; MT5 log shows conviction rejects **0.0%** too.
  - Trend-quality NOT binding (tq=10 → 464). Both conviction+TQ are inflated to near-max but that's not
    the over-fire (MT5 also passes them).
  - pip_size: data is 3-digit gold (EA pipSize=0.001) but engine 0.01 — tested 0.001, **no effect** on
    over-fire and slightly worse match (SL is structure-dominated, pip-insensitive). Left at 0.01.
  - **EMA-shift (B2) hypotheses tested & REJECTED:** moving trigger EMA reads B-1/B-2→align-2/-3 AND
    gate `emas_ready_entry` align-3→align-2 both **worsened** match (155→130). The current shifts
    (gate align-3, trigger B-1) are the known-good ones — do NOT change them again without per-bar EMA
    evidence.

## 🧰 MT5 ground-truth rejection histogram (from tester.log.gz — THE map of which gate to match)
Extract: `gunzip -c .../tester.log.gz | LC_ALL=C grep -aA60 "Shows why entry attempts were rejected"`.
**E1 LONG (51160 rej): HTF Trend 58.1%, MTF/EMA 31.2%, Momentum 4.3%, TrendQuality 1.3%, Conviction 0%.**
HTF is MT5's dominant E1 filter — but in the engine it's REDUNDANT with the MTF gate (E1 count is
insensitive to `E1_HTF_MIN_ADX`/`DI` even at 0, because fired entries are already M5-aligned). So the
over-fire is the per-armed-bar pass-rate of the EMA-stack/MTF/price structural gates being ~3× MT5's.

## ▶️ NEXT ACTION (exact)
The remaining lever is **why the engine's structural gates (EMA-stack alignment / MTF / price-vs-EMA)
pass on ~3× more armed bars than MT5**, and **why it arms ~3-6× more**. To crack it you need MT5's
per-bar EMA/DI values to diff against the engine on specific armed-but-MT5-didn't-fire bars:
1. The E1E2 run's `trace.csv` (291MB, E5 bar-trace) OR re-run the EA with the bar trace; join
   `cpp_ts-60000 == mt5_ts`. Pick a day the engine over-fired (e.g. 2024-01-15 05:50 L-E1) and compare
   the EMA25/75/100/192 + M5 DI the engine sees vs MT5 at that bar — find which input diverges enough to
   flip the EMA-stack/MTF gate. That single divergence likely explains both the extra arming AND the
   extra late fires.
2. Also worth: split-test disabling EMA200-touch arming (engine arms 3687 via touch) — quantify how much
   of the over-fire is touch vs cross, then verify each against MT5's actual touch events in the log.

## ✅ Landed this session (commit pending) — NON-REGRESSIVE, baseline preserved at 155/325
- **Loss-cooldown port** (faithful `UpdateLosingStreak`: global escalating `losingStreakBlockUntil` +
  per-(kind,dir) 60-min consec-loss block, `RiskManager.mqh:20-160`) in `tick_engine.hpp`. **Default OFF**
  (`ENABLE_LOSS_COOLDOWNS=false`) — it depends on per-trade WIN/LOSS outcomes, and exits aren't yet
  MT5-faithful (A7), so with current exits it blocks REAL matches too (155→137). Turn ON only after exits
  tie out. Config: `losing_streak_escalation_thr`, reuses `max_consec_losses_type`/`consec_loss_block_mins`.
- **Arming diagnostics** in the tick backtester: `ARM events: E1 N (cross C, touch T)  E2 M`.

## 🔑 Key facts / gotchas
- Full 2yr run is FAST (~20s). Iterate freely. Tick engine only for P&L.
- `anchor_E1E2.set` = the exact MT5 config. Data: `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv,
  ticks_xauusd_2024_2026.csv}` (3-digit gold). from/to ms = 1704067200000 / 1780272000000.
- MT5 logs per-bar `[E1] ... blocked: <reason>` lines AND end-of-run rejection histograms — the richest
  parity signal available; mine `tester.log.gz` before adding instrumentation.
- diff tool: `research/kenkem_parity/diff_kk.py` (greedy nearest-entry within same dir+kind, 5min lag).

## 📚 Durable refs
`docs/BUILD-PLAN.md` (Phase A→D plan) · `research/kenkem_parity/CPP_VS_MQL_FAITHFULNESS_AUDIT.md` ·
`INDICATOR_PARITY_SPEC.md` · memory [[kenkem-clean-rewrite-2026-06]].
