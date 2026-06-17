# RUN_2026-06-18 — KK-MasterVP · BTCUSD M3 · 2-year (MasterVP anchor)

MT5 ground truth for MasterVP parity.

## Run spec (user, 2026-06-18)
- Expert: `KK-MasterVP.mq5` (kenkem repo)
- Symbol `BTCUSD-Exnes-0406` · **M3** · Every tick based on real ticks
- Period 2024.01.01 → 2026.06.01 · deposit 10000 · leverage 1:500
- Default params, CSV logging on.

## Result — ⚠️ EA STOPS TRADING after 2024-05-31
- **134 trades, ALL in 2024-01..2024-05**, then ZERO trades for the remaining ~24 months.
- per-bar `parity_trace.csv` DOES span the full 2yr (2024.01.01 → 2026.05.31) — so the EA kept
  evaluating bars but never entered after May 2024 ⇒ a **lockout** (persistent drawdown/daily-loss
  soft-block or a state flag that never resets). Investigate before trusting this as a baseline.
- sum realizedUsd +136.39 (raw), final balance **7880.84** (−21%) — the loss is account-state /
  lot effects, not the raw trade P&L.
- kinds: all kind=0 (single entry type). exits: SL-LOSS×62, SL-WIN×57, EA×14, TP×1.
- months: 2024.01=31, 02=40, 03=13, 04=8, 05=42, then none.

## Files
- `trades.csv` — per-trade journal (MasterVP schema, 21 cols — matches `research/validation/parity_diff.py`):
  `entryTimeUTC,dir,rev,retest,regimeTrend,session,entry,riskPrice,mfeR,maeR,realizedUsd,entryReason,brkDistAtr,bodyPct,adx,diSpread,runwayAtr,nodeNet,spreadPips,spreadAtr,exitTag`
- `parity_trace.csv` — per-bar VP/ADX decision trace (172MB). ⚠️ first-row formatting looks run-together; verify delimiter before diffing.
- `inputs_all.txt`, `tester.log.gz`.

## TODO
- Diagnose the post-May-2024 trading halt (which limiter latched). May need a re-run with the
  lockout disabled, OR model the same lockout in the engine for faithful parity.
- Build BTC M1 ticks+bars (M3/M5/M15 derive by aggregation) for the engine diff.
