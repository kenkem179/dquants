# E5 entry-quality sweep — findings (2026-06-20)

**TL;DR:** The planned "tighten E5 entry gates → cut the −629 overfire → win" thesis is *partly true but
misleading*. A full-window sweep shows the only large net gains come from raising
`MIN_ENTRY_ATR_PERCENTILE`, and that gain is **overfit to 2025** — it works by *discarding* the 2026
trades where the engine is broken, not by fixing anything. The engine's whole-run −480 is a
**period-localized parity break in 2024 + 2026**, not generic entry overfire. **Do NOT lock an
entry-tightened .set.** The real lever is the 2026 entry-detection divergence + the uniform exit residual.

Harness: `research/kenkem_parity/sweep_e5_entry.py` (reusable; reports profitability AND parity per combo).
Baseline = `MT5_E5_ONLY.set` on the full 2yr parity window; MT5 ref =
`mt5_runs/RUN_2026-06-19_1.8.154_xau_2yr_E5only_cd120/trades.csv` (656 E5, net +1267, PF 1.10).

## 1. Baseline decomposition (engine vs MT5, full window)
matched 401 (engNet +125 / mt5Net +945), missed 255, overfire 235 (net **−629**), whole-run net **−480**.
Overfire IS net-losing — the user's input was correct. But *where* it loses matters (below).

## 2. 1-D + 2-D sweep result
- `MIN_ENTRY_ATR_PERCENTILE` is the only big net lever: 65→75 flips net −480→+507; 80 → +383 (DD halved).
- `E5_MAX_EMA_CROSS_AGE=15` and `E5_MIN_MOMENTUM_ADX=22` are **parity-preserving** (recall stays ~59-61%)
  and *additive on top of* the ATR lever. Best aggregate combo: **ATR80 + age15 + adx22 → net +732,
  PF 1.119, DD 817, recall 24.7%**.
- CSVs: `sweep_e5_entry_1d.csv`, `sweep_e5_entry_grid.csv`.

## 3. Why the "+732" is a mirage — time-split (the decisive test)
| Year | MT5 net (PF) | Engine ATR65 (PF) | Engine ATR80+age15+adx22 (PF) |
|------|--------------|-------------------|-------------------------------|
| 2024 | −198 (0.95)  | **−732 (0.85)**   | −276 (0.87) |
| 2025 | +696 (1.12)  | **+690 (1.12)** ✓ | +1501 (1.64) |
| 2026 | **+769 (1.31)** | **−438 (0.83)** | −494 (0.69) |
| ALL  | +1267 (1.10) | −480 (0.96)       | +732 (1.12) |

- **2025 is in near-perfect parity** (engine +690 vs MT5 +696, same PF). The strategy + engine work there.
- Raising ATR to 80 amplifies 2025 (+690→+1501) by filtering, but **2024 and 2026 still lose**. The
  aggregate "+732" is a single-period peak — violates the plateau rule. Adopting it = curve-fitting to 2025.

## 4. The actual bug — a 2026 (and milder 2024) SELECTION-parity break
Matched-pair gaps are uniform (~77% tag-agree all years): 2024 −322, 2025 −405, 2026 −93 ≈ −820 total
(the known **exit residual** — real, spread evenly, separate problem).

The 2026 catastrophe is in **selection**, not exits:
- 2026 **MISSED 59 trades, net +727** — MT5's *entire* 2026 profit is in trades the engine never fires.
- 2026 OVERFIRE 28, net −411 — engine fires losers MT5 avoids.
- Contrast 2025: overfire net **+238** (engine's extras are *winners*), missed −161 — divergences *favorable*.

So the engine systematically picks the *wrong* E5 trades in 2026: misses MT5's winners, fires its own
losers. No entry-quality gate recovers the +727 missed winners; raising ATR just trades less in 2026,
hiding the break.

## 5. Cause hypothesis (not yet confirmed)
- **NOT data coverage**: engine fires in every 2026 month (~71% of MT5's count, no cliff).
- Most likely **pip-hardcoded tolerances at 2026's price level** — XAU ~4540 in 2026 vs ~2000 in 2024;
  `ema_align_tol_pips * pip_size` and `E5_MIN_SL_PIPS=50` are absolute, so the same band is a far smaller
  *relative* tolerance in 2026 → cross-arm / MTF-alignment decisions flip. Ties directly to the standing
  [[goal-pip-to-atr-relative]]. Alternative: ATR-percentile rolling-window drift (the known ~19% pctile
  category mismatch from [[kenkem-atr-is-sma-not-wilder]]) concentrating in 2026's vol regime.

## 6. Recommended next actions (supersedes "E5 entry sweep")
1. **Localize the 2026 selection break.** Ask the user for an MT5 E5 per-bar gate trace over 2026 (same
   method that cracked E1's MTF residual), OR engine-side: dump the 59 2026-missed entries and check
   whether the engine *armed-then-gated* vs *never-armed* them; test the pip→ATR-tolerance hypothesis by
   scaling `ema_align_tol_pips` with price and re-checking 2026 recall (2025 must stay matched).
2. **Exit residual** (−820, uniform): continue the matched-pair exit-tag work (separate track).
3. **Only after 2026 parity holds** should any entry-quality .set be locked — otherwise we deploy a
   2025-overfit config that loses in 2024 and 2026.
