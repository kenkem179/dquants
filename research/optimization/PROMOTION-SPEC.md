# Production promotion — #1 strategy → MQL5

## Recommendation: KenKem-distilled **E4** (Ichimoku Tenkan/Kijun cross), BTC primary / XAU secondary

Chosen over Monster-XAU (higher raw PF but 2-month same-year OOS) and MasterVP (MT5-proven but weakest
edge) because it has the **most rigorous OOS** (full fresh year 2026 H1, PF 1.239), the **best robustness**
(MC 100% profitable, P5 PF 1.164; survives 3× spread), and the **simplest logic** (one entry) → the most
auditable "zero-mistake" production code. See `KENKEM-RESULTS.md`.

## What "promote" means here
The distilled engine differs from the existing `KenKemExpert.mq5` (risk-correct sizing, stripped gates,
distilled SL/TP). So promotion = a NEW thin EA that mirrors `kk::kenkem` E4 **exactly**, built on
KK-MasterVP's proven broker/risk plumbing. Deliver a new `KK-KenKemE4/` package in the kenkem repo
(non-destructive — does not touch the existing EA).

## Exact transcription map (C++ header → MQL5)
Target chart: **M1**. TFs: M1/M3/M5/M15. ENTRY_SHIFT=1 (read last closed bar). One new M1 bar = one
detection; manage every tick.

| Concern | C++ source | MQL5 |
|---|---|---|
| EMA0..4 = 10/25/71/97/192, PRICE_CLOSE, MODE_EMA, per TF | `tf_cache.hpp` | `iMA` handles [TF][ema] |
| ADX/DI(14) per TF; ADX(9) M1 | `tf_cache.hpp` (dmi_adx_mt5) | `iADX` (MT5 native = matches dmi_adx_mt5) |
| ATR(14) M1; RSI(14) M1 | `tf_cache.hpp` | `iATR` / `iRSI` |
| Ichimoku(9/26/52) M1+M3 | `indicators.hpp` | `iIchimoku`; **E4 "cloud" = buffers 0/1 = Tenkan/Kijun** |
| Snapshot (all reads shift 1) | `snapshot.hpp` | `CopyBuffer(...,ENTRY_SHIFT,1,...)` |
| Sideways score 0-100 | `snapshot.hpp::sideways_score` | port verbatim |
| Trend hard-gate (ADX/DI/MTF) | `gates.hpp::trend_core_score` | port verbatim |
| HTF filter (E4 = M5-or-M15) | `gates.hpp::htf_filter_ok` | port verbatim |
| E4 trigger = TK cross (M1∧M3 flip) | `triggers.hpp::update_triggers` | port; persist `lastIchiCloudCross{Up,Down}` |
| E4 detect + gate (ADX≥min, cloud green, thickness) | `entries.hpp::entry_gate_ok kind 4` | port |
| SL = structure∓SL_EMA_DISTANCE, ATR cap/floor | `entries.hpp::compute_sl` | port |
| TP = entry ± RR·risk (E4_RR / E4_RR_SHORT; sideway switch) | `entries.hpp::compute_tp` | port |
| **Sizing = riskUSD/(riskPrice·valuePerPricePerLot)** | `trade_manager.hpp::position_size` | use KK-MasterVP `RiskManager` style |
| Manage: partial→BE→chandelier trail | `trade_manager.hpp::manage_tick` | port; SL/TP via `OrderModify`/broker stops |

## Params to ship
`best_kenkem_btc.set` / `best_kenkem_xau.set` → translate to the new EA's input names. Winner is
**E4-only** (ENABLE_E1=ENABLE_E2=false). Key BTC values: MIN_MOMENTUM_ADX≈26, E4_RR≈1.70,
E4_RR_SHORT≈1.64, E4_MAX_CROSS_AGE=38, E4_ATR_SL_CAP≈2.06, SL_EMA_DISTANCE=10,
E4_TRAILING≈0.27, E4_PARTIAL_TP_TRIGGER≈0.53, E4_HTF_MIN_ADX≈18, SIDEWAYS_BLOCK=53.

## Zero-mistake broker/risk checklist (mirror KK-MasterVP `Utils/BrokerHelpers.mqh` + `TradeManagement/`)
- Normalize lot to `SYMBOL_VOLUME_STEP`/`MIN`/`MAX`; price to `SYMBOL_DIGITS`; respect `SYMBOL_TRADE_STOPS_LEVEL`/`FREEZE_LEVEL`.
- Per-symbol pip/contract from `SymbolInfo*` (BTC pip=1/contract=1; gold pip=10⁻ᵈⁱᵍⁱᵗˢ) — already in the existing EA OnInit.
- `OrderSend` with ret/requote retries (reuse existing helper); verify fill; set SL/TP atomically or via retried `PositionModify`.
- Sizing caps: per-trade risk ratio + max concurrent + block-opposite; never exceed free margin.
- Spread guard at entry (skip if spread > budget); slippage tolerance on market orders.
- Add the non-destructive `Parity/` export hooks (default OFF) so a future C++↔MT5 cross-check is possible.

## Final gate (human-in-the-loop)
Compile via kenkem `make compile EA=KK-KenKemE4.mq5`; run Strategy Tester on BTCUSD M1 2026 to confirm
the C++ result reproduces (±costs); then **demo forward-test** before any live capital.
