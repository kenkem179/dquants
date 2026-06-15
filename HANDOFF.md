# HANDOFF — read me first, update me last

_Last updated: 2026-06-16 by Claude (Opus 4.8). Branch `1-reorganize-code`._

## 🎯 Goal (user, restated 2026-06-15)
Make the **dquants tick backtest engines reproduce MT5 "Every tick based on real ticks" exactly** so the
engine can be trusted for parameter sweeps. **CRITICAL scope clarification:** ALL entry types **E1–E5**
must act identically across the original MQL5 EA and the dquants C++ engine — not just one entry.

## 📍 Where we are (per strategy)
| Strategy | Tick-engine parity vs MT5 | Notes |
|---|---|---|
| **MasterVP** | ✅ Validated (signal-exact; misses = MT5 iATR tick-jitter on a knife-edge gate) | Trustworthy for sweeps now |
| **Monster** | ✅ Zero-trade bug fixed (`*100` unit fix), engine matches oracle | |
| **KenKem** | 🔴 C++ inverts verdict (C++ PF 0.90 vs MT5 1.23, XAU/E5). Gap narrowed 394→218 vs MT5 136 | E5 only so far; E3 missing in C++ |

## ✅ What just changed this session (commits)
- **dquants `a4fe28a`** — Corrected a MIS-diagnosis: the "daily-DD predictive-vs-reactive parity bug"
  is NOT a bug. MT5 `IsDailyDDHit(ComputeRiskBudgetUSD())` is predictive too (RiskManager.mqh:142-147),
  byte-identical to `kk::common::risk_manager::is_daily_dd_hit`. **Do NOT flip it** — would break parity.
  The only real MasterVP/Monster divergence is the broker `tick_value≈0.1` glitch. See
  `research/kenkem_parity/MASTERVP_MONSTER_PARITY.md`.
- **kenkem `bbc3301`** — Built the EA-side **per-bar E5 decision trace**: `Parity/BarTrace.mqh` +
  `Entry5::TraceBar()` + 4 hooks in `KenKemExpert.mq5`. Emits the identical 61-col schema as the C++
  `cpp_core/tools/kenkem/trace_dumper`. Behind `InpExportBarTrace` (default off). **Compiles clean.**
- **dquants (uncommitted as of writing)** — added `InpExportBarTrace=true` to `parity_kenkem_{xau,btc}.set`;
  added RUN A / RUN B sections to `research/kenkem_parity/RUN_GUIDE_PARITY.md`; this HANDOFF.md +
  CLAUDE.md handoff mandate.

## ✅ RUN A DONE + ROOT CAUSE FIXED (2026-06-16) — ADX_LEN mismatch; verdict UN-INVERTED
MT5 oracle 136 trades (`mt5_trades_xau_runA.csv`); per-bar trace `mt5_trace_xau_runA.csv`. Diff tools:
`diff_kenkem_trades.py` + new `diff_kenkem_trace.py`. Full writeup: `PARITY_RESULT_XAU.md` iter 4-5.
- **THE BUG:** parity set had `ADX_LEN=9`; C++ applied it (ADX(9)) but the EA hardcodes `int ADX_LEN=14`
  (NOT an input) so MT5 always ran ADX(14). ADX(9)>ADX(14) → ~7.8 ADX drift → over-fire + verdict inversion.
- **FIX = `ADX_LEN=14` in `parity_kenkem_{xau,btc}.set` (+ presets).** Result: ADX drift 7.8→~0.1-2.0;
  trades 218→**150** (MT5 136); **PF 0.90 (losing) → 1.106 (winning)**, MT5 1.23. Verdict no longer inverted.
- Also fixed a stale committed trace (was 82,112 rows missing Apr 28-30/May 16; fresh = 87,844 = MT5).
- **⚠️ SYSTEMIC: dquants exposes params (ADX_LEN…) the EA HARDCODES.** Any sweep that moved them made
  EA-unhonorable configs → the prior "distilled" PF numbers used a different ADX than the EA. MUST audit:
  every C++ tunable → a real EA `input`. This is central to "trust the engine."
- **Residual (smaller):** ~3-min entry lag (M1 EMA micro-drift ~0.16 flips strict alignment onset) +
  adx_m1 2.06 / M1 DI-RSI / weekly-open (Sun 22:00) EMA-close seams (close max|Δ|42 @ 05-11 22:09).

## ⛔ STILL BLOCKED ON USER — RUN B (clean MasterVP/Monster reference)
`RUN_GUIDE_PARITY.md` → RUN B. Correctly-configured XAU symbol (sane lots, no blow-up), replaces the
broker-glitched "2426-Good" oracle. Lower priority than the KenKem indicator fix below.

## ▶️ NEXT ACTIONS (in order) — no user needed for #1-#2
1. **AUDIT THE PARAM SURFACE (systemic, highest trust-value).** ADX_LEN proved dquants exposes tunables the
   EA hardcodes. Cross-check EVERY `kk::kenkem` config key (kenkem_config.hpp `apply_key`) against the EA: is
   there a matching `input`? If the EA hardcodes it (like ADX_LEN), the C++ must LOCK to the EA's value and it
   must NOT be swept. Produce a table {C++ key → EA input? → value} and fix the locked `.set`s + best_* sets.
   (RSI_LEN, the ATR periods, sideways thresholds, HTF mins are prime suspects.)
2. **Close the residual M1 drift** (after #1): the ~3-min entry lag is M1 EMA micro-drift flipping the strict
   onset; investigate the M1 bar high/low vs MT5 bid bars + the weekly-open (Sun 22:00) seam. To verify bars
   directly, fix the EA `TraceBar` high/low to shift-1 (currently shift-0, cosmetic) and add tick_count, then
   one more RUN A gives MT5's true M1 OHLC to diff. Also fix EA trace `adxS/diPS/diMS` to emit the iADX(9)
   short handle (currently emits the 14-period cache → false 7.8 drift on those 3 cols only).
3. **(needs RUN B, optional)** Clean MasterVP/Monster reference — LOW priority (MasterVP already validated;
   see answer to user 2026-06-16: RUN B is largely redundant, only a clean Monster-XAU confirmation remains).
4. **ALL-ENTRIES (user's real goal):** C++ covers **E1/E2/E4/E5 but NOT E3**; traces are E5-only. Add E3;
   generalize both traces to per-entry columns; parity-diff each. The #1 param audit + ADX fix help ALL entries.

## 🔑 Key facts / gotchas
- Python: use `~/miniforge3/envs/kenkem/bin/python` (NOT system python3, NOT `conda activate`).
- Compile MQL5 here: `bash scripts/compile_mql5.sh <abs path to .mq5>` (wine64 + MetaEditor).
- MT5 tester output: `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/<strategy>/`. Symbol is
  `XAUUSD-Exness-KK`, not plain XAUUSD. Confirm export inputs show `true` in the tester log.
- Adopt a toggle to a locked `.set` ONLY if **net↑ AND drawdown↓**; rank on 2026 OOS; report the 9-col table.
- Use the **tick engine**, never the bar engine, for any P&L claim (bar engine disagrees on sign).

## 📚 Durable plan & memory
`docs/BUILD-PLAN.md` (phase plan, keep ticking) · `~/.claude/.../memory/MEMORY.md` (cross-session facts) ·
`research/kenkem_parity/` (PARITY_RESULT_XAU.md, MASTERVP_MONSTER_PARITY.md, RUN_GUIDE_PARITY.md).
