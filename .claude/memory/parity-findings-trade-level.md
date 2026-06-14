---
name: parity-findings-trade-level
description: KK-MasterVP Level-2/3 trade parity result + the baseline.set-is-wrong-config gotcha
metadata: 
  node_type: memory
  type: project
  originSessionId: 5080b780-c6e1-43c1-b5c8-28268f43d81e
---

Level-2/3 trade parity of the C++ TickEngine vs the MT5 473-trade reference
(`trades_BTCUSD-Exnes-0406_PERIOD_M3.csv`, BTCUSD M3 2025-08-11..11-29) is **achieved to the
ATR-from-CSV limit**: **478 trades vs 473; 377 match by exact entry-timestamp**; on matched
trades dir/rev/regimeTrend/session/entryReason/bodyPct/adx/diSpread/spreadPips are **EXACT**,
entry meanΔ 0.18, riskPrice meanΔ 15 (the [[parity-findings-front-half]] ATR caveat → stops),
exitTag mismatch 13/377. Level-3: CPP net -$75 / win 57.3% / PF 0.995 vs REF +$451 / 59.2% /
PF 1.026 — same count + win-rate + PF band. Residual 96 missed / 101 extra = ATR-feed-extreme
cascade (different stops → different exits → different re-entries), NOT logic.

**CRITICAL GOTCHA — `KK-MasterVP-baseline.set` is NOT the config the BTC reference run used.**
It is XAU-oriented (e.g. `InpSlAtrBrk=1.48`, `InpMaxSpreadPips=70`). The actual BTC run used
**code-default economics**: `SlAtrBrk=2.2, RrBrk=3, UseMtfAgree=false, MaxSpreadPips=0,
MaxPeakDDPct=30, RiskAccPct=0.9, RiskUsd=180, SkipIfMinLotOverRisk=false`. **The authoritative
inputs for any given tester run are echoed in `kenkem/Tester/Agent-127.0.0.1-3000/logs/*.log`**
(each run prints `... bytes of input parameters loaded` then every `InpXxx=val`; the trades/
parity CSVs are overwritten per run, so match the file mtime to the LAST input block before it).
Extracted config saved as `cpp_core/tools/btc_ref_run.set`. Applying baseline.set instead gave
127 trades / 64 matched — chasing that was the main time sink. **Always pull the run's real
inputs from the log; don't trust baseline.set.**

**Bug fixed via the diff:** the RiskManager min-lot skip guard must gate on
`flooredUp = (rawLot < minLot)` (RiskManager.mqh:114) — only skip when the broker minimum
floored the lot UP and that over-risks. Without the precondition it dropped ordinary trades
whose normal lot merely rounded slightly over budget (this alone suppressed ~3/4 of trades).

**Run it:** `cpp_core/tools/export_ticks.py 2025 clean <start> <end> <out> btcusd` → bars via
`export_bars.py` (full-year warmup) → `build/backtester --bars … --ticks … --trade-from-ms
1754870400000 --set tools/btc_ref_run.set` → `tools/diff_trades.py cpp ref`. trade-from-ms =
test-period start (warmup bars before it are precomputed but never traded). Debug a single
divergence: `KKVP_DBG_FROM=<ms> KKVP_DBG_TO=<ms> build/backtester …` prints the gate that blocked
each signal. See [[parity-findings-front-half]] and [[real-target-kenkem-strategies]].
