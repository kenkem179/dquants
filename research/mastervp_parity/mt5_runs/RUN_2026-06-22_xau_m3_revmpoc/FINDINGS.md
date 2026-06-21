# KK-MasterVP XAU M3 RevMpoc (2026-06-22) — "67% win but thin net" explained

Real-tick $10k, 2025.01→2026.06.09. Preset `KK-MasterVP-XAUUSD-M3-RevMpoc.set`
(`InpTp1ClosePct=20`, `InpTrailRev=0` bank reversion@mPOC). Final balance **$14,712** (+47%).

## Round-trip economics (my CSV groups deals into 2949 round-trip trades)
- n=2949, **trade-level win=51.0%**, PF **1.030**, net **+4,713**, expectancy **+$1.60/trade** (≈ breakeven).
- avg WIN +106.65 / **median win +28.61**  vs  avg LOSS −107.60 / **median loss −109.82**.
- payoff ratio (avgWin/|avgLoss|) = **0.99**. Symmetric payoff + ~50% win = NO edge.

## Why "67% profitable" in the MT5 report yet thin net
1. **MT5 counts DEALS, not round-trips.** `InpTp1ClosePct=20` banks a 20% partial at TP1 → that partial
   is a separate *winning deal*. So most positions log a small green TP1 deal, inflating the report's
   "% profit trades" to ~67% — while the round-trip win rate is only **51%**.
2. **mPOC banking caps winners, losers run full.** Reversion exits bank at mPOC = small R; the median
   WIN is +$28 but the median LOSS is −$110 (~3.8× bigger). You win a bit more often but each loss
   erases ~4 typical wins → expectancy collapses to ~$0.
3. Only a few runners (max +$1,230; the 69 full-TP deals avg +$247) drag PF barely above 1.0.

## Lesson / verdict
**Win rate is meaningless without payoff ratio.** A high deal-level % built from partial-TP1 banking +
mPOC-capped winners is a near-zero-edge config (PF 1.030 vs XAU-M5 base 1.341). NOT release-grade.
Directly reinforces **H6 (FVG-anchored SL)**: profitability is set by SL/exit geometry, not win%.
By reason: L-BRK +8,500 carries it; S-BRK −2,547 and both REV slices negative (−884 / −357) — reversion
is a net drag on M3, same as the M5 RevMpoc A/B.
