# RUN_2026-06-18 — KenKemExpert 1.8.154 · XAUUSD 2-year anchor (NEW reliable baseline)

This is the authoritative MT5 ground truth for KenKem parity. It **supersedes** the deleted
9-trade Feb-2026 window (old `RUN_2026-06-17_1.8.154_xau_feb`, now gone).

## Run spec (user, 2026-06-18)
- Expert: `KenKemExpert.mq5` v1.8.154 (kenkem repo, branch `KKMasterVPv1`)
- Symbol `XAUUSD-Exness-KK` · M1 · **Every tick based on real ticks**
- Period **2024.01.01 → 2026.06.01** · deposit 10000 · leverage 1:500
- Params: **defaults except** E1+E2+E4+E5 ON (E3 off), `COMMON_MAX_RISK_PER_TRADE=0.01` (1%)
- Parity toggles `InpExportTradeJournal=true`, `InpExportBarTrace=true`

## Result
- final balance **11761.34** (+1761.34 / +17.6%), OnTester 44.55, deterministic across 2 passes.
- **1005 trades**: E1×136, E2×124, E4×165, E5×579.
- exit tags: EA(managed)×388, SL-LOSS×248, SL-WIN×235, TP×134.
- span 2024.01.04 02:11 → 2026.05.29 07:41.

## Files
- `trades.csv` — per-trade journal (TradeJournal.mqh). Cols:
  `entryTimeUTC,dir,kind,entry,riskPrice,exitPrice,realizedUsd,mfeR,maeR,exitTag` — **THE diff target**.
- `trace.csv` — per-bar E5 decision trace (BarTrace.mqh, 291MB). E5 ON ⇒ populated.
  ⚠️ ichimoku cols buffer-swapped (see HANDOFF). Join `cpp_ts−60000 == mt5_ts`.
- `inputs_echo.txt` — full 412-line EA input echo (the exact config to mirror in the engine .set).
- `tester.log.gz` — full MT5 tester log.

## Engine repro target
C++ tick engine on the same XAU ticks + this config must reproduce these 1005 trades within
tick-fill tolerance (entry bar/dir/kind match; price/SL/exit within tolerance).
