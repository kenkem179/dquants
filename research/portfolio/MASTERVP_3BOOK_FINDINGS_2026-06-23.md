# MasterVP 3-instance portfolio — XAU M5 + BTC M5 + BTC M3 (2026-06-23)

**Question (user):** running MasterVP on BTC M3, BTC M5, XAU M5 at once — how to maximize joint
profit without conflicts.

**Method:** MT5-CONFIRMED trade streams only (engine exit-model is flagged directionally unreliable,
esp. BTC). Sliced to the COMMON window **2026-01-02 → 2026-05-29** so correlations are fair. Daily
return-fraction matrix → `research/portfolio/portfolio.py`. Repro: `mastervp_3book_2026-06-23.py`.

## The numbers

Standalone, common window, each as if alone on $10k:

| stream | net | PF (daily) | ann.Sharpe | maxDD | full-history PF |
|---|---|---|---|---|---|
| **XAU_M5** | **+$11,789** | 1.86 | **2.92** | 18.9% | **1.366 (real edge)** |
| BTC_M5 | +$1,815 | 1.23 | 0.99 | 11.0% | **1.013 (breakeven, 17mo)** |
| BTC_M3 | +$494 | 1.06 | 0.33 | 11.5% | 1.031 (marginal) |

Correlation (daily): **XAU⊥BTC ≈ 0** (−0.02, 0.07); **BTC_M3 ↔ BTC_M5 = +0.34**.

Risk-normalized to the SAME 4.4% prop daily cap (uniform downscale so combined worst-day = −4.4%):

| book | net | maxDD |
|---|---|---|
| XAU-only | $3,971 | 6.7% |
| XAU + BTC_M5(0.5) + BTC_M3(0.25) | $4,073 | 7.5% |
| XAU + BTC_M5(0.5), drop M3 | **$4,123** | 7.1% |

## Conclusions

1. **Only XAU M5 has a validated edge.** BTC_M5 is breakeven over its full 17 months (PF 1.013) — the
   2026 slice merely flatters it; BTC_M3 (PF 1.031) is marginal. Portfolio math cannot manufacture
   profit from near-breakeven components.
2. **The two BTC timeframes are partly redundant** (corr +0.34, same underlying). Running BTC_M3 AND
   BTC_M5 is NOT independent diversification — risk-normalized, dropping BTC_M3 is *better* ($4,123 vs
   $4,073, lower DD). The only genuine diversifier is XAU ⊥ BTC.
3. **Do NOT use naive risk-parity / HRP here.** They equalize *risk* and starve the only edge: HRP puts
   just 0.10 weight on XAU and 0.54 on BTC_M3 → book Sharpe collapses 2.85 → 1.60. Edge-aware methods
   (max-Sharpe / Kelly) correctly keep XAU dominant (≈0.59) and zero out BTC_M3.
4. **Prop-cap conflict is real.** `InpMaxDailyDDPct=4.4` is PER-INSTANCE → three EAs can lose 3×4.4% in
   one day. Stacking all three at independent full size: combined worst-day −15.2%, maxDD −28.3%, 15
   days breaching −4.4% (vs XAU-alone 8). Risk must be budgeted ACROSS the book, not per-EA.

## Recommendation

- **Core = XAU M5 at full risk budget** (it carries the book). Total risk scaled so the *combined*
  worst-day stays ≤ 4.4% → XAU at ≈0.32–0.34× its as-run per-trade risk on a shared account.
- **Optional diversifier = BTC_M5 only, at ≈0.5× XAU's risk.** Drop BTC_M3 (redundant with BTC_M5).
  The BTC sleeve is diversification insurance (smooths DD), not a profit source — expect ≈ XAU-alone
  net, slightly smoother.
- **To actually grow joint profit**, the lever is a *genuinely uncorrelated edge*, not a second BTC
  timeframe: either give BTC a real edge first (engine says none on M3, marginal on M5), or add a
  different symbol / non-MasterVP strategy as the third leg.

## Follow-up: drop BTC M3, add KenKem (cross-strategy book)

User: drop BTC M3, combine MasterVP with KenKem. Added **KenKem D5-E4Long** (XAU M1, Ichimoku/EMA
entries — a genuinely different strategy) using its MT5 lock run (126 trades). Used the full 17-mo MT5
XAU M5 MasterVP run for overlap. Repro: `mastervp_kenkem_book_2026-06-23.py`. Common window
2025-03-05 → 2026-05-26.

**KenKem is the uncorrelated leg BTC never was.** Despite both being XAUUSD:

| pair | daily corr |
|---|---|
| XAU_M5_MVP ↔ **KENKEM_M1** | **0.082** (near-zero — different signal) |
| XAU_M5_MVP ↔ BTC_M5 | 0.012 |
| KENKEM_M1 ↔ BTC_M5 | 0.118 |

Standalone (common window): XAU_M5_MVP PF 1.83 / Sharpe 2.37 (but as-run sizing is HOT, maxDD 70%);
KenKem PF 1.48 / Sharpe 1.14 / maxDD only 5.5% (most risk-efficient stream); BTC_M5 PF 1.03 (dead).

Risk-normalized to the 4.4% prop daily cap (2-book, BTC dropped):

| book | net | maxDD | ann.Sharpe |
|---|---|---|---|
| XAU_MVP only | $9,939 | 11.8% | 2.37 |
| KenKem only | $3,641 | 13.6% | 1.14 |
| **risk-parity blend** | **$10,349** | **10.9%** | 2.38 |
| 60/40 $ split | $10,055 | 11.8% | 2.39 |

**Verdict:** combining XAU-MasterVP + KenKem is a **genuine (if modest) free lunch** — ≈+4% net at
*lower* drawdown vs XAU-alone, because corr ≈ 0.08. This is real diversification, unlike the redundant
BTC legs. **BTC_M5 stays dropped** (breakeven, adds nothing). Caveats: (1) risk-based allocators pile
96% into KenKem (low-vol, high-Sharpe) — but KenKem is only 126 trades and *barely* cleared the
overfitting gate (PSR 0.955, MinTRL 118<126), so don't over-concentrate there; a balanced edge-aware
split (XAU primary $ engine + KenKem co-equal-risk diversifier) is sounder. (2) Both are XAUUSD and
both long-trend-biased — daily corr 0.08 is benign-regime; a sharp gold shock can hit both, so size for
tail co-movement, not the 0.08.

**Recommendation:** Run **XAU M5 MasterVP + KenKem XAU M1** as the book; drop both BTC legs. Budget total
risk so the COMBINED worst-day ≤ 4.4% (≈ scale XAU to ~0.12× its as-run hot risk; let KenKem run at ~1×
its small native size, or up to ~1.5–2× given its tiny DD). Expect ≈ XAU-alone net with a smoother curve.

## Infra fixed this session
Two RED tests from the parallel-session checkpoint (`e8fcb11`) resolved — both were
test-expectation bugs, not code bugs:
- `test_portfolio.py::test_returns_matrix_build_and_align` — fixture had one trade on Jan-3 but
  asserted two summed; added the second Jan-3 trade.
- `test_cpcv.py::test_pbo_overfit_detection_on_noise` — single-draw PBO is unreliable (one config wins
  globally by luck → low PBO is correct for that draw); now averages over 40 seeds with the canonical
  complementary split (test_size = N/2) → mean PBO ≈ 0.5. cpcv.py code verified correct (no leakage).
