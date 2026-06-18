# 1.8.154 parity — diagnosis (oracle-validated): over-fire/selection, NOT ATR, NOT broken detection

_2026-06-17 (Opus 4.8). Reconciled with the parallel session's `--pctile-oracle` finding. Ground truth =
the EA's 1.8.154 anchor run (`mt5_runs/RUN_2026-06-17_1.8.154_xau_feb/{parity_trace,trades}.csv`,
XAUUSD M1 every-tick, Feb-2026). Engine config = `anchor_1.8.154.set` (173 keys from the run's logged
inputs)._

## The headline numbers
| run | engine trades | exact-bar match to EA's 9 executed |
|---|---|---|
| baseline (faithful, ATR on) | 45 (E1 18 / E2 13 / E4 14) | 1 / 9 |
| `--pctile-oracle` (MT5's EXACT atr_pctile) | 47 | **0 / 9** |
| ATR gates OFF | 133 | 3 / 9 (within 3 min) |

## Conclusion 1 — ATR-percentile is NOT the blocker (oracle-proven; my earlier draft was WRONG)
Feeding MT5's exact per-bar `atr_pctile` into the engine changes 45→47 trades and recovers **0/9** EA
trades. So the percentile is not what gates the EA's entries. My first draft claimed "4/9 blocked by an
ATR wall" — that was an **artifact of entry_trace's short-circuit ordering** (the ATR gate is checked
early, masking downstream gate failures). Removing/oracling ATR does not recover those bars because a
downstream gate also fails. This corroborates the parallel session's oracle disproof. (There remains a
small, separate truth: the engine's `atr_pctile` differs from MT5 by median 6.25pt — forming ref ~7% off
+ closed-ATR mid-vs-bid rank ~2/32 — but it does **not** drive the parity gap. Deprioritize it.)

## Conclusion 2 — detection is LARGELY FAITHFUL (6/9 EA bars pass engine detection)
Running `entry_trace` with ATR gates OFF (so the reported gate is the true detection blocker), at the 9
EA-executed bars the engine's per-type detection verdict is:
| EA bar | type | engine detection | note |
|---|---|---|---|
| 02.04 07:45 | L-E1 | **PASS** | detects it |
| 02.06 12:07 | L-E4 | **PASS** | |
| 02.09 14:32 | L-E1 | `e1_mtf` FAIL | E1 multi-TF EMA check diverges |
| 02.16 09:02 | L-E4 | **PASS** | |
| 02.16 13:29 | S-E1 | **PASS** | |
| 02.17 03:28 | S-E4 | `tq` FAIL (8 vs 9) | trend-quality forming-ADX 1-pt gap |
| 02.17 13:20 | S-E4 | **PASS** | the 1 exact match |
| 02.18 02:10 | L-E4 | **PASS** | |
| 02.23 07:38 | S-E4 | `tq` FAIL (8 vs 9) | trend-quality forming-ADX 1-pt gap |
**6/9 pass detection; only 3 fail** (1 E1-MTF, 2 trend-quality). So detection is mostly right.

## Conclusion 3 — the real gap is OVER-FIRE + SELECTION (limiters + priority), not detection
Detection passes at 6/9 EA bars, yet the engine TRADES only 1/9. The difference is the layer that
`entry_trace` does NOT model: **priority (E1→E2→E4), occupancy, min-seconds, max-concurrent, and the
account limiters.** The engine fires 45–47 trades vs the EA's 9 executed; those phantom trades both add
noise AND crowd out / suppress the real entries:
- **E2 over-detection**: engine detects **49 E2 vs EA 20** (ATR off). The EMA75-touch trigger is
  byte-identical (triggers.hpp:100-108 == EMAHelpers.mqh:285-313) and the gate ORDER is faithful → the
  looseness is in the indicator INPUTS the E2 gate reads (HTF M5/M15 ADX/DI, emas_ready, trend-quality)
  or E1↔E2 priority coupling. Because E2 has priority over E4, a phantom E2 SUPPRESSES the real E4 (e.g.
  02.18 02:10, where engine detection passes BOTH E2 and E4 but E2 wins).
- The remaining over-fire is loose E1/E4 detection on non-EA bars (many engine E1 fires have no EA E1
  signal within 15 min) + unmodeled account limiters that would have blocked them in the EA.

## Recommended order (reconciled with the parallel session's limiter port)
1. **E2 detection-input fidelity** — highest leverage. Diff the E2 gate's INPUTS (not order) vs the EA
   at the ~29 engine-only E2 bars. Drives engine E2 → ~20 and un-suppresses real E4 (e.g. 02.18 02:10).
2. **Finish the account-limiter port** (parallel session started MAX_SESSION_LOSSES/MAX_SLTP): add
   consec-loss block, losing-streak cooldown, daily-loss, drawdown EOD-block, and the high-risk routing
   (every E2 routes through HandleHighRiskEntry → momentum/weak-trend skip). This trims the over-fire so
   the engine's selection matches the EA's executed set.
3. **Trend-quality forming-HTF-ADX** — recovers the 2 S-E4 (03:28, 07:38). Build forming M3/M5 ADX from
   M1 aggregation; feed {forming,closed,closed-1} to the accel helpers. (Reading forming naively
   net-hurt before — needs the proper bucket model.)
4. **E1 MTF check** at 02.09 14:32 (`e1_mtf` fail) — diff `isAllTimeframeEMAsReadyForEntry` vs engine.
5. ATR-percentile: DEPRIORITIZED (oracle-disproven). Only revisit if everything else ties out.

## Artifacts / repro
- `anchor_1.8.154.set` — engine config from logged inputs.
- Oracle test: `tick_backtester ... --pctile-oracle <ts_ms,atr_pctile.csv>` (build the CSV from
  `parity_trace.csv` cols ts_ms+atr_pctile; joins at offset 0).
- `build/kenkem/entry_trace` (`make kenkem_entry`) — per-bar gate localizer. Run with ATR-off set to see
  the TRUE detection blocker (ATR-on masks it via short-circuit).
- Baselines: `/tmp/eng_base.csv` (45), `/tmp/eng_oracle.csv` (47), ATR-off (133).
