# KK-MasterVP — Strategy Description

> Tick-volume-profile scalper for XAUUSD/BTCUSD, specialized in M3. Builds a rolling local (50-bar) and master (150-bar) volume profile (POC/VAH/VAL), arms entries off a FRESH cross of a master level (cross consumed on entry), and confirms with multi-timeframe near-price net tick volume (M1/M3/M5). Two entry families: breakout beyond the master value-area edge, and a 4-variant mean-reversion fade back into value. Core edge hypothesis: a fresh break of (or excursion past) a master VP level, backed by >=80% one-sided near-price tick flow on at least one fast TF and not opposed >80% on M3/M5, has directional follow-through worth 1.5R-3R.

## 1. Overview

- **Instruments:** XAUUSD and BTCUSD (CFD tick-volume feeds). Nothing symbol-specific is hardcoded; sizing uses `syminfo.pointvalue`.
- **Timeframe:** M3 is the chart/entry TF. The script hard-blocks any chart TF other than 30s, M1, M3, M5, M15 (`validTf` check; invalid TF paints red background and vetoes entries).
- **Style:** intraday scalper, long and short, stacking allowed (one trade per fresh master-level cross, capped per direction), each entry carries its own SL/TP bracket.
- **Source file (truth):** `kenkem-pine/kk-vp/KK-MasterVP.pine` (Pine v6 `strategy()`, ~1140 lines).
- **Strategy declaration:** `pyramiding=20`, initial capital 10,000 USD, commission `cash_per_order` 0.50, slippage 8 ticks, `calc_on_every_tick=true`, `process_orders_on_close=false`, `use_bar_magnifier=true`, margin 0.5% both sides.
- **Relation to other variants:** unrelated to KenKem classic (EMA-structure scalper). KK-MasterVP-Monster is the active evolution (adds impulse-thrust entries, predicted POC, opt-in regime gates); this file is the stable base.
- **MQL5 EA port:** `kenkem/MQL5/Experts/KK-MasterVP/` — modular port, compiles 0/0, quant-review PASS-WITH-EDITS, Stage-A bar-parity backtest not yet run. Neither variant has cleared the deploy gate.

## 2. Market Context / Regime Detection

### 2.1 Volume profile (local + master)

Single function `f_vp(_len, _bins, _vaPct)` run twice per bar:

- **Local profile:** lookback 50 bars (`vpLookback`), 40 bins (`vpBins`), value area 70% (`vaPct`). All three are hidden consts, not inputs.
- **Master profile:** lookback 50 x 3 = 150 bars (`masterMult = 3`), same 40 bins, same 70% VA.

Construction:
- Price range = `ta.highest(high, len)` − `ta.lowest(low, len)`; row height = range / 40.
- Each of the last `len` bars contributes its **entire `volume`** to the single bin containing its `hlc3` (no intra-bar volume spreading).
- **POC** = center of the max-volume bin.
- **Value area:** expand from the POC bin outward, each step adding whichever neighbor bin has more volume (`nextH >= nextL` — high side wins ties), until accumulated volume `>= 70%` of total. **VAH** = top edge of the highest included bin; **VAL** = bottom edge of the lowest included bin.

This produces `poc/vah/val` (local) and `mPoc/mVah/mVal` (master). All recompute every bar — the profile is rolling, so levels drift.

**Operational note — local profile is inert in breakout-only mode (measured, C++ engine).** Although both profiles are computed every bar, the breakout entry (kind 1 — the only family enabled in the deployed lock) triggers **entirely off the MASTER value-area edges** (`mVah`/`mVal`), never the local profile and never the POC line itself. The local `poc/vah/val` are consumed only by the breakout's local-VA alignment check (a loose `<= mVah + 0.1·ATR` tolerance, section 3) and by the reversion families' entry/SL geometry. With reversion OFF, the local profile contributes **zero signal** — proven empirically: sweeping local lookback from 60→240 bars with the master length fixed yields byte-identical backtests (`research/mastervp_parity/VP_LENGTH_STUDY.md`). So in breakout mode the single tuned degree of freedom is the **master length** (in bars), and "master POC" is really shorthand for the master **value-area boundary**, not the peak-volume node. Reviving the dead local VP (plus an HTF M5/M15 VP) as a breakout *agreement gate* is an open, unrealized enrichment idea — not something the current algorithm does.

### 2.2 Node state engine (synthetic order flow)

Per-bin `nodeBuy/nodeSell/nodeTouch` arrays over the **master** window grid (40 bins spanning the 150-bar high/low). Updated on confirmed bars only:

- All bins decay by `0.94` per bar (`nodeDecay`, ~11-bar half-life).
- Direction proxy: `dirProxy = (close − open) / max(high − low, mintick)`; `buyProxy = volume * max(dirProxy, 0)`, `sellProxy = volume * max(−dirProxy, 0)`.
- A bin is "touched" if `|close − binPx| <= touchDist` (touchDist = `max(0.05 * ATR, 2 * mintick)`) **or** the bin price sits inside the bar's low..high. Touched bins get touch +1 and the buy/sell proxies split equally across the touched span.
- Node state (`f_node_state`): `net = (buy − sell) / max(buy + sell, 1)`. **Absorbed/DEAD** if `touch >= 4.0` (`nodeSaturation`) AND `|net| <= 0.15` (`nodeNeutralBand`). Otherwise state = +1 if `net > 0.15`, −1 if `net < −0.15`, else 0.

**Important:** node states (BUY/SELL/DEAD tags on mPOC/mVAH/mVAL etc.) are **display diagnostics only** — they do not gate entries. The node arrays *do* feed the chart-TF net read (below).

### 2.3 Multi-TF near-price net tick volume (the actual confirmation engine)

Three reads, all in [−1, +1]:

- **M1 (`netM1c`) and M5 (`netM5c`):** `f_tfNetNear(50, 1.5)` via `request.security(..., lookahead=barmerge.lookahead_off)` returning the **prior completed bar's** value (`v[1]` inside the callback — repaint-safe, one-bar lagged on that TF). Over the last 50 bars of that TF, bars whose `hlc3` is within ±1.5 x ATR(14) of current close contribute `volume * body/range` to buy or sell; net = (buy − sell)/(buy + sell), 0 when total is 0.
- **M3 / chart TF (`netM3c`):** a **different computation** — `f_near_net_weighted` reads the *decayed node arrays* within ±1.5 x ATR of close and nets each bin's dominant side (`bv > sv` contributes `bv − sv` to buy, else to sell). Optional HVN/MED/LVN tier weighting (`useWeightedNet`, default OFF, experimental: tier > 0.66 of near-window max → weight 1.5, < 0.33 → 0.5, else 1.0).

So the chart-TF net carries decay memory while M1/M5 are flat 50-bar sums — an intentional but real asymmetry; the MQL port must replicate this exactly.

There is no separate regime classifier in this script. "Regime" is implicit: the volatility floor/ceiling (section 6), the M5 opposing-net veto, and session windows.

## 3. Entry Logic

### 3.0 Shared machinery

- **Fresh-cross arming:** `ta.crossover/crossunder` of `close` vs `mVah`, `mVal`, `mPoc` (six raw crosses, computed unconditionally every bar to keep ta-state clean). The cross bar index is recorded **only on confirmed bars**. A cross is *fresh* while `bar_index − crossIdx <= freshBars` (6 for both families). The index is **consumed (set na) on the matching entry** — one cross = at most one trade; a re-cross is required for the next.
- **Decision timing:** all signals evaluate on the confirmed bar (`barstate.isconfirmed`); `close` of that bar is the spec's "prev close". Orders fill next bar open. No look-ahead.
- **Shared net gates** (breakout values shown; reversion uses its own identical-default inputs):
  - Confirming: `netLongOk = (netM1c >= 0.80) or (netM3c >= 0.80)` — EITHER M1 or M3 (`brkNetMin`/`revNetMin` = 0.80).
  - Opposing veto: `oppLongOk = (netM3c > −0.80) and (na(netM5c) or netM5c > −0.80)` — blocked if M3 **or** M5 opposes by more than 0.80 (`brkOppMax`/`revOppMax`). Shorts mirror with signs flipped.
- **Level validity:** all six levels non-na (`lvlsOk`), `risk > 0` required everywhere.
- **One pick per direction per bar:** breakout preferred; otherwise the eligible reversion variant with the higher computed RR (variant 1 wins ties via `>=`).
- **Stacking:** `pyramiding=20` at the engine level, but effective cap = `maxConcurrentPerDir` (default 3) open trades per direction, and no hedging — longs require `strategy.position_size >= 0`, shorts `<= 0`.

ATR everywhere below = `ta.atr(14)` on the chart TF.

### Breakout — fresh master VAH/VAL break (kind 1)

Long (`sigBrkL`), all required:
1. `enableBreakout` ON (default ON) and `lvlsOk`.
2. Fresh `close x mVah` upward cross within 6 bars (`brkFreshBars`).
3. Local-VA alignment: `vah <= mVah + 0.1 * ATR` (`brkLocalTolAtr`) — local value area must not sit above the master edge.
4. Entry distance: `close >= mVah + 1.0 * ATR` (`brkEntryBufAtr`) — a full ATR beyond the edge. **Alternative path** (only when `brkBigCandle` ON, default OFF): `close >= mVah` AND `close > open` AND `(high − low) > 1.0 * ATR` (`brkBigCandleAtr`).
5. Net confirmation: M1 or M3 net `>= 0.80` long.
6. Opposing veto: M3 and M5 net `> −0.80`.
7. `riskBrkL > 0`.

SL/TP (long):
- `SL = min(mVah − 0.2 * ATR, close − 2.0 * ATR)` (`brkSlBufAtr` = 0.2, `brkSlAtrMult` = 2.0).
- `TP = close + RR * (close − SL)`; RR = **2.0** (`brkRrNear`) if a same-direction entry occurred within the last 25 bars (`brkRrLookbackBars`), else **3.0** (`brkRrFar`). Note: `lastLongEntryBar` is stamped by **any** long entry (breakout or reversion), not just breakout entries, despite the input tooltip saying "same-direction breakout entry".

Short mirrors exactly: fresh `close x mVal` down-cross, `val >= mVal − 0.1 * ATR`, `close <= mVal − 1.0 * ATR`, `SL = max(mVal + 0.2 * ATR, close + 2.0 * ATR)`.

### Mean Reversion — variant 1: master POC cross, VAH/VAL-family TP (kind 2)

Long (`sigRevL1`), all required:
1. `enableReversion` ON (default ON), `lvlsOk`.
2. Fresh `close x mPoc` upward cross within 6 bars (`revFreshBars`).
3. Entry distance: `close >= max(mPoc + 0.06 * ATR, poc) + 1.0 * ATR` (`revAnchorOffAtr` = 0.06, `revEntryDistAtr` = 1.0) — i.e. price has run a full ATR past the higher of (offset master POC, local POC).
4. Net confirmation / opposing veto as above (`revNetMin`/`revOppMax` = 0.80).
5. `SL = min(close − 2.0 * ATR, max(mPoc + 0.1 * ATR, poc) − 0.2 * ATR)` (`revSlAtrMult` = 2.0, `revPocSlOffAtr` = 0.1, `revSlBufAtr` = 0.2).
6. `TP = mVah` if `mVah > vah + ATR`, else `max(mVah, vah)`.
7. `TP > close` and computed `RR = (TP − close)/(close − SL) >= 1.5` (`revMinRR`).

Short mirror: fresh `close x mPoc` down-cross, `close <= min(mPoc − 0.06 * ATR, poc) − 1.0 * ATR`, TP at `mVal`/`min(mVal, val)` family.

Despite the "mean-reversion" group name, variants fade *toward the next VP level above/below*: this variant is effectively a value-area rotation trade from POC toward VAH (long) / VAL (short) — it enters **with** the direction of the cross.

### Mean Reversion — variant 2: master VAL/VAH cross, POC-family TP (kind 3)

Long (`sigRevL2`): fresh `close x mVal` **upward** cross (price re-entering value from below), `close >= max(mVal + 0.06 * ATR, val) + 1.0 * ATR`, same net gates, `SL = min(close − 2.0 * ATR, max(mVal + 0.06 * ATR, val) − 0.2 * ATR)`, `TP = mPoc` if `mPoc > poc + ATR` else `max(mPoc, poc)`, `RR >= 1.5`.

Short mirror: fresh `close x mVah` **downward** cross, target the POC family from above.

The header's "4-variant mean-reversion" = {POC-cross, edge-cross} x {long, short}.

## 4. Exit & Trade Management

Each entry gets its **own** bracket (per-entry registry arrays track SL/TP1/TP2/peak/runner-stop per open trade ID):

- **Base bracket:** fixed `stop=SL`, `limit=TP2` (`strategy.exit(eid+"r")`), placed at entry.
- **TP1 partial** (`useTp1Partial`, default ON): a second exit closes a percentage of the entry at `TP1 = entry +/- 1.0R` (`tp1Rr` = 1.0, R = stop distance). Close % is per-family: 20% breakout (`tp1CloseBrk`), 20% reversion (`tp1CloseRev`). Same SL on both legs.
- **Break-even after TP1** (`enableBeAfterTp1`, default ON, requires TP1 partial): once the bar's high (long) / low (short) touches TP1, the runner's stop is pulled to `entry +/- 0.05 * ATR` (`beBufAtr`, hidden const). Monotonic — the stop only ever tightens (`math.max` ratchet for longs).
- **Chandelier runner trail** (`trailRunner`, default OFF, requires TP1 partial): after TP1, the runner's stop ratchets to `peak −/+ 3.6 * ATR` (`trailAtrMult`); TP2 was set at entry to a far `10R` backstop (`runnerRr`) instead of the spec fixed/POC target. When OFF, TP2 stays the per-path target from section 3.
- **Net-volume flush early-exit** (`enableEarlyExit`, default OFF): closes the **entire position** (`strategy.close_all`) when opposing net `>= 0.80` (`exitNetMin`) on (M1 AND M3) or (M3 AND M5). A long exits on sell-flush; mirror for shorts.
- **Session/news force-close** (`forceCloseSessNews`, default ON): any open position is closed next bar open the moment price is out of every enabled session or a news window opens.

TP1-touch detection in the registry uses the live bar's high/low (`calc_on_every_tick=true`); on history `use_bar_magnifier=true` improves fill realism.

## 5. Risk Management

- **Position sizing** (`f_riskQty`): qty = `riskBudgetUSD / (stopDistance * pointvalue)`. Risk budget per `riskUnit` input (default **"% Account Balance"**): `1.6%` (`riskPerTradeAccPercent`) of `initial_capital + strategy.netprofit` (closed equity, not floating). Alternatives: fixed `180 USD` (`riskPerTradeUSD`), or Min/Max of the two.
- **Daily drawdown breaker** (`maxDailyDDPct`, default 6.0%): **predictive** — a new entry is refused when `(dayStartEquity − equity + riskBudgetUSD) / dayStartEquity * 100 >= 6.0`, i.e. the day's drop so far *plus this trade's worst-case loss* would reach the cap. `dayStartEquity` resets on each new UTC day (`varip`, uses `strategy.equity`). 0 disables. Blocks entries only; open positions keep their brackets.
- **Trade count cap:** `maxTradesPerSession` = 50 (hidden const, deliberately loose), reset per session change — or per UTC day when "Trade anytime" is ON.
- **Concurrency cap:** `maxConcurrentPerDir` = 3 (the real stacking limit). No hedging (see 3.0).
- **Volatility gates** (hidden consts, part of `safetyOk`): ATR%-of-price floor `atrPct >= 0.0156` and ceiling `atrPct <= 0.158` (`atrPct = ATR/close * 100`; ceiling 0 = disabled).
- **No loss-streak cooldown and no peak-equity DD trail in this Pine script.** Those layers exist in the MQL5 EA's `RiskManager` only — do not assume Pine/MQL parity here.
- Master kill-switch `allowTrading` is a hidden const (true).

## 6. Filters & Sessions

All times **UTC** (sessions are `input.session` strings evaluated on exchange time of the ticker; configured values below):

- **Asia** 0000–0600, **London** 0700–1100, **New York** 1230–1630 — each individually toggleable, all default ON.
- `tradeAnytime` (default OFF): ignores all session windows; entries allowed any hour; session force-close stops applying (news force-close still works); trade counter keys to UTC day.
- No day-of-week rules. Blocked-hours mechanism exists (`blockedHoursStr`) but is hardwired empty.
- **News avoidance** (`avoidNews`, default ON): `request.economic("US", ...)` for NONFARM, CPI, IR (rate), GDP, JC (jobless claims). Release minute-of-day is learned into 5 slots (deduped within ±2 min); new entries are blocked from 15 min before to 15 min after each learned slot (`newsMinsBefore`/`newsMinsAfter`). With force-close ON, open positions are also closed when a window opens. Caveat: a slot only exists after that event has printed at least once in the loaded history — early bars are unprotected.
- **Entry master gate** (`safetyOk`): kill-switch AND valid TF AND in-session AND ATR floor/ceiling AND session trade count AND not-in-news AND daily-DD not hit AND not blocked hour.
- No spread filter in Pine (costs are modeled via commission 0.50/order + 8 ticks slippage); spread handling is the EA's job.

## 7. Key Parameters

| Parameter | Default | What it does |
|---|---|---|
| `vpLookback` / `masterMult` / `vpBins` / `vaPct` | 50 / 3 / 40 / 70 (hidden) | Local profile = 50 bars, master = 150 bars, 40 price bins, 70% value area. |
| `atrLen` | 14 (hidden) | ATR period for every ATR-multiple in the script (chart TF). |
| `tfNetLook` | 50 | Bars each TF sums for near-price net tick volume. |
| `netWinAtr` | 1.5 | Half-width (ATR) of the near-price window for net-volume reads. |
| `brkFreshBars` / `revFreshBars` | 6 / 6 | Bars a master-level cross stays armed; consumed on entry. |
| `brkEntryBufAtr` | 1.0 | Long needs `close >= mVAH + 1.0 ATR` (mirror short at mVAL). |
| `brkLocalTolAtr` | 0.1 | Local VAH must be `<= mVAH + 0.1 ATR` for a long breakout. |
| `brkNetMin` / `revNetMin` | 0.80 | Min confirming near-price net on EITHER M1 or M3 (the "80% gate"). |
| `brkOppMax` / `revOppMax` | 0.80 | Entry blocked if M3 or M5 net opposes by more than this. |
| `brkSlBufAtr` / `brkSlAtrMult` | 0.2 / 2.0 | Breakout SL = min(mVAH − 0.2 ATR, close − 2.0 ATR) for longs. |
| `brkRrFar` / `brkRrNear` / `brkRrLookbackBars` | 3.0 / 2.0 / 25 | Breakout TP RR: 3.0 if no same-direction entry in last 25 bars, else 2.0. |
| `revAnchorOffAtr` / `revEntryDistAtr` | 0.06 / 1.0 | Reversion anchor offset and required excursion past the anchor (ATR). |
| `revPocSlOffAtr` / `revSlBufAtr` / `revSlAtrMult` | 0.1 / 0.2 / 2.0 | Reversion SL geometry (POC-family anchor offset, buffer, protective ATR distance). |
| `revMinRR` | 1.5 | Skip reversion entries whose target-based RR < 1.5. |
| `useTp1Partial` / `tp1Rr` / `tp1CloseBrk` / `tp1CloseRev` | ON / 1.0 / 20 / 20 | TP1 partial at 1R closing 20% (per family). |
| `enableBeAfterTp1` / `beBufAtr` | ON / 0.05 (hidden) | After TP1, runner stop to entry ± 0.05 ATR, monotonic. |
| `trailRunner` / `runnerRr` / `trailAtrMult` | OFF / 10 / 3.6 | Optional chandelier runner: 10R backstop TP2, 3.6 ATR trail. |
| `maxConcurrentPerDir` | 3 | Max stacked same-direction trades (each from its own fresh cross). |
| `enableEarlyExit` / `exitNetMin` | OFF / 0.80 | Opposing net-volume flush close-all on (M1&M3) or (M3&M5). |
| `riskUnit` / `riskPerTradeAccPercent` / `riskPerTradeUSD` | % Acct / 1.6 / 180 | Per-trade risk budget definition. |
| `maxDailyDDPct` | 6.0 | Predictive daily-DD breaker from UTC-day starting equity. |
| `minAtrPct` / `maxAtrPct` | 0.0156 / 0.158 (hidden) | Volatility floor/ceiling as ATR % of price. |
| `asia` / `ldn` / `ny` | 0000-0600 / 0700-1100 / 1230-1630 | Session windows (UTC). |
| `avoidNews` ± mins | ON / 15 / 15 | News window around high-impact USD releases. |
| `nodeDecay` / `nodeNeutralBand` / `nodeSaturation` / `nodeTouchAtr` | 0.94 / 0.15 / 4.0 / 0.05 (hidden) | Node-flow memory decay, neutral band, DEAD saturation, touch distance. |

## 8. Known Limitations & Notes

- **Tick volume, not real volume.** `volume` on FX/CFD feeds is tick count; the whole profile and net-flow engine inherit that approximation. Feeds differ between TradingView and MT5 — a primary suspect in past Pine-vs-MT5 divergence.
- **Synthetic order flow.** Buy/sell pressure is `volume * candle-body-sign` (body/range proxy), not bid/ask delta. Node states and the chart-TF net are heuristics on top of a heuristic.
- **M3-vs-M1/M5 net asymmetry.** `netM3c` derives from the decayed node arrays (`f_near_net_weighted`); M1/M5 use the flat 50-bar `f_tfNetNear` of the prior completed HTF bar. These are not the same statistic. The EA port must mirror both implementations bin-for-bin.
- **Rolling profile drift.** POC/VAH/VAL recompute every bar from a rolling window; the level a cross was armed against can move during the 6-bar freshness window. Cross detection itself is repaint-safe (indices recorded on confirmed bars only; `lookahead_off` everywhere), but level drift is inherent.
- **RR near/far input mismatch.** Tooltip claims the 25-bar lookback checks for a prior *breakout* entry; the code stamps `lastLongEntryBar`/`lastShortEntryBar` on **any** entry of that direction, so a reversion entry also downgrades the next breakout's RR to 2.0.
- **News slots are learned, not preloaded.** The first occurrence of each economic event in loaded history creates the slot; bars before that are unprotected, and only 5 distinct minute-of-day slots exist.
- **WON/LOST labels are cosmetic heuristics** (close vs entry at detection bar), not P&L truth — use the strategy tester trade list.
- **Pyramiding ceiling (20) is decorative**; the binding cap is `maxConcurrentPerDir = 3`.
- **No loss-streak cooldown / peak-DD trail in Pine** — those exist only in the MQL5 EA's RiskManager; parity claims must exclude them.
- **Project status (measured):** PF 1.21 TRAIN / 1.10 OOS on XAUUSD M3 (~1331 trades) — below the deploy gate (1.25/1.15). The edge is tail-carried: ~20 trades ≈ 112% of net profit. Exit-tuning sweeps came back null; structural improvements (the Monster variant), not param sweeps, are the path forward. Any change must prove the tail trades survive.

## 9. Optimization & Locked Parameters (C++/MT5 research, 2026-06)

> Sections 1–8 describe the **Pine source as written** (M3, local 50 / master 150, RR-based TP, 20% TP1 partial). Section 9 records what the C++ tick-engine sweeps + MT5 confirmation actually **locked** for deployment. These supersede the Pine defaults for the shipped `.set` presets.

**Why these changes raised XAU profit.** The breakout *logic* was not touched. The gains came from (a) **fixing the master VP length** to a swept-robust value instead of the floating `local × 3`, (b) moving the entry TF **M3 → M5**, and (c) tuning the risk bracket (break buffer, SL, Chandelier trail, TP1 partial = 0%) and adding hour blocks — each validated by walk-forward + Monte-Carlo, not a lone peak. Master length is the *sole* signal-side driver (see the 2.1 operational note); everything else is trade management.

### The master-length question, answered

Master VP length in bars = `InpVpLookback × InpMasterMult` (this is what the `108×4` / `24×30` shorthand means — lookback × multiplier; bins is a separate `InpVpBins = 30`). Because the local profile is inert, the *split* of that product is cosmetic — only the **total bars** matter.

| | **XAUUSD M5** ✅ deployable | **BTCUSD M5** ❌ not deployable |
|---|---|---|
| Master VP length | **432 bars = 36 h** (108 × 4) | **720 bars = 60 h** (24 × 30) |
| Bins / Value area | 30 / 70% | 30 / 70% |
| Break buffer | 0.85 × ATR | 1.0 × ATR |
| SL | 1.2 × ATR | 2.2 × ATR |
| Chandelier trail | 2.5 × ATR | 6.0 × ATR |
| TP1 partial close | **0%** (banking caps the runner) | 20% |
| ADX trend min | 22 | 30 |
| Reversion | ON (small additive edge) | **OFF** (MT5-disconfirmed as fictional) |
| Hour blocks (UTC+10 frame) | 2, 3, 14 | none (24/7) |
| Local VP | OFF / inert | OFF / inert |
| Preset | `kenkem/MQL5/Presets/KK-MasterVP-XAUUSD-M5.set` | `kenkem/MQL5/Presets/KK-MasterVP-BTCUSD-M5.set` |

- **XAU 432 bars is a plateau center**, not a peak: the 384–480 bar band all behaves well (lowest OOS drawdown, OOS PF > train). Walk-forward: 11/12 months profitable, 7/8 equal-N folds PF>1, and the fixed 432 lock *beats* per-fold re-optimization (no curve-fit, no periodic re-tuning). Monte-Carlo (20k): P(profit) 99.6%, PF 5th-pctile 1.108. **DD honesty:** the headline 10.3% OOS DD is a benign window — full-year maxDD is 27.7% and MC 95th-pctile ~38%; size for a **~30–40% peak-to-trough**.
- **BTC 720 bars passed the engine sweep but failed MT5** (live PF 1.058 ≈ breakeven; only 57% of trades matched the engine vs XAU's ~86%; the reversion edge the engine reported was fictional on the BTC/Exness feed, which round-trips intrabar). **There is no trustworthy BTC master length yet** — treat 720 as provisional until the entry-match gap is closed. Source: `research/mastervp_parity/mt5_runs/RUN_2026-06-20_btc_m5_locked_reversion/FINDINGS.md`.

### Practical takeaways

1. **Right master length right now:** XAU M5 = **432 bars (36 h)**, validated. BTC = unresolved (720 bars is engine-only, not MT5-confirmed).
2. **Local POC contribution to breakouts:** none — the master value-area edge defines the breakout; the local profile is currently dead weight (only a confirmation-gate experiment would change that).
3. The shipped XAU profitability is **risk-management + master-length + M5**, not a new entry rule.

Research trail: `research/mastervp_parity/VP_LENGTH_STUDY.md`, `M5_SWEEP_FINDINGS.md`, `BTC_SWEEP_FINDINGS.md`, `WF_MC_FINDINGS.md`; engine locks under `cpp_core/tools/mastervp/`.
