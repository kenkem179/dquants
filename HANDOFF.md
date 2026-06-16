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

## 🔍 Config-drift audit DONE (2026-06-16) — `research/kenkem_parity/CONFIG_DRIFT_AUDIT_KENKEM_MONSTER.md`
Re-ran the MasterVP unpinned-key lesson on KenKem + Monster (2 parallel agents, findings verified by hand).
- **Monster = ✅ CLEAN.** Every genuine EA-input key C++ reads has C++ default == EA default → unpinned keys
  agree by construction. 0 drift keys (`InpUseMtfAgree` absent; `InpMaxPeakDDPct` 0==0). **One minor lock-set
  gap:** 2 EA-hardcoded plain vars (`InpBrkRrLookbackBars`=25, `InpMaxTradesPerSession`=50) are read by
  `apply_kv` but missing from `monster_non_input_keys()` → add them (safe now, low urgency).
- **KenKem = ⚠️ CONFIRMED divergence + target-EA mismatch.** TWO EAs run in MT5: original
  `KenKem\KenKemExpert.ex5` (ADX/RSI hardcoded 14) vs the **current** `dquants\KK-KenKem\KK-KenKem.ex5`
  (most recent runs, 2026-06-16). In KK-KenKem, ADX/RSI len are **genuine inputs** (`KK-Common/KenKem/Inputs.mqh:54`)
  and MT5 ran **ADX=15 / RSI=11**. The C++ engine models KenKemExpert → **locks** ADX_LEN/RSI_LEN to 14 and
  parity sets strip them ("EA hardcodes to 14" — true for KenKemExpert, FALSE for KK-KenKem). So pinning won't
  fix it; the lock must be revisited. Also flagged (verify): latest XAU `KK-KenKem.set` may carry BTC-tuned
  values (wrong-file load, not drift).
- **✅ RESOLVED (user, 2026-06-16, CORRECTED — supersedes the first call): two EAs, two ROLES.**
  `KenKemExpert.ex5` = baseline-to-beat (PF 1.62, hardcoded). `dquants\KK-KenKem.ex5` = the **parameterized
  Layer-4 deploy vehicle** (same E1/E2/E4/E5 logic, ADX/RSI/EMA/RR are genuine inputs) → **this is what we
  tune & ship.** ⟹ re-point the C++ engine at KK-KenKem: **UN-LOCK** ADX/RSI/EMA, pin them in the parity
  `.set`, validate parity vs a **KK-KenKem** run. The lock was only right for the hardcoded original.
  Goal pipeline: (1) baseline-equivalence (KK-KenKem@orig-config ≈ KenKemExpert PF 1.62) + engine↔KK-KenKem
  parity; (2) sweep KK-KenKem's real inputs in C++ (costed/OOS/MC); (3) promote any config that beats PF 1.62
  → KK-KenKem `.set` → demo.

### 🔬 engine↔KK-KenKem scoping DONE (2026-06-16) — they diverged; a strategic fork
- **Aligned:** same entries E1/E2/E4/E5 (neither has E3); triggers + SL/TP math identical. KK-KenKem.mq5
  header self-describes as "faithful transcription of the dquants kk::kenkem engine."
- **Diverged (the crux):** the **C++ engine is STRICTLY MORE SELECTIVE.** Its `entry_gate_ok`
  (`cpp_core/include/kk/kenkem/entries.hpp:116-167`) applies trend-quality(0-11)/conviction/RSI-div-veto/
  ATR-percentile filters that KK-KenKem's `GateOk` (`KK-Common/KenKem/Engine.mqh:213-238`) **dropped**.
  Same params => different trades. Also: C++ `apply_kv` reads ORIGINAL `KenKemExpert` key names, NOT `Inp*`
  (needs a name-translation layer); per-entry `e*_rr_sideway` vs KK-KenKem's single `InpRrSidewayAll`;
  different exit/position manager.
- **Reality:** KK-KenKem LOSES. Today's MT5 runs blew up (BTC->$48, XAU -73%, E5-only config); its own best
  self-reported OOS = PF 1.145 BTC / 1.132 XAU — both < the **PF 1.63** original baseline (captured:
  `kenkem/MQL5/Profiles/Tester/v17620ReportTester-227922402.html`, XAU M1, +$2456, 260 tr).
- **KEY INSIGHT:** KK-KenKem looks **over-distilled** — it deleted the engine's selectivity gates (likely the
  edge). The real fork: **(A)** dumb the engine down to KK-KenKem (disable gates -> parity -> sweep), vs
  **(B, recommended)** keep the gated engine as the research asset, verify it's competitive on recent OOS in
  C++ (no MT5 needed), then **add the gate params as inputs to the KK-KenKem EA** so the EA inherits the edge.
- **✅ USER CHOSE PATH B.** Gated-engine OOS measured (tick engine; full table in
  `research/kenkem_parity/PATHB_GATED_ENGINE_OOS.md`): **E5-only = PF 1.143 in BOTH 2025 Feb–May AND 2026
  Jan–May** (stable real edge, but = KK-KenKem's own ~1.13 ceiling). **E2 loses both periods; E1 regime-
  dependent** (+709 2025 / −792 2026) → at engine-default params, adding E1+E2 HURTS (PF→0.938 in 2026).
  ⟹ engine does NOT yet beat PF 1.63 — but comparison is unfair on two counts.
- **✅ LIKE-FOR-LIKE DONE — the gap is EXITS, not gates/entries.** Exported the baseline's exact window
  (Sep 1–Nov 15 2025) from parquet → `cpp_core/tools/{ticks,bars}_xauusd_2025_sepnov*.csv` and ran the tick
  engine: E1+E2+E5 gated = **250 trades / PF 1.082 / +$1,245** vs the original's **260 trades / PF 1.63 /
  +$2,456**. Near-identical trade count + ALL entries positive (E1 +302, E2 +385, E5 +557) ⟹ **entries &
  gates are faithful; the engine just earns half per trade via its tight native trail vs the original's
  managed/laddered exits.** Re-confirms [[kenkem-e5-root-cause-exits]] / [[parity-gate-built]] from a fresh angle.
- **NEXT ACTION:** port the original `KenKemExpert`'s managed exit geometry (TP-ladder/partials/trail/
  profit-protection hardcoded params) into the C++ engine `trade_manager.hpp`; re-run the Sep–Nov 2025
  like-for-like; watch PF climb toward 1.63. THEN the engine is a faithful, better base to sweep + promote
  into KK-KenKem. E5 core (PF ~1.14 across 3 windows) can ship as a first KK-KenKem candidate in parallel.
  Full evidence: `research/kenkem_parity/PATHB_GATED_ENGINE_OOS.md`.

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

## ✅ This session (2026-06-16, Opus 4.8) — C++⇄EA PARITY LEDGER built + first fidelity fixes
User reframed the priority: **C++→EA fidelity (zero surprises, not even tiny) ABOVE chasing baseline PF.**
Did a full line-by-line read of the kk::kenkem engine (truth) vs the **deployed KK-KenKem EA**
(`kenkem/.../KK-Common/KenKem/{Engine,Inputs}.mqh`; the `.mq5` is an 18-line include shim).
- **🔑 KEY FINDING — the EA header LIES.** `Engine.mqh:4` calls itself a "faithful transcription of the
  kk::kenkem engine," but it is the *distilled subset*. The engine is a strict SUPERSET: the EA dropped
  the **valid-session entry gate** (engine trades only UTC JP/LN/NY; EA trades 24h), the **ATR-percentile
  floor + ATR-high block**, the **full 0–11 trend-quality min / conviction / RSI-divergence** entry
  filters, the **fast-ADX panic** + **score-drop** exits, **session-end close**, and all **portfolio/DD
  guards**. Same params ⇒ EA over-fires ⇒ this is *why KK-KenKem over-trades & lost/blew up in MT5.*
- **NEW canonical artifact: `research/kenkem_parity/CPP_EA_PARITY_LEDGER.md`** — every divergence with
  file:line on BOTH sides, severity (F formula / P port / M broker-modelable / I irreducible), and the
  exact reconciliation. This is the zero-surprise contract; close every (F)/(P) row → engine PF predicts MT5 PF.
- **Fixed NOW (C++ side, headless-testable, committed):** **C1** `manage_tick` partial slice now floors to
  the broker volume step + requires ≥min_lot (byte-equal to EA `MathFloor(q/step)*step; q>=mn`), latching
  `partial_done` even on a sub-min slice; **C2** modeled broker `stops_level_price` (default 0 ⇒ inert for
  Exness; faithful for nonzero-stops brokers) on BE/trail SL moves. `test_kenkem_trade_manager.cpp` +3
  tests (30 checks). Full `make test` green.
- **Reconciliation direction = Path B (bring EA UP to engine), already user-endorsed.** Each row adds an EA
  `input` defaulting OFF (so all-OFF == today's EA), then flips ON; each needs ONE MT5 run + `parity_diff.py`.
- **✅ STEP 1 DONE — SESSIONS (ledger A1+B2) ported into KK-KenKem, compiles 0/0** (UNCOMMITTED in kenkem
  `KKMasterVPv1`, left for user review — branch has parallel uncommitted MasterVP work; KK-KenKem edits are
  separate files). New `InpUseSessionFilter` (default false = unchanged 24h), `InSession()` byte-mirrors
  `engine.hpp in_valid_session`, session-end flatten mirrors `per_bar_exits_`, entry gated in `TryEnter`.
  **⏳ NEEDS USER MT5 RUN to validate:** load current KK-KenKem `.set`, set `InpUseSessionFilter=true` +
  `InpSessionGmtOffset` to the broker→UTC offset, run XAU M1 OOS → trade count should drop toward the
  engine's session-gated count → `parity_diff.py` vs engine export should converge. THEN move to step 2
  (quality suite A4–A7). Ledger = `research/kenkem_parity/CPP_EA_PARITY_LEDGER.md`.

## ▶️ Next actions (full detail in `docs/BUILD-PLAN.md` → LIVE WORK L1–L4)
0. **L4-parity (NEW critical path):** execute the ledger reconciliation in order — (1) sessions A1+B2,
   (2) quality suite A4–A7, (3) ATR regime A2+A3, (4) panic/score-drop B3+B4, (5) guards D3 (+D4/D5 after
   the engine grows DD breakers, BUILD-PLAN C2), (6) sizing E2. Port each into KK-KenKem `Engine.mqh`/
   `Inputs.mqh` default-OFF, then validate vs the engine export with `parity_diff.py`. **Cannot self-test
   MQL5 here — each step needs a user MT5 run.** Ledger = `research/kenkem_parity/CPP_EA_PARITY_LEDGER.md`.
1. **L3a** Reconcile the engine **exit path** with the EA-managed exits (tight-trail vs `EA` session/news/
   managed close) until MasterVP XAU+BTC **PASS** `parity_diff.py`. Same exit-geometry family as KenKem;
   note KenKem's manage_tick↔EA `Manage()` are now byte-equal after C1/C2 (only MasterVP `TradeManager.mqh`
   uses a *different* ATR-distance trail — audit that one next).
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
