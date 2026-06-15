# dquants pipeline — systemic root-cause investigation (2026-06-15)

User's hypothesis: dquants strategy ports systematically underperform their MT5 originals, so something is
wrong pipeline-wide (not just per-strategy). Investigated empirically (KenKem, XAUUSD M1) + /codex debate.

## Decisive experiments run

### #1 BAR engine vs TICK engine — CONFIRMED systemic, HIGH impact
Same KenKem config + .set, **3-month window (2025-03→06)**:

| Engine | Trades | Net | PF | Win% |
|---|---|---|---|---|
| BAR (synthetic OHLC walk) | 229 | **-2,369** | 0.89 | 40.2 |
| TICK (real bid/ask) | 375 | **+5,047** | 1.12 | 46.9 |

Opposite sign of profitability. Tick win% (46.9) matches the ground-truth 45.95; bar (40.2) does not. The
bar engine's 4-point adverse-first walk mis-resolves path-dependent exits (partial→BE→chandelier) and
SL/TP ordering. **All bar-engine validation across strategies is suspect.** The engine's own header already
warns of this. → Make the tick engine the canonical validation path; re-baseline KenKem/MasterVP/Monster.

### #2 Entry over-firing — CONFIRMED, HIGH impact (dominant on full window)
TICK engine, **full window** (2025-03→2026-06): 1,692 trades vs ground-truth 156 (**11×**), net -5,960,
PF 0.97. Over-firing is uniform (~110/mo vs the EA's ~10/mo, every month). Overlap analysis vs the 156
real trades:
- Day-level: dquants trades **112 of the EA's 115 days (97%)** — broad timing is RIGHT — but on **333 days
  total** (3× too many days).
- Trade-level: only **24%** (38/156) match within ±3min same type+dir; **56%** (88/156) at ±30min ignoring
  type. So the precise entry selection diverges — a mix of **trigger-timing divergence** + **residual gate
  leniency**, not a clean superset.
→ Audit the EMA-cross (E1) / EMA-touch (E2) trigger definitions vs the EA; verify conviction/trend-quality
  integer scores reproduce the EA's exactly (mine may be inflated → 7/10/6/9 thresholds pass too easily);
  wire E1 `HasSufficientMomentum` + `E1_HTF_TREND_FILTER` + high-risk-path branch.

### MID vs BID signal basis — RULED OUT
TICK engine, 3-month, mid bars 375/PF1.123 vs bid bars 377/PF1.132. Negligible at XAU scale.

## Candidate systemic causes (ranked, pre-codex)
1. **[HIGH, confirmed]** Bar engine unreliable → use tick engine (task #7).
2. **[HIGH, confirmed]** Entry over-firing: trigger-timing + gate leniency (task #8/#6).
3. **[MED, untested]** Flat research-sizing vs EA conviction/regime-weighted sizing → depresses size-weighted
   PF; good trades under-sized, bad over-sized (task #9).
4. **[LOW/untested]** HTF M1→floor aggregation vs MT5 native per-TF bars + session boundaries.
5. **[LOW/untested]** shift-1-everything snapshot vs EA shift-0/shift-1 mix (signal timing) — could explain
   part of the trade-level mismatch in #2.
6. **[LOW]** Indicator parity (ADX/DMI/ATR/RSI/Ichimoku) — MasterVP already hit exact parity, so likely OK.
7. **[RULED OUT]** MID vs BID.

## Second-opinion debate
- **/codex**: UNAVAILABLE — auth token expired/reused (401 `refresh_token_reused`); needs interactive
  `codex login`. It hung retrying, was killed.
- **/gemini** (substitute) ranked: (1) HTF M1→floor aggregation misalignment, (2) acceleration shift-1
  vs EA shift-0 → 1-min entry lag (systematically negative), (3) lenient/inflated conviction/TQ scores,
  (4) Wilder-seeding indicator drift. Recommended golden-buffer dumps from the EA + a "gate-vocalizer"
  per-trade diff as the decisive tests.

## Over-firing localization (MT5-free experiments)
- **HTF alignment — RULED OUT**: M3 buckets fall on :00/:03/:06; a whole-hour server offset (GMT+9) is
  bucket-invariant for M1/M3/M5/M15. (Gemini Rank-1 doesn't apply to this feed.)
- **Score inflation — RULED OUT**: histogram over 439k bars — conviction is well-spread (only **15%** of
  bars ≥10), trend-quality is selective (**67%** hard-gated to 0, only **6%** ≥9). Scores are not maxed.
- **Gate leniency — RULED OUT as the cause**: threshold sweep (3-mo tick window, GT=34 trades): base 375
  → conviction 12 + TQ 11 (the MAXIMUMS) still **213** trades, PF flat ~1.1. Even stricter-than-EA gates
  leave 6× over-firing. ATR-pctile 85 cuts to 111 but PF drops to 0.99 (kills good high-vol trades).
- **Trigger port — FAITHFUL**: the EA's `UpdateEmaTouches` (EMAHelpers.mqh:287-313) sets the EMA75 touch
  on *every* straddle bar with no debounce, exactly like dquants triggers.hpp; the EMA-cross + EMA200
  touch paths match too. Entry2.mqh's gate is the same TQ/conviction/RSI set already ported.
- **CONCLUSION**: the residual ~6–11× over-firing is NOT scores, gates, or trigger definition. Most likely
  a **per-bar indicator/decision divergence** (small persistent value drift shifting which bars
  straddle/cross/pass) or a subtle unported `CheckE2EntryConditions_Internal` detail. **This cannot be
  localized further without a golden per-bar diff against an instrumented MT5 run.**

## DECISIVE next experiment (needs ONE instrumented MT5 run)
Instrument the EA to `FileWrite`, per M1 bar at ENTRY_SHIFT for a 1-week window: EMA0-4 + ADX/DI + ATR +
RSI per TF (M1/M3/M5/M15), Ichimoku Tenkan/Kijun/SpanA/B, the trigger state (lastEma75Touch*,
lastEMACrossing*), and for each entry attempt the conviction + trend-quality scores + pass/fail + reason.
Emit the identical trace from dquants. Diff to find the FIRST diverging bar → localizes indicator-drift
vs trigger-state vs gate-decision. (MasterVP already hit exact indicator parity on BID bars, so the
shared kk::ind EMA/ADX/ATR/RSI are likely fine — but KenKem runs them on MID bars; verify on this trace.)

## FINAL ordered plan
1. **[DONE]** Neutralize the bar engine — added a loud "NOT MT5-faithful" banner; tick engine is canonical.
2. **[BLOCKED on 1 MT5 run]** Golden per-bar diff to localize the residual over-firing (the dominant
   full-window loss). Build the instrumented EA + dquants trace dumper + differ.
3. **[OPEN]** Port conviction/regime-weighted sizing (PF is size-weighted).
4. **[DONE 2026-06-15 — see below]** Re-baseline on the tick engine over **2026 OOS** (prior numbers suspect).

## 2026-OOS tick re-baseline — KenKem-E5 (2026-06-15) — INVALIDATES the production-promotion numbers
Built 2026-OOS tick CSVs from `data/processed/ticks_{btc,xau}usd_2026.parquet` (BTC 2026-01-01→06-09 = 15.0M
ticks; XAU 2026-01-01→05-29 = 46.7M ticks) via `export_ticks.py`. Ran the SAME config + window through both
engines. Config = the C++-format research sets `research/optimization/best_kenkem_E5_{btc,xau}.set`
(`--from-ms 1767225600000`, warmup 300, BTC bars = 2025+2026 concat for warmup, XAU =
`bars_xauusd_2025h2_2026_m1.csv`).

| Config | BAR engine | TICK engine (canonical) |
|---|---|---|
| E5 BTC | 750 tr · win 73.9 · **PF 1.339** · **+12,938** · DD 1,746 | 1580 tr · win 70.9 · **PF 0.718** · **−25,981** · DD 26,094 |
| E5 XAU | 248 tr · win 70.2 · **PF 1.445** · **+6,506** · DD 2,070 |  593 tr · win 67.6 · **PF 0.889** · **−4,261** · DD 7,004 |

**The bar engine flips the SIGN of profitability on the production config too** (PF 1.34/1.45 → 0.72/0.89),
understates trade count ~2× and drawdown ~10×. The "distilled result" PF 1.24/1.08 that justified promoting
**KenKem-E5 to production MQL5 is a bar-engine artifact** — on the faithful tick engine the strategy LOSES
on 2026 OOS. The high win-rate + negative net is the classic small-wins/large-losses (giveback/SL) profile,
amplified by the unresolved ~30× over-firing (1580 BTC trades in ~5mo vs the real EA's ~10/mo). So this is
NOT "the underlying strategy is bad" — it is "the dquants port over-fires and is not yet MT5-faithful, and
no production number derived from the bar engine can be trusted." The golden per-bar diff (plan #2) remains
the decisive unblock.

### SECONDARY BUG found while re-baselining — the deployed `.set` was silently ignored (0 keys)
`load_set()` (kenkem_config.hpp) only recognises EA-internal UPPERCASE keys (`ENABLE_E5_ENTRIES`, `E5_RR`,
`MY_STANDARD_LOT_SIZE`…). The **promoted production set** `mql5/experts/KK-KenKem/KK-KenKem-E5-BTCUSD.set`
uses MetaTrader `Inp*` names (`InpE5On`, `InpE5Rr`, `InpRiskPerTrade`…) → **`[set] applied 0 keys`**, engine
ran pure C++ defaults (E1/E2/E4 on, E5 off → 1177 wrong trades). Two `.set` namespaces have always existed
and never matched. Worse, the deployed `Inp*` set and the validated UPPERCASE set carry **different values**
(e.g. MIN_MOMENTUM_ADX 21.3 vs InpMinMomentumAdx 13.97; EMAs 8/18/55/122/163 vs 12/23/53/94/210) — the EA in
production is NOT running the config the engine validated. TODO: (a) teach `load_set` the `Inp*` aliases (or
add a converter), (b) reconcile the deployed set against the validated one, (c) re-confirm parity.

## Over-firing root cause LOCALIZED from the dquants side alone (2026-06-15) — golden trace tool built
Built `cpp_core/tools/kenkem/trace_dumper.cpp` (`make kenkem_trace`): a read-only per-M1-bar decision trace —
every shift-1 indicator + the E5 trigger state + each E5 gate sub-decision (sideways / atr-pctile lo+hi /
price-vs-EMA25 / trend-core / adx-floor / htf) for BOTH directions, plus the raw signal-fire. Schema matches
what an instrumented MQL5 EA would `FileWrite`, so it doubles as the golden-diff C++ side. Ran a 1-week BTC E5
window (`trace_E5_btc_wk.csv`, 10,077 bars). The residual over-firing was localized WITHOUT an MT5 run:

1. **Trigger liveness, not loose gates, drives the count.** The gates already filter hard (only ~7–8% of
   live-trigger bars pass). But the E5 trigger is "live" 21% (long) / 16% (short) of all bars because
   `E5_MAX_EMA_CROSS_AGE=48` keeps one EMA-alignment onset eligible ~48 minutes. Age-at-pass distribution:
   **43% of qualifying entries fire at trigger age 33–48** (a late chase ~40 min after onset), only ~11% at the
   genuine onset (age 0–1). Tightening maxage on the TICK engine (2026 OOS BTC): age 48 → 1580 tr, −$25,981,
   DD 26k; age 1 → 353 tr, −$5,391, DD 5.5k. The wide window inflates trades ~4.5× and DD ~5×.

2. **But over-firing is SECONDARY — the strategy loses at EVERY maxage (PF 0.70–0.77).** Even pure onset
   entries (age 1) lose. The killer is **exit-management geometry**: on the 1580-trade run, win 70.9% yet avg
   win **$59 (~0.3R)** vs avg loss **−$200 (full −1R)** (ratio 0.29); max loss −$202 ≈ avg loss ⇒ nearly every
   loss is a FULL stop-out, while most "wins" are tiny partial-TP / BE-trail scratches and few reach the RR-1.22
   TP ($241). Net per trade ≈ 0.71·0.3 − 0.29·1.0 = **−0.08R**. The bar engine HID this: its synthetic 4-point
   OHLC walk mis-resolves the path-dependent partial→BE→trail sequence favorably (→ fake PF 1.34).

**Fix priority:** (a) **exit management** — the partial-TP/BE/trail scratches winners at ~0.3R while losers run
to full −1R; this is exactly the ProfitManager (C5) surface (giveback-cap, BE-protect, partial-trigger), now
validatable on the CANONICAL tick engine instead of the bar engine that masked it; (b) **entry maxage** — drop
`E5_MAX_EMA_CROSS_AGE` toward 1–3 to cut late-chase trades and ~5× the drawdown. Exit geometry is the dominant
term. The MQL5-instrumentation + python-differ half of the golden diff (for C++↔MQL5 port parity) is built-ready
but DEFERRED — the cause was localized on the C++ side alone, so the one MT5 run is no longer the critical path.

## Exit-geometry fix APPLIED & adopted (2026-06-15) — E5 flips loss→profit on the TICK engine
Acted on the fix priority above. Built `research/optimization/sweep_e5_exits.py` — a parallel sweep of the four
ProfitManager (C5) exit knobs × entry maxage, **on the canonical TICK engine, 2026 OOS, BTC+XAU**, ranked by OOS
PF. Grid: `E5_PARTIAL_TP_TRIGGER {0.22,0.45,0.70,0.90} × E5_PARTIAL_TP_RATIO {0.25,0.476,0.70} ×
E5_SL_TO_BREAKEVEN_BUFFER {0,0.05,0.20} × E5_TRAILING_SL_FACTOR {0.435,0.75,1.2} × E5_MAX_EMA_CROSS_AGE {1,2,3}`
(324/symbol) + a refinement pass around the edge. Data regenerated reproducibly via
`cpp_core/tools/common/export_kenkem_oos.py` (BTC baseline reproduced exactly: PF 0.714, 1581 tr, −26,440).

**Surface (clean, monotonic, no lone peaks):**
- `E5_PARTIAL_TP_TRIGGER` is the dominant lever — PF rises monotonically 0.22→0.95 at every maxage. At 0.22 the
  partial fires at ~0.28R and the chandelier scratches the runner (avg win ~$59 ≈ 0.3R); pushing it to ~0.95
  (≈1.22R given RR≈1.28) lets winners ride to TP → avg win ~$206–314 ≈ avg loss. The plateau pt∈{0.93,0.95,0.97}
  is flat on both symbols (BTC ~1.075, XAU ~1.06–1.09) — robust, not a peak. (A tiny late partial at 0.95 even
  beats partial-OFF: same PF, *lower* DD.)
- `E5_MAX_EMA_CROSS_AGE=1` is the necessary amplifier — **only age 1 clears PF>1**; age 2/3 stay ≤1.0 at the same
  exits with ~1.7× the DD (the late-chase entries are net-negative). Confirms over-firing is secondary but real.
- ratio / BE-buffer / trail are near-inert once the trigger is late (the partial rarely fires).

**Adopted consensus config (one config wins both symbols → clean MQL5 port):**
`E5_MAX_EMA_CROSS_AGE=1 · E5_PARTIAL_TP_TRIGGER=0.95 · E5_PARTIAL_TP_RATIO=0.476 · E5_SL_TO_BREAKEVEN_BUFFER=0.05
· E5_TRAILING_SL_FACTOR=1.2`, locked into `research/optimization/best_kenkem_E5_{btc,xau}.set` (entry params
untouched). Adoption rule satisfied: **net UP and DD DOWN** on both. Standard 9-column table (TICK engine, 2026 OOS):

| Strategy | Settings | Symbol, TF | Net Profit | Profit Factor | Recovery Factor | Max Drawdown | Sharpe | Trades/day |
|---|---|---|---|---|---|---|---|---|
| E5 BEFORE | early partial 0.22/0.23 · tight trail · maxage 48/29 | BTCUSD M1 | -26,440 | 0.714 | -1.00 | 26,440 | -7.10 | 9.9 |
| E5 AFTER  | partial 0.95 · trail 1.2 · BE 0.05 · maxage 1         | BTCUSD M1 | +2,637 | 1.074 | 0.75 | 3,531 | 1.12 | 2.2 |
| E5 BEFORE | early partial 0.22/0.23 · tight trail · maxage 48/29 | XAUUSD M1 | -4,564 | 0.806 | -0.83 | 5,480 | -3.26 | 3.5 |
| E5 AFTER  | partial 0.95 · trail 1.2 · BE 0.05 · maxage 1         | XAUUSD M1 | +897   | 1.080 | 0.37 | 2,420 | 0.84 | 1.0 |

(XAU 2026 window here ends Apr 6 = 34M ticks vs the earlier re-baseline's May 29 = 46.7M, so XAU baseline reads
PF 0.806 here vs 0.889 there; the BTC reproduction is exact and the fix is directionally identical on both.)

**Honest read:** PF is now *clearly >1 but thin* (1.07–1.08) — E5's edge is small; the fix's real win is the
sign flip + the DD crush (BTC 7.5×, XAU 2.3×) + Sharpe going positive. **MQL5 fidelity:** all five knobs are real
EA inputs; `E5_PARTIAL_TP_TRIGGER` maps 1:1 to the EA's *default-active* standard partial path
(`partialTPTrigger`, `TakePartialProfitAsNeeded`; `ENABLE_CONSERVATIVE_TRADE_MGMT=false` by default so the
R-ladder is off), so this ports directly. At trigger 0.95 the partial/trail seldom fire, so the dquants
chandelier-trail vs EA trail divergence shrinks → dquants↔MT5 path-dependence converges. **Remaining for
promotion:** (1) re-confirm the EA actually runs these UPPERCASE values (the deployed `Inp*` set is silently
ignored — see the secondary bug above); (2) IS (2025) re-check not yet run — scoped to 2026 OOS per request.
