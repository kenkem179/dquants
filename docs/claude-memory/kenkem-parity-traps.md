---
name: kenkem-parity-traps
description: KenKem C++ port — the exact source-confirmed details that will break MT5 parity if missed
metadata: 
  node_type: memory
  type: project
  originSessionId: 67691271-7127-41af-98bb-1c0f44816ec8
---

Porting KenKem EA (v1.8.154, KenKemExpert.mq5, kenkem repo) to `kk::kenkem` C++. Full port-ready specs
with line refs live in `research/hypotheses/kenkem-portnotes/{01-config,02-indicator-cache,03-triggers-entries,04-trade-manager}.md`.
Snapshot pinned: sha256 `61bc702b…` of KenKemExpert.mq5 (kenkem repo is git, recoverable).

**Source-confirmed parity traps (don't trust the SPEC's earlier from-memory values):**
1. **EMAs = 10/25/71/97/192** (INPUT_EMA0..4_PERIOD), NOT the round 75/100/200 the enum labels
   (EMA_75/EMA_100/EMA_200) and stale comments imply. RuntimeConfig CFG.ema* (25/75/100/200) is DEAD code.
2. **ATR cache reads shift 0** (forming bar); ADX/DI/RSI/EMA/Ichimoku-current read shift 1. ATR-percentile
   = lookback 32 at shift 1 vs currentATR at shift 0. Replicate the mismatch exactly.
3. **Per-symbol OnInit override (KenKemExpert.mq5:122-163):** BTCUSD pip=1, contract=1, MY_STANDARD_LOT_SIZE×2,
   minLot=0.01. XAUUSD/GOLD pip=10^-digits (0.01 for 2-digit Exness), contract=detected(100), no lot mult.
4. **Management early-exits read forming-bar iClose/iHigh/iLow(...,0) + live cache** → the tick replay must
   feed RUNNING per-bar values, not sealed bar-0 OHLC, or it leaks the bar's outcome. THE key backtester rule.
5. **RR asymmetry:** E1/E2 short = RR×0.875/0.867; **E4 short = E4_RR_SHORT(1.8)×0.875**; E4 sideway =
   E4_RR_SIDEWAY(1.15). Dispatch is first-match-wins E1→E2→E4 (E3/E5 skipped); long evaluated before short.
6. **GetTrendQualityScore hard gate:** returns 0 if ADX-comp OR DI-comp OR MTF-comp == 0. Mins E1≥6, E2/E4≥9.
   Trigger ages: E1=80, E2=36 (stored as Bars()-1 basis!), E4=20.
7. **8 ordered per-tick early-exits:** score-drop → ADX-drop → DI-flip → E5-sideway → sideway → ichi-cloud →
   panic → early-cut-near-SL. First closer wins; E1/E2/E3/E6 are bar-gated (first tick of new M1 bar).

Broker run config (mirror MasterVP): Exness BTCUSD-Exnes-0406 / XAUUSD, $10k, 1:200, real ticks,
2025 IS / 2026 OOS. Target BOTH symbols. Parity is a HARD GATE before optimization. See [[real-target-kenkem-strategies]].
