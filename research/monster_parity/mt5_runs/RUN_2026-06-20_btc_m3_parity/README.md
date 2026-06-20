# RUN_2026-06-20_btc_m3_parity — Monster BTC M3 EA↔engine parity (post TP-fix + parity journal)

First Monster parity run after porting the runner-TP fix + `Parity.mqh`.

## MT5 run
- **Pair/TF:** BTCUSD-Exnes-0406, **M3** · **Period:** 2026.01.01 → 2026.06.09
- **Expert:** `dquants\KK-MasterVP-Monster\KK-MasterVP-Monster.ex5` (recompiled, TP fix)
- **Set:** `KK-MasterVP-Monster-BTCUSD.set` + `InpExportParity=true`
- Output: `trades_mt5_btc_m3.csv` (420 trades). Engine baseline: `trades_cpp_btc_m3.csv` (404).

## Result (parity_diff, bar-seconds 180)
| metric | engine | MT5 |
|---|---|---|
| trades | 404 | 420 |
| matched pairs | 345 | |
| unmatched | 59 engine-only | 75 MT5-only |
| exit-tag mismatch | 23/345 | |
| net P&L | +2,801 | +469 |
| net Δ% | — | 498% |
| profit factor | 1.178 | 1.031 |

## Findings
- **Runner-TP fix WORKS:** MT5 TP exits = 3 (was capping at 3.0R before the fix); now trails out
  like the engine (SL-WIN 154). Entries faithful (`entryΔ`=0 on matched).
- **BTC spread is NOT inflated** (unlike XAU): MT5 avg ~$11 ≈ the engine feed's BTC spread
  (C++ "1094 pips" × 0.01 = $10.94). So the engine's OOS PF was already at realistic cost — no
  10× gap. (XAU M5 needed +0.17; BTC needs ~0.)
- **Session/force-close config MATCHES** the engine lock (ForceCloseSessNews=true, same windows,
  blocked hours 8/10/11/16) — the 115 MT5 "EA" force-closes are expected, not a bug.
- **RESIDUAL = unmatched trades drive the net gap.** Matched 345 agree on P&L; the gap is 75 MT5-only
  (likely net-negative) + 59 engine-only (net-positive). The EA takes ~75 trades the engine doesn't —
  entry-gating / re-entry near force-close/session boundaries is the prime suspect. On Monster's thin
  edge this drops live PF 1.18 → 1.03.

## Verdict / next
- Monster's EA is structurally faithful (entries + matched exits + TP fix) but the unmatched-trade
  residual makes its **thin edge marginal in MT5 (PF ~1.03)**. Unlike XAU M5 (clean ~1.27 live), Monster
  is NOT clearly deployable.
- NEXT (if pursuing Monster): diagnose the 75 MT5-only entries — compare entry-gate / max-trades-per-
  session / cooldown counting between EA and engine near session boundaries. Otherwise prioritize the
  XAU M5 forward-test (the strong candidate) and treat Monster as lower-priority.
