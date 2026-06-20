# E5 2026 real-path entry trace — findings (2026-06-20)

Run: `mt5_runs/RUN_2026-06-20_1.8.154_xau_2026H1_E5only_realtrace/` (XAUUSD M1, 2026.01–06,
E5-only, `reproduce.set`, `InpExportRealTrace=true`). `realtrace_*.csv` = 4,914 armed/fired E5 bar
snapshots with the LIVE trigger decision (`final_decision`, `gate`, per-gate cols). 108 E5 trades
(+949 MT5). The realtrace is the SIGNAL-level decision per armed bar (478 fire-decisions collapse to
108 positions via occupancy/cooldown).

## Baseline (engine, fresh 2026 window, MT5_E5_2026.set)
Pre-fix: eng 75 / matched 49 / missed 59 / overfire 26 / recall 45.4% / net −683.

## FIX 1 — `hr_momentum_level(E5)` = NONE (commit) ✅ VERIFIED
EA `Entry5::GetHighRiskMomentumCheck()` returns `NONE` (hardcoded, InputParams.mqh NONE=-1) → the
high-risk route for E5 applies NO momentum gate. The engine's `hr_momentum_level()` had no kind==5
case → fell through to `c.hr_momentum_e1` = 3 (M1_AND_M3), wrongly applying E1's strict momentum
filter to E5 high-risk entries. Fixed `risk_exec.hpp`: kind==5 → return -1 (NONE).
Result: matched 49→**57**, missed 59→**51**, recall 45.4→**52.8%** (+8 high-risk entries recovered;
the missed HIGH_RISK_ROUTE bucket 40→32). Overfire 26→33 (engine now fires more HR entries; some land
on a different bar than MT5). Golden tests green (28/28).

## Decomposition of the residual 51 missed (via realtrace + 2 new engine diagnostics)
New env-gated engine instruments (byte-identical when off):
- `KK_EXEC_DIAG` — per-detected-E5 execute-stage block reason (`EXEC,ts,dir,E5,why,…`).
- `KK_E5_GATE` — per-bar E5 armed-state + detection-gate first-fail (`E5G,ts,dir,arm,age,label`).

| Engine state on the missed bar | n | Root |
|---|---|---|
| **unarmed** | 26 | engine never arms the E5 alignment-onset (M1 4-EMA strict-alignment onset divergence) |
| armed → **htf** block | 15 | engine E5 HTF (M5) filter blocks where MT5 `htf_block=0` — HTF value divergence near thr |
| armed → **trend_core** block | 7 | engine `trend_core_score==0` where MT5 passes (DI/EMA-structure value divergence) |
| armed → PASS | 3 | timing/occupancy (engine fired the cross at another bar / execute ATR) |

Execute-stage (post-detection) accounts for only 9 of 51 (ATR blocks); the gap is DETECTION-stage:
arming (26) + HTF (15) + trend_core (7).

All 42 detection-misses have MT5 `adx_pass=tq_pass=price_ok=in_session=1`, `sideway_block=0`,
dir-relevant `htf_block=0`, cross age 0–27 (< the 28 cap). Only 5/42 are firing-timing shifts — 37 are
genuine engine non-detections. **NOT the "gate ADX 1-bar shift"** (forming-ADX experiment already
disconfirmed) — it is HTF/trend_core/alignment VALUE divergence.

## BLOCKER — realtrace lacks the HTF/EMA inputs needed to value-diff the 48 detection-misses
`reproduce.set` E5 HTF/trend-core/alignment config MATCHES the engine (no config mismatch). The
realtrace logs only the RESULTS (`htf_block_long/short`, `aligned_bull/bear`, `ema25`, `ema200`) — not
the HTF (M5) EMA/ADX/DI inputs nor the full M1 4-EMA stack. To pin the 26 arming + 15 htf + 7 trend_core
I need the EA to add these columns to RealTrace.mqh and re-run (see HANDOFF "NEXT for E5").
