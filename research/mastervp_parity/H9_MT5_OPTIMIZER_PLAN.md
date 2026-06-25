# H9 — Re-validate the MasterVP EXIT cluster on the MT5 optimizer (2026-06-26)

**Why this is the #1 MT5 work item.** The C++ engine's exit model is **untrusted** — it over-credits the
trailed runner. The proof: the current FINAL LOCK (RunnerRr 4.0 / TrailAtrMult 2.75 / BeBuf 0.02) was found
by **you, on the MT5 Strategy-Tester optimizer** (fine step 0.25), *after* the engine's step-1.0 view missed
it. So every exit-side lever the engine previously "rejected" (partial/laddered TP, profit-lock ladder,
BE/trail geometry) must be **re-judged on MT5**, not the engine. When MT5 disagrees with an engine verdict,
**MT5 wins.**

These are all `.set`-only sweeps — **zero parity risk, no recompile of the strategy logic.**

---

## NEW: use the **KK-MasterVP-Debug** EA for sweeps

To avoid the "which params are exposed?" struggle, there is now a dedicated internal sweep build:

- **`KK-MasterVP-Debug.mq5`** (`Experts\dquants\KK-MasterVP\KK-MasterVP-Debug.ex5`) — identical engine and
  identical compiled-in defaults as the shipped `KK-MasterVP`, but it `#define`s `KK_DEBUG_EXPOSE_ALL`, which
  flips the `KK_IN` macro in `Inputs.mqh` so **every hidden strategy param becomes a visible `input`** (VP
  length, regime, SL/RR, the `InpPm*` profit-lock ladder, partial-TP, etc.). The curated/marketplace
  `KK-MasterVP` is **byte-identical and unchanged** (KK_IN expands to nothing there; the market-edition text
  transform never sees these as inputs). Account-lock / expiry globals are deliberately NOT exposed.
- **Behaviour is identical at default inputs** → loading a lock `.set` on the Debug EA reproduces the lock.
- **Never ship KK-MasterVP-Debug.** It exists only for the optimizer.

Grids A and B use keys that are `input` in BOTH builds, so they run on either EA. Grid C needs the Debug EA.

---

## Common Strategy-Tester settings (all grids)

| Field | Value |
|---|---|
| Expert | **KK-MasterVP-Debug** (or KK-MasterVP for A/B) |
| Symbol | **XAUUSD** |
| Timeframe (attach) | **M5** |
| Modelling | **Every tick based on real ticks** |
| Date range | **2025.06.01 → 2026.05.29** |
| Deposit | **10000** (USD) |
| Optimization | **Slow complete algorithm** (exhaustive — grids are small) |
| Optimized criterion | **Profit Factor** (rank on PF, NOT net profit) |

**Ranking rule (load-bearing):** rank by **Profit Factor + robustness**, never peak net. The rejected
RR3.2/T2.75 corner had higher raw net (92k) but lower PF (1.357) and a weakening recent year — that is the
net-chasing trap. A candidate only replaces the lock if it beats **PF 1.413** AND does not worsen
**maxDD (~21% trade-close)** AND holds up on **both year sub-folds** (2025.06–2025.12 and 2026.01–2026.05),
then passes the overfitting gate (`research/stats/gate.py`, recording `n_trials` + `sr_trial_std` from the
optimization report). Otherwise the lock stands (a flat plateau is an anti-overfit win, not a failure).

---

## The grids (load each `.set` via Tester → Inputs → Load, from `dquants/KK-MasterVP/`)

### Grid A — Partial-TP bank  ·  `KK-MasterVP-XAUUSD-M5-H9-OPT-A-PartialTP.set`  ·  30 passes
The simplest "bank a partial at TP1, let the rest run" test. Sweeps `InpTp1ClosePct` (0→50 step 10) ×
`InpTp1R` (0.6→1.4 step 0.2). The `InpTp1ClosePct=0` row IS the lock baseline / control. Runs on either EA.

### Grid B — BE × Trail × RR plateau  ·  `KK-MasterVP-XAUUSD-M5-H9-OPT-B-BeTrailRr.set`  ·  80 passes
Re-confirms the exit-geometry plateau around the lock. Sweeps `InpBeBufAtr` (0.00→0.06/0.02) ×
`InpTrailAtrMult` (2.25→3.25/0.25) × `InpRunnerRr` (3.5→5.0/0.5). Lock = (0.02, 2.75, 4.0). Runs on either EA.

### Grid C — Profit-lock progressive-trail ladder  ·  `KK-MasterVP-XAUUSD-M5-H9-OPT-C-ProgTrailLadder.set`  ·  36 passes  ·  **Debug EA only**
The user's "ratchet the SL to bank profit" / laddered idea. Forces `InpPmProgTrail=true` and sweeps
`InpPmProgTriggerR` × `InpPmProgIncrementR` × `InpPmProgStepR`. This is a smooth profit-banking ladder on top
of the existing BE + chandelier trail.

---

## ⚠️ What is NOT yet a single mechanism (needs a code build to greenlight)

A **true discrete multi-rung laddered TP** — e.g. *bank 1/3 at 1R, 1/3 at 2R, trail the final third* — is
**not built**. The closest existing levers are:
- **Grid A** `InpTp1ClosePct` — one fractional bank at TP1.
- **Grid C** `InpPmProgTrail` — a smooth continuous ratchet (not discrete rungs).
- `InpPmPartialTp` (Debug-exposed) — one ProfitManager fractional bank at a trigger R.

If, after seeing A/C results, you want genuine N-rung banking (a vector of (R-level, fraction) rungs), that
is a **~1 evening C++ + MQL build** (new `pm_ladder` in `ProfitManager.mqh` + engine mirror, default-OFF,
golden-parity byte-identical). Flag it and I'll build it behind a default-OFF toggle, then add a Grid D.

## Order to run (highest signal first)
1. **Grid A** (partial bank) — the cleanest, smallest, directly answers "does banking help now on MT5".
2. **Grid C** (prog-trail ladder) — the ratchet idea, on the Debug EA.
3. **Grid B** (BE×Trail×RR) — re-confirm the plateau (expected: lock holds).

After any winner: 2-year sub-fold check → `research/stats/gate.py` → only then re-lock + update the
best-experts table + `make release STRATEGY=KK-MasterVP`.
