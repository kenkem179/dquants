# E5 onset-latch realtrace — DECODED (2026-06-27)

User ran the instrumented EA (KenKemExpert 1.8.154, E5-only, 2026.01.01–06.01, real ticks). Collected
`realtrace_XAUUSD-Exness-KK.csv` (108 E5 trades = MT5 truth ✓, +the 4 new latch cols) → archived
`mt5_runs/RUN_2026-06-27_E5only_2026H1_realtrace_latch/`. Diffed vs the engine's per-bar onset valdump
(KK_E5_VALDUMP `E5V` = M1 alignment at B-1/B-2/B-3; `E5D` = M1/M5/M15 ADX). Tools `/tmp/e5_*.py`.

## PROVEN (solid)
1. **The EA reads E5 alignment at B-1, NOT the engine's faithful B-2.** On all 375 bull-onset bars the EA's
   `aligned_bull == engine alB1` (375/375) and the EA's logged `ema25 == engine B-1 stack` to |Δ|=0.0000
   (vs |Δ|=0.41 to B-2). 100% confirmed — the engine onset is one bar too stale.
2. **The EA's "prev" is a STATEFUL latch that FREEZES during quiet gaps — not a positional B-2 read.**
   `prev_aligned` agrees with positional engine-B-2 only 255/375 (68%) at onsets. The 120 mismatches (EA arms,
   engine wouldn't) **ALL follow a >5-min non-armed gap** (median 208 min; 0 of 120 at ≤5 min, vs the
   reproduced onsets which cluster tighter). The EA arms when alignment RE-appears after a quiet stretch
   because its `m_prevBullishAligned` was reset/frozen during it; the engine, evaluating alignment EVERY bar,
   sees `alB1_prev=1` (no transition) and won't re-arm.
3. **The freeze is driven by the EA's Detect early-returns** — chiefly the ADX gate (`Entry5.mqh:148`,
   `cache.adx[0] < E5_MIN_MOMENTUM_ADX`) which `return`s BEFORE the once-per-bar latch update at line 213. On
   low-ADX bars the latch doesn't update → stale across the gap. (The session-limit early-returns do the same.)

## WHY a port is hard (the honest blocker)
- A naive **stateful B-1 latch** (cur=B-1, prev=prior-bar's B-1) reproduces only **69%** of EA onsets — and
  prior-bar-B-1 ≈ positional B-2, so it is ~the **blind shift that already REGRESSED** (52.8→41.7%, net
  −617→−1231; [[kenkem-e5-2026-selection-break]]). My data explains WHY it regressed: it misses the
  gap-freeze, mis-firing the 31% of onsets that depend on it.
- **Gating the engine latch by the engine's own ADX does NOT close it** (tested adxF0 and adx0 ≥18 → still
  69%): the EA froze on different bars than the engine would, because the EA gates on its OWN forming `cache.
  adx[0]` (SMA-vs-Wilder + forming-bar differences, [[kenkem-atr-is-sma-not-wilder]]) — and the realtrace
  only logs ARMED/fired bars, so the EA's per-bar ADX on the SKIPPED (frozen) bars is not in the data.
- ⇒ Faithfully replicating the freeze needs the EA's per-bar ADX-gate decision on the skipped bars — which
  this realtrace can't supply. Closing it would need EITHER (a) an engine impl of "read B-1 + freeze the
  prev-latch whenever the engine's E5 ADX/session gate fails" then BACKTEST-validate (the onset-match% is not
  the arbiter — recall/net on 2026 AND 2025 is), accepting it may still diverge where engine-ADX ≠ EA-ADX; OR
  (b) another realtrace round logging EVERY bar's alignment+ADX (not just interesting bars) for an exact port.

## Assessment / recommendation
The instrumentation SUCCEEDED — it decoded the exact mechanism (B-1 read + ADX-gated stateful freeze), which
prior sessions had not. But it also shows closing E5 to trustworthy recall is NOT a quick port: the natural
port ≈ the regressive blind shift, and the exact freeze needs per-bar ADX the trace doesn't carry. Given E5's
upside is bounded (recover ~+466 net of the 51 misses; E5 stays a small add to a 141-trade lock) and the cost
is now "implement engine ADX-gated B-1 latch + backtest, or a 2nd MT5 round," this is a genuine fork:
- **(A) Attempt the engine port** (B-1 + engine-ADX-gated freeze, toggle default-OFF) and let the BACKTEST
  judge on 2026+2025. Medium effort, uncertain (engine-ADX ≠ EA-ADX where it froze).
- **(B) One more realtrace round** logging every bar's alignment+forming-ADX → exact port. Needs another MT5 run.
- **(C) Accept the 52.8% ceiling** — E5 stays OFF; pivot to the surgical E2/chop sweep on the existing lock
  ([[LOCK_EDGE_AUTOPSY]]), which doesn't depend on E5 parity at all.

Repro: engine run `cpp_core/build/kenkem/tick_backtester --set …E5only-2026H1-RealTrace.set --from-ms
1767225600000 --to-ms 1780272000000` with `KK_E5_VALDUMP=1 KK_E5_GATE=1`; analysis `/tmp/e5_pairing.py`,
`/tmp/e5_adxlatch.py`, `/tmp/e5_mismatch.py` (copy into the RUN folder).
