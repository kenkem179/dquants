# research/stats — overfitting & multiple-testing gate (strategy-agnostic)

The statistical-rigor layer for the **sweep → lock** workflow. When you evaluate many configs and
keep the best, the winner's Sharpe is inflated by selection — these methods (Bailey & López de
Prado) deflate it back. **Not** Green-Book material; this is backtest-selection best practice.

Works for **every** strategy (KenKem, MasterVP, Monster, BTC) — one tool, not a per-strategy copy.

## Files
- `overfitting.py` — the math: PSR, Deflated Sharpe (DSR), Min Track Record Length, PBO (CSCV),
  Bonferroni / Benjamini-Hochberg. Pure numpy/scipy, deterministic.
- `gate.py` — universal CLI/loader. Reads **any** engine's trades CSV (auto-detects
  `entryTimeUTC`/`ts_ms` time + `realizedUsd`/`pnlUsd` pnl) and runs the gate.
- `test_overfitting.py` — `pytest`, all green.

## Run it on any locked stream
```bash
conda run -n kenkem python research/stats/gate.py \
    --trades <any engine trades.csv> --label "XAU M5" \
    --n-trials 200 --sr-trial-std 0.03      # the two sweep-context args unlock the DSR verdict
```
- `--n-trials` = how many configs the sweep evaluated before locking.
- `--sr-trial-std` = std of per-trade Sharpe across those trials (the search dispersion).
- Omit both → still get PSR-vs-0 + Min Track Record Length (DSR shows `n/a`).

**Verdict:** `PASS` = DSR ≥ 0.95 and sample long enough · `WARN` = DSR ≥ 0.90 · `FAIL` otherwise.

## Already wired into the lock harnesses
- `research/mastervp_parity/wf_mc.py` — prints the gate after the Monte-Carlo block.
- `research/optimization/robustness_kenkem.py` — prints the gate per trade log.
- Monster's `wf_monster.py` is a grid-sweep (no single locked stream) → run `gate.py` on its
  locked CSV directly.

## Sweep context — where `--n-trials` / `--sr-trial-std` come from (wired)
The `optimize_*.py` harnesses now emit the real search width. Each objective records its trial's
per-trade Sharpe (`trial.set_user_attr("sharpe", trial_sharpe(train+test))`), and after the study
`report_sweep_context(study, best_set, label=...)` (in `sweep_context.py`) prints `n_trials` +
`sr_trial_std`, writes a sidecar `<best>.set.sweepctx.json`, and echoes the exact `gate.py` command.
So the flow is: run the sweep → read the printed command (or the sidecar) → run `gate.py` on the
locked trade stream with those two numbers. No more placeholder dispersion.
