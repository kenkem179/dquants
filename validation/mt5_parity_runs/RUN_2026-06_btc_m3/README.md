# Parity Run — BTCUSD M3, 2026-06-01 → 2026-06-08

First real-ticks MT5 vs C++ engine parity check. Goal: confirm the C++ TICK engine
reproduces MT5 "Every tick based on real ticks" before scaling.

## MT5 Strategy Tester settings (run these EXACTLY)
- Expert:      KK-MasterVP  (base — NOT Monster)
- Symbol:      BTCUSD
- Timeframe:   M3
- Model:       **Every tick based on real ticks**   <-- the whole point
- Date range:  2026.06.01 00:00  ->  2026.06.08 00:00   (UTC; inside tick coverage which ends 2026-06-09)
- Optimization: OFF (single pass)
- Params:      **LOAD preset KK-MasterVP-parity-btc** (== cpp_core/tools/btc_ref_run.set).
               Do NOT use code defaults — the C++ engine runs this exact set, so params must match.
               It already has InpMaxSpreadPips=0 (defaults=40 blocks ALL BTC entries -> 0 trades)
               and InpAvoidNews=false. Override only InpBrokerGMTOffset if broker server != UTC.

## LIVE terminal data folder (portable mode, origin = C:\Program Files\MetaTrader 5)
  /Users/tokyotechies/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5
  Presets:  MQL5/Presets/KK-MasterVP-parity-btc.set  (symlink -> repo btc_ref_run.set)
  NOTE: the kenkem/ repo MQL5+Tester is NOT this terminal (stale Dec-2025). Ignore it for outputs.

## Outputs to collect after the run  (from the LIVE terminal folder above)
  MQL5/Files/KK-MasterVP/parity_BTCUSD_M3.csv   -> copy to ./mt5_ref/
  MQL5/Files/KK-MasterVP/trades_BTCUSD_M3.csv   -> copy to ./mt5_ref/
  Tester/Agent-127.0.0.1-3000/logs/<date>.log   -> copy to ./mt5_ref/  (modelling quality, ticks, deals)

## Then (analysis side, dquants)
1. Feed the SAME tick window to C++ -> ./cpp_out/parity_cpp_BTCUSD_M3.csv + trades_cpp_BTCUSD_M3.csv
2. Level 1 (bar math, PRIMARY): tools/common/validate_parity_py.py  (discard warmup; tol VP<.001, ADX<.005)
3. Level 2 (trades): tools/common/diff_trades.py
4. Level 3: PF / trade count / net (headline only)
5. On pass: freeze ~1 day as a C++ golden unit test.
