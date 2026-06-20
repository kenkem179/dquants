# KK-MasterVP Extreme Reversion (XRev) — build + sweep findings (2026-06-20)

Build of the `KK-MasterVP-ExtremeReversion.md` plan: a failed-breakout liquidity-sweep reversal
entry family, **toggle OFF by default** so the locked base is byte-identical. C++ engine first →
isolated/additive sweeps → MQL5 port (KK-MasterVP **and** Monster EAs) → presets for MT5 A/B.

## What shipped
- **C++**: `cpp_core/include/kk/mastervp/extreme_reversion.hpp` (pure detector, mirrors `impulse.hpp`),
  `is_extreme_rev` on `Signal`, `enable_extreme_reversion` + 13 `xrev_*` params + `apply_kv` keys,
  precompute lookbacks + priority dispatch in `tick_engine.hpp` (gated on the toggle).
- **Tests**: `tests/mastervp/test_extreme_reversion.cpp` (9 cases: fire/no-fire, SL/TP/RR, toggle-off).
  `make test` green (28→+ checks); `test_parity_golden` unchanged → **base byte-identical when OFF**.
  Empirical: XAU M5 locked set OFF vs default = 103/103 identical trades, same balance.
- **MQL5**: `ExtremeReversion.mqh` (1:1 port) wired into BOTH `KK-MasterVP/Engine.mqh` and
  `KK-MasterVP-Monster/Engine.mqh`, `InpXRev*` inputs default OFF. Both EAs compile **0/0**.
- **Presets** (flush-left, in EA folders + MT5 Tester Presets + kenkem Presets):
  `KK-MasterVP-XAUUSD-M3-XRev.set`, `KK-MasterVP-Monster-BTCUSD-M3-XRev.set`.
- **Sweep harness**: `research/mastervp_parity/sweep_xrev.py` (isolated + additive, train/OOS).

## The setup is RARE by design
With default-strict params XRev fires ~1 signal / 5-month M5 window. The structural ceiling (sweep
above `max(mVAH,HH(N))` + close back below `mVAH`, sign-only) is ~300 (XAU M3) / ~510 (BTC M3) raw
signals over the train window; the conviction gates (wick, body, candle-size, flow, failed-acceptance,
age, RR) cut it to a handful. **A 6-fold walk-forward is infeasible (~1-2 trades/fold).** train/OOS
split is the right granularity here. Sample is the dominant limitation — every result below rests on
**5-10 trades** and must be read as low-confidence.

## Key sweep findings (isolated XRev, breakout+reversion OFF)
- **The upper-wick "sweep tail" is the single strongest discriminator** (as the plan predicted).
  BTC M3 isolated OOS PF: WickFrac 0.0→1.16, 0.5→1.54, 1.0→2.92 (replicates train→OOS).
- **`BigCandleAtr` must stay ≤0.6.** At 1.0 it overfits train (PF 24!) and DESTROYS OOS (PF 0.54).
- **The synthetic node-net gate (`NetDeltaMin`) adds noise on BTC** — best at 0.0. Node gate OFF.
- `MinAgeBars`/`RrMin` are near-inert in the BTC plateau; kept at thesis defaults (40 / 2.0).
- **Chosen candidate** (both presets): Wick 0.5, BigCandle 0.6, Body 0.3, Closes≥2, Fail 30, Age 40,
  RR 2.0, NetDelta 0.0, NodeGate off, SL 0.7, HH 5.

## Additive impact on the locked base (the real deployment; XRev as an overlay)
| symbol/TF | base OOS PF / net / dd | +XRev OOS PF / net / dd | verdict |
|---|---|---|---|
| **BTC M3** (Monster, impulse ON, +M1) | 1.284 / +4288 / 7.1% | **1.330 / +5138 / 6.6%** | HELP (+9 tr, dd↓) |
| **XAU M3** (KK-MasterVP) | 1.114 / +4575 / 17.5% | **1.122 / +5077 / 17.2%** | help (+5 tr) |
| **XAU M5** (KK-MasterVP) | 1.422 / +10211 / 8.1% | 1.401 / +9780 / 8.1% | **HURT** (−1.5%) |

(Train mirrors OOS direction on all three.) BTC M3 is the standout — XRev lifts PF and net **and
lowers drawdown** (counter-trend entries hedge the trend base). XAU M3 mildly helps; XAU M5 hurts
(don't enable on M5).

## ⚠️ The honest caveat (why this stays OFF until MT5 confirms)
The biggest engine win (BTC M3) is on the **BTC/Exness feed, which the engine has historically been
over-optimistic about for reversion families** — the T3 mean-reversion lock looked great in the engine
(revNet +5,414) and was **MT5-DISCONFIRMED** (revNet −76, 57% trade-match); same for Monster BTC M3.
**XRev is also a reversion family on BTC.** The trustworthy XAU feed only marginally confirms (M3) or
disconfirms (M5). So: **default OFF everywhere; MT5 A/B is mandatory before any trust.**

## "Bank full profit at mPOC" (humble RR) test — mean-reversion-only & XRev-only (2026-06-21)
User ask: do reversion + XRev take MORE profit banking the whole position at the **master POC** (the value
magnet, a closer/humbler-RR target) than trailing to the far value edge? Added two gated flags (default OFF
→ base untouched): `rev_tp_mpoc` (base reversion TP=mPOC) and `xrev_tp_mpoc` (XRev TP=mPOC). Test = isolated
(breakout OFF), **fixed bracket** (`InpTrailRunner=false`, `InpTp1ClosePct=0`, `InpBeAfterTp1=false`), XRev
`rr_min=0.5` (humble). OOS PF, mPOC-bank vs trail:

| family | XAU M5 | XAU M3 | BTC M3 |
|---|---|---|---|
| **Mean-rev** mPOC / trail | **1.57 / 1.29** (net +511/+218) | 1.03 / 0.90 | 0.78 / 0.91 |
| **XRev** mPOC / trail | **2.84 / 0.96** (net +413/−9) | 3.32 / 2.19 (n11; TR neg) | 1.93 / 3.17 |

**Verdict: banking at mPOC WINS on XAU, LOSES on BTC.** Economic reading: XAU (mean-reverting metal) rotates
to value and the humble mPOC bank beats trailing a move that often fails to reach the far edge — for XRev the
*trailing* far-edge version is even **net-negative** on XAU M5 (TR −313), mPOC flips it positive. BTC (trendier,
noisy feed) the runner captures the bigger swing, so the far edge/trail wins; BTC mean-reversion is a net loser
either way. **Best standalone reversion result = XAU M5 mean-rev @ mPOC (OOS PF 1.57)** and XAU M5 XRev @ mPOC
(OOS PF 2.84, n4 — tiny). Samples small for XRev (4-18 tr); mean-rev healthy (n18-93).

⚠️ **Additive-deployment caveat:** banking reversion at mPOC needs `trail_runner=false`, but that flag is GLOBAL
— turning it off would also stop the breakout base trailing. Running reversion-at-mPOC *additively on top of the
trailing breakout base* requires per-entry-type exit routing (fixed-TP for reversion, trail for breakout) in the
shared `position_manager` — deferred (would risk the base). The table above is the STANDALONE (breakout-off) test.
Flags `InpRevTpMpoc`/`InpXRevTpMpoc` ported to both EAs (default OFF, compile 0/0).

## ▶️ MT5 tests for the user (A/B each preset against its base; toggle `InpEnableExtremeReversion`)
1. **BTC M3** — Expert `KK-MasterVP-Monster`, BTCUSD **M3**, 2025.08–2026.06, every-tick.
   Preset `KK-MasterVP-Monster-BTCUSD-M3-XRev.set` (XRev ON) vs the same with toggle false (base).
   Engine expects OOS PF 1.284→1.330, net +4288→+5138, dd 7.1→6.6%. **This is the decisive test.**
2. **XAU M3** — Expert `KK-MasterVP`, XAUUSD **M3**, 2025.06–2026.05, every-tick.
   Preset `KK-MasterVP-XAUUSD-M3-XRev.set` vs toggle false. Engine: OOS PF 1.114→1.122.
Ship XRev (flip a base default ON) only if MT5 beats the base on BOTH net AND PF, BTC especially.
