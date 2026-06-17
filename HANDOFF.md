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

## 🚨 STRONGEST LEAD (found via trace diff) — pervasive DI drift corrupts every DI-gate
Ran the per-bar trace diff (engine `trace_dumper` vs MT5 `trace.csv`, 848k common bars):
```
cd cpp_core && make kenkem_trace
./build/kenkem/trace_dumper --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --symbol-xau \
  --set ../research/kenkem_parity/anchor_E1E2.set --from-ms 1704067200000 --to-ms 1780272000000 --out /tmp/eng_trace.csv
~/miniforge3/envs/kenkem/bin/python tools/kenkem/diff_kenkem_trace.py /tmp/eng_trace.csv \
  research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/trace.csv [--dump "YYYY.MM.DD HH:MM"]
```
Result: **EMAs bit-exact** (ema mean|Δ|=0.0024 ✓). **ADX near-exact** (adx_m1 mean|Δ|≈2 but worst at data
holes; at clean bars ~0.01). **BUT DI DRIFTS PERVASIVELY: diP_m1 mean|Δ|=3.12, diM_m1=3.09, diP_m3=1.02**
(worst single bars 10-13 pts). At the over-fire bar 2024-01-15 05:50: adx_m1 35.580 vs 35.571 (exact) but
**diP_m1 cpp 23.06 vs mt5 19.98** — and `L_tcore` cpp=6 vs **mt5=0**, `L_pass` cpp=1 vs **mt5=0**: the
engine's trend_core HARD GATE passes where MT5's fails. DI feeds trend_core, HTF, MTF, momentum, conviction
— a systematic 3-pt DI error makes the engine's DI-gates pass on far more armed bars → the late-firing
over-fire (consistent with the AGE sweep). **This is very likely THE root cause, above trigger timing.**

⚠️ CAVEAT — do NOT blindly "fix the DI formula": `kk::ind::dmi_adx_mt5` is independently **validated <0.005
vs the MT5 MasterVP parity CSV** (comment at indicators.hpp:140; matches MT5 ADX.mq5: per-bar 100·DM/TR
then ExponentialMAOnBuffer k=2/(n+1)). So the trace DI drift is likely **partly a trace-dump SHIFT artifact**
— DI is noisier than ADX, so a 1-bar offset between the engine `trace_dumper` DI column and the EA
`BarTrace` DI column inflates DI's |Δ| (3 pts) while the smooth ADX stays ~0. **VERIFY the DI column shift
on both sides FIRST.** The robust, shift-independent signal is the **gate-decision disagreement**:
`L_tcore` cpp=6 vs **mt5=0** at the over-fire bar. And note MT5's trend_core=0 there is NOT explained by
its OWN logged bullish DI (diP>diM on M1/M3/M5) — so MT5's GetTrendQualityScore core reads a shift/input
the trace columns don't expose. THAT is the thing to pin down.

## ▶️ NEXT ACTION (exact, priority order)
1. **Resolve the trend_core disagreement at 2024-01-15 05:50** (L_tcore cpp=6 vs mt5=0). First confirm the
   trace `diP_m1`/`adx_m1` SHIFT matches on both sides (compare a smooth EMA column you know is exact at
   the same row). Then figure out why MT5's GetTrendQualityScore core returns 0 with bullish DI — likely a
   required-direction or M15/MTF component the engine's `trend_core_score` (gates.hpp) computes too leniently.
   Use `diff_kenkem_trace.py --dump <dt>` on several over-fire bars to find the COMMON differing gate column.
2. Whatever gate is too lenient, tighten it to match MT5, re-run trade diff; expect E1 over-fire to drop
   (AGE-sweep late-firing self-resolves once the engine rejects the same armed bars MT5 does).
3. Only then revisit cooldowns (ENABLE_LOSS_COOLDOWNS on) + exits (A7).

Tooling note: engine per-bar trace = `build/kenkem/trace_dumper` (bar-based, no ticks, ~10s); diff =
`tools/kenkem/diff_kenkem_trace.py <cpp> <mt5> [--dump "YYYY.MM.DD HH:MM"]` (61-col schema, joins on `dt`).

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
