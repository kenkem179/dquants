# H9 EXIT-cluster MT5 optimizer — RESULTS (2026-06-26)

Source: MT5 Strategy-Tester optimizer, **KK-MasterVP-Debug**, XAUUSD M5, every-tick real ticks,
2025.06.01→2026.05.29, deposit 10k, Exness feed. Parsed from the binary `.opt` caches via
`scripts/parse_mt5_opt.py` (layout validated by reproducing Run A's ReportOptimizer XML exactly).
In-frame lock baseline (no ladder, no partial) = **net 87,838 / PF 1.436 / DD 14.5% / 1425 tr**
(this optimizer's PF for the committed lock; net == committed 87,836).

## Run A — Partial-TP bank (InpTp1R × InpTp1ClosePct, 30 passes) → LOCK HOLDS
Winner = `InpTp1ClosePct=0` (no bank): 87,838 / 1.436 / DD 14.5 / 1425 tr. Every nonzero close-% has
strictly lower PF and inflates trade count. **Partial-TP rejected again** (consistent with all priors).
CSV: `H9_A_partialTP.csv`.

## Run B — BE × Trail × RR (80 passes) → ⚠️ INVALID / CONTAMINATED, must re-run
Run B was executed with **`InpPmProgTrail=true` left ON in the base at the bad default ladder
(Trigger 1.0 / Increment 0.5 / Step 0.1)**. Proof: B's lock-coordinate row `(BeBuf0.02, RR4.0,
Trail2.75)` = `64386.51 / 1.3698 / 1427 / DD20.05` is **byte-identical** to Run C's `(1.0/0.5/0.1)`
row. So every B pass had a runner-choking ladder underneath → the BE×Trail×RR geometry could not be
judged. B's apparent "winner" (PF 1.415) is meaningless. **Re-run B with `InpPmProgTrail=false`.**
CSV: `H9_B_BeTrailRr_CONTAMINATED.csv` (kept for the record, do not trust).

## Run C — Progressive-trail ladder (Trigger × Increment × Step, 36 passes) → 🟢 WINNER CANDIDATE
ProgTrail ON, lock exit geometry as base. **16/36 passes beat the lock PF.** The signal is clean:
**arm the ladder LATE.** All Trigger=2.0 passes dominate; Trigger=1.0 (arm early) is worst (chokes the
runner — that's the same leak that contaminated B).

Robust plateau (Trigger 2.0, Increment ≥0.5) — 8 configs within PF 0.010:

| Trigger | Increment | Step | Net | PF | DD% | Trd |
|--------:|----------:|-----:|----:|---:|----:|----:|
| 2.0 | 1.0  | 0.3 | 91,021 | 1.448 | 14.5 | 1425 |
| 2.0 | 0.5  | 0.1 | 90,932 | 1.449 | 14.5 | 1425 |
| 2.0 | 0.75 | 0.2 | 90,781 | 1.448 | 14.5 | 1425 |
| 2.0 | 1.0  | 0.2 | 90,478 | 1.447 | 14.5 | 1425 |
| 2.0 | 0.75 | 0.3 | 90,097 | **1.450** | 14.4 | 1427 |
| 2.0 | 0.5  | 0.2 | 90,295 | 1.449 | 14.4 | 1426 |

vs lock baseline 87,838 / 1.436 / 14.5. **Best beats lock on PF (+0.014), net (+~3k) AND DD (tied/better),
same ~1425 trades** (entries unchanged — pure exit improvement). Avoid Increment 0.25 (degrades, DD→22%).
Suggested central pick: **Trigger 2.0 / Increment 0.75 / Step 0.2** (90,781 / 1.448 / DD 14.5).
CSV: `H9_C_progTrailLadder.csv`.

### Before this can be locked (SOP) — VALIDATION PREPPED 2026-06-26
Chosen winner = central plateau pick **Trigger 2.0 / Increment 0.75 / Step 0.2** (90,781 / PF 1.448 / DD 14.5).
Validation `.set` written: **`KK-MasterVP-XAUUSD-M5-H9C-Validate.set`** (production EA, `InpExportParity=true`,
ProgTrail ON at the winner). It is the lock with ONLY the 4 ProgTrail keys flipped. Synced to Presets.

Sweep dispersion (36 passes, for the gate): ExpPayoff mean 53.26 / std 8.60 USD/trade; PF mean 1.398 / std
0.045; winner ExpPayoff 63.71. `sr_trial_std` (in gate per-trade units) = std(ExpPayoff)/σ_usd_pertrade —
σ comes from the winner's `trades_*.csv` (computed once the FULL run is in). n_trials = 36.

VALIDATION PROGRESS:
- ✅ **Run 1 (FULL) DONE 2026-06-26.** Flat-risk trade stream (`trades_H9C_validate_full.csv`):
  **net 86,034 / PF 1.4246 / 1423 tr / 52.5% win**, vs lock flat-risk stream (83,227 / PF 1.413) →
  beats lock on net (+3.4%) AND PF (+0.012). σ_usd/trade = 635.05 → `sr_trial_std` = std(EP)/σ = 8.60/635 = 0.0135.
- ✅ **GATE PASS.** `gate.py --n-trials 36 --sr-trial-std 0.0135`: per-trade Sharpe 0.109 (lock 0.108),
  PSR 1.000, MinTRL 192<1423, **DSR 1.000 → PASS**.
- ⚠️ **Run 2 (2025 H2, 2025.06–12) MARGINAL MISS.** `trades_H9C_validate_2025H2.csv`: 858 tr, net 24,847,
  **PF 1.3577** vs lock 2025 bar 1.367 → −0.009 (≈0.7% rel). Within window/run noise but does NOT clear the
  "beat lock on both halves" bar outright. ⇒ pooled win must be carried by 2026; Run 3 is decisive.
- ✅ **Run 3 (2026.01–05) BEATS.** `trades_H9C_validate_2026.csv`: 559 tr, net 16,280, **PF 1.4511** vs
  lock 2026 bar 1.437 → +0.014. Win rate 53.3%.
- **SCORECARD:** pooled 1.4246>1.413 ✅, 2025H2 1.3577<1.367 ⚠️(−0.009), 2026 1.4511>1.437 ✅, gate PASS.
  Wins pooled + recent year + gate; marginal slip on 2025H2 vs a REMEMBERED bar.
- ✅ **TIE-BREAKER: 2025H2 is an EXACT TIE.** Lock on same window (`trades_LOCK_2025H2.csv`) = PF **1.3577**,
  858 tr, net **24,846.59** — BYTE-IDENTICAL to the candidate's 2025H2 stream. ⇒ the late-arm ladder (2.0R)
  is **completely INERT in 2025H2** (no runner armed it). The "miss" was a phantom (remembered 1.367 = wrong
  window). Candidate does NOT lose 2025H2; it EQUALS the lock. Ladder = free option (inert w/o big runner,
  additive with one — all the edge is in 2026).
- ⏳ **FINAL run PENDING:** LOCK full 2025.06.01→2026.05.29 to get lock's TRUE pooled + 2026 (no remembered
  numbers). Candidate already ties 2025H2; if candidate ≥ lock pooled & 2026 → LOCK C.

Remaining steps (need MT5 — user action):
1. **Run the validation `.set` 3×** on KK-MasterVP / XAUUSD / M5 / every-tick real ticks / deposit 10000:
   (a) FULL 2025.06.01→2026.05.29, (b) 2025.06.01→2025.12.31, (c) 2026.01.01→2026.05.29.
   Must beat lock (full PF 1.436; 2025 sub 1.367; 2026 sub 1.437) on BOTH sub-folds.
2. From run (a) `trades_*.csv` → `research/stats/gate.py --n-trials 36 --sr-trial-std <std(EP)/σ>` → need DSR≥0.95.
3. Only then: copy the 4 ProgTrail keys into the lock `.set`, re-lock, update best-experts table
   (ladder already in `ProfitManager.mqh`; `.set`-only change). Then `make release`.
