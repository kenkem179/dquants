# Discovery — BTCUSD M1

- Rows: 1,273,622 · Features: 41
- Target: `tp_first` (TP-before-SL, 1×ATR/H60) and `fwd_ret_20`
- Heavy steps subsampled (MI / SHAP); see CSVs for full tables.

## Top drivers (by SHAP importance)

| # | feature | SHAP | dir | MI(tp) | Spearman(ret) | stability |
|--:|---|--:|:--:|--:|--:|:--:|
| 1 | `di_minus` | 0.0202 | ↓tp | 0.0003 | +0.0282 | stable+ |
| 2 | `di_plus` | 0.0199 | ↑tp | 0.0000 | -0.0252 | stable- |
| 3 | `rsi_7` | 0.0181 | ↓tp | 0.0000 | -0.0307 | stable- |
| 4 | `di_spread` | 0.0173 | ↑tp | 0.0006 | -0.0295 | stable- |
| 5 | `dist_val` | 0.0163 | ↑tp | 0.0014 | -0.0117 | stable- |
| 6 | `dist_vah` | 0.0157 | ↓tp | 0.0000 | -0.0157 | stable- |
| 7 | `hour` | 0.0150 | ↑tp | 0.0001 | +0.0048 | stable+ |
| 8 | `dist_kijun` | 0.0144 | ↓tp | 0.0000 | -0.0304 | stable- |
| 9 | `ema_200_dist` | 0.0122 | ↓tp | 0.0003 | -0.0362 | stable- |
| 10 | `atr` | 0.0119 | ↓tp | 0.0000 | +0.0077 | stable+ |
| 11 | `dow` | 0.0106 | ↑tp | 0.0000 | -0.0020 | stable- |
| 12 | `rsi_21` | 0.0104 | ↓tp | 0.0006 | -0.0359 | stable- |
| 13 | `dist_tenkan` | 0.0096 | ↓tp | 0.0000 | -0.0264 | stable- |
| 14 | `rsi_21_accel` | 0.0078 | ↓tp | 0.0000 | -0.0051 | stable- |
| 15 | `atr_pct` | 0.0077 | ↑tp | 0.0000 | +0.0078 | stable+ |

**Direction** = sign of feature↔SHAP correlation (↑tp raises TP-first probability). **stability** = forward-return correlation sign consistent across 2024/2025/2026.

## Feature redundancy (|Spearman| ≥ 0.9) — keep 24, drop 17

Greedy reduction in SHAP-importance order: keep the more important feature, drop peers redundant with it. (Avoids the transitive-chaining artifact of single-linkage grouping; raw linkage groups are in the redundancy JSON.)

| drop | redundant with (kept) |
|---|---|
| `rsi_21` | `di_spread` |
| `ema_50_dist`, `ema_50_slope`, `ema_75_dist`, `ema_75_slope` | `dist_cloud` |
| `ema_25_dist`, `ema_25_slope` | `dist_kijun` |
| `dist_poc` | `dist_val` |
| `ema_100_dist`, `ema_100_slope`, `ema_200_slope` | `ema_200_dist` |
| `rsi_14_accel`, `rsi_7_accel` | `rsi_21_accel` |
| `ema_12_dist`, `rsi_14` | `rsi_7` |
| `rsi_14_slope`, `rsi_21_slope` | `rsi_7_slope` |

## Market regimes (KMeans, k=5)

| regime | bars | % | TP rate | mean fwd_ret_20 | ADX | ATR%ile | EMA compr |
|---|--:|--:|--:|--:|--:|--:|--:|
| Weak Trend | 382,894 | 30.1% | 0.4929 | +0.000013 | 21.5 | 0.27 | 0.0015 |
| Reversal | 348,831 | 27.4% | 0.4963 | +0.000001 | 20.7 | 0.75 | 0.0032 |
| Compression | 298,129 | 23.4% | 0.5000 | +0.000008 | 23.6 | 0.24 | 0.0016 |
| Expansion | 140,929 | 11.1% | 0.4978 | -0.000004 | 36.9 | 0.79 | 0.0065 |
| Strong Trend | 101,400 | 8.0% | 0.4920 | +0.000048 | 39.2 | 0.77 | 0.0070 |

Regime names are assigned heuristically from centroid stats (ADX / ATR percentile / EMA compression) — verify against the centroid columns above. Each regime should be researched separately in Phase 6+. Per-bar regime tags: `regimes_btcusd_M1.parquet`.
