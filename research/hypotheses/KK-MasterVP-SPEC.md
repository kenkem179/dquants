# KK-MasterVP — Implementation Spec (port target)

> Phase 6 deliverable, reframed: this formalizes the **existing** KK-MasterVP strategy as the contract
> for the C++/Python tick backtester. Source of truth = the **MQL5 EA** at
> `KEM/kenkem/MQL5/Experts/KK-MasterVP/` (the deployment target), cross-checked against the Pine
> `KEM/kenkem-pine/kk-vp/KK-MasterVP.pine`. Where they differ, **the MQL5 wins** (it's what ships).

## 0. Critical reconciliation — MQL5 ≠ Pine

The strategy notes (`notes/strategies/KK-MasterVP.md`) describe the **Pine**: fresh-cross arming +
multi-TF M1/M3/M5 net-tick-volume 80% gates + 4 reversion variants. The **deployed MQL5 base EA is
re-architected** and is what we port:

| Aspect | Pine (notes) | **MQL5 base EA (port this)** |
|---|---|---|
| Entry trigger | fresh `crossover(close, mVAH/mVAL)` armed ≤6 bars | **windowed break** of VAH (long) / VAL (short), bidirectional |
| Confirmation | multi-TF net tick volume ≥0.80 (M1/M3/M5) | **ADX/DI regime** + **node-state absorption gate** (no multi-TF net engine in base) |
| Reversion | 4 variants, ON | touch-of-VAL + rejection candle, **OFF by default** |
| Extra gates | — | MTF M15-EMA agreement (ON), RSI-50 veto (ON) |

The multi-TF net engine lives only in **KK-MasterVP-Monster** (`Core/NetVolume.mqh`) — phase 2 target.

## 1. Runtime shape

- **Symbol/TF:** XAUUSD (also BTCUSD), chart TF **M1 or M3** (`g_tf`). All session times **UTC**
  (the strategy evaluates session windows directly in UTC; our tick data is already UTC).
- **One position at a time** (netting, no pyramiding/hedging). Magic `88200531`.
- **Decision cadence:** all signal/VP/node work runs **once per just-closed bar**; position management
  (TP1/BE/trail) runs **every tick**. Entry fills next tick after the signal bar closes. No lookahead.
- **Warmup:** `max(InpEmaSlow=194, masterLen=150, volRR?101) + 3` bars.

`OnTick` pipeline (`KK-MasterVP.mq5:140`): manage open pos → (retest fill) → new-bar gate → seed day
equity → session state → force-close if out-of-session/news → compute master VP (+local if reversion)
→ update node engine → compute regime → `DetectSignal` → quality gate → safety gate + flat check →
size lot → `OpenTrade`.

## 2. Volume Profile  (`Core/VolumeProfile.mqh`)

`ComputeVP(len, bins, vaPct, startShift)` over `len` bars ending at `startShift`:
- Range `[lo,hi]` = min low / max high over the window; `step = (hi-lo)/bins`.
- **Stage A (default, `InpVpFeedMode=0`):** each bar drops its **whole `tick_volume`** into the single
  bin containing its **hlc3** = `(H+L+C)/3`. *(Our M1/M3 `tick_count` == MT5 tick_volume — exact.)*
- **Stage B (`=1`):** real ticks binned by price (`last`, else mid) weighted by tick volume. *(We have
  the ticks → can reproduce production fidelity.)*
- **POC/VAH/VAL** (`BuildVAFromHist`): POC = max-volume bin center. Grow the value area from the POC
  bin outward, each step adding whichever neighbor bin has more volume (**ties → high side**), until
  accumulated ≥ `vaPct%` of total. `VAH = lo+(hiIdx+1)·step`, `VAL = lo+loIdx·step`,
  `POC = lo+(pocIdx+0.5)·step`.
- **Master profile** = `len = InpVpLookback·InpMasterMult = 50·3 = 150` bars. **Local** = 50 bars
  (only used by reversion).

> Already implemented and tested in `pipeline/indicators.py::volume_profile_levels` (same expand-from-
> POC, ties-high algorithm) — reuse it, swap the windowing to rolling-150-bar.

## 3. Node-state engine  (`Core/NodeStateEngine.mqh`) — synthetic order flow

Three per-bin arrays (`nodeBuy/nodeSell/nodeTouch`, size `InpVpBins`) over the **sliding** master
`[lo,hi]` grid. Updated once per closed bar with shift-1 bar:
- **Decay all bins** by `InpNodeDecay = 0.94` (~11-bar half-life).
- `dirProxy = (C-O)/max(H-L, mintick)`; `buyProxy = vol·max(dirProxy,0)`, `sellProxy = vol·max(-dirProxy,0)`.
- `touchDist = max(InpNodeTouchAtr·ATR, 2·pip)` (pip = 0.01 XAU). For each bin in `[lowIdx..highIdx]`
  spanned by the bar: if `|C - binPx| ≤ touchDist` OR bin price ∈ `[L,H]` → `touch += 1`,
  `buy += buyProxy/span`, `sell += sellProxy/span`.
- **State at a bin:** `net = (buy-sell)/max(buy+sell,1)`. **absorbed** if `touch ≥ InpNodeSaturation=4`
  AND `|net| ≤ InpNodeNeutralBand=0.15`. `state = absorbed?0 : net>0.15?+1 : net<-0.15?-1 : 0`.

## 4. Regime  (`Core/Regime.mqh`)  — read at shift 1

`trend = (ADX > 22) AND (|+DI - -DI| > 6) AND (|emaFast - emaSlow| > 0.25·ATR)`, else `balance`.
EMA fast=24, slow=194, ADX/DMI len=14 (all Wilder/MT5 — already in `pipeline/indicators.py`).

## 5. Entry  (`Entries/EntryVP.mqh::DetectSignal`) — FULLY BIDIRECTIONAL

The strategy trades **long AND short**, symmetrically. Two entry families (breakout, reversion), each
with a long and a short variant → 4 signal types. `enterLong = longBrk || longRev`,
`enterShort = shortBrk || shortRev`; never both in one bar.

**Shared inputs.** Signal bar OHLC at **shift 2** (`sO,sH,sL,sC`; `InpUsePriorBarVP=false`), ATR at
shift 2 (`atr2`). Levels = current master VP (`sVah,sVal`). `brkBuf=InpBreakBufAtr·atr2` (0.65),
`brkMax=InpBreakMaxAtr·atr2` (9 — at default this ceiling rarely binds, so the break is effectively
"beyond the edge by ≥0.65·ATR"; Pine's was 1.0), `touch=max(InpRetestAtr·atr2, 3·pip)`. Node reads:
`nsVah=NodeAtPrice(VAH)`, `nsVal=NodeAtPrice(VAL)`, `nsPx=NodeAtPrice(sC)`. Candle: `bodyPct=|sC-sO|/max(sH-sL,mintick)`,
`bullBody=(sC>sO & bodyPct≥InpBodyPctMin)`, `bearBody=(sC<sO & bodyPct≥…)`, wicks `upWick=sH-max(sO,sC)`,
`dnWick=min(sO,sC)-sL`.

### Breakout (`InpEnableBreakout=true`) — both require `regime.trend`

| Condition | **LONG** (`longBrk`) | **SHORT** (`shortBrk`) |
|---|---|---|
| Price trigger (windowed) | `sC > VAH+brkBuf` AND `sC ≤ VAH+brkMax` | `sC < VAL−brkBuf` AND `sC ≥ VAL−brkMax` |
| DI direction | `+DI > −DI` | `−DI > +DI` |
| Node gate (`InpNodeGateEnabled=true`) | `nsVah.absorbed OR nsVah.state ≥ 0` | `nsVal.absorbed OR nsVal.state ≤ 0` |
| Flow filter (`InpBrkRequireFlow` OFF) | `nsVah.net≥0.15 AND nsPx.net≥0.15` | `nsVal.net≤−0.15 AND nsPx.net≤−0.15` |
| Rejected-candle veto (`InpBrkVetoSfp` OFF) | NOT (`upWick>dnWick & upWick>bodyAbs`) | NOT (`dnWick>upWick & dnWick>bodyAbs`) |

### Reversion (`InpEnableReversion=false` by default) — both require `regime.balance`

Fades the *opposite* edge back into value. **Note the asymmetry vs breakout: reversion FORBIDS
absorbed nodes** (breakout allows them).

| Condition | **LONG** (`longRev`) | **SHORT** (`shortRev`) |
|---|---|---|
| Touch | `|sL − VAL| ≤ touch` (low at VAL) | `|sH − VAH| ≤ touch` (high at VAH) |
| Candle | `bullBody` | `bearBody` |
| Node gate | `!nsVal.absorbed AND nsVal.state ≥ 0` | `!nsVah.absorbed AND nsVah.state ≤ 0` |

### Economics (anchor = shift-1 close `entryClose`, `atr1`) — symmetric

`slAtrUse = isRev ? InpSlAtrRev(1.45) : InpSlAtrBrk(2.2)`; `rr = (isRev?InpRrRev(1.35):InpRrBrk(1.4))·rrScale`.

| | **LONG** | **SHORT** |
|---|---|---|
| SL | `entryClose − max(slAtrUse·atr1, 8·pip)`; if rev: `SL = min(SL, localLo − 4·pip)` | `entryClose + max(slAtrUse·atr1, 8·pip)`; if rev: `SL = max(SL, localHi + 4·pip)` |
| risk | `entryClose − SL` | `SL − entryClose` |
| TP1 | `entryClose + risk·InpTp1R(0.8)` | `entryClose − risk·InpTp1R` |
| TP2 | `entryClose + risk·rr` | `entryClose − risk·rr` |

Reject if `risk ≤ 0`. (Diagnostic features `fBrkDistAtr/fRunwayAtr/fNodeNet/fBodyPct/fAdx/fDiSpread`
are computed per side for the selectivity study — no trading effect.)

**Supplementary quality gates** (`QualityGateOk`, layered after detection):
- **MTF agree (`InpUseMtfAgree=true`, M15, hard veto):** HTF EMA-fast vs EMA-slow must agree with trade
  direction.
- **RSI veto (`InpUseMomVeto=true`, RSI14, mid=50):** long needs RSI≥50, short ≤50.
- (ATR-pctl gate OFF.)

## 6. Trade management  (`TradeManagement/TradeManager.mqh`) — every tick

- **TP1 partial:** trigger when `bid ≥ TP1` (long) / `ask ≤ TP1` (short); close `InpTp1ClosePct=20%`
  of initial volume.
- **BE after TP1 (`InpBeAfterTp1=true`):** move SL to `entry + InpBeBufAtr·atr1` (long) /
  `entry − InpBeBufAtr·atr1` (short), 0.05.
- **Runner trail (`InpTrailRunner=true`, DEFAULT ON — critical):** the order's TP2 is opened at a far
  `InpRunnerRr=10`·R backstop (NOT the 1.4·R cap); after TP1 a **chandelier stop** ratchets to
  `bestPrice ∓ InpTrailAtrMult·ATR` (3.6), only ever tightening. **This is what captures the right
  tail** — directly relevant to the "edge is tail-carried" finding.
- (Retest-fill `InpUseRetestFill` OFF — EA-only, diverges from "enter next bar".)

## 7. Risk & filters

- **Sizing:** `budget = balance·InpRiskAccPct%/100` (0.9%); `lot = budget/(stopDist·valuePerPricePerLot)`,
  `valuePerPricePerLot = tickValue/tickSize` (XAU: = contractSize 100). Normalized to broker steps.
- **Daily-DD breaker (`InpMaxDailyDDPct=6`, predictive):** block entry if
  `(dayStartEquity - equity + riskBudget)/dayStartEquity·100 ≥ 6`. Day resets on UTC date change.
- **Peak-DD halt (22) / soft-block (15→×0.55) / loss-streak cooldown (3 losses→4h) / daily-DD
  cooldown (12h):** EA-only risk layers (not in Pine).
- **Sessions (UTC):** Asia 00:00–06:00, London 07:00–11:00, NY 12:30–16:30. **Blocked hours**
  `8,10,11,16`. Out-of-session ⇒ no entry + force-close. `InpMaxTradesPerSession=4`.
- **ATR% band:** entry only if `0.0156 ≤ ATR/price·100 ≤ 0.158`.
- **Spread gates** (`InpMaxSpreadPips`, `InpMaxSpreadTp1Frac=0.25`) and **news** (high-impact USD,
  ±15 min) — EA-side. *Parity caveat: news needs an economic calendar; v1 backtest can disable it and
  note the difference.*

## 8. Default parameters (the optimization surface)

| Group | Params (default) |
|---|---|
| VP core | bins 30, vaPct 70, lookback 50, masterMult 3, nodeDecay 0.94, nodeNeutral 0.15, nodeSat 4, touchAtr 0.05 |
| Regime | emaFast 24, emaSlow 194, adxLen 14, adxTrendMin 22, diSpreadMin 6, emaSepAtr 0.25 |
| Breakout | breakBufAtr 0.65, breakMaxAtr 9, rrBrk 1.4, slAtrBrk 2.2 |
| Exit | tp1R 0.8, tp1Close% 20, beBufAtr 0.05, trailRunner ON, runnerRr 10, trailAtrMult 3.6 |
| Risk | riskAccPct 0.9, maxDailyDD 6, peakDD 22, softBlock 15/0.55, lossStreak 3/4h |
| Gates | mtfAgree ON (M15, hard), momVeto ON (RSI14/50), nodeGate ON |
| Sessions | Asia 00-06, Ldn 07-11, NY 12:30-16:30, blocked 8/10/11/16, maxTrades 4 |

## 9. C++ port plan & parity strategy

**Module → C++ class map** (the MQL5 modularity ports ~1:1):
`VolumeProfile.mqh`→`VolumeProfile`, `NodeStateEngine.mqh`→`NodeEngine`, `Regime.mqh`+`Indicators.mqh`→
`Regime`/`Indicators`, `EntryVP.mqh`→`Strategy::DetectSignal`, `TradeManager.mqh`→`PositionManager`,
`RiskManager.mqh`→`RiskManager`, sessions/news→`Filters`. `TickEngine` replays Parquet ticks →
builds M1/M3 bars → drives the above → `ExecutionSimulator` (spread/slippage/commission).

**Parity methodology — three levels, identical schemas, diff (bar-level FIRST).** The C++ engine
emits **byte-compatible CSVs** to the MQL exporters (same column order, `DoubleToString(.,3)` rounding,
`YYYY.MM.DD HH:MM` timestamps) so a plain diff works:

1. **Per-bar computation** (`parity_*.csv`, `ParityExport.mqh`): poc/vah/val/mpoc/mvah/mval,
   trend/plus/minus/adx/atr1, sigValid/long/rev/entry/sl/tp1/tp2. Proves the *math* matches
   independent of trading — **diff this first**; it pinpoints the exact bar + column that diverges
   before any trade exists. This is the primary tool.
2. **Per-trade** (`trades_*.csv`, `TradeJournal.mqh`): entry/dir/sl/tp/mfeR/maeR/realized/exitTag —
   catches execution & management (TP1 partial, trail, BE, fills).
3. **Aggregate**: PF/trade-count/net (target **1.21 TRAIN / 1.10 OOS**) — headline only, weak for debug.

**Rules that make it rigorous:** (a) compare with **tolerance, not bytes** — FP order + MT5's Wilder
SMA-seed vs our ewm-seed differ on warmup; the 3-decimal CSV rounding quantizes FP noise; discard
warmup; flag *systematic* vs last-digit divergence. (b) **Verify bars match before strategy** — if
`vah`/`adx` already differ at Level 1, the bug is bar-construction/indicator-seeding (the TV-vs-MT5
class), not the logic; feed the engine the *same ticks* and run the tester in "every tick based on real
ticks". (c) **Deterministic parity mode** — identical news CSV, fixed spread, no realtime-only gates,
so the only possible difference is strategy logic; re-enable extras one at a time. (d) **Golden test** —
freeze ~1 day of `parity_*.csv` as a C++ unit test so faithfulness becomes a `make test` regression
guard, not a one-off check.

**Known parity risks to control:** (1) tick_volume vs our tick_count (should match exactly); (2)
MT5 iATR/iADX seeding vs our Wilder seed — discard warmup; (3) news calendar (disable for v1 parity);
(4) fill model (next-tick vs MT5 bar-open) — match MT5 tester's fill assumptions; (5) the node grid
*slides* every bar — replicate, don't "fix".

**Level-1 results (BTCUSD M3, 2026-04-09, 480 rows; `cpp_core/tools/common/validate_parity_py.py`):**
master VP <0.001, ADX/+DI/-DI <0.005, regime trend **100%**. Two hard-won facts:
- **`iADX` ≠ Wilder.** MT5's `iADX` handle (what the EA uses, *not* `iADXWilder`) computes per-bar
  `100·DM/TR` then smooths `+DI`/`-DI`/`DX` with **EMA k=2/(n+1)**; DM-zeroing clamps negatives then
  the strictly-greater wins (ties→both 0). Textbook Wilder put `-DI` off by ~10 pts. → C++
  `kk::ind::dmi_adx_mt5` (golden `test_dmi_mt5_golden`); regime/signal must consume it, not `dmi_adx`.
- **ATR is not dollar-matchable from the CSV.** Matches on average (ratio mean 0.9986) but diverges on
  vol spikes — the tester's tick model captures wider intrabar extremes than the exported tick CSV.
  VP (window-extreme) and ADX (ratio) are robust; ATR is scale-sensitive. Accept the caveat; expect
  small SL/TP/breakout-distance differences on spike bars at trade level.
