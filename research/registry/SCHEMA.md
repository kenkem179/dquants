# Experiment Registry — SCHEMA (R3)

One machine-readable row per experiment lives in `experiments/<experiment_id>.yaml`. The flat
rollup `index.csv` is **generated** from those files (`registry.py rebuild`) — never hand-edit it.

This is the auditability spine for the mutual-skepticism trust contract: a registry row is the
difference between an *assertion* ("the lock is good") and *reproducible evidence* (commit, data,
.set, cost model, search width, gate verdict, artifacts → decision).

## Conventions

- **`null` / blank means UNKNOWN, never zero.** A missing maxDD is `null`, not `0`. Do not invent
  numbers; transcribe them from a source-of-record and cite it in `source_refs`.
- **Field names mirror `research/stats/gate.py`** so a registry row and a gate run speak the same
  language: `n_trials`, `sr_trial_std`, `gate.psr` (= gate's `psr0`), `gate.dsr`, `gate.mintrl`,
  `gate.verdict`.
- **IDs are deterministic**, derived from `strategy + symbol + timeframe + decision + label`
  (slugified). No timestamps, no randomness → re-running a back-fill overwrites the same file.
- **`metrics.sharpe` is per-trade Sharpe** (matches gate's `sharpe`); **`metrics.n_trades`** matches
  gate's `n`.

## Top-level fields

| field | type | meaning |
|---|---|---|
| `schema_version` | int | currently `1`. |
| `experiment_id` | str | deterministic slug id (see above). Filename = `<id>.yaml`. |
| `date` | str (YYYY-MM-DD) | decision date. Supplied, **not** `now()` (keeps rebuilds deterministic). |
| `hypothesis_id` | str·null | BUILD-PLAN item / Codex step (e.g. `K1/D5-E4Long`, `R5a/Codex-Step-8`). |
| `strategy` | str | `kenkem` · `mastervp` · `monster`. |
| `symbol` | str | `XAUUSD` · `BTCUSD`. |
| `timeframe` | str | `M1` · `M3` · `M5`. |
| `train_start`,`train_end` | str·null | in-sample window. |
| `oos_start`,`oos_end` | str·null | out-of-sample window (kept strictly OOS). |
| `commit_hash` | str·null | git commit the experiment ran at. |
| `data_source` | str·null | human description of the input data (file + span). |
| `data_sha256` | str·null | sha256 of the data artifact (use `sha256_file()` going forward; `null` for back-fill — the artifact-at-run-time is not the current file). |
| `set_path` | str·null | path to the `.set` preset (READ-only reference; registry never edits it). |
| `set_sha256` | str·null | sha256 of the `.set` at lock time (`null` for back-fill). |
| `cost_model` | str·null | how costs were modeled (MT5 every-tick vs C++ engine vs offline cost stress). |
| `n_trials` | int·null | configs the sweep evaluated (for DSR deflation). |
| `sr_trial_std` | float·null | std of per-trade Sharpe across those trials (search dispersion). |
| `metrics` | map | see below. |
| `gate` | map | see below. |
| `mt5_confirmed` | bool·null | whether MT5 (the final exit judge) confirmed the result. |
| `artifacts` | list[str] | paths to the writeups / run dirs / CSVs backing the row. |
| `decision` | enum | `LOCK` · `REJECT` · `RESEARCH-ONLY` · `STOP`. |
| `supersedes` / `superseded_by` | str·null | id links between successive locks. |
| `notes` | str·null | one-paragraph honest summary (caveats, what's fictional, why). |
| `source_refs` | list[str] | provenance: `memory:<fact>`, `docs:<file>`, `archive:<item>`, `HANDOFF:<step>`. |

### `metrics` (nested map — every key present, value may be `null`)
`net_usd`, `pf`, `max_dd_pct`, `sharpe` (per-trade), `n_trades`, `win_pct`.

### `gate` (nested map — mirrors gate.py output)
`psr` (PSR-vs-0, gate's `psr0`), `dsr` (deflated Sharpe), `mintrl` (min track-record length, trades),
`mintrl_sufficient` (bool: `mintrl <= n_trades`), `pbo` (prob. of backtest overfit, CSCV), `verdict`
(`PASS` / `WARN` / `FAIL` / `null`). Verdict policy = gate.py: `PASS` = DSR ≥ 0.95 **and** sample
sufficient · `WARN` = DSR ≥ 0.90 · else `FAIL`.

## Decision values

- **`LOCK`** — production-eligible config (must carry a gate verdict; ideally `mt5_confirmed: true`).
- **`REJECT`** — tested and failed a decision rule (overfit, OOS-negative, MT5-disconfirm).
- **`RESEARCH-ONLY`** — diagnostic/audit or infra-only finding; no deployment claim.
- **`STOP`** — a pre-gate that halts further search (no cost headroom, no monotone structural edge).

## `index.csv` columns (generated, fixed order)
`experiment_id, date, decision, strategy, symbol, timeframe, hypothesis_id, net_usd, pf,
max_dd_pct, sharpe, n_trades, n_trials, sr_trial_std, psr, dsr, mintrl, mintrl_sufficient, pbo,
gate_verdict, mt5_confirmed, commit_hash, set_path, supersedes, superseded_by, notes`.
`null` → empty cell; bool → `true`/`false`.
