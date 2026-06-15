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
4. Re-baseline KenKem/MasterVP/Monster on the tick engine (all prior bar-engine numbers are suspect).
