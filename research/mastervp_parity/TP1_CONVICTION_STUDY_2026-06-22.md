# TP1 / profit-protection redesign — giveback-cap + conviction-protect (2026-06-22)

## Motivation
User showed a BTC winner that nearly hit full TP then retraced, handing back >50% of the move, and asked
to revise the no-TP1 policy: bank a partial **with conviction** when the VP histogram (near-price verdict
/ net volume delta) shows strong flow against the trade — not blindly. Chosen action: **partial bank +
tighten stop**.

## What was built (both default-OFF, base byte-identical — `make test` 37/37 + golden parity green)
- **(A) Giveback-cap (blind)** — `kk::common::ProfitManager` #3, already wired engine-side. Once MFE ≥
  `arm_r`, ratchet the stop so it can never give back more than `cap_frac` of PEAK gain. Keys
  `InpPmGiveback / InpPmGivebackArmR / InpPmGivebackCapFrac`.
- **(B) Conviction-protect (the user's idea)** — NEW. Once MFE ≥ `arm_r` AND the **near-price VP node-net**
  flips against the position (long: net ≤ −`net_min`; short: ≥ +`net_min` — the panel's "Net ▼/over"
  verdict), bank a one-shot partial AND ratchet the stop to lock `lock_frac` of the peak. Keys
  `InpEnableConvictionProtect / InpConvictionArmR / InpConvictionNetMin / InpConvictionPartialFrac /
  InpConvictionLockFrac`. Engine wires a per-bar near-price node-net array (`node_net_close_`) read at
  management cadence; `PositionManager::conviction_protect()` does the one-shot partial+tighten.

## Single train/OOS split (looked promising)
`tp1_conviction_sweep_2026-06-22.py`. On XAU-M5 OOS, `conv arm1.0 net0.2` improved all three axes (PF
1.322→1.409, net +3470→+4796, dd 12.3→10.1%) with TRAIN preserved. BTC-M5 `conv p0.3 lk0.6` jumped OOS
net +5116→+9655. XAU-M3 was marginal-to-negative.

## Walk-forward (6 disjoint folds, XAU-M5) — the honest test KILLS the lock case
`wf_mastervp.py`. Baseline POOLED **PF 1.344 / net 23,098 / dd 7.8% / worstPF 1.223 / 6-6 folds+**.

| config | POOLED PF | net | dd% | worstPF |
|---|---|---|---|---|
| **BASELINE (all OFF)** | **1.344** | **23,098** | 7.8 | **1.223** |
| conv arm1.0 net0.2 | 1.354 | 24,406 | **7.1** | 1.192 |
| conv arm1.0 net0.3 | 1.345 | 23,536 | 8.2 | 1.202 |
| conv arm2.0 net0.3 | 1.340 | 22,790 | 8.1 | 1.206 |
| conv arm3.0 net0.3 | 1.325 | 21,596 | 8.0 | 1.207 |
| giveback arm3.0 cap0.3 | 1.314 | 22,376 | 7.7 | 1.106 |
| giveback arm2.0 cap0.3 | 1.241 | 17,450 | 10.6 | 1.090 |

**Verdict: NO LOCK.** Every variant **degrades the worst-fold PF** (baseline 1.223 is the best). The blind
giveback cuts winners hard (net −24% at arm2.0). The single best variant, `conv arm1.0 net0.2`, improves
*pooled* net (+5.7%) and dd (7.8→7.1%) — but at a worse worst fold (1.223→1.192) and 2/6 folds slightly
down. It fails the repo's standing bar: *improve pooled AND not degrade the worst fold* (the T1 lesson,
`[[mastervp-m5-gate-sweep-lock]]`). The baseline already has both the best pooled PF and the best worst fold.

## Why the chart was misleading (the real lesson, again)
The motivating screenshot was **survivorship** — same trap as the FVG before/after charts
(`HANDOFF` FVG section) and the VMC module. Protecting that one giveback costs more across the full book
(cutting other winners early / re-entering into chop) than it saves. The 2.0×ATR chandelier trail on the
runner is already near-optimal on a portfolio basis for XAU-M5.

## Status of the other targets
- **XAU-M3:** single-split marginal-to-negative (protective exits cost TRAIN net for ≈flat OOS); base
  rides best. Not pursued to WF.
- **BTC-M5:** single-split showed a large OOS jump (`conv p0.3 lk0.6`, +88% OOS net) BUT (1) single window,
  (2) the BTC/Exness feed is the one memory flags as MT5-OVER-optimistic on intrabar round-trips
  (`[[mastervp-t3-reversion-lock]]` — engine reversion/partial wins there were FICTIONAL vs MT5). No BTC
  fold harness exists; **do not trust or lock without a BTC walk-forward + an MT5 A/B.** Flagged, not chased.

## Disposition
Both features ship as **tested, default-OFF infrastructure** (zero effect on every current lock). The user
can toggle them on a specific chart if they want the discretionary peace-of-mind behaviour, but on the
evidence they are **not** a portfolio improvement and are **not** locked. If revisited: the only avenue
with any signal is BTC-M5 `conv p0.3 lk0.6` — and only behind a proper BTC WF + MT5 confirmation.
