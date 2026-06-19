# KK-MasterVP XAU M5 — Walk-Forward + Monte-Carlo hardening (2026-06-20)

Hardening the **locked M5 config** (`cpp_core/tools/mastervp/kkmastervp_xau_m5_LOCKED.set`:
master 432b = `VpLookback108×Mult4`, break_buf 0.85, sl_atr_brk 1.2, trail 2.5, risk 1%, daily-DD 10%)
before the manual MT5 forward-test. This does **not** re-optimize — it stress-tests the already-chosen
config against (a) time-period dependence (walk-forward) and (b) trade-sequence luck (Monte-Carlo).

Tooling added this session:
- C++ `--trade-to-ms` fold cap on the backtester (`tick_engine` `set_trade_to_ms`): past the boundary,
  open positions are still managed/closed but no new entries — clean WF fold windowing. Golden tests green.
- `research/mastervp_parity/wf_mc.py` — WF stability (monthly + equal-N) + Monte-Carlo (bootstrap + shuffle).
- `research/mastervp_parity/wf_reopt.py` — anchored re-optimization WF of the dominant lever (master length).
- Continuous tick file `cpp_core/tools/ticks_xau_full.csv` (train+OOS merged, gitignored).

Canonical stream: locked config replayed CONTINUOUSLY over 2025-06-19 → 2026-05-29 (single compounding
account, no artificial train/OOS reset) = **1,413 trades, x4.11 (+311%), PF 1.260, win 58.0%,
maxDD 27.7%, recovery 11.2** (`_wf_fullrun.csv`).

## 1. Walk-forward stability (locked config, fixed params)

**Calendar months — 11/12 positive (median PF 1.336):**

| period | n | win% | PF | net% | maxDD% |
|--------|---|------|----|------|--------|
| 2025-06 | 48 | 60.4 | 1.432 | +8.0 | 5.4 |
| 2025-07 | 131 | 62.6 | 1.336 | +16.8 | 9.4 |
| **2025-08** | **138** | **47.1** | **0.690** | **-21.6** | **25.3** |
| 2025-09 | 128 | 64.8 | 1.710 | +37.2 | 11.1 |
| 2025-10 | 148 | 57.4 | 1.297 | +18.9 | 6.9 |
| 2025-11 | 122 | 59.0 | 1.082 | +3.3 | 12.9 |
| 2025-12 | 125 | 56.8 | 1.230 | +11.8 | 11.6 |
| 2026-01 | 132 | 56.8 | 1.381 | +22.0 | 14.9 |
| 2026-02 | 112 | 56.2 | 1.110 | +4.3 | 13.9 |
| 2026-03 | 122 | 65.6 | 1.796 | +37.6 | 6.6 |
| 2026-04 | 99 | 56.6 | 1.061 | +2.0 | 13.1 |
| 2026-05 | 108 | 54.6 | 1.461 | +23.4 | 9.6 |

Equal-N (8 folds of ~176 trades): **7/8 positive, median PF 1.297, worst 0.817** — the one negative fold
is the same **Aug-2025** window. The edge is broad-based, not carried by any single period; Aug-2025 is the
historical stress month (trendless chop → the breakout edge bleeds, -21.6% / 25% intramonth DD).

## 2. Monte-Carlo (20,000 iters, de-compounded 1%-fixed-fractional returns)

Bootstrap (resample the 1,413 trades WITH replacement — "what if the mix had differed"):

| pctile | 1% | 5% | 25% | 50% | 75% | 95% | 99% |
|--------|----|----|----|----|----|----|----|
| net%   | +19.5 | +71.4 | +186.6 | +310.0 | +494.4 | +906.2 | +1348.3 |
| maxDD% | 14.3 | 16.4 | 20.5 | 24.4 | 29.3 | 38.4 | 46.7 |
| PF     | 1.048 | 1.108 | 1.196 | 1.259 | 1.327 | 1.427 | 1.498 |

- **P(profit) = 99.6%**, PF 5th-pctile **1.108** (>1) — the edge survives resampling.
- **Risk-of-ruin** at 1% sizing: equity ever ≤50% of start = **0.06%**, ≤65% = 0.89%, ≤80% = 8.3%. Negligible.
- Order-shuffle (sequence risk, same trades permuted): maxDD median 24%, 95th 35%, **worst-of-20k = 54.8%**.

## ⚠️ Honesty correction on drawdown (sizing-critical)
The locked-config headline "OOS dd ~10.3%" was a **benign 4-month split window** (2026-02→05). Over a FULL
YEAR with compounding, realistic drawdown is materially larger: **observed full-year maxDD 27.7%**, MC-median
24%, **MC 95th-pctile ~38%, 99th ~47%**, shuffle worst-case ~55%. Size for a **~30–40% expected peak-to-trough**,
not 10%. Risk-of-ruin is still negligible at 1%/trade, but the equity-curve experience will include ~25%+ dips.

## 3. Anchored re-optimization walk-forward (master length re-selected per fold)

The gold-standard test: at each step re-select master-VP length on an EXPANDING in-sample, then trade it
untouched on the next OOS fold. Candidates lookback {72,96,108,120,144} = master {288,384,432,480,576} bars.

| step | IS span | pick | IS PF | OOS span | OOS n | OOS PF | OOS net% | OOS dd% | WFeff |
|------|---------|------|-------|----------|-------|--------|----------|---------|-------|
| 1 | 06-19..11-01 | 480b | 1.201 | 11-01..12-15 | 175 | 1.157 | +11.6 | 12.4 | 0.96 |
| 2 | 06-19..12-15 | 480b | 1.187 | 12-15..01-30 | 192 | 1.284 | +26.0 | 16.3 | 1.08 |
| 3 | 06-19..01-30 | 480b | 1.215 | 01-30..03-15 | 186 | 0.948 | -4.4 | 24.8 | 0.78 |
| 4 | 06-19..03-15 | 432b | 1.228 | 03-15..04-30 | 160 | 1.258 | +19.3 | 13.3 | 1.02 |
| 5 | 06-19..04-30 | 576b | 1.234 | 04-30..05-30 | 114 | 1.383 | +23.1 | 8.9 | 1.12 |

**Re-opt WF: 4/5 OOS folds PF>1, median 1.258, mean 1.206. WF-efficiency ≈ 1.0** (OOS PF ≈ IS PF — no
out-of-sample degradation; the selection process is not overfitting).

**Two decisive takeaways:**
1. The IS optimizer **always picks inside the known plateau** (480/432/576b) — it never chases an extreme or
   curve-fit value. This independently re-confirms the M5-study plateau (384–480b) is real, not a fluke.
2. **The FIXED locked-108 (432b) beats the per-fold re-optimizer on the same folds: 5/5 vs 4/5 PF>1,
   median 1.295 vs 1.258, mean 1.282 vs 1.206.** Re-tuning the lever every fold does NOT help — the only
   losing re-opt fold (step 3, 480b) was handled positively by the fixed lock. → The 432b lock generalizes
   as well or better than adaptive re-selection, so it needs **no periodic re-tuning**. Ideal WF verdict.

## Verdict
The locked M5 config is **hardened and cleared for forward-test.** It survives walk-forward (11/12 months,
7/8 equal folds, 4/5 anchored re-opt folds positive; WF-eff ~1.0), Monte-Carlo (P(profit) 99.6%, PF 5th-pctile
1.108, ruin negligible), and the fixed lever beats per-fold re-optimization (not a curve-fit). The single
actionable change is **expectation-setting, not parameter change**: plan for ~30–40% peak drawdown over a
year (not the 10% of the benign split window). No re-lock needed; EA preset unchanged, recompiles 0/0.
