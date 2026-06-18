# ATR Fix A/B — Wilder vs EMA-smoothed ATR (KK-MasterVP BTCUSD M3, 2026-06-01..06-08)

**Question:** MT5's "Wilder" indicators actually smooth with EMA `k=2/(n+1)` (already encoded
for ADX in `dmi_adx_mt5`). Our ATR used textbook Wilder RMA (`alpha=1/n`). Does an EMA-smoothed
ATR (`kk::ind::atr_mt5`, opt-in via `InpAtrMt5Mode`) better match MT5 and recover the flipped,
ATR-scaled breakout trades?

## Setup
- Same bars + ticks (`cpp_out/bars_btcusd_2026_M3.csv`, `ticks_btcusd_2026_window.csv`).
- Param set `cpp_core/tools/btc_ref_run.set`, copied with `InpAtrMt5Mode=false` / `=true`.
- `make parity backtester` clean; `make test` -> **ALL TESTS PASSED** (golden parity test
  unchanged — default routing is still textbook Wilder, so nothing regressed).
- Match rule: same dir, entry bar within +/-1 M3 bar (180s), entry price within $15 (~2bps;
  same-bar BTC breakout fills legitimately differ ~$8-9 via the breakout-buffer tick — a $5
  absolute tol is unreasonable on a $73k instrument).
- C++ runs on a full-year 2026 bars file; 3 out-of-window 2026-01 trades are dropped before
  scoring (MT5 ground truth has only the 10 window trades).

## Results

| mode   | atr median ratio (cpp/mt5) | trades matched | extra | missed | net P&L |
|--------|----------------------------|----------------|-------|--------|---------|
| Wilder | 1.01728                    | 5/10           | 2     | 5      | $598.66 |
| EMA    | 1.00393                    | 5/10           | 0     | 5      | $306.14 |

MT5 reference net P&L (window): **$575.22**, 10 trades.

ATR ratio measured over the 3360-bar overlap. EMA cuts the median ATR bias from **+1.73% to
+0.39%** — the indicator itself is materially closer to MT5.

The 5 matched trades are the **same set** in both modes (04:24 S, 07:00 S, 00:18 S, 07:00 L
core, 06-07 L). EMA removes the 2 spurious Wilder extras (06-02 12:33 S, 06-07 07:33 L) but
**does not add any new MT5 match**. The 5 missed MT5 trades (00:30 L, 01:45 S, 13:09 S,
09:12 S, plus one 06-07 L) are missed in *both* modes — and the nearest cpp same-dir trade is
hundreds-to-thousands of $ and many bars away, i.e. these are **entirely different/absent signal
bars, not ATR-scaling flips**. So the divergence is upstream of ATR (bar construction / signal
detection / session gating), not the ATR kernel.

Note: EMA's net P&L ($306) drifts *further* from MT5 ($575) than Wilder's ($599) here, because
EMA drops the two winning extras and a winning 06-07 long — but net P&L over 5-8 trades is noise
and not a parity signal.

## VERDICT

**EMA-ATR improves the indicator (ATR median ratio +1.7% -> +0.4%) and cleanly removes 2
spurious Wilder breakouts, but it does NOT recover any missed MT5 trade — match stays 5/10 in
both modes.** The residual divergence is NOT ATR-kernel noise: the 5 missing trades are different
signal bars entirely (multi-hundred-$ / multi-bar away), pointing at spike-bar bar-construction
and signal/gating differences upstream of ATR. Recommendation: **adopt `InpAtrMt5Mode=true` as
the engine default** — it is strictly the more MT5-faithful kernel (tighter ATR, fewer false
breakouts, no test regression) — while keeping it a parsed flag so Wilder remains selectable.
But do not expect it to close the trade-count gap; the remaining 5/10 must be chased in bar
construction and the breakout/signal path, not in ATR smoothing.
