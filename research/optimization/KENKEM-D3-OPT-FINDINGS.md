# KenKem XAU M1 — Optimization Findings (D3 lock)

> ## ⚠️ 2026-06-20 MT5 REALITY CHECK — engine numbers are INFLATED by an E4 exit bug
> The D3 MT5 confirm run (after fixing a `.set` whitespace bug that made MT5 silently ignore the
> preset twice) returned **+905 / PF 1.22 / 155 trades**, vs engine **+2194 / PF 1.40 / 198**.
> Time-aligned diff (`mt5_runs/2026-06-20_D3/`):
> - **Entry parity is fine** — 141/155 matched; engine over-fires net only −28, MT5-only trades net −284.
> - **E1 is exit-clean** (engine +883 vs MT5 +868 on matched).
> - **E4 exits are BROKEN.** All 48 matched E4 trades have *identical entry time+price*, but engine
>   books +747 where MT5 books **−42** (sign-flips: engine TP where MT5 hits SL). SL levels differ by
>   only ~0.29 median → not an SL-level issue; the engine **misses the intrabar adverse path** that
>   stops MT5 out (engine eMFE≫MT5 mMFE; engine `maeR` is a 0.00 stub). E2 is mildly optimistic
>   (+591 vs +362).
> - **CONSEQUENCE: "E4 is the best entry (PF 1.51)" and the reorder-rejection rationale below are
>   ARTIFACTS of fictional E4 exits.** In MT5 ground truth E4 is a net loser (−167). Engine-based
>   sweep conclusions carry an exit-optimism bias (worst on E4, mild on E2, ~none on E1).
> - **RESOLVED via MT5 A/B → NEW LOCK = D3-noE4 (E1+E2, E4 OFF).** `KK-KenKem-XAUUSD-M1-D3-noE4.set`,
>   MT5-confirmed: **+1049 / PF 1.39 / 102 tr** vs full-D3 +905 / PF 1.22. OOS 2026 +243/1.23 → **+327/1.47**;
>   profitable quarters 3/6 → **4/6** (25Q2 +231, 26Q2 flips −279→+57). Only 26Q1 preferred E4 (+522→+270),
>   outweighed. Both runs in `mt5_runs/2026-06-20_D3{,-noE4}/`. Stubborn losers: 25Q1 (sparse early data),
>   25Q3 (summer chop).
> - **Still TODO (engine):** fix E4 intrabar exit evaluation so engine sweeps involving E4 are trustworthy
>   again. Not blocking the lock (E4 is OFF), but required before any future E4 work.
>
> ## D4 — E1+E2 sweep candidate (engine, awaiting MT5 confirm)
> From D3-noE4 base, swept E1 (cross-age/RR/SL/ADX/DI/TQ) + E2 (touch-age/RR/SL) + master gates
> (`e1e2`/`e1e2b` families). Both winning levers are ENTRY filters → the side the engine models
> faithfully (E1 parity-clean, E2 ~96% recall), so this should translate to MT5 unlike E4 exits.
> **D4 = D3-noE4 + `E1_MIN_MOMENTUM_ADX` 19.5→23 + `E2_MAX_TOUCH_AGE` 36→60** (`KK-KenKem-XAUUSD-M1-D4.set`):
> engine ALL +1247→**+1695 / PF 1.42**, Sharpe 2.47→**3.12**, OOS +251→**+293**, per-quarter keeps BOTH
> 2026 quarters positive (26Q1 +202, 26Q2 +91). The two levers are ADDITIVE (S1 +ADX23 +1397, S2 +TA60
> +1470, S3 both +1695). REJECTED: `min_TQ_E1=8` (redundant w/ ADX23), `E1_RR=1.5` (pooled OOS +353 but
> 26Q2 FLIPS to −98 — per-quarter illusion). Master gates ATRpct70 + sideways45 already optimal; E1 HTF-DI
> & low min_TQ inert; cross-age 100-120 = overfit trap. ⏳ needs MT5 run to confirm before lock.
>
> ## E5 — MT5 evaluation queued (engine CANNOT judge; user-requested)
> Preset `KK-KenKem-XAUUSD-M1-D4-E5.set` = D4 + `ENABLE_E5_ENTRIES=true` (E1+E2+E5, E4 OFF). Engine
> reference (DIRECTIONAL ONLY — engine under-counts E5 entries ~53% recall + is optimistic on E5 exits):
> D4 148tr/+1695/**PF 1.419** → D4+E5 397tr/+2092/**PF 1.184**. E5's own 248 engine-trades earn +435
> (PF ~1.04, razor-thin) and dilute book PF; E5 also nibbles E1/E2 via 1-slot/bar contention (E1
> +1214→+1118). Engine verdict = "E5 dilutes quality", BUT MT5 fires ~2× the E5 entries the engine
> misses → only MT5 can settle it. (Accidental MT5 E5-*solo* run earlier = +1019, but that's E5 with
> ALL slots, not the leftovers it gets behind E1/E2.) **RUN #2 after D4 confirms:** same XAU M1
> 2025.03.02→2026.05.29 every-tick, Load `KK-KenKem-XAUUSD-M1-D4-E5.set`; ship E5 only if E1+E2+E5
> net AND PF both beat D4's E1+E2.


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
