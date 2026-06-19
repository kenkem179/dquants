# E5 2026 selection-break — gate-trace forensics (2026-06-20)

**Input:** user ran KenKemExpert E5-only over **2026-01-01 → 2026-06-01** (fresh start), producing a
per-bar E5 gate trace. Archived: `mt5_runs/RUN_2026-06-20_1.8.154_xau_2026H1_E5only_gatetrace/`
(trades.csv 108 E5 net **+949**; trace.csv.gz 144,066 bars; inputs_echo.txt; tester.log.gz).

**Engine reproduction (fresh-state, windowed `--from-ms/--to-ms`, set `MT5_E5_2026.set`):**
75 E5 trades net **−683**. Diff: matched 49, missed **59**, overfire 26. The 2026 break reproduces
cleanly and is NOT an accumulated-state artifact (engine entered 2026 fresh, balance 10000, like MT5).

## What it is NOT (hypotheses killed this session)
1. **NOT a config mismatch.** Full `.set`-vs-echo diff: every entry-selection key matches
   (E5_MAX_EMA_CROSS_AGE=28, MIN_ENTRY_ATR_PERCENTILE=65, E5_MIN_MOMENTUM_ADX=18, E5_HTF_* all equal).
   Only diffs: VOL_LOT_ADJ_E5, E5_PARTIAL_TP_TRIGGER (exit), consec-loss-mins — none affect selection.
2. **NOT limit orders.** `ENABLE_LIMIT_ORDERS=false` in the echo (despite `LIMIT_USE_E5=true`). MT5 used
   market execution. (The EA's `PlaceLimitOrder`/`pendingOrders[]` system is globally disabled.)
3. **NOT the pip→ATR tolerance.** The E5 gate uses DI-spread/ADX HTF filters + trend-quality, not pip
   tolerances; `price`/`htf` gates are <5% of divergences. The standing pip-tolerance hypothesis is wrong for E5.
4. **NOT ATR computation.** Engine ATR matches MT5 **exactly** (100% when aligned). The apparent "engine
   ATR higher / 9% pctile mismatch" was an artifact of the trace 1-bar offset (below). Engine `atr_pctile`
   matches MT5's **exactly** offset-corrected (eng_pct == mt5_pct[k-1]: 31.2=31.2, 59.4=59.4, 46.9=46.9…).
5. **NOT cross-arming / onset.** Reconstructing E5 alignment onsets from the (exact) EMA columns in BOTH
   traces: **LONG eng 680 vs MT5 681, SHORT 655 vs 655**; alignment disagrees on 2 of 144,065 bars. The
   E5 onset/arming is essentially identical. (The earlier "engine never armed" was the unreliable
   `e5_age` trace column — see below.) The EA also consumes-on-fire identically (Entry5.mqh:359
   `m_lastBullishSignal=-1`), so the consume model matches too (verified by A/B: removing engine consume → 361 trades).

## Trace-reliability caveats (important for anyone re-running the diff)
- **`trace_dumper` 1-bar offset:** engine logs EMA at the correct bar but **close/adx/atr/rsi one bar
  staler** (eng[k] == mt5[k-1] at 99.9–100%; EMA matches at shift 0). Both use `build_snapshot`, so this
  reflects the snapshot reading ADX/close at shift 1 while EMA is at the validated B-2 — i.e. the engine's
  gate ADX is **one bar staler than MT5's**. (Whether that's a real systemic gate shift or a logging-only
  artifact is the leading open question — see Next.)
- **The trace gate columns ≠ the real entry path.** `Entry5.TraceBar` (a) uses a SEPARATE state machine
  (`m_tr_*`, by design "so the observer never perturbs trading"), so its `e5_age`/`inage` diverge from the
  real `m_lastBullishSignal`; and (b) computes `L_atrlo` from **`ATR_PERCENTILE_LOW`=20**, NOT the real
  **`MIN_ENTRY_ATR_PERCENTILE`=65** block that actually gates entries (that block lives in
  `GetEntryBlockReason`, not in the trace columns at all). So `diff_e5_trace.py` gate-blame is unreliable
  for arming and ATR; trust the EMA-derived reconstruction + the engine's own gate logic instead.

## What it IS (localized) + the failed fix
Among **identical onsets** (~1335), only ~100 become trades — so the **gates** are the dominant filter,
and engine gates pass 75 while MT5 passes 108. It is a **pervasive gate-selection divergence**, not one gate:
- A/B disabling `MIN_ENTRY_ATR_PERCENTILE` entirely: engine 75 → **218** (massive overfire).
- A/B high-risk-bypass of MIN_ENTRY (keep black-swan low/high): engine 75 → **167**, but recall only
  **49→51** while overfire **26→114**. The bypass adds 88 engine-only trades that DON'T match MT5 →
  MT5's low-pctile entries are **selective**, not a blanket bypass. **Reverted** (net-negative).
- Even with ATR fully bypassed, the engine still **misses 57 of 108** → most missed are blocked by
  NON-ATR gates and/or fire-bar timing, spread thinly (sideways, trend_quality, price, trendcore), with
  no single dominant lever. Consistent with a systemic cause (the 1-bar ADX/close gate shift) rather than
  one gate threshold.

## Next (decisive instrument needed)
The per-bar `TraceBar` can't resolve this because its gate columns use different thresholds/state than the
real path. Need an MT5 **real-path E5 entry trace**: for every bar the EA evaluates an E5 signal, log from
`DetectNewEntry`/`HandleHighRiskEntry` (NOT TraceBar): `m_lastBullishSignal` age, `isHighRiskTrade`,
`cachedATRPercentile`, the `GetEntryBlockReason()` string, and the `cache.adx[0]`/`currentPrice` used.
Then value-diff the engine's gate decision against the real path (the method that cracked E1 via
`kke1gate.csv`). In parallel (engine-side, no new data): test the **ADX/close 1-bar-fresher** hypothesis —
feed forming (shift-0) adx/close to the E5 gate, re-run 2026 AND 2025; confirmed only if 2026 recall rises
while 2025 stays matched (currently near-perfect). Do NOT lock any entry .set until 2026 parity holds.

---

## UPDATE 2026-06-20 — forming-ADX experiment RESULT: hypothesis DISCONFIRMED for recall

**What was tested.** Added a toggleable engine flag `E5_GATE_FORMING_ADX` (default off; commit-safe,
golden tests byte-identical). When on, the E5 ADX floor and the E5 HTF filter read the engine's
**forming** (shift-0) `s.adxF/diPF/diMF` instead of the closed shift-1 `s.adx/diP/diM` — i.e. the exact
"engine gate ADX is one bar staler than MT5's `cache.adx[0]`" fix. Code: `gates.hpp` (`htf_*_src`),
`entries.hpp` E5 branch, `kenkem_config.hpp`. A/B harness: `diff_e5_2026.py` (fresh 2026 window).

**A/B (fresh 2026 window vs MT5 108 +949):**

| variant            | eng_n | matched | missed | overfire | recall | net  |
|--------------------|-------|---------|--------|----------|--------|------|
| BASELINE (closed)  | 75    | 49      | 59     | 26       | 45.4%  | −683 |
| FORMING-ADX (on)   | 70    | 49      | **59** | 21       | **45.4%** | −557 |

**Conclusion.** Forming ADX trims 5 overfire and cleans `net` (−683→−557, mNet −127→−33) but **does
NOT move recall** — matched stays 49/108, missed stays 59. It makes the gate *stricter* (passes fewer),
whereas the missed-59 (MT5 fires, engine blocks) need the engine to pass *more*. So the 1-bar ADX shift
is the WRONG direction for the core divergence. **The gate-selection break is NOT the forming-ADX shift.**
Consistent with the earlier finding that even fully bypassing the ATR-pctile gate still misses 57/108.

**Disposition.** Flag kept (default OFF — no regression) as a faithful, internally-consistent refinement
(MT5's E5 gate genuinely reads forming `cache.adx[0]`, and engine `atr_pctile` is already forming), but
NOT enabled — it doesn't earn parity and the default must stay byte-identical until 2026 holds.

**The decisive instrument is now BUILT and waiting on a CORRECT MT5 run.** The real-path E5 trace
(`Parity/RealTrace.mqh`, `InpExportRealTrace`) ships in the EA (compiles 0/0). The first attempt was run
with the WRONG config (`ENABLE_E5_ENTRIES=false`, E1/E2/E4 on — see tester log 05:25) so `realtrace_*.csv`
came back header-only. Re-run E5-only (load `reproduce.set`, which now also sets `InpExportRealTrace=true`)
to get the per-bar real-path gate inputs (`cachedATRPercentile` vs `MIN_ENTRY_ATR_PERCENTILE`=65, real
onset age, real `cache.adx[0]`, the gate that blocked) → then value-diff vs engine to localize the missed-59.
