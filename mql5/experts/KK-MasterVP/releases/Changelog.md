# KK-MasterVP — Changelog

## 1.07 — 2026-06-26

- Built `2026-06-26T14:03:32Z` · commit `c64a34e` on `2-stabilization`
- EA: `KK-MasterVP-1.07.ex5` (locked build of `KK-MasterVP.mq5`)
- XAU M5 lock: add ProgTrail late-arm ladder (Trigger 2.0R/Inc 0.75/Step 0.2). MT5 full-run PF 1.4127->1.4246 (+3.4% net), 2026 1.4372->1.4581; gate DSR 1.000 PASS. Ladder baked as compiled defaults (hidden globals).
- Variants: `xauusd-m5` `btcusd-m5` `xauusd-m5-prop` `btcusd-m5-prop` `xauusd-m5-mixed-fn`

## 1.06 — 2026-06-25

- Built `2026-06-25T15:51:56Z` · commit `71da7fe` on `UTC-time-fix`
- EA: `KK-MasterVP-1.06.ex5` (locked build of `KK-MasterVP.mq5`)
- Fix MQL5 Market validation: guard SL/TP modify against broker stop/freeze level (skip when SL/TP within max(stops,freeze,spread); floor 10pt) - prevents 'modification failed ... close to market' on EURUSD and other 0-stops-level symbols. XAU lock unchanged.
- Variants: `xauusd-m5` `btcusd-m5` `xauusd-m5-prop` `btcusd-m5-prop` `xauusd-m5-mixed-fn`

## 1.05 — 2026-06-23

- Built `2026-06-23T10:22:16Z` · commit `51b63e6` on `reliableBaseline`
- EA: `KK-MasterVP-1.05.ex5` (locked build of `KK-MasterVP.mq5`)
- Add Mixed-Portfolio FN-Stellar2 $100K variant + per-trade CSV on all variants; fix MQL5-Market edition (missing ProfitManager InpPm* decls in Inputs.release.mqh)
- Variants: `xauusd-m5` `btcusd-m5` `xauusd-m5-prop` `btcusd-m5-prop` `xauusd-m5-mixed-fn`

## 1.04 — 2026-06-23

- Built `2026-06-23T06:47:10Z` · commit `3aa14e1` on `reliableBaseline`
- EA: `KK-MasterVP-1.04.ex5` (locked build of `KK-MasterVP.mq5`)
- Marketplace validation fix: skip entries when free margin is insufficient (no more No-money/not-enough-money failures on tiny-deposit validator runs)
- Variants: `xauusd-m5` `btcusd-m5` `xauusd-m5-prop` `btcusd-m5-prop`

## 1.03 — 2026-06-23

- Built `2026-06-23T06:33:17Z` · commit `0ddfc64` on `reliableBaseline`
- EA: `KK-MasterVP-1.03.ex5` (locked build of `KK-MasterVP.mq5`)
- Marketplace validation fix: clamp lots to SYMBOL_VOLUME_LIMIT + widen stop-distance by spread (no more Volume-limit-reached / Invalid-stops on validator symbols)
- Variants: `xauusd-m5` `btcusd-m5` `xauusd-m5-prop` `btcusd-m5-prop`

## 1.02 — 2026-06-23

- Built `2026-06-23T06:22:56Z` · commit `66b34b1` on `reliableBaseline`
- EA: `KK-MasterVP-1.02.ex5` (locked build of `KK-MasterVP.mq5`)
- Add MQL5-Market edition (internals hidden); XAU M5 locked defaults
- Variants: `xauusd-m5` `btcusd-m5` `xauusd-m5-prop` `btcusd-m5-prop`

## 1.01 — 2026-06-21

- Built `2026-06-21T23:00:00Z` · commit `8303652` on `reliableBaseline`
- EA: `KK-MasterVP-1.01.ex5` (locked build of `KK-MasterVP.mq5`)
- Re-cut with updated prop variant: firm limits Max daily loss 4.4% (InpMaxDailyDDPct=4.4) + Max account drawdown 9% (InpMaxPeakDDPct=9.0). Locked configs unchanged: XAU M5 LOCKED + BTC M5; personal as-swept.
- Variants: `xauusd-m5` `btcusd-m5` `xauusd-m5-prop` `btcusd-m5-prop`

