# HANDOFF — read me first, update me last

_Last updated: 2026-06-16 by Claude (Opus 4.8). Branch `1-reorganize-code`._

## 🚨 TRUST CHECK (2026-06-16, latest) — user ran the 3 promoted EAs in MT5; all bad
User compiled & tested KK-Monster/MasterVP/KenKem in MT5 and called the results "trash / no profit."
**Correct.** Today's journal (`../kenkem/Tester/.../logs/20260616.log`): KK-KenKem XAU M1 = 1164 entries /
1 TP / 629 SL (~0%); KK-Monster XAU M1 = 2576 entries / 18% TP (over-fires); MasterVP BTC M3 = 12% TP,
XAU M1 = 0 trades. Full unspun scorecard: **`research/optimization/HONEST-AUDIT-2026-06-16.md`**.
**None of the 3 dquants ports is profit-validated. Only the user's ORIGINAL `KenKemExpert` (E1+E2, PF
1.62) works in MT5.** Compiling ≠ validating. Do not present engine PFs as deployable.

## 🧭 PIPELINE FIX IN PROGRESS (2026-06-16) — spec written, Monster fidelity next
User: pipeline isn't useless, the **validate→deploy** link is. Plan agreed: (1) spec ✅
`research/PIPELINE-CONTRACT.md` (engine rule: tick-only; config rule: Class-A only; VALIDATE gate =
manual-MT5 parity diff; DEPLOY gate = parity PASS + beats original KenKemExpert). (2) Fix engine
fidelity bugs — **MT5 stays MANUAL for now**. Target = **Monster**.
- **Stale diagnosis RETIRED:** deployed `KK-Monster/Engine.mqh::MonNearNet` = body-proxy net (port of
  C++ `tf_net_near_at`), NOT broker volume; it fired 2,576 entries today (not 0). The bug is now
  **economics**, not signal-firing: engine PF ~1.23 vs MT5 ~18% TP loss.
- **#1 lead (cost model) — RESOLVED as NOT the cause:** user is on **Exness Pro = COMMISSION-FREE**
  (web-verified 2026-06-16; cost is in the spread). Engine already models $0 commission + real spread
  from ticks, so **commission is NOT the Monster divergence.** Commission is now importable anyway
  (added key `CommissionPerLot`/`InpCommissionPerLot` → `apply_kv`, config.hpp:324; files
  `cpp_core/tools/commission_{xau,btc}_exness_pro.set` = 0.0, with Raw/Zero refs for account switching;
  import verified by /tmp test). **→ Pivot: the culprit is exit geometry or a spread mismatch between
  the engine's tick feed and MT5's modeled spread, NOT costs.**
- **Next build:** `research/validation/parity_diff.py` to make the manual MT5 run a real gate, then the
  first Monster trade-level engine-vs-MT5 diff to pinpoint exit-geometry vs spread.

## 🎯 Goal (user, restated 2026-06-16)
Make the **dquants tick engines reproduce MT5 "every tick" EXACTLY** so they can be trusted, then run
**reliable param sweeps** to rank production candidates. User's framing: *"my original EAs are profitable
but the C++-optimized configs lose in MT5"* — find & fix why, reproduce ≥ EA profitability. **Don't lie.**
Mode: autopilot, commit as you go, revert bad code.

## 🔑 ROOT CAUSE FOUND & FIXED THIS SESSION — systemic param contamination (all 3 strategies)
The dquants engines exposed `.set` keys that the EAs **HARDCODE** (not `input`s). MT5 silently ignores
them, so any sweep that moved one produced a config MT5 can't reproduce → it loses when deployed. **This is
exactly why the user's optimized configs failed in MT5.** Full audit: `research/kenkem_parity/PARAM_SURFACE_AUDIT.md`.

| Strategy | hardcoded keys exposed | contamination found | fix (committed) |
|---|---:|---|---|
| KenKem | 21 (ADX_LEN, RSI_LEN, ICHIMOKU_*, USE_CONVICTION_*, USE_HTF_VETO_*, USE_ICHIMOKU_*, sessions) | **51** best_*.set swept ADX_LEN; 51 swept RSI_LEN; parity sets too | `is_ea_locked_key()` refuses them (`82fb4b9`) |
| MasterVP | 12 | best_mastervp_*: InpAtrLen=11/15, InpVpBins=21/49, InpVaPct~75 | added `InpAtrLen` to `non_input_keys()` (`ece8f2b`) |
| Monster | 15 | best_monster_*: InpNodeDecay/NeutralBand/Saturation/TouchAtr | new `monster_non_input_keys()` refuses 15 (`ece8f2b`) |

Engines now **structurally cannot** honor an EA-hardcoded param (warn once + keep EA value). New tests:
`test_ea_locked_keys_ignored`, `test_monster_locked_keys_ignored`. **ALL C++ TESTS PASS.**

## 📍 Parity state after the fix (per strategy)
| Strategy | tick parity vs MT5 | evidence |
|---|---|---|
| **MasterVP** | ✅ validated (signal-exact); InpAtrLen leak now closed | [[mastervp-tick-engine-mt5-validated]] |
| **Monster** | 🟡 engine matches oracle; best-sets were contaminated, now lockable | re-run needed |
| **KenKem** | 🟡 **much closer**: RSI lock took XAU E5 **150→139 trades** (MT5 136), net +559/PF 1.10 (MT5 +995/1.23), verdict stays un-inverted, geometry mean\|Δ\|=0.03 | `cpp_trades_xau_locked.csv`, PARITY_RESULT_XAU.md |

## ⚠️ TWO things still block "100% identical" + "trustworthy sweeps"
1. **KenKem residuals** (refinements, NOT sign inversions): (a) ~3–6 min **entry lag** — M1 indicator
   micro-drift flips the strict `25>75>100>200` onset (worst at weekly-open bar seams, e.g. close max\|Δ\|=42
   at a Sun 22:09 bar — a real bar-construction seam to chase); (b) **exit geometry** — dquants closes via
   tight `SL-WIN` trail where MT5 closes via `EA`-managed exits → win% 77.7 vs 52, PF 1.10 vs 1.23.
2. **Sweeps ran on the BAR engine** (`optimize_kenkem.py` BIN=kenkem/backtester) which disagrees with MT5 on
   P&L sign ([[bar-engine-systemic-defect]]). Trustworthy sweeps MUST use the **tick engine**. The 51+4
   `best_*` sets are unreliable and must be **regenerated** by a clean tick-engine sweep over CLASS-B
   (honorable) params only. `optimize_kenkem.py` now strips locked keys from its search space (`6c4ad18`).

## ▶️ NEXT ACTIONS (in order)
1. **Re-validate MasterVP + Monster** on the tick engine with the cleaned engine (confirm no regression,
   confirm profitable, diff vs their MT5 oracles). Data: regenerate `bars_xauusd_2425_*.csv` +
   `ticks_xauusd_2425_window.csv` (see MASTERVP_MONSTER_PARITY.md repro).
2. **Build a tick-engine sweep harness** (replace bar-engine `optimize_kenkem.py` BIN, or new script) and
   regenerate the `best_*` candidates honestly. THEN produce the 9-col comparison table → top production pick.
3. **Close KenKem residuals**: chase the weekly-open M1 bar seam (tick→M1 bucketing across daily gaps) for
   the entry lag; reconcile the E5 exit path (SL-WIN vs EA-managed) for the win%/PF gap.
4. **ALL-ENTRIES**: C++ covers E1/E2/E4/E5 but NOT E3; traces are E5-only. Add E3; per-entry parity.

## 🔑 Key facts / gotchas
- Python: `~/miniforge3/envs/kenkem/bin/python` (NOT system python3, NOT `conda activate`).
- Use the **tick engine** (`cpp_core/build/kenkem/tick_backtester`, `cpp_core/build/backtester`,
  `cpp_core/build/monster_backtester`), NEVER the bar engine, for any P&L / parity claim.
- This shell is bash 3.2 (no `declare -A`); the kenkem env has bash 5. Some write-loops returned no output —
  use Edit or awk, not bash assoc-arrays.
- MT5 tester output: `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/<strategy>/`. XAU symbol = `XAUUSD-Exness-KK`.
- Adopt a toggle to a locked `.set` ONLY if **net↑ AND drawdown↓**; rank on 2026 OOS; report the 9-col table.

## 📚 Durable plan & memory
`docs/BUILD-PLAN.md` · `~/.claude/.../memory/MEMORY.md` · `research/kenkem_parity/` (PARAM_SURFACE_AUDIT.md =
the trust artifact; PARITY_RESULT_XAU.md; MASTERVP_MONSTER_PARITY.md; RUN_GUIDE_PARITY.md).
