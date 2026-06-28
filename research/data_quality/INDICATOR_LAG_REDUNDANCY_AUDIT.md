# R2 — Indicator Lag & Redundancy Audit (EMA / RSI / DMI / ADX)

**BUILD-PLAN Phase 1 · R2.** Operating Doctrine #8: *"Lagging indicators are state
variables, not alpha by themselves."* This audit puts numbers on that claim.

- **Symbol / TF:** XAUUSD M1 (the live-edge surface for KenKem).
- **Data source actually used:** `data/features/features_xauusd_M1.parquet`
  (**849,963 bars, 2024-01-01 → 2026-05-29**) + `data/labels/labels_xauusd_M1.parquet`.
  These XAU feature/label Parquets **did not exist at the start of this task** — only
  BTC features were built. They were generated here from the existing XAU processed
  ticks via the standard one-directional pipeline (`validate_data → build_bars →
  features → labels`, `--symbol xauusd --tf M1`); no upstream artefact was edited in
  place. 162M XAU ticks → 850k M1 bars → 41 features → triple-barrier labels.
- **Reusable code:** `research/data_quality/indicator_lag_redundancy.py`
  (py_compile-clean). Per-feature CSV/JSON artefacts: `r2_lag_*`, `r2_corr_matrix_*`,
  `r2_halflife_*`, `r2_partial_ic_*`, `r2_ic_stability_*`, `r2_summary_*`.
- **Reproduce:** `conda run -n kenkem python research/data_quality/indicator_lag_redundancy.py --symbol xauusd --tf M1 --horizon 5`

**Forward target:** ATR-normalised forward return (`fwd_5`, cross-checked at `fwd_20`).
**Base "already-known" structure** the indicators must beat (incremental test):
`ret_1, ret_5, atr, atr_pct, atr_slope, dist_poc, dist_vah, dist_val` — i.e.
price momentum + volatility + Volume-Profile structure. **No EMA/RSI/DMI/ADX is in the
base**, by construction.

---

## TL;DR verdicts

| Family | Lag vs price | Worst redundancy | Incremental value after price/vol/VP | **Verdict** |
|---|---|---|---|---|
| **EMA** (dist) | coincident (lag 0, embeds price) | slope ≈ dist (0.99); adjacent periods 0.93–0.94 | partial-IC stable (\|t\|≈6) but **nested OOS R² negative** | **KEEP-AS-STATE-FILTER** (1 period); **REDUNDANT-DROP** slopes + extra periods |
| **RSI** (level) | coincident (lag 0, \|r\|≈0.96) | rsi_7/14/21 mutually 0.93–0.98; **rsi_14 ≈ di_spread 0.935** | partial-IC stable (\|t\|≈8) but **OOS R² negative** | **KEEP-AS-STATE-FILTER** (1 period); **REDUNDANT-DROP** other periods + slopes/accels |
| **DMI** (di_spread) | coincident (lag 0, \|r\|≈0.76) | di_spread ≡ di_plus−di_minus (\|r\|≈0.93); ≈ rsi (0.935) | partial-IC stable (\|t\|≈4) | **KEEP di_spread AS-STATE-FILTER**; **REDUNDANT-DROP** di_plus & di_minus as separate inputs |
| **ADX** (level) | **non-directional** (corr≈0 with signed impulse) | only 0.59 vs \|di_spread\| → **NOT redundant** (orthogonal) | partial-IC ≈ 0, sign flips fold-to-fold (t=−0.18, agree 0.50) | **NO-INCREMENTAL-VALUE** for direction → **KEEP-AS-STATE-FILTER (regime gate) ONLY** |

`adx_slope` is the one ADX-derived feature with a *small, fold-stable* incremental signal
at h=5 (t=3.9) — but it fades at h=20 (t=1.3). `ema_compression`, `rsi_14_accel`,
`adx_accel` all show **no stable incremental value**.

**Decision-rule application:** for *every* family the nested walk-forward OOS R² increment
is **≤ 0** (EMA −6e-5, RSI −8e-5, ADX −5e-5, DMI +4e-5, ALL −2.3e-4 at h=5; same sign at
h=20). No EMA/RSI/DMI/ADX feature earns the right to be the **sole** reason for an entry,
SL or target. They survive only as **regime/state filters**, exactly as Doctrine #8 asserts.

---

## 1. Lag table — signal delay vs an ATR-normalised price impulse

`peak_lag_bars` = the lag *k* (in M1 bars) at which Δ(indicator) best correlates with the
impulse; **k>0 ⇒ the indicator lags price by k bars.** `contemp_corr` = correlation at k=0.

| indicator | family | peak_lag (bars) | peak_corr | contemp_corr | read |
|---|---|---:|---:|---:|---|
| ema_12_dist | EMA | 0 | 0.761 | 0.761 | coincident (contains current price) |
| ema_50_dist | EMA | 0 | 0.783 | 0.783 | coincident |
| ema_200_dist | EMA | 0 | 0.788 | 0.788 | coincident |
| ema_50_slope | EMA | 0 | 0.456 | 0.456 | coincident, weaker |
| ema_compression | EMA | 0 | −0.011 | −0.011 | ~uncorrelated w/ impulse (slow regime) |
| rsi_7 | RSI | 0 | 0.923 | 0.923 | coincident — RSI ≈ bounded momentum |
| rsi_14 | RSI | 0 | 0.962 | 0.962 | coincident |
| rsi_21 | RSI | 0 | 0.973 | 0.973 | coincident |
| rsi_14_slope | RSI | **3** | −0.712 | 0.669 | **lags 3 bars** |
| rsi_14_accel | RSI | **3** | −0.796 | 0.386 | **lags 3 bars** |
| di_plus | DMI | 0 | 0.669 | 0.669 | coincident, directional |
| di_minus | DMI | 0 | −0.671 | −0.671 | coincident, directional |
| di_spread | DMI | 0 | 0.760 | 0.760 | coincident, directional |
| adx | ADX | 1 | **−0.013** | −0.006 | **no directional content** |
| adx_slope | ADX | 1 | −0.018 | −0.010 | no directional content |
| adx_accel | ADX | 4 | 0.018 | −0.008 | no directional content |

**Findings.** EMA-distance, RSI-level and DI features are **coincident** (lag 0) — but
that is because each is a *transform of the current price* (distance-to-EMA, bounded
momentum, directional index), not because they *lead*. The genuinely *derived* features
(RSI slope/accel) **lag by 3 bars**. **ADX carries essentially zero correlation with the
signed price impulse** (|corr| ≈ 0.01) — it is an unsigned trend-*strength* magnitude, a
state variable by design, not a directional signal.

---

## 2. Redundancy matrix — near-duplicate pairs (|Pearson| ≥ 0.90)

| pair | \|r\| | note |
|---|---:|---|
| ema_200_dist ~ ema_200_slope | **0.994** | slope is a near-perfect duplicate of distance |
| rsi_14 ~ rsi_21 | 0.978 | RSI periods redundant |
| ema_50_dist ~ ema_50_slope | 0.978 | slope ≈ distance |
| rsi_7_slope ~ rsi_14_slope | 0.975 | RSI-slope periods redundant |
| ema_25_dist ~ ema_50_dist | 0.943 | adjacent EMA periods |
| ema_12_dist ~ ema_25_dist | 0.936 | adjacent EMA periods |
| **rsi_14 ~ di_spread** | **0.935** | **cross-family near-duplicate** |
| rsi_7 ~ rsi_14 | 0.935 | RSI periods |
| rsi_21 ~ di_spread | 0.935 | cross-family |
| di_minus ~ di_spread | 0.928 | di_spread ≡ di_plus−di_minus |
| di_plus ~ di_spread | 0.927 | di_spread ≡ di_plus−di_minus |
| ema_12_dist ~ ema_12_slope | 0.914 | slope ≈ distance |

Named hypothesis checks:

| test | corr | conclusion |
|---|---:|---|
| ADX vs \|di_spread\| | 0.593 | **partial** overlap — ADX is *not* just \|DI-spread\| |
| ADX vs signed di_spread | 0.001 | orthogonal (ADX is unsigned) |
| rsi_14 vs ema_12_dist | 0.713 | moderate overlap |
| rsi_7 vs rsi_14 | 0.935 | redundant |
| ema_50_dist vs dist_kijun (Ichimoku) | 0.872 | cross-family overlap |

**Biggest redundancy:** *within-family*, `ema_200_dist ≈ ema_200_slope` (**0.994**) — the
EMA **slope adds almost nothing over the distance**; this repeats for every EMA period and
is the single largest source of duplicated columns. *Cross-family*, the surprising one is
**`rsi_14 ≈ di_spread` (0.935)** — RSI and the DI-spread are measuring nearly the same
thing on XAU M1. ADX, by contrast, is **only 0.59** vs |DI-spread| and ~0 vs signed
DI-spread, so ADX is genuinely **orthogonal** state information (it just isn't directional).

---

## 3. Predictive-information half-life (IC/MI vs forward return)

`halflife_bars` = number of bars of lag until the feature's |Spearman IC| with `fwd_5`
decays to half its lag-0 value (linear-interpolated; `>40` = never halves in-window).
`ic0` is small everywhere (~0.01–0.02) — normal for M1 single-feature IC.

| indicator | ic0 | ic_lag5 | ic_lag20 | half-life (bars) |
|---|---:|---:|---:|---:|
| ema_12_dist | 0.0224 | 0.0150 | 0.0036 | 7.2 |
| ema_50_dist | 0.0216 | 0.0152 | 0.0063 | 8.4 |
| ema_200_dist | 0.0157 | 0.0112 | 0.0058 | 11.6 |
| ema_compression | 0.0094 | 0.0082 | 0.0078 | 41.0 (slow regime) |
| rsi_7 | 0.0207 | 0.0131 | 0.0028 | 7.1 |
| rsi_14 | 0.0212 | 0.0143 | 0.0043 | 8.0 |
| rsi_21 | 0.0206 | 0.0145 | 0.0055 | 8.8 |
| rsi_14_slope | 0.0102 | 0.0048 | 0.0005 | **1.6 (very short-lived)** |
| rsi_14_accel | 0.0040 | 0.0012 | 0.0009 | **0.7** |
| di_plus | 0.0183 | 0.0133 | 0.0056 | 9.5 |
| di_spread | 0.0193 | 0.0139 | 0.0058 | 9.5 |
| adx | 0.0038 | 0.0004 | 0.0011 | 2.0 (tiny IC, decays fast) |
| adx_slope | 0.0085 | 0.0041 | 0.0035 | 4.8 |

**Finding.** Directional level features (EMA-dist, RSI-level, DI) hold their (small)
predictive content for **~7–12 bars**; the *derived* RSI slope/accel are essentially spent
in **1–2 bars**; `ema_compression` is a genuinely **slow** regime variable (>40 bars). ADX
level has almost no IC to begin with.

---

## 4. Incremental value after price / volatility / VP is known

### 4a. Conditional (partial) IC, per-fold

corr( residual(feature | base), residual(fwd_5 | base) ), computed **within each of 6 time
folds**. `sign_agreement` = fraction of folds matching the mean sign; `t_stat` = mean / SE
across folds.

| indicator | mean partial-IC | sign-agree | t-stat | read |
|---|---:|---:|---:|---|
| ema_12_dist | −0.0135 | 1.00 | −7.0 | stable, small |
| ema_50_dist | −0.0133 | 1.00 | −6.6 | stable, small |
| ema_200_dist | −0.0106 | 1.00 | −5.7 | stable, small |
| ema_50_slope | −0.0130 | 1.00 | −6.6 | stable (but ≈ dist) |
| ema_compression | +0.0004 | 0.50 | **+0.15** | **no value** |
| rsi_7 | −0.0098 | 1.00 | −7.3 | stable, small |
| rsi_14 | −0.0112 | 1.00 | −8.5 | stable, small |
| rsi_21 | −0.0116 | 1.00 | −7.7 | stable, small |
| rsi_7_slope | +0.0022 | 0.67 | +2.1 | weak/unstable |
| rsi_14_accel | −0.0009 | 0.67 | **−1.0** | **no value** |
| di_plus | −0.0089 | 0.83 | −3.5 | mostly stable |
| di_minus | +0.0093 | 1.00 | +4.4 | stable, small |
| di_spread | −0.0101 | 1.00 | −4.1 | stable, small |
| adx | −0.0006 | 0.50 | **−0.18** | **no value, sign flips** |
| adx_slope | +0.0071 | 1.00 | +3.9 | small but stable (h=5 only) |
| adx_accel | +0.0024 | 0.67 | +1.3 | weak/unstable |

EMA-dist, RSI-level and DI keep a **statistically robust but economically tiny** (~0.01 IC)
conditional signal after price/vol/VP. **ADX level, ema_compression, rsi_14_accel show no
stable incremental value** (|t|<1, sign flips across folds).

### 4b. Nested walk-forward ridge — incremental OOS R²

Expanding-window ridge predicting `fwd_5`; base-only vs base+family vs base+ALL.

| model | OOS R² (h=5) | incremental | OOS R² (h=20) | incremental |
|---|---:|---:|---:|---:|
| base (price/vol/VP) | −0.000116 | — | −0.000830 | — |
| base + EMA | −0.000176 | **−6e-5** | −0.001055 | **−2.2e-4** |
| base + RSI | −0.000197 | **−8e-5** | −0.000980 | **−1.5e-4** |
| base + DMI | −0.000072 | +4e-5 | −0.000800 | +3e-5 |
| base + ADX | −0.000163 | **−5e-5** | −0.000945 | **−1.2e-4** |
| base + ALL | −0.000347 | **−2.3e-4** | −0.001477 | **−6.5e-4** |

**Finding (the load-bearing one).** Base OOS R² is already ~0 (price/vol/VP barely predict
M1 forward return linearly). **Adding any indicator family does not improve OOS R² — it is
flat-to-negative at both horizons.** The only positive increment (DMI, +4e-5) is negligible
and within noise. So although the *univariate/partial* IC is "significant" (large N → small
SE), there is **no exploitable joint OOS predictive lift** from EMA/RSI/DMI/ADX as
return-predictors. This is precisely Doctrine #8: they are **state descriptors, not alpha.**

---

## 5. Univariate IC stability across folds

EMA-dist, RSI-level and DI features have **sign_agreement = 1.00** (consistent IC sign
across all 6 folds) with mean |IC| ~0.013–0.022 and std ~0.007–0.009 — *directionally
stable but tiny.* **`adx` is the least stable (sign_agreement 0.667)**; `ema_compression`,
`rsi_14_accel`, `adx_accel` are at 0.833. Full table in `r2_ic_stability_xauusd_M1.csv`.

---

## Per-indicator verdicts (with numbers)

- **EMA distance (keep one period, e.g. `ema_50_dist` or `ema_200_dist`):**
  **KEEP-AS-STATE-FILTER.** Coincident (lag 0), stable conditional IC (t≈−6, agree 1.0),
  half-life 8–12 bars. But OOS R² increment ≤ 0 → **not** a standalone entry/SL/target
  driver. **EMA *slopes* and the redundant adjacent periods → REDUNDANT-DROP** (slope≈dist
  up to r=0.99; adjacent periods r=0.93–0.94).
- **RSI level (keep one period):** **KEEP-AS-STATE-FILTER** (overbought/oversold regime).
  Coincident, stable conditional IC (t≈−8). **Other RSI periods + RSI slope/accel →
  REDUNDANT-DROP / NO-VALUE** (periods r≥0.93; slope/accel half-life ≤2 bars, |t|≤2,
  unstable). Note **rsi_14 ≈ di_spread (0.935)** — do not treat RSI and DI-spread as
  independent confirmations.
- **DMI — `di_spread`:** **KEEP-AS-STATE-FILTER** (directional regime). Coincident, stable
  conditional IC (t≈−4). **`di_plus` & `di_minus` as separate inputs → REDUNDANT-DROP**
  (di_spread ≡ di_plus−di_minus, |r|≈0.93). Not standalone alpha (OOS R² flat).
- **ADX level (`adx`):** **NO-INCREMENTAL-VALUE for direction** — corr≈0 with signed
  impulse, partial-IC t=−0.18, sign flips fold-to-fold (agree 0.50), OOS R² increment −5e-5.
  It is **orthogonal** (only 0.59 vs |DI-spread|), so it is **legitimately KEPT-AS-A-REGIME
  GATE ONLY** (trend-strength / compression state). It must **never** set entry direction,
  SL or target.
- **`adx_slope`:** marginal **KEEP-AS-STATE-FILTER** — small but fold-stable incremental
  signal at h=5 (t=3.9, agree 1.0), fades at h=20 (t=1.3). Use only as a state input.
- **`ema_compression`, `rsi_14_accel`, `adx_accel`:** **NO-INCREMENTAL-VALUE** (|t|<1.5,
  sign agreement ≤0.83); `ema_compression` is at most a slow background regime tag.

**Net:** the feature stack can be compressed substantially — keep **one** EMA-distance,
**one** RSI period, **`di_spread`**, **`adx`** (gate only) and maybe **`adx_slope`**; the
remaining EMA slopes, extra RSI/EMA periods, RSI accel and `di_plus`/`di_minus` are
redundant or value-less. Every one of these is a **state variable**: none provides positive
OOS return-prediction on its own, so none may be the sole basis for an entry, stop, or
target — consistent with Operating Doctrine #8. They earn their place only where a
downstream test shows they improve OOS robustness or conditional MFE/MAE (next step:
re-run the conditional MFE/MAE check on the live KenKem trade stream, which carries
`mfe_r`/`mae_r`).
