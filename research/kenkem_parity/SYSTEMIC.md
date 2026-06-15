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
