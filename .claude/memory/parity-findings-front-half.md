---
name: parity-findings-front-half
description: KK-MasterVP front-half parity results + the iADX-vs-Wilder and ATR data-source gotchas
metadata: 
  node_type: memory
  type: project
  originSessionId: 93eabcdd-ed73-4c3a-8a0a-c1d68af64676
---

Front-half parity (VP + regime + indicators) of the C++ KK-MasterVP port was validated against the
MT5 tester reference `parity_BTCUSD-Exnes-0406_PERIOD_M3.csv` (BTCUSD M3, 2026-04-09, 480 rows) via
the Python reference harness `cpp_core/tools/validate_parity_py.py`.

**Results:** master VP (mpoc/mvah/mval) match to **<0.001**, ADX/+DI/-DI to **<0.005**, regime trend
flag agrees **100%**.

**Setup that makes it match (all confirmed from baseline.set, defaults hold):**
- Bars are **bid-based** M3 built from ticks; `barTimeUTC` = server time,
  so it aligns directly to our tick `ts`. Master VP = 150 bars (VpLookback 50 ×
  MasterMult 3), 30 bins, VA 70%, **bar-feed** (`InpVpFeedMode=0`, weight = per-bar tick count),
  startShift 1 (window = the 150 bars ending at the row's timestamp inclusive).

**Two gotchas that cost the most time:**
1. **The EA's `iADX` is NOT Wilder.** MT5 built-in `iADX` computes per-bar `100·DM/TR` then smooths
   `+DI`, `-DI`, and `DX` with **EMA k=2/(n+1)** (not Wilder DM/TR smoothing). DM-zeroing: clamp
   negatives, then strictly-greater wins (ties → both 0). Textbook Wilder gave `-DI` off by ~10 pts.
   Fixed in C++ `kk::ind::dmi_adx_mt5` (golden test `test_dmi_mt5_golden`). The old Wilder
   `dmi_adx` stays for research features only — regime/signal must use `dmi_adx_mt5`.
2. **ATR can't be matched to the dollar from the CSV.** ATR matches on average (ratio mean 0.9986)
   but diverges on volatility spikes (e.g. ref 253 vs ours 198). The MT5 tester's internal tick
   model registers **wider intrabar extremes** than the exported tick CSV. VP is robust (window
   max/min set by the same spike bars) and ADX is robust (ratio-based), but ATR is scale-sensitive.
   This is a data-source limit, not a formula bug — accept the caveat; trade-level parity will carry
   small SL/TP/breakout-distance differences on spike bars.

**C++ driver now closes the front-half loop (commit 900cc46).** `tools/export_bars.py` (DuckDB
Parquet→bid M3 bars CSV, keeps C++ dependency-free) → `build/parity_driver` (`make parity`, driven by
`include/kk/parity_runner.hpp`) emits the MT5 ParityExport schema per bar → `tools/diff_parity.py` vs
the MT5 ref. **Shift map (verified from MQL source): processing bar i = MQL shift 1; signal bar OHLC +
atr2 = shift 2 (bar i-1); entry_close + atr1 + regime + master VP window-end = shift 1 (bar i); node
engine UPDATED with bar i BEFORE the signal read; sigValid is raw pre-gate.** Result on the 480-row
ref: master VP ≤0.001, +DI/-DI/ADX **exact (0.000)**, trend 100%, raw **sigValid 74/75** (entry exact
on both-fired rows). The 1 miss (00:03) + sl/tp deltas are entirely the ATR-spike caveat above. Frozen
as golden test `tests/test_parity_golden.cpp` (+ `tests/golden/`) in `make test`. Next: execution layer
(PositionManager/RiskManager/Filters/ExecutionSimulator/TickEngine) → trade-level (Level-2) parity.

**Scaled validation (53,260-row ref, BTCUSD M3 2025-08-10..11-29, the user's 1yr/⅓-fwd run).**
Re-ran the driver over the full run: **+DI/-DI/ADX bit-exact (0.000) and entry bit-exact (0.000) on
every row**; trend 99.82%; raw sigValid 9206/9386 (98%). **Master VP diverges on 456/53260 rows
(0.86%, max mpoc Δ 4727)** — clustered, NOT a logic bug: the offending bars' window-max high is real
in our tick feed (2nd-max only ~10 below it) but MT5's tester history carried a *lower* extreme on
those bars. Same data-feed-extreme class as the ATR caveat (here our feed is the wider one). VP is
window-extreme-anchored so one differing bar shifts the grid for ~150 bars. → a data-reconciliation
item (validate-data), not a port fix. **Broker specs confirmed by user** (XAU vppl=100, BTC vppl=1,
commission $0, balance $10k, 1:200) → `Params::apply_{xauusd,btcusd}_specs()`. The overwritten ref now
has **473 trades** for Level-2; my golden fixture is a frozen copy so it's unaffected.

See [[real-target-kenkem-strategies]] and [[workflow-commit-and-plan]].
