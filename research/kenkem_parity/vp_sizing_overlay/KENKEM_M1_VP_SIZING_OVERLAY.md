# KenKem M1 VP Sizing Overlay

## Codex-Step-7 Verdict

STOP: Do not implement KenKem VP sizing yet. The walk-forward policy does not improve the full base stream cleanly enough to justify an EA code change.

This test keeps every KenKem trade. VP context may only change risk weight, so it is less sample-hungry than
a hard entry filter. Production promotion still requires C++ implementation, costs, registry row, and DSR/MinTRL.

## Scenario Metrics

| Scenario | n | Net | PF | MaxDD | Avg/trade | Win rate |
|---|---:|---:|---:|---:|---:|---:|
| BASE | 141 | 1987.64 | 1.517 | 479.92 | 14.10 | 0.539 |
| VP_state_inside_0.50 | 141 | 1882.25 | 1.550 | 484.75 | 13.35 | 0.539 |
| EntryVP_diagnostic | 141 | 2409.65 | 1.686 | 463.14 | 17.09 | 0.539 |
| WalkForward_cell_sizing | 141 | 1847.38 | 1.483 | 479.92 | 13.10 | 0.539 |

## Robustness Notes

- Base positive quarters: 3/6.
- Walk-forward positive quarters: 3/6.
- Base worst quarter: -250.22.
- Walk-forward worst quarter: -250.22.
- `EntryVP_diagnostic` is in-sample and is reported only to show possible cell structure; it is not a lock.
- Blank/zero MAE values in the source stream limit path-quality conclusions.

## Artifacts

- `vp_sizing_overlay_summary.csv`
- `vp_cell_summary.csv`
- `walkforward_cell_sizing_quarter_metrics.csv`
