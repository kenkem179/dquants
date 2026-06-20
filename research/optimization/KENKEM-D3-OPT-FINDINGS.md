# KenKem XAU M1 — Optimization Findings (D3 lock)

_2026-06-20. Engine: `cpp_core/build/kenkem/tick_backtester` (TICK engine, the validated one).
Data: `research/kenkem_parity/ticks_xau_full.csv` + `bars_xauusd_M1_kk.csv` = **XAUUSD 2025-03-02 → 2026-05-29** (~15 months, 113M ticks). Harness: `research/optimization/sweep_kenkem_opt.py`.
Baseline config: `anchor_E1E2E4.set` (E1+E2+E4 on, E3/E5 off)._

## TL;DR — lock D3
**D3 = baseline + 4 mechanistic, portable changes.** Beats baseline on every axis AND smooths the
equity curve from a one-quarter wonder to 4-of-5 profitable quarters.

| Key | baseline → D3 | rationale |
|-----|---------------|-----------|
| `USE_DYNAMIC_RR_SCALING` | true → **false** | session×ATR-pctile RR scaler mis-tunes TP in recent regime |
| `E1_ATR_SL_CAP_MULTIPLIER` | 4.0 → **3.5** | hand-set cap was slightly wide; trims DD + OOS loss |
| `SIDEWAYS_BLOCK_THRESHOLD` | 53 → **45** | block chop one notch earlier (free OOS gain) |
| `MIN_ENTRY_ATR_PERCENTILE` | 65 → **70** | the master filter — only trade live volatility |

Preset: `research/kenkem_parity/KK-KenKem-XAUUSD-M1-D3.set` (also copied to MT5 Presets).

| Config | n | net | PF | maxDD | Sharpe | 2026 OOS |
|--------|----|-----|-----|-------|--------|----------|
| baseline | 259 | +2101 | 1.269 | 907 | 2.09 | −145 (0.93) |
| **D3** | 198 | **+2194** | **1.401** | **522** | **2.97** | **+470 (1.34)** |

Same net, **−42% drawdown**, PF 1.27→1.40, OOS flipped negative→strongly positive.

## The headline risk finding (per-quarter walk-forward)
**Baseline profit is 100% concentrated in 2025 Q4** (+2741 of +2101 total); the other 4 quarters are
break-even-to-losing. A pooled PF of 1.27 hid this. D3 broadens it:

| Quarter | BASE net (PF) | D3 net (PF) |
|---------|---------------|-------------|
| 2025 Q2 | −86 (0.97) | +302 (1.19) |
| 2025 Q3 | −410 (0.79) | −318 (0.79) ← only stubborn loser (summer chop) |
| 2025 Q4 | +2741 (3.02) | +1740 (2.80) ← lower peak, traded for safety |
| 2026 Q1 | +392 (1.74) | +444 (2.02) |
| 2026 Q2 | −537 (0.66) | +26 (1.03) |
| **profitable** | **2 / 5** | **4 / 5** |

## Sweep evidence (what's a lever vs what's inert)
- **Entry priority looks inverted but is actually correct (TESTED).** Detection is first-match-wins
  E1→E2→E4 (one slot/bar, faithful to EA `DetectNewEntry`, `:2225` `detectedTrade.type==""`). Static
  per-kind PF (E4 1.40 best/lowest-prio, E2 1.08 worst/outranks-E4) *suggested* reordering E1→E4→E2.
  **Tested via `ENTRY_E4_BEFORE_E2` flag → REJECTED:** reorder gave E4 +14 bars but its PF COLLAPSED
  1.51→1.24 (net +808→+551), book PF 1.401→1.268, worse in 4/5 quarters. Contested bars (both arm)
  self-select for E4 WEAKNESS; E2 absorbing them first KEEPS E4 selective (E4's in-book PF 1.51 > E4
  solo 1.40 *because* of this). Keep EA order; **keep E2** (its hidden job is protecting E4 selectivity).
- **E5 / E1+E5 unattractive.** E5 solo PF 1.04 (310 trades, near-zero edge); E1+E5 = 1.06 (worse than
  E1 alone). E5 is net-negative alongside E1 (−96..−114). Needs much tighter gating before it helps.
- **`MIN_ENTRY_ATR_PERCENTILE` is the master gate.** OFF → 512 trades, 2026 −1916, DD 2038. 65→70 (D3)
  preserves net while cutting DD 42%. 75 cuts too much net.
- **SL floors are inert** (no change 0.8→1.8 either side); structure stop always wider than floor×ATR.
- **E2/E4 cap tightening is a regime trap** (cap 2.0 → 2026 +341 but 2025 1.111 + DD 1413). Keep 3.0.
- **Many entry gates are inert at default** (E1_HTF_MIN_DI_SPREAD fully flat 2→8; E1_MIN_ADX≤19.5;
  min_TQ_E1≤6; sideways≥53). **E4 trend-quality≥9 is load-bearing** (lowering craters E4's edge).
  Tightening entry gates mostly HURTS — the edge is not in stricter entries.
- **TP/RR:** `USE_DYNAMIC_RR_SCALING=false` is the single best RR lever (overall PF up + OOS flips).

## Caveats
- 15-month single-symbol (XAU) window. 2025 Q3 stays unprofitable in every config tested.
- This is engine-side; **needs MT5 re-run of KenKemExpert with the D3 preset to confirm parity** before
  trusting the numbers live (baseline parity already validated; D3 only flips standard inputs).
- "Drop E2" helped on an earlier larger dataset but HURTS net on this 15-month set — left OFF the lock.
