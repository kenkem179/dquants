# KenKem D5-E4Long lock — edge-quality autopsy (2026-06-27)

Before any optimization sweep, characterize the lock's edge (the BTC-revisit lesson: know the edge shape
before you tune). Engine repro of the lock (tick engine, `bars_xauusd_2024_2026_m1.csv` + `ticks_xau_full.csv`,
2024–2026.05): **n=141, net +1,988, PF 1.517, maxDD $480 (4.8% of 10k), win 53.9%.** (MT5 lock = 126 tr /
+1,427 / PF 1.428 over a slightly longer window — engine window starts at tick-file 2025-06-19.)

## THE DOMINANT CONSTRAINT: tiny sample
n≈126–141, MinTRL≈122 (gate barely passed, PSR 0.953). **Any sweep that cuts n below ~122 breaks the gate**,
and every grid inflates the multiple-testing penalty. MasterVP-style "sweep 40 levers" is an OVERFITTING
MACHINE here. Optimization must be surgical, per-quarter-validated, and gate-deflated.

## Edge shape — REAL but NARROW and tail-heavy
- **Tail-dependence:** top-10 winners = **88% of net** (top-5 = 50%); ex-top10 PF 0.531. Expected for a small
  trend-follower (fat right tail) but it means PF 1.43 rests on ~10 trades.
- **Time concentration (the key finding):** the edge is ONE quarter.
  | Quarter | n | net | PF | win% |
  |---|--:|--:|--:|--:|
  | 2025Q3 (Jul–Sep) | **53** | **−250** | **0.83** | 43.4 |
  | 2025Q4 (Oct–Dec) | 44 | **+1,731** | 2.82 | 63.6 |
  | 2026Q1 | 18 | +407 | 1.75 | 61.1 |
  | 2026Q2 (recent) | 22 | +149 | 1.18 | 59.1 |
  **2025Q4 alone = 87% of net.** And **2025Q3 is the HIGHEST-volume quarter yet a net LOSER** — the engine
  OVER-TRADES a chop regime. 2026Q2 (most recent) is softening (PF 1.18).
- **All 3 entries + both directions positive** — do NOT disable any: E1 (62tr, PF 1.60), E2 (38tr, 1.61),
  E4 (41tr, 1.30, weakest but fine). Shorts (PF 1.64, 60% win) BEAT longs (1.42, 47.9%) — short edge is real.

## Exit breakdown — a secondary, n-SAFE leak
| exitTag | n | net | win% | note |
|---|--:|--:|--:|---|
| TP (full target) | 30 | +3,812 | 100 | the winners |
| SL-WIN (trail/BE locked +) | 37 | +1,599 | 100 | |
| SL-LOSS (full stop) | 35 | −2,800 | 0 | |
| **EA (panic/score-drop/session)** | **39** | **−623** | **23** | early-bail bucket — net-negative, 28% of all trades |

The **EA-exit bucket leaks −623 at 23% win**. mfeR-by-exitTag RESOLVES the open question: these bails are
**correctly cutting stalled non-winners**, NOT killing recoverable winners — EA mean mfeR 0.35 (only 1/39
reached ≥1R; 15/39 never went green <0.25R; SL-WIN/TP by contrast have mfeR 1.15/1.30). So **exit-tuning is
NOT the lever** (the bails already cut at ~−34 vs the −41 full-SL). The leak is almost entirely **E2**: 17 of
the 39 EA-exits, net **−582**, mfeR **0.23** (never developed). ⇒ both the 2025Q3 chop loss AND the EA-exit
leak share ONE root: **E2 (and chop-regime) entries that stall and never develop** — an ENTRY-selectivity
problem, not an exit problem. (maeR column is unpopulated/0.0 in this export — use mfeR only.)

## Strategic implication — KenKem is overfitting-sensitive & n-constrained
The lock is good (gate-PASS, MT5-confirmed, maxDD 4.8%). The edge is real but regime-concentrated (trend
quarters) and the obvious lever (cut 2025Q3 chop) is **n-constrained** — only ~19 trades of headroom before
MinTRL breaks, so entry-tightening can't go far. This bounds what "optimization" can safely mean here.

## Candidate levers (ranked by safety, all must pass per-quarter + gate)
1. **Exit-quality (EA-bail bucket)** — SAFEST (doesn't cut n). Study whether panic/score-drop exits help or
   hurt vs holding to SL/TP (model-free mfeR by exitTag). Tune `PANIC_*` / `SCORE_DROP_THRESHOLD_*` only if
   the data says the bails destroy value. Upside ~ +300–600 net, low overfit risk.
2. **Chop selectivity (existing gates)** — tune `SIDEWAYS_BLOCK_THRESHOLD`(53) / `MIN_ENTRY_ATR_PERCENTILE`(70)
   to thin 2025Q3 losers. Same class as MasterVP hour-block (tuning an existing load-bearing gate, not a new
   dimension). CONSTRAINT: cuts n → must keep n≥~122 AND not degrade 2025Q4/2026. Tight budget.
3. **Add sample (complete E5 parity)** — the only move that IMPROVES the statistics instead of fighting them
   (4th entry type → more trades → higher MinTRL headroom). But it's parity work, not tuning, and E5 has known
   hard parity gaps (indicator drift, multi-TF sideway gate not ported). Bigger effort.
4. **Validate-and-stop** — accept the lock is near its statistical ceiling; do MC/robustness hardening + demo
   forward-test rather than chase more in-sample edge.

Repro: `cpp_core/build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks
tools/ticks_xau_full.csv --symbol-xau --set research/kenkem_parity/KK-KenKem-XAUUSD-M1-D5-E4Long.set --out
tools/trades_kenkem_lock_autopsy.csv`; autopsy `/tmp/kk_autopsy.py` (per-quarter/tail/entry/exit).
