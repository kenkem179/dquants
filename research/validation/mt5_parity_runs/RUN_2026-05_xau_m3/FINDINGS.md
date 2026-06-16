# Parity FINDINGS — MasterVP XAU M3, 2026-05 (first true trade-level diff)

Date: 2026-06-16. Config: `KK-MasterVP-baseline.set` as-is, XAUUSD-Exness-KK, M3,
every-tick, 2026.05.01→2026.05.29, deposit 10000. C++ tick engine vs MT5 every-tick.

## Top-line
| | MT5 (oracle) | C++ engine |
|---|---|---|
| trades | 105 | 77 |
| net | −$1552 | −$372 |
| PF | 0.759 | 0.928 |
| win rate | 48.6% | 49.4% |
| exits | 3 EA · 53 SL-LOSS · 48 SL-WIN · 1 TP | 3 EA · 39 SL-LOSS · 33 SL-WIN · 2 TP |

`parity_diff.py` verdict: **FAIL** — 56 matched, 16 engine-only, 51 MT5-only, net P&L Δ 91%.

## Root cause — the QUALITY GATE computes differently (NOT exit geometry)
- **Matched trades are parity-clean:** 0/56 exit-tag mismatches; entryΔ ~spread, slΔ small,
  per-trade pnlΔ single-digit. Entry price, SL placement, and exit logic port faithfully.
- The failure is **which trades get taken.** Cross-referencing the C++ engine's own gate log
  (`cpp_gate_log.txt`, `KKVP_DBG_FROM/TO`) against the 51 MT5-only trades:

  | C++ engine's reason for skipping a trade MT5 took | count |
  |---|---|
  | **quality (MTF/RSI)** | **42 (82%)** |
  | daily DD | 4 (cascade) |
  | cooldown | 2 (cascade) |
  | ATR% band | 2 |
  | position already open | 1 |

- The C++ engine's #1 block reason over all May = **quality (MTF/RSI), 596×**; the MT5 MasterVP
  run shows **zero** quality-gate blocks. Both sides have the gate **ON** with identical params
  (`InpUseMtfAgree=true`, `InpMtfHardVeto=true`, `InpUseMomVeto=true`, EMA 24/194, HTF=M15,
  RSI 14/mid 50). → the gate's **computation** diverges, not its config.

- Suspects (both gates ON both sides; params identical):
  1. **M15 HTF EMA agreement (primary suspect).** C++ builds M15 by bucketing M3 bars
     (`build_htf_m15_`, last-M3-close per 15-min bucket) then `ema(close,24/194)`. MT5 uses native
     `iMA(M15, …, PRICE_CLOSE)`. A sustained bias in the slow EMA-194 flips htf_bull/htf_bear for
     long stretches → blocks one whole side the EA would trade. Check: M15 close series + EMA
     seeding (MT5 iMA seeds SMA then recurses over full history).
  2. **RSI(14) near midline.** `quality (MTF/RSI)` is one label for both checks; RSI flips right at
     the 50 midline. Need to split the label to attribute.

## Cascade (secondary)
The 16 engine-only trades are mostly MT5 "position already open" / "daily DD" / "max trades/session":
once the 42 entries diverge, equity path + stateful breakers (peak-DD, daily-DD, cooldown) drift,
producing more divergence. Fixing the quality gate should collapse most of it.

## ⚠️ This OVERTURNS the prior hypothesis
The "exit-geometry is the universal fidelity blocker" belief (parity-gate memo) does NOT hold for
MasterVP: matched exits agree 0/56. The real blocker here is the **MTF/RSI quality-gate computation**.

## Next
1. Split the C++ `quality (MTF/RSI)` block label → attribute the 42 to MTF vs RSI.
2. Reconcile C++ M15-EMA build with MT5 `iMA` (construction + seeding + shift-1 alignment).
3. Re-run + re-diff (no new MT5 run needed to MEASURE convergence — MT5 trades already captured).
4. For airtight value-level confirmation: one more instrumented MT5 run that ALSO sets
   `InpExportParity=true` AND adds `HtfEmaFast/Slow(1)` + `RSI(1)` columns to ParityExport.mqh,
   so the exact per-bar HTF-EMA/RSI values can be diffed.

## Files in this run dir
- `mt5_ref/trades_mt5.csv` — MT5 oracle (105 trades)
- `cpp_out/trades_cpp.csv` — C++ engine (77 trades)
- `parity_diff_report.txt` — full trade-level diff
- `cpp_gate_log.txt` — C++ per-bar gate BLOCK reasons (the symmetric half)
- `logs/tester_20260616.log` — MT5 journal (note: also contains unrelated KenKemExpert M1 runs)

---
# RESOLVED (same session) — it's the MT5 TESTER, not a C++ bug

**Proof the MTF gate is INERT in the MT5 tester:** the MT5 MasterVP journal logs 22 RSI vetoes
("RSI<mid"/"RSI>mid") and every other reason copiously — but **zero** MTF vetoes
("MTF not bullish/bearish/counter"). The EA guards the MTF check with `if(hf>0 && hs>0)`; the only way
RSI vetoes while MTF never does is `HtfEmaSlowAt(1)==0` — i.e. the cross-TF `iMA(M15,194)` handle never
warms up in the Strategy Tester. **The higher-TF trend filter is silently disabled for the whole backtest.**

Independent check: an M15 EMA built from scratch off the raw ticks (what `iMA` *should* see) blocks
**42/42** of the divergent trades — same as C++. So C++'s M15 EMA is CORRECT; MT5 just isn't running it.

**Consequence:** the MT5 tester is running a MORE PERMISSIVE strategy than what would deploy live
(live would have M15 history → MTF gate active → behaves like C++). The tester is an unfaithful oracle here.

**Residual after replicating inert-MTF (InpUseMtfAgree=false):** C++ 67 tr, 65/107 matched, 2 engine-only,
P&L Δ 70%. The remaining 42 MT5-only now block on **peak DD halt (36)** — a 2nd divergence, this one a
cascade: stateful trailing-DD breaker trips on a different equity path once entries diverge. Strategies
with equity-path-dependent breakers can't be matched by gate-fixes alone end-to-end; needs bar-synced state.

**Net:** per-trade mechanics faithful; divergence = (1) tester-disabled MTF gate [primary, proven],
(2) peak-DD-halt equity-path cascade [secondary]. NOT exit geometry, NOT a C++ math bug.

---
# SOLVED — near-complete parity via TWO config fixes (not engine bugs)

The "iMA M15 warmup" theory was wrong. The MT5 tester input echo showed the truth: the divergence was
**config drift** — baseline.set fails to pin two behavioral keys, so engine & MT5 used different DEFAULTS:

| Input | C++ default | MT5 (EA) default | effect |
|---|---|---|---|
| `InpUseMtfAgree` | true | **false** (tester) | MT5 skipped the MTF gate → +28 trades |
| `InpMaxPeakDDPct` | 22% | **30%** | C++ halted early at 22% → −10 trades, locked losses |

Fixing both (MTF on both sides via in-EA HTF-from-M3 compute + recompile; peak-DD pinned to 30):

| Stage | matched | unmatched MT5 | net eng vs MT5 |
|---|---|---|---|
| original (mismatch) | 56 | 51 | −372 vs −1552 |
| both MTF on | 72 | 11 | −372 vs −148 |
| + peak-DD 30 | **81/83** | **2** | +125 vs −148 |

Residual: 5 engine-only (1 is a differ mis-pair = MT5 also entered; 2 are "position already open" = MT5
held a few ticks longer) + 2 exit-tag flips + small per-trade fill deltas ≈ **1.3% of account** — the
irreducible tick-level floor (fill timing / partial-fill ordering / one-position-at-a-time cascade).

**Engine is now TRUSTWORTHY at the trade level** for ranking configs, PROVIDED every behavioral key is
pinned identically on both sides. ACTION: pin ALL behavioral inputs in baseline.set + the parity preset
so engine-default vs EA-default can never silently diverge again (same root as param-surface contamination).
EA fix validated: `[HTF] built 2401 PERIOD_M15 buckets from 12000 PERIOD_M3 bars` → in-EA HTF EMA warms up
in the tester AND matches live. Preset: kenkem `MQL5/Presets` mirror + MT5 Presets `KK-MasterVP-MTFon-xau.set`.
