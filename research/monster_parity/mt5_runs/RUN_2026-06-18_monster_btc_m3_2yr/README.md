# RUN_2026-06-18 — KK-MasterVP-Monster · BTCUSD M3 · 2-year (Monster anchor)

MT5 ground truth for Monster parity.

## Run spec (user, 2026-06-18)
- Expert: `KK-MasterVP-Monster.mq5` (kenkem repo)
- Symbol `BTCUSD-Exnes-0406` · **M3** · Every tick based on real ticks
- Period 2024.01.01 → 2026.06.01 · deposit 10000 · leverage 1:500
- Default params, CSV logging on.

## Result — ⚠️ ACCOUNT BLOWUP at defaults
- **2049 trades**, sum realizedUsd **−9971.90**, final balance ≈ **$28** from $10000.
- kinds: kind1×1952, kind4×97 · dir: L×825, S×1224.
- exits: SL-LOSS×1362 (66%), SL-WIN×373, TP×314 — pure SL/TP, no managed exits.
- span 2024.01.02 08:12 → 2026.05.31 16:39.
- ⇒ Monster on BTC M3 with default params is catastrophically unprofitable. Parity first
  (reproduce these 2049 trades), THEN optimization is the real job (per CLAUDE.md: "not
  properly optimized yet").

## Files
- `trades.csv` — per-trade journal (Monster schema, 20 cols):
  `entryTimeUTC,dir,kind,session,entry,riskPrice,mfeR,maeR,realizedUsd,entryReason,brkDistAtr,bodyPct,slopeNorm,netM1,netM3,netM5,atrPct,spreadPips,spreadAtr,exitTag`
- `parity_trace.csv` — per-bar decision trace (89MB).
- `inputs_all.txt` — EA input echo (all passes; isolate the Monster block).
- `tester.log.gz` — full tester log.

## TODO before engine diff
- Confirm exact Monster `.set`/config + BTC contract point value/commission for the C++ Monster engine.
- BTC ticks: build from `~/Downloads/Exness MT5 Tick data 2024-2026` (BTCUSD) like the XAU anchor.
