# RUN_2026-06-20_xau_m5_parity — first EA↔engine trade-level parity check

First production-gate parity run for the KK-MasterVP XAU M5 lock. **VERDICT: FAIL.**

## The MT5 run
- **Pair/TF:** XAUUSD-Exness-KK, **M5**
- **Period:** 2026.01.01 00:00 → 2026.06.01 00:00 (UTC)
- **Expert:** `dquants\KK-MasterVP\KK-MasterVP.ex5`
- **Set:** `KK-MasterVP-XAUUSD-M5.set` (= `used.set`) + `InpExportParity=true`
- Output: `trades_mt5_xau_m5.csv` (631 trades). Log slice: `tester_xau_m5.log`.

## The engine run (matched window)
```
./build/backtester --bars tools/bars_xauusd_2026_m5.csv --ticks tools/ticks_xauusd_2026_oos.csv \
  --set-all tools/mastervp/kkmastervp_xau_m5_LOCKED.set --symbol-xau \
  --trade-from-ms 1767225600000 --trade-to-ms 1780272000000 --out trades_cpp_xau_m5.csv
```
→ `trades_cpp_xau_m5.csv` (563 trades). Diff: `parity_report.txt` (`parity_diff.py --bar-seconds 300`).

## Result
| metric | engine | MT5 |
|---|---|---|
| trades | 563 | 631 |
| matched pairs | 416 | |
| unmatched | 147 engine-only | 215 MT5-only |
| net P&L | +10,334 | +2,027 (Δ 409%) |
| profit factor | 1.316 | 1.071 |
| exit-tag mismatch | 141/416 | |

## Diagnosis — entries faithful; ROOT CAUSE = 10× broker-feed SPREAD mismatch
- **Entry parity is GOOD:** on the matched trades `entryΔ` is mostly **0.000**. Signal detection +
  entry timing port cleanly. The signal logic is NOT the problem.
- **SL formula is IDENTICAL** on both sides — `sl = entry_close ± max(sl_atr_brk·atr1, 8·pip)`
  (Strategy.mqh:71 ≡ strategy.hpp:90). The residual `slΔ ≈ 0.68` is purely an ATR *value* diff, which
  is itself a symptom of the feed mismatch below (different bars → different ATR).
- **ATR-mode hypothesis TESTED → DISCONFIRMED:** re-ran engine with `InpAtrMt5Mode=true`. slΔ did NOT
  collapse (−0.39 → +0.68), exit-mismatch 141→133, net Δ 409%→416%. ATR smoothing is not the lever.
- **⭐ ROOT CAUSE — the imported tick feed is 10× tighter-spread than the live Exness-KK account:**
  - engine avg spread = **18.9 points** (0.019/oz) vs MT5 avg = **189 points** (0.189/oz).
  - The engine fills on the tick file's native bid/ask (no `--spread` flag exists); the lock was
    optimized/validated on `ticks_xauusd_2026_oos.csv`, a TIGHT-spread source. The real account
    (Exness MT5Trial, XAUUSD-Exness-KK) charges ~10× the gold spread.
  - This fully explains the headline gap: engine net +10,334 / PF **1.31** vs MT5 +2,027 / PF **1.07**.
    At real transaction cost the edge is ~5× smaller. It also drives much of the count/exit divergence
    (spread shifts which SL/TP triggers near the gates).

## Implication (production)
**The locked OOS PF 1.31 is NOT realizable on this Exness account** — at the real ~189-pt spread the
same logic yields PF ~1.07. The lock must be re-validated (and likely re-tuned) against real-spread data
before deployment. This quantifies the HANDOFF's earlier "residual PF gap is FEED-DRIVEN" note at the
account level.

## Next actions (decision required — see HANDOFF)
1. **Re-validate the lock at real spread.** Options: (a) re-import Exness-KK ticks for the window and
   re-run the engine/sweeps on them; or (b) add an additive-spread option to the backtester
   (`--extra-spread`) to stress the lock at ~170 extra points and re-check PF/plateau.
2. Only after cost-parity holds is the trade-by-trade SL/exit residual worth chasing.
3. The verifier itself WORKS — it caught a real, deployment-blocking cost gap on the first run.
