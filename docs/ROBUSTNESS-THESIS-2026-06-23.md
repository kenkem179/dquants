# Robustness & Profitability Thesis — MasterVP + KenKem

**Created:** 2026-06-23 (Claude, Opus 4.8) — *"think like a world-class quant developer, surface the
missing assumptions, put aside params that barely move the needle."*
**Last updated:** 2026-06-28 — full re-assessment against the **currently developed EAs** (code +
local notes + cross-session memory). Adds the *current scorecard*, what the 2026-06-26/27 lever work
proved, and a **Citadel-Securities-grade roadmap**.

> Read order if resuming: this doc → `docs/BUILD-PLAN.md` → `HANDOFF.md`. Where they disagree, trust
> git + code, then reconcile.

---

## PART I — CURRENT SCORECARD (the honest "how good/bad are my EAs")

Two — and only two — validated, MT5-confirmed edges exist. Everything else is breakeven, regime-
dependent, or feed-fictional. This has not changed since 2026-06-23; five more levers were attacked
since and **all five were rejected**, which is itself the most important new datapoint (see Part II).

| EA | Symbol·TF | Status | Best MT5-confirmed result | Gate | Honest read |
|---|---|---|---|---|---|
| **KK-MasterVP** v1.07 | XAU·M5 | ✅ **LOCK, deployed** | PF **1.4246** / net +86,034 flat-risk / 1,423 tr (2025.06–2026.05, $10k every-tick); +ProgTrail late-arm ladder 2.0R/0.75/0.2 | **DSR 1.000 PASS** (n=36, PSR 1.000, MinTRL 192<1423) | The one strong edge. XAU trend-breakout. ⚠️ true full-year maxDD **27.7%** — size for 30–40% peak. ⚠️ ProgTrail params are *hidden compiled globals*, baked not `.set`-driven. |
| **KK-KenKem** v1.03 | XAU·M1 | ✅ LOCK (thin) | PF **1.428** / net +1,427 / **126 tr** (D5-E4Long); OOS PF 1.523 | PASS by a hair (PSR 0.953, MinTRL 122<126) | Real but *fragile*: the famous 1.428 was almost entirely one held-out golden quarter; TRAIN-window PF is only **1.146**. Regime-concentrated, near the statistical floor. |
| KK-MasterVP | BTC·M5 | ⚠️ **regime-dependent, NOT release-grade** | Full window net **−1,892 LOSER**; but 2025H2+2026 **+2,093** (matches user's live profit) | — | Deployed live and *currently profitable in trending regimes*; only 2025-H1 down-grind loses. Engine over-credits BTC (MT5 1.058 vs engine 1.293). Edge is real but **unconditioned** — needs a stand-down guard, not a sweep. |
| KK-MasterVP | BTC·M3 | ❌ **DEAD** | OOS PF 0.668, 81% DD | FAIL | Pure overfit. Train↑⇒OOS↓. Do not reopen without new entry geometry. |
| KK-KenKem | XAU·M3 | ❌ rejected (2026-06-27) | OOS PF 0.81–0.88, net-negative | FAIL | 3×-clock proxy; RR-rescale overfits, worse than M1 on full window. **Accept KenKem M1-only.** |
| KK-MasterVP-Profiler v1.01 | (indicator) | 🔶 parity blocked on user | — | — | EA-exact visual twin; awaiting MT5 visual spot-check (PF1 baton). Not a P&L instrument. |

**Bottom line:** *one* robust money-maker (MasterVP XAU M5), *one* thin-but-real edge (KenKem XAU M1),
*one* live-but-unconditioned edge (MasterVP BTC M5), and a graveyard of ~35 rejected sweeps. The
portfolio of *two uncorrelated XAU edges* (daily corr 0.082) is the most valuable under-built asset.

---

## PART II — WHAT THE LAST WEEK PROVED (the thesis was right: the sweep is dry)

Since 2026-06-23, five more levers were built and tested to conclusion. **Every one was rejected** — and
each failed for one of the three modes this thesis named on 2026-06-23 (curve-fit / regime-dependent /
feed-fictional):

- **H7 — BTC M3 sweep** → DEAD. Train-fittable to PF 1.09, OOS-catastrophic (0.668, 81% DD). *Curve-fit.*
- **H10c — session-giveback stop** (`InpGivebackPct`) → REJECT. OFF wins every axis; every giveback value
  collapses net ~92% **and** raises maxDD. 4th independent XAU falsification of "don't give it back."
- **H12 — entry-flow direction veto** → REJECT. Against-flow entries are *favorable pullbacks, not traps*
  (model-free autopsy on 2117 entries). *The premise was simply false.*
- **H12b — fading-volume magnitude veto** → REJECT. Low/dying-volume breakouts are equal-or-better.
- **H12c — node-absorption veto** → REJECT (engine flat PF, worst-fold degrades) **and MT5 catastrophic
  (−95% net)** — which surfaced a real **MQL↔C++ node-net VALUE parity gap** (MT5 flags ~74% of breakouts
  against vs engine ~15%). *Feed-fictional, plus a new infrastructure debt.*
- **KenKem M3** → REJECT (see scorecard). *Curve-fit.*

**This is the thesis's central claim, now confirmed empirically:** the marginal single-instrument
parameter/lever sweep is producing **noise**. The information in one instrument's price history is
largely extracted. Six structural assumptions remain that have never been properly attacked — **none of
them a parameter** — and they are where any remaining edge (and all of the "institutional-grade" upside)
lives. **There are no open conventional MasterVP research levers left.** Continuing to sweep is now
negative expected value: it spends statistical power (multiple-testing) and returns nothing.

> One factual correction to the 2026-06-23 draft: the regime flag **does** gate entries
> (`strategy.hpp:69-87` — breakouts require `regime.trend`, reversions require `regime.balance`). It is
> still a *crude VP-derived binary*, not a real regime classifier, so A4 below stands — but it is not
> "informational only" as originally written.

---

## PART III — THE SIX STRUCTURAL ASSUMPTIONS (updated, with status)

Ranked by leverage. Status reflects work through 2026-06-28. **None of A1–A6 has been executed** — the
last week was spent on conventional levers (Part II) instead. That is the single biggest process gap.

### A1 — Costs are modeled as fantasy. `[NOT STARTED] · highest truth-value · cheapest to build`
**Code-grounded (verified 2026-06-28):** the tick engine models gated spread + optional commission
(**default 0**, `config.hpp:265,273,278`). **Slippage = 0** (`execution.hpp:8-11,23-25`),
**latency = 0** (fills on the first tick of the bar, `execution.hpp:4-6`), **swap = 0** (no rollover
code anywhere). We already *know* the XAU feed spread is ~10× too tight vs live Exness (18.9 vs 189 pts).

**Missing assumption:** *"backtest PF = live PF."* A PF-1.10 scalper at zero slippage/latency/swap can be
a net loser live. T5 (cost realism) has been on the plan since 2026-06-20 and **never executed.**

**The move:** build a *realistic-friction* layer and **re-rank every lock under it before trusting any
number** — stochastic slippage (half-spread + fat-tailed adverse, larger on impulse/news bars), latency
(fill on tick N+k), per-symbol commission (Exness raw ≈ $3.5/lot/side), overnight swap for rollover-
crossing holds. **If MasterVP-XAU-M5 and KenKem survive realistic friction, that is the battle-tested
result.** This gates everything below.

### A2 — The engine's exit model is directionally wrong → the research process is biased. `[NOT STARTED]`
**Proven three times now** (trail 3.5: +24% eng / −24% MT5; H12c: engine flat / MT5 −95%; BTC engine
over-credits vs MT5). The engine resolves intrabar exits on a discrete tick/OHLC path and cannot know the
within-tick path; the feed round-trips (45% continuation here vs 94% OANDA). **Engine entry-side numbers
are trustworthy; engine exit-side numbers systematically over-credit runners.**

**The move:** (cheap) **freeze the exit model** at the MT5-confirmed lock — only sweep ENTRY params in the
engine; every exit idea goes straight to an MT5 A/B. (better) **calibrate intrabar fidelity** — measure
the feed's empirical post-breakout continuation curve and apply a continuation haircut so engine exit
rankings match MT5. This tooling fix is worth more than any sweep.

### A3 — Portfolio is the real edge, and it's under-built. `[NOT STARTED] · highest profitability leverage`
**Finding:** MasterVP-XAU-M5 ⊥ KenKem-XAU-M1 (**daily corr 0.082**) → risk-parity blend **+$10,349 / DD
10.9%** beats XAU-alone **+$9,939 / 11.8%** — genuine free lunch (+4% net, *lower* DD). One structural
result beat ~30 sweeps.

**Three unaddressed missing assumptions:** (1) Pearson on daily P&L hides **tail co-movement** — both are
long-trend XAU and will draw down together in sustained chop; the number that matters is **conditional
correlation in the worst 5% of days** + drawdown-overlap. (2) Allocators want **96% KenKem on 126 trades**
= over-fit allocation; weights need the same DSR discipline as a lock. (3) **`InpMaxDailyDDPct` is
per-instance** (verified `risk_manager.hpp:76-82`) — two EAs can each lose the full cap the same day.
**There is no combined-book governor.** This is a live-money bug, not a nicety.

**The move:** a thin **portfolio risk layer** — tail-aware allocation (CVaR / drawdown-overlap, gated),
and a **shared-equity daily-DD + common-drawdown kill-switch** so the *book* respects the cap. (Build-plan
D5 is the live-EA half of this.)

### A4 — The edge is regime-conditional and we deploy it unconditionally. `[NOT STARTED]`
**Finding:** "helps 2025, hurts 2026" recurs in *every* rejected filter — and BTC is the clean case: the
*same config* is +PF in 2025H2/2026 and −PF in 2025H1. That is regime dependence screaming. The current
regime gate is a crude binary trend/balance flag (`strategy.hpp:69-87`) + an ATR% band — not a classifier.

**Missing assumption:** *"one parameter set trades all regimes."* The robust improvement is a **regime
gate that deploys each edge only in its favorable regime** (trend-persistence / Hurst, realized-vol
regime, trend-strength percentile, time-of-day × vol). MasterVP is a trend breakout — it should *stand
down in mean-reverting regimes*; BTC's open lever is exactly a **drawdown/regime stand-down guard** to
survive 2025-H1-type bleeds while staying live in trends.

**The move:** build an explicit regime classifier, measure each edge's expectancy **conditional on
regime** (extend `quant-6b-edge-autopsy`), and gate deployment. Attacks the worst-fold problem directly.

### A5 — Statistical power, not strategy quality, is the binding constraint. `[NOT STARTED]`
KenKem clears the gate by a hair (126 tr); MasterVP locks rest on single OOS windows; the XAU **2025-H2
data gap** still exists. *"More tuning on XAU = more confidence"* is false — it *spends* confidence.

**The move:** (1) close the XAU 2025-H2 data gap; (2) **cross-instrument validation** — run the *frozen,
untuned* MasterVP/KenKem logic on 3–5 other liquid instruments (EURUSD, indices, other metals). The
fraction showing PF>1 OOS is the real edge-existence probability — worth more than any single-symbol sweep.

### A6 — Structural logic changes, not param tweaks. `[NOT STARTED]`
- **MasterVP — VP used naively.** Fixed-lookback rolling window; pros anchor VP to *structure* (session
  open, swing points). Untested: (a) **anchored/session VP**; (b) reversion should fade the **LOCAL** VP
  node, not master (`strategy.hpp:32,69-74` confirms it fades master); (c) turn the dead local/HTF VP into
  a **multi-TF breakout-confluence gate**.
- **KenKem — static on/off ensemble + weak exits.** E4/E5 are net-losers/noise; E1+E2 carry it, yet
  they're statically gated. Real improvement: **regime-conditional ensemble weighting** (ties to A4). And
  KenKem's proven weak point is **exit geometry** (structural SL at real invalidation, not blind ATR).

---

## PART IV — TAKING THESE TO "CITADEL SECURITIES LEVEL"

Be precise about the target. "Citadel level" is not a better `.set` file. It is a **different operating
discipline**. A retail MT5 EA asks *"is this backtest profitable?"*; an institutional system asks *"what
is the risk-adjusted, capacity-aware, cost-real, out-of-sample, multiple-testing-deflated edge, and how do
I size, monitor, and kill it under a portfolio risk budget?"* The good news: most of that discipline is
already half-built here (the gate, parity doctrine, WF/MC). The gap is **execution realism, portfolio
construction, and live monitoring** — exactly A1–A5.

The honest framing: we will never *be* Citadel (no co-location, no order flow, no sub-millisecond infra,
no thousands of uncorrelated signals). But we can run an EA book to **institutional process standards.**
Here is the gap, by dimension, with what "good" looks like and the concrete next step.

### 1. Execution & cost realism — `current: 2/10 → target: 8/10` (THE binding gap)
Institutional backtests model the *full* cost stack and assume **adversarial fills**. Ours assumes
free, instant, slippage-free fills (A1/A2). **This is the single biggest credibility gap and the cheapest
to close.**
- **Do now:** the A1 friction layer (stochastic slippage, latency tick-offset, per-symbol commission,
  swap) + the A2 continuation-haircut so engine exits stop over-crediting runners. Re-rank both locks.
- **"Good" =** the demo forward-test PF lands within a stated tolerance band of the friction-adjusted
  backtest PF. Track expected-vs-realized fill/slippage as a live scorecard that feeds back into the model.

### 2. Portfolio construction & capital allocation — `current: 1/10 → target: 7/10`
Citadel's edge is *many* uncorrelated bets sized by a risk model — not one big bet. We have *two*
uncorrelated edges and run them as isolated EAs with no shared risk view (A3).
- **Do now:** tail-aware allocation (CVaR / drawdown-overlap, gated for DSR) across MasterVP-XAU + KenKem-
  XAU; then a **combined-book daily-DD + common-drawdown kill-switch** (research layer now, live meta-EA
  later — build-plan D5).
- **"Good" =** the book — not each EA — respects one risk budget; allocation weights are validated, not
  fit to 126 trades; correlation is measured in the tail, not full-sample Pearson.

### 3. Risk management — `current: 4/10 → target: 9/10`
Per-instance daily-DD exists and is *faithful* (not buggy — see memory). Missing: combined-book governor
(above), volatility-targeted position sizing (size inverse to realized vol so risk-per-trade is constant
across regimes), and an explicit **regime stand-down** (A4) instead of trading every regime at full size.
- **Do now:** vol-targeted sizing + the BTC/regime stand-down guard. These convert the 27.7% MasterVP
  peak DD into something a prop account survives.

### 4. Statistical validation — `current: 7/10 → target: 9/10` (closest to institutional already)
This is the strongest pillar: the overfitting gate (DSR/PSR/MinTRL) is mandatory, parity-is-gate-0 is
doctrine, WF + MC are run. The gaps are **sample power** and **cross-sectional confirmation** (A5):
single-instrument validation, KenKem at the statistical floor, the 2025-H2 data hole.
- **Do now:** close the data gap; run the frozen logic on 3–5 untuned instruments. Out-of-sample on a
  *different instrument* is the strongest evidence a mechanism is real — this is how you convert "looks
  good on XAU" into "is a genuine VP-breakout edge."

### 5. Signal diversity & capacity — `current: 2/10 → target: 6/10`
Two correlated-family edges (both XAU, both trend). Citadel runs thousands of decorrelated alphas.
Realistic target here: **3–5 genuinely different mechanisms across 3–5 instruments**, combined in the
portfolio layer. The A6 structural changes (anchored VP, MTF confluence, regime-weighted ensemble) and
A5 cross-instrument work are the supply line. **Do NOT** manufacture diversity by re-parameterizing the
same breakout — that's the sweep trap that just failed five times.

### 6. Infrastructure, reproducibility & monitoring — `current: 5/10 → target: 8/10`
Strong: deterministic C++ core, headless tick engine, byte-parity discipline, versioned releases,
account-locking, the HANDOFF/memory continuity system. Gaps: (a) the **MQL↔C++ node-net parity gap** is
now a documented infra debt — *any* future feature consuming node-net VALUE must first prove per-entry
parity; (b) no **live production monitoring** — expected-vs-realized PF/slippage/fill drift, regime
detector, kill-switch telemetry; (c) no automated **forward-test scorecard** feeding back into the cost
model.
- **Do now:** stand up the forward-test scorecard (ties to #1). Treat node-net parity as a blocker on any
  node-value feature.

### The Citadel-level sequence (what actually moves the needle, in order)
1. **A1 + A2 — execution realism.** Without it, every PF is fiction. Cheapest, highest truth-value.
2. **A3 — portfolio layer + combined-book governor.** The validated free lunch, hardened. Highest profit
   leverage, and the thing that makes a *book* instead of two EAs.
3. **A4 — regime-conditional deployment.** Vol-targeted sizing + stand-down guard. Fixes the worst-fold
   killer and the BTC bleed; turns DD survivable.
4. **A5 — cross-instrument + data gap.** Buys *real* confidence and is the supply line for diversity.
5. **A6 — structural logic** (anchored/MTF VP, local-VP reversion, KenKem exit robustness + conditional
   ensemble). Only *after* 1–2 make the engine trustworthy again.
6. **Live monitoring scorecard** running through all of it.

**What to stop doing (the discipline that defines the level as much as the building):** no more single-
instrument param grids on knobs already shown flat (VP length, ADX, break-buf, SL mult, hour blocks, ER,
conviction-protect, giveback, entry-flow vetoes). They produce noise and *spend* statistical power. No
trusting an engine exit-side "win" without an MT5 A/B. No locking an allocation weight from a thin sample.
The last week proved this empirically — five rejections, zero edge found. **The next edge is structural,
not a parameter.**

---

## PART V — PROPOSED RE-SEQUENCING OF THE BUILD PLAN
1. **A1 realistic-cost re-rank** (gate everything; cheap; highest truth-value) — maps to plan T5.
2. **A2 engine exit-fidelity fix** (or freeze-exits discipline) — restores research integrity.
3. **A3 portfolio risk layer** — the validated free lunch, hardened (tail corr + book governor); plan D5.
4. **A4 regime-conditional deployment** — attacks the worst-fold killer; BTC stand-down guard.
5. **A5 cross-instrument + data-gap** — buys real confidence (deep-research flavored); plan K2 prerequisite.
6. **A6 structural logic** — anchored/MTF VP; local-VP reversion; KenKem exit robustness — only after 1–2.

Forward-test discipline runs through all of it: a scorecard of expected-vs-realized PF/slippage/fill on
the demo account, feeding back into A1's cost model. **The MasterVP 1.07 production confirmation run and
the Profiler visual check (PF1) remain the only open *tactical* items** — everything above is the
strategic path to institutional grade.
