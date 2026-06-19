# HANDOFF — read me first, update me last

_Last updated: 2026-06-19 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, C++ tests PASS (28).
Latest: started **E2**. E2's own port is solid (**95.8% recall, 136/142**); the dominant E1E2 divergence is
an **E1↔E2 interaction** — engine lacks the EA's account-equity entry-block. E1-only is locked at 74/4/17._

## 🎯 Goal: KenKem entry parity engine⇄MT5. **NOW ON: E2 / the E1↔E2 interaction.** Then E4, E5.
Ground truth = the canonical EA (`kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5`).

## ⭐ CURRENT FOCUS — E1↔E2 interaction (user chose: "diagnose interaction first")
**Diff: engine `anchor_E1E2.set` vs MT5 `RUN_2026-06-18_1.8.154_xau_2yr_E1E2/trades.csv` (325 MT5 trades):**

| kind | MT5 | eng | matched | missed | overfire | recall |
|------|-----|-----|---------|--------|----------|--------|
| E1   | 183 | 124 | 92      | **91** | 32       | 50%    |
| E2   | 142 | 162 | 136     | 6      | 25       | **95.8%** |

- **E2 entry logic is GOOD** (95.8%). 6 missed are all marginal (EA-close/SL-WIN, tiny pnl). User's intuition
  (E2 ⊆ E1 factors → ports easily) holds. The E2-specific residual (25 overfire) is secondary.
- **The headline problem is E1, not E2.** E1 recall collapses 95%→50% when E2 is enabled.

### ✅ ROOT-CAUSED (code-verified): engine lacks the EA's account-EQUITY entry-block
- The EA gates **ALL** entries through `GetEntryBlockReason()` / `CanCreateNewEntry()`
  (`TradeManagement/RiskManager.mqh:241-344`): black-swan cooldown, spread, ATR-pctile, **drawdown-limit /
  recovery-mode / profit-protection** (all driven by `peakAccountBalance` vs live balance).
- E1 and E2 **share the account equity**. Enabling E2 reshapes the equity curve → changes WHEN the drawdown
  entry-block is active → MT5 E1 swings **78 (E2 off) → 183 (E2 on)**. Same conviction=7, same MAX_CONCURRENT=2;
  the ONLY input diff is `ENABLE_E2_ENTRIES`.
- The **engine does NOT model this entry-block**: it tracks `balance_`/`peak_` but uses `ddPct` ONLY to resize
  lots (`tick_engine.hpp:351-352 mult*=1.2`); there is NO equity-based entry block. So engine E1 is ~insensitive
  to E2: **91 (E2 off) → 124 (E2 on)** — hence 50% recall in the combined run.
- Secondary coupling (real but not the driver): E1/E2 share GLOBAL arm state `lastEMACrossingUp/Down`,
  `lastEma75TouchUp/Down` (`Core/GlobalState.mqh:441-444`). Dispatch is **E1 first, E2 only if E1 didn't fire**
  (`KenKemExpert.mq5:2222`), so E2 does NOT directly steal E1 bars — the coupling is via the shared ACCOUNT, not
  the arm flags.

### ▶️ NEXT ACTION (E2)
1. **Port the EA's account-equity entry-block into the engine** (the dominant lever). Model
   `GetEntryBlockReason`'s drawdown-limit / recovery-mode / profit-protection on the engine's live `balance_`/
   `peak_`, blocking entries (not just resizing lots). Read `RiskManager.mqh` `IsWithinDrawdownLimit` +
   `CheckProfitProtection` (340-430) + `GetEntryBlockReason` (241-344) for exact thresholds/params.
   Validate vs committed `…_E1E2/trades.csv`; expect MT5's 78↔183 E1 swing to reproduce and E1 recall to climb.
2. Then revisit E2's own 25 overfire (likely partly downstream of #1 — shared account state).
3. **Repro:** `KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2024_2026_m1.csv
   --ticks tools/ticks_xauusd_2024_2026.csv --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1E2.set
   --out /tmp/e1e2.csv` then `python research/kenkem_parity/diff_kk.py --engine /tmp/e1e2.csv --mt5
   research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/trades.csv [--kind E1|E2] [--show N]`.
   Committed E1E2 data: `trades.csv` (diff target), `trace.csv.gz` (per-bar MT5), `cpp_trades.csv`,
   `mt5_e1_touch_arms_utc.csv`, `inputs_echo.txt`, `tester.log.gz`.

## 📌 E1-ONLY — LOCKED at 74/4/17 (recall 94.9%, effectively MAXED)
All 4 E1-only missed are trades MT5 took and **LOST** (3 SL-LOSS + 1 end-of-test). Don't chase them. The 17
E1-only overfire need the user MT5 re-run (M3/M5 EMA values + sideways sub-components) — see old NEXT ACTIONS below.

## ✅ THIS SESSION — ATR FIXED (commit `f210631`): overfire **62→31**, missed **31→11**, matched **47→67**
The forming-bar ATR divergence is SOLVED. The prior diagnosis ("track forming H/L tick-by-tick") was a
**red herring**: MT5 uses first-tick **H=L=open** on 100% of bars exactly like the engine (forming TR already
matched 99.94%). **Real bug = the CLOSED-bar smoothing. MT5's built-in `iATR` is a rolling SIMPLE MA of
True Range** (`ATR[i]=ATR[i-1]+(TR[i]-TR[i-n])/n`), **NOT Wilder/SMMA.** The engine's `kk::ind::atr` used
Wilder → ~6% mixed-sign off → 29% of bars got the wrong ATR-percentile block category.
- Fix (KenKem-only): `indicators.hpp` add `atr_sma_from_tr`/`atr_sma_mt5`; `tf_cache.hpp` cache ATR(14)→SMA
  + store TR series; `snapshot.hpp` M1+M3 forming shift-0 = SMA window-slide `atr_c + (tr_form - tr[i1-(n-1)])/n`.
- Verify (vs MT5 trace, 848,532 bars): forming-ATR exact(<1e-4) **0.12%→99.93%**; pctile exact **31.6%→81.4%**
  (±3 on 99.96%); entry-gate block-category agree **~71%→100%**.
- ⚠️ **1-bar trace label offset** (key for any future ATR/trace diff): MT5 trace row ts=T = decision at OPEN
  of bar T+1; align engine→MT5 with **shift −1** (engine ts−60000 = MT5 ts) → prevClose matches 100%.

### Prior session (commit `1ba5157`) — TP parity: short-RR factor→1.0 + ported `GetDynamicRRMultiplier`.
Tag-agree 66%→81%, |ΔpnlUSD| med 114→4.6, SL-LOSS 11/11. (Detail in [[kenkem-tp-parity-rr-fixes]].)

### Result now (FULL 2yr E1 anchor, `KK_E1_FAITHFUL=1`, commit `ce47b1f`)
- matched **74** / missed **4** / overfire **17** (engine 91 vs MT5 78). Recall **94.9%**.
- |ΔpnlUSD| median ~4.5; all 4 missed are losing trades (see RECALL REALITY above).

## 🟢 DATA BLOCKER — APPARENTLY RESOLVED (verify with user)
`cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` on disk now give
**849,963 bars / 162,761,235 ticks** — i.e. the COMPLETE source (matches the proven-exact 848,532 /
162,657,649, [[tick-source-parity-proven-exact]]), NOT the 577k holes-affected regen the prior handoff
feared. All this session's numbers use the complete data. **Confirm with the user** whether they
restored the full Exness export (or it was never actually deleted) before trusting absolute counts.

## ✅ MTF EMA off-by-one FIXED (commit `c3a51dc`) — matched 67→74, missed 11→4, overfire 31→26
The EA reads MTF EMAs via `GetEMA(tf,ema,ENTRY_SHIFT=1)`; `EMAHelpers.GetEMAValues` fills `emaBuffers` with a
**NON-series** `CopyBuffer(h,0,0,bufferSize=4,dst)` → order REVERSES (`dst[0]=B-3 … dst[3]=B`), so
`GetEMA(…,1)=dst[1]=B-2` (one bar BEFORE last closed). Engine read `align_tf-3` (=B-3) — one too stale, while
`s.emaM1` everywhere else correctly reads `ema[i1-1]=B-2`. Fixed `emas_ready_entry`+`m5_directional_ok`+E4
STEP-2 M3 read to `align_tf-2`. (Authoritative: `kke1gate.csv` showed 14/31 overfire were `BLOCK:mtf`.)
Recall now **95%** (74/78). NB: matched net engine +516 vs mt5 +1196 — the +7 recovered trades are
MT5-profitable but the engine exits them worse → an EXIT-parity issue on those, not entry.

## ✅ THIS SESSION — sideways ADX/RSI 5-bar avg (`ce47b1f`): overfire **26→17**, recall preserved
`GetSidewaysScore` (TrendIdentifier.mqh:390) reads `GetADXAverage(TF,5)` + `GetRSIAverage(TF0,5)` = mean of
shifts **0..4** (not single shift-1). Engine used single-bar → biased LOW → under-blocked sideways → over-fired.
Fix: added `adxM1_avg5`/`adxM3_avg5` (forming `adxF` + 4 closed) in snapshot.hpp, switched RSI→`rsiM1_avg5`.
DI **kept on last-CLOSED bar** — the EA reads `cache.diPlus[0]` (forming shift-0) but the engine's first-tick
forming DI is degenerate (H=L=open) and overshoots indecision points (cost 1 recall in A/B; reverting it = 74/4/17).
- ⚠️ **DATA CEILING**: reconstructing MT5's `sideways` from MT5's OWN trace columns = only **27% exact** (single-bar
  adx/di can't reproduce the avg-based score). Engine now 25.9% (was 20.3%). Full sideways match is IMPOSSIBLE
  from existing data — needs an MT5-side dump of the **5 sideways sub-components** (or the avg-ADX/forming-DI inputs).

## 🔬 RESIDUAL now = 17 overfire + 4 missed
- **12 `BLOCK:mtf`** — engine still passes mtf where MT5 blocks, but **M1 EMAs now match MT5 99.69%**, so these
  are **HTF (M3/M5) EMA boundary VALUE diffs** (not shift). Diagnosing needs MT5-side M3/M5 EMA values or a
  `KKE1GATE,…,mtf` detail dump of `m1/m3/m5/extreme` — **requires a user-side MT5 re-run** with enhanced gate
  trace. Likely boundary rounding from M3/M5 bar construction (engine aggregates M1 → native M3/M5).
- **8 `PASS:all`** — gate passed, blocked at EXECUTION (high-risk path). The earlier "intrabar" theory was
  WRONG: `DetectNewEntry`+`UpdateIndicatorCache` run ONCE per bar at the new-bar event (KenKemExpert.mq5:2429,
  2491), NOT per-tick — MT5 decides at bar-open like the engine. Sub-reason not yet pinned (spread off;
  daily-loss/aggregate-risk provably inert — see [[kenkem-e1-residual-is-intrabar-exec]]).
- **6 no-row** — MT5 never evaluated E1 there (arming/age timing).
- **4 missed**: 3 are MT5 SL-LOSSES the engine avoids (harmless), 1 end-of-test EA close.

## ▶️ NEXT ACTIONS (in order)
1. ⭐ **BLOCKED ON USER MT5 RE-RUN** — one re-run of canonical KenKemExpert with an EXTENDED per-bar trace unblocks
   BOTH remaining residuals. Need columns added at each evaluated bar:
   - **M3 & M5 EMA values** (EMA1..EMA4 each, at ENTRY_SHIFT) → pins the **~12 `mtf`** overfire (current trace has
     only M1 emas + combined `L_htf`/`S_htf`; can't see which HTF EMA boundary flips). Ideally also the mtf
     sub-breakdown `m1_ready,m3_ready,m5_dir,extreme`.
   - **The 5 sideways SUB-COMPONENTS** (EMA-conv, ADX-weak, DI-indec, RSI-neutral, ATR-compress) → breaks the 27%
     reconstruction ceiling on the remaining sideway overfire; lets us pin which component still diverges.
2. **Sideways component diffs** (after #1 data) — engine `sideways_score` is in snapshot.hpp; ADX/RSI now use 5-bar
   avg + ATR-pctile faithful. Remaining bias is +2.48 HIGH; suspects = EMA-band (atr denom / which emas) or the
   averaging shift. Verify each component vs the EA's per-component dump.
3. **Exit parity on the newly-matched** (engine net < MT5 net on recovered trades) — over-trail / TP-vs-SL-WIN family.
4. Accept 17/4 as the current E1 floor and extend to **E2/E4/E5** (the bigger remaining scope).

## 🔁 Repro (full 2yr, ~30s)
```
cd cpp_core && make test                        # 29 checks, green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/e.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
python research/kenkem_parity/matched_exit_crosstab.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv
# diagnostics: prefix KK_TRADE_DIAG=1 and/or KK_ENTRY_DIAG=1 (2>/tmp/diag.txt)

# --- ATR-pctile root-cause diagnostics (this session) ---
# 1) oracle A/B: feed MT5's exact per-bar pctile, expect overfire 62->47
D=research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace
gzcat $D/trace.csv.gz | awk -F, 'NR>1{print $1","$33}' > /tmp/pctile_oracle.csv
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --ticks tools/ticks_xauusd_2024_2026.csv --symbol-xau --spread 0.05 \
  --set research/kenkem_parity/anchor_E1_only_trace.set --pctile-oracle /tmp/pctile_oracle.csv --out /tmp/e_oracle.csv
# 2) per-bar pctile divergence: engine trace_dumper col atr_pctile vs MT5 col 33
./build/kenkem/trace_dumper --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --set research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/eng_trace.csv
# (then compare /tmp/eng_trace.csv[atr_pctile] vs $D/trace.csv.gz col33 -> 31.6% exact, 29% wrong category)
```
Current (post-ATR-fix `f210631`): matched **67** / missed **11** / overfire **31**; |Δrisk| 0.181;
|ΔpnlUSD| median **5.12**; matched tag-agree **87%**; matched net engine **+673** vs mt5 **+959**.
(ATR-pctile diagnostics below are now mostly historical — block-category agrees 100%.)

## 📦 Data / instruments
- Full 2yr XAU: `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` —
  REGENERATED this session from `data/xauusd/` symlinked raws; **incomplete** (577,738 bars). gitignored.
- **MT5 ref run (committed)** at `research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/`:
  `trades.csv` (78, the diff target) · `kke1gate.csv` · `tester.log.gz` (input echo + mechanism counts +
  `TRAILING SL` lines) · `trace.csv.gz` (gunzip before use). EA=canonical KenKemExpert, XAU 2024.01→2026.06.
  **Input echo confirms MY_STANDARD_LOT_SIZE=100, COMMON_MAX_RISK_PER_TRADE=0.01, leverage 1:500.**
- Ground-truth EA = `kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5` (+ `TradeManagement/TradeManager.mqh`,
  `Config/InputParams.mqh`). dquants `mql5/experts/KenKem/` is the THIN KK-rewrite — NOT this EA.

## 🧱 After E1→E5 parity LOCKED (user's explicit next phase)
Convert pip-denominated params to ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before — parity
is ground truth. See [[goal-pip-to-atr-relative]].
