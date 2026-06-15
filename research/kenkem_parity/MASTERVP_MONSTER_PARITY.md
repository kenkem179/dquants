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

2. **Over-fire ~2× and UNIFORM** (cpp ~45/mo vs ref ~28/mo, every month). dquants accepts ~160 in-band
   setups MT5 skips. **Root cause found in the run log** — MT5's per-bar skip reasons:
   `2982 ATR pct below floor` (dquants matches), **`1246 daily DD breaker`**, `103 position already open`.
   The daily-DD breaker is the dominant suppressor, and it is a **DIRECT CONSEQUENCE of the 10× oversizing
   in #3**: MT5's huge per-trade risk → frequent ≥5% daily drawdowns → the breaker blocks new entries all
   year; dquants (correctly sized) sees small DD → breaker rarely fires → it keeps trading → over-fire.
   Secondary: `position already open` = one-position-at-a-time concurrency MT5 enforces that dquants does
   not. So this is NOT a signal-detection gate — it's governor behavior coupled to sizing + concurrency.

3. **Sizing ~10× (broker tick-value quirk) — the ROOT CAUSE of both $-scale AND the over-fire.** Log:
   `InpRiskUnit=0, InpRiskAccPct=1.6` → budget should be 1.6%·$10k = $160 → ~0.6 lots. But MT5 sized
   **lot=6.34** (≈$1654 = 16.5%), then settled P&L at contract=100 (−1678 = 6.34·2.61·100). So MT5
   **sized at vpppl≈10 but P&L'd at vpppl=100** — `SYMBOL_TRADE_TICK_VALUE` on "XAUUSD-Exness-2426-Good"
   is ~$0.1 (not $1), making `ComputeLot` over-risk 10× and blow the account ($10k→$19 by Dec). dquants
   sizes correctly (vpppl=100). Because the daily-DD breaker (#2) is %-based, this 10× difference makes
   the breaker fire on completely different bars → it changes WHICH trades fire, not just the $.

   ⚠️ The "2426-Good" oracle is therefore a **broker-misconfigured blow-up run**. **DECISION NEEDED:**
   (A) reproduce it tick-for-tick (set dquants XAU `tick_value=0.1` so sizing→DD→entry-suppression all
   match — proves the engine is faithful to MT5, even to the glitch), or (B) get a CLEAN MT5 reference
   (proper XAU symbol / fixed tick value) and make dquants match that (the strategy we actually want to
   ship). (A) validates the engine; (B) validates the strategy. They need different reference data.

## Next (gated on the #3 A-vs-B decision)
- **If (A) reproduce MT5 faithfully:** set dquants XAU sizing `tick_value=0.1` (vpppl≈10), add
  one-position-at-a-time concurrency to the monster engine, re-diff — the daily-DD breaker should then
  fire on the same bars and the 2× over-fire should largely close. This is the cleanest proof the engine
  is MT5-faithful, and it's fully doable on existing data.
- **If (B) validate the strategy:** the user runs a CLEAN MT5 reference (correct XAU tick value) and we
  match that instead — the current oracle is a broker blow-up and not worth chasing to the cent.
- Either way then: add concurrency parity, re-diff M1, and apply the same harness to KenKem once an
  instrumented KenKem MT5 run exists ([[kenkem-parity-instrumentation-missing]]).
