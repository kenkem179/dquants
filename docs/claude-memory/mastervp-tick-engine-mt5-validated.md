---
name: mastervp-tick-engine-mt5-validated
description: "KK-MasterVP C++ TICK engine is MT5-validated (signal exact, 7/10 trades) — supersedes the \"nothing validated\" notes"
metadata: 
  node_type: memory
  type: project
  originSessionId: a534af7c-bf6c-4d84-b8bc-787d0a44cd72
---

On 2026-06-15 the C++ KK-MasterVP **tick** engine (`cpp_core`, TickEngine) was validated against
a real MT5 "every tick based on real ticks" run (BTCUSD-Exnes-0406 M3, 2026-06-01..08, preset =
`cpp_core/tools/btc_ref_run.set`). This is the first true tick-engine vs MT5 confirmation and
**supersedes [[kenkem-bar-engine-invalid]] and [[mt5-reality-all-three-fail]] for MasterVP** (those
were the bar-OHLC engine / period-dependent runs).

Result — **PASS at logic level**:
- **Signal/strategy logic = EXACT parity**: all 10 MT5 entry bars compute identical
  sigValid/sigLong/entry/regime/adx in C++. Bar math (VP/ADX/DI/body/regime) matches MT5 to rounding.
- **Trades = 7/10 fill identically** (same dir+exit). Authoritative count comes from the engine's
  own gate trace, NOT the A/B agent's `trades_cpp_ema.csv` (that file was buggy — dropped the 00:30 &
  01:45 fills — and wrongly reported 5/10).
- **The 3 misses share ONE cause**: the `ATR% band` gate (`InpMaxAtrPct=0.158`). On 3 volatility-spike
  bars C++ ATR runs 3–15% high (the bar-construction caveat), tipping atr% just OVER 0.158 while MT5's
  sits just under → MT5 takes them, C++ vetoes. Proven via the gate log + per-bar atr% straddle.

Key mechanics learned:
- **MT5 iATR ≈ EMA k=2/(n+1), not textbook Wilder** — same trap as [[kenkem-parity-traps]] iADX.
  Added `kk::ind::atr_mt5` + Params `atr_mt5_mode` / set key `InpAtrMt5Mode` (default false, routes
  tick_engine.hpp:138 + parity_runner.hpp:67). EMA cut ATR median bias +1.7%→+0.4% and killed 2 false
  breakouts. **Adopt `InpAtrMt5Mode=true` as default.** It does NOT recover the 3 ATR%-cap misses.
- **The C++ engine is already instrumented**: `TickEngine::set_debug_window()` (env vars
  `KKVP_DBG_FROM`/`KKVP_DBG_TO` on the mastervp backtester) prints `[gate] <time> <L/S> -> BLOCK: <reason>`
  for every valid signal. This is THE tool to localize Level-2 trade divergences — use it first.
- Our dquants ticks == MT5 Exness feed to within 2 ticks for the window (same data; parity is real).
- Closing 7→10 needs spike-bar ATR to match MT5 → requires MT5 to also export bar OHLC from
  ParityExport.mqh (declined for now). Not needed to TRUST the engine for optimization/walk-forward.

Artifacts: `validation/mt5_parity_runs/RUN_2026-06_btc_m3/` (mt5_ref/, cpp_out/, PARITY_REPORT.md,
ATR_FIX_AB.md — note ATR_FIX_AB's 5/10 is wrong, real is 7/10). XAU run staged at
`RUN_2026-05_xau_m3/mt5_ref/` (XAUUSD-Exness-KK M3, 2026-05-19..26, 22 trades) — diff pending.
MT5 live terminal is PORTABLE mode at `…/Program Files/MetaTrader 5` (its MQL5/Experts/KK-MasterVP
is a SYMLINK to the kenkem repo, so editing+compiling kenkem source flows straight to the terminal).

XAU RESULT (2026-05-19..26, 22 MT5 trades): signal surface EXACT (VP/ADX/DI to rounding), atr1 ratio
median 1.006, sigLong 2/2250 disagree. **Trades 20/22 exact** (effectively 22/22 at signal level).
The 2 misses are NOT the ATR%-cap story — they're an EXIT-TIMING cascade on 2026-05-22 (MT5 holds a
short longer via the `EA` forced session/news close → different position-occupancy → C++ takes a
different next trade → trips loss-streak cooldown → blocks a later one) + one 2-bar-late atr1 straddle.
So BTC misses = ATR%-cap×spike-ATR; XAU misses = exit-layer forced-close timing. Both engines faithful.

BAR-OHLC EXPORT (DONE 2026-06-15, BTC re-run): ParityExport.mqh dumps barOpen/High/Low/Close/Ticks.
DECISIVE RESULT — our exported M3 bars are **BIT-IDENTICAL to MT5's**: high/low/close AND tick_count
match to 0.0 on every bar incl. the 3 spike bars (498/498, 544/544...). So the old "spike-bar bar-
construction caveat" is FALSE — the engine replays MT5's exact bars. The residual ATR diff is NOT bars
and NOT our smoothing: MT5's exported atr1 (=iATR(14)[1], AtrAt(1) in Regime.mqh:24) cannot be
reproduced by ANY batch Wilder/EMA of the identical bars — effective alpha swings 0.008→0.26 bar-to-bar,
self-recursion fails (2.8% within 0.1%). MT5's iATR is recomputed PER TICK in real-tick mode and sampled
mid-evolution = tick-path-dependent, not reconstructible offline. CONCLUSION: our C++ ATR is a clean,
correct recursion; the 3 BTC misses are MT5's own iATR tick-jitter nudging 3 bars across the knife-edge
InpMaxAtrPct=0.158 cap — a MT5 non-determinism on a fragile gate, NOT a C++ engine error. 7/10 is the
faithful ceiling; chasing 10/10 would mean replicating an MT5 quirk, not improving correctness. ACCEPT. MONSTER zero-trades FIXED (2026-06-15): the broken EA was the dquants port
`dquants/mql5/experts/KK-Monster/KK-Monster.mq5` (NOT the old `kenkem/.../KK-MasterVP-Monster` which
trades fine at 2649 entries). Bug: `Engine.mqh:105` computed `atrFrac=atr1/c[1]` (fraction ~0.0007)
but compared it to `min/max_atr_pct` which are PERCENT (0.04/0.2) → floor gate false every bar → 0 trades.
C++ oracle (`monster_engine.hpp:516`) and old EA (`KK-MasterVP-Monster.mq5:248`) both have the `*100.0`.
Fix = add `*100.0` at Engine.mqh:105, recompiled clean (KK-Monster.ex5, wine Experts/dquants symlinks
to repo). VERIFIED 2026-06-15: re-run BTCUSD-Exnes-0406 M3 2026.06.01-08 → ~31 entries, final balance
+1889 USD (was 0 trades). Fix confirmed. Secondary nit (not fatal):
Engine.mqh:99-100 hardcodes HTF net refShift=2 vs oracle's net_last_closed_shift()+1 — off-by-one,
revisit after.
