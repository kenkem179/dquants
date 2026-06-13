# Discovery — BTCUSD M3

- Rows: 424,729 · Features: 41
- Target: `tp_first` (TP-before-SL, 1×ATR/H60) and `fwd_ret_20`
- Heavy steps subsampled (MI / SHAP); see CSVs for full tables.

## Top drivers (by SHAP importance)

| # | feature | SHAP | dir | MI(tp) | Spearman(ret) | stability |
|--:|---|--:|:--:|--:|--:|:--:|
| 1 | `dist_val` | 0.0236 | ↑tp | 0.0000 | -0.0197 | stable- |
| 2 | `hour` | 0.0204 | ↑tp | 0.0003 | +0.0051 | stable+ |
| 3 | `dist_poc` | 0.0200 | ↓tp | 0.0020 | -0.0231 | stable- |
| 4 | `dist_vah` | 0.0187 | ↓tp | 0.0035 | -0.0267 | stable- |
| 5 | `atr` | 0.0178 | ↓tp | 0.0019 | +0.0117 | stable+ |
| 6 | `di_plus` | 0.0176 | ↑tp | 0.0026 | -0.0318 | stable- |
| 7 | `atr_pct` | 0.0164 | ↑tp | 0.0000 | +0.0104 | stable+ |
| 8 | `rsi_21` | 0.0162 | ↓tp | 0.0000 | -0.0384 | stable- |
| 9 | `di_spread` | 0.0157 | ↑tp | 0.0000 | -0.0332 | stable- |
| 10 | `dow` | 0.0154 | ↑tp | 0.0001 | -0.0010 | stable- |
| 11 | `dist_tenkan` | 0.0149 | ↓tp | 0.0000 | -0.0288 | stable- |
| 12 | `rsi_7_slope` | 0.0148 | ↓tp | 0.0001 | -0.0105 | stable- |
| 13 | `rsi_7` | 0.0148 | ↓tp | 0.0006 | -0.0313 | stable- |
| 14 | `rsi_14_slope` | 0.0147 | ↑tp | 0.0017 | -0.0124 | stable- |
| 15 | `ema_compression` | 0.0136 | ↓tp | 0.0000 | +0.0041 | stable+ |

**Direction** = sign of feature↔SHAP correlation (↑tp raises TP-first probability). **stability** = forward-return correlation sign consistent across 2024/2025/2026.

## Feature redundancy (|Spearman| ≥ 0.9) — keep 24, drop 17

Greedy reduction in SHAP-importance order: keep the more important feature, drop peers redundant with it. (Avoids the transitive-chaining artifact of single-linkage grouping; raw linkage groups are in the redundancy JSON.)

| drop | redundant with (kept) |
|---|---|
| `di_spread` | `di_plus` |
| `ema_75_slope` | `dist_cloud` |
| `ema_12_dist` | `dist_tenkan` |
| `dist_poc` | `dist_val` |
| `ema_100_dist`, `ema_100_slope`, `ema_200_slope` | `ema_200_dist` |
| `rsi_21_accel`, `rsi_7_accel` | `rsi_14_accel` |
| `ema_25_dist`, `ema_25_slope`, `ema_50_dist`, `ema_50_slope`, `ema_75_dist`, `rsi_14` | `rsi_21` |
| `rsi_14_slope`, `rsi_21_slope` | `rsi_7_slope` |

## Market regimes (KMeans, k=5)

| regime | bars | % | TP rate | mean fwd_ret_20 | ADX | ATR%ile | EMA compr |
|---|--:|--:|--:|--:|--:|--:|--:|
| Compression | 158,826 | 37.4% | 0.4910 | -0.000007 | 19.8 | 0.17 | 0.0026 |
| Reversal | 113,961 | 26.9% | 0.4968 | +0.000100 | 19.6 | 0.69 | 0.0051 |
| Weak Trend | 73,821 | 17.4% | 0.4958 | -0.000081 | 31.2 | 0.59 | 0.0046 |
| Strong Trend | 56,422 | 13.3% | 0.4921 | +0.000005 | 36.7 | 0.68 | 0.0095 |
| Expansion | 21,220 | 5.0% | 0.4872 | +0.000359 | 40.5 | 0.88 | 0.0173 |

Regime names are assigned heuristically from centroid stats (ADX / ATR percentile / EMA compression) — verify against the centroid columns above. Each regime should be researched separately in Phase 6+. Per-bar regime tags: `regimes_btcusd_M3.parquet`.
