---
name: discovery-findings
description: "Phase 5 discovery results for BTCUSD M1/M3 — what drives (and doesn't drive) the triple-barrier outcome"
metadata: 
  node_type: memory
  type: project
  originSessionId: 93eabcdd-ed73-4c3a-8a0a-c1d68af64676
---

Phase 5 (`/quant-discovery`, code in `research/discovery/discover.py`) on BTCUSD M1 (1.27M rows) and
M3 (425k rows). Target: `tp_first` (TP-before-SL, 1×ATR / H60) and `fwd_ret_20`.

**Headline (honest negative result):** there is **no strong standalone single-feature edge** for the
symmetric 1×ATR barrier. SHAP importances are tiny (top ≈0.02), mutual information near-zero (≤0.004),
and every KMeans regime's TP rate sits within 0.008–0.010 of the 0.496 base rate. This is the
guardrail finding — don't curve-fit a lone indicator.

**But the SHAP ranking is consistent and confirms the playbook thesis "Volume Profile > RSI":**
- **Volume-profile distances dominate**, especially on M3 (dist_val #1, dist_poc #3, dist_vah #4).
  On M1 they're top-6. These outrank RSI/EMA distances.
- **Time-of-day (`hour`) is consistently important and sign-stable** across years (M1 #7, M3 #2).
- **Directional (`di_plus`/`di_minus`/`di_spread`) matter** more than RSI.
- Strongest *linear* signal is mild mean-reversion: `ema_200_dist`, `dist_kijun`, `rsi_21` all
  Spearman ≈ −0.03 to −0.036 vs fwd_ret_20, stable across 2024/25/26.
- **Strong Trend** regime has the only positive mean fwd_ret_20 (faint upward drift) but symmetric
  barriers hide it.

**Redundancy:** of 41 features, 17 are ≥0.9-redundant → 24 effective (see `redundancy_*.json`:
adjacent EMAs collapse; rsi_14/21→rsi_7; dist_poc→dist_val).

**Implications for Phase 6 (`/quant-hypothesis`):** symmetric barriers wash out the faint directional
edge — try **asymmetric/directional targets**; build hypotheses around **prior-day VP levels + session/
hour + directional (DI) regime**, conditioned on **Strong Trend / Expansion** regimes; drop the 17
redundant features. Per-bar regime tags in `research/discovery/regimes_btcusd_<tf>.parquet`. See
[[pipeline-phase3-conventions]], [[btcusd-data-quirks]], [[project-kenkem-quant-os]].
