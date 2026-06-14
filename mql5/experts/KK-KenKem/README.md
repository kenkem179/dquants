# KK-KenKem — dquants production EA (E5 promoted)

This is the **first end-to-end deploy** out of the dquants pipeline: the distilled `kk::kenkem` C++
engine (the validated source of truth) transcribed to a thin MQL5 EA, configured to the promoted
**E5-only ("SuperBros" M1 EMA-stack alignment)** edge.

## Where to find it in MetaTrader 5 (no symlink confusion)

The MT5 terminal sees this folder via a single symlink created for dquants:

```
MQL5/Experts/dquants  ->  /Users/tokyotechies/Workspace/KEM/dquants/mql5/experts
```

So in the MT5 Navigator everything from this repo lives under **`Experts/dquants/`** — separate from the
`../kenkem` strategies (KK-Common, KK-MasterVP, KenKem, …) which are their own symlinks. Open:

```
Navigator → Expert Advisors → dquants → KK-KenKem → KK-KenKem
```

## How to run

1. Attach **KK-KenKem** to a **BTCUSD M1** (or **XAUUSD M1**) chart, or open Strategy Tester.
2. Strategy Tester → Inputs → **Load** one of the per-symbol configs in this folder:
   - `KK-KenKem-E5-BTCUSD.set`
   - `KK-KenKem-E5-XAUUSD.set`
   - (Attaching with **no .set** uses the baked-in defaults = the BTCUSD E5 config.)
3. Run on M1. The EA is a thin `OnTick()` shell; all logic is in `experts/KenKem/` + `experts/KK-Common/`.

## Validated performance (kk::kenkem engine, 2026 true out-of-sample, 2% fixed-fraction on $10k)

| Symbol, TF | Settings | Net | PF | Recovery | MaxDD | Sharpe | Trades/day |
|---|---|---|---|---|---|---|---|
| BTCUSD M1 | E5 only · native trail+partial ON · ProfitManager OFF | +72,888 | 1.792 | 29.4 | 2,482 | 17.7 | 12.8 |
| XAUUSD M1 | E5 only · native trail+partial ON · ProfitManager OFF | +28,373 | 1.619 | 24.4 | 1,163 | 10.8 | 7.1 |

Each `.set` carries a distinct magic (BTC 4242410, XAU 4242411) so both can run on one account.

## Important: backtest parity is on the C++ engine, not the MT5 tester

Per the dquants doctrine, research **never** runs in the MT5 Strategy Tester — the C++ engine is the
authoritative backtest and the EA is a 1:1 transcription. The numbers above come from the C++ engine on
imported tick→M1 bars (BID + modelled spread, adverse-first intra-bar fill). The remaining Phase-10 step
before live capital is a **one-off MT5-tester vs C++ parity diff** on a short window to confirm the
transcription matches; treat live forward-testing on demo as the final gate.

## Provenance

- Engine: `cpp_core/include/kk/kenkem/*.hpp`
- Locked configs: `research/optimization/best_kenkem_{btc,xau}.set` (= `best_tuned_e5_{btc,xau}`)
- Full study + 9-column comparison: `research/optimization/KENKEM-RESULTS.md`
