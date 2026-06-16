# HANDOFF — read me first, update me last

_Last updated: 2026-06-16 by Claude (Opus 4.8). Branch `1-reorganize-code`._

## 🎯 Goal
Make the **dquants tick engines reproduce MT5 "every tick" EXACTLY** so they can be trusted, then run **reliable
param sweeps** to rank a production candidate that ≥ the user's profitable original `KenKemExpert`. User's framing:
*"my original EAs are profitable but the C++-optimized configs lose in MT5"* — find & fix why. **Don't lie** (every
PF names the engine+binary). Mode: autopilot, commit as you go, revert bad code.

## 🚨 Trust state — nothing is MT5-validated except the original
User ran KK-Monster/MasterVP/KenKem in MT5; all bad (journal `../kenkem/Tester/.../logs/20260616.log`: KenKem
1164 entries/1 TP, Monster over-fires 18% TP, MasterVP 12% TP / 0 trades). **Only the ORIGINAL `KenKemExpert`
(E1+E2, PF 1.62) works in MT5.** Unspun scorecard: `research/optimization/HONEST-AUDIT-2026-06-16.md`. Compiling ≠
validating — do not present engine PFs as deployable.

## 🔑 Root cause found & FIXED this session — systemic param contamination
The engines exposed `.set` keys the EAs **HARDCODE** (not `input`s). MT5 silently ignored them, so any sweep that
moved one produced a config MT5 can't reproduce → it lost when deployed. **This is exactly why the optimized configs
failed.** Audit: `research/kenkem_parity/PARAM_SURFACE_AUDIT.md`. Fix: engines now structurally refuse EA-locked
keys (`is_ea_locked_key` / `monster_non_input_keys`; warn once + keep EA value). New tests pass. Commits `82fb4b9`
(KenKem), `ece8f2b` (MasterVP+Monster), `6c4ad18` (sweep search-space strip).
**Consequence:** every existing `best_*.set` is untrusted (contaminated and/or bar-engine) → must be regenerated.

## 📍 Per-strategy parity state
| Strategy | tick parity vs MT5 | note |
|---|---|---|
| **MasterVP** | ✅ signal-exact ([[mastervp-tick-engine-mt5-validated]]) | re-verify `InpAtrLen` leak closure didn't move it |
| **Monster** | 🟡 fires (2,576 entries, not 0) but **economics** lose | culprit = exit geometry OR engine-vs-MT5 spread mismatch, NOT costs (Exness Pro = commission-free) |
| **KenKem** | 🟡 much closer, un-inverted | XAU E5 150→139 trades (MT5 136), net +559/PF 1.10 (MT5 +995/1.23); residuals = entry lag + exit geometry; C++ lacks E3 |

## ✅ This session (2026-06-16, Opus 4.8) — user chose "fix parity first, then sweep"
**Parity GATE BUILT: `research/validation/parity_diff.py` (commit `267f6d0`)** — the §4 trade-level
engine-vs-MT5 check. stdlib-only; window-aligns engine `trades_*.csv` vs MT5 `trades_mt5.csv`, greedy
nearest-time match within dir, reports count/entry/SL/exit/P&L deltas + PF, emits PASS/FAIL. Doc:
`research/validation/README_PARITY_GATE.md`. **Self-tested & validated** — it independently reproduced
the documented MasterVP ground truth (XAU 20/22, BTC 4/10 on the known-buggy `trades_cpp_ema.csv`).
**🔑 KEY FINDING — even MasterVP FAILS §4** (XAU net P&L Δ 13.3%, 3/20 exit-tag mismatches; BTC Δ 62%).
Dominant divergence in BOTH = **EXIT GEOMETRY**: engine closes via tight `SL-WIN/SL-LOSS` trail, MT5 EA
closes via managed `EA` session/news exits (XAU 2026-05-22/05-25 cluster). Matches the KenKem-E5 exit
root cause already on record. **Exit-path fidelity is THE blocker before any sweep is trustworthy.**

## ✅ MasterVP XAU M3 May-2026 — NEAR-COMPLETE PARITY ACHIEVED (config drift, not engine bug)
Root cause was **config drift**: baseline.set didn't pin two behavioral keys → engine & MT5 used different
DEFAULTS — `InpUseMtfAgree` (C++ true / MT5 false) and `InpMaxPeakDDPct` (C++ 22% / MT5 30%). Fixed both →
**81 of 83 trades matched** (from 56/51), net +125 vs −148 (≈1.3% residual = tick-level fill timing).
- EA fix (committed-pending in kenkem KKMasterVPv1): `Core/Indicators.mqh` computes HTF EMA from M3 IN-EA
  (`BuildHtfEmaIfNeeded`/`HtfEmaAtBuf`), recompiled (0/0); validated `[HTF] built 2401 PERIOD_M15 buckets`.
- Preset created: MT5 `Presets/KK-MasterVP-MTFon-xau.set` (baseline + MTF on + peak-DD via EA default 30 + exports).
- C++ side: trades_cpp_mtfON_p30.csv (peak-DD pinned 30). Evidence: `RUN_2026-05_xau_m3/parity_diff_mtfON_p30.txt`,
  `FINDINGS.md` (SOLVED section), `mt5_ref/trades_mt5_mtfON.csv` + `parity_mt5_mtfON.csv` (per-bar now exported).
- **✅ DONE — keys pinned (2026-06-16):** added the 13 C++-read-AND-EA-input keys missing from baseline.set
  (incl. `InpUseMtfAgree=true`, `InpMaxPeakDDPct=22` [true EA default — the 30 was a stale tester value]).
  Verified: pinned baseline reproduces the original 77-trade C++ run IDENTICALLY (pinning is non-destructive).
  The 39 EA-locked Pm*/Stp*/Net* keys are correctly refused by C++ / not MT5 inputs → not a drift risk.
  Regenerated MT5 preset `Presets/KK-MasterVP-MTFon-xau.set` from the fully-pinned baseline (pins peak-DD=22
  + MTF on + exports) so the tester cannot drift. baseline.set edit is UNCOMMITTED in kenkem (KKMasterVPv1).
- **NEXT:** (1) OPTIONAL final confirm: re-run MT5 with the regenerated preset (peak-DD now 22, not stale 30)
  → both sides halt at 22 → expect even tighter parity (~77 vs 77) than the 81/83@30 run; (2) re-test the
  config-drift lesson on KenKem/Monster (likely same unpinned-key mismatches); (3) THEN trustworthy sweeps.

## 🗄️ (superseded) earlier same-session diagnosis — MasterVP parity DIFF → QUALITY GATE
First true trade-level diff complete. Full writeup: `research/validation/mt5_parity_runs/RUN_2026-05_xau_m3/FINDINGS.md`.
- **Verdict FAIL:** MT5 105 tr / −$1552 / PF 0.759 vs C++ 77 tr / −$372 / PF 0.928. 56 matched, 16
  engine-only, 51 MT5-only.
- **🔑 ROOT CAUSE (overturns exit-geometry hypothesis):** matched trades are parity-CLEAN (0/56 exit-tag
  mismatch; entry/SL/exit mechanics port faithfully). The divergence is **which trades fire**. Of the 51
  MT5-only trades, **42 (82%) my engine blocks on `quality (MTF/RSI)`**; MT5's MasterVP run has ZERO
  quality-gate blocks. Both sides have the gate ON with identical params (MtfAgree/HardVeto/MomVeto all
  true, EMA 24/194, HTF M15, RSI 14/50) → the gate's **COMPUTATION** diverges, not its config.
- Prime suspect: **C++ M15 HTF-EMA build** (`tick_engine.hpp build_htf_m15_`, bucket-M3→last-close then
  ema 24/194) vs MT5 native `iMA(M15,…)` — likely EMA-194 seeding/series mismatch flips htf_bull/bear for
  long stretches. Secondary: RSI(14) near midline (label lumps both). daily-DD/cooldown skips are cascade.
- Evidence files in RUN dir: `parity_diff_report.txt`, `cpp_gate_log.txt` (C++ per-bar BLOCK reasons via
  `KKVP_DBG_FROM/TO` env), `mt5_ref/trades_mt5.csv`, `cpp_out/trades_cpp.csv`, `logs/tester_20260616.log`.
- Added `--symbol-xau` to `parity_driver.cpp` (uncommitted, unbuilt — build was declined; use the tick
  `backtester` gate-log path instead, which is what produced the diagnosis).
- **✅ RESOLVED — it's the MT5 TESTER, not a C++ bug.** Split the C++ quality label → all 42 are MTF (zero
  RSI). MT5 journal logs 22 RSI vetoes but ZERO MTF vetoes ⇒ EA guard `if(hf>0&&hs>0)` ⇒ `iMA(M15,194)`
  never warms up in the tester ⇒ **MTF higher-TF filter is silently DISABLED for the whole backtest.**
  Independent M15-EMA-from-ticks blocks 42/42 (= C++) ⇒ C++ M15 EMA is CORRECT; MT5 isn't running it. So
  the **tester runs a more permissive strategy than deploys live** (live has M15 history). Replicating
  inert-MTF in C++ (`InpUseMtfAgree=false`): matched 56→65, engine-only 16→2, P&L Δ 91%→70%; residual 42
  now block on **peak DD halt (36)** = equity-path breaker cascade (2nd-order). Per-trade mechanics faithful.
- **DECISION: user chose (B) fix the EA to be faithful to live.** IMPLEMENTED: `KK-MasterVP/Core/Indicators.mqh`
  now computes the HTF EMA from base-TF (M3) closes IN-EA (`BuildHtfEmaIfNeeded`/`HtfEmaAtBuf`), mirroring
  the C++ `build_htf_m15_` byte-for-byte (HTF close = last base-TF close in bucket; EMA seed = first value,
  α=2/(n+1); closed bars only). Replaces the iMA(M15) handles that never warmed in the tester. **Compiles
  0 errors / 0 warnings; .ex5 rebuilt.** Change is UNCOMMITTED in kenkem (branch KKMasterVPv1, parallel work
  — left for user to review/commit). C++-side: quality label split (`tick_engine.hpp`, committed `5bb8b92`).
- **⚠️ CORRECTION (the "iMA warmup" theory was an over-reach):** the MT5 tester input echo shows
  `InpUseMtfAgree=false` in EVERY run (incl. the original 105-trade one). The real divergence = a plain
  **config mismatch**: MT5 tester ran MTF **off**, C++ ran MTF **on** (baseline.set doesn't pin the key →
  C++ default true; MT5 tester remembered its own false). That's why every re-run was identical and no
  `[HTF]` line printed (the `if(InpUseMtfAgree)` branch is never entered). My EA from-M3 HTF change is still
  a valid robustness improvement (and needed IF iMA-warmup is also real), but it's dormant until MTF is on.
- **FIX:** created explicit preset `kenkem/MQL5/Presets/KK-MasterVP-parity-xau.set` pinning
  `InpUseMtfAgree=true`, `InpMtfHardVeto=true`, `InpUseMomVeto=true`, `InpExportParity=true`,
  `InpExportTradeJournal=true` (so the tester can't silently fall back to a stale input).
- **⏳ PENDING USER RE-RUN:** Strategy Tester → Inputs → **Load** `KK-MasterVP-parity-xau.set` (must LOAD it,
  not just re-run — tester remembers inputs), same XAU M3 / every-tick / 2026.05.01→05.29 / deposit 10000.
  Expect: a `[HTF] built …` line in the journal, MTF vetoes to appear, trade count to drop 105→~77 toward
  the C++ MTF-on run. Hand back new `trades_*.csv` (+ `parity_*.csv` now that export is on).
- **THEN (me):** `parity_diff.py --engine cpp_core/tools/trades_cpp_xau_may2026.csv (=trades_cpp.csv, MTF on)
  --mt5 <new>` → expect convergence. Residual will be the peak-DD-halt equity-path cascade (2nd-order) to
  chase next via bar-synced state.

## ▶️ Next actions (full detail in `docs/BUILD-PLAN.md` → LIVE WORK L1–L4)
1. **L3a (NOW the critical path)** Reconcile the engine **exit path** with the EA-managed exits
   (tight-trail vs `EA` session/news/managed close) until MasterVP XAU+BTC **PASS** `parity_diff.py`.
   This is the same exit-geometry bug seen on KenKem-E5 → fix once, benefits all three.
2. **L3b** Then run the §4 loop on **Monster** (recent OOS): engine export + manual MT5 + `parity_diff.py`
   → first real Monster trade-level diff. Cost is ruled out (Exness Pro commission-free); expect exit/spread.
3. **L1** Re-validate MasterVP + Monster on the cleaned tick engine (regen data, confirm profitable).
4. **L2** Build a **tick-engine** sweep harness (bar engine flips P&L sign — [[bar-engine-systemic-defect]]);
   sweep **Class-A params only**; accept a config only if it PASSes parity AND beats `KenKemExpert` (PF 1.62)
   on recent OOS + survives Monte Carlo → 9-col table → production pick.
5. **L4** Close KenKem residuals: weekly-open M1 bar-seam (entry lag), E5 exit path, add E3.

Deferred (premature until L1–L4): C1–C8 backlog in BUILD-PLAN — top of that group is **C2: KenKem has ZERO drawdown
breakers (safety gap)**.

## 🔑 Key facts / gotchas
- Python: `~/miniforge3/envs/kenkem/bin/python` (NOT system python3, NOT `conda activate`).
- **Always use the tick engine** (`cpp_core/build/kenkem/tick_backtester`, `.../backtester`, `.../monster_backtester`),
  NEVER the bar engine, for any P&L / parity claim. Every PF must name its binary (PIPELINE-CONTRACT §2).
- This shell is bash 3.2 (no `declare -A`); kenkem env has bash 5. Use Edit/awk, not bash assoc-arrays.
- MT5 tester output: `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/<strategy>/`. XAU symbol = `XAUUSD-Exness-KK`.
- Adopt a toggle into a locked `.set` ONLY if **net↑ AND drawdown↓**; rank on 2026 OOS; report the 9-col table.
- Do NOT recreate `kenkem/MQL5/Experts/KK-MasterVP-Monster/` — it exists/evolved on `origin/KKMasterVPv1`; ship `.set` only.

## 📚 Durable references
`docs/BUILD-PLAN.md` (live) · `docs/BUILD_PLAN_ARCHIVED.md` (done) · `research/PIPELINE-CONTRACT.md` (the 4-stage
gate) · `research/kenkem_parity/` (PARAM_SURFACE_AUDIT.md = trust artifact; PARITY_RESULT_XAU.md;
MASTERVP_MONSTER_PARITY.md; RUN_GUIDE_PARITY.md) · `~/.claude/.../memory/MEMORY.md`.
