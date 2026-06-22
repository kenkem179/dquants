# MT5 A/B — XAU M5 trail 2.5 (lock) vs 3.5 (engine candidate) — 2026-06-23

Expert `Experts\dquants\KK-MasterVP\KK-MasterVP.ex5`, XAUUSD-Exness-KK M5, 2025.06.01→2026.05.29,
every-tick (94,173,877 ticks / 70,302 bars both runs), deposit 10,000, leverage 1:500. The two runs differ
ONLY in `InpTrailAtrMult` (verified in the inputs echo — all other keys identical).

## Result — the engine's ranking FLIPPED in MT5
| run | InpTrailAtrMult | MT5 final balance | **MT5 net** | engine WF prediction |
|---|---|---|---|---|
| **B — current lock** | 2.5 | 72,731.58 | **+62,732** | pooled PF 1.344 (baseline) |
| **A — candidate** | 3.5 | 57,791.10 | **+47,791** (PF 1.388, 1290 tr, win 55.3%, maxDD 14.0%) | pooled PF 1.472, +24% — "clean win" |

**Candidate A is −$14,940 (−24%) vs the lock.** The C++ engine 6-fold WF had ranked trail 3.5 as a clear,
gate-PASS winner (+24% net, better worst-fold). MT5 says the exact opposite. **Lock stays at trail 2.5.**

## Root cause — engine over-credits the trailed runner (exit-model parity gap)
A wider chandelier trail (3.5×ATR) keeps the runner's stop farther from price so it rides longer. The C++
tick engine books the continuation the runner "captures"; MT5's real intrabar tick path gives a chunk of it
back before the wider stop triggers. So wider = better in the engine, worse in reality. Same family as the
documented "engine runner-trail too optimistic" / BTC-reversion-fictional caveats
([[mastervp-t3-reversion-lock]], [[parity-is-gate-0]]).

## The consequence that matters (reframes the whole TP1/SL question)
Every exit-side verdict from the 2026-06-23 engine WF was computed on this same over-optimistic runner model:
- engine said **TP1 partial bank "hurts"** → because banking *caps the (partly fictional) runner*.
- engine said **move SL closer / tighter "hurts"** → because it *cuts the (partly fictional) runner*.
- engine said **wider trail 3.5 "helps"** → because it *lets the (partly fictional) runner ride* — and THAT
  one we could MT5-check, and it was FALSE.

→ **The engine systematically biases AGAINST the user's protect-the-winner ideas.** Their engine-rejection is
not trustworthy. MT5's 2.5≫3.5 (tighter runner protection wins) is direct evidence the user's instinct may be
right. **TP1-bank and move-SL-closer must be judged in MT5, not the engine.** Next: MT5 A/B those levers +
a DOWNWARD trail sweep (2.0, 1.5) on this same window. All are existing EA inputs → zero parity risk.
</content>
