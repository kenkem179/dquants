# HANDOFF - read first, update last

Last updated: 2026-06-29 by Claude. Branch: `kenkem-rr-atr-sweep` (scratch, off `3-codex-handoff`).

## Current Goal
Push the half-optimized KenKem entries (E1/E2/E4/E5) all the way through a PROPER, gated SL+RR optimization
(user's standing request), fix the E4 profit-giveback, and give MasterVP a precise hands-off protocol. All EA
changes stay DEFAULT-OFF on this scratch branch; the live KenKem (D5-E4Long) and MasterVP (ProgTrail 9X/1%)
locks stay byte-identical until MT5 proves a change wins.

## What Just Changed (this session)
- **maeR fix — DONE & committed (`4e820b1`).** The KenKem tick trade export hardcoded maeR=0.00; added a
  mirrored `worstPrice` tracker (analytics-only, drives no behavior) → maeR now populated. Verified: clean
  winners maeR≈0, stops show real 0.55–0.80R adverse. Unblocks all SL/exit work.
- **MasterVP protocol — DONE & committed (`bf823be`).** `research/mastervp_parity/MASTERVP_PROTOCOL.md`:
  9X-on-1% is REAL (came from MT5, not engine) & FROZEN; engine over-credits exits ~30% so it may NEVER pick a
  MasterVP exit change again — exits are MT5-only; 4 giveback families stay closed; one open lever =
  regime-conditioned exit (OU half-life), still MT5-gated. One MT5 ask = full-window `InpExportParity` export.
- **Exit-giveback + SL analysis — DONE & committed (`bf823be`).**
  `research/kenkem_parity/EXIT_GIVEBACK_AND_SL_ANALYSIS.md` (+ `exit_giveback_analysis.py`). HONEST finding:
  the "E4 bleeds all its profit" story is a **~4% effect** (~$67 genuinely round-tripped vs +$1,827 net). E4
  *already has* laddered+partial TP, armed at 1.68R but trades peak ~0.79R. **The real lever is SL geometry**:
  losers stop at 0.55–0.80R adverse while winners rarely dip past 0.75R → per-entry SL tightening is the
  measurable edge.
- **Tick-engine SL/RR sensitivity sweep — RUNNING.** `research/optimization/sweep_kenkem_sl_rr_tick.py`
  (NEW). Sweeps 15 live, EA-honorable SL/RR/exit knobs one-at-a-time around the lock on the TICK engine
  (the prior harness `optimize_kenkem.py` used the BAR engine = P&L-sign defect = why these were mis-tuned),
  full window, 2025-train/2026-test split. Output → `sweep_kenkem_sl_rr_tick.{csv,out}`. ~65 runs @18s.

## Key facts established
- Per-entry (lock, full window, 198 trades): E1 +1019/PF~ (mfeR .74, maeR .46), E2 +368 (mfeR .56), E4
  +808 (mfeR .91). Capture 12–19% but that's dominated by losers, not surrendered winners.
- **E4 borrows E2's ATR-SL cap/floor** by design (entries.hpp:62, MT5 parity) → `E4_ATR_SL_*` is DEAD; sweep
  E2's cap to move E4's stop. `SL_EMA_DISTANCE=27` and `E5_MIN_SL_PIPS=50` are fixed-pip → ATR-relative targets.
- 450 EA inputs; only 3 truly dead (E4 ATR-SL trio, parity-clutter). Real overfit surface = per-entry ladder
  magic-multipliers, never swept.

## Exact Next Action
1. **When the sensitivity sweep finishes:** read `sweep_kenkem_sl_rr_tick.out`, identify PLATEAUS (not peaks)
   where train>0 AND test>0, per knob. Write findings doc. Then a focused JOINT refine around the plateaus
   (small grid / coordinate) and run the winner through `research/stats/gate.py` (DSR/PSR/MinTRL, with
   n_trials + sr_trial_std from the sweep). Only a DSR-PASS config becomes a candidate `.set`.
2. **E4 anti-bleed:** fold into the sweep — the `E4_PARTIAL_TP_TRIGGER` curve shows whether arming the bank
   earlier (0.5–0.7) helps; respect the fat-tail caution (early-bank has been 0%-optimum elsewhere).
3. **Then:** E2 rejection scaffold (#4, default-OFF, now unblocked by maeR — re-check E2 adverse side first),
   and prune dead params (#5, after the sweep shows which knobs matter).
4. **MT5 confirm** any gated candidate before it can ever be a lock (engine ranks, MT5 judges).

## Decisions To Preserve
- Released `.ex5`/`.set` byte-identical; all work on scratch branch `kenkem-rr-atr-sweep`.
- Sweeps run on the TICK engine only (bar engine has the P&L-sign defect). MT5 is the final judge of any lock.
- MasterVP exits are MT5-only forever (engine over-credits ~30%); its 9X/1% lock is frozen.
- E4's dead ATR-SL keys are parity-faithful — do NOT "fix" them blindly; give E4 its own SL only as a
  default-OFF change if the sweep justifies it.
