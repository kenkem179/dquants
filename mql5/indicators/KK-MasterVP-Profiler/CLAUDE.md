# KK-MasterVP-Profiler — Engineering Contract

Standalone MT5 volume-profile cockpit (display-only, no trading) for the
KK-MasterVP-Monster strategy. Single self-contained `.mq5`; folder is
symlinked into the live MT5 `MQL5/Indicators/`. Read this before changing
anything — every rule below exists because the naive version failed.

## Compile (Makefile does NOT cover Indicators)

```
WINEDEBUG=-all WINEPREFIX="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5" \
"/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64" \
"$WINEPREFIX/drive_c/Program Files/MetaTrader 5/metaeditor64.exe" \
/compile:"Z:<abs .mq5 path>" /log:"Z:<abs log path>"
```
Log is UTF-16LE (`iconv -f UTF-16LE -t UTF-8`). Gate: **0 errors, 0 warnings**.
In the Devin IDE the editor-title compile button (MQL Clang ext) is wired via
`.vscode/settings.json`; the MQLens "Compile MQL File" command is a fake stub.
The running terminal hot-reloads the `.ex5` on indicator re-attach.

## Reliability techniques (and the failure each one prevents)

1. **Committed vs live separation (anti-repaint).** Committed histogram/node
   state is built ONLY from completed-bar ticks (`toMs = forming-bar open − 1 ms`);
   the forming bar lives in separate `g_live*` arrays reset on each new bar.
   Node engine updates once per closed bar (`g_nodeBarTime` guard). Nothing a
   user saw on a closed bar can ever redraw differently.
2. **Stateless setup history.** WON/BE/LOST is a deterministic rescan of bar
   data on every new bar — zero accumulated state to corrupt on reload.
   Ambiguity resolves conservatively, never flattering: same-bar SL+TP1 touch
   = LOST; BE-ratchet stop lift applies from the NEXT bar (intrabar order is
   unknowable from OHLC).
3. **Feed honesty.** Real-tick build with explicit bar-feed fallback (exact
   Pine-parity math), `[TICK]/[BAR]` in the panel header, one Experts-log line
   per feed-state change with the failure reason, and a 5 s auto-retry after
   attach — `CopyTicksRange` returns empty while history syncs, which is the
   root cause of every "all-gray histogram" report.
4. **Guarded reads, no silent zeros.** Handles checked vs `INVALID_HANDLE`;
   every `CopyBuffer/CopyRates/Copy*` return count checked; `EMPTY_VALUE`
   checks before use; divisions floored (`MathMax(x, g_mintick)`); the EMA
   history copy is all-or-rearm — a short copy never poisons a buffer.
5. **ATR-relative geometry only.** Every price distance is `x × ATR`; the only
   non-ATR constants are `SYMBOL_TRADE_TICK_SIZE` floors. The verdict window
   floors at the forming bar's own range because ATR(14) lags news candles.
6. **Anti-flicker UX.** Headline verdict direction changes only after holding
   `InpVerdictHoldSec` (kills bid/ask bounce); per-tick work throttled to
   250 ms and O(bins); objects create-once / update-in-place; the panel
   backdrop is recreated BEFORE its labels every refresh — creation order is
   MT5's only z-order rule.
7. **Visible delta on any TF.** Recency decay (`InpNodeDecay` per bar of age)
   + net-scale ranking (`InpHistNetScale`) — an undecayed 150-bar tick-rule
   sum nets out near zero in every bin and renders all-gray.
8. **Incremental tick cache.** Rolling `g_ticks` window: fetch only the new
   tail, prune the expired head; dwell credit capped (`InpDwellCapSec`) so
   session gaps cannot dominate time-at-price or the exec-speed baseline.
9. **Honest telemetry semantics.** Rejection markers speak trade language
   ("sell 44% need 50%", "opp buy 79%"); panel "slip" is a tape-speed proxy
   (an indicator sees no fills); exec baselines come from the same committed
   tick window as the profile.

## Scout ≠ EA (do not blur this)

The setup scout is deliberately looser than the EA: net gate 0.50 vs EA 0.80,
no session/news/regime/overhead gates, fills at signal close vs EA next-open.
It exists to show MORE than the EA takes, with rejection reasons. Never tune
the EA by eye from scout outcomes — WON means TP1-touch-before-SL, gross of
spread. Use `/parity-check` and EA backtests for any real claim.

## Known limits / next steps toward live practicality

Ordered by expected value; SL/TP/exit items are EA/Pine strategy changes that
need `/strategy-hypothesis` → toggle → real-tick backtest → tail-survival
check FIRST, with the scout only visualizing the result:

1. **Failed-break early exit study** (queued next in the master plan): close
   back inside the broken edge within N bars, or near-price net flipping
   ≥0.5 against the position before 0.5R — attacks the loss tail directly.
2. **Structural TP2**: snap to the first HVN-grade bin beyond TP1 minus
   0.2 ATR (the `ComputeProjection` magnet-walk already computes this map),
   else predicted VA edge; clamp [1.2R, 3R]. Screenshots show fixed 2R
   repeatedly pointing into volume vacuum past mVAH.
3. **HVN-shelf SL**: strongest bin 0.5–2.5 ATR behind entry + 0.25 ATR,
   clamped — instead of `max(edge-buffer, 2 ATR)` landing in structureless air.
4. **Flow-aware chandelier** for the EA runner: tighten 3.0 → 1.5 ATR when
   near-net ≥0.7 with M1 agreement and bar range ≥1.5×ATR; ratchet-only.
5. **Parity-grade scout toggle**: one input flipping the scout to EA gates
   (net 0.80, session/news/regime) so the chart shows exactly what the EA
   would trade — the manual-trading bridge.
6. **Alerts**: `Alert`/push/sound toggles on setup triggers and verdict flips
   — required for real manual use and for an MQL5 Market listing.
7. **Scoreboard row**: running WON/BE/LOST counts + hit rate on the panel
   (with the gross-of-spread caveat in the tooltip).
8. **Market-validator hardening**: verify behavior on arbitrary symbols/TFs,
   symbols with sparse history, and the validator's dead account (display-only
   code mostly passes by construction — but prove it before listing).
