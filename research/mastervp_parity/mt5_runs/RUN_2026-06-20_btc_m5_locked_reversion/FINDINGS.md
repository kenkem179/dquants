# BTC M5 MasterVP (T3 reversion lock) — MT5 DISCONFIRMS the engine (2026-06-20)

User ran the **locked BTC M5 `.set` (reversion=true)** in MT5. Result was "bad, not as good as XAU."
Collected here: `trades_BTCUSD-Exnes-0406_PERIOD_M5.csv` (757 MT5 trades), the XAU M5 run from the
same session (for contrast), the locked set, and the inputs echo.

## Headline: BTC M5 is NOT live-deployable; the reversion lock is an engine artifact

MT5 inputs confirmed = the locked config (`InpEnableReversion=true`, `InpMasterMult=30`,
`InpVpLookback=24`, `InpSlAtrBrk=2.2`, `InpSlAtrRev=1.2`, `InpTrailAtrMult=6.0`, body 0.4, 24/7).

Fair comparison over the **overlapping window** (engine is missing Dec-2025 + has a stray Jan-2025
trade; restricted both to 2025-06-20→2025-11-30 ∪ 2026-01-04→2026-05-29):

| Metric | Engine | MT5 | |
|---|---|---|---|
| Trades | 706 | 683 | similar |
| Net USD | +10,129 | **+1,761** | engine 5.7× inflated |
| PF | 1.293 | **1.058** | ≈ breakeven live |
| Win % | 59.6 | **51.2** | engine over-wins +8.4 pts |
| **Reversion net** | **+5,414** (n129) | **−76** (n90) | the whole T3 thesis is fictional |

(Full unrestricted: engine 743tr +8,983 PF1.232 win60%; MT5 757tr +968 PF1.028 win50.5%.)

## Why (trade-level match, ±5min same-dir)

- Only **434/757 MT5 trades match an engine trade** (57%). 323 MT5-only, 309 engine-only — a
  fundamentally different entry set, not just timing jitter. (XAU M5 parity matched ~86%.)
- On **matched** trades exits agree **388/434 (89%)**, but matched net still diverges (MT5 +1,528 vs
  ENG +5,042): the drain is **39 "engine SL-WIN → MT5 SL-LOSS"** — the engine locks a trailing win
  where the real tick path round-trips to a loss.
- **engine-only trades net +3,941** (the engine cherry-picks a favorable trade set its tick sim sees);
  MT5 never takes them.
- **Reversion specifically:** on the 66 matched rev trades MT5 +124 ≈ ENG +163 (agree!). The engine's
  headline +5,414 comes almost entirely from rev trades MT5 **doesn't take** or that round-trip → live
  reversion ≈ breakeven, NOT the +62% the WF engine sweep claimed.

## Root cause (consistent with all prior BTC work)

The BTC/Exness feed's intrabar **round-trip** behavior. The Pine-faithful study already measured it: a
break that reaches 0.8R continues to 1.8R ~**94%** on OANDA but only ~**45%** on this MT5/Exness feed.
The C++ tick engine's runner-trail simulation is too optimistic about that continuation on BTC, so it
over-wins by ~8 pts and manufactures a reversion edge that the real feed doesn't pay. Same shape as
Monster BTC M3 (engine PF 1.178 → MT5 1.031).

## Decision

1. **BTC M5 MasterVP = NOT deployable** (live PF ~1.06, net ~+1.8k/yr — not worth ~28% MC drawdown).
2. **Revert the BTC T3 reversion lock** (`InpEnableReversion` true→false) in the engine set + EA preset:
   its sole justification (engine +62% / revNet +5,158) is MT5-disconfirmed (revNet −76).
3. **XAU M5 stays the validated front-runner** (same session MT5: +60,264, PF 1.400, 1294 trades).
4. BTC would need the engine↔MT5 entry-selection gap closed (the 57% match rate) before any BTC lock is
   trustworthy — and even then the feed's round-trip caps the achievable edge. Deprioritized vs XAU M5.
