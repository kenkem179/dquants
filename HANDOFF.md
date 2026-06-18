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
- ⚠️ **CORRECTION:** `tester.log.gz` contains **3 concatenated tester runs** (input echo at 00:24/00:27/00:32),
  so the raw 7987 touch lines are inflated 3×. **Deduped: MT5 has 2761 unique touch-arm bars (L1619/S1142).**
  The saved `mt5_e1_touch_arms_utc.csv` already de-dups to 2761 (set-keyed).

## 🧪 ROUND-2 (this session, age=80 to match MT5) — touch-arm shift & wick hypotheses REJECTED
Built consumption-aware engine arm emit (`KK_EMIT_ARMS=1` → `ARMFIRE,ts,dir,src{cross|touch}`) and
bar-matched vs MT5's 2761 touch arms (engine run on `/tmp/anchor_age80.set`, src-split: cross 3704, touch 3585):
- Engine **over**-touch-arms (3585 vs 2761, +30%); exact-bar overlap only **~72%** (L 74%, S 69%).
- **EMA200-touch read-SHIFT REJECTED:** `KK_TOUCH_SHIFT` sweep 0/1/2 moves overlap only 72→73→75% — NOT
  the cause. Do not change the touch shift.
- **Wick-fidelity REJECTED:** engine M1 `close/high/low` match MT5 to **0.0000** (at the +1 trace label
  shift; raw 0.74 was the same labeling artifact as DI). Bars are exact.
- **E1 HTF filter is a faithful 1:1 port** (EA enum `HTF_TREND_MODE` == engine `HtfMode`; mode 1=M5_ONLY;
  block-counter logic matches). Not the divergence.
- **Net:** bars + indicators + E1 gates + arming LOGIC are each individually faithful, yet entry sets still
  diverge (86/183 matched). The residual must be **stateful trigger COUPLING** — guard (`==-1`) +
  consumption + expiry + intra-bar arm/fire ORDERING — where small timing diffs compound the trigger state
  apart. The 72% touch overlap is largely DOWNSTREAM of this (different fire/expiry history → different bars
  eligible to arm), not an independent root.

## 🎯 ROUND-3 (this session) — OVER-FIRE DECOMPOSED via MT5 arm-bar reconstruction (DECISIVE)
Reconstructed MT5's true E1 arm bars from `tester.log.gz`: expiry lines (`Expired stale … age N`) give
`arm_idx = expiry_idx − N` (recovers the UNLOGGED cross-arms) + touch arms + fire bars → 2143 L / 1620 S.
Method validated: **97% of MATCHED engine trades** sit on a reconstructed MT5-armed bar (control). Then:
- **68% of the 538 OVERFIRE trades fire on a bar where MT5 had NO armed E1 trigger** (age≤80, same dir) →
  the engine ARMS where MT5 does not.
- **32% fire where MT5 WAS armed but did NOT fire** → a SILENT gate block (MTF 31% / momentum / RSI-div —
  these use `TrackEntryAttempt` with NO per-bar Print; only HTF & ADX are logged per-bar) or occupancy.
- **Mechanism = feedback loop:** the engine fires on the 32% "seed" bars (MT5 armed, silent gate blocks it)
  → consumes+clears the trigger → re-arms sooner → fires again → manufactures the 68% spurious-arm bars.
  (Confirmed: HTF is NOT the leak — 0% of overfire bars are MT5 HTF-block bars; engine HTF is faithful.)

## ▶️ NEXT ACTION (exact, priority order)
1. **Kill the 32% SEED: find the silent gate MT5 uses on armed-but-not-fired bars.** Build an E1-semantics
   per-bar gate trace (mirror the E5 `trace_dumper` but with `entry_gate_ok(kind=1)` sub-decisions:
   `emas_ready_entry`/`m5_directional`, price, `has_sufficient_momentum`, RSI-div). For the subset of overfire
   bars that ARE on an MT5-armed bar (the 32%), see which engine E1 gate passes that MT5's must fail. Prime
   suspect = `isAllTimeframeEMAsReadyForEntry` (MTF, 31% of MT5 rejections): re-examine `emas_ready_entry`'s
   `align_tf−3` shift with PER-BAR EMA evidence (NOT matched-count — it's unreliable, see ROUND-1/2).
2. Then the 68%: once the seed is fixed, re-measure — the fire→re-arm feedback should shrink arming toward
   MT5's. If residual spurious arming remains, audit the cross-arm geometry (`triggers.hpp:64–84`) vs the
   reconstructed MT5 cross-arm bars (now available from expiry reconstruction).
3. Only after entry timing ties out: exits (A7) + cooldowns.

Reusable: MT5 arm-bar reconstruction (expiry+touch+fire) is the key instrument — re-derive in Python from
`tester.log.gz` (UTF-16) as above; `diff_kk.match()` gives matched/missed/overfire splits.

## 🧰 Tooling (all env-gated, non-regressive — default OFF reproduces baseline E1 624)
- `KK_EMIT_AGE=1` → tick backtester emits `AGEFIRE,ts_ms,dir,Ekind,age` per fire (EntrySignal.age).
- `KK_EMIT_ARMS=1` → emits `ARMFIRE,ts_ms,dir,src{cross|touch}` per E1 arm WITH consumption
  (`tick_engine.hpp` `on_bar_closed_`). This is the consumption-aware arm dump (use over `e1_arm_dumper`).
- `KK_TOUCH_SHIFT=N` → offsets the EMA200/alignment read in the touch arming (`triggers.hpp:86`); sweep
  showed flat overlap → keep 0.
- `cpp_core/tools/kenkem/e1_arm_dumper.cpp` — standalone consumption-FREE arm dumper (undercounts; prefer
  `KK_EMIT_ARMS`).
- MT5 touch-arm extraction (UTF-16, de-dup 3 runs): `gzip.open(...,'rb').read().decode('utf-16')` + regex
  `(\d4.\d2.\d2 \d2:\d2):\d2\s+\[EMA200 Touch\] (Bull|Bear)ish` → set-key (ts,dir).

## 🔑 Key facts / gotchas
- Full 2yr run FAST (~20s). Tick engine only for P&L. `anchor_E1E2.set` = MT5 config (now E1 age=28).
- Data: `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` (3-digit gold).
  from/to ms = 1704067200000 / 1780272000000.
- tester.log.gz is **UTF-16** (Python `gzip.open(...,'rb').read().decode('utf-16')`; shell `grep -a`).
- Engine indicators (EMA/ADX/DI) are MT5-EXACT — divergence is in ENTRY logic (arming/gates), not numbers.

## 📚 Durable refs
`docs/BUILD-PLAN.md` · `research/kenkem_parity/CPP_VS_MQL_FAITHFULNESS_AUDIT.md` ·
`INDICATOR_PARITY_SPEC.md` · memory [[kenkem-clean-rewrite-2026-06]], [[kenkem-e1-overfire-trendcore]].
