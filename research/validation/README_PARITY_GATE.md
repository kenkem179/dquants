# Parity gate — `parity_diff.py` (PIPELINE-CONTRACT §4)

The trade-level engine-vs-MT5 check that makes "validated" mean *MT5 reproduces it*,
not *the C++ engine likes it*. A config may not advance to DEPLOY until it PASSes here.

## Run it

```bash
python3 research/validation/parity_diff.py \
  --engine <tick-engine trades_*.csv> \
  --mt5    <MT5 trades_mt5.csv> \
  --bar-seconds 180          # M1=60, M3=180
  [--from 'YYYY.MM.DD HH:MM' --to ...]   # default: MT5 entry-time span
  [--tol-pnl-pct 1.0] [--lag-bars 1] [--lag-frac 0.05] [--json out.json]
```

Both CSVs use the ParityExport/C++-ledger header (`entryTimeUTC,dir,...,realizedUsd,...,exitTag`).
The engine run is usually wider than the MT5 window, so the tool window-filters the
engine side to the MT5 span before matching. Matching is greedy nearest-time within
the same direction, bounded by `--lag-bars`.

## PASS criteria (contract §4)

- entries match 1:1 (≤1-bar lag on ≤`--lag-frac` of trades),
- exit reasons match,
- net P&L within `--tol-pnl-pct` (default 1%).

Any structural mismatch (different trade count, opposite direction, wrong exit path)
= **FAIL → engine-fidelity bug. Fix the engine, do not promote.**

## Self-test result (2026-06-16) — the tool is validated, the engines are not

Run against the two existing MasterVP MT5 reference runs. The tool independently
reproduced the documented ground truth (it was not told the answer):

| run | matched | unmatched (eng/mt5) | exit-tag Δ | net P&L Δ | verdict |
|---|---|---|---|---|---|
| MasterVP XAU M3 2026-05 | **20/22** | 3 / 2 | 3/20 | 13.3% | **FAIL** |
| MasterVP BTC M3 2026-06 | 4/10\* | 0 / 6 | 0/4 | 62.3% | **FAIL** |

\* The BTC engine export `trades_cpp_ema.csv` is a known-buggy file (dropped the 00:30
& 01:45 fills; authoritative count is the engine gate-trace = 7/10). The tool faithfully
reports what the file contains — fix the export, then re-run.

**Finding:** even MasterVP, the best-parity strategy, fails §4. The dominant divergence
in both runs is **exit geometry** — the engine closes via tight `SL-WIN`/`SL-LOSS` trail
where the MT5 EA closes via managed `EA` session/news exits (e.g. XAU 2026-05-22/05-25
cluster). This is the #1 engine-fidelity bug to fix before any sweep is trustworthy, and
it matches the KenKem-E5 exit-geometry root cause already on record.

## Next

1. Reconcile the engine exit path with the EA-managed exits (trail-vs-managed) so exit
   tags and exit P&L agree → re-run until XAU/BTC MasterVP PASS.
2. Then run the same loop on Monster (recent OOS) to localize its cost-vs-exit divergence.
3. Only after PASS: run Class-A-only tick-engine sweeps; accept a config only if it PASSes
   parity AND beats the original `KenKemExpert` (PF 1.62) on recent OOS.
