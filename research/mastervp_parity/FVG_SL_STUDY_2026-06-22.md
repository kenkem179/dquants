# FVG-anchored stop-loss study — does "SL beyond the FVG" add edge? (2026-06-22)

**User idea (Desktop/testcases 1-6, before/after charts):** place the stop just BEYOND the recent
significant Fair Value Gap (3-bar imbalance) that sits beyond VAL/VAH, to "ensure successful breakout
trades." User note: *"This idea works even before considering doing mean reversion for local VP only"*
(i.e. FVG-SL is an independent lever from the reversion-local-VP assumption).

**TL;DR — Tested honestly in the concurrency-correct engine, FVG-anchored SL does NOT add edge on the
existing breakout book of any target.** The hand-picked chart examples are a survivorship view: across
ALL breakout trades, re-anchoring the stop beyond the FVG behaves like a blanket *wider* stop — it
trades TRAIN PF for OOS drawdown (the exact curve-fit pattern the secondary VP sweep already flagged),
and it cannot rescue an entry that has no edge (BTC-M3). Entry-gating on FVG presence (`InpFvgRequire`)
is the strongest form of the idea and showed a tempting single-split XAU OOS jump — **but per-month
walk-forward killed it: OFF wins on total dollars and the gate guts the best month. NOT ported.** See
the REQ + Walk-forward sections below.

## What was built (engine, default OFF = base byte-identical)
`kk::apply_fvg_sl` (`cpp_core/include/kk/mastervp/fvg_sl.hpp`), wired in `tick_engine.hpp` before the
struct-TP block. Re-anchors a breakout stop to the nearest significant 3-bar FVG between entry and the
value edge, recomputing risk + TP1/TP2 with the detector's RR (risk-based sizing auto-scales the lot).
- LONG (broke up thru VAH): bullish gap `low[k] > high[k-2]`; SL = `high[k-2] − buf` (support below).
- SHORT (broke down thru VAL): bearish gap `high[k] < low[k-2]`; SL = `low[k-2] + buf` (resistance above).
- `fvg_beyond_va`: gap must sit in breakout territory (LONG gap-bottom ≥ VAH; SHORT gap-top ≤ VAL).
- Modes: 0 replace / 1 widen-only / 2 tighten-only. Guards: `fvg_min_atr` (significance),
  `fvg_min/max_risk_atr` (clamp), `fvg_lookback`, `fvg_breakout_only`. `fvg_require` = entry-gate.
- Keys: `InpEnableFvgSl InpFvgMode InpFvgBeyondVa InpFvgMinAtr InpFvgBufAtr InpFvgMinRiskAtr
  InpFvgMaxRiskAtr InpFvgLookback InpFvgBreakoutOnly InpFvgRequire`. `make test` green (+4 FVG tests).
- Harness: `vp_length_sweep_2026-06-22.py --fvg [TARGET]` (FVG_ONLY=substr to filter).

## Stop-relocation grid (no entry gate) — `_fvg_sweep.out`

### XAU M3 (lock OFF: TRAIN 1.258/+20518/dd28.6 · OOS 1.320/+5583/dd11.5)
| config | TRAIN PF/net/dd | OOS PF/net/dd |
|---|---|---|
| **OFF (lock)** | **1.258 / +20518 / 28.6** | **1.320 / +5583 / 11.5** |
| rep bVA min.25 cap1.5 | 1.209 / +15954 / 27.0 | 1.287 / +4906 / 12.4 |
| rep bVA min.25 cap2.5 | 1.221 / +19746 / 24.2 | 1.253 / +4173 / 13.4 |
| rep VA min.25 cap2.5 | 1.232 / +18491 / 17.0 | 1.122 / +1888 / 18.3 |
| wdn bVA min.25 cap3.0 | 1.190 / +15123 / 32.1 | 1.306 / +5020 / 12.7 |
| wdn VA min.25 cap3.0 | 1.147 / +9153 / 24.4 | 1.304 / +4719 / 9.9 |
| wdn VA min.25 cap2.0 buf.05 | 1.264 / +20822 / 25.0 | 1.257 / +4484 / 12.8 |
| tgt VA min.25 flr.5 | 1.277 / +22820 / 22.5 | 1.224 / +3715 / 12.9 |
**No config beats OFF on both windows.** Widen-beyond-VA improves OOS dd (→9.9%) but craters TRAIN PF
(1.258→1.147) — pure train-for-OOS, the curve-fit trap. OFF stays.

### BTC M3 (NO LOCK — dead: OFF TRAIN 0.748/−7185 · OOS 0.828/−7206)
| config | TRAIN PF/net/dd | OOS PF/net/dd |
|---|---|---|
| OFF | 0.748 / −7185 / 72.3 | 0.828 / −7206 / 82.6 |
| rep VA min.25 cap2.5 | 0.803 / −5776 / 61.3 | 0.820 / −7199 / 77.3 |
| wdn VA min.25 cap3.0 | 0.789 / −5730 / 63.2 | **0.891 / −4896 / 64.0** |
| wdn VA min.25 cap2.0 buf.05 | 0.793 / −6001 / 60.9 | 0.859 / −6230 / 76.2 |
**Still net-negative everywhere.** Best (wdn VA cap3.0) cuts OOS loss −7206→−4896 and dd 82.6→64.0% —
real risk reduction, but PF stays < 1. A stop fix can't make a sub-1.0 entry edge profitable. BTC-M3
breakout is a *mechanism* problem.

### BTC M5 (lock OFF: TRAIN 1.150/+1940/dd13.6 · OOS 1.263/+5530/dd14.7)
| config | TRAIN PF/net/dd | OOS PF/net/dd |
|---|---|---|
| **OFF (lock)** | **1.150 / +1940 / 13.6** | **1.263 / +5530 / 14.7** |
| rep bVA min.25 cap2.5 | 0.943 / −772 / 19.6 | 1.207 / +5138 / 23.1 |
| wdn bVA min.25 cap3.0 | 1.157 / +2000 / 13.7 | 1.266 / +5531 / 14.6 |
| wdn VA min.25 cap2.0 buf.05 | 1.150 / +1940 / 13.6 | 1.263 / +5530 / 14.7 |
**Widen-only ≈ neutral** (+0.003 PF = noise; the tight-cap widen never triggered → byte-identical to
OFF). Replace modes hurt badly (TRAIN < 1). No edge added.

## REQ — FVG-required entry gate (`_fvg_require.out`)
The gate DROPS any breakout that has no qualifying structural FVG to hide behind (test the FVG as an
entry FILTER, the user's "ensure successful breakouts" framing). Paired with a sane widen/replace stop.

### XAU M3 (lock OFF: TRAIN 1.258/+20518/dd28.6 · OOS 1.320/+5583/dd11.5)
| config | TRAIN PF/net/dd/n | OOS PF/net/dd/n |
|---|---|---|
| **OFF (lock)** | **1.258 / +20518 / 28.6 / 1304** | **1.320 / +5583 / 11.5 / 356** |
| REQ wdn bVA min.25 cap3.0 | 1.158 / +7316 / 23.7 / 1005 | 1.234 / +2627 / 13.4 / 256 |
| REQ wdn VA min.25 cap3.0 | 1.188 / +10133 / 19.7 / 1157 | **1.402 / +5780 / 9.1 / 306** |
| REQ rep bVA min.25 cap2.5 | 1.191 / +11076 / 20.8 / 1055 | 1.289 / +3485 / 15.0 / 270 |
| REQ rep VA min.50 cap2.5 | 1.191 / +10604 / 21.8 / 1116 | **1.504 / +6863 / 10.7 / 286** |

### BTC M3 (NO LOCK — dead)
| config | TRAIN PF/net/dd | OOS PF/net/dd |
|---|---|---|
| OFF | 0.748 / −7185 / 72.3 | 0.828 / −7206 / 82.6 |
| REQ wdn bVA min.25 cap3.0 | 0.765 / −5932 / 63.2 | 0.909 / −3908 / 55.0 |
| REQ wdn VA min.25 cap3.0 | 0.789 / −5731 / 59.0 | 0.897 / −4506 / 63.6 |
Still net-negative everywhere; bleed roughly halved (OOS −7206→−3908, dd 82.6→55%) but no edge to gate.

### BTC M5 (lock OFF: TRAIN 1.150/+1940/dd13.6 · OOS 1.263/+5530/dd14.7)
| config | TRAIN PF/net/dd | OOS PF/net/dd |
|---|---|---|
| OFF | 1.150 / +1940 / 13.6 | 1.263 / +5530 / 14.7 |
| REQ wdn bVA min.25 cap3.0 | **1.344 / +3483 / 8.6** | 1.066 / +1006 / 21.8 |
| REQ rep VA min.50 cap2.5 | 1.215 / +3009 / 13.5 | 1.090 / +1623 / 20.5 |
**The gate REVERSES direction vs XAU** — it helps TRAIN (1.150→1.344) but *hurts* OOS (1.263→1.066).

### Why the XAU OOS uptick is suspect (not yet lockable)
The REQ gate's striking XAU OOS jump (1.320→1.504) is undercut by two tells of regime-dependence, not edge:
1. **It strips XAU TRAIN winners:** TRAIN net halves (+20518→+10604) on only a 14% trade cut → the
   dropped trades were the big 2025 winners. The same filter dropped *losers* in 2026 OOS. Same rule,
   opposite trade-quality by period = the filter rides the regime, it doesn't identify quality.
2. **It reverses on BTC-M5** (+train/−OOS) — a transferable structural edge would point the same way.
→ This is exactly the single-window uptick CLAUDE.md says needs walk-forward before any lock.

## Walk-forward (XAU-M3, per-month) — `_fvg_wf.out` — **VERDICT: NOT a real edge**
11 monthly folds across the full 2025.06→2026.04 XAU range, OFF vs the two best REQ gates.

| month | OFF PF/net/n | REQ_rep_VA min.50 cap2.5 | REQ_wdn_VA min.25 cap3.0 |
|---|---|---|---|
| 2025.06 | 1.38 / +666 / 42 | 1.23 / +384 | 1.14 / +220 |
| 2025.07 | 0.96 / −432 / 172 | **0.63 / −2653** | 0.84 / −1217 |
| 2025.08 | 1.11 / +790 / 161 | 1.39 / +2069 | 1.01 / +32 |
| 2025.09 | 1.37 / +3729 / 182 | 1.21 / +1469 | 1.04 / +235 |
| 2025.10 | 1.07 / +1164 / 204 | 1.01 / +136 | 1.15 / +1365 |
| 2025.11 | 0.56 / −5149 / 163 | 0.77 / −1940 | 0.84 / −1209 |
| 2025.12 | 1.37 / +3147 / 186 | 1.19 / +1263 | 1.18 / +1088 |
| 2026.01 | 2.16 / **+16603** / 194 | 2.16 / +9875 | 2.11 / +9619 |
| 2026.02 | 1.07 / +580 / 167 | 1.18 / +1218 | 1.17 / +1197 |
| 2026.03 | 1.54 / +4820 / 185 | 1.76 / +5286 | 1.62 / +4486 |
| 2026.04 | 2.20 / +184 / 4 | 999 / +359 / 3 | 1.63 / +97 |
| **Σ net** | **+26,102** | **+17,466** | **+15,901** |
| PF-folds-beat-OFF | — | 6/11 ("ROBUST") | 4/11 (NOT robust) |

**The 6/11 "ROBUST" label is an artifact of counting PF-per-fold, and it collapses the moment you look
at dollars or at the decisive months:**
1. **OFF wins on net by ~$8.6k** over the identical period (+26,102 vs +17,466). The gate's PF "wins"
   land in low-volume, low-net months (2025.08, 2026.02/03); OFF wins where the money is.
2. **It guts the single most important fold:** 2026.01, OFF +16,603 vs REQ +9,875 — the gate threw away
   $6.7k of the best month's edge. That one fold dwarfs every PF "win" combined.
3. **It is not even a reliable loss-reducer:** in 2025.07 (a down month) the gate made it *worse*
   (−432 → −2,653); it only softened the 2025.11 drawdown. Inconsistent sign = regime, not skill.
4. The earlier single-split OOS jump (1.320→1.504) was the 2026.01–04 tail flattering the ratio while
   the gate quietly bled net dollars — exactly the survivorship illusion the chart examples create.

→ **FVG-as-entry-gate does NOT add a transferable edge on XAU-M3.** Keep OFF. Do not lock, do not port.

## Conclusions — FINAL (WF-confirmed)
1. **FVG-SL stop relocation is tested-inert-to-marginal** — where it "helps" (XAU widen-VA OOS dd) it's
   just a wider stop trading away TRAIN PF, not new information.
2. **FVG-as-entry-gate is NOT a real edge.** The eye-catching single-split XAU OOS jump (1.320→1.504)
   did NOT survive per-month walk-forward: OFF wins on total net by ~$8.6k, the gate guts the best
   month (2026.01, −$6.7k), and its sign is regime-dependent (worsened 2025.07, reversed on BTC-M5).
   The "6/11 folds" was a PF-ratio artifact on low-net months. **Keep OFF.**
3. **BTC-M3 cannot be rescued** by stop OR gate — the entry has no edge; FVG only bleeds less.
4. Lesson matches [[vmc-momentum-module-result]]: a visually-compelling idea from selected examples must
   be validated on the FULL book in the concurrency-correct engine + WF, never post-hoc on winners. The
   chart "before/after" examples were survivorship — across the full book the gate costs more than it saves.
5. Feature kept **default OFF** opt-in infra; **NOT ported to MQL5** (WF failed → no overfitting-gate run
   needed). The engine code stays as a reusable, tested lever should a future regime-aware use emerge.
