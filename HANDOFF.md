# HANDOFF — read me first, update me last

_Last updated: 2026-06-18 (latest) by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, 28 C++ checks PASS._

## 🎯 Goal: KenKem **E1 perfect parity** (then E2, E4, E5), engine ⇄ MT5. Ground truth = the EA.

## ✅ BUFFER-INVERSION FIX **CONFIRMED AT FULL 2yr SCALE** — the over-ARM problem is solved
The prior handoff's open next-action ("confirm 511→~78 on the full E1-only 2yr run") is **DONE and POSITIVE**.
The 2yr data was NOT gone — `tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` (5.17GB) and
the full MT5 reference `RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/{trades,kke1gate,trace}.csv` are all on
disk. Re-ran both legs:

| run (full 2yr, E1-only, `anchor_E1_only_trace.set`) | engine | matched | missed | **overfire** | arm cross / touch |
|---|---|---|---|---|---|
| legacy `KK_E1_FAITHFUL=0` | 511 | 46 | 32 | **465** | 4065 / 2220 (INVERTED) |
| **faithful (default)** | 142* | 46 | 32 | **96** | **1385 / 3043** |
| **MT5 ground truth** | 78 | — | — | — | ~1174 / ~3146 |

\*142 = windowed-to-MT5-span (149 raw). **The fix cut over-fire 4.8× (465→96) and corrected the cross/touch
arm split to match MT5 almost exactly.** matched(46)/missed(32) are IDENTICAL legacy↔faithful ⇒ it's a **pure
precision fix** — it kills spurious arms without touching which real trades fire. Diff tool:
`research/kenkem_parity/diff_kk.py` (windowed, +60s-offset aware). Fix lives in
`cpp_core/include/kk/kenkem/triggers.hpp` (gated `cfg.e1_faithful_trigger`, default TRUE; `KK_E1_FAITHFUL=0`
reverts). Already committed (355cf19). **No code changed this session — confirmation + decomposition only.**

## 🔬 The residual 96 overfire + 32 missed — DECOMPOSED (vs MT5 `kke1gate.csv`, `/tmp/decomp.py`)
- **OVERFIRE 96** = 10 over-arm (no MT5 arm) · **23 gate-leak** (mtf 20, price_pos/trend_strength/trend_quality 1 ea) · **63 "MT5 gate-PASS but fired NO trade"**.
- **MISSED 32** = ALL 32 are MT5 gate-**PASS** bars the engine under-fired (0 block, 0 no-arm).
- The legacy diagnosis was "85% spurious over-ARM"; after the fix **over-arm is essentially gone (10 left)**.

### ⭐ KEYSTONE = EXIT FIDELITY, not trigger and not the gate. The MT5 post-gate funnel proves it:
**MT5 gate-PASS on 554 bars → only 78 trades fire** (a 7:1 suppression layer AFTER the per-bar gate). The
engine converts 142 of those passed arms (vs MT5's 78) because its post-gate suppression is weaker. That
layer is **position-occupancy + account limiters**, and both hinge on exits matching MT5:
- The loss-cooldown limiter **is already ported** (`tick_engine.hpp:227-360`) but **disabled by default**
  (`enable_loss_cooldowns=false`, kenkem_config.hpp:58-61) because it needs faithful per-trade WIN/LOSS.
  **A/B confirmed: flipping `ENABLE_LOSS_COOLDOWNS=true` moved overfire only 96→95** — useless until exits tie out.
- Matched trades already diverge on exit: **|ΔpnlUSD| median 60.3 / max 237**, **exitTag mismatch on 18/46**
  (e.g. cpp=TP vs ref=SL-WIN), |Δrisk(SL)| median 0.25. So engine hold-windows ≠ MT5 hold-windows ⇒ the
  engine is free to re-enter on passed arms where MT5 still holds a position ⇒ the 63 "PASS-but-no-trade".

### ▶️ NEXT ACTION — make E1 exits MT5-faithful (the "A7" exit work), THEN re-enable limiters
1. Tie out exit mechanics on the 46 matched trades first (exitTag + Δpnl + Δrisk → ~0). Suspects: SL/TP
   trigger order, forming-bar exit timing, BE/trail, partial-close. Use matched-pair list from diff_kk.
2. Once exits match, re-run with `ENABLE_LOSS_COOLDOWNS=true` and verify the 63 PASS-but-no-trade collapse
   (position-occupancy now aligns) and the 32 missed resolve. Expect engine→~78.
3. The 20-bar `mtf` gate-leak is small and known ([[kenkem-e1-overfire-trendcore]] §9) — chase only after exits.
4. Do NOT touch the trigger/arm path or mirror anything into MQL5 — the EA already has the (faithful) behavior;
   the engine now matches it. Parity = keep both as-is.

## 🔁 Repro (full 2yr, each leg ~40s)
```
cd cpp_core && make kenkem_tick && make test          # 28 checks, green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/e.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
python /tmp/decomp.py    # overfire/missed decomposition vs kke1gate.csv (script saved in /tmp this session)
```

## ✅ M1/M3/M5/M15 DATA INTEGRITY VERIFIED (2026-06-18) — bars/EMA/ADX/DI bit-exact on normal days
Bar aggregation is correct (`aggregate()` in tick_backtester.cpp). Only desync = holiday/month-end tick
holes. **ATR caveat:** Wilder seeding/mode diff (`InpAtrMt5Mode`, [[parity-findings-front-half]]) drifts even
where OHLC is exact; converges after warmup; resolve when locking ATR-based SL/gates. Full repro in git
history (commit 8459947) if needed.

## 📦 Data reality (CORRECTED — prior handoff wrongly said 2yr data was gone)
- Full 2yr XAU present: `cpp_core/tools/bars_xauusd_2024_2026_m1.csv` (45MB) + `ticks_xauusd_2024_2026.csv`
  (5.17GB), plus 2026/2025h2/2425 windows. MT5 ref `RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/` INTACT
  (kke1gate.csv 55748 rows: 554 PASS / 55194 BLOCK; trades.csv 78; trace.csv 291MB).
- Engine arm instruments: `KK_EMIT_ARMS`, `KK_EMIT_ARMSTATE`, `KK_EMIT_GATE`, `KK_EMIT_GATE_REASON`.
  A/B knobs: `KK_E1_FAITHFUL` (trigger), `ENABLE_LOSS_COOLDOWNS` (.set key, limiter).

## 🧱 After E1→E5 parity is LOCKED (user's explicit next phase)
Convert pip-denominated params to ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before — parity is
ground truth. See [[goal-pip-to-atr-relative]], [[kenkem-e1-overfire-trendcore]], [[kenkem-e1-ema-buffer-inversion]].
