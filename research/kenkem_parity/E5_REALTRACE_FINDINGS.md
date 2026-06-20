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

## ✅ RESOLVED (2026-06-20, v2cols run) — richer realtrace columns → decomposition OVERTURNED
Added 10 value-diff columns to RealTrace.mqh (`ema75/ema100`, `m1_diplus/minus`, `m5/m15 adx+di`) +
populated in Entry5.mqh (kenkem `ebd1bde`). Re-ran the SAME E5-only 2026 config →
`mt5_runs/RUN_2026-06-20_1.8.154_xau_2026H1_E5only_realtrace_v2cols/`. New engine instruments
(env-gated, byte-identical off): `KK_E5_VALDUMP` (E5V = M1 EMA stack + alignment verdict at B-1/B-2/B-3;
E5D = M1/M5/M15 DI+ADX closed AND forming). Analysis tool: `diff_e5_valuediff.py`.

**The prior "26 unarmed + 15 htf + 7 trend_core" was a MISATTRIBUTION.** With real inputs, the 51 missed
E5 trades decompose as:

| bucket | n | finding |
|---|---|---|
| **M1 onset / arming** | **42** | engine never arms the M1 4-EMA strict-alignment onset |
| htf | 1 | engine M5 **closed** adx/di == EA realtrace EXACTLY (20.7,20.0,17.6) — NOT an HTF value diff |
| trend_core | 2 | M1 di/adx — negligible |
| armed+pass | 2 | timing/occupancy |
| nojoin | 4 | (signal bar outside the ±3min realtrace join) |

So the residual is **almost entirely M1 onset-arming**, not HTF/trend-core. The engine's HTF/trend
values MATCH MT5 — those buckets were arming misclassifications in the gate-label-only decomposition.

### ROOT (proven, not a value/seeding bug) — it's the onset BAR-PAIRING
`KK_E5_VALDUMP` shift-test: the EA's logged alignment `ema25` matches the engine's stack at **B-1 (m1s1)
EXACTLY, 42/42** (e.g. EA 4348.485 == eng.B-1 4348.485), while the engine's E5 onset reads **B-2 (m1s2,
faithful)**. So the engine EMA *values are correct* (== MT5 at the same bar) — the disagreement is purely
**which bar pair** the onset latches on: engine arms `aligned@B-2 && !aligned@B-3`; the EA's realtrace
values imply `aligned@B-1 && !aligned@B-2` (one bar fresher).

### …but a naive global shift REGRESSES — the fix is NOT one line
A/B (`KK_E5_FRESH_ONSET`, cur=m1s1/prv=m1s2): recall **52.8%→41.7%**, matched **57→45**, overfire
**33→53**, net **−617→−1231**. The arming bar and the FIRE bar are coupled (d1704ab tuned both for
net-best at faithful B-2); shifting arming one bar fresher desyncs the fire → more overfire + lost
matches. So **faithful B-2 onset timing is net-best**, and the 42 are marginal near-tie alignment bars
where B-2 just misses an onset MT5 caught at B-1.

### Is it worth chasing? YES — the misses carry real edge
The 51 missed MT5 E5 trades net **+466 (53% win, +9.1 avg)** — REPRESENTATIVE of the full E5 edge
(+949 net / 52% win). Unlike E1 (whose misses were all losers — recall MAXED), recovering these would add
~half the E5 P&L. But the global-shift regression shows it needs the EA's EXACT onset latch, not a shift.

### ▶️ NEXT (optional, needs 1 MT5 run + carries regression risk)
To replicate MT5's exact onset pairing, the realtrace must carry the latch internals it currently lacks:
`m_prevBullishAligned`/`m_prevBearishAligned` (the prior-bar alignment the EA's onset compares against)
and `m_lastBullishSignal`/`m_lastBearishSignal` (the armed-bar index). With those I can reproduce
`aligned@cur && !aligned@prv` at MT5's exact shift and port it precisely (vs the blind shift that
regressed). DECISION pending: push E5 recall past the faithful 52.8% ceiling (real +466 edge, regression
risk) vs accept the ceiling and move to E1/E2/E4.
