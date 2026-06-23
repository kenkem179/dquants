# Robustness & Profitability Thesis — MasterVP + KenKem (2026-06-23)

**Author:** Claude (Opus 4.8), as requested "think like a world-class quant developer, suggest the
missing assumptions I didn't know to ask about, put aside params that barely move the needle."
**Status:** DRAFT for adversarial review (codex) → then folds into `BUILD-PLAN.md`.

---

## 0. The one honest observation that reframes everything

After ~30 documented sweeps across MasterVP/KenKem × M1/M3/M5 × XAU/BTC, the score is:

- **Validated, MT5-confirmed edge: exactly ONE** — MasterVP **XAU M5** (PF ~1.37–1.40).
- KenKem **D5-E4Long** barely clears the overfitting gate (126 trades, MinTRL 118, PSR 0.955).
- **Everything else** is breakeven (BTC M5 PF 1.01), structurally dead (BTC M3), or **feed-fictional**
  (BTC reversion: engine revNet +5,414 vs MT5 −76; trail 3.5: engine +24% vs MT5 −24%).

**Almost every rejected lever failed for one of three reasons, repeated over and over:**
1. *Curve-fit* — wins TRAIN, dies OOS (VP-length peaks, FVG-gate, conviction-protect, ER filter…).
2. *Regime-dependent* — "helps 2025, hurts recent 2026" (hour blocks, gates, ADX23, almost all of T1/T2).
3. *Feed-fictional* — engine over-credits the trailed runner / BTC intrabar continuation.

**Conclusion: the marginal parameter sweep is now producing noise.** The needle no longer moves because
the *information in one instrument's price history is largely extracted.* The remaining edge is in
**six structural assumptions that have never been properly attacked** — none of them a parameter.

---

## 1. The six missing assumptions (ranked by leverage)

### A1 — Costs are modeled as fantasy. (Highest truth-value, cheapest to build.)
**Finding (code-grounded):** the tick engine models spread (gated) + optional commission (**default 0**).
**Slippage = 0, latency = 0, overnight swap = 0** (`execution.hpp:23-24`, `config.hpp:235`, no swap
anywhere). For M1/M3/M5 scalping with dozens of trades/day this is existential — and we *already know*
the XAU feed spread is **10× too tight** vs live Exness (18.9 vs 189 pts).

**Missing assumption:** *"the backtest PF is the live PF."* It is not. A PF-1.10 scalper at zero
slippage/latency/swap can be a net loser live. T5 (cost realism) was on the plan since 2026-06-20 and
**never executed.**

**The world-class move:** build a *realistic-friction* layer and **re-rank every lock under it before
trusting any number**:
- Stochastic slippage (e.g. half-spread + a fat-tailed adverse component, larger on impulse/news bars).
- Latency: fill on tick *N+k* (not the first tick) — directly tests the engine's biggest fragility.
- Per-symbol commission (Exness raw-spread accounts DO charge ~$3.5/lot/side — "0" is wrong).
- Overnight swap for any position crossing rollover (KenKem M1 holds short; MasterVP M5 holds for hours).

If MasterVP-XAU-M5 and KenKem survive realistic friction, *that* is the battle-tested result the user
wants. If they don't, every other task is moot. **This gates everything.**

### A2 — The engine's exit model is directionally wrong → the research process is biased.
**Finding:** proven twice — engine "wins" on the trailed runner that MT5 reverses (trail 3.5: +24% eng /
−24% MT5). Root cause (code-grounded): the engine resolves intrabar exits on a discrete tick/OHLC path;
it **cannot know the within-tick path**, and the feed round-trips (45% continuation here vs 94% OANDA).
The runner backstop is also anchored to *signal* price, not *fill* (`position_manager.hpp:126-137`).

**Missing assumption:** *"a sweep result is a fact."* Engine **entry-side** numbers are trustworthy;
engine **exit-side** numbers are a biased estimator that systematically over-credits runners.

**The world-class move:** stop sweeping exit/runner params in the engine. Two concrete options:
- **(cheap) Freeze the exit model** at the MT5-confirmed lock; only sweep ENTRY params in the engine;
  every exit-side idea goes straight to an MT5 A/B (the user's TP1/SL instincts belong here — MT5 said
  *tighter* protection wins, the opposite of the engine).
- **(better) Calibrate intrabar fidelity:** measure the feed's empirical post-breakout continuation
  curve and apply a **continuation haircut** to runner credit so the engine's exit ranking matches MT5.
  Then engine exit numbers become trustworthy again. This is a tooling fix worth more than any sweep.

### A3 — Portfolio is the real edge, and it's under-built. (Highest *profitability* leverage.)
**Finding:** the 2026-06-23 study found MasterVP-XAU-M5 ⊥ KenKem-XAU-M1 (**daily corr 0.082**) →
risk-parity blend **+$10,349 / DD 10.9%** beats XAU-alone **+$9,939 / 11.8%** — a genuine free lunch
(+4% net, LOWER DD). This single structural result beat ~30 param sweeps.

**Missing assumptions (three, all unaddressed):**
1. *"0.082 daily correlation means diversified."* Pearson on daily P&L **hides tail co-movement** — both
   are long-trend XAU; they will draw down *together* in sustained chop. The number that matters is
   **conditional correlation in the worst 5% of days** and **drawdown-overlap**, not the full-sample ρ.
2. *"The risk allocator's weights are usable."* Allocators want **96% KenKem on 126 trades** — that's
   over-fitting the allocation to a thin sample. Allocation needs the same DSR discipline as a lock.
3. *"The prop DD cap protects the book."* `InpMaxDailyDDPct` is **per-instance** — two EAs can each lose
   the full cap on the same day. There is **no combined-book governor.** This is a live-money bug, not a
   research nicety.

**The world-class move:** build a thin **portfolio risk layer** (research + a live meta-EA later):
tail-aware allocation (CVaR / drawdown-overlap, not Pearson), allocation run through the gate, and a
**shared-equity daily-DD + common-drawdown kill-switch** so the book — not each EA — respects the cap.

### A4 — The edge is regime-conditional and we deploy it unconditionally.
**Finding:** "helps 2025, hurts 2026" recurs in *every* rejected filter. That is regime dependence
screaming. The engine has only a **binary trend/balance flag that doesn't even gate entries**
(`regime.hpp:9-19`, informational only) + an ATR% band.

**Missing assumption:** *"one parameter set should trade in all regimes."* The robust improvement is not a
better param — it's a **regime gate that only deploys each edge when its favorable regime is present**
(trend persistence / Hurst, realized-vol regime, trend-strength percentile, time-of-day × vol). MasterVP
is a *trend breakout* — it should stand down in mean-reverting regimes; KenKem's entry mix is
regime-sensitive per entry type.

**The world-class move:** build an explicit regime classifier, **measure each edge's expectancy
conditional on regime** (this is `quant-6b-edge-autopsy` extended), and gate deployment. This directly
attacks the worst-fold problem that kills every lock — instead of averaging a good regime and a bad one,
trade only the good one.

### A5 — Statistical power, not strategy quality, is the binding constraint.
**Finding:** KenKem clears the gate by a hair; MasterVP locks repeatedly rest on *single* OOS windows;
DSR can't even be computed for some sweeps (missing `sr_trial_std`); the XAU 2025-H2 data is *missing*.

**Missing assumption:** *"more tuning on XAU = more confidence."* It doesn't — it *spends* confidence
(multiple testing). Confidence comes from **independent evidence**, and the strongest independent evidence
is **the same mechanism working on instruments we did NOT tune.** A VP-breakout edge that is real should
appear on EURUSD / US indices / other metals — not only XAU. Cross-instrument confirmation of the
*identical* logic is worth more than any single-instrument sweep.

**The world-class move:** (1) close the XAU 2025-H2 data gap; (2) **cross-sectional validation** — run
the *frozen* MasterVP/KenKem logic, untuned, on 3–5 other liquid instruments. Count how many show
PF>1 OOS. That fraction is the real edge-existence probability.

### A6 — Strategy-logic improvements that are *structural*, not param tweaks.
Putting aside knobs, two genuine logic changes have evidence behind them but were never built:

- **MasterVP — Volume Profile is used naively.** The profile is a fixed-lookback rolling window; pros
  anchor VP to *structure* (session open, swing points). Two untested structural changes:
  (a) **anchored/session VP** instead of rolling-N; (b) the user's standing assumption that reversion
  should fade the **LOCAL VP node, not master** (`reversion-local-vp-assumption` — currently fades
  master, code-confirmed `strategy.hpp:32,69-74`); (c) turn the *dead* local/HTF VP into a **breakout
  multi-TF confluence gate** (only take breakouts confirmed by a higher-TF VP edge).
- **KenKem — fixed on/off entry ensemble + weak exits.** E4/E5 are net-losers/noise, E1+E2 carry it,
  yet they're statically on/off. A real improvement: **regime-conditional ensemble weighting** (weight
  each entry type by recent *conditional* performance) — ties into A4. And KenKem's *proven* weak point
  is **exit geometry** (E5 0.3R wins vs −1R losses; E4 intrabar fiction). Exit robustness (structural SL
  at real invalidation, not blind ATR) is higher-leverage than any entry tweak.

---

## 2. What I would NOT do (the user's instinct is right)
- No more single-instrument param grids on knobs already shown flat (VP length, ADX, break-buf, SL mult,
  hour blocks, ER, conviction-protect). They produce noise and *spend* statistical power.
- No trusting an engine exit-side "win" without an MT5 A/B.
- No locking an allocation weight from a 126-trade sample without the gate.

## 3. Proposed re-sequencing of the build plan
1. **A1 realistic-cost re-rank** (gate everything; cheap; highest truth-value).
2. **A2 engine exit-fidelity fix** (or freeze-exits discipline) — restores research integrity.
3. **A3 portfolio risk layer** — the validated free lunch, hardened (tail corr + book governor).
4. **A4 regime-conditional deployment** — attacks the worst-fold killer.
5. **A5 cross-instrument + data-gap** — buys real confidence (deep-research flavored).
6. **A6 structural logic** (anchored/MTF VP; local-VP reversion; KenKem exit robustness + conditional
   ensemble) — only after 1–2 make the engine trustworthy again.

Forward-test discipline runs through all of it: a scorecard of expected-vs-realized PF/slippage/fill on
the demo account, feeding back into A1's cost model.
