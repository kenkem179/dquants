# HANDOFF — read me first, update me last

_Last updated: 2026-06-20 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN._

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
- **▶️ IN PROGRESS — sweeps (task #2):** harness `research/mastervp_parity/sweep.py` (Calmar=net/maxDD, gated
  n & PF>1). Train window `cpp_core/tools/ticks_xau_train.csv` (2025-06-19→2026-01-31, ~8s/run, page-cached);
  OOS `ticks_xau_oos.csv` (2026-02→05). **S4 trail sweep result:** chandelier **trail beats fixed-TP2** →
  PF 0.997→**1.046**, net −644→**+13.4k**, with **trail_atr_mult≈2.0 + sl_atr_brk=1.0** (tighter SL dominates
  1.48/2.0 everywhere). BUT maxDD still **~53%** → needs S6 risk layers. Refining sl∈[0.6..1.2]×trail next,
  then S1 entry filters (break_buf/adx/di), then S6 DD/streak limiters, S7 walk-forward, S9 lock, S10 EA.
- **Data:** combined bars `cpp_core/tools/bars_xauusd_2025_2026_m3.csv`; full ticks `ticks_xauusd_2024_2026.csv`
  (5.2GB); train/oos cuts above. TV log: `~/Downloads/KK_-_Master_VP_OANDA_XAUUSD_2026-06-20.csv`.

---

## 📌 PAUSED — KenKem E1–E5 parity (resume after MasterVP, or if user redirects)
_E5 (SuperBros): fixed E5 entry onset off-by-one (committed `d1704ab`) → matched 295→399, exact-minute
66→342, |Δentry| 0.286→0. NEXT KenKem BLOCKER = E5 EXIT parity (engine net −489 vs MT5 +733). E1+E2 entry
parity ~93–96%. C++ tests PASS (28)._

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
