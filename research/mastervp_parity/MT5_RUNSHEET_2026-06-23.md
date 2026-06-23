# MT5 A/B Run-Sheet — KK-MasterVP runner-protection (2026-06-23)

**Goal:** find an exit/protection tweak that beats the locked XAU-M5 result, OR cuts drawdown with
little net give-up while stopping winners from round-tripping to break-even. The C++ engine over-credits
the trailed runner, so **MT5 is the sole judge** for anything touching exits.

## Fixed run settings (identical for EVERY run)
- **Expert:** `Experts\dquants\KK-MasterVP\KK-MasterVP.ex5` (attach to the chart)
- **Model:** Every tick based on real ticks
- **Deposit:** 10000  · **Leverage:** as your account
- **Load `.set` via:** Tester → Inputs → Load → `dquants\KK-MasterVP\<file>.set`
- **XAU runs:** Symbol **XAUUSD**, Timeframe **M5**, Period **2025.06.01 – 2026.05.29**
- **BTC runs:** Symbol **BTCUSD**, Timeframe **M5**, Period **2025.06.01 – 2026.05.29**

## Baselines to beat
| Market | Baseline preset | Result to beat |
|---|---|---|
| XAU M5 | `KK-MasterVP-XAUUSD-M5.set` | **net +62,732** (lock, trail 2.5) — beat this on net, or cut DD with ≤ small net give-up |
| BTC M5 | `KK-MasterVP-BTCUSD-M5.set` | full-window ~breakeven (PF 1.013) — goal is **lower DD without going net-negative** |

---

## ▶ BATCH A — XAU M5 only, 4 runs (do this FIRST; each = one input vs lock)
Run the base once, then each candidate. All single-input changes, zero parity risk.

| # | Preset | Lever changed | Hypothesis |
|---|---|---|---|
| A0 | `KK-MasterVP-XAUUSD-M5.set` | — (baseline) | reference = +62,732 |
| A1 | `KK-MasterVP-XAUUSD-M5-Trail20.set` | `InpTrailAtrMult` 2.5→2.0 | tighter trail protects runner (MT5 just favored tighter) |
| A2 | `KK-MasterVP-XAUUSD-M5-Trail15.set` | `InpTrailAtrMult` 2.5→1.5 | tighter still |
| A3 | `KK-MasterVP-XAUUSD-M5-Tp1bank25.set` | `InpTp1ClosePct` 0→25 | your idea 1: bank 25% at TP1 |
| A4 | `KK-MasterVP-XAUUSD-M5-SL10.set` | `InpSlAtrBrk` →1.0 | your idea 2: tighter initial SL |

**STOP-EARLY RULE after Batch A:**
- If **A1 or A2 beats +62,732** (or matches net with lower maxDD) → tighter trail already solves the
  round-trip problem. **Skip Batch B entirely** (Ladder/Floor target the same dead zone — redundant).
- If A1/A2 both **hurt** net and DD → trail-tightening isn't the answer → **proceed to Batch B** to test
  the dedicated profit-lock mechanism.
- A3/A4 are expected to lose (engine + prior WF rejected them); run them only to MT5-confirm your two
  ideas are truly dead. If either surprises and beats baseline, keep it.

---

## ▶ BATCH B — Profit-lock ladder, 6 runs (only if Batch A trail-tightening failed)
Tests the dedicated dead-zone filler (0.8R→chandelier gap). One active lever each; rest default-OFF.

| # | Symbol | Preset | Active lever |
|---|---|---|---|
| B0x | XAU M5 | `KK-MasterVP-XAUUSD-M5.set` | baseline (reuse A0) |
| B1x | XAU M5 | `KK-MasterVP-XAUUSD-M5-Ladder.set` | `InpPmProgTrail=true` (progressive ratchet 1.0/0.3/0.20) |
| B2x | XAU M5 | `KK-MasterVP-XAUUSD-M5-Floor.set` | `InpPmGiveback=true`, arm 1.5R, keep 50% |
| B0b | BTC M5 | `KK-MasterVP-BTCUSD-M5.set` | baseline |
| B1b | BTC M5 | `KK-MasterVP-BTCUSD-M5-Ladder.set` | `InpPmProgTrail=true` |
| B2b | BTC M5 | `KK-MasterVP-BTCUSD-M5-Floor.set` | `InpPmGiveback=true`, arm 1.5R, keep 33% |

**ADOPT RULE for Batch B:** adopt a candidate if it **banks ≥ baseline net OR cuts maxDD meaningfully
with ≤ small net give-up**, AND the equity curve visibly stops round-tripping winners back to BE.

---

## Do NOT bother running (already settled)
- **XAU M3 protection** — winners run clean (4.7% round-trip); protection only costs net.
- **BTC M3 anything** — breakout dead (PF 0.78 / −$24k / 244% DD). The lucky M3-BTC screenshot was survivorship.
- **trail 3.5** — already MT5-disconfirmed (−24% vs lock); set deleted.

## After you run
Drop me the MT5 results (net / PF / maxDD per run, or the report HTMLs). I'll auto-collect them into a
dated `mt5_runs/` folder, diff vs baseline, and tell you which (if any) to lock + ship.
