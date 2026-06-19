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

## 🟡 RESIDUAL = E1 overfire (67 full / 29 gap-free). E2 overfire 23/14.
- E1 overfire are NOT re-fires (only 5/68 within 80min of an MT5 E1). **56/68 are novel bars >8h from any
  MT5 E1** → engine gate-passes where MT5 never fired = unmodeled MT5 **execution-layer limiters**
  (the known wall: [[atr-percentile-parity-wall]], [[kenkem-e1-residual-is-intrabar-exec]] — MT5
  gate-pass ≫ fire). Engine's daily-loss/aggregate-risk limiters are STRUCTURALLY INERT; do not re-attempt
  the inert ports.
- **To resolve overfire needs USER:** one MT5 re-run at the E1E2 config (lot=0.15) dumping the per-armed-bar
  E1 gate+execution verdict (kke1gate-style) so the 56 novel overfire can be localized to the blocking
  layer. Without it we can only confirm the engine over-passes, not which MT5 limiter stops it.

## ▶️ NEXT ACTIONS (in order)
1. **[committed this session]** `E1_MAX_CROSS_AGE=80` in `anchor_E1E2.set`. Note: `kenkem_config.hpp:199`
   default stays 28 (live-trading optimization) — parity is driven by the `.set`, leave the default.
2. **[USER]** MT5 E1E2-config gate/execution trace (above) → localize the 56 novel E1 overfire.
3. E4/E5 parity still blocked — **no E4-only or E5-only MT5 reference run committed**; need a user MT5
   E4 (and E5) run before either can be measured.
4. After E1→E5 LOCKED: pip→ATR-relative conversion per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before.

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
