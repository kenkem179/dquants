---
name: quant-5-discovery
description: Phase 5 of the KenKem Quant OS SOP — statistical discovery (correlation, mutual information, SHAP, regime clustering) to find which features actually drive forward returns. Use after features+labels exist.
---

# Phase 5 — Discovery Engine

Find what actually drives profit. Output ranked drivers + market regimes, not a model to deploy.

## Input
`data/features/features.parquet` + `data/labels/labels.parquet`.

## Output
Reports in `research/discovery/`:
- Correlation & **Mutual Information** of each feature vs forward returns.
- **SHAP** importance from a LightGBM model trained to predict forward return / `hit_tp_before_sl`.
- Regime clusters (HDBSCAN / KMeans): Strong Trend, Weak Trend, Compression, Expansion, Reversal.
- Feature-redundancy map (which features are duplicative).

## How
- Train LightGBM for explainability only — **do not** chase deep learning; favor interpretable signals.
- Run SHAP; surface the true drivers (often Volume Profile > RSI).
- Cluster market conditions; tag each bar with a regime for per-regime analysis.
- Note redundant/correlated features to drop.

Put logic in `research/discovery/`. Run in `kenkem`.

## Acceptance
- Top drivers ranked with effect direction and stability across years.
- Regimes labeled and counted; each studied separately downstream.
- Redundancy explicitly flagged.

Next: `/quant-6-hypothesis`. See `docs/KENKEM_QUANT_OS.md` §7 (Phase 5).
