# KenKem E1/E2/E4/E5 — Honest Sweep & Best Combinations (2026-06-21)

> **Read the trust boundary first.** This sweep uses the C++ TICK engine
> (`cpp_core/build/kenkem/tick_backtester`) over **XAUUSD 2025-03-02 → 2026-05-29**
> (~15 months, 113M ticks). The engine reproduces every documented baseline **exactly**
> (verified this session): baseline E1E2E4 +2101/PF1.269/259tr, D3-noE4 +1247/PF1.326/136tr,
> D4 +1695/PF1.419/148tr, D4+E5 +2092/PF1.184/397tr. So it is a **stable, deterministic
> measuring stick** — but its trustworthiness is **per-entry**, from the trade-for-trade
> MT5 parity work:
>
> | Entry | Entry selection | Exit modeling | Net/PF trustworthy? |
> |-------|-----------------|---------------|---------------------|
> | **E1** | ✅ ~93% recall, exact-minute | ✅ clean (eng +883 vs MT5 +868) | **YES** |
> | **E2** | ✅ ~96% recall | ⚠️ mildly optimistic (+591 vs +362) | **mostly** |
> | **E4** | ✅ ~94% recall | ❌ **FICTIONAL** (eng +747 vs MT5 −42; engine TP where MT5 SL) | **NO — MT5 only** |
> | **E5** | ⚠️ ~53% recall (onset latch) | ❌ optimistic | **NO — MT5 only** |
>
> **Rule applied throughout:** levers are judged on **2026 OOS + per-quarter robustness**,
> not pooled peaks. E4/E5 net/PF below are shown only to map the engine's *view* of the knobs;
> **the deploy verdict for E4 and E5 is MT5's, not the engine's.**

---

## TL;DR — the best combination is the one already locked

The sweep did **not** surface a new magic combo. It **confirms** that the MT5-validated
direction is correct and the knobs sit on plateaus:

- **Deploy now (MT5-confirmed):** `D3-noE4` = E1+E2, E4 off → **+1049 / PF 1.39 / 102 tr** live.
- **Best engine-measured E1+E2 (entry-side levers → should translate; needs MT5 confirm):**
  `D4` = D3-noE4 **+ E1_MIN_MOMENTUM_ADX 19.5→23 + E2_MAX_TOUCH_AGE 36→60**
  → engine **+1695 / PF 1.419** (vs D3-noE4 +1247). Both winning levers are **entry filters**
  (the side the engine models faithfully), so this is the one candidate I'd expect to carry to MT5.
- **E5 and E4 = MT5 decides.** Engine says both *dilute* the E1+E2 book, but the engine
  **cannot judge them** (E4 exits fictional, E5 ~half-missed). Shipped as toggle A/B sets.

---

## What each knob does (RR / ATR / ADX — the axes you asked for)

### RR (`tp` family, full E1E2E4 book)
- **`USE_DYNAMIC_RR_SCALING=false` is the single robust RR lever** — 2026 OOS −145→**+231**.
  The session×ATR-pctile RR scaler mis-tunes TP in the recent regime. (Already in D3/D4.)
- **Individual RR levels do NOT robustly beat defaults.** E1_RR sweep: 1.7 looks good pooled
  but every step is OOS-fragile (1.9→−145, 2.2→−284). On the clean E1+E2 book (`e1e2b` S5),
  **E1_RR=1.5 lifts 26Q1 to +452 but FLIPS 26Q2 to −98** — a textbook per-quarter illusion.
  E2_RR 2.3 craters 2026 (−373). **Keep RR defaults; the lever is DYN-off, not the RR number.**

### ATR (`sl` family)
- **`E1_ATR_SL_CAP_MULTIPLIER=3.5` is the OOS-best plateau** (2026: 3.5→−23 best, vs 4.0→−145,
  3.0→−121; 2.5→−494 and 5.0→−339 both crater). Already in D3/D4.
- **E2 cap: keep 3.0.** Tightening to 2.0 boosts 2026 (+341) but craters 2025 (PF 1.11) and
  **explodes DD to 1413** — a regime trap.
- **ATR SL floors (E1/E2) are fully INERT** — the structure stop is always wider than floor×ATR.
- **`MIN_ENTRY_ATR_PERCENTILE=70` is the master gate** (see `gates`): the single highest-impact
  filter — OFF → 512 tr / 2026 −1916 / DD 2038; 65→70 preserves net while cutting DD ~42%; 75 over-cuts.

### ADX (`gates` / `e1e2` families)
- **`E1_MIN_MOMENTUM_ADX=23`** (up from 19.5) is a clean robust winner on the E1+E2 book
  (`e1e2b` S1: +1247→+1397, both 2025 & 2026 up). In D4.
- **`SIDEWAYS_BLOCK_THRESHOLD=45`** (block chop one notch earlier) — free OOS gain. In D3/D4.
- E1 HTF-DI spread, low min-trend-quality, E1_MIN_ADX ≤19.5 = inert at default. Tightening
  entry gates mostly HURTS — **the edge is not in stricter entries.**
- **⚠️ The E4 fiction even poisons the ADX gate sweep.** `E1_MIN_ADX=23` on the E4-contaminated
  E1E2E4 base craters 2026 OOS (**−492**, PF 0.79) — the bars E1 declines get absorbed by E4
  (whose engine exits are fiction). On the **clean E1+E2 book** (`e1e2b` S1) the *same* lever
  *helps* 2026 (**+263**). This is why the trustworthy sweep must be run E4-OFF, and why D4 is
  measured on the E1+E2 book. ATR-pctile master gate is **essential** (`ATR_HIGH_BLOCK` OFF →
  2026 **−1916**); `MIN_ENTRY_ATR_PERCENTILE` plateau 65–75 (70 = lock); `RSI_DIVERGENCE_VETO`
  keep ON (off → 2026 −237).

### Entry combinations (`combos` family — individual vs combined)
Per-kind net on the E1E2E4 base (⚠️ E4/E5 exits = engine fiction; shown for the map only):

| Combo | net | PF | per-kind (engine) |
|-------|-----|-----|-------------------|
| E1 only | +894 | 1.24 | the reliable earner |
| E2 only | +241 | 1.14 | weak alone |
| E4 only | +1008 | 1.40 | **engine fiction** — MT5: E4 = net loser |
| E5 only | +357 | 1.04 | near-zero edge (engine; ~half missed) |
| E1+E2 | +717 | 1.13 | (old base; D3-noE4 lifts this to +1247) |
| E1+E2+E4 | +2101 | 1.27 | baseline — E4's +997 is fiction |
| E1+E2+E4+E5 | +1910 | 1.11 | E5 drags (−114 engine) |

**Honest reading:** E1 is the dependable core; E2 adds breadth + protects selectivity; E4's
apparent edge is an exit artifact; E5 is unresolved on the engine. The MT5-confirmed winner is
**E1+E2 (D3-noE4)**.

---

## Per-quarter robustness (the discipline that matters)
On the trustworthy E1+E2 book, D4 (S3) keeps **4 of 5 quarters profitable**
(25Q4 +1645, 26Q1 +202, 26Q2 +91; 25Q2/25Q3 are the stubborn summer-chop losers in *every*
config tested — a session/volatility filter is the untested lever there, outside RR/ATR/ADX).

---

## Deploy candidates (all flush-left, load directly into KenKemExpert.ex5)
_(MT5 run asks in the section below; sets live in `research/kenkem_parity/`)_

| Set | Entries | What it is | Confidence |
|-----|---------|------------|------------|
| `KK-KenKem-XAUUSD-M1-D3-noE4.set` | E1+E2 | **MT5-CONFIRMED lock** +1049/PF1.39 | ✅ live-proven |
| `KK-KenKem-XAUUSD-M1-D4.set` | E1+E2 | D3-noE4 + ADX23 + TouchAge60 | 🟡 engine-best, entry-side → MT5-confirm |
| `KK-KenKem-XAUUSD-M1-D4-E2RR14.set` | E1+E2 | D4 + E2_RR 1.4 (survived d5 joint test) | 🟡 engine +1775/PF1.44 → MT5-confirm after D4 |
| `KK-KenKem-XAUUSD-M1-D4-E5.set` | E1+E2+E5 | D4 + E5 on | 🔴 MT5 decides (engine can't judge E5) |
| `KK-KenKem-XAUUSD-M1-D4-E4.set` | E1+E2+E4 | D4 + E4 on | 🔴 MT5 decides (engine E4 exits fictional) |

## ▶️ EXACT MT5 RUN ASKS (you run these; I can't run MT5 headless)
**Common settings for every run:** Expert = **KenKemExpert** (legacy `.ex5` at
`mql5/experts/KK-KenKem/releases/1.8.154-legacy/`, or compile the source) · Symbol = **XAUUSD** ·
Timeframe = **M1** · Date range = **2025.03.02 → 2026.05.29** · Model = **Every tick (real ticks)** ·
Deposit 10000 · in Tester → **Inputs → Load** the named `.set` (it loads flush-left, no edits needed).
After each: tell me "ran it" and I auto-collect the tester output, diff vs engine, and report.

| # | Purpose | Load `.set` | Decision rule |
|---|---------|-------------|---------------|
| 1 | **Confirm D4** (engine-best E1+E2) vs the lock | `KK-KenKem-XAUUSD-M1-D4.set` | Ship D4 if it beats D3-noE4 (+1049/PF1.39) on **both** net AND PF |
| 2 | **Settle E5** (engine can't judge it) | `KK-KenKem-XAUUSD-M1-D4-E5.set` | Ship E5 only if E1+E2+E5 beats the better of D3-noE4/D4 on **both** net AND PF |
| 3 | **Re-test E4** (you re-included it; engine exits are fiction) | `KK-KenKem-XAUUSD-M1-D4-E4.set` | Ship E4 only if E1+E2+E4 beats E1+E2 on **both** net AND PF (prior MT5: E4 was a net loser) |
| 4 | **Refine** (only if #1 confirms D4) | `KK-KenKem-XAUUSD-M1-D4-E2RR14.set` | Adopt if it beats D4 on **both** net AND PF (E2_RR touches TP → confirm, don't assume) |

Run **#1 first** (highest-confidence). #2 and #3 are independent A/Bs (order-free). #4 is a follow-up to #1.
Each set differs from D4 by exactly one key/toggle, so every diff is clean.

## Granular E1+E2 sweep (the TRUSTWORTHY book, from D3-noE4 base) — `e1e2` family
On the clean E1+E2 book (E4 OFF), the lock knobs sit at their **OOS-robust optima**:
`MIN_ENTRY_ATR_PERCENTILE=70` best (60/65 dilute, 75/80 over-cut), `SIDEWAYS_BLOCK=45` best 2026
(53 higher pooled-2025 but weaker OOS), `E2_MAX_TOUCH_AGE=60` best (+1470, 2026 +290),
`E1_MIN_MOMENTUM_ADX=23` clean win (+1397). These ARE the D4 levers.

**Three refinements beat D4-base pooled while keeping 2026 positive (all ENTRY-side → engine-faithful):**
- `E1_MAX_CROSS_AGE` 80→**60**: +1247→**+1434**, 2026 +251→+245 (flat). (100/120 = overfit: 2026 collapses.)
- `E1_ATR_SL_CAP` 3.5→**3.0**: +1247→**+1534**, 2026 +251→+221. (On the clean book 3.0>3.5; the `sl` family
  said 3.5 only because E4 contaminated that base.)
- `E2_RR` 1.575→**1.4**: +1247→**+1300**, 2026 +251→**+294** (banks the pullback sooner).

⚠️ **These are NOT yet a lock.** Per the repo's hard lesson (*sequential wins can fail jointly; per-quarter
illusions* — cf. E1_RR=1.5 which lifts 26Q1 but flips 26Q2), the `d5` family stack-tests them on D4
**per-quarter**. Only fold a `D5` set into the MT5 asks if it beats D4 across quarters (esp. both 2026
quarters). See `sweep_logs_2026-06-21/d5.log`. Until then **D4 is the candidate to MT5-confirm.**

## E5 & E4 verdict (per-quarter table — `final` family)
Per-kind net + per-quarter for the 4 deploy candidates on the trustworthy window:

| Candidate | n | net | PF | per-kind | 26Q1 | 26Q2 |
|-----------|---|-----|-----|----------|------|------|
| D3-noE4 ✅MT5-confirmed | 136 | +1247 | 1.326 | E1 +928 / E2 +319 | +130 | +121 |
| **D4** 🟡engine-best E1+E2 | 148 | **+1695** | **1.419** | E1 +1214 / E2 +481 | **+202** | **+91** |
| D4+E5 🔴directional | 397 | +2092 | 1.184 | +E5 +435 @PF1.06 | +421 | **−427** |
| D4+E4 🔴E4=fiction | 209 | +2414 | 1.416 | +E4 **+711 (fiction)** | +598 | **−115** |

**Reading it honestly:**
- **D4 is the clean winner** — best PF (1.419) and **both 2026 quarters positive**.
- **E5 (engine view = dilute + hurt OOS):** adds 248 trades earning only +435 (PF 1.06, razor-thin),
  drops book PF 1.419→1.184, nibbles E1 (1214→1118 via slot contention), and **flips 26Q2 to −427.**
  E5 RR 1.5 is the engine-best E5 RR (higher hurts); E5_MIN_ADX/TQ tightening kills E5's thin edge.
  **BUT the engine misses ~half of real E5 and is optimistic on E5 exits** — so this negative signal is
  *directional*; only the MT5 A/B (`D4-E5.set`) settles it. Ship E5 only if MT5 E1+E2+E5 beats D4.
- **E4 (engine pooled +2414 is INFLATED):** E4's +711 is exit-fiction; even on the optimistic engine E4
  **flips 26Q2 to −115** and worsens 25Q3. MT5 ground truth had E4 a **net loser**. Re-test via
  `D4-E4.set`; ship only if MT5 E1+E2+E4 beats E1+E2 (unlikely on the prior evidence).

## D5 stack-test verdict (`d5` family) — the discipline paid off
Tested the 3 granular refinements **stacked on D4, per-quarter** (not on the weaker D3-noE4 base):

| On top of D4 | net | PF | 2026 | verdict |
|--------------|-----|-----|------|---------|
| (D4 base) | +1695 | 1.419 | +293 | — |
| **+ E2_RR 1.4** | **+1775** | **1.440** | **+329** | ✅ **robust win** — pooled + OOS + PF all up |
| + cross-age 60 | +1667 | 1.409 | +201 | ❌ hurts 2026 (only helped on D3-noE4 base) |
| + E1cap 3.0 | +1678 | 1.399 | +250 | ❌ hurts 2026 |
| + all 3 (D5) | +1675 | 1.404 | +113 | ❌ **26Q2 flips −33** (sequential wins fail jointly) |

**Conclusion:** only `E2_RR=1.4` survives the joint per-quarter test. cross-age60 / E1cap3.0 were
**base-dependent illusions** — real on D3-noE4, gone once D4's ADX23+TA60 are in. This is precisely why
levers must be re-tested jointly, not stacked from isolated wins. → new optional candidate
**`D4-E2RR14`** = D4 + E2_RR 1.4 (engine +1775/PF1.440/2026 +329). Caveat: E2_RR sets the TP (an *exit*
lever, and E2 exits carry mild engine optimism) — so confidence is a notch below D4's pure-entry levers;
MT5-confirm as a follow-up to D4.

## Final answer — best combinations, ranked by confidence
1. **`D3-noE4`** (E1+E2) — ✅ **MT5-CONFIRMED +1049/PF1.39.** The proven floor; deploy-ready today.
2. **`D4`** (E1+E2 + ADX23 + TouchAge60) — 🟡 engine **+1695/PF1.419**, pure entry-filter levers →
   highest-confidence improvement to carry to MT5. **Run this first.**
3. **`D4-E2RR14`** (D4 + E2_RR 1.4) — 🟡 engine **+1775/PF1.440**, the one refinement that survived
   joint per-quarter testing; MT5-confirm after D4.
4. **`D4-E5`** / **`D4-E4`** — 🔴 engine says both *dilute/hurt* the book (E5 flips 26Q2 −427; E4 exits
   fiction + flips 26Q2 −115); MT5 A/Bs only — ship only if MT5 beats D4 on net AND PF.
