# KenKem E1 Efficiency-Ratio (ER) chop filter — findings (2026-06-22)

**Verdict: WEAK / not lockable on engine numbers. D5-E4Long stays the lock. ER feature
committed default-OFF (base parity preserved). One optional MT5 A/B offered to settle the
narrow OOS-E1 signal.**

## What it is
A new E1 entry filter: Kaufman **Efficiency Ratio** over the last `E1_ER_PERIOD` closed M1
closes ending at shift 1. `ER = |close[i1]-close[i1-N]| / Σ|Δclose|` (strictly past data, no
lookahead). If `ER < E1_ER_MIN` the E1 entry is dropped as "choppy" (`E1_ER_ABANDON=true` =
clear the cross; `false` = delay = empirically worse). `E1_ER_MIN=0.0` = OFF = **exact parity**
with the faithful clone / D5-E4Long lock. Implemented in `snapshot.hpp` (`erM1`),
`kenkem_config.hpp` (keys), `entries.hpp` (post-gate drop). `make test` 28/28 green.

## Why it looked promising (E1-only grid)
The earlier E1-only 2D grid (`e1_decomp/er_2dgrid.log`, N×thr) found `ER_PERIOD=5` dominates
N=4/6/8 across **all** thresholds; thr 0.10–0.25 is a broad E1-only plateau (~+1160, PF ~1.6
vs E1-only base +932/PF1.37). **BUT that grid ran under a limiter-choked E1-only regime (83 E1
trades); it does not transfer to the free-fire lock book (189 E1).**

## Full D5-E4Long book (engine proxy, 2024–2026, ranking-only — NOT MT5 truth)
| ER_MIN | FULL net / PF | 2026-OOS net / PF | 2026 **E1-only** net / PF / n | 26Q2 E1 net / PF |
|--------|---------------|-------------------|------------------------------|------------------|
| OFF    | 3477 / 1.33   | 462.7 / 1.29      | 20.9 / 1.02 / 23             | 177.5 / 1.29     |
| 0.10   | 3229 / 1.31   | 344.6 / 1.20      | 23.2 / 1.02 / 22             | 185.6 / 1.31     |
| 0.15   | 3401 / 1.34   | 456.8 / 1.28      | 15.0 / 1.02 / 22             | 177.5 / 1.29     |
| **0.20** | 3362 / 1.34 | **577.6 / 1.39**  | **127.0 / 1.15 / 21**        | **289.4 / 1.60** |
| 0.25   | 3327 / 1.34   | 463.3 / 1.29      | 144.6 / 1.18 / 21            | 307.1 / 1.63     |
| 0.30   | 3390 / 1.36   | 486.0 / 1.36      | 38.2 / 1.05 / 18             | 200.6 / 1.54     |

### Honest read
- **Pooled net is NET-NEGATIVE at every ER_MIN** (3327–3401 vs OFF 3477); PF only flat-to-
  marginally-better. The chop filter trims a few winners in trending in-sample quarters
  (24Q4 −213, 25Q4 −233).
- **The 2026-OOS benefit is concentrated in the trustworthy E1 book** (by-kind decomp):
  2026 OOS E1 net 20.9→127.0 (PF 1.02→1.15) at 0.20; E2 flat-positive; E4 (fictional exits)
  is noise in both directions. The headline 26Q1 "hurt" and 26Q2 "+241" were inflated by
  fictional-E4 slot-contention; the **trusted-E1** OOS gain is +106.
- **But it is a narrow spike, not a plateau:** the OOS-E1 gain exists only at 0.20–0.25 and
  vanishes at 0.15 (15.0) and 0.30 (38.2). With **n=21 E1 OOS trades**, the 0.15→0.20 jump is
  one dropped trade. This is exactly the small-n OOS spike pattern the user has been burned by.
- **Overfitting gate (engine 481-tr proxy basis):** base per-trade Sharpe 0.1098 → cand 0.1127
  (+2.6%); both PSR-vs-0 0.994, MinTRL sufficient. The engine **cannot robustly distinguish**
  the candidate from base. (DSR still n/a — grid doesn't log `sr_trial_std`.)

## Decision
- **D5-E4Long remains the KenKem XAU M1 lock** (E1+E2+E4-long; MT5 +1427/PF1.428/126tr; gate PASS).
- **ER feature committed default-OFF (ENGINE only)** — clean, no-regression infrastructure available
  for future use; base parity preserved by construction (`make test` 28/28).
- **`KK-KenKem-XAUUSD-M1-D6-E1ER.set`** (= D5-E4Long + `E1_ER_PERIOD=5 / E1_ER_MIN=0.20 /
  E1_ER_ABANDON=true`, flush-left, 416 keys) is an **ENGINE-ONLY candidate**. It is **NOT
  MT5-runnable today**: the MQL5 EA (faithful KenKemExpert clone) does not implement the ER filter,
  so loading this `.set` into the current `.ex5` silently ignores `E1_ER_*` → B ≡ A (invalid A/B).

## ⛔ Prerequisite for an MT5 A/B — and why it is deferred
A valid MT5 test requires first **porting the ER filter into the MQL5 EA** (new `input` keys
`E1_ER_PERIOD/E1_ER_MIN/E1_ER_ABANDON`, default OFF so the clone stays byte-parity, applied at the
same post-gate E1 drop site). **This port is NOT justified by the current evidence:** the engine
gain is a narrow small-n (n=21 OOS-E1) spike at 0.20–0.25, pooled net is negative, and per-trade
Sharpe barely moves (0.110→0.113). Spending complexity on the parity-validated clone for that is a
bad trade. **Recommendation: keep ER OFF / D5-E4Long lock; revisit the EA port only if a broader,
deeper re-sweep (more E1+E2 history, or a wider OOS) turns the narrow spike into a real plateau.**

If the user *does* want to settle it: port ER into the EA (default OFF), recompile headless
(`scripts/compile_mql5.sh`), clean-restart MT5 (clear Bases/MQL5 Cache, verify `E1_ER_*` appear in
the run-log input dump), then A/B — Expert **KK-KenKem**, **XAUUSD M1**, **2025.03.02–2026.05.29**,
**every tick**: A=`D5-E4Long.set` vs B=`D6-E1ER.set`; ship only if B beats A on **both** net AND PF.
