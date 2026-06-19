# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, C++ tests PASS (28).
Data 98.45% complete. **E1 + E2 entry parity now BOTH ~93–96% recall** after the cross-age fix below.
The prior HANDOFF's "E1 50% / sideways over-block is the culprit" was WRONG — see ▶️ THIS SESSION._

## 🎯 Goal: KenKem entry parity engine⇄MT5. E1+E2 recall now solved; residual = OVERFIRE.
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
