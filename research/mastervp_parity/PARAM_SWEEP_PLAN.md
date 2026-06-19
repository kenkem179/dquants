# KK-MasterVP — Parity-First Build & Parameter-Sweep Plan

_Author: Claude (Opus 4.8). Date: 2026-06-20. Instrument focus: **XAUUSD M3**.
Objective class chosen by user: **Robust PF + plateau** (not lone peaks)._

> **The one rule that governs everything below:** we never tune an engine we cannot trust.
> First reproduce the TradingView reference run trade-for-trade (Phase 0). Only then do we
> optimize — and we add each new risk-management layer **one at a time, defaulting OFF**, so
> every change is an isolated A/B and we always know whether a delta is a *parity fix* or an
> *alpha change*. This mirrors how the Pine itself is written (every new filter is an opt-in
> toggle that is byte-identical when OFF).

---

## 1. Reference & ground truth

| Artifact | Path | Role |
|---|---|---|
| Reference Pine (v6 `strategy`) | `research/mastervp_parity/KK-MasterVP.pine` (962 lines) | **Source of truth** for logic |
| TradingView trade log | `~/Downloads/KK_-_Master_VP_OANDA_XAUUSD_2026-06-20.csv` (10,408 rows = 5,204 trades) | **Parity target** |
| TV headline result | +2583.77% net / 39.98% maxDD / 56.98% win / PF **1.24** / 5,204 trades / 365d (2025-06-19 → 2026-06-19) | Acceptance benchmark |
| C++ infra to reuse | `cpp_core/include/kk/mastervp/*` + `cpp_core/include/kk/common/*` | VP, node engine, indicators, risk, loader |
| Engine tick data | `data/processed/ticks_xauusd_{2024,2025,2026}.parquet` + M1/M3 bars | Headless replay |

**TV log column map** (for the parity differ): `Trade number, Type{Entry/Exit long/short},
Date and time (UTC, minute), Signal{L|S|L TP1|L TP2|S TP1|S TP2}, Price USD, Size qty, Size value,
Net PnL USD, Net PnL %, MFE USD/%, MAE USD/%, Cumulative USD/%`. Each trade number appears on ≥2 rows
(entry + one-or-more exits). TP1/TP2 tags confirm the **partial-exit** structure (20% at TP1, runner at TP2).

> ⚠️ Data-source caveat (documented, accepted): the TV run is **OANDA XAUUSD** tick/`use_bar_magnifier`
> data; our engine replays **our MT5 feed**. Tick volume differs between feeds, and the whole VP/node
> engine is built on tick volume. So Phase-0 parity is **distributional/structural**, not byte-exact:
> we target the *shape* (trade count within a band, win%, PF, entry-price geometry, exit-tag mix),
> not identical fills. Byte-exact parity is reserved for the eventual **C++↔MQL5** leg on a shared feed.

---

## 2. The complete trading model (the faithful spec)

Everything the reference Pine does to make a trade. Lines 672–962 are **pure visuals** — ignored.
Defaults below are the **baseline that produced the 5,204-trade TV run**.

**Indicators**
- VP local: `f_vp(50, 30, 70%)`; VP master: `f_vp(150, 30, 70%)` → `poc/vah/val`, `mPoc/mVah/mVal`.
  Each bar contributes its **whole `volume`** to the single bin holding its `hlc3`. VA grows from POC
  outward, high-side wins ties (`nextH >= nextL`).
- Node engine on the **master 150-bar grid** (30 bins): decay `0.94`/bar; `dirProxy=(c−o)/max(h−l,tick)`;
  `buyProxy=vol·max(dir,0)`, `sellProxy=vol·max(−dir,0)`; bins touched by the bar split the proxy; `net=(b−s)/max(b+s,1)`;
  **absorbed/DEAD** iff `touch≥4.0 && |net|≤0.15`. (Used by the optional node gate & all visuals.)
- `atr = ta.atr(14)` (Wilder). `[plus,minus,adx]=ta.dmi(14,14)`. `emaFast=ema(24)`, `emaSlow=ema(194)`.

**Regime** — `trendRegime = adx>22 && |plus−minus|>6 && |emaFast−emaSlow|>0.25·atr`; `balanceRegime = !trend`.

**Signal-bar selection** — `usePriorBarVP=false` (baseline): signal reads **prior bar** price `[1]`
vs the **current** value area `[0]`. (The ON variant is a research lever, §5.)

**Breakout (ON by default — this is what fires the 5,204 trades):**
- Long: `trendRegime && sC > mVah + 0.50·atr[1] && plus>minus` (+ optional flow/veto/node gates, all OFF).
- Short mirror at `mVal`. **No upper distance bound** → chases extended breaks (see §4-Q2).

**Reversion (OFF by default):** `balanceRegime && wick within 0.1·atr of mVal/mVah && rejection body ≥0.6`
(+ optional reentry / both-POC / POC-target / SFP, all OFF).

**Execution / sizing**
- One position only (`pyramiding=0`; entry requires `position_size==0`). Long/short symmetric.
- Risk sizing ON: `riskBudget = 2.0% · (initial_capital + closed_netprofit)`; `qty = riskBudget/(stopDist·pointvalue)`,
  `pointvalue` falls back to 1.0 on OANDA XAU.
- SL: breakout `1.48·atr` (floored `8·tick`); reversion `1.5·atr`, additionally floored below the signal-bar
  swing (`pl−4·tick` long). `risk = |entry − SL|`.
- TP1 = `entry ± 0.8R`, close **20%**. TP2 = `entry ± RR·R`, `RR_brk=1.8`, `RR_rev=1.2`.
- **BE-after-TP1 ON**: once price tags TP1, runner stop ratchets to `entry ± 0.05·atr` (monotonic).

**Safety gates** (`safetyOk`, all must pass to enter):
`allowTrading && validTf && inAnySession && atrTicks≥40 && tradesThisSession<4`.
Sessions UTC: **Asia 0000-0700, London 0700-1300, NY 1300-2100**. Counter resets on session change.

**What is NOT in the Pine (the gap you want to close):**
no daily-DD breaker, no consecutive-loss cooldown, no peak-equity DD trail, no news filter,
no session force-close exit, no chandelier trail, no TP-extension logic, no ATR-percentile *entry* gate.
These are the **additive layers** of Phase 2+.

---

## 3. Parameter inventory — four buckets

We classify every knob so the sweep never wastes compute on things that should stay fixed for parity,
and never "optimizes" a structural constant into an overfit.

### Bucket A — STRUCTURAL / PARITY-LOCKED (do **not** sweep; fix to reproduce TV)
`vpLookback=50`, `vpBins=30`, `vaPct=70`, `masterMult=3`, `atrLen=14`, `emaFast=24`, `emaSlow=194`,
`adxLen=14`, node engine consts (`decay=0.94`, `touchAtr=0.05`, `neutral=0.15`, `saturation=4.0`),
`pyramiding=0`, sizing model (`2%`), `tp1Close=20%`, `tp1Rr=0.8`, `beBufAtr=0.05`, session windows,
all optional filters OFF. These define the *identity* of the strategy; changing them is a different strategy,
not a tuning. (We may revisit a few in a deliberate **Bucket-A robustness pass** late in §5, never in the main sweep.)

### Bucket B — ENTRY-SHAPE (primary alpha levers — sweep first)
| Param | Pine default | Sweep range (coarse) | Hypothesis |
|---|---|---|---|
| `break_buf_atr` | 0.50 | 0.25 → 1.00 (step 0.05) | How far past mVAH/mVAL = a *real* break vs a poke. |
| `adx_trend_min` | 22 | 16 → 30 (step 2) | Regime strictness — too low = chop breaks, too high = miss trends. |
| `di_spread_min` | 6 | 2 → 14 (step 2) | Directional conviction floor. |
| `ema_sep_atr` | 0.25 | 0.0 → 0.6 (step 0.05) | Trend-separation floor. |
| **`break_max_atr`** *(anti-chase, NEW-as-active)* | 9.0 (≈off) | 1.5 → 6.0 + ∞ | **Your Q2** — stop chasing breaks beyond X·ATR. |

### Bucket C — EXIT / RISK-SHAPE (sweep second, after entries are stable)
| Param | Pine default | Sweep range | Hypothesis |
|---|---|---|---|
| `sl_atr_brk` | 1.48 | 1.0 → 3.0 (step 0.1) | Stop room for the retest pullback. |
| `rr_brk` | 1.8 | 1.2 → 3.5 (step 0.1) | Runner target. |
| `tp1_close_pct` | 20 | 10 → 50 (step 5) | Win%/expectancy trade-off on the partial. |
| `tp1_r` | 0.8 | 0.5 → 1.2 (step 0.1) | Where the partial books. |
| `be_buf_atr` | 0.05 | 0.0 → 0.25 (step 0.05) | BE tightness after TP1. |

### Bucket D — NEW RISK-MANAGEMENT LAYERS (add **one at a time**, default OFF, A/B each — §6)
ATR-percentile entry gate (**your Q1**), chandelier runner trail + TP-extension exit (**your Q3**),
daily-DD breaker, consecutive-loss cooldown, peak-equity DD trail, volatility-RR scaling, news window.
Most already exist as dormant `Params` fields (`enable_vol_rr`, `atr_pctl_low/high`, `trail_runner`,
`trail_atr_mult`, `max_daily_dd_pct`, `loss_streak_*`, `max_peak_dd_pct`).

---

## 4. Your three questions → concrete experiments

**Q1 — "ideal ATR/price percentile to enter or block a trade."**
The Pine has `enableVolatilityRR` (atrPctl 40/78) but it only **scales RR**, never blocks entries.
We add a real **ATR-percentile entry gate**: compute `volPctile = percentrank(atr,100)`; block entries when
`volPctile < lowGate` (dead chop → false breaks) or `volPctile > highGate` (panic spikes → SL-fest).
Sweep `lowGate ∈ {0,10,20,30,40}`, `highGate ∈ {70,80,90,100}`. The "ideal band" is the plateau that
keeps PF up **without** gutting trade count. We also A/B the existing RR-scaling use of the same percentile.

**Q2 — "stopping chasing breakout trades after X ATR is a good idea?"**
Yes — almost certainly. The reference Pine has **no upper bound** on break distance, so it will buy a
breakout that has already run 4 ATR (terrible RR, you are the exit liquidity). We add/activate
`break_max_atr`: require `sC ≤ mVah + maxAtr·atr[1]`. Sweep `maxAtr ∈ {1.5, 2, 2.5, 3, 4, 6, ∞}`.
Expected shape: PF rises then trade count collapses — pick the plateau knee.

**Q3 — "how much to trail SL / when to exit because TP can't extend further."**
Two additive mechanisms after TP1 (today only BE exists):
- **Chandelier trail**: runner stop = `peak ∓ trailAtrMult·atr`, monotonic. Sweep `trailAtrMult ∈ {2.0…5.0}`.
- **TP-extension / stall exit**: if the runner has not made a new favorable extreme for `N` bars (TP "can't
  extend"), close it. Sweep `stallBars ∈ {3,5,8,12}`. A/B trail-only vs stall-only vs both vs neither.

---

## 5. Sweep methodology (the engine of the plan)

**Objective function** (per the chosen "Robust PF + plateau"):
```
score = PF_train                                  # maximize
  subject to:  trades_train ≥ 800 (XAU/2yr)       # statistical floor; reject thin configs
               PF_oos       ≥ 1.15                 # out-of-sample gate (deploy gate)
               PF_train     ≥ 1.25                 # train gate
               plateau_ok   = neighbors within ±1 grid step keep PF ≥ 0.95·PF_center
penalize:  maxDD, and PF_drop = PF_train − PF_oos  (overfit tax)
report also: PF_tail = PF after dropping top-N winners (tail-robustness, N=20)
```
We **prefer a broad plateau at PF 1.30 to a lone spike at PF 1.6** — a spike that craters one grid step
away is overfit and will not survive live.

**Data splits (XAUUSD, our feed, 2024-01 → 2026-05):**
- **Train (IS):** 2024-01 → 2025-06 (~18 mo).
- **OOS-1:** 2025-07 → 2026-05 (~11 mo) — overlaps the TV window for cross-check.
- **Walk-forward:** 6 rolling folds, 12-mo train / 3-mo test, step 3-mo (Phase-9 skill).
- **Cross-instrument robustness (later):** replay the locked set on BTCUSD M3 — must stay PF>1 (not re-tuned).

**Stages (each gated on the previous):**

| Stage | Tool | What | Output |
|---|---|---|---|
| **S0 Parity** | new `mastervp_parity` differ | reproduce TV 5,204-trade shape | PASS/FAIL report |
| **S1 Coarse grid** | C++ backtester + `sweep_*.py` | Bucket B only, full factorial (≈ a few k combos) | `sweep_mastervp_xau_B.csv` |
| **S2 Sensitivity** | pandas heatmaps | 2-D heatmaps per pair; find plateaus | `*.png` + plateau table |
| **S3 Entry-lock** | — | freeze Bucket B at plateau center | locked entry block |
| **S4 Exit grid** | sweep | Bucket C on the locked entries | `sweep_mastervp_xau_C.csv` |
| **S5 Optuna refine** | `optuna_mastervp_xau.py` | TPE over B∪C around the plateau, 300–800 trials | `optuna_mastervp_xau.csv` |
| **S6 Risk layers** | A/B harness | Bucket D, **one toggle at a time** (§6) | per-layer A/B table |
| **S7 Walk-forward** | Phase-9 skill | 6 folds on the final set | WF equity + PF/fold |
| **S8 Monte Carlo** | Phase-9 skill | trade-order & bootstrap resample | DD/PF confidence bands |
| **S9 Lock `.set`** | — | write `Presets/KK-MasterVP-XAU.set` | shipping config |
| **S10 EA port** | `/quant-10-promote-mt5` | C++→MQL5, byte-parity on shared feed | EA for your MT5 forward test |

**Anti-overfit discipline (non-negotiable, from CLAUDE.md):**
costs always modeled (commission + slippage + spread); IS/OOS never mixed; plateaus over peaks;
a layer is kept only if it improves **OOS** PF or **reduces maxDD without material PF loss** — never on IS alone.

---

## 6. Adding risk-management layers — the A/B protocol

For each Bucket-D layer, in this order (cheapest-risk-reduction first):

1. **Anti-chase `break_max_atr`** (Q2) — entry-shape, do in S1 actually (it's Bucket B-adjacent).
2. **ATR-percentile entry gate** (Q1).
3. **Chandelier trail + stall exit** (Q3).
4. **Daily-DD breaker** (`max_daily_dd_pct`) — predictive, blocks new entries only.
5. **Consecutive-loss cooldown** (`loss_streak_count` / `cooldown_hrs`).
6. **Peak-equity DD trail** (`max_peak_dd_pct`, soft-block lot mult).
7. **Volatility-RR scaling** (`enable_vol_rr`, session × ATR-pctile).
8. **News window** (only if a clean economic-calendar source is wired; else defer).

**Protocol per layer:** baseline (layer OFF) vs layer ON at default → if neutral/positive on OOS,
sweep that layer's own params for the plateau → keep only if OOS PF ↑ or maxDD ↓ ≥ ~10% at < ~5% PF cost.
Record every result (kept or rejected) in the run log so we never re-try a dead layer (the KenKem lesson:
several risk ports were *structurally inert* — we will detect that with an A/B = 0 and move on).

---

## 7. Compute & harness

- **Engine:** `cpp_core` headless tick backtester (deterministic; same ticks → same trades). One 2-yr XAU
  run is ~tens of seconds. Coarse grids run via a Python driver that shells the backtester per param vector
  and collects `trades_*.csv` → metrics. (`research/optimization/` already has the pattern:
  `sweep_pm_sl.py`, `optuna_*` outputs.)
- **Param plumbing:** every sweepable knob is already a field on `kk::Params` and settable via `.set`
  (`load_set`). The driver writes a `.set` per trial; no recompiles.
- **Metrics module (to build):** PF, expectancy(R), win%, trades, maxDD, PF_oos, PF_tail(drop-N), plateau check.
- **Parallelism:** grids are embarrassingly parallel — fan out across cores.

---

## 8. Deliverables

1. **This plan** (done) + `BUILD-PLAN` ticks.
2. Pine-faithful C++ engine aligned to `KK-MasterVP.pine` + **S0 parity report** vs the TV log.
3. Sweep CSVs + sensitivity heatmaps + plateau tables (S1–S5).
4. Per-layer risk A/B tables (S6).
5. Walk-forward + Monte-Carlo robustness (S7–S8).
6. Locked `Presets/KK-MasterVP-XAU.set` (S9).
7. **MQL5 EA** in `mql5/experts/` for your manual MT5 forward test (S10).

---

## 9. Open decisions (resolve as we go — current defaults in **bold**)

- Trade-count floor for "thin config" rejection: **800 / 2yr** (≈ TV's 5,204/1yr scaled down to our
  stricter `maxTradesPerSession`; revisit after S0 tells us our baseline count).
- Tail-robustness `N` for drop-top-N: **20** (TV note: ~20 trades carried the old variant's profit).
- Whether to also enable **reversion** (`enable_reversion`) as a parallel sweep track after breakout is
  locked: **defer** until breakout-only is solid (keeps the search space honest).
- News filter: **defer** unless a clean calendar feed is available for the engine.
