---
name: quant-2-validate-data
description: Phase 2 of the KenKem Quant OS SOP — validate and clean imported tick Parquet (dedup, impossible prices, negative spread, gaps). Use after import, before building bars/features.
---

# Phase 2 — Validate Data

Bad ticks are the #1 source of fake edges. Validate and clean before anything downstream.

## Input
`data/processed/ticks_<year>.parquet` (from `/quant-1-import-data`).

## Output
- Cleaned `data/processed/ticks_<year>.parquet` (or a `*_clean.parquet` variant).
- A validation report in `reports/` (Markdown/HTML) summarizing what was removed and why.

## Checks & cleaning
- Drop duplicate timestamps.
- Drop impossible prices (≤0, absurd jumps), **negative spread**, maintenance spikes.
- Report spread distribution (mean/median/p95/max), missing periods/gaps, session coverage per day.
- Flag (do not silently delete) suspicious clusters — log counts.

Put logic in `pipeline/validate_data.py`. Run in the `kenkem` env.

## Acceptance
- No duplicate timestamps, no negative spreads, no obviously impossible prices remain.
- Session coverage looks complete (24/5 for BTC; respect XAUUSD sessions when added).
- Report committed; cleaning is reproducible (deterministic, no manual edits).

Next: `/quant-3-build-features`.
