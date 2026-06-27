# KenKem M3 (3×-clock) surgical sweep — TESTED → REJECT (2026-06-27)

User lever K1: extend KenKem E1/E2 to M3 via strict EMA-alignment + recalibrated quality gate.
Hypothesis: coarser bars + strict alignment = chop filter → cleaner edge than the n-constrained M1 lock.

## Setup
- **Engine constraint:** the kenkem `tick_backtester` is hardwired M1-base (resamples ×3/×5/×15 →
  M3/M5/M15 internally). Feeding the **M3 bars file** to `--bars-m1` runs the SAME strategy on a **3×
  clock** (base M3, HTF M9/M15/M45; EMA bar-counts unchanged). This is the faithful research proxy for
  "KenKem on M3". ⚠️ MT5 has no M9/M45 → a proxy winner would need a TF-mapping/engine-generalization
  step before it could deploy (never reached — arm rejected first).
- Built full-window `bars_xauusd_2024_2026_m3.csv` (283,960 bars) by resampling the lock's M1 bars.
- Sweep harness `sweep.py`; validation `validate.py`; ticks = `ticks_xauusd_2024_2026.csv` (162M).
- TRAIN = 2024→2025Q3 (to 2025-10-01); **OOS = held-out 2025Q4 + 2026** (the M1 lock's golden period).

## Bar to beat (apples-to-apples)
M1 lock (`D5-E4Long`) on the SAME train window = **PF 1.146 / net 1160 / n 396 / maxDD 512**.
(The famous 1.428 was almost entirely the held-out 2025Q4.) Full window M1 = **PF 1.329 / net 3477 / maxDD 512**.

## What we found
1. **Sample size is NOT the blocker** — M3 (3× clock) = 217 trades full / 172 train, ≫ MinTRL ~122.
   M3 is E1-dominant: E1 192, E2 ~10, E4 ~15 (E2/E4 vanish at the M1 pip settings).
2. **Raw M1 config transfers poorly** (PF 1.33→1.04) — pip/RR params mis-scaled for ~√3× bars.
3. **One dominant lever = RR.** Rescaling `E1_RR` 1.9→4.5–5.5 lifted TRAIN PF to 1.30–1.36 and healed
   the train dead-quarters (2025Q3 −158→+109). **The quality-gate levers did NOT help** — raising
   `MIN_ENTRY_ATR_PERCENTILE` or tightening `SIDEWAYS_BLOCK_THRESHOLD` both hurt. Alignment tol weak/looser-better.
   → the user's "strict alignment + recalibrated gate" hypothesis did NOT pan out; only RR moved the needle.
4. **The RR lift is OVERFITTING — dies OOS.** OOS PF **0.81–0.88, net −217…−350 at EVERY RR** (3.2→6.0);
   train↑ / OOS-flat-negative. A single **2026Q1 −534** collapse swamps the OOS window.
5. **Worse than M1 even on the full window:** M3 best (RR5.5) full = PF 1.218 / net 1646 / **maxDD 1391**
   vs M1 lock PF 1.329 / net 3477 / maxDD 512. Lower PF, <½ net, ~3× DD.
6. **Degenerate exit regime:** at RR5.5 only 10/222 trades hit TP — "wins" are trail/BE; the high RR
   sets an unreachable target and leans on the runner. Classic range-edge artifact.

## Verdict — REJECT the M3-XAU arm
Fails the build-plan decision rule on multiple axes: does NOT beat M1 on PF, robustness (OOS loser),
or DD. No gate/MT5 step reached. **KenKem M1 `D5-E4Long` stays the sole validated KenKem edge.**

## Only remaining untested variant (low prior, costly — do NOT pursue without explicit go)
The proxy used a clean ×3 HTF stack (M9/M15/M45). A "proper" M3 with MT5-native HTF (e.g. M5/M15/M30)
would require generalizing the engine to arbitrary HTF bar inputs. Prior is now negative (natural ×3
scaling overfits AND underperforms M1; gate/alignment showed no edge), so engine-generalization work is
hard to justify. Logged as the single open thread; recommend accepting M1-only for KenKem.

Repro: `research/kenkem_parity/m3_sweep/{sweep.py,validate.py,*_results.csv,validate.out}`.
