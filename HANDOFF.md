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
