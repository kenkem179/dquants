# MasterVP/Monster tick-parity vs MT5 — first measured gap (2026-06-15)

**Goal (user, 2026-06-15):** dquants tick backtest must reproduce MT5 tick-for-tick for **all**
strategies; ground truth = the already-collected MT5 trade CSVs + run logs; fix the **shared/common**
modules so every strategy moves together.

**Oracle:** `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/KK-MasterVP-Monster/trades_XAUUSD-Exness-2426-Good_PERIOD_{M1,M3}.csv`
(generated 2026-06-13; inputs + account state in `logs/20260613.log`). Initial deposit $10,000, lev 1:200.
Tick data covers 2025-01-01 → 2025-07-16 (XAU gap after), so parity is measured on that overlap.

## Harness (reusable, committed)
- `research/kenkem_parity/mastervp_monster_parity.set` — the MT5 tester `.set` cleaned to dquants
  `key=value` (UTF-16→UTF-8, stripped `||min||step||max`). 102 keys.
- Inputs from Parquet: `cpp_core/tools/bars_xauusd_2425_m{1,3,5}.csv` (Dec-2024 warmup + 2025) +
  `ticks_xauusd_2425_window.csv` (2025-01-01..07-16).
- `cpp_core/tools/common/diff_aligned.py` — convention-aware trade diff. Handles the two logging
  conventions: dquants logs the FILL bar (signal+1) with `:SS`; MT5 logs the SIGNAL bar at minute
  res → shift cpp back by `--bar-min`. Folds exit tags into families {TP, SLWIN(=BE/SL-in-profit),
  SLLOSS}. Compares entry, riskPrice, exit-family (NOT $ — sizing config differs; see below).

Run:
```
./cpp_core/build/monster_backtester --bars-m3 cpp_core/tools/bars_xauusd_2425_m3.csv \
  --bars-m1 cpp_core/tools/bars_xauusd_2425_m1.csv --bars-m5 cpp_core/tools/bars_xauusd_2425_m5.csv \
  --ticks cpp_core/tools/ticks_xauusd_2425_window.csv --symbol-xau \
  --set research/kenkem_parity/mastervp_monster_parity.set --trade-from-ms 1735689600000 \
  --out research/kenkem_parity/cpp_trades_mastervp_monster_xau_M3.csv
python cpp_core/tools/common/diff_aligned.py research/kenkem_parity/cpp_trades_mastervp_monster_xau_M3.csv \
  research/kenkem_parity/ref_mastervp_monster_xau_M3_thruJul.csv --bar-min 3
```

## Result (M3, window thru 2025-07-15): cpp 315 vs ref 191
```
matched=155 (exact signal-bar+dir)   missed(ref-only)=36   extra(cpp-only)=160
matched entry   max|Δ|=0.117  mean|Δ|=0.010      <- entry geometry: EXCELLENT
matched risk    max|Δ|=19.4   mean|Δ|=2.82       <- SL placement diverges on a subset
exit-family agreement 146/155 = 94%              <- executor exits: largely FAITHFUL
  (mismatches: SLLOSS<->SLWIN x6, ->TP x2, TP->SLWIN x1)
```

## Decomposition — what actually diverges (evidence-based)

1. **Entry GEOMETRY parity is excellent** (Δ 0.01) and **exit executor is 94% faithful** on matched
   trades. ⟹ The shared `kk::common::position_manager` (trail/BE/partial) is *already* close for
   MasterVP/Monster — the user's "fix the common executor" lever is mostly already paid here. The
   bigger gaps are elsewhere:

2. **Over-fire ~2× and UNIFORM** (cpp ~45/mo vs ref ~28/mo, every month Jan-Jul; not a late-period
   blowup artifact — the ref keeps trading steadily). dquants accepts ~160 in-band setups MT5 skips.
   Ruled OUT as causes: ATR% band (dquants enforces [0.04,0.2]; all cpp trades in-band), daily/peak-DD
   governors (modeled), spread filter (disabled in this config). ⟹ Remaining cause is a **signal-layer
   selectivity gate** (breakout-strength / flow / impulse-vs-breakout / anti-churn-between-entries), NOT
   the executor. Needs a per-bar signal diff (MT5 parity_*.csv-style export) to pin — the log's most
   common skip reason is "ATR pct below floor" but that's already matched.

3. **Sizing ~10× (broker tick-value quirk in MT5 itself).** Log: `InpRiskUnit=0, InpRiskAccPct=1.6` →
   budget should be 1.6%·$10k = $160 → ~0.6 lots. But MT5 sized **lot=6.34** (≈$1654 risk = 16.5%),
   then settled P&L at the real contract=100 (−1678 = 6.34·2.61·100). So MT5 **sized at vpppl≈10 but
   P&L'd at vpppl=100** — i.e. `SYMBOL_TRADE_TICK_VALUE` on "XAUUSD-Exness-2426-Good" is ~$0.1 (not
   $1), making `ComputeLot` over-risk 10× and ultimately blow the account ($10k→$19 by Dec). dquants
   sizes "correctly" at vpppl=100 → 10× smaller $. This is a **$-scale only** issue (doesn't change
   which trades fire) but it must be reproduced for $-level parity. **DECISION NEEDED:** reproduce the
   MT5 mis-sizing (true tick-parity) vs treat sizing as a fixed-risk config (cleaner research numbers)?

## Next
- Build/locate a per-bar MasterVP/Monster signal trace on BOTH sides to pin the 2× over-fire gate
  (this is the real systemic logic gap; harness `diff_parity.py` already exists for bar-level).
- Reconcile sizing per the decision above (set dquants XAU `tick_value=0.1` to mirror the broker, OR
  switch to fixed-risk and accept $-scale divergence).
- Then re-diff M1 too; then apply the same harness to KenKem once an instrumented KenKem MT5 run exists
  ([[kenkem-parity-instrumentation-missing]]).
