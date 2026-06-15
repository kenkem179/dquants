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

   **⛔ CORRECTION (2026-06-15, verified against MT5 source — supersedes the "parity bug" claim below).**
   There is **NO predictive-vs-reactive parity bug.** The MT5 EA (`KK-MasterVP.mq5:132,214`) calls
   `IsDailyDDHit(riskBudget)` with `riskBudget = ComputeRiskBudgetUSD()` — and `IsDailyDDHit`
   (`RiskManager.mqh:142-147`) adds `+ riskBudget` to the projection. That is **predictive, byte-identical
   to the C++ `is_daily_dd_hit`**. The C++ port is FAITHFUL. (MT5 also has the reactive arm at
   `KK-MasterVP.mq5:170` — `IsDailyDDHit(0.0)` for the cooldown — and the C++ mirrors that too in
   `maybe_arm_daily_dd_cooldown`.) **The earlier experiment was flawed:** it set `InpRiskAccPct` 1.6→16,
   which makes the *budget* $1600 (16% of $10k) → predictive add alone breaches the 5% cap → 0 trades,
   which is the CORRECT predictive response to a genuinely 16%-budget trade. But MT5 ran at
   `InpRiskAccPct=1.6` (budget $160, harmless predictive add) and only *realized* ~16% losses via the
   `tick_value≈0.1` sizing quirk (#3). Budget ≠ realized loss — `risk_acc_pct=16` does NOT mirror MT5.
   So the over-fire is fully explained by #3 alone; **do NOT change `is_daily_dd_hit`** (it would break
   parity). Path (B) resolves this by replacing the broker-glitched oracle.

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

## Next — DECISION MADE: path (B), clean MT5 reference (user, 2026-06-15)
The current "2426-Good" oracle is a broker blow-up (`tick_value≈0.1`) and not worth chasing to the cent.
The user will run a CLEAN MT5 reference on a correctly-configured XAU symbol; dquants matches THAT.
Run spec for the clean reference: see `RUN_GUIDE_PARITY.md` → "Clean MasterVP/Monster reference (B)".
After the clean CSVs land, re-run `diff_aligned.py`; the over-fire should largely close once sizing
matches (no tick_value glitch → daily-DD breaker fires on the same bars). Concurrency parity
(one-position-at-a-time) still to add to the monster engine, then re-diff M1.
