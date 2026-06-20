# KK-MasterVP — "Extreme Reversion" entry family (Hypothesis & Build Plan)

> **Status:** ✅ BUILT (C++ engine + both MQL5 EAs + presets), **toggle OFF by default** (`enable_extreme_reversion = false`) so the locked base is byte-identical. Engine sweeps done (isolated + additive, train/OOS): additive HELP on BTC M3 (Monster) + XAU M3, slight HURT on XAU M5; tiny sample (rare setup) → **awaiting MT5 A/B confirmation** (BTC M3 is the decisive test). Full results: `research/mastervp_parity/XREV_FINDINGS.md`. The `InpXRevTp1ClosePct` mPOC-partial (§8.1) was DEFERRED — it requires touching the shared `position_manager`, which would risk the base; the other 11 params are implemented + swept.
>
> **One-line thesis:** A failed breakout above the master value-area high (`mVAH`) that *sweeps* the recent swing-high liquidity and then snaps back **below** `mVAH` on a big, sell-flow-dominated candle is a high-conviction short back toward the opposite value edge (`mVAL`). Long mirrors at `mVAL`. This is a **liquidity-grab / trapped-breakout reversal**, not the base value-touch reversion.

This is a *signal-side* addition. It reuses every existing KK-MasterVP primitive — master volume profile (`mVAH/mVAL/mPOC`), per-bar net flow, node-state order flow, ATR, the SL/TP/RR bracket plumbing. See [`KK-MasterVP.md`](./KK-MasterVP.md) for the base strategy and §2.1's "local profile is inert" note; **this family is the first thing that would put structure back to work around the master edges with order-flow confirmation.**

---

## 1. Why this edge should exist (economic rationale)

The master VAH is the upper boundary of the 70% value area — a level where, by construction, the market has repeatedly *rejected* higher prices. Two populations cluster their stops just above it:

1. **Breakout buyers** who buy the close above VAH expecting continuation, with stops below.
2. **Resting buy-stops / liquidity** sitting above the obvious recent swing-high.

A genuine "stop hunt" prints a spike that **takes out `max(mVAH, recent swing-high)`** — triggering those buy-stops and filling late longs — and then **immediately reverses and closes back below `mVAH`** on heavy selling. The trapped longs are now offside; their stops below become fuel. The path of least resistance is a rotation back through the value area toward `mVAL` (and the `mPOC` magnet on the way). The edge is the **asymmetry**: tight invalidation (just above the swept high) vs a wide, structurally-supported target (the far value edge).

The "more than 2 closes above `mVAH` in the last M bars, but failed" precondition is what distinguishes this from a clean first-touch: it evidences that price **attempted acceptance above value and was rejected**, i.e. liquidity and trapped positioning genuinely built up there. That is the difference between a tradable trap and noise.

---

## 2. Falsifiable entry rules

Canonical case is **SHORT at `mVAH`**; LONG is the exact mirror at `mVAL` (substitute lowest-low, close-above, bullish body, buy-flow). All conditions evaluate on the **confirmed rejection bar** (the just-closed bar, engine `SignalBar s` = `bars_[i-1]`); entry fills at the next bar's first tick (engine anchor `entry_close = bars_[i].close`). No lookahead — every lookback uses closed bars only.

Let `mVAH/mVAL/mPOC` = current master VP; `atr2 = atr_[i-1]` (signal-bar ATR), `atr1 = atr_[i]` (entry ATR).

**A. Context preconditions (failed acceptance above value)**
1. Master VP valid (`master_cur.valid`).
2. **Failed-acceptance count:** over the last `M` closed bars (default 14), the number of bars whose **close > `mVAH`** is **≥ `minClosesBeyond`** (default 2 → the user's "more than 2"). Optional upper cap `maxClosesBeyond` (default off) to exclude a *real* sustained breakout that is merely pulling back.
3. **Aged excursion (mature round-trip):** the most recent **up-cross of `mVAL`** — price entering value from below, `close` crossing from `≤ mVAL` to `> mVAL` on the rolling level — was **more than `minAgeBars` bars ago** (default 40). *Why:* it rejects fading a **fresh, fast rally straight off `mVAL`**, which still carries breakout momentum and is more likely to be a real move; requiring the up-leg to be mature means price has spent time building the trap above `mVAH` and the rotation back to `mVAL` is a genuine round-trip with real runway. **LONG mirror:** the most recent **down-cross of `mVAH`** (entering value from above) was > `minAgeBars` ago.

**B. The sweep + rejection trigger (the entry bar)**
3. **Sweep level:** `sweepHi = max(mVAH, highestHigh(N))` over the `N` bars (default 5) preceding the rejection bar.
4. **Liquidity swept:** `s.h > sweepHi` — the bar poked above both the value edge *and* the recent swing-high (ran the stops).
5. **Failed back inside value:** `s.c < mVAH` — closed back below the edge (the breakout failed).
6. **Big bearish candle:** `s.c < s.o`, body% = `|s.c−s.o| / (s.h−s.l) ≥ bodyPctMin` (default 0.4), and range `(s.h−s.l) ≥ bigCandleAtr · atr2` (default 1.0).
7. **Sweep tail signature:** upper wick `= s.h − max(s.o,s.c) ≥ wickFrac · |s.c−s.o|` (default 1.0× body) **or** `≥ wickAtr · atr2`. This is the visible rejection tail.

**C. Order-flow confirmation (the "strong net volume delta")**
8. **Near-price net delta ≤ −`netDeltaMin`** (default 0.6; range [−1,+1], negative = sell-dominated tick flow). This is the same normalized "% delta" the base strategy's 80% gate uses, applied to the rejection bar — it confirms aggressive sellers, not a passive drift back. *(Sweep this; it is the user's open "how many %".)*
9. **Optional node gate:** the node state at `mVAH` shows selling/absorption — `ns_vah.net ≤ −nodeBand` **or** `ns_vah.absorbed` (a liquidity wall doing the rejecting). Toggleable (`useNodeGate`).
10. **Opposing veto (reuse existing):** not blocked by a strong opposing *buy* net on M3/M5.

**D. Bracket & RR filter**
11. **SL** = `sweepHi + slAtr · atr1` (default 0.7) — placed above the **swept high**, not merely `mVAH`, so a second probe doesn't stop us out cheaply. *(This is a deliberate hardening of the user's "x ATR above mVAH".)*
12. **TP** = `mVAL` (full value-area rotation).
13. **RR filter:** `RR = (entry − mVAL) / (SL − entry) ≥ rrMin` (default 2.0). Reject otherwise — the user's 1:2 rule. This auto-rejects setups where price is already near `mVAL` (no runway) or the value area is too narrow.

Emit `Signal{ is_long=false, is_extreme_rev=true, reason="S-XREV", entry, sl, tp2=mVAL }`.

**Dispatch / priority.** `enable_extreme_reversion` OFF by default. When ON: the trigger (close *below* `mVAH`) is mutually exclusive with breakout (close *above* `mVAH`), so they never collide. To avoid clashing with the base value-touch reversion near the edge, **Extreme Reversion takes priority** when its stricter conditions hold; otherwise control falls through to the base path. The existing "one signal per bar per direction; never both directions" rule is preserved.

---

## 3. What I changed / added vs the raw idea (quant enhancements)

| # | Your idea | Enhancement & why |
|---|---|---|
| 1 | SL "x ATR above mVAH" | SL above the **swept high** `max(mVAH, HH(N))`, not `mVAH` — survives a double-sweep; invalidation is the structural failure point. |
| 2 | "strong net volume delta, % TBD" | Use the engine's **near-price net** [−1,+1] (the same unit as the 80% gate) as a sweepable `netDeltaMin`; add an **optional node-absorption gate** at `mVAH` (`ns_vah`) for a second, independent confirmation. |
| 3 | "big bearish candle closed below mVAH" | Decomposed into **3 measurable filters**: bearish body%, range ≥ ATR-mult, and an explicit **upper-wick (sweep tail)** test — the tail *is* the sweep signature and is the strongest single discriminator. |
| 4 | "tried to close above >2 candles in last M" | Made it a count of **closes beyond `mVAH`** with an optional **upper cap** so a real, sustained breakout pulling back isn't faded. |
| 5 | "TP all the way to mVAL" | Keep `mVAL` as headline TP; **propose testing a `mPOC` partial** (POC is the value magnet) as a TP1 — but default partial = 0% because the locked base found banking *hurts* the runner ([[mastervp-tp1-partial-zero-is-best]]). Test, don't assume. |
| 6 | "start on BTC M3" | Keep BTC M3 as primary, **but require an early XAU cross-check and early MT5 confirmation** — BTC/Exness round-trips intrabar and has a documented history of *fictional* engine reversion edges (§7). |
| 7 | (implicit counter-trend) | The failed-acceptance + strong-rejection + wick + SL-above-sweep stack is precisely what separates "fade a trap" from "catch a falling knife into a real breakout." |

---

## 4. Parameters (defaults + sweep ranges)

All are real `Inp*` inputs (overridable from `.set`); none are compile-constants. Mirror C++ `xrev_*` ↔ MQL `InpXRev*`.

| `.set` key | C++ field | Default | Sweep range | Role |
|---|---|---|---|---|
| `InpEnableExtremeReversion` | `enable_extreme_reversion` | **false** | — | Master toggle (OFF). |
| `InpXRevHHLookback` | `xrev_hh_lookback` | 5 | 3–12 | `N` for the swing-high/low sweep level. |
| `InpXRevFailLookback` | `xrev_fail_lookback` | 14 | 8–30 | `M` window for the failed-acceptance count. |
| `InpXRevMinClosesBeyond` | `xrev_min_closes_beyond` | 2 | 1–5 | Min closes beyond `mVAH` in `M`. |
| `InpXRevMaxClosesBeyond` | `xrev_max_closes_beyond` | 0 (off) | 0 or 4–10 | Cap to exclude a real breakout. |
| `InpXRevMinAgeBars` | `xrev_min_age_bars` | 40 | 15–80 | Min bars since the opposite-edge cross (`mVAL` up-cross for short / `mVAH` down-cross for long) — the aged-excursion gate. |
| `InpXRevBigCandleAtr` | `xrev_big_candle_atr` | 1.0 | 0.6–1.8 | Rejection-bar range ≥ ×ATR. |
| `InpXRevBodyPctMin` | `xrev_body_pct_min` | 0.4 | 0.3–0.6 | Body fraction of range. |
| `InpXRevWickFrac` | `xrev_wick_frac` | 1.0 | 0.5–2.0 | Upper wick ≥ ×body (sweep tail). |
| `InpXRevNetDeltaMin` | `xrev_net_delta_min` | 0.6 | 0.4–0.9 | **The "net volume delta %"** (near-price net magnitude). |
| `InpXRevUseNodeGate` | `xrev_use_node_gate` | true | {0,1} | Require selling/absorption at `mVAH`. |
| `InpXRevSlAtr` | `xrev_sl_atr` | 0.7 | 0.3–1.5 | SL distance above swept high. |
| `InpXRevRrMin` | `xrev_rr_min` | 2.0 | 1.5–3.0 | Min RR to take the trade. |
| `InpXRevTp1ClosePct` | `xrev_tp1_close_pct` | 0 | 0–40 | Optional `mPOC` partial (default off). |

---

## 5. Implementation map (the build, once approved)

Mirrors how the Monster/impulse family was added (`impulse.hpp` is the template). **C++ first → sweep/lock → MQL5 port → parity** (per CLAUDE.md layering).

1. **`cpp_core/include/kk/common/types.hpp`** — add `bool is_extreme_rev = false;` to `Signal` (after `is_impulse`); reason tags `"S-XREV"/"L-XREV"`.
2. **`cpp_core/include/kk/common/config.hpp`** — add `enable_extreme_reversion` + the `xrev_*` fields with defaults (§4); add `apply_kv` mappings for each `InpXRev*` key (around the existing reversion keys). Confirm they are *not* in the non-input set so `.set` overrides them.
3. **`cpp_core/include/kk/mastervp/extreme_reversion.hpp`** (NEW, modeled on `impulse.hpp`) — `detect_extreme_reversion(p, master_cur, s, lookbackStats, ns_vah, ns_val, net_delta, ...)` implementing §2; returns a tagged `Signal`.
4. **`cpp_core/include/kk/mastervp/tick_engine.hpp`** `precompute_()` — precompute the per-bar lookbacks once (rolling `highestHigh(N)/lowestLow(N)`, the closes-beyond-`mVAH` count over `M`, and a running **bars-since-last-cross** counter for the `mVAL` up-cross / `mVAH` down-cross on the rolling levels — the aged-excursion gate A.3), alongside the existing `net_flow_`/`mpoc_` precomputes; pass them + the rejection-bar near-price net into `detect_extreme_reversion`; wire the **priority** (XRev before base reversion) under `if (p_.enable_extreme_reversion)`.
5. **`cpp_core/tools/mastervp/` tests** — golden unit test: synthesize a failed-breakout-sweep bar sequence, assert exactly one `S-XREV` fires with the expected SL/TP/RR; assert nothing fires when the toggle is OFF (proves base behavior is byte-identical when disabled).
6. **`research/optimization/sweep_mastervp_extreme_rev_btc.py`** (NEW, clone `sweep_mastervp_f1.py`) — Optuna over the `xrev_*` grid on a fixed train/test split; robustness-weighted score (`net/(1+dd)` with a both-windows-positive bonus); emit a ranked CSV. Same for XAU.
7. **MQL5 port (Phase 10, after C++ locks):** add `InpXRev*` to `mql5/experts/KK-MasterVP/Inputs.mqh`; port `detect_extreme_reversion` 1:1 into `Strategy.mqh`/`Engine.mqh` keeping names identical; emit parity CSV and diff vs engine.

---

## 6. Validation gates (must pass, in order — KENKEM_QUANT_OS §7)

1. **Costed backtest (Phase 7):** C++ tick engine with spread + commission + slippage + latency. BTC M3 **and** XAU M3/M5. Report PF, expectancy in **R**, win%, trade count, max DD. Uncosted = rejected.
2. **Sample size:** failed-breakout sweeps are *rare* — require enough trades per fold for significance (target ≥ ~100–150/fold); if too sparse, relax `M`/`minClosesBeyond` or pool symbols before drawing conclusions. Flag any fold with n too low.
3. **Sensitivity (Phase 8):** heatmaps over the key pairs — `netDeltaMin × bigCandleAtr`, `N × M`, `slAtr × rrMin`. **Accept only a plateau, not a peak.** Decompose **per-fold, especially the most recent OOS** — pooled WF averages hide regime non-stationarity ([[mastervp-m5-gate-sweep-lock]]).
4. **Walk-forward + Monte Carlo (Phase 9):** disjoint folds, OOS PF ≥ ~1.15 across folds, no period mixing; MC for P(profit), PF 5th-pctile, honest DD distribution.
5. **MT5 parity + demo (Phase 10):** byte-compatible parity CSV; **for BTC, require trade-match ≥ ~85% before trusting any engine PF** (XAU historically ~86%, BTC ~57%); then demo forward-test.

**Ship gate:** positive after costs **and** plateau-confirmed **and** MT5-confirmed (BTC especially). Until then it stays OFF.

---

## 7. Risks & failure modes

- **🚨 BTC engine over-optimism (the big one).** The BTC/Exness feed round-trips intrabar; the engine's runner/trail and reversion fills are too generous there. A prior MasterVP BTC reversion lock looked great in the engine (revNet +5,414) and was **MT5-disconfirmed (revNet −76, only 57% trade-match)** → `InpEnableReversion` was flipped OFF for BTC ([[mastervp-t3-reversion-lock]]). **Extreme Reversion is also a reversion family on BTC** — treat any BTC engine edge as *unproven* until MT5 confirms. This is why XAU cross-check + early MT5 are mandatory, not optional.
- **Catching a falling knife.** Fading into a genuine breakout. Mitigated by the failed-acceptance count, the close-back-below-VAH, the strong-rejection wick + flow, and SL above the swept high — but a sweep that *keeps going* is the core loss mode. Watch the loss-tail.
- **Rare setup → overfit.** Few trades invite curve-fitting on the 12 params. Mitigated by the plateau requirement, disjoint WF folds, and reading robustness across BTC+XAU jointly.
- **Far TP.** `mVAL` is a wide target on M3; many trades may stall mid-rotation. The `mPOC` partial is the hedge to test (but banking hurt the base — don't assume it helps here).
- **Overlap with base reversion** near the edge — handled by the priority rule (§2 Dispatch).

---

## 8. Resolved design decisions (locked 2026-06-20)

1. **TP model — DECIDED: test the `mPOC` partial.** Ship the TP1-partial-at-`mPOC` machinery (`InpXRevTp1ClosePct`) and **sweep it (0–40%)**; default stays 0% (banking hurt the base) but it is in scope, runner to `mVAL`.
2. **Validation symbols — DECIDED: BTC M3 + XAU M3/M5 in parallel.** XAU is the trustworthy cross-check for any BTC engine result (§7). Both must be reported for every sweep/WF/MC stage.
3. **Failed-acceptance count — DECIDED: bars that CLOSE above `mVAH`** (strict; condition A.2 stands as written — counts attempted acceptance / trapped longs). If sample size proves too thin in WF folds, the looser "high pokes above" variant is the documented fallback (§6 step 2), not a redesign.

---

*Build order when approved: types/config → `extreme_reversion.hpp` → tick_engine wiring → golden test → BTC+XAU sweep → plateau/WF/MC → MT5 parity. Nothing ships until §6 passes; default stays OFF so the locked base is untouched.*
