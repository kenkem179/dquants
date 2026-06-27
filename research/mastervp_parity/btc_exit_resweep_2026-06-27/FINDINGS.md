# BTC exit-geometry re-sweep — proven XAU exit on BTC entries (2026-06-27)

**Trigger (user, correct):** the BTC "no edge" verdict (`btc_revisit_2026-06-27`) was reached with the
**abandoned `InpRunnerRr=10` + wide trail + NO ProgTrail ladder** exit — NOT the capped-RR (3.2/4.0) +
late-arm ladder geometry that stabilized the validated XAU M5 lock. So BTC was never tested with the
proven exit. This re-sweep transplants the XAU exit onto the SAME BTC entries (isolates the exit effect).

## Setup
- Engine `cpp_core/build/backtester`, BTC, full window 2025-01→2026-05, `--set-all --symbol-btc
  --trade-from-ms 1735689600000`. Bars `bars_btcusd_2025_2026_{m5,m3}.csv`, ticks `ticks_btcusd_2024_2026.csv`.
- **Baseline VALIDATED:** arm A (RR10/T6/no-ladder) reproduces the revisit autopsy EXACTLY (1232 tr / net −1892).
- B = XAU geometry: `InpRunnerRr` 4.0 (and 3.2), `InpTrailAtrMult` 2.75, `InpBeBufAtr` 0.02,
  `InpPmProgTrail=true` (Trigger 2.0 / Inc 0.75 / Step 0.2), `InpTp1ClosePct` swept {0,20,33}.
- mfeR is exit-agnostic → also reports entry-quality (entry-vs-exit diagnostic).

## Results — BTC M5 (full window)
| config | n | PF | net | maxDD |
|---|--:|--:|--:|--:|
| baseline RR10/T6/no-ladder | 1232 | 0.952 | −1892 | 5021 |
| **RR3.2 / partial0 / ladder** | 1696 | **0.980** | **−1223** | 4302 |
| RR3.2 / partial20 | 1696 | 0.977 | −1426 | 4198 |
| RR3.2 / partial33 | 1696 | 0.974 | −1657 | 4151 |
| RR4.0 / partial0 | 1661 | 0.971 | −1667 | 4858 |
| RR4.0 / partial33 | 1661 | 0.961 | −2305 | 4751 |

## Results — BTC M3 (full window)
A_base PF 0.654 / −9981 / DD 10000 (account blown); B_xaugeom PF 0.684 / −9986 / DD 10212.
Exit geometry irrelevant — M3 is hopeless.

## Findings
1. **User was right + it mattered:** proven exit geometry improves BTC M5 from −1892 (PF 0.952) to
   **−1223 (PF 0.980)** — ~35% less loss, lower DD. The old verdict used the wrong (abandoned) exit.
2. **Still NOT an edge:** best BTC M5 = PF 0.980, net −1223 (LOSER). Never crosses PF 1.0. The engine
   OVER-credits BTC (Exness feed) → real MT5 worse. Not deployable; no MT5 run warranted (loser in the
   optimistic engine).
3. **Partial-banking HURTS BTC too** (monotone p0>p20>p33), same as XAU. Stability on XAU comes from the
   **late-arm ProgTrail ladder + capped RR**, NOT partial-banking (the XAU lock runs `InpTp1ClosePct=0`).
4. **Binding constraint = ENTRY quality, not exit.** Exit-agnostic mfeR: median ~0.85R, ~43% reach 1R,
   ~20% reach 2R. The better exit recovers some gap but cannot manufacture edge from entries that don't run.
   Losses concentrate in 2025 H1 (unconditioned down-grind) — the revisit autopsy already showed no regime
   filter rescues it.

## Verdict (revised after the production reconciliation below)
NOT "dead". The XAU M5 exit (ladder + capped RR) is a genuine improvement *mechanism* but doesn't flip the
FULL window positive; however the full-window loss is a **single regime**, not a flat absence of edge.

## PRODUCTION RECONCILIATION (2026-06-27 — user reported BTC profitable live; backtest AGREES)
Deployed config = `mql5/experts/.../releases/1.07/KK-MasterVP-1.07-btcusd-m5.set` — key params byte-identical
to the engine lock I tested (MasterMult30/RunnerRr10/Trail6/BeAfterTp1=true/Reversion=false) → arm A IS the
production config. Period breakdown of THAT config (`recent.py`):
| period | net | PF | n |
|---|--:|--:|--:|
| 2025 H1 | **−3,986** | 0.76 | 490 |
| 2025 H2 | +375 | 1.04 | 386 |
| 2026 | **+1,718** | 1.14 | 356 |
| full | −1,892 | 0.952 | 1232 |
**Only 2025 H1 loses; since mid-2025 BTC is net +2,093.** The user's live profit is REAL and matches the
backtest for the period they've run it. The "closed/no-edge" framing was OVER-ABSOLUTE — correct statement:
**BTC has a regime-dependent edge** (works trending/recovery, bleeds in the 2025-H1 down-grind).

**BE-after-TP1 is ESSENTIAL (user was right):** BASE (BE on) −1,892 vs BASE_noBE −2,679 = **+787 net**;
SL-WIN 228→682 (BE triples protected winners); it FLIPS 2025 H2 positive (+375 vs −337). BE was `true` in
EVERY tested config — correctly tested. (Distinct from partial-banking, which hurts — partial=close-% at
TP1; BE=move-SL-to-BE at TP1.) Ladder Trigger=1.0 is WORSE than BASE (−2,363, early-arm choke — late-arm
2.0R is better, consistent with XAU). Caveat: engine over-credits BTC → live thinner than +1,718.

**Open lever (constructive):** a regime / equity-drawdown stand-down guard to survive 2025-H1-type bleeds
while staying live in trending regimes — turns the real recent edge into a deployable one. Repro `recent.py`.
