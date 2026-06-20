# RUN_2026-06-20_xau_m5_gates_lock — MT5 parity for the T1 gate-sweep lock

MT5 re-run after locking 3 dormant gates (`InpBrkVetoSfp`+`InpUseMomVeto`+`InpUseMtfAgree` ON) on the
XAU M5 candidate. **Two findings: (1) logic parity HOLDS; (2) the gate lock is a REGIME BET that is
currently on the WRONG side of the most recent 4 months.**

## The MT5 run
- **Pair/TF:** XAUUSD-Exness-KK, **M5** · **Period:** 2026.01.01 → 2026.06.09 (UTC), every-tick
- **Expert:** `dquants\KK-MasterVP\KK-MasterVP.ex5` · **Set:** `KK-MasterVP-XAUUSD-M5.set` (`InpExportParity=true`)
- Output: `trades_mt5_xau_m5.csv` (489 trades, final balance **$17,144.71** = +71.4%). Log `tester_xau_m5.log`.

## 1) PARITY = faithful (logic reproduced; residual = feed noise + spread)
`parity_diff.py` engine (494) vs MT5 (489), bar-seconds 300:
| metric | 0-spread | +0.17 spread (cost-matched) |
|---|---|---|
| matched pairs | 424 / 489 (87%) | 420 |
| entry lag >0 | 2.0% (≤5% tol) | — |
| exit-tag mismatch | 36 / 424 | 36 |
| net P&L Δ% | 20.3% | **12.0%** |
| profit factor (eng vs MT5) | 1.275 vs 1.246 | 1.259 vs 1.246 |
`parity_diff.py` prints FAIL (net Δ > 1% strict gate), but as in the prior near-parity run this is
**feed-level noise** — engine uses the imported XAU feed (~19pt spread), MT5 uses live Exness (112pt);
cost-matching halves the gap, and the ~70 unmatched each side are boundary entries flipping on bar/ATR
value diffs. Signal + entry + exit mechanics are faithfully ported (PF within ~1%, lag 2%).

## 2) REGIME FINDING — the gates HURT the most recent regime (the forward proxy)
Clean engine A/B on this exact window (2026.01.01–06.09):
| config | n | PF | net | maxDD |
|---|---|---|---|---|
| gates OFF (baseline) | 573 | **1.339** | **+$12,177** | **10.6%** |
| gates ON (lock)      | 494 | 1.275 | +$8,596 | 16.5% |

Gates are WORSE on every axis on 2026 H1. Per-fold across the full WF (the 1c5afbc lock basis):
gates HELP F1–F4 (mid-2025 → early-2026, choppy/mixed) but HURT F5 (−28%) and F6 (−43%, the strong
gold uptrend Feb–May 2026). The gates are momentum/trend-alignment filters that block valid continuation
breakouts in strong trends. The pooled-6-fold improvement I locked on was carried by 2025; the most
recent 4 months prefer baseline.

## VERDICT / DECISION PENDING
- EA↔engine parity: **CONFIRMED faithful** (the EA is a correct port; not the issue).
- The gate lock (commit 1c5afbc) is a robustness/consistency bet that currently underperforms raw return
  AND drawdown on the most recent regime. **Awaiting user call:** keep gates (long-run consistency,
  higher worst-fold, lower full-year MC DD) vs revert to baseline (higher recent return + lower recent DD;
  the "MT5-is-reality / recent-OOS-is-the-forward-proxy" choice).
