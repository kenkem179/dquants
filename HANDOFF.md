# HANDOFF — read me first, update me last

_Last updated: 2026-06-18 (late) by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, all C++ tests PASS._

## 🎯 Goal: KenKem **E1 perfect parity** (then E2, E4, E5), engine ⇄ MT5. Ground truth = the EA.

## ✅ ROOT CAUSE of the E1 over-fire FOUND & FIXED — the EA EMA-buffer inversion ("the REAL trap")
The handoff's open question ("why does the engine cross-arm 3.5× MT5") is **answered**. It was NOT the gate,
NOT param-driven — it was an **un-ported MQL5 buffer quirk** in the E1 trigger.

### The bug (source-verified, EMAHelpers.mqh + GlobalState.mqh)
- `emaBuffers` is a **fixed** `double[NUM_TF*NUM_EMA][30]` (GlobalState.mqh:199), filled from a
  **non-series** `CopyBuffer` tempBuffer (EMAHelpers.mqh:28-35). Non-series ⇒ element **[0] = OLDEST**.
- With `ENTRY_SHIFT=1` (bufferSize=4), `GetEMA(shift)` is therefore **INVERTED**:
  `GetEMA(shift=1) → series bar 2 = B-2` (the "ready"/latch bar) ; `GetEMA(shift=2) → series bar 1 = B-1`.
- So the EA's E1 "just crossed up" = `!ready@shift2 && ready@shift1` = **`!ready@(B-1) && ready@(B-2)`**:
  alignment **present at the OLDER bar (B-2)** and **absent at the NEWER bar (B-1)** — i.e. it actually
  fires on an alignment **LOSS**, not a fresh chronological cross.
- The old engine trigger read the two bars in **natural order** (`ready@B-1`, `prev@B-2`) → a true
  chronological cross → **inverted vs the EA** ⇒ the ~3.5× cross over-arm. (The validated SIGNAL/gate path
  already reads single EMAs at B-2, so only the ARM/trigger path was wrong.) The old `KK_E1_EMA_TRAP`
  uniform-offset knob could never fix this — it's a **swap**, not an offset.

### The fix (`cpp_core/include/kk/kenkem/triggers.hpp`)
Models the inversion faithfully for BOTH the E1 EMA-cross and the EMA200-touch trigger:
`GetEMA(shift1)→B-2`, `GetEMA(shift2)→B-1`; touch reads ema200+alignment at B-2 but bar low/high at B-1
(iLow/iHigh are series, untrapped). Gated by **`cfg.e1_faithful_trigger` (default TRUE)**; CLI env
`KK_E1_FAITHFUL=0/1` overrides for A/B; synthetic engine-mechanics tests set it false (their clean-ramp
scenario can't arm a faithful cross — that path only fires on alignment-loss).

### Evidence (Feb-2026 XAU, the one reproducible window) — A/B
| run | E1 trades | cross-arms | touch-arms |
|---|---|---|---|
| legacy `KK_E1_FAITHFUL=0` | 15 | 129 | 76 |
| **faithful (default)** | 3 | **40** | **105** |
| **MT5 ground truth** (20260617.log `[EMA200 Touch]`) | — | (low) | **105** |
**Touch arms match MT5 EXACTLY (105 = 105)**; 78/105 exact-minute + 4 within ±1min on timestamps (remaining
~23 are large-delta, explained by E1-only engine vs E1+E2+E4 MT5 latch-consumption mismatch). The fix
corrects **both** sides the handoff flagged (cross over-fire ↓, touch under-fire ↑) in one change.

**Scale check** (2425 window ≈ 2024-12→2025-07, no MT5 ref but directional): legacy 104 E1 trades / 860
cross / 439 touch → faithful **19 / 304 / 616**. The 5.5× trade collapse matches the full-2yr 6.5× over-fire
signature (511 vs 78) → strong evidence the same fix closes the 2yr gap.

### ▶️ NEXT ACTION — confirm on the full E1-only 2yr run, then lock
The decisive Feb-2026 check is arm-level (touch 105=105). To close trade-level parity, **regenerate the
full 2yr E1-only MT5 + engine run** (the old `bars/ticks_xauusd_2024_2026*` and the
`RUN_..._E1only_trace/{trades,kke1gate}.csv` were cleaned — only `tester.log.gz` survives) and confirm the
old **511 → ~78** collapses with `e1_faithful_trigger` on. If trade-level still diverges, the residue is
downstream of the arm (gate/limiter/exit), not the trigger. Then mirror the same swap into the MQL5 port?
**NO** — the EA already has the (buggy) behavior; the engine now matches it. Parity = keep both as-is.

## 🔁 Repro (Feb-2026, ~30s; full 2yr needs regenerated data)
```
cd cpp_core && make kenkem_tick && make test   # all green
FROM=1769904000000; TO=1772236800000           # 2026-02-01 .. 2026-02-28 UTC
KK_EMIT_ARMS=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2026_m1.csv --ticks tools/ticks_xauusd_2026_window.csv \
  --symbol-xau --spread 0.05 --from-ms $FROM --to-ms $TO \
  --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/e.csv 2>/tmp/arm.txt
grep -c cross /tmp/arm.txt; grep -c touch /tmp/arm.txt   # 40 / 105 (faithful) ; set KK_E1_FAITHFUL=0 -> 129/76
# MT5 touch ground truth:
grep -c 'EMA200 Touch' ../../kenkem/Tester/Agent-127.0.0.1-3000/logs/20260617.log   # 105
```

## ✅ M1/M3/M5/M15 DATA INTEGRITY RE-VERIFIED on this machine (2026-06-18) — safe to proceed
Reproduced the prior agent's bar-parity check here AND extended it to M3/M5/M15 explicitly (not just M1),
via `trace_dumper` vs the MT5 per-bar traces with `tools/kenkem/diff_kenkem_trace.py`.
- **paritywin** (2025-03..05, 82,112 common bars): close bit-exact on **82,109/82,112**; only 3 desync bars
  = 00:00 on 2025-05-01 / 03-31 / 05-19 (holiday/month-end tick-export holes). **MTF proof:** every bar where
  adx_m1/m3/m5/m15 or diP/diM drifts >1.0 is on a hole-day — **ZERO drift on any normal day** ⇒ the UTC-epoch
  bucket aggregation (`aggregate()` in tick_backtester.cpp, `ts_ms/w*w`) is correct.
- **Feb-2026** (27,379 bars): close/EMA(all)/ADX/DI on M1/M3/M5/M15 mean|Δ|≈0.0003, **0 bars >1.0, no holes —
  fully clean** (this is why E1 work used it).
- **ONE caveat — ATR:** drifts even where OHLC is bit-exact (Feb max|Δ|=12.1, ~2% typical, worst at run's
  first bars). NOT a bar-data bug — Wilder ATR seeding/mode diff (known `InpAtrMt5Mode`,
  [[parity-findings-front-half]]); converges after warmup. Resolve when locking ATR-based SL/gates.
- Repro: `./build/kenkem/trace_dumper --bars-m1 tools/bars_xauusd_2026_m1.csv --symbol-xau --spread 0.05
  --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/cpp_trace_feb.csv` then diff vs
  `research/kenkem_parity/mt5_runs/RUN_2026-06-17_1.8.154_xau_feb/parity_trace.csv`.
- Production question raised by user: EA showed **1 trade/week live** vs ~6/week in the Feb backtest (E1+E2+E4,
  24 exec/mo, 78% of signals SKIPPED). NOT the buffer bug (it's in every backtest too) and NOT "C++ doing
  better" (more trades was the over-fire bug; the over-firing version was LESS profitable). Likely config drift
  / live spread / quiet regime. To diagnose: need production input set + a week of Experts-log block reasons.

## 📦 Data reality (CHANGED since last handoff)
- The full 2yr `tools/{bars,ticks}_xauusd_2024_2026*` and the E1-only-trace `trades.csv`/`kke1gate.csv`
  are **gone** (large+gitignored, cleaned). Available XAU: `bars_xauusd_2026_m1.csv` +
  `ticks_xauusd_2026_window.csv` (covers Feb-2026), plus 2425 / 2025h1 / 2025 windows.
- MT5 ground truth still on disk: `kenkem/Tester/Agent-127.0.0.1-3000/logs/20260617.log` — a **Feb-2026
  E1+E2+E4** run (NOT E1-only; not the handoff's E1-only 2yr). Has 105 `[EMA200 Touch]` timestamped arm
  events + `cross expired (age=N)` lines (arm_bar = expiry − N) for cross-arm reconstruction.
- Engine arm instruments: `KK_EMIT_ARMS` (ARMFIRE,ts_ms,L|S,cross|touch,tfbits), `KK_EMIT_ARMSTATE`,
  `KK_EMIT_GATE`, `KK_EMIT_GATE_REASON`. A/B: `KK_E1_FAITHFUL` (or `cfg.e1_faithful_trigger`).

## 🧱 After E1→E5 parity is LOCKED (user's explicit next phase)
Convert pip-denominated params to ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before — parity is
ground truth. See memory [[goal-pip-to-atr-relative]], [[kenkem-e1-overfire-trendcore]],
[[kenkem-e1-ema-buffer-inversion]].
