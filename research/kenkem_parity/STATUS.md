# KenKem dquants port — "fix the lie" status (2026-06-15)

## The problem the user reported
Original `KenKemExpert.ex5` (XAUUSD M1, 2025.03.01→2026.06.08) backtests at **PF 1.39, +$1,968.91,
164 trades, Recovery 1.40, Sharpe 13.61** (E1+E2 only; E3/E4/E5 OFF). The dquants C++ "KenKem" edition
lost heavily on the same data.

## Root cause: the config lied
The distilled C++ engine **parsed all 250 EA params from the `.set` but only applied a fraction** — the
file headers literally documented the dropped logic. So the `.set` made it *look* faithful while the
engine silently ignored the EA's main selectivity machinery:

| Feature (in winning .set) | Parsed? | Was applied? |
|---|---|---|
| Conviction scoring (E1=7, E2=10) | yes | **no** → wired now |
| Full 0-11 trend-quality (min E1=6, E2=9) | yes | reduced to 0-6 → wired now |
| RSI-divergence veto | yes | **no** → wired now |
| ATR high-vol block (pctile>90) | yes | **no** → wired now |
| Consecutive-loss-per-type block | yes | **no** → wired now |
| Fast-ADX panic exit | yes | **no** → wired now |
| Score-drop exit (E2 ON) | yes | **no** → wired now |

## What was done
Faithful 1:1 ports from `../kenkem` MQL5 source, each gated by its existing config flag so **config now
drives behaviour** (no silently-ignored params for the implemented features):

- `include/kk/kenkem/scoring.hpp` — conviction (0-12), full trend-quality (0-11 + ichimoku + ATR), RSI
  divergence veto. Wired into `entries.hpp::entry_gate_ok` via `quality_filters_ok`.
- `include/kk/kenkem/entries.hpp` — ATR high-vol block.
- `include/kk/kenkem/engine.hpp` — stateful governors: consecutive-loss-per-(kind,dir) timed block,
  MIN_SECONDS_BETWEEN_ENTRIES; per-bar snapshot hoisted for exits.
- `include/kk/kenkem/exits.hpp` — fast-ADX panic exit + score-drop exit, evaluated once per M1 bar.
- `tf_cache.hpp` — M3 now carries RSI (needed by conviction + RSI-veto).
- New tests: `test_kenkem_scoring.cpp`; geometry/integration tests relaxed (filters covered separately).
  **All 10 kenkem tests pass.**

## Measured trajectory (XAUUSD M1, full window, spread 0.14, winning .set)
Note: M1 bar count = **439,777 — exactly matches the MT5 report's "Bars 439777"** (bar sets aligned).

| Stage | Trades | Net USD | PF | E1 | E2 |
|---|---|---|---|---|---|
| Broken (filters ignored) | 3430 | **-23,067** | 0.94 | -11,075 | -11,992 |
| + entry filters (conv/TQ/RSI) | 2327 | -8,054 | 0.97 | -11,643 | +3,589 |
| + ATR-high/consec-loss/min-sec | 1659 | -4,657 | 0.98 | -8,838 | +4,181 |
| + panic/score-drop exits (current) | 1655 | **-1,640** | 0.99 | -7,590 | +5,950 |

Isolated: **E2-only = +$4,980, PF 1.091** (760 trades) — a working, profitable component.
**E1-only = -$7,579, PF 0.94** (968 trades) — the remaining bleed.

## Remaining gap to PF 1.39 (see task #6)
The whole loss is now concentrated in **E1, which over-fires 11× (968 vs the EA's 86)**. E1 intentionally
runs a LOW conviction threshold (7) and relies on E1-specific gates that are NOT yet wired:
1. `HasSufficientMomentum` confirmation (E2 deliberately omits this; E1 requires it).
2. `E1_HTF_TREND_FILTER` strength (E1_HTF_MIN_ADX=18.5, E1_HTF_MIN_DI_SPREAD=4.0) + high-risk-path branch
   (`potentialLoss >= maxLoss` → stricter momentum gate + per-session high-risk cap).
3. **Session-window filtering** — the EA only trades JST sessions + closes all at session end; dquants
   trades 24/5. Needs the tick-data↔JST offset resolved first (derivable by matching the ground-truth
   ledger's entry timestamps to dquants candidate signals by price).
4. Audit the E1 EMA-cross trigger frequency vs the EA.

## Artifacts (research/kenkem_parity/)
- `winrun.log` — isolated winning KenKemExpert run from the MT5 journal.
- `ground_truth_ledger.csv` — 156 executed trades reconstructed from the journal (E1=86, E2=70).
- `winning.set` — 418 inputs extracted from the journal.
- `bars_xauusd_M1_kk.csv` — 439,777 M1 mid bars (matches MT5 bar count).
- `dq_trades_v3.csv` — current dquants trade ledger.
- `build_ledger.py` — journal→ledger parser.
