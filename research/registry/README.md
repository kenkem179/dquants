# research/registry — Experiment registry & immutable result ledger (BUILD-PLAN R3)

**Every sweep, backtest, and MT5 run writes one row here.** This is non-optional: it is how
Operating Doctrine #3 ("Search must pay rent") and the mutual-skepticism trust contract are
*enforced* rather than just stated. A result with no registry row is an assertion, not evidence.

```
research/registry/
├── SCHEMA.md            # field definitions + value conventions (read this first)
├── registry.py          # the API + CLI (make_record / append_row / rebuild_index)
├── backfill_initial.py  # one-shot back-fill of experiments already on record (idempotent)
├── experiments/         # one <experiment_id>.yaml per experiment (the immutable rows)
└── index.csv            # GENERATED rollup — never hand-edit; `registry.py rebuild` regenerates it
```

## How to write a row after any sweep / backtest / MT5 run

Add it programmatically so the id, gate field names, and index stay consistent:

```python
import sys; sys.path.insert(0, "research/registry")
from registry import make_record, append_row, sha256_file

rid = append_row(make_record(
    strategy="mastervp", symbol="XAUUSD", timeframe="M5",
    decision="LOCK", label="my-new-lock",          # id = strategy-symbol-tf-decision-label
    date="2026-07-01", hypothesis_id="M5/Mx",
    train_start="2025-06", train_end="2026-05", oos_start="2026-01", oos_end="2026-05",
    commit_hash="<git rev-parse --short HEAD>",
    data_source="XAU M5 ticks 2025.06-2026.05",
    data_sha256=sha256_file("data/processed/<file>.parquet"),   # real hash going forward
    set_path="mql5/experts/Presets/KK-MasterVP/KK-MasterVP-XAUUSD-M5.set",
    set_sha256=sha256_file("mql5/experts/Presets/KK-MasterVP/KK-MasterVP-XAUUSD-M5.set"),
    cost_model="MT5 every-tick, real spread + commission/swap",
    n_trials=36, sr_trial_std=0.0135,              # straight from sweep_context.report_sweep_context
    net_usd=86034, pf=1.4246, max_dd_pct=None, sharpe=0.109, n_trades=1423,
    psr=1.000, dsr=1.000, mintrl=192, mintrl_sufficient=True, gate_verdict="PASS",
    mt5_confirmed=True,
    artifacts=["research/mastervp_parity/H9_results/"],
    notes="one honest paragraph: caveats, what's fictional, why locked",
    source_refs=["memory:mastervp-progtrail-ladder-lock"],
))
```

`append_row` validates against `SCHEMA.md`, writes `experiments/<rid>.yaml`, and rebuilds
`index.csv`. The id is **content-derived** → re-running the same logical experiment overwrites the
same file (idempotent), never a duplicate.

### Where the gate numbers come from
`n_trials` / `sr_trial_std` are exactly the two values `research/stats/sweep_context.py`
(`report_sweep_context`) prints after an Optuna study. `psr` / `dsr` / `mintrl` / `verdict` are
exactly what `research/stats/gate.py` reports on the locked trade stream. Copy them straight across
— the registry field names match the gate's on purpose.

## CLI

```bash
conda run -n kenkem python research/registry/registry.py rebuild    # regenerate index.csv
conda run -n kenkem python research/registry/registry.py validate    # schema-check every row
conda run -n kenkem python research/registry/registry.py list         # one-line summary per row
conda run -n kenkem python research/registry/backfill_initial.py      # re-create the back-filled rows
```

## Rules

1. **`null` = unknown, never zero.** Don't fabricate a metric to fill a cell. Leave it `null` and,
   if you later learn it, append the row again (idempotent overwrite).
2. **`decision` ∈ {LOCK, REJECT, RESEARCH-ONLY, STOP}.** A `LOCK` should carry a gate verdict and,
   for production, `mt5_confirmed: true`.
3. **Never hand-edit `index.csv`.** It is generated; edit the yaml and rebuild.
4. **Cite provenance** in `source_refs` so any number can be traced back to its source-of-record.
5. The registry **reads** `.set` paths for reference/hashing but **never writes** `.set`/`.mq5`/`.mqh`
   or anything under `mql5/`.

## Current contents
15 experiments back-filled from the record (5 LOCK, 4 REJECT, 4 STOP, 2 RESEARCH-ONLY) spanning
KenKem XAU M1, MasterVP XAU M5, MasterVP/Monster BTC M3/M5. See `index.csv` for the rollup.
