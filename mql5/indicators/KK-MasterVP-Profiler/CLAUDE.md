# KK-MasterVP-Profiler — Engineering Contract (EA-twin rebuild)

Display-only MT5 indicator that is the **visual twin of the KK-MasterVP EA**.
It does NOT re-implement the strategy — it `#include`s the EA's own decision
code and replays the EA bar-by-bar, so an entry marker lands on the EXACT
candle the EA fires. (This replaces the earlier standalone "scout", which was
deliberately looser than the EA and therefore diverged from it.)

## Single-source architecture (do not break this)

The indicator includes the EA's pure logic directly:
- `../../experts/VP-Common/{Types,VolumeProfile,Regime,NodeEngine}.mqh`
- `../../experts/KK-MasterVP/{Inputs,Strategy,Decision,SessionNews}.mqh`

It must NEVER include `KK-MasterVP/Engine.mqh` (that pulls in `CTrade` +
OnTick/OnInit and would make it a trader). The entry decision = the EA's
`MVP_DetectSignal` + `MVP_DeterministicGatesPass` (in `Decision.mqh`). If the EA
logic changes, this indicator inherits it for free — that is the whole point.
All EA `Inp*` params are inherited verbatim; display-only knobs are `InpViz*`
(prefixed so they can never clash with the EA schema). **Drive it from the EA's
`.set`** so its params == the EA's.

## The replay (mirrors Engine.mqh::OnNewBar)

Shift map: forming bar = `b`, shift1 = `b-1`, shift2 = `b-2`. Master VP ends at
`b-1` over `InpVpLookback*InpMasterMult` bars; signal bar OHLC = `b-2`; fill at
the open of bar `b` (entry price = `close[b-1]` = `sig.entry`). Per bar, in order:
master+local VP → node `Update` (stateful decay, every bar) → `SN_UpdateSession`
→ regime → `MVP_DetectSignal` → `MVP_DeterministicGatesPass` → stateful gates
(one-position-at-a-time + `SN_MaxTradesOk`) → on fire, a forward OHLC exit replay
(TP1 → BE → ATR chandelier trail, runner cap) yields WON/LOST/BE + the exit bar.

Use the same indicator handles as the EA (`iATR/iRSI/iADX/iMA`, same lengths) so
ATR/EMA/ADX/RSI values are byte-identical. Recompute only on a new closed bar.

## Parity scope (what matches, what does not)

MATCHES the EA exactly for the locked config: signal, regime, session, ATR%/
ATR-ticks, blocked-hour, news, max-trades/session, one-position. **Ignored by
design: the predictive daily-DD cap** (needs live equity an indicator lacks;
rarely binds). MTF-EMA + RSI quality gates are passed `0,0`/chart-RSI — exact
while they are OFF (the lock); approximate if you enable MTF.

## Local POC

INERT in the locked breakout-only config: `Strategy.mqh:72/80` use local VP ONLY
to tighten a **reversion-trade** SL, and `InpEnableReversion=false`. Drawn faint +
off by default (`InpVizShowLocalPOC`), labelled "rev-only". Not a driver.

## Visuals delivered

Master VAH/VAL/POC at the EA's length (buffers) · regime EMA fast/slow · entry
markers E/SL/TP1/TP2 with WON/LOST/BE verdict · SL→BE→trail stop path · gray
background over blocked trading hours (`InpBlockedHoursStr` via `SN_RefTime`) ·
compact status panel (master length, WON/LOST/BE tally, hit%, blocked hrs).

## Compile (Makefile does NOT cover Indicators)

`bash scripts/compile_mql5.sh mql5/indicators/KK-MasterVP-Profiler/KK-MasterVP-Profiler.mq5`
Gate: **0 errors, 0 warnings**. The running terminal hot-reloads the `.ex5` on
indicator re-attach.

## Follow-ups (not yet done)

- Visual MT5 spot-check: attach to XAU M5 with the EA's `.set`, confirm markers
  sit on the same candles the EA backtest opens trades on.
- Optional: port the old scout's tick-flow histogram / exec-health panel as an
  opt-in overlay if the richer cockpit is wanted alongside the parity markers.
- MTF-EMA exact replay (align M15 EMA to chart time) — only if MTF gate is used.
