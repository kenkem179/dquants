# KK-MasterVP — TP1 + "move SL closer to entry" validation (2026-06-23)

Validates the user's two ideas with the **correct (simple) reading**, not the previous agent's
over-engineered VP "conviction-protect" (which 6-fold WF already rejected, see
`TP1_CONVICTION_STUDY_2026-06-22.md`). Method: generalized 6-fold WF across all 4 markets
(`wf_mvp_generic.py`, BTC/XAU × M3/M5, shared `slice_ticks_by_fold.FOLDS`). Standing bar (T1 rule):
adopt only if it **improves pooled AND does not degrade the worst-fold PF**.

Baselines reproduce the prior study exactly (XAU-M5 PF 1.344/net 23,098) → slices trustworthy.

## Idea 1 — "improve with TP1" = bank a partial at TP1 (`InpTp1ClosePct`)  → REJECTED
`g1` grid `InpTp1ClosePct{0,20,33,50} × InpTrailAtrMult{2.0,2.5,3.5,6.0}`, all 4 markets.
- Banking ANY partial **monotonically hurts** every axis on every market (caps the trailed runner).
  XAU-M5: 0%→PF1.344, 20%→1.265, 33%→1.230, 50%→1.174 (at lock trail). Same shape XAU-M3/BTC.
- This re-confirms the 2026-06-20 T3-exit lock (`InpTp1ClosePct=0`) on a broader 4-market basis.

## Idea 2 — "move SL closer to entry"  → REJECTED (all readings, all markets)
Tested every reading of "closer to entry":
- **g3_be** = break-even ratchet `InpTp1R{0.5,0.8,1.0} × InpBeBufAtr{0.0,0.05,0.15}`.
  - XAU-M5: best = SL exactly to entry (`BeBuf 0.0`) PF 1.350 — a *microscopic* pooled bump but
    **worst-fold 1.223→1.175 (degrades)** → fails the T1 rule. Bigger buffer / earlier arm = worse.
  - XAU-M3 / BTC-M5: flat-to-worse, no fold-count improvement.
- **g4_sl** = tighter initial stop `InpSlAtrBrk{0.8,1.0,1.2,1.5}`.
  - XAU-M5: baseline 1.2 is best; tighter (1.0/0.8) cut PF 1.344→1.289→1.277 and crush worst-fold
    1.223→1.084→1.022. **Tightening strictly hurts.**
  - BTC-M5: tighter SL is **catastrophic** (PF 0.91–1.00, dd 43–74%, net negative) — chopped out.
- **Confirmed on the better base too** (`confirm_on35`): on trail-3.5, moving SL to entry drops
  PF 1.472→1.454 and banking 20% drops it to 1.427. Both ideas hurt on BOTH bases, direction-consistent.

**Why:** the edge is a trend runner. Every move that pulls the stop IN (partial bank, earlier/closer
BE, tighter initial SL) chops winners and costs more across the book than it saves on the occasional
giveback. The motivating "gave back >50%" chart was **survivorship** (same lesson as FVG / VMC /
conviction-protect). Protecting the giveback is the wrong direction for this strategy.

## The genuine win that emerged — the OPPOSITE direction: WIDER runner trail (XAU-M5 only)
`InpTrailAtrMult` 2.5 → **3.5** lets the runner breathe more.

| trail | PF | net | dd% | worstPF | folds |
|---|---|---|---|---|---|
| 2.5 (lock) | 1.344 | 23,098 | 7.8 | 1.223 | 6/6 |
| 3.0 | 1.369 | 23,236 | 10.0 | 1.167 | 6/6 |
| **3.5** | **1.472** | **28,616** | **7.4** | **1.316** | 6/6 |
| 4.0 | 1.453 | 26,180 | 8.5 | 1.287 | 6/6 |
| 4.5 | 1.383 | 21,102 | 9.7 | 1.228 | 6/6 |

- Beats the lock on **every axis** (pooled PF, net, dd, worst-fold), all 6/6 folds.
- **Plateau, not a peak** — 4.0 corroborates; smooth hill 3.0→3.5→4.0→4.5.
- **Overfitting gate PASS** (`research/stats/gate.py`, n_trials=28, sr_trial_std=0.00792):
  per-trade Sharpe 0.096, PSR-vs-0 **1.000**, MinTRL **194 < 1207** (sufficient), **DSR 1.000** → PASS.
- **Zero parity risk:** `InpTrailAtrMult` is an existing, already-MT5-confirmed EA input. The change ships
  as a `.set` value only — NO new C++/MQL logic, NO recompile. (Unlike conviction-protect.)
- Other markets: XAU-M3 trail noisy (≤4/6 folds, weak worst-fold); BTC-M5 trail flat; BTC-M3 dead. The
  trail win is **XAU-M5 specific** — do not generalize.

## Disposition
- Idea 1 (TP1 bank) and Idea 2 (move SL closer to entry): **validated and REJECTED** by 6-fold WF — they
  are not portfolio improvements; both hurt. The discretionary conviction-protect infra stays default-OFF.
- **trail-3.5 = engine-validated candidate** (gate-PASS), `.set`-only, parity-safe. Per parity-is-gate-0
  the engine is a ranking proxy → **needs MT5 A/B before locking.** Candidate preset:
  `mql5/experts/KK-MasterVP/KK-MasterVP-XAUUSD-M5-Trail35.set` (vs live `...-M5.set`). Lock on MT5 confirm.
</content>
</invoke>
