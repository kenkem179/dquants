# VMC "in action" on KenKem E1 — findings (2026-06-20)

**Harness (non-invasive):** `cpp_core/tools/kenkem/vmc_e1_lab.cpp` (target `make kenkem_vmc`).
Runs the REAL `TickEngine` to get the baseline trade list, rebuilds committed per-bar VMC from the SAME
tick stream, and applies VMC as a **post-hoc directional veto** on a chosen entry kind (`--kind`, default
E1). Touches **zero** production engine/EA code. Three readouts: independence diagnostic, VMC score-scale
percentiles, and a **threshold-free** flow-direction discrimination split.

> Caveat (printed at runtime): post-hoc trade-SELECTION, not full re-sim — it ignores concurrency/margin
> coupling. The engine is ~single-position so coupling is small, but a *positive* result would still need
> an opt-in engine hook to confirm. The results below are *negative*, which a re-sim would not rescue.

## Verdict: VMC has NO usable confirmation edge on E1 (XAUUSD). Hypothesis falsified.

### 1. Score-scale bug caught first (methodology, not result)
Initial `--vmc-confirm 0.20` vetoed 100% of E1 trades — because `|vmc|` (the product `clamp(d/d_ref)·P·R`)
maxes at ~0.17–0.56 and sits at p50≈0.02. With `d_ref=0.5`, `|d|` (p99≈0.17) is crushed. Recalibrated to
`d_ref=0.10`, `confirm=0.01` (on-scale). A 100%-veto "improvement" is a confound: killing an unprofitable
entry flatters the book regardless of signal.

### 2. Magnitude-confirmation gate is robustly NEGATIVE (every window)
| window | E1 base trades | base PF / net | VMC-kept PF / net |
|---|---|---|---|
| 2024–2026 (full, n=126) | 126 | **1.170 / +813** | 0.879 / **−440** |
| 2024–2025 (n=21) | 21 | 1.148 / +100 | 0.656 / −123 |
| 2025 H1 (n=16) | 16 | 1.379 / +208 | 0.801 / −54 |
Confirming on flow *magnitude* removes **profitable** trades. The `d·P·R` product measures "strong-flow
bar," which is not "trade will win."

### 3. Flow-direction discrimination is sample-dependent noise (sign flips)
Threshold-free split, flow AGREES vs OPPOSES/flat the trade direction:
| window | AGREES (PF / net / n) | OPPOSES (PF / net / n) | edge? |
|---|---|---|---|
| 2024–2026 (full) | 1.067 / +255 / 96 | **1.580 / +558 / 30** | OPPOSES better |
| 2024–2025 | 1.363 / +150 / 16 | 0.803 / −51 / 5 | AGREES better |
| 2025 H1 | 1.669 / +220 / 12 | 0.945 / −12 / 4 | AGREES better |
The "divergence-veto" edge seen on small windows **reverses** on the 126-trade sample. No stable sign → noise.

### 4. Root cause (was visible from the independence diagnostic)
`corr(r_b, bar body)` = **0.48** (full) / 0.69 (2024–25) / sign-disagreement only ~10%. Tick-flow direction
is largely **redundant** with E1's own EMA-alignment momentum trigger: when E1 fires long, recent flow is
already up. Confirming it adds little independent predictive power. VMC is not "the truth ADX misses" *for a
momentum-alignment entry* — it mostly restates the entry condition.

## E5 — same structural verdict (the thesis-favored target also fails)
E5 (M1 4-EMA scalper, NO active momentum gate) needs the E5-only set (`MT5_E5_ONLY.set`) to fire; on
default config it makes 0 trades. With the set, 2026 window (54 E5 trades):
- magnitude-confirm gate **NEGATIVE** again: base PF 1.185 / +301 → kept-18 PF 0.996 / −2.6 (removes profitable trades).
- direction split weak: AGREES (35) PF 1.271 / +263 vs OPPOSES/flat (19) PF 1.058 / +38 — both profitable, small gap.
- same `corr(r_b, body)` 0.48 → same redundancy. The "no momentum gate" hope doesn't rescue it: E5 is still
  EMA-alignment, so flow is still redundant with the trigger. [full-history E5-set run pending → append]

## What this does NOT yet test
- **BTCUSD** — different microstructure (point grid, 24/7), may differ.
- VMC as a **regime/volatility gate** (its spread_z / tick_z legs) rather than a direction signal — untested
  and the most plausible surviving role.

## Recommendation
Do **not** wire VMC as an E1 confirmation/veto gate. If E5/E2/E4 also come back flat, VMC's remaining
plausible role is a **toxicity/regime suppressor** (spread_z, tick_z), not a directional confirm — re-scope
the spec accordingly. The C++/MQL5 modules stay (parity-ready, well-tested); only the *use* changes.
