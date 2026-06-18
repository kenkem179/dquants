# dquants Layer-4 MQL5 codebase

Production MQL5, generated from the validated C++ engines (the single source of truth — `cpp_core/`).
Clean separation: **common / family / per-entry / EA shell**. Compiles headlessly via
`scripts/compile_mql5.sh <file.mq5>` (wine64 + MetaEditor).

```
experts/
  KK-Common/                  cross-family, reusable by ALL strategies
    Indicators.mqh            KKBuf — single-value buffer read
    Sizing.mqh                KKPositionSize (risk-correct), KKMinStopDist, KKClampStops
    PositionManager.mqh       KKManagePosition — partial-TP -> breakeven -> chandelier trail
  KenKem/                     the KenKem FAMILY (shares EMA/DMI/ATR/RSI/Ichimoku)
    Inputs.mqh                input schema (defaults = best_kenkem_btc.set)
    State.mqh                 shared globals + decision-time Snap struct
    Indicators.mqh            handle set + accessors (off-entries create zero handles)
    Snapshot.mqh              BuildSnap + sideways score + ATR percentile
    Gates.mqh                 EmasReady, TrendCore hard-gate, HTF filter
    Entries/                  ONE file per entry: trigger + gate + SL anchor + RR + mgmt
      E1.mqh  E2.mqh  E4.mqh  E5.mqh
    Engine.mqh                OnInit/OnTick, trigger update, first-match dispatch, sizing, manage
  KK-KenKem/
    KK-KenKem.mq5             thin EA shell (2 #includes) — compiles 0 errors / 0 warnings
```

## Compile / deploy
```
scripts/compile_mql5.sh mql5/experts/KK-KenKem/KK-KenKem.mq5
```
The compiler resolves `<Trade/...>` from the MT5 install and the relative `"../KenKem/..."` /
`"../KK-Common/..."` includes from this tree (symlinked into the wine MT5 `Experts/dquants`).

## Status
- **KK-KenKem (E1/E2/E4/E5): compiles clean.** Validated 2026 true-OOS: BTC E1+E4+E5 PF 1.145 (E4-only
  1.239); XAU E4+E5 PF 1.132. Params: `research/optimization/best_kenkem_{btc,xau}.set`.
- The **VP family** (MasterVP / Monster) are future siblings that will reuse `KK-Common/` (sizing,
  position manager, indicators) + their own `VolumeProfile` modules.
- Final gate before live: demo forward-test.
