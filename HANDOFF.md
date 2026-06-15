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

## ✅ RUN A DONE (2026-06-16) — diagnosed: KenKem divergence = INDICATOR DRIFT, not gate logic
MT5 oracle 136 trades (`mt5_trades_xau_runA.csv`); per-bar trace `mt5_trace_xau_runA.csv`. Diff tool
`cpp_core/tools/kenkem/diff_kenkem_trace.py`. Full writeup: `PARITY_RESULT_XAU.md` iteration 4.
- Aligned-trade geometry near-perfect (entry Δ0.02, risk Δ0.16). The whole gap = which minute fires + extra longs.
- **The E5 gate logic MATCHES; the indicator inputs DRIFT.** Pervasive, systematic: C++ ADX runs ~7.8 higher
  than MT5 on EVERY TF (mid-session, not just seams); DI/RSI off too. EMA micro-drift (~0.22) flips the strict
  `25>75>100>200` onset → 2-6 min entry lag + spurious longs. Plus rare day-seam bars where C++ reads a wrong
  bar (05-01 00:00: close 3318.75 vs 3272.02, 46 pts).

## ⛔ STILL BLOCKED ON USER — RUN B (clean MasterVP/Monster reference)
`RUN_GUIDE_PARITY.md` → RUN B. Correctly-configured XAU symbol (sane lots, no blow-up), replaces the
broker-glitched "2426-Good" oracle. Lower priority than the KenKem indicator fix below.

## ▶️ NEXT ACTIONS (in order) — no user needed for #1
1. **FIX KENKEM C++ INDICATORS (dominant root cause, do now).**
   a. **ADX/DI/RSI parity** — C++ multi-TF (M1→M3/M5/M15 aggregated) ADX/DI/RSI ≠ MT5 iADX/iRSI; C++ runs
      systematically higher. MasterVP's single-TF ADX matched MT5 to rounding, so port that validated path
      + the iADX-as-EMA smoothing fix (same family as `atr_mt5_mode`) into `kk::kenkem`'s aggregated ADX.
      Re-run RUN A's trace diff until adx mean|Δ| → ~rounding.
   b. **Day-seam bar construction** — fix the wrong/offset M1 bar at some 00:00 boundaries (tick→M1 bucketing
      + HTF aggregation across daily gaps).
   c. Re-diff the trace, then the trades; expect the 136-vs-218 + lag to collapse once indicators match.
2. **(needs RUN B)** Re-diff MasterVP/Monster with `diff_aligned.py`; add one-position-at-a-time concurrency to monster.
3. **ALL-ENTRIES generalization (user's real goal):** C++ covers **E1/E2/E4/E5 but NOT E3**; both traces are
   E5-only. Add E3 to C++; generalize the trace (C++ `trace_dumper` + EA `BarTrace`/`TraceBar`) to per-entry
   columns for E1/E2/E3/E4; parity-diff each. NOTE: the indicator fix in #1 benefits ALL entries at once.

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
