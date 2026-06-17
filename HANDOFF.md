# HANDOFF — read me first, update me last

_Last updated: 2026-06-18 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, 28 C++ checks pass._
_Anchor = 2yr E1E2 (`research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/`). NOTE: that
reference run used E1_MAX_CROSS_AGE=80; we just changed the param to 28 (see below) so the reference is
now STALE for E1 parity — a fresh MT5 run at age=28 is needed to re-validate._

## 🎯 Current goal: Phase A6 — KenKem E1E2 parity gate
Repro (full 2yr ≈ 20s, 162M ticks). `KK_EMIT_AGE=1` adds per-fire `AGEFIRE,ts,dir,kind,age` to stderr:
```
cd cpp_core && make kenkem_tick
KK_EMIT_AGE=1 ./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --ticks tools/ticks_xauusd_2024_2026.csv --symbol-xau \
  --set ../research/kenkem_parity/anchor_E1E2.set --from-ms 1704067200000 --to-ms 1780272000000 \
  --out /tmp/e.csv 2>/tmp/age.log
~/miniforge3/envs/kenkem/bin/python research/kenkem_parity/diff_kk.py \
  --engine /tmp/e.csv --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/trades.csv
```

## ✅ DONE this session — E1_MAX_CROSS_AGE 80 → 28 (per user instruction, both codebases)
Set in: `cpp_core/.../kenkem_config.hpp:193`, `research/kenkem_parity/anchor_E1E2.set`, and the ORIGINAL EA
`kenkem/.../KenKem/Config/InputParams.mqh:303`. Effect on C++: E1 624→561 (only −63 — faster expiry makes
the engine RE-ARM more, 7289→8428 arms, largely offsetting). So the cap alone does NOT fix over-fire.
**ACTION FOR USER: recompile + re-run MT5 at age=28 to produce a fresh E1E2 reference for true parity.**

## 🔁 MAJOR RE-DIAGNOSIS this session — the HANDOFF's prior 2 leads were TRACE-TOOLING ARTIFACTS
Both "strongest leads" from last session are DEBUNKED (verified, do NOT re-chase):
1. **"trend_core disagreement (L_tcore cpp=6 vs mt5=0)" = INVALID COMPARISON.** The MT5 `BarTrace`
   `L_tcore` is populated inside **Entry5**'s detect (`Entry5.mqh:485`): `L_tcore=(bull&&!bear)?1:0` — E5's
   EMA-alignment gate (0/1). The C++ `trace_dumper` writes `trend_core_score` (E1 DI gate, 0–6). Two
   DIFFERENT gates. The whole trace's gate columns (L_pass/L_tcore/L_htf…) are **E5 semantics**, useless
   for E1/E2 diagnosis.
2. **"Pervasive DI drift = root cause" = 1-BAR TRACE LABELING ARTIFACT.** Empirical: `ema0` matches at
   shift 0 (mean|Δ|=0.0024) but `diP_m1/diM_m1/adx_m1` match at **shift +1 (mean|Δ|≈0.0001)** — exact
   parity once aligned. Cause: `trace_dumper` labels rows by the FORMING bar; the EA `BarTrace` labels by
   the shift-1 bar (`Entry5.mqh:534`). DI/ADX formula is EXACT. The real `tick_engine` reads DI at shift 1
   and EMA at shift 2 (`snapshot.hpp:106,124`), faithfully matching the EA (DI via `getDIPlus` series-shift1;
   EMA via the `GetEMA` non-series trap series-shift2). **Engine indicators are faithful. Stop chasing DI.**

## 🧭 The REAL problem — E1 entry SELECTION is desynced, NOT "late firing"
Per-fire age instrumentation (`KK_EMIT_AGE=1`) + `diff_kk` matching (E1, age-80 baseline 624 vs MT5 183):
- **86 matched / 97 MISSED / 538 OVERFIRE.** Engine simultaneously misses HALF of MT5's real E1 trades
  AND adds 538 spurious ones — they fire at largely DIFFERENT bars.
- **Over-fire is NOT late-firing:** MATCHED engine trades skew HIGH age (median 24, 50/86 at age 21–80);
  OVERFIRE trades lean LOW age (median 7, 124 at age 0–1). So clamping max-age kills REAL matches while
  keeping spurious low-age fires — the old "AGE sweep lever" hit the right COUNT for the WRONG reason.
- Overfire is **net-losing** (40% win, −$1307) vs MT5 E1 (56% win, +$3069); spread in time (median gap
  1.8 days — NOT a re-entry storm / cooldown issue).
- ⚠️ **matched-COUNT is an unreliable metric** (it fooled the AGE sweep AND likely the earlier
  "EMA-shift rejected 155→130"). Always judge by matched **+ missed + overfire + pnl**, not count alone.

## 🚨 STRONGEST LEAD now — E1 ARMING-BAR divergence (touch vs cross), with MT5 ground truth in hand
MT5 tester.log (`tester.log.gz`, **UTF-16**) logs arm events directly:
`gunzip→decode utf-16, regex "(\d4.\d2.\d2 \d2:\d2):\d2\s+\[EMA200 Touch\] (Bull|Bear)ish"`.
- **MT5 arms E1 almost entirely via EMA200-TOUCH: 7987 touch-arms logged** (4686 bull + 3301 bear),
  ~0 cross-arm lines (cross arming has no Print). 7119 "Expired stale" + 183 fires reconcile.
- Offset is **UTC+0** (log bar-times already UTC): 142/183 MT5 fires reconcile to a same-dir touch-arm at
  age 0–80 (median age **40** — MT5 ALSO fires late, so late-firing is normal). The other ~41 fires are
  cross-armed (recent). So MT5 E1 ≈ **78% touch-armed, 22% cross-armed**.
- The ENGINE **under-touch-arms** (3687 touch vs MT5 7987) yet over-fires — i.e. it leans on CROSS arming
  (3806) the EA barely uses, AND its touch arming fires on different/fewer bars.
- **Artifact saved:** `research/kenkem_parity/mt5_runs/RUN_.../mt5_e1_touch_arms_utc.csv` (7987 rows
  ts_ms,dt,dir) — MT5's actual touch-arm bars, ready to diff against the engine's.

## ▶️ NEXT ACTION (exact, priority order)
1. **Compare engine vs MT5 E1 touch-arm BARS directly.** Add a per-source tag to the engine's touch-arm
   emission WITH consumption (the real engine, not the consumption-free `e1_arm_dumper`), then bar-by-bar
   diff vs `mt5_e1_touch_arms_utc.csv`. Likely an EMA200 read-SHIFT difference: EA reads
   `ema200=GetEMA(...,ENTRY_SHIFT)` (non-series trap → series-shift2) but bar low/high at
   `iLow(...,ENTRY_SHIFT)` (series-shift1); the C++ `triggers.hpp` touch (lines 86–98) reads BOTH ema200 and
   low/high at `m1s1=B-1` (series-shift1). Fix the EMA200 shift to the trap shift and re-diff.
2. Audit the CROSS arming shift (`triggers.hpp:64–84`): EA uses `isEMAsReadyForEntry(...,1)`/`(...,2)` =
   `GetEMA` trap (series-shift2/3); C++ uses `emas_ready(s, B-1, B-2)` (series-shift1/2). Re-test the
   trap-shift with the QUALITY metric (matched/missed/overfire/pnl), NOT matched-count.
3. Once arm bars align, re-check the missed/overfire split. Only then revisit exits (A7) + cooldowns.

## 🧰 Tooling added this session
- `KK_EMIT_AGE=1` → tick backtester emits `AGEFIRE,ts_ms,dir,Ekind,age` per fire (EntrySignal.age, set in
  `entries.hpp:288`; printed in `tick_engine.hpp`). Non-regressive (diagnostic field, env-gated).
- `cpp_core/tools/kenkem/e1_arm_dumper.cpp` (compile: `clang++ -std=c++20 -O2 -Iinclude
  tools/kenkem/e1_arm_dumper.cpp -o build/kenkem/e1_arm_dumper`) — dumps E1 arm transition bars
  (CONSUMPTION-FREE → undercounts; for the bar-diff in NEXT-1 make it consumption-aware / source-tagged).

## 🔑 Key facts / gotchas
- Full 2yr run FAST (~20s). Tick engine only for P&L. `anchor_E1E2.set` = MT5 config (now E1 age=28).
- Data: `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` (3-digit gold).
  from/to ms = 1704067200000 / 1780272000000.
- tester.log.gz is **UTF-16** (Python `gzip.open(...,'rb').read().decode('utf-16')`; shell `grep -a`).
- Engine indicators (EMA/ADX/DI) are MT5-EXACT — divergence is in ENTRY logic (arming/gates), not numbers.

## 📚 Durable refs
`docs/BUILD-PLAN.md` · `research/kenkem_parity/CPP_VS_MQL_FAITHFULNESS_AUDIT.md` ·
`INDICATOR_PARITY_SPEC.md` · memory [[kenkem-clean-rewrite-2026-06]], [[kenkem-e1-overfire-trendcore]].
