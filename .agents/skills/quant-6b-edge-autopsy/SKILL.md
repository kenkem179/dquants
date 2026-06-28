---
name: quant-6b-edge-autopsy
description: Phase 6b of the KenKem Quant OS SOP — prove a signal has conditional edge BEFORE spending sweep cycles on its parameters. Runs between hypothesis (6) and backtest/sweep (7-8); gates the sweep. Use whenever a new entry rule exists in the C++ engine.
---

# Phase 6b — Edge Autopsy (the analytic middle that gates the sweep)

The trap this closes: sweeping the PnL of a rule whose raw predictive content was never measured —
guess-and-sweep, then MT5-disconfirm. Here you prove (or kill) the edge on the RAW signal stream
first, so you only sweep survivors.

> **Precondition: `/quant-0-parity-baseline` must pass (or be N/A) first.** The autopsy's expectancy
> is only as trustworthy as the engine's correspondence to MT5 — on an unvalidated engine it just
> measures fiction faster. **Envelope guard:** the autopsy is valid only for signal paths inside the
> parity-validated set; if you condition on a path whose primitives are unverified, re-parity it.

## Input
The C++ engine's **pre-gate signal stream** + bars:
```bash
./cpp_core/build/backtester --bars <bars.csv> --ticks <ticks.csv> --set-all <base.set> \
    --symbol-xau --signals-out signals.csv          # one row per RAW DetectSignal (pre-gate)
```
`signals.csv` cols: `tsMs,timeUTC,dir,kind,isRev,isImpulse,isXRev,entry,sl,risk,brkDistAtr,bodyPct,`
`adx,diSpread,runwayAtr,nodeNet,atr,close,regimeTrend`. Forward returns are joined in Python from
the bars on `tsMs` (engine stays lookahead-free). `--signals-out` is opt-in; trades stay byte-identical.

## How (Python harness / notebook)
1. **Conditional expectancy / IC** — join forward returns at horizons (e.g. 10/20/50 bars, in ATR
   units) onto each raw signal; compare conditional vs unconditional mean, with bootstrap CIs and a
   t-stat / information coefficient. No signal-level edge ⇒ no sweep will manufacture one. **Stop.**
2. **Regime/session/volatility slices** — expectancy by `regimeTrend`, session, ATR-percentile band.
   Find where it lives and where it dies (non-stationarity is what pooled WF hides).
3. **Cost margin** — edge-per-signal (in $ via `risk`) vs cost-per-trade (spread+slip+commission).
   For a scalper this kills ~half of ideas outright.
4. **Gate-ablation funnel** — diff `signals.csv` against the executed `trades_*.csv` (join on time):
   how many of 25k signals survive (~3%), and is the SURVIVING set higher-expectancy than the BLOCKED
   set? If the gates don't raise expectancy, they're decoration, not edge.

## Acceptance (the gate)
- Raw-signal conditional expectancy is positive with a CI that clears costs **before** any sweep.
- The where-it-works regime/session slice is documented (feeds the sweep's search space, not a blind grid).
- Gates demonstrably remove negative-expectancy signals (selectivity funnel), or are flagged as inert.
- **If the autopsy fails, the idea is killed here — sweeping is skipped.**

Tooling: `research/mastervp_parity/MasterVP_End_to_End.ipynb` (§ edge autopsy). Run in `kenkem`.
Next (only if it passes): `/quant-7-backtest` → `/quant-8-sensitivity`. See `docs/KENKEM_QUANT_OS.md` §5.
