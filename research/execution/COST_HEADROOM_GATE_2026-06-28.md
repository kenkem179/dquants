# Cost Headroom Gate - MasterVP BTC M3 and KenKem XAU M1

## Codex-Step-8 Verdict

STOP for MasterVP BTC M3 alpha work from current local evidence.

The current BTC M3 stream has no cost headroom: 478 trades, net -75.30, PF 0.995, mean PnL/trade -0.158.
Any additional realistic cost makes it worse. A +1 USD/trade stress moves net to -553.30 and PF to 0.97.

KenKem XAU M1 has positive but not large cost headroom: 141 trades, net 1987.64, PF 1.517,
mean PnL/trade 14.097. A +10 USD/trade stress leaves net 577.60 and PF 1.13; +20 USD/trade flips it negative.

## Commands

```bash
source ~/miniforge3/etc/profile.d/conda.sh
conda activate kenkem
python research/execution/cost_model.py --trades cpp_core/tools/trades_cpp_btcusd_2025_M3.csv --fixed-usd-levels 1,2,5,10,20,50
python research/execution/cost_model.py --trades cpp_core/tools/trades_kenkem_lock_autopsy.csv --fixed-usd-levels 1,2,5,10,20,50
```

## BTC M3 Fixed-USD Cost Stress

| Extra USD/trade | Net | PF | Win% | Sharpe | MaxDD% |
|---:|---:|---:|---:|---:|---:|
| Base | -75.3 | 1.00 | 57.3 | -0.0016 | -19.5 |
| 1 | -553.3 | 0.97 | 57.1 | -0.0120 | -22.3 |
| 2 | -1031.3 | 0.94 | 56.9 | -0.0224 | -25.1 |
| 5 | -2465.3 | 0.86 | 56.9 | -0.0536 | -34.7 |
| 10 | -4855.3 | 0.74 | 48.1 | -0.1056 | -53.1 |
| 20 | -9635.3 | 0.55 | 24.1 | -0.2096 | -96.6 |
| 50 | -23975.3 | 0.27 | 19.0 | -0.5217 | -233.7 |

## KenKem XAU M1 Fixed-USD Cost Stress

| Extra USD/trade | Net | PF | Win% | Sharpe | MaxDD% |
|---:|---:|---:|---:|---:|---:|
| Base | 1987.6 | 1.52 | 53.9 | 0.1697 | -4.8 |
| 1 | 1846.6 | 1.47 | 53.9 | 0.1577 | -5.1 |
| 2 | 1705.6 | 1.43 | 53.2 | 0.1456 | -5.4 |
| 5 | 1282.6 | 1.31 | 48.9 | 0.1095 | -6.6 |
| 10 | 577.6 | 1.13 | 44.0 | 0.0493 | -8.7 |
| 20 | -832.4 | 0.84 | 43.3 | -0.0711 | -14.2 |
| 50 | -5062.4 | 0.36 | 36.2 | -0.4322 | -50.4 |

## Data Gaps Blocking Higher-Precision Cost Work

- Current MasterVP BTC M3 trade export has no `exit_ts`, `exit`, `lot`, `commission`, `slippage`, or realized `r_multiple`.
- Current KenKem XAU M1 export has `exitPrice`, but no `exit_ts`, `lot`, `spread`, `commission`, or `slippage`.
- `spreadPips` exists for MasterVP, but without lot/pip-value/deal commission it cannot be converted to realized account-currency cost.
- BTC cost modeling still needs weekend/session spread widening, rollover behavior, and adverse slippage from MT5 deal history or a broker-realistic fill model.

## Decision

Do not spend more search budget on MasterVP BTC M3 parameters until BTC has either:

1. a structural hypothesis that passes model-free event taxonomy before costs, and
2. deal-level cost fields or engine-emitted lot/exit/commission/slippage fields sufficient for realistic repricing.

For KenKem, the next productive path is not VP code. It is cost-aware entry-role/risk-geometry audit on the base
M1 edge, because the edge survives small costs but becomes marginal around +10 USD/trade and fails by +20 USD/trade.
