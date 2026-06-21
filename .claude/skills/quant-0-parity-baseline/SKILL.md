---
name: quant-0-parity-baseline
description: Phase 0 of the KenKem Quant OS SOP — prove the C++ engine reproduces the MT5 reference to tolerance BEFORE trusting any engine number (autopsy, backtest, sweep). The first gate. If no reference EA/run exists, the gate is N/A (auto-skip, results flagged UNVALIDATED) — never a hard block.
---

# Phase 0 — Parity Baseline (the FIRST gate: validate the engine, then trust it)

The failure this prevents: the C++ engine promotes a config that runs like shit in MT5, because its
indicators/feed/fills silently diverge (historical: ATR was SMA-not-Wilder ~6% off → 29% wrong pctile
category; MTF-EMA off-by-one; E4 exits *fictional*; BTC reversion feed-optimism, engine revNet +5,414
vs MT5 −76, 57% trade match). Any autopsy/sweep run on an unvalidated engine optimises fiction.

## The rule (three parts)
1. **Parity is a property of the ENGINE's shared machinery** (ATR/EMA/ADX/RSI, VP build, bar
   construction, fill model, feed) — proven ONCE on a reference config, it transfers to every config
   built from those same primitives. So: validate a baseline **before** Phase 6b/7/8, not after.
2. **Sweep only INSIDE the validated envelope.** A swept toggle that activates a code path or regime
   whose primitives were never parity-checked **re-opens parity** — flag it, don't trust it.
3. **Re-parity the CANDIDATE before lock** (Phase ~7/§8) with a full trade-level diff.

## Critical: indicator-parity ≠ execution-parity
Matching ATR/EMA *values* does NOT catch intrabar adverse-path or feed round-trip divergences (the E4
fictional exits, the BTC reversion optimism). Those surface ONLY in **trade-level P&L parity on the
actual config**. A values check is necessary, not sufficient.

## How
```bash
# engine over the SAME window + .set as a real MT5 tester run, then diff:
./cpp_core/build/backtester --bars <b.csv> --ticks <t.csv> --set-all <ref.set> --symbol-xau --out cpp.csv
python research/validation/parity_diff.py --engine cpp.csv --mt5 <mt5_ref_trades.csv> \
    --bar-seconds <180|300> --label "<strategy> <sym> <tf>"      # prints VERDICT: PASS/FAIL
```
MT5 references live under `research/**/mt5_runs/`. Diff existing cpp/mt5 CSV pairs directly when present.

## The no-reference rule (per user)
**If no reference EA or MT5 tester run exists for a config, the gate is N/A — skipped by DEFAULT, never
a hard block.** Print a loud `UNVALIDATED` banner, record `PARITY=N/A`, and proceed; the config's
engine numbers are provisional until its own MT5 run exists. New-from-scratch strategies legitimately
start here.

## Acceptance
- A reference exists → engine reproduces it to tolerance (`VERDICT: PASS`): structural (counts/lag),
  trade-level P&L Δ within tol, exit-tags agree. THEN Phase 6b/7/8 may run.
- No reference → `PARITY=N/A`, results explicitly flagged UNVALIDATED.

Tooling: `research/validation/parity_diff.py`, `research/mastervp_parity/PARITY_WORKFLOW.md`,
`research/mastervp_parity/MasterVP_End_to_End.ipynb` (§0). Next: `/quant-6b-edge-autopsy`.
See `docs/KENKEM_QUANT_OS.md` §7.
