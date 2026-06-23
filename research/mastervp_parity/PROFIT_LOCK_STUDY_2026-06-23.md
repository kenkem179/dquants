# MasterVP profit-lock ladder — study + MT5 A/B candidates (2026-06-23)

**User ask:** the M3 BTC version trailed the SL nicely to bank profit when price reversed; the latest
M5 lock "stupidly" rides a big floating profit back to break-even. Add smarter SL trailing / partial TP
so profit is secured more safely.

## Root cause — the 0.8R → chandelier "dead zone"

`position_manager.hpp` (engine) and `Engine.mqh` (EA) manage exits in three stages:
1. **< 0.8R** (`InpTp1R`): SL at the initial stop (1.2×ATR). No profit protection.
2. **at 0.8R**: SL → break-even (`InpBeAfterTp1`, +0.05 ATR).
3. **after 0.8R**: a **2.5×ATR chandelier trail** (`InpTrailAtrMult`) takes over.

The chandelier sits 2.5 ATR *behind* price, so for any winner that peaks between ~0.8R and ~2.5R the
trail candidate is still below entry and never engages — the only live stop is break-even. The trade runs
to +1.5R floating, retraces, and round-trips straight back to BE. That is the screenshot. The "good" M3
example only looked good because that winner ran far enough (>~2.5R) for the chandelier to actually bite.

**Quantified (engine WF, 6 disjoint folds, % of winners that reached ≥1R peak and ended ≤0.15R):**
- XAU-M5: **45.3%** round-trip · BTC-M5: **62.8%** · XAU-M3: **4.7%** · BTC-M3: n/a (no edge).

## ⚠️ Why the engine cannot be the judge here

The tick engine **over-credits the trailed runner** (HANDOFF 2026-06-23; MT5 A/B that day showed trail-2.5
beating trail-3.5 — the *opposite* of the engine's "wider is better"). So any engine sweep of profit
*protection* shows a net cost that is **over-stated**; real MT5 net cost is smaller (and the same session's
MT5 evidence says tighter protection actually *wins*). Therefore the engine's role below is narrow:
1. confirm PM-OFF == base (regression — verified: baseline row reproduces each lock exactly), and
2. provide the **mechanical round-trip rate** (giveback is a price-path fact, far less biased than net)
   so we can pick the *least-aggressive config that still fills the dead zone* as an **MT5 A/B candidate**.

**MT5 is the judge.** Adopt a candidate only if MT5 confirms it banks more / drawdowns less.

## The mechanism (ported to the EA, default-OFF)

Reused the existing `kk::common::ProfitManager` (`profit_manager.hpp`) — a 1:1 port now lives in the EA as
`mql5/experts/KK-MasterVP/ProfitManager.mqh`, wired into `Engine.mqh` after the chandelier (merged
tighten-only). **Every `InpPm*` toggle defaults OFF → `MvpPmAny()` false → block skipped → base
byte-identical.** The EA and engine read the *same* `InpPm*` keys, so one `.set` drives both. Two levers
matter for this problem:
- **progressive-trail (ladder):** SL→entry at `TriggerR`, then advances `StepR` per `IncrementR` of extra
  gain. A smooth ratchet that fills the dead zone — the "trail SL nicely to bank profit" behaviour.
- **giveback-cap (floor):** once peak gain ≥ `ArmR`, keep ≥ (1−`CapFrac`) of the peak locked. A hard floor.

## Per-market verdict (engine WF; net cost over-stated)

| Market | Base RT | Candidate | New RT | Engine net Δ | Engine DD |
|---|---|---|---|---|---|
| **XAU-M5** | 45.3% | **Ladder** prog 1.0 / 0.3 / 0.20 | **21%** | −4.5% | 7.8→7.8% (flat) |
| **XAU-M5** | 45.3% | **Floor** giveback arm 1.5R / keep 50% | **29%** | −4.6% | 7.8→**7.0%** (better) |
| **BTC-M5** | 62.8% | **Ladder** prog 1.0 / 0.3 / 0.20 | **25%** | −9% | 22→22.9% (flat) |
| **BTC-M5** | 62.8% | **Floor** giveback arm 1.5R / keep 67% | **33%** | −3.6% | 22→22.6% (flat) |
| XAU-M3 | 4.7% | — none — runners already clean; protection only costs net (PF 1.23→≤1.20) | — | — | worse |
| BTC-M3 | n/a | **DO NOT DEPLOY** — breakout structurally dead (PF 0.78, −$24k, 244% DD) | — | — | — |

The single lucky M3-BTC short in screenshot #1 is *survivorship*: over the full sample MasterVP breakout
loses on BTC-M3. Don't run it there.

## MT5 A/B — exact runs (the judge)

Expert **`KK-MasterVP`**, every-tick, deposit 10,000, period **2025.06.01 – 2026.05.29**. For each market
run the BASE lock first, then each candidate, same window/ticks. Load presets from Strategy Tester →
Inputs → Load → `dquants/KK-MasterVP/`. Adopt a candidate only if it banks ≥ base net **or** cuts DD with
≤ small net give-up, and the equity curve visibly stops round-tripping winners to BE.

**XAUUSD M5 chart:**
- base: `KK-MasterVP-XAUUSD-M5.set`
- A: `KK-MasterVP-XAUUSD-M5-Ladder.set`  (smooth ratchet)
- B: `KK-MasterVP-XAUUSD-M5-Floor.set`   (hard 50%-of-peak floor)

**BTCUSD M5 chart:**
- base: `KK-MasterVP-BTCUSD-M5.set`
- A: `KK-MasterVP-BTCUSD-M5-Ladder.set`
- B: `KK-MasterVP-BTCUSD-M5-Floor.set`

(XAU-M3: no profit-lock candidate — its winners run clean. BTC-M3: not deployable.)

## Repro

- Sweep: `research/mastervp_parity/profit_lock_sweep_2026-06-23.py --symbol {xau,btc} --tf {m3,m5} --mode {prog,giveback}`
- Raw output: `research/mastervp_parity/plock_2026-06-23/`
- Engine keys (same names in the EA): `InpPmProgTrail/ProgTriggerR/ProgIncrementR/ProgStepR`,
  `InpPmGiveback/GivebackArmR/GivebackCapFrac` (full ladder also exposes be_protect / partial_tp /
  tp_extension / pre_be_structure — all default OFF).
